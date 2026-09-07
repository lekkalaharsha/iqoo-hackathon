# MEMORY.md — running log

Short, dated notes on what changed and why. `PROJECT.md` is the authoritative
status tracker; `AGENTS.md` is the rulebook; this file is just the timeline.

---

## 2026-09-07 — seam, push-to-talk, TTS safety net, UX polish (→ `v0.1.0`)

Branch: `feature/open-app-by-voice`. All steps verified with `flutter analyze`
(0 errors), the pure `dart run` self-checks, `flutter test` (21 pass; the 2
`widget_test.dart` failures are the pre-existing Mockito stub), and a release
arm64 APK built + installed on the iQOO I2305. **Nothing is blind-user or
TalkBack validated.**

**LLM seam** (`lib/services/llm/`)
- `LlmBackend` interface — `generate() → LlmResult` (text | typed `LlmFailure`),
  `isReady`, `initialize`, `dispose`.
- `GeminiBackend` wraps `GeminiApiClient` and owns the 3-model fallback list.
- `GemmaBackend` is a stub (`isReady=false`); its class doc holds the full
  `flutter_gemma` wiring to paste in.
- `AIService` tries on-device first when ready, then cloud. `on_device_llm_service.dart`
  **deleted**. Wiring a real on-device model is now a `GemmaBackend`-only change.

**Voice**
- `Chatscreen` Voice Chat is now **push-to-talk**: hold anywhere to listen,
  release to send. Removed the mic toggle, the spoken "clear over" terminator,
  the 2-minute timeout, and the auto-re-listen loop. Homepage long-press =
  Emergency SOS is untouched.
- `voice_assistant_service` `_switchMode` / parser now cover all 3 home modes
  (0 Explore, 1 Read & Explain, 2 Voice Chat).

**TTS safety net** (`speech_config.dart`)
- After `setLanguage('en-US')`, pick an en-US voice whose name isn't a known-
  broken neural pack (`lstm`/`seanet`/`iog`/`hol`/`network`).
- One-time silent `synthesizeToFile` probe → `ttsHealthy` (`ValueNotifier<bool?>`);
  healthy only if it completes **and** writes a > 2 KB WAV.
- `homepage._announceReady` speaks + SnackBars `ttsBrokenAdvice` (with an
  "Open" action → system TTS settings via the new `openTtsSettings` channel
  method) instead of ~7 s of silence per line.
- The Google TTS English voice data is broken on both test phones — this is a
  device fix (reinstall voice data), the app just surfaces it.

**Cloud reliability**
- Markdown stripped from every model reply — new pure `lib/services/plain_text.dart`
  `toPlainSpeech()` (headings, bold/italic, bullets, links, code, rules).
- Timeouts raised: `explain()` 6 s → 25 s; `generateResponse()` 15 s → 25 s
  text / 45 s with an image. (The user's key works; calls were just timing out
  on a poor connection.)
- Read & Explain writes the fallback template to the on-screen panel (was blank
  whenever the model was unavailable).

**UX / Settings** (PR #3, merge `32578e7`)
- New Settings **"Speaking"** section: persisted **speaking speed** (Slower /
  Faster / Test, 20–90 %) and a **Brief answers** toggle (one sentence).
- "Still working." spoken every 6 s while an answer is pending (Read & Explain
  and chat).
- Read & Explain: a tap while explaining stops the wait and speaks the OCR
  template now; leads with `keyFact` (expiry / amount / due date).
- Emergency contact optional **name** — "Calling Amma…" instead of "…your
  emergency contact".
- Launch announces offline state.

**Branding / cleanup**
- New hand-written adaptive launcher icon (vector "source + 3 waves", brand
  `#673AB7`) + branded splash; dropped `flutter_launcher_icons` config.
- `shortSender` deduped into `sms_classifier`; unused `assets/images/*` removed.
- First-run tutorial no longer auto-plays (still on demand from Settings).
  `DebugOverlay` + floating GPS badge gated to `kDebugMode`.

**Tag:** `v0.1.0` (git tag only — make the GitHub Release in the web UI and
attach `build/app/outputs/flutter-apk/app-release.apk`).

**PR #2** (jhansipallapothu — "Listening Mode, flutter gemma and tamil
disabling"): reviewed, **do not merge as-is**. It fills the deleted
`on_device_llm_service.dart` stub back in (collides with the seam), uses
Qwen3 0.6B (tiny; reconsider Gemma 3 1B), raises `minSdk` to 30, and is
stale/conflicting. Plan: land the Tamil-strip separately rebased; port its
`flutter_gemma` code into `GemmaBackend`.

**Deferred** (ideas raised, not built): real response streaming, live pre-
capture OCR framing guidance + auto-capture/torch, haptic vocabulary + earcons,
Voice Chat sound-level meter, hardware-key live speech-rate control.
