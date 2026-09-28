import AudioCapture
import Foundation
import Localization
import Testing
@testable import CallLibrary

@Test func unnamedVoicesReadInTheInterfaceLanguage() {
    #expect(SpeakerNames.defaultName(for: "Я", in: .english) == "Me")
    #expect(SpeakerNames.defaultName(for: "Собеседник 2", in: .english) == "Speaker 2")
    #expect(SpeakerNames.defaultName(for: "Спикер 1", in: .english) == "Speaker 1")
    #expect(SpeakerNames.defaultName(for: "Анна", in: .english) == "Анна")
    #expect(SpeakerNames.defaultName(for: "Собеседник 2", in: .russian) == "Собеседник 2")
}

@Test func aNameGivenToAVoiceIsKeptInEveryLanguage() {
    let names = SpeakerNames(names: ["Собеседник 1": "Анна"])
    #expect(names.displayName(for: "Собеседник 1") == "Анна")
}

@Test func datesInDocumentsFollowTheInterfaceLanguage() {
    #expect(Language.russian.locale.identifier == "ru_RU")
    #expect(Language.english.locale.identifier == "en_US")
}
