import CallLibrary
import SwiftUI
import Transcription
import UniformTypeIdentifiers

/// The app's main screen: recordings with search, a record button, import, and the AI settings. A split view, so
/// on iPad the list and the open recording sit side by side; on iPhone it collapses to a single stack.
struct RecordingListView: View {
    @Bindable var model: AppModel
    @Environment(AppPreferences.self) private var preferences
    @State private var showsImporter = false
    @State private var showsSettings = false
    @State private var showsRecorder = false
    @State private var pendingDelete: RecordingItem?

    var body: some View {
        NavigationSplitView {
            ZStack {
                AmbientBackground()
                list
            }
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.searchText, prompt: "Поиск по записям")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsSettings = true
                    } label: {
                        Label("ИИ и настройки", systemImage: "sparkles")
                    }
                    .buttonStyle(.glass)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsImporter = true
                    } label: {
                        Label("Импортировать", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.glass)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    showsRecorder = true
                } label: {
                    Label("Новая запись", systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding()
            }
        } detail: {
            if let item = model.selectedRecording {
                NavigationStack {
                    RecordingDetailView(model: model, item: item)
                }
                .id(item.id)
            } else {
                ZStack {
                    AmbientBackground()
                    ContentUnavailableView("Выберите запись", systemImage: "waveform", description: Text("Расшифровка, итоги и задачи появятся здесь."))
                }
            }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task { await model.importAudio(urls) }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showsRecorder, onDismiss: { Task { await model.reload() } }) {
            RecordView()
        }
        .sheet(isPresented: onboardingIsPresented) {
            OnboardingView(model: model) { showsSettings = true }
                .interactiveDismissDisabled()
        }
        .alert("Не получилось", isPresented: errorIsPresented) {
            Button("Понятно", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert(
            "Удалить «\(pendingDelete?.title ?? "")»?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("Удалить", role: .destructive) {
                if let id = pendingDelete?.id { model.delete(id) }
                pendingDelete = nil
            }
            Button("Отмена", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Аудио и расшифровка удалятся без возможности восстановить — на iPhone нет Корзины для приложений.")
        }
        .task { await model.reload() }
    }

    private var list: some View {
        List(selection: $model.selectedID) {
            Section {
                GradientTitle(text: "Ваши созвоны")
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            if model.visibleRecordings.isEmpty, !model.searchText.isEmpty {
                Text("Ничего не нашлось. Поиск идёт по названиям, именам, итогам, задачам и расшифровкам.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(Array(model.visibleRecordings.enumerated()), id: \.element.id) { index, item in
                RecordingRow(
                    item: item, stage: model.processingStages[item.id],
                    hit: LibrarySearch.hits(in: item, query: model.searchText, limit: 1).first
                )
                .tag(item.id)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing) {
                    if !item.isSample {
                        Button(role: .destructive) { pendingDelete = item } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
                .staggeredAppear(index)
            }
        }
        .scrollContentBackground(.hidden)
        .animation(Motion.smooth, value: model.visibleRecordings.map(\.id))
    }

    private var onboardingIsPresented: Binding<Bool> {
        Binding(get: { !preferences.hasCompletedOnboarding }, set: { if !$0 { preferences.hasCompletedOnboarding = true } })
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.dismissError() } })
    }
}

private struct RecordingRow: View {
    let item: RecordingItem
    let stage: PipelineStage?
    let hit: SearchHit?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.headline)
                Text("\(item.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(item.duration.clockString)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let hit, hit.place != .title {
                    Text(hit.snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            badge
        }
        .glassCard(cornerRadius: 18, padding: 14)
        .contentShape(.rect)
    }

    @ViewBuilder
    private var badge: some View {
        if item.isSample {
            Text("Пример")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: .capsule)
        } else if stage != nil {
            ProgressView()
        } else {
            switch item.status {
            case .awaitingProcessing: Image(systemName: "hourglass").foregroundStyle(.secondary)
            case .transcribed: Image(systemName: "text.bubble").foregroundStyle(.secondary)
            case .ready: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }
}
