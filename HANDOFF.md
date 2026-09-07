> Historical plan/context: consult PROJECT.md for current verification.
> Offline, accessibility, latency, and device claims below are not current
> acceptance evidence. Follow AGENTS.md safety rules for all new work.

# Handoff — 2026-09-03

Read `README.md` for architecture, `DEMO_FEATURES.md` for the hackathon plan +
90-sec script, `TASKS.md` for the next-session checklist.

## Branch

`feature/blind-first-and-sms` (unmerged; `main` = baseline). Recent work:

```
07fc4b9  HANDOFF: shareable split-ABI release APK
1c7e88e  Disable R8 for release (ML Kit CJK recognisers)
f671aa3  First-run spoken tutorial + assistant-setup step
1c7e88e/172bf19  Double-tap to ask a custom question
834df59  Blind-first UX pass + English-only build
1beafa8  Fix two rounds of code-review findings (TTS/emergency/OCR/voice)
97e087d  Voice chat in Explore + speech rate 0.4
ee15ba5  Device-test fixes: thumbnail decode, OCR text on screen
```

## Verified on the Redmi this session (adb-driven)

- Volume-Up capture, no system volume bar; navigates to Read & Explain
- On-device ML Kit OCR runs; fast-path TTS speaks the result
- Camera suspend/resume survives backgrounding
- Mode switch, launch announcement
- Emergency: long-press → red countdown overlay → tap cancels; `dumpsys
  telecom` confirmed **no call placed** (tested with a dummy `0000000000`
  contact injected via `run-as` into `flutter.emergency_contact`)
- New UX: no bottom nav/FAB, "TAP TO DESCRIBE" pill renders (screenshot)

## NOT verified — do these first next session

1. **ML Kit OCR on a real printed medicine strip / notice.** Everything so far
   was blank surfaces or handwriting, so the slow-path `explain()` has never
   actually fired. This is the demo's load-bearing unknown.
2. **Emergency after the `1beafa8` rework** — the spoken preamble is now
   cancellable (it wasn't; taps during it no-op'd, then the call went
   through). Re-test: long-press → tap *during* the "your location is…"
   speech → must abort. Then double-long-press (must not double-dial). Then
   let one call actually connect to a safe 2nd number.
3. **First-run tutorial** — fresh install → 7 spoken steps, tap advances,
   swipe skips, last step opens the assistant picker. Then set AIFORALL as
   the device Assistant and confirm power-button-hold opens it.
4. **Everything voice** (double-tap-to-ask, Explore voice chat) needs the
   **iQOO 15** — `speech_to_text` won't init on the Redmi's MIUI stub
   recogniser (it announces "not available" and falls back).
5. SMS triage, camera torch in low light.

## Sept 4 — on-device spike (not started)

`ai_service.explain()` is the seam. Swap cloud Gemini → `flutter_gemma` +
Gemma 2B. On the iQOO 15 (or any Snapdragon phone) measure before committing:

- `.npu` / `.gpu` / `.cpu` backend latency (NNAPI was >4200 ms vs ~500 ms CPU
  in arXiv 2607.02371 — do not assume NPU wins)
- peak RAM with the model loaded + camera running
- Qualcomm AI Hub for pre-optimised Snapdragon weights

## Shareable APK

```
flutter build apk --release --split-per-abi
```

- Release block in `android/app/build.gradle`: `minifyEnabled=false` +
  `shrinkResources=false` — R8 fails on ML Kit's CJK/Devanagari recognisers we
  reference but don't bundle.
- Fat APK ~90 MB; hand testers **`app-arm64-v8a-release.apk` (~38 MB)** from
  `build/app/outputs/flutter-apk/` (gitignored). Over the 30 MB chat-upload
  cap — share via WhatsApp-as-document / Drive.
- Needs `lib/screens/constapi.dart` (real key) or it builds keyless.

## Tooling added this session

- `.mcp.json` → `context7` (live docs for flutter_tts / speech_to_text / camera
  / ML Kit); enabled in `.claude/settings.local.json`.
- `.claude/skills/device-run` (user-only): rebuild → install on Redmi → wait →
  screenshot loop.
- `.claude/skills/blind-ux-check` (Claude-only): accessibility guardrails.

## Known constraints

- Impeller off (`EnableImpeller=false` in manifest) — black-screens old Mali GPUs
- `speech_to_text` dead on the Redmi's MIUI — all voice input unverified until iQOO
- `en-IN` TTS is network-only on Indian devices — everything uses `en-US`
- `SpeechConfig.rate` Android = 0.4 (flutter_tts's Android scale runs hot)
- English-only: `isTamil` hard-wired false; dead Tamil ternaries still in source
- `lib/screens/constapi.dart` gitignored; copy from `.example`, add a key
- Always commit with `git -c core.autocrlf=false`
- `HACKATHON_README.md` is stale — delete or point to README + DEMO_FEATURES
