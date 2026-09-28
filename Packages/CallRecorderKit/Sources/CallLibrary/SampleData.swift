import Foundation
import Localization

/// Illustrative results shown until real recordings exist; always labelled "Пример" in the interface.
public enum SampleData {
    /// In the interface language, so an English interface does not open on a Russian example.
    public static var recordings: [RecordingItem] {
        Language.current == .english ? [englishWeeklyRelease, englishPaymentsDaily] : [weeklyRelease, paymentsDaily]
    }

    /// The samples to list next to `realCount` recordings of the person's own: all of them while the library is
    /// empty and samples are enabled, none otherwise. They illustrate an empty library; once there is a real
    /// recording they only get in the way.
    public static func visible(_ samples: [RecordingItem], alongside realCount: Int, enabled: Bool) -> [RecordingItem] {
        enabled && realCount == 0 ? samples : []
    }

    private static var weeklyRelease: RecordingItem {
        RecordingItem(
            id: UUID(uuidString: "0A000000-0000-0000-0000-000000000001")!,
            title: "Weekly по релизу 2.4",
            appName: "Zoom",
            appBundleID: "us.zoom.xos",
            startedAt: Calendar.current.date(byAdding: .hour, value: -3, to: .now) ?? .now,
            duration: 1_612,
            status: .ready,
            directory: nil,
            isSample: true,
            transcript: [
                TranscriptLine(id: 0, time: 0, speaker: "Анна", isMe: false, text: "Всем привет, начинаем weekly по релизу. Главный вопрос: успеваем ли мы выпустить версию 2.4 в пятницу."),
                TranscriptLine(id: 1, time: 14, speaker: "Борис", isMe: false, text: "Бэкенд готов, остались тесты на платёжном модуле. Я проверю их до среды."),
                TranscriptLine(id: 2, time: 31, speaker: "Я", isMe: true, text: "Хорошо. Тогда решение такое: релиз в пятницу, если тесты пройдут. Если нет, переносим на понедельник."),
                TranscriptLine(id: 3, time: 47, speaker: "Анна", isMe: false, text: "Согласна. Ещё нужен changelog для клиентов, я подготовлю черновик до четверга."),
                TranscriptLine(id: 4, time: 62, speaker: "Борис", isMe: false, text: "И надо предупредить поддержку о новой форме оплаты. Кто возьмёт?"),
                TranscriptLine(id: 5, time: 70, speaker: "Я", isMe: true, text: "Я напишу поддержке сегодня после звонка."),
                TranscriptLine(id: 6, time: 78, speaker: "Анна", isMe: false, text: "Отлично. Тогда встречаемся в четверг в десять, чтобы финально всё сверить."),
            ],
            analysis: AnalysisResult(
                summary: "Команда сверила готовность релиза 2.4. Бэкенд готов, открытым остаётся только проверка платёжного модуля. Релиз назначен на пятницу при условии успешных тестов, запасной срок — понедельник. Отдельно договорились подготовить материалы для клиентов и предупредить поддержку о новой форме оплаты.",
                decisions: [
                    "Релиз 2.4 выходит в пятницу, если тесты платёжного модуля пройдут; иначе переносится на понедельник.",
                    "Финальная сверка проходит в четверг в 10:00.",
                ],
                tasks: [
                    TaskItem(id: UUID(), title: "Проверить тесты платёжного модуля", owner: "Борис", due: "до среды", quote: "Я проверю их до среды.", timestamp: 14, isDone: false),
                    TaskItem(id: UUID(), title: "Подготовить черновик changelog для клиентов", owner: "Анна", due: "до четверга", quote: "я подготовлю черновик до четверга", timestamp: 47, isDone: false),
                    TaskItem(id: UUID(), title: "Предупредить поддержку о новой форме оплаты", owner: "Я", due: "сегодня", quote: "Я напишу поддержке сегодня после звонка.", timestamp: 70, isDone: true),
                    TaskItem(id: UUID(), title: "Финальная сверка релиза", owner: nil, due: "четверг, 10:00", quote: "встречаемся в четверг в десять", timestamp: 78, isDone: false),
                ]
            )
        )
    }

    private static var paymentsDaily: RecordingItem {
        RecordingItem(
            id: UUID(uuidString: "0A000000-0000-0000-0000-000000000002")!,
            title: "Daily — команда платежей",
            appName: "Google Meet",
            appBundleID: "com.google.Chrome",
            startedAt: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now,
            duration: 894,
            status: .ready,
            directory: nil,
            isSample: true,
            transcript: [
                TranscriptLine(id: 0, time: 0, speaker: "Иван", isMe: false, text: "Вчера закрыл интеграцию с эквайрингом, сегодня беру возвраты."),
                TranscriptLine(id: 1, time: 22, speaker: "Я", isMe: true, text: "Есть блокеры?"),
                TranscriptLine(id: 2, time: 27, speaker: "Иван", isMe: false, text: "Нужен доступ к тестовому стенду банка, жду ответа от их поддержки."),
            ],
            analysis: AnalysisResult(
                summary: "Иван завершил интеграцию с эквайрингом и переходит к возвратам. Единственный блокер — доступ к тестовому стенду банка.",
                decisions: [],
                tasks: [
                    TaskItem(id: UUID(), title: "Получить доступ к тестовому стенду банка", owner: "Иван", due: nil, quote: "Нужен доступ к тестовому стенду банка", timestamp: 27, isDone: false),
                ],
                template: .standup
            )
        )
    }

