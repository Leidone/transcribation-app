<div align="center">

# Transcribation

**Record a call. Get the transcript, decisions and tasks.**
Recognition runs on your device. Only text ever leaves it — and only if you choose to send it.

![Swift](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-26%2B-000000?logo=apple&logoColor=white)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-only-555555)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI%20·%20Liquid%20Glass-0A84FF)
![License](https://img.shields.io/badge/license-MIT-blue)
![Local first](https://img.shields.io/badge/audio-never%20leaves%20the%20device-30D158)

</div>

---

## What it is

Transcribation is a native macOS app (with an iPhone companion) that:

1. **records** the audio of a chosen app (Zoom, Meet, Teams…) and your microphone as two separate streams;
2. **transcribes** the recording locally, in Russian and English, with speakers told apart;
3. **produces a summary** — key points, decisions made and tasks with owners — through the AI of your choice.

The interface follows the apple.com look: Liquid Glass, a living gradient background, smooth animations.

## Features

| | |
|---|---|
| 🎙 **Two streams** | Other participants' audio and your microphone are recorded separately and aligned by PTS, so "who is speaking" is known even before diarization |
| 🔒 **Local transcription** | Parakeet TDT v3 (FluidAudio, Core ML), on the device after the initial model download; each recording shows its actual processing time |
| 🗣 **Speakers** | Offline diarization; voices can be renamed and the names are stored next to the recording |
| 🧠 **Four AI providers** | ChatGPT account (via Codex), OpenAI API key, Claude (Anthropic API), any OpenAI-compatible server |
| ✅ **Summary & tasks** | One JSON schema for every provider; tasks can be checked off |
| ▶️ **Player in sync** | Click a transcript line or a task's timestamp to hear that moment; the line being heard is highlighted; playback at 1×, 1.25×, 1.5× or 2× |
| 🔎 **Search** | Across titles, speaker names, summaries, tasks and transcripts of every recording, with the matching snippet |
| 🧾 **Export** | Copy the summary, share it, or save Markdown/PDF (with or without the transcript) |
| ⏰ **Reminders** | Send one task or all open ones to Apple Reminders; exact dates become due dates |
| 👂 **Voice memory** | Name a voice once and it is named automatically in later recordings (only a numeric voiceprint is kept, on the device) |
| 🗂 **Meeting templates** | General, stand-up, interview, client call, one-on-one — the same schema, a different focus |
| ✏️ **Transcript editing** | Fix a line by hand; the summary is flagged as outdated and can be regenerated |
| 📞 **Call detection** (Mac) | When Zoom, Teams, FaceTime, Telegram… turn on the microphone, a notification offers to record |
| 🛑 **End-of-call detection** (Mac) | Saves the recording when the call ends or its app closes; can remind you instead of stopping automatically; also watches for prolonged silence |
| 🗓 **Calendar** (Mac) | Takes the meeting title and invited people from Apple Calendar; previews the match before recording, lets you choose another event or unlink it, and suggests participants' names for speakers |
| 💾 **Storage & recovery** (Mac) | Compresses recorded audio to M4A after transcription, recovers saved audio from interrupted recordings, and warns or stops safely when disk space runs low |
| 🛠 **Problem reports** (Mac) | Saves a diagnostic archive with logs and Mac details, without recordings, conversation text or API keys |
| ⌨️ **Global hotkey** (Mac) | Starts and stops a recording from any app; pick your own combination (⌃⌥⌘R by default), e.g. ⌥R or F5 |
| 📥 **Import** | WAV, MP3, M4A, AAC, FLAC, AIFF, CAF — drag files into the window |
| 🗑 **Delete** | On Mac a recording goes to the Trash; on iPhone it is removed permanently (with a warning) |
| 💬 **Ask your meetings** (Mac) | "What did we decide about the budget?", "What did Boris promise?" — about one meeting or all of them, through the AI you connected; answers link to the recording and the minute |
| ⭐ **Important moments** (Mac) | A shortcut (⌃⌥⌘M, held only while recording) or a button marks the moment; it is highlighted in the transcript and the summary gives it weight |
| 📋 **All tasks** (Mac) | Tasks of every meeting in one place, grouped by meeting; show open or all tasks, filter your own, tick them off or jump to where they were agreed |
| 🗣 **Shortcuts, Siri, Spotlight** (Mac) | Start Recording, Stop Recording, Mark Important Moment, Last Meeting Summary; transcripts and summaries are searchable with ⌘Space |
| 📝 **Live transcript** (Mac, beta) | Text appears in a separate panel during calls and in-person meetings, your words apart from the others' on calls; the full transcript still comes after recording |
| 🔄 **Automatic updates** (Mac) | Sparkle, EdDSA-signed; off until a public place for updates is chosen ([docs/UPDATES.md](docs/UPDATES.md)) |
| 🌐 **English and Russian** (Mac) | The interface follows the system language (or the per-app language setting); English when neither is preferred |
| ✉️ **Follow-up letter** (Mac) | A Mail draft for the meeting's people with the summary, decisions and open tasks; the invited people from the calendar are already the recipients |
| 🔈 **Sound check** (Mac) | Warns after 30 seconds without app audio or a minute without microphone sound; detects a microphone delivering digital silence after about 8 seconds |
| 🧑‍🤝‍🧑 **In-person meetings** (Mac) | Records a meeting in a room from the microphone alone, with speaker separation in the transcript |
| ⏸ **Pause** (Mac) | Pause a recording and carry on; nothing said on pause is kept, times and marks stay right |
| 📖 **Your vocabulary** (Mac) | Names and terms recognition gets wrong, fixed in every transcript (and in old ones on request) |
| 🗒 **Summaries to a folder** (Mac) | Every summary is also kept as a Markdown note in a folder you choose — an Obsidian vault, iCloud Drive |
| 📊 **Who spoke how much** (Mac) | Each person's share of the talk on the summary tab |
| 🗓 **Questions by period** (Mac) | "What did we decide this week?", "What was discussed yesterday?" look at that period's meetings only |
| 📍 **Latest meeting in the menu bar** (Mac) | The latest summary and its open tasks without opening the window |
| 💬 **Telegram and Slack** (Mac) | A summary goes to a Telegram chat through your own bot or to a Slack channel through a webhook, only when you press the button; the token and address stay in the Keychain |
| 🔐 **Touch ID** (Mac) | The window and the menu bar show recordings only after Touch ID or the Mac's password; recording carries on |
| 🔁 **Meeting series** (Mac) | Recordings linked to calendar events with the same title form a series; questions compare with the last one, and summaries follow up on its open tasks |
| 🏷 **Tags** (Mac) | Your own labels on recordings; a click shows every recording with the tag |
| ⚙️ **AI instructions** (Mac) | Edit the summary prompt, tune Codex reasoning effort and see token usage when the provider reports it |
| 📱 **iPhone** | Import, transcription, summaries and ReplayKit recording — same design, same providers (except ChatGPT sign-in) |

## Privacy

- Audio recognition runs **on the device**. Recordings and transcripts are stored locally; call recordings have `session.json`, CAF audio (or M4A after compression), `transcript.json`, `analysis.json` and `speakers.json`.
- Only the **transcript text** is sent to the AI you picked, and only when you press "Get summary" or ask a question. A question about all meetings sends the text of the meetings related to it (up to ~40 thousand tokens).
- Sharing summaries to Telegram, Slack or Mail, or exporting to a cloud-synced folder, sends the chosen content to that destination. Touch ID protects access through the app; it does not separately encrypt recording files.
- The Spotlight index is kept by macOS on the Mac itself and can be turned off in the settings; the live transcript is never written to disk.
- API keys are stored **in the Keychain only** — not in `UserDefaults`, not in files.
- Codex runs with all agent tools disabled and a read-only sandbox: it can read text and answer, nothing more.

## Installation

### macOS

Requires an Apple Silicon Mac with **macOS 26+**.

1. Download `Transcribation.dmg` from [release 1.0.0](https://github.com/Leidone/transcribation-app/releases/tag/v1.0.0) and drag the app into Applications.
2. The app is not notarized (there is no paid Apple Developer Program membership), so Gatekeeper warns about an unidentified developer on first launch. Remove the quarantine flag:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Transcribation.app
   ```

   or right-click the app → Open → confirm.
3. Allow microphone access and app audio recording.
4. Click "Connect AI" at the bottom left and choose how to sign in.

The interface follows your preferred macOS languages, not the Mac model. To use English for this app, choose Transcribation → English in System Settings → General → Language & Region → Applications, then restart it. English is the fallback when neither English nor Russian is preferred.

### iPhone

Requires **iOS 26+**. Built through Xcode with a free Apple ID — the provisioning profile lasts 7 days, after which the app has to be reinstalled. Choose your team in Xcode, or set it once before generating the project:

```bash
export TRANSCRIBATION_TEAM=<your Apple team ID>
xcodegen generate
open CallRecorder.xcodeproj   # scheme CallRecorderMobile → your iPhone → Run
```

## How it works

```
        ┌────────────────────┐        ┌───────────────────────┐
        │  CallRecorder       │        │  CallRecorderMobile    │
        │  macOS · SwiftUI    │        │  iOS · SwiftUI         │
        │  ScreenCaptureKit   │        │  + Broadcast Extension │
        └─────────┬──────────┘        └───────────┬───────────┘
                  └──────────────┬────────────────┘
                     Packages/CallRecorderKit  (SwiftPM)
        ┌──────────────┬─────────┴─────────┬──────────────────┐
   AudioCapture   Transcription       CodexClient
   recording,     FluidAudio +        Codex JSON-RPC,
   CAF, import    WhisperKit, Core ML Anthropic, OpenAI-compat.
```

- **Recording.** macOS: ScreenCaptureKit — the audio of one specific app plus the microphone. iOS: a ReplayKit Broadcast Upload Extension — the only system way to capture audio on iPhone; it records the whole screen's audio rather than one app, and can only be started manually through the system picker.
- **Transcription.** [FluidAudio](https://github.com/FluidInference/FluidAudio) (Parakeet TDT v3 + diarization). [argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) (WhisperKit) was used for comparison: Whisper turbo ran at ~2.7× realtime against 169× for Parakeet.
- **AI.** One compact prompt and one JSON schema (`summary` / `decisions` / `tasks`) for all providers. Codex speaks JSON-RPC over stdio; Anthropic and OpenAI-compatible servers are direct HTTP clients with a forced structured reply (tool calling and `response_format: json_schema`).
- **Shared code.** Recognition, AI clients, storage formats and reusable library logic live in `CallRecorderKit`; each app also has its own models and platform integrations. Platform code is isolated with `#if os(macOS)` / `#if os(iOS)`.

### What is missing on iPhone — and why

| Capability | Why it is unavailable |
|---|---|
| Recording a single app's audio | iOS has no ScreenCaptureKit equivalent; ReplayKit captures the whole screen |
| ChatGPT account sign-in | That is Codex's own OAuth, and iOS does not let apps launch other executables |
| Features marked **(Mac)** above | Not yet exposed in the iPhone app; sharing a package does not mean full feature parity |

## Building from source

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
xcodegen generate                    # the .xcodeproj is not stored in git
```

```bash
# macOS app
xcodebuild build -project CallRecorder.xcodeproj -scheme CallRecorder -configuration Release
```

```bash
# installer image with Codex bundled
Tools/dmg/make-dmg.sh --bundle-codex
```

> Building for the iOS simulator needs an explicit `arm64` architecture: FluidAudio's `NemoTextProcessing.xcframework` has no x86_64 slice. A simulator older than iOS 26 will refuse to install the app.

## Tests

```bash
cd Packages/CallRecorderKit && swift test
```

341 tests on Swift Testing in five targets — `LocalizationTests`, `AudioCaptureTests`, `TranscriptionTests`, `CodexClientTests`, `CallLibraryTests` (JSON-RPC, the AI clients, search, export and PDF, voice memory, transcript edits, file formats, questions to meetings, marks, the live transcript's phrase cutting, settings reaching the helpers, and a check that every Russian interface text has an English twin). GitHub Actions runs them and builds the macOS app on pushes and pull requests. Recognition quality (WER/DER) is measured by a separate Python tool in [`Tools/eval`](Tools/eval).

## Repository layout

```
project.yml                      XcodeGen manifest
Packages/CallRecorderKit/        shared logic (SwiftPM)
  Sources/Localization/          interface language, texts in both languages
  Sources/AudioCapture/          recording, import, recording-folder format, marks, App Group (iOS)
  Sources/Transcription/         recognition pipeline, live transcript
  Sources/CodexClient/           Codex + Anthropic + OpenAI-compatible clients, meeting templates
  Sources/CallLibrary/           what both apps share: models, search, export, player, voice memory,
                                 questions to meetings, task overview, settings and helpers
CallRecorder/App/                macOS app
CallRecorderMobile/              iOS app and Broadcast Extension
Tools/dmg/                       dmg build
Tools/release/                   appcast for automatic updates (prepares, never uploads)
Tools/eval/                      WER/DER evaluation
docs/UPDATES.md                  how to turn on automatic updates (in Russian)
Corpus/                          real recordings for measurements — never committed
```

## Status

- **macOS** — [1.0.0 released](https://github.com/Leidone/transcribation-app/releases/tag/v1.0.0); live transcription remains beta, and automatic updates are not configured yet. The About window and Settings show the version and author.
- **iOS** — experimental. Import → transcription → Claude summary is verified in the simulator; the app installs and launches on an iPhone. The "OpenAI key" and "Other AI" providers are covered by tests but have not been tried with real keys. ReplayKit recording builds, but the full "record → transcribe" path on a real call has not been exercised yet.
- **Roadmap** — task list parity with Mac, a notification when a broadcast ends in the background, iPad, moving the duplicated iOS models into a shared target.

## License

[MIT](LICENSE) © 2026 Alex Berezkin.

Dependencies keep their own licenses. The `Transcribation.dmg` build can embed the unmodified OpenAI Codex binary, which is distributed under its own terms.
