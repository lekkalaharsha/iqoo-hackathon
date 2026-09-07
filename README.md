# Logic Legends

A Flutter visual-assistance prototype for blind and low-vision users. It uses
on-device text recognition and cloud AI explanations. The on-device language
model is not implemented yet.

Built for the iQOO Hackathon 2026 (Chennai). Flutter, Android, English.

Use a clearly printed, non-sensitive notice for the demo. Read captured text
first, then label any explanation as interpretation. Missing or unclear dose,
expiry, amount, or required-action details must never be invented.

Start with PROJECT.md for current evidence, AGENTS.md for coding rules, and
DEMO_SETUP.md for this laptop's run steps. Earlier plans are not verification.

---

## Architecture

### Two-stage "Read & Explain"

A single large multimodal model means seconds of silence and one point of
failure. Instead, one capture drives two paths:

```
        capture ──┐
                  ├─► FAST: ML Kit OCR ──► speak the raw text        (~100–300 ms)
                  │        classify: medicine / bill / notice / generic
                  │
                  └─► SLOW: language model ──► return a plain-language
                           explanation, then speak by sentence         (2–6 s)

   if SLOW stalls / times out (6 s) ──► speak a rule-based template over the OCR text
   result is cached by SHA-1 image hash ──► a repeat capture answers instantly
```

OCR is the intended fast path, but it can fail or misread text. The
speech and failure behavior still require physical-device validation.

The language model behind the explanation is a **seam** (`AiService.explain`):

| Phase | Runs on | Why |
| --- | --- | --- |
| Submission video | cloud Gemini (`gemini-3.6-flash`) | proves the flow and UX |
| Hackathon build | on-device via `flutter_gemma` (Gemma 2B) | the graded version, airplane mode on stage |

Everything else — OCR, document classification, fallback templates, cache,
text-to-speech — already runs on-device.

### Blind-first interaction

The user never sees the screen, so nothing depends on finding a control.

| Input | Action |
| --- | --- |
| Tap anywhere on the viewfinder | Capture |
| **Volume Up** | Capture |
| **Volume Down** | Repeat the last spoken answer |
| Swipe left / right | Change mode (spoken confirmation) |
| Long-press the viewfinder | Emergency call, with a cancellable 5 s countdown |
| Hold the power button | Opens the app (registered as an Android `ASSIST` provider) |

Volume keys are intercepted natively in `MainActivity.kt` and the system volume
UI is suppressed while the app is foregrounded. Launch speaks a prompt; every
action confirms by haptic and voice. Speech is de-duplicated so unchanged
information is never repeated.

### Modes

1. **Read & Explain** — medicine, bills, notices, labels, signs. The two-stage
   pipeline above. Primary mode.
2. **Explore** — general scene description (`ChatScreen`). Meaningful only once a
   multimodal on-device model (Gemma 3n) is wired; kept out of the demo until
   then.
3. **Voice Chat** — swipe left once from the default Read & Explain mode, then
   tap anywhere or press Volume Up. The microphone collects speech across pauses
   and sends the turn after the user says “clear over.”

### Supporting features

- **Emergency calling** — long-press or the "emergency" voice command. Speaks
  your location, then a 5 s spoken countdown that any tap or key cancels. Calls
  a user-nominated contact set in Settings — **never** 112/108, so an accidental
  trigger cannot summon emergency services. Falls back to the dialler without
  the `CALL_PHONE` permission.
- **SMS triage** — incoming SMS classified offline (OTP / spam / transaction /
  normal) by `sms_classifier.dart` and read aloud, e.g. *"O T P from HDFCBK:
  4 4 9 2 8 1"*. Demo-only: `READ_SMS` is a restricted Play Store permission.
- **GPS context** — reverse-geocoded address, accuracy badge, injected into the
  Explore-mode prompt.
- **Offline cache** — 7-day TTL, LRU, keyed by image hash for Read & Explain.
- **Debug overlay** — double-tap: FPS, GPS, cache, network, active model.

---

## Project layout

```
lib/
├── main.dart                         app entry and camera init
├── models/                           app_config / prompts (+ hand-written .g.dart)
├── screens/
│   ├── homepage.dart                 camera, gestures, routing, emergency overlay
│   ├── read_explain_screen.dart      the two-stage OCR + explanation coordinator
│   ├── chatscreen.dart               Explore-mode scene description (DashChat)
│   └── settings_screen.dart          toggles, emergency contact, wake word
├── services/
│   ├── ocr_service.dart              ML Kit on-device text recognition
│   ├── read_explain_logic.dart       PURE: classify, fallback templates, prompt,
│   │                                 sentence-split — has a `dart run` self-check
│   ├── ai_service.dart               cloud Gemini today; explain() is the
│   │                                 on-device seam for flutter_gemma
│   ├── gemini_api_client.dart        bounded authenticated Gemini REST client
│   ├── on_device_llm_service.dart    stub — returns null (cloud fallback)
│   ├── speech_config.dart            single source for TTS rate/pitch/language
│   ├── hardware_keys.dart            volume-rocker EventChannel + repeat buffer
│   ├── emergency_service.dart        countdown, cancel, location, dialling
│   ├── sms_service.dart / sms_classifier.dart   offline SMS triage (classifier is pure)
│   ├── gps_service.dart              high-accuracy location + reverse geocode
│   ├── config_service.dart           loads assets/config/*.json
│   ├── localization_service.dart     en / ta strings (ta kept in build, not demoed)
│   ├── offline_cache_service.dart    response cache
│   └── browsing_service.dart         DuckDuckGo scrape (Explore augmentation)
├── widgets/debug_overlay.dart
└── utils/colors_utils.dart

android/app/src/main/kotlin/.../MainActivity.kt
    EventChannel  aiforall/hardware_keys   volume rocker
    MethodChannel aiforall/phone           emergency calling
```

Config lives in `assets/config/app_config.json` and `prompts.json` — feature
flags and prompt templates, bundled as assets; changes require a rebuild. Runtime editing is not implemented.

---

## Build

```bash
flutter pub get
# add a Gemini key: cp lib/screens/constapi.dart.example lib/screens/constapi.dart
#   then paste your key (from https://aistudio.google.com/apikey)
flutter run                     # or: flutter build apk --release
```

`constapi.dart` is gitignored. Run the pure-logic self-checks with:

```bash
dart run lib/services/read_explain_logic.dart
dart run lib/services/sms_classifier.dart
```

### Notes / known constraints

- Impeller is disabled (`EnableImpeller=false` in the manifest) — it black-screens
  on older Mali GPUs. The renderer is Skia.
- `android/` is on Gradle 8.14.3 / AGP 8.11.1 / Kotlin 2.2.20, with an
  `afterEvaluate` block in `android/build.gradle` forcing JVM 17 and stripping
  `-Werror` for old plugins.
- `speech_to_text` needs a real system recogniser; it does not initialise on some
  MIUI builds. Expected to work on the iQOO 15.

See `DEMO_FEATURES.md` for the hackathon plan, the model decision, the Sept 4
spike, and the 90-second demo script.

---

## Repo

Built by [@lekkalaharsha](https://github.com/lekkalaharsha) for the iQOO
Hackathon 2026. Issues and PRs welcome after the event.
