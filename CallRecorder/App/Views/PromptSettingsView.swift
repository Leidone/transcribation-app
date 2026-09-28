import CallLibrary
import CodexClient
import Localization
import SwiftUI

/// The internal prompt the AI is given, and the settings that decide how many tokens a summary costs.
struct PromptSettingsView: View {
    @Environment(CodexAccountModel.self) private var account

    var body: some View {
        @Bindable var settings = account.settings

        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Внутренний промпт", "Internal prompt"))
                    .font(.title2.weight(.semibold))
                Text(tr("Так ИИ получает задачу. Короткий текст и низкие затраты на рассуждение экономят токены; результат остаётся тем же.", "This is how the AI gets its task. Short text and little reasoning save tokens; the result stays the same."))
                    .foregroundStyle(.secondary)
            }
            .staggeredAppear(0)

            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $settings.prompt.instructions)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(height: 190)
                HStack {
                    Text(tr(
                        "≈ \(TokenEstimate.of(settings.prompt.instructions)) токенов в инструкции",
                        "≈ \(TokenEstimate.of(settings.prompt.instructions)) tokens in the instructions"
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(Motion.quick, value: TokenEstimate.of(settings.prompt.instructions))
                    Spacer()
                    Button(tr("Вернуть по умолчанию", "Restore the default")) {
                        withAnimation(Motion.smooth) { settings.resetPrompt() }
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .disabled(settings.prompt == .standard)
                }
            }
            .glassCard(cornerRadius: 20, padding: 16)
            .staggeredAppear(1)

            tuningCard(settings: settings)
                .staggeredAppear(2)

            usageCard
                .staggeredAppear(3)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
        .animation(Motion.smooth, value: settings.prompt.replacesAgentPrompt)
        .animation(Motion.smooth, value: settings.provider.kind)
    }

    /// Codex-only knobs; Claude takes the instructions as its system prompt and has nothing else to tune.
    @ViewBuilder
    private func tuningCard(settings: AISettings) -> some View {
        @Bindable var settings = settings

        if settings.provider.kind == .anthropic {
            Text(tr("Claude получает эти инструкции как системный промпт и отвечает через один инструмент со строгой схемой, поэтому лишних токенов почти нет. Глубина рассуждений здесь не используется.", "Claude gets these instructions as its system prompt and answers through one tool with a strict schema, so almost no tokens are wasted. Reasoning depth is not used here."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 20, padding: 18)
                .transition(.blurReplace)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $settings.prompt.replacesAgentPrompt) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Заменять системный промпт Codex", "Replace Codex's system prompt"))
                            .font(.headline)
                        Text(tr("Убирает встроенные инструкции агента и лишний контекст (окружение, права, приложения). Самая большая экономия.", "Drops the agent's built-in instructions and extra context (environment, permissions, apps). The biggest saving."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("Глубина рассуждений", "Reasoning depth"))
                        .font(.headline)
                    GlassTabBar(
                        tabs: [
                            (ReasoningEffort.minimal, tr("Минимум", "Minimal")), (ReasoningEffort.low, tr("Низкая", "Low")),
                            (ReasoningEffort.medium, tr("Средняя", "Medium")), (ReasoningEffort.high, tr("Высокая", "High")),
                        ],
                        selection: $settings.prompt.effort
                    )
                    Text(tr("Для итогов хватает низкой. Выше значит дороже и медленнее.", "Low is enough for summaries. Higher is costlier and slower."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .glassCard(cornerRadius: 20, padding: 18)
            .transition(.blurReplace)
        }
    }

    @ViewBuilder
    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Расход последнего запроса", "Last request's usage"))
                .font(.headline)
            if let usage = account.lastUsage {
                HStack(spacing: 18) {
                    stat(tr("вход", "input"), usage.input)
                    stat(tr("из кэша", "cached"), usage.cachedInput)
                    stat(tr("выход", "output"), usage.output)
                    stat(tr("всего", "total"), usage.total)
                }
            } else {
                Text(tr("Появится после первого анализа.", "Appears after the first analysis."))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20, padding: 18)
        .animation(Motion.smooth, value: account.lastUsage)
    }

    private func stat(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted())
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
