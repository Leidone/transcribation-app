import AppKit
import AudioCapture
import Foundation
import Localization

/// Looking after a running recording: it should not outlive the call, and it should not fill the disk.
extension AppModel {
    private static let watchInterval: Duration = .seconds(5)

    /// Refuses to start on a nearly full disk, and warns when a long call may not fit.
    func hasRoomToRecord() -> Bool {
        guard let budget = currentDiskBudget() else { return true }
        switch budget.level {
        case .critical:
            report(tr("На диске осталось меньше 300 МБ — запись не начата. Освободите место и попробуйте снова.", "Less than 300 MB is left on the disk — the recording did not start. Free some space and try again."))
            return false
        case .low:
            diskWarning = Self.lowSpaceText(budget)
        case .fine:
            diskWarning = nil
        }
        return true
    }

    /// Checks every few seconds whether the call has ended and whether the disk is running out.
    func watchRecording(of app: SourceApp) -> Task<Void, Never> {
        Task { [weak self] in
            var watch = CallEndWatch()
            var hasReminded = false
            var hasToldAboutSilence = false
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.watchInterval)
                guard let self, self.isRecording, !Task.isCancelled else { return }
                if await self.stopIfDiskIsFull() { return }
                // Nothing is heard on pause by design; the checks carry on once the recording does.
                if self.isPaused { continue }
                guard let silence = await self.recorder.silence() else { continue }
                var problems = SoundCheck.problems(
                    elapsed: self.recordedTime(),
                    othersSilentFor: silence.others, meSilentFor: silence.me,
                    meIsMuted: await self.recorder.microphoneIsMuted()
                )
                // In a room there is no app to hear from; only the microphone matters.
                if app.isInPerson { problems.remove(.othersNotHeard) }
                self.soundWarning = Self.soundWarningText(problems, appName: app.name)
                if problems.contains(.othersNotHeard), !hasToldAboutSilence {
                    hasToldAboutSilence = true
                    self.onOthersNotHeard?(app.name)
                }

                let reading = CallEndWatch.Reading(
                    appIsRunning: app.isInPerson
                        || !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty,
                    appUsesMicrophone: app.isInPerson ? nil : MicrophoneUse.isActive(for: app.bundleID),
                    othersSilentFor: silence.others,
                    meSilentFor: silence.me
                )
                guard let ending = watch.ending(after: reading, at: .now) else { continue }
                // A closed app sends nothing more, so that recording always stops.
                if ending == .appQuit || self.preferences.stopsWhenCallEnds {
                    await self.stopRecording()
                    self.onCallEnded?(ending, app.name, true)
                    return
                }
                if !hasReminded {
                    hasReminded = true
                    self.onCallEnded?(ending, app.name, false)
                }
            }
        }
    }

    /// Returns `true` when the recording had to be stopped.
    private func stopIfDiskIsFull() async -> Bool {
        guard let budget = currentDiskBudget() else { return false }
        switch budget.level {
        case .fine:
            diskWarning = nil
        case .low:
            diskWarning = Self.lowSpaceText(budget)
        case .critical:
            await stopRecording()
            report(tr("Запись остановлена и сохранена: на диске почти не осталось места.", "The recording was stopped and saved: the disk is almost full."))
            return true
        }
        return false
    }

    private func currentDiskBudget() -> DiskBudget? {
        DiskBudget.availableBytes(at: Self.recordingsDirectory).map(DiskBudget.init(availableBytes:))
    }

    /// One line for the recorder screen, or `nil` when both sides have been heard.
    static func soundWarningText(_ problems: Set<SoundCheck.Problem>, appName: String) -> String? {
        let lines = [
            problems.contains(.othersNotHeard)
                ? tr("Из \(appName) пока не слышно ни звука — проверьте, что выбрано нужное приложение.",
                     "Not a sound from \(appName) yet — check that the right app is chosen.")
                : nil,
            problems.contains(.meMuted)
                ? tr("Микрофон выключен: приходит полная тишина. Проверьте кнопку на наушниках, микрофон в звонке и в системе.",
                     "The microphone is muted: only silence comes in. Check the headset button, the call app and the system.")
                : nil,
            problems.contains(.meNotHeard)
                ? tr("Микрофон пока ничего не слышит — проверьте, не выключен ли он в системе.",
                     "The microphone hears nothing yet — check that it is not muted in the system.")
                : nil,
        ].compactMap { $0 }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    static func lowSpaceText(_ budget: DiskBudget) -> String {
        let minutes = budget.minutesLeft
        let time = minutes < 60
            ? tr("\(minutes) мин", "\(minutes) min")
            : tr("\(minutes / 60) ч \(minutes % 60) мин", "\(minutes / 60) h \(minutes % 60) min")
        return tr("Мало места на диске: хватит примерно на \(time) записи", "The disk is filling up: room for about \(time) of recording")
    }
}
