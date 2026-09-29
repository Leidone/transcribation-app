import AppKit
import AudioCapture
import CallLibrary
import Localization
import SwiftUI

/// One set of animation curves for the whole app, so every movement has the same feel.
enum Motion {
    /// Content that changes: tabs, cards, screens.
    static let smooth = Animation.smooth(duration: 0.5)
    /// Small state changes: selection, hover, toggles.
    static let quick = Animation.snappy(duration: 0.28)
    /// Things that arrive on screen: a gentle spring.
    static let arrive = Animation.spring(duration: 0.65, bounce: 0.16)
    /// Slow ambient motion (a floating icon, a drifting gradient), played once: a motion that never stops keeps the
    /// window redrawing many times a second for as long as the screen is open.
    static let ambient = Animation.easeInOut(duration: 3)
}

/// Fades, lifts and un-blurs a view into place, one after another when given rising indexes.
struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 18)
            .blur(radius: isVisible || reduceMotion ? 0 : 6)
            .onAppear {
                withAnimation(reduceMotion ? nil : Motion.arrive.delay(Double(index) * 0.07)) { isVisible = true }
            }
    }
}

/// A slight shrink while pressed, like the controls on apple.com.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// A pill-shaped tab bar on glass whose highlight glides from one tab to the next.
struct GlassTabBar<Tab: Hashable>: View {
    let tabs: [(tab: Tab, title: String)]
    @Binding var selection: Tab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.tab) { item in
                Button {
                    withAnimation(Motion.quick) { selection = item.tab }
                } label: {
                    Text(item.title)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .foregroundStyle(selection == item.tab ? Color.primary : Color.secondary)
                        .contentTransition(.opacity)
                }
                .buttonStyle(.plain)
                .background {
                    if selection == item.tab {
                        Capsule()
                            .fill(Color.primary.opacity(0.14))
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }
}

/// A large title whose gradient drifts slowly, as in the hero sections of apple.com.
struct GradientTitle: View {
    let text: String
    var size: CGFloat = 44
    @State private var drifted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .tracking(-0.6)
            .multilineTextAlignment(.center)
            .lineLimit(2, reservesSpace: true)
            .foregroundStyle(LinearGradient(
                colors: [Color.primary, Color.indigo, Color.blue],
                startPoint: drifted ? .topLeading : .leading,
                endPoint: drifted ? .bottomTrailing : .trailing
            ))
            .onAppear {
                guard !reduceMotion else { return }
                // Started a moment after appearing: a repeating animation begun in the same update as the view's
                // own layout would repeat that layout too (a sheet's content kept sliding back and forth).
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    withAnimation(Motion.ambient) { drifted = true }
                }
            }
    }
}

extension View {
    func staggeredAppear(_ index: Int = 0) -> some View {
        modifier(StaggeredAppear(index: index))
    }
}

enum Theme {
    static let cardRadius: CGFloat = 24
    private static let speakerColors: [Color] = [.orange, .green, .pink, .purple, .teal, .indigo]

    /// The same name always gets the same colour (a stable hash; `hashValue` changes on every launch).
    static func speakerColor(_ name: String, isMe: Bool) -> Color {
        if isMe { return .accentColor }
        var hash: UInt32 = 5381
        for byte in name.utf8 { hash = hash &* 33 &+ UInt32(byte) }
        return speakerColors[Int(hash % UInt32(speakerColors.count))]
    }
}

extension View {
    /// A rounded Liquid Glass surface for grouped content.
    func glassCard(cornerRadius: CGFloat = Theme.cardRadius, padding: CGFloat = 22) -> some View {
        self.padding(padding)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

/// Soft colour field behind the glass, so the material has something to refract.
struct AmbientBackground: View {
    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.55, 0.45], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
            colors: [
                .indigo.opacity(0.35), .blue.opacity(0.18), .purple.opacity(0.25),
                .teal.opacity(0.15), .clear, .pink.opacity(0.15),
                .blue.opacity(0.20), .purple.opacity(0.12), .indigo.opacity(0.25),
            ]
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
    }
}

struct AppIconView: View {
    let bundleID: String?
    var size: CGFloat = 28

    var body: some View {
        if bundleID == SourceApp.inPersonBundleID {
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: size * 0.7))
                .foregroundStyle(.tint)
                .frame(width: size, height: size)
        } else if let icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: size * 0.8))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }

    private var icon: NSImage? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Chooser for the app whose audio is recorded, shared by the window and the menu bar panel.
struct AppPicker: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(bundleID: model.selectedBundleID, size: 26)
            Picker(tr("Приложение", "App"), selection: $model.selectedBundleID) {
                ForEach(model.apps, id: \.bundleID) { app in
                    Text(app.name).tag(Optional(app.bundleID))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(model.isRecording || model.isBusy)

            Button {
                model.refreshApps()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(tr("Обновить список приложений", "Refresh the list of apps"))
        }
    }
}