    private static var englishWeeklyRelease: RecordingItem {
        RecordingItem(
            id: UUID(uuidString: "0A000000-0000-0000-0000-000000000001")!,
            title: "Release 2.4 weekly",
            appName: "Zoom",
            appBundleID: "us.zoom.xos",
            startedAt: Calendar.current.date(byAdding: .hour, value: -3, to: .now) ?? .now,
            duration: 1_612,
            status: .ready,
            directory: nil,
            isSample: true,
            transcript: [
                TranscriptLine(id: 0, time: 0, speaker: "Anna", isMe: false, text: "Hi everyone, let's start the release weekly. The main question: can we ship 2.4 on Friday?"),
                TranscriptLine(id: 1, time: 14, speaker: "Boris", isMe: false, text: "The backend is done, only the payment module tests are left. I'll check them by Wednesday."),
                TranscriptLine(id: 2, time: 31, speaker: "Я", isMe: true, text: "Good. Then the decision is: we release on Friday if the tests pass. If not, we move it to Monday."),
                TranscriptLine(id: 3, time: 47, speaker: "Anna", isMe: false, text: "Agreed. We also need a changelog for customers, I'll draft it by Thursday."),
                TranscriptLine(id: 4, time: 62, speaker: "Boris", isMe: false, text: "And support has to know about the new payment form. Who takes that?"),
                TranscriptLine(id: 5, time: 70, speaker: "Я", isMe: true, text: "I'll write to support today after the call."),
                TranscriptLine(id: 6, time: 78, speaker: "Anna", isMe: false, text: "Great. Then let's meet on Thursday at ten for a final check."),
            ],
            analysis: AnalysisResult(
                summary: "The team checked whether release 2.4 is ready. The backend is done; only the payment module tests are still open. The release is set for Friday if the tests pass, with Monday as the fallback. The team also agreed to prepare material for customers and to tell support about the new payment form.",
                decisions: [
                    "Release 2.4 ships on Friday if the payment module tests pass; otherwise it moves to Monday.",
                    "The final check is on Thursday at 10:00.",
                ],
                tasks: [
                    TaskItem(id: UUID(), title: "Check the payment module tests", owner: "Boris", due: "by Wednesday", quote: "I'll check them by Wednesday.", timestamp: 14, isDone: false),
                    TaskItem(id: UUID(), title: "Draft the customer changelog", owner: "Anna", due: "by Thursday", quote: "I'll draft it by Thursday", timestamp: 47, isDone: false),
                    TaskItem(id: UUID(), title: "Tell support about the new payment form", owner: "Я", due: "today", quote: "I'll write to support today after the call.", timestamp: 70, isDone: true),
                    TaskItem(id: UUID(), title: "Final release check", owner: nil, due: "Thursday, 10:00", quote: "let's meet on Thursday at ten", timestamp: 78, isDone: false),
                ]
            )
        )
    }

    private static var englishPaymentsDaily: RecordingItem {
        RecordingItem(
            id: UUID(uuidString: "0A000000-0000-0000-0000-000000000002")!,
            title: "Daily — payments team",
            appName: "Google Meet",
            appBundleID: "com.google.Chrome",
            startedAt: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now,
            duration: 894,
            status: .ready,
            directory: nil,
            isSample: true,
            transcript: [
                TranscriptLine(id: 0, time: 0, speaker: "Ivan", isMe: false, text: "Yesterday I finished the acquiring integration, today I'm taking refunds."),
                TranscriptLine(id: 1, time: 22, speaker: "Я", isMe: true, text: "Any blockers?"),
                TranscriptLine(id: 2, time: 27, speaker: "Ivan", isMe: false, text: "I need access to the bank's test environment, waiting for their support to answer."),
            ],
            analysis: AnalysisResult(
                summary: "Ivan finished the acquiring integration and moves on to refunds. The only blocker is access to the bank's test environment.",
                decisions: [],
                tasks: [
                    TaskItem(id: UUID(), title: "Get access to the bank's test environment", owner: "Ivan", due: nil, quote: "I need access to the bank's test environment", timestamp: 27, isDone: false),
                ],
                template: .standup
            )
        )
    }
}
