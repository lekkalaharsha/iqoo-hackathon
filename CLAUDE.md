# CLAUDE.md — orientation for AI agents

**Read `AGENTS.md` first** — it is the rulebook (blind-first is a release gate,
safety rules for medicine/money/emergency, testing expectations). This file is
just a fast map. `PROJECT.md` is the authoritative status tracker — update it
after any user-visible change. `MEMORY.md` is the dated timeline.

## What this is

**Logic Legends** (Android applicationId `com.logiclegends.saarthi`) — a
blind-first, audio-only Flutter assistant for the iQOO Hackathon 2026
(Chennai). Point the camera at printed text; it reads it aloud **and explains
what it means and what to do**. English only (Tamil branches are dead code;
`LocalizationService.isTamil` is hard-wired false).

## Home screen — 3 swipe modes (`lib/screens/homepage.dart`)

`_selectedIndex` starts at **1**.

| # | Mode | Screen | Path |
| - | ---- | ------ | ---- |
| 0 | Explore | `Chatscreen` | capture → cloud multimodal scene description |
| 1 | Read & Explain (default) | `ReadExplainScreen` | ML Kit OCR speaks raw text now → `AIService.explain()` adds a plain-language explanation → `read_explain_logic.dart` templates as the offline floor |
| 2 | Voice Chat | `Chatscreen(autoStartVoice: true)` | **push-to-talk**: hold anywhere = listen, release = send |

Gestures: tap = capture · Volume-Up = capture · Volume-Down = repeat last answer
· swipe = change mode · long-press (home) = Emergency SOS (cancellable
countdown, calls a user-chosen contact, never 112/108) · power-button hold =
open (ASSIST provider).

## LLM path — the seam (`lib/services/llm/`)

`LlmBackend` interface → `GeminiBackend` (cloud REST, `x-goog-api-key`, 3-model
fallback) + `GemmaBackend` (**stub** — `isReady=false`; its class doc has the
`flutter_gemma` wiring ready to paste). `AIService` tries on-device first when
ready, then cloud; strips Markdown from every reply via `plain_text.dart`
`toPlainSpeech()`. Timeouts: `explain` 25 s, `generateResponse` 25 s text /
45 s with image.

**API key:** `lib/screens/constapi.dart` (gitignored) → `GEMINI_API_KEY`.
Placeholder `YOUR_...` ⇒ `GeminiBackend.isReady` false ⇒ every AI path shows
"not set up". Copy the real key from the working-copy snapshot if present.

## Speech (`lib/services/speech_config.dart`)

One shared `FlutterTts` + `SpeechToText`. `apply()` = sequential mode + a
one-time TTS health probe (`ttsHealthy` `ValueNotifier<bool?>`) + non-broken
en-US voice selection. Speaking rate is user-settable and persisted
(`SpeechConfig.setRate`, 20–90 %); `briefAnswers` bool persisted. Route all
speech through this file — never set language/rate/pitch per screen.

Platform channel `aiforall/phone` (`android/.../MainActivity.kt`):
`call`/`dial`, `openAssistSettings`, `openTtsSettings`, `payUpi`,
`listLaunchableApps`/`launchApp`. EventChannel `aiforall/hardware_keys` = the
volume rocker.

## Build / test / device loop

```
flutter analyze                 # gate: 0 error-level diagnostics
dart run --enable-asserts lib/services/{read_explain_logic,sms_classifier,intent_resolver,plain_text}.dart
flutter test test/              # 21 pass; widget_test.dart has 2 pre-existing Mockito failures
flutter build apk --release --target-platform android-arm64
git checkout -- linux/ macos/ windows/   # pub get regenerates desktop registrants — revert them
adb -s <serial> install -r build/app/outputs/flutter-apk/app-release.apk
```

Commit with `git -c core.autocrlf=false commit` (files flip CRLF↔LF otherwise).
No `gh` CLI here — GitHub PR/release work is web UI or `curl` against the API.

## Current state (2026-09-07)

Trunk `feature/open-app-by-voice`, tagged **`v0.1.0`**. **PR #2** is open and
must NOT be merged as-is (it re-creates the deleted on-device stub and
conflicts with the seam — see `MEMORY.md`). TTS voice data is broken on both
test phones; the fix is device-side (reinstall the English voice). Nothing is
blind-user / TalkBack validated yet — that is the top gap.
