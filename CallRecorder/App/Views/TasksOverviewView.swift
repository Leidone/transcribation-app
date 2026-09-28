import CallLibrary
import Localization
import SwiftUI

/// Every task from every meeting: what is still open, grouped by the meeting it was agreed in.
struct TasksOverviewView: View {
    @Bindable var model: AppModel
    @AppStorage("tasks.showsDone") private var showsDone = false
    @AppStorage("tasks.mineOnly") private var mineOnly = false

    private var groups: [TaskGroup] {
        TaskOverview.groups(in: model.recordings, filter: showsDone ? .all : .open, mineOnly: mineOnly)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                    .staggeredAppear(0)
                filters
                    .staggeredAppear(1)
                if groups.isEmpty {
                    emptyState
                        .staggeredAppear(2)
                } else {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        TaskGroupCard(model: model, group: group)
                            .staggeredAppear(min(index + 2, 8))
                    }
                }
            }
            .padding(36)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .animation(Motion.smooth, value: groups.map(\.id))
        .animation(Motion.smooth, value: groups.flatMap(\.tasks).map(\.isDone))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("Все задачи", "All tasks"))
                .font(.system(size: 34, weight: .semibold))
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }

    private var subtitle: String {
        let open = TaskOverview.openCount(in: model.recordings)
        guard open > 0 else { return tr("Открытых задач нет", "No open tasks") }
        return tr("Открыто: ", "Open: ") + plural(open, "задача", "задачи", "задач", "task", "tasks")
            + tr(" из всех встреч", " across all meetings")
    }

    private var filters: some View {
        HStack(spacing: 14) {
            GlassTabBar(
                tabs: [(false, tr("Открытые", "Open")), (true, tr("Все", "All"))],
                selection: $showsDone
            )
            Toggle(tr("Только мои", "Only mine"), isOn: $mineOnly)
                .toggleStyle(.switch)
                .help(tr(
                    "Задачи, где исполнитель — вы («Я» или имя, которое вы дали своему голосу)",
                    "Tasks whose owner is you (“Me” or the name you gave your own voice)"
                ))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text(showsDone || mineOnly
                ? tr("Под этот фильтр задач нет.", "No tasks match this filter.")
                : tr("Все задачи выполнены. Новые появятся после итогов следующей встречи.",
                     "Everything is done. New tasks appear with the next meeting's summary."))
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 26)
    }
}

/// One meeting's tasks; the title opens the meeting, a task's time opens it at the moment it was agreed.
private struct TaskGroupCard: View {
    @Bindable var model: AppModel
    let group: TaskGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                model.open(group.recording.id)
            } label: {
                HStack(spacing: 12) {
                    AppIconView(bundleID: group.recording.appBundleID, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.recording.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(group.recording.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(PressableStyle())
            .help(tr("Открыть встречу", "Open the meeting"))

            ForEach(group.tasks) { task in
                TaskRow(
                    task: task, displayName: group.recording.displayName,
                    onToggle: {
                        withAnimation(.smooth) { model.toggleTask(task.id, in: group.recording.id) }
                    },
                    onSeek: group.recording.audio == nil && !group.recording.isSample ? nil : { time in
                        model.open(group.recording.id, at: time)
                    },
                    onRemind: { Task { await model.addToReminders([task], from: group.recording) } }
                )
            }
        }
        .padding(.bottom, 4)
    }
}
