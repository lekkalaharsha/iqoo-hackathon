# Logic Legends — Project Tracker

Last updated: 2026-09-07  
Current working branch: `feature/open-app-by-voice`  
Primary users: blind and low-vision people

This is the living source of truth for product status. Update it immediately
after implementing, testing, device-verifying, or reconsidering a feature.
Code existing is not the same as a feature helping a real person.

## Product purpose

Logic Legends is an audio-first Flutter assistant that helps a blind person
understand printed information using a phone camera. Its central promise is
**comprehension, not transcription**: read important text quickly, explain it
in plain language, and state a useful next action without requiring the user to
see or locate an on-screen control.

The app should increase independence without creating false confidence. OCR,
model-generated explanations, and inferred actions can be wrong, especially
for medicine, money, legal notices, and emergency situations. Uncertainty must
be spoken clearly.

## What success means

A feature succeeds only when a blind user can:

1. Discover or learn that it exists without relying on sight.
2. Reach and operate it using touch, a physical key, gesture, or voice.
3. Hear and feel immediate confirmation that the action occurred.
4. Understand the result and what to do next.
5. Recover from silence, an error, accidental activation, or interruption.
6. Use it on a real device in realistic noise, lighting, network, and motion.

A sighted developer completing the happy path is necessary, but it is not user
validation.

## Status language

Use these exact stages so that the project never overstates progress:

| Stage | Meaning |
| --- | --- |
| Planned | Agreed idea; implementation has not started. |
| In progress | Work exists but the end-to-end flow is incomplete. |
| Implemented | The code path is complete enough to exercise. |
| Automated tested | Relevant unit/widget/integration checks pass. |
| Device verified | The complete flow was exercised on named physical hardware. |
| Blind-user validated | A blind user completed realistic tasks; observations and follow-ups are recorded. |
| Blocked | A named dependency prevents meaningful progress. |

Statuses are cumulative only when there is evidence. Record the highest honest
stage and explain gaps in the notes.

## Feature register

This snapshot consolidates `README.md`, `TASKS.md`, and `HANDOFF.md`. Correct it
whenever newer evidence becomes available.

| Feature | Current stage | Evidence / blind-user assessment | Next action |
| --- | --- | --- | --- |
| Read & Explain: OCR fast path plus plain-language explanation | In progress; classifier automated tested | User verified camera and speech on I2305, then reported ordinary captures were frequently described as medicine. Raw-substring classification was replaced with bounded terms and conservative evidence thresholds; eight focused tests pass and the APK is installed. OCR accuracy and corrected spoken classification still await user verification. No blind-user session is recorded. | Re-test an ordinary page and a real medicine label on I2305; record the exact OCR and spoken category without sensitive text. |
| Tap-anywhere and Volume-Up capture | Device verified | Capture and volume-key handling were exercised on Redmi. Large, location-independent input is useful without sight. | Validate discoverability, grip comfort, accidental activation, and one-handed use with blind users. |
| Volume-Down repeat and swipe mode switching | Device verified | Physical recovery path and spoken mode confirmation are reported working on Redmi. | Test while TTS is speaking and after navigation/backgrounding. |
| Speech, haptics, and last-answer recovery | Implemented | Shared speech configuration and response repeat exist. Speech collision and interruption remain important risks. | Add/retain automated checks for ordered speech; test calls, notifications, headphones, and screen lock. |
| First-run spoken tutorial and Assist-provider setup | Implemented | Seven-step tutorial exists; fresh-install device verification is still listed as pending. | Clear app data, complete with TalkBack and screen covered, then observe a blind first-time user. |
| Emergency contact countdown and call | Implemented | User-selected contact and cancellation path exist. The latest rework still needs a complete safe-number device test. | Test cancellation during spoken preamble, duplicate long-press prevention, and one intentional call. Never use 112/108 in tests. |
| SMS inbox triage and scam warnings | Implemented | Offline classification, danger redaction, important-message marking, and replay are described. Physical-device verification is pending. | Seed realistic safe and scam messages; verify ordering, redaction, persistence, and accessible navigation. |
| Voice commands / open app by voice | In progress (parser automated tested) | Four focused tests pass for English mode routing, repeat phrases, reserved commands, and missing-key fallback. Repeat dispatch now reaches existing playback. No current iQOO audio-flow verification. | Verify capture, repeat, stop, TalkBack, haptics, and recognizer failure on connected I2305. |
| Explore voice chat / swipe mode | In progress; control parser automated tested | Voice Chat is the third main swipe mode. Device logs showed forced en-IN repeatedly failed to load its language pack (`error 13`) and then reported no speech. The client now prefers en-US online recognition and spaces restarts to reduce microphone churn. It accumulates speech across pauses and submits after “clear over.” | Re-test on I2305 and inspect the recognized ending phrase. Then test repeat, tap-to-cancel, timeout, and TalkBack. Blind-user validation is pending. |
| Explore / scene description | Implemented; API boundary automated tested; installed | Replaced the failing package stream with a direct authenticated Gemini REST client. It preserves certificate verification, bounds image/prompt input, sanitizes failures, and gives distinct spoken setup, quota, service, photo, and connection recovery. Eleven focused tests pass; corrected APK built, installed, and cold-launched on I2305. An actual scene answer is awaiting user verification. | Capture one non-sensitive scene in Explore, listen for the result, then test airplane-mode recovery and Volume-Down repeat. Add accessible cloud disclosure/consent before wider use. |
| Offline cache | Implemented | Seven-day/LRU design is documented and supports quick repeat results. | Confirm that cached answers are identified when staleness could matter and can be cleared accessibly. |
| On-device language model | Planned; seam refactored + automated tested | Text generation now goes through a single `LlmBackend` interface (`lib/services/llm/`). `GeminiBackend` (cloud) is live; `GemmaBackend` (on-device) is an explicit stub reporting `LlmFailure.unsupported`, so `AIService` falls through to cloud. Five focused tests cover the seam. Feature flag still false; no model bundled; offline claims still unsupported. | Implement `GemmaBackend` with `flutter_gemma` + a quantised model behind the flag; benchmark backends, RAM, heat, latency, airplane-mode on target hardware. Keep the template fallback. |
| English-only localization | Implemented scope decision | English is the supported experience; Tamil assets/dead branches remain. This limits who can benefit. | Keep claims explicit; discuss future languages only after English reliability is validated. |

## Documentation map and trust boundaries

There are enough documents for the current scope; avoid duplicating policy.

| File | Responsibility |
| --- | --- |
| AGENTS.md | Required coding, input-security, privacy, accessibility, and testing rules |
| PROJECT.md | Current status, evidence, decisions, release gaps, and reviews |
| README.md | Architecture and setup; must agree with the tracker |
| TASKS.md | Operational backlog; unchecked items are not completed features |
| DEMO_SETUP.md | This laptop's run steps and physical-device checklist |
| DEMO_FEATURES.md, HACKATHON_README.md, HANDOFF.md | Historical plans/context; not current verification evidence |

The imported Redmi claims above come from historical documents. They have not
been reproduced in this session. I2305 is the model identifier actually observed
through ADB; an iQOO 15 has not been verified here.

## Current priorities

### P0 — prove the core experience

- [ ] Test OCR on a real medicine strip, utility bill, and official notice.
- [ ] Confirm that fast speech starts promptly and never leaves unexplained
      silence while the slow path runs.
- [ ] Re-test emergency cancellation and duplicate-trigger protection with a
      safe nominated number.
- [ ] Verify the first-run tutorial after clearing app data.
- [ ] Verify message danger redaction and important-message replay on device.
- [ ] Run voice input and voice-command flows on the iQOO 15.
- [ ] Conduct at least one observed task session with a blind participant.

### P1 — make offline claims true

- [ ] Integrate and benchmark the on-device explanation model.
- [ ] Measure first-audio latency, total response time, peak RAM, heat, and
      battery impact with the camera active.
- [ ] Test airplane mode, model timeout, process death, and low-memory fallback.
- [ ] Confirm that OCR-only fallback remains complete and understandable.

### P2 — clarity and maintainability

- [ ] Remove stale language branches and resolve conflicting documentation.
- [ ] Add semantics-focused widget tests for every interactive screen.
- [ ] Move visual-only diagnostic information out of the primary experience.
- [ ] Keep generated platform registrant changes separate from feature logic
      where practical.

## Mandatory post-feature review

Complete this review after every user-visible feature or meaningful behavior
change. Do it once after implementation and update it again after device or user
validation. Copy the compact record into the feature log below or link to a
dedicated issue/test note.

### Feature review template

- Feature and date:
- User problem being solved:
- Status stage and evidence:
- Entry point without sight:
- Spoken confirmation and haptic confirmation:
- TalkBack label, role, state, hint, and traversal order:
- Success feedback:
- Failure/timeout feedback:
- Cancel, undo, back, and repeat paths:
- Behavior with screen covered and in a noisy place:
- Privacy or safety risk:
- What I experienced when simulating the task without sight:
- What a blind participant experienced (or `Not yet tested`):
- Does this genuinely improve independence? Why or why not?
- Friction, follow-up work, and owner:

The screen-covered simulation is a development check, not a substitute for a
blind person's lived experience. Never mark a feature `Blind-user validated`
from simulation alone.

## Feature log

Add one row whenever a feature changes stage. Do not rewrite old evidence; add a
new row so decisions remain traceable.

| Date | Feature | New stage | Evidence | Blind-user finding | Follow-up |
| --- | --- | --- | --- | --- | --- |
| 2026-09-05 | Project governance | Implemented | Added this tracker and repository-wide agent rules. | Not applicable; process change only. | Use this log for the next feature change. |
| 2026-09-05 | Documentation safety review | Implemented | Added untrusted-input, cloud disclosure, credential, and dependency rules. Marked historical plans and corrected unsupported README/demo claims. | No user session; documentation work only. | Enforcement and product behavior still need verification. |
| 2026-09-05 | English voice and repeat recovery | In progress; parser automated tested | Four focused tests pass; home dispatch calls existing repeat playback. | Not tested with blind users or TalkBack on I2305. | Phone testing and semantics/audio widget coverage pending; see review below. |
| 2026-09-05 | AI fallback and response collection | Implemented; missing-key automated tested | Missing-key fallback test passes; full stream collection implemented. | Not tested with blind users. | Stream, cancellation, timeout, disclosure, and cloud-answer verification remain pending. |
| 2026-09-05 | Android build setup | Implemented; build verified | Java 17 configured; Gradle/SDK/NDK installed; ARM64 debug APK built successfully. | Not applicable; tooling only. | Initial install failed while disconnected; subsequent install and launch to Android permission prompt succeeded on I2305. Camera/audio flow pending. |

## Suggestions and development areas

This is deliberately a discussion space. Agents and contributors should add
ideas here, including disagreement with the current approach, and raise them
freely with the project owner. Suggestions are not commitments until accepted.

| Suggestion | Why it may help a blind user | Concern / question | Decision |
| --- | --- | --- | --- |
| Test early with several blind users, including different TalkBack experience levels | Reveals discovery, gesture, speech-rate, and trust problems that sighted simulation misses. | Recruitment, consent, and compensation need planning. | Discuss |
| Add optional spoken framing guidance for camera alignment | A blind user cannot know whether a small label is centered, sharp, or affected by glare. | Continuous prompts can become noisy; use concise, actionable cues. | Explore |
| Separate verbatim OCR from model interpretation in speech | Helps the user understand which information was observed and which was inferred. | Extra wording may slow urgent tasks. | Explore |
| Add explicit confidence/uncertainty language for high-stakes results | Prevents a plausible but incorrect explanation from sounding authoritative. | Must stay understandable rather than expose technical scores. | Recommended |
| Design audio-interruption policy | Calls, notifications, and overlapping TTS can hide critical instructions. | Requires careful priority and resume behavior. | Recommended |
| Provide an accessible privacy/history control | Camera text, messages, location, and cached answers may be sensitive. | Clearing data must not erase useful preferences accidentally. | Explore |
| Allow configurable gestures and speech rate | Blind users differ greatly in dexterity, hearing, and screen-reader habits. | More settings increase onboarding burden. | Discuss |

## Open product questions

- What exact task should a first-time user succeed at within the first minute?
- When should the app say “I am not sure” and ask for another capture?
- Should high-stakes explanations always read the source text before giving an
  interpretation?
- How should the app help frame tiny or reflective objects without constant
  speech?
- Which interactions conflict with TalkBack gestures or Android system actions?
- What data should never be cached, and how should expiry be communicated?
- Is the emergency long-press too easy to trigger while stabilizing the phone?

## Known constraints and risks

- OCR on curved, reflective, or tiny print remains a load-bearing unknown.
- Speech recognition does not initialize on the current Redmi test device.
- Cloud explanation requires a private key and does not support an offline
  product claim.
- Model output may invent facts or unsafe next actions.
- TTS queue flushing can clip earlier speech unless sequencing is deliberate.
- Gestures that work with TalkBack disabled may behave differently when it is
  enabled.
- A visual demo can appear successful while the audio-only path is confusing.

## Definition of done

A user-facing feature is done only when:

- The user problem and success behavior are written down.
- The feature has a nonvisual entry point and complete spoken feedback.
- Semantics and TalkBack order are correct.
- Loading, empty, denied-permission, offline, timeout, and failure states speak
  a useful next action.
- Cancellation/recovery is safe and the last important result can be repeated.
- Automated checks appropriate to the change pass.
- The flow is exercised on a physical Android device with the screen covered
  and TalkBack enabled.
- Safety and privacy implications are reviewed.
- This feature register and feature log are updated honestly.
- Blind-user validation is either recorded or explicitly marked as pending.


## Post-feature review — 2026-09-05 demo fixes

- User problem: English commands must reach the two existing modes; a requested
  repeat must replay the last useful answer; missing AI setup must recover.
- Implementation: mode mapping, short repeat parsing, home repeat dispatch,
  missing-key guard, and full response collection exist. Four focused tests pass.
- Nonvisual entry: voice recognition when available, plus existing Volume-Up
  capture and Volume-Down repeat. Established gesture/key mapping is unchanged.
- Spoken/haptic feedback: existing mode/capture announcements and repeat speech
  are reused. Missing-key scene recovery offers Read & Explain. Immediate haptic
  feedback for each voice outcome has not been verified and remains a release gap.
- Semantics/focus: no new widgets. Existing TalkBack labels, traversal, focus on
  return, and dynamic announcements were not tested; widget coverage is pending.
- Success/failure: parser behavior and missing-key null fallback are tested.
  Actual spoken timing, cloud responses, empty OCR, offline behavior, timeouts,
  and permission denial remain unverified on hardware.
- Cancel/back/repeat: existing back and speech controls remain. Repeat dispatch
  is wired; cancellation and speech collision need real-device tests.
- Screen-covered design walkthrough (reasoning only): user learns the controls
  through spoken tutorial, captures with Volume Up, hears text, returns and asks
  for Repeat or uses Volume Down. If cloud setup is absent, scene recovery should
  direct them to Read & Explain. I did not physically cover a phone or hear this
  flow; noise, interruption, framing, and TalkBack conflicts remain unknown.
- Privacy/safety: cloud data disclosure/consent and cache deletion need review.
  An APK-embedded key is prototype-only. No real SMS, calls, payments, or medicine
  decisions were exercised. Do not use model inference as authorization.
- Blind participant experience: Not yet tested.
- Independence assessment: these fixes remove identifiable routing and recovery
  defects; improvement in independent real-world use has not been established.
- Follow-up owner: project team — reconnect I2305, test with TalkBack and the
  screen covered, include failure/cancel/repeat, then arrange blind-user feedback.

## Local verification — 2026-09-05

Subsequent key-setup evidence is recorded under the September 6 update below;
older build and disconnected-device results are retained as history.

- ARM64 debug build: passed; `build/app/outputs/flutter-apk/app-debug.apk`.
- Focused regression tests: 6 passed (voice routing/recovery and explanation
  prompt safety).
- Pure checks: read_explain_logic and sms_classifier both passed.
- `flutter analyze --no-pub`: exit 1, 80 warning/info findings, no error-level
  diagnostics. This is not a clean analyzer gate.
- Legacy widget tests: previous run failed in Mockito setup; not repaired or
  silently skipped as passing. Full suite is not green.
- ADB install: failed with device not found; phone was disconnected. No current
  install, launch, camera, audio, TalkBack, or blind-user validation is claimed.
- Documentation review: policy is strong, but CI enforcement, semantics/audio
  tests, cloud disclosure/consent, and cache privacy controls remain gaps.

## Device verification update — 2026-09-05

- iQOO I2305: ADB install returned Success; explicit activity launch returned Status: ok.
- Startup reached Android GrantPermissionsActivity. Permission choices remain with the user.
- Camera preview, OCR, voice, speech, TalkBack, cancellation, and blind-user validation remain pending.
- Earlier disconnected-install evidence above is retained as history.

| Date | Feature | New stage | Evidence | Blind-user finding | Follow-up |
| --- | --- | --- | --- | --- | --- |
| 2026-09-05 | APK installation and startup | Device verified (installation and permission prompt only) | ADB install Success and cold launch Status: ok on I2305. | Not tested. | User handles permissions; then test non-sensitive notice capture, speech and repeat. |
| 2026-09-05 | Read & Explain default and high-stakes prompt guard | Implemented; automated tested; installed | App starts in the local OCR mode, announces that mode, and the model prompt forbids inferring missing medicine, billing, legal, or identity facts. Six focused tests pass; updated APK installed and cold-launched on I2305. | Not tested with a blind participant. User reported camera and speech worked in the earlier build, but OCR was not exercised because Explore was active without cloud AI. | Capture a non-sensitive printed paragraph; verify raw-text speech, empty-text recovery, repeat, haptic feedback, and TalkBack with the screen covered. |
| 2026-09-05 | Conservative document classification | Implemented; automated tested; installed | User reported most Read & Explain captures received medicine descriptions. Root cause was raw substring matching such as `mg`, plus weak single-term ties. Classifier now uses bounded terms and evidence thresholds; ordinary, medicine, bill, and notice regression cases pass. ARM64 APK rebuilt, installed, and launched on I2305. | Not tested with a blind participant. Corrected spoken result is awaiting user verification. | Test ordinary and medical samples; keep generic when evidence is ambiguous and add sanitized examples for any remaining false labels. |

### Post-feature review — conservative document classification

- Entry, controls, haptics, repeat, and navigation are unchanged.
- A generic classification now avoids speaking an unsupported medical claim;
  actual OCR text is still spoken before any fallible explanation.
- Failure recovery remains “move closer or hold steadier” for empty OCR and a
  partial-result retry cue for very short text.
- No new widget or TalkBack focus behavior was introduced. Spoken category
  behavior, screen-covered use, noisy conditions, and blind-user experience
  remain unverified.
- No captured text was added to logs or tests. Regression inputs are synthetic
  and non-sensitive.

### Post-feature review — Read & Explain default and prompt guard

- Entry without sight: launch announces Read and Explain; tap anywhere or
  Volume Up captures. Swipe still reaches Explore and announces the mode.
- Feedback: capture retains existing haptic/spoken feedback. OCR speaks either
  captured text or an actionable move-closer/hold-steady retry. This needs
  direct listening verification on I2305.
- Trust: interpretation is instructed to use only captured facts and to state
  when high-stakes details cannot be confirmed. Prompt tests pass, but model
  compliance has not been device verified and raw OCR can still be wrong.
- Recovery: Volume Down and the English Repeat command retain the last answer.
  Back returns to the camera. Speech interruption and TalkBack focus remain
  unverified.
- Screen-covered reasoning check: the announced starting mode removes the need
  to visually identify the correct mode before reading. Accurate framing,
  glare, blur, noise, and gesture conflicts remain unknown until physical use.
- Privacy: local OCR is the default path. Cloud explanation still requires a
  separate key and a future spoken disclosure/consent review.
- Blind-user validation: Not yet tested.

## Cloud configuration update — 2026-09-06

- The user saved their key in the tracked example instead of the private file.
  Copied it into the Git-ignored constapi.dart and restored a placeholder in
  constapi.dart.example. No credential value was displayed or recorded here.
- Google accepted authentication and listed the three models used by AIService.
  A short synthetic text request returned text. No user photo, OCR, location,
  or message content was sent during these checks.
- ARM64 debug APK rebuilt successfully with the local configuration.
- Initial installation was blocked by USB authorization. After the user
  authorized I2305, ADB installation succeeded and a cold launch reached
  MainActivity with Status: ok. The cloud-configured APK is now on the phone.
- Scene-image accuracy, spoken results, timeout/cancel, TalkBack, cloud
  disclosure/consent, and blind-user validation remain unverified.

| Date | Feature | New stage | Evidence | Blind-user finding | Follow-up |
| --- | --- | --- | --- | --- | --- |
| 2026-09-06 | Cloud key configuration | Configured; API text smoke check passed | Key found in example, transferred to ignored config; model listing and synthetic generation succeeded; APK rebuilt. | Not tested. | Authorize phone, install, then test a non-sensitive scene and spoken recovery. |
| 2026-09-06 | Cloud-configured APK installation | Device verified (installation/startup only) | ADB install returned Success; cold launch reached MainActivity on I2305 with Status: ok. | Not tested. | User captures a non-sensitive scene in Explore with internet enabled; actual image description and speech remain unverified. |
| 2026-09-06 | Reliable Explore cloud request and spoken failures | Implemented; automated tested; installed | Removed `flutter_gemini`, whose client used a fragile response stream and disabled TLS certificate rejection. Added a bounded REST client with API-key header, sanitized typed failures, and actionable speech. Eleven focused tests pass; analyzer reports no error-level diagnostics; ARM64 APK installed and cold-launched on I2305. | Not tested with a blind participant; real scene output is awaiting user verification. | Test a non-sensitive object, offline recovery, repeat, TalkBack, and speech interruption on I2305. |
| 2026-09-06 | Explore voice-chat loop and recovery | Implemented; automated tested | Start speech is awaited before microphone activation; stop/repeat are local controls; permission, recognizer, network, timeout, and silence paths speak a next action; timers are cancelled on exit. Nine focused tests pass and static analysis has no error-level diagnostics. | Not tested with a blind participant or TalkBack on hardware. | Install on I2305 and test two turns, repeat, spoken stop, silence, and interruption. |
| 2026-09-06 | “Clear over” voice turn completion | Implemented; automated tested | Speech is accumulated across recognizer sessions and sent only when the final phrase is “clear over.” Indian English is preferred when installed; silence resumes listening; tap cancels; a two-minute timeout speaks recovery. Eight focused tests pass and analysis has no error-level diagnostics. | Not tested with a blind participant or on-device recognition accuracy. | Install and test natural speech with pauses on I2305; record misrecognitions of the ending phrase. |
| 2026-09-06 | Voice Chat main swipe mode | Implemented; automated regression tested | Added Voice Chat as mode 3 without changing the swipe gesture contract. One left swipe from the default mode announces it; tap or Volume Up opens auto-listening chat. Eight focused voice regressions pass; analysis has no error-level diagnostics. | Physical swipe discovery and TalkBack traversal are not yet tested. | Install on I2305 and verify announcement, tap, Volume Up, back, and neighboring mode navigation with the screen covered. |

### Post-feature review — reliable Explore request and recovery

- User problem: a valid scene prompt ended with a misleading generic internet
  error, leaving a blind user unable to tell whether the key, quota, service,
  photo, or network needed attention.
- Entry and controls: swipe to Explore or use the existing voice mode command;
  tap anywhere or Volume Up captures. The established interaction contract is
  unchanged, and Volume Down remains the repeat path.
- Feedback: existing capture haptics/loading speech remain. Success is spoken;
  failure now states an actionable setup, quota, invalid-photo, unavailable, or
  connection message without exposing response content or the key.
- Semantics and focus: no widget structure or traversal changed. TalkBack focus,
  speech collision, cancellation during a request, and noisy-place behavior
  still need physical verification.
- Screen-covered reasoning check: the user can enter, capture, hear success or a
  specific recovery step, and repeat without finding a visual control. Camera
  framing remains the largest unresolved nonvisual difficulty.
- Privacy and safety: Explore photos leave the phone for Google Gemini. The new
  client retains normal TLS validation, limits requests to one image of at most
  10 MiB, and does not log keys, prompts, images, or response bodies. The API key
  is still embedded in a prototype APK; spoken disclosure/consent and a server
  credential boundary remain release gaps.
- Automated evidence: 11 focused tests pass. Static analysis completes with the
  repository's existing warning/info backlog and no error-level diagnostics.
  ARM64 build, install, and cold launch pass on I2305.
- Blind participant experience: Not yet tested.
- Independence assessment: specific audible recovery removes an ambiguous dead
  end, but independence is not established until a blind participant completes
  scene capture and failure recovery.

### Post-feature review — Explore voice chat

- Entry without sight: the existing labeled microphone control starts the loop;
  it speaks when voice chat is ready and vibrates immediately before listening.
- Success: speech is retained across pauses and sent once only after the user
  says “clear over.” Gemini's answer is spoken, and the microphone reopens only
  after speech completes.
- Failure and recovery: setup, microphone permission, unavailable recognizer,
  network, no-match, and unexpected-stop paths now speak an actionable result.
  Silence reopens recognition without losing the draft. A two-minute safety
  timeout stops the loop with a spoken recovery message.
- Cancel and repeat: tapping the listening overlay or saying “stop voice chat”
  stops recognition. Saying “repeat” speaks the last answer locally and resumes
  listening; pending restart timers are cancelled during exit/disposal.
- Semantics and focus: the existing microphone tooltip and full-screen live
  listening region remain. TalkBack traversal and focus after each asynchronous
  turn still require device testing.
- Screen-covered reasoning check: the spoken cue, vibration, answer, repeat, and
  stop command allow operation without seeing the waveform or chat transcript.
  Recognition in noise and speech/TalkBack overlap remain physical test risks.
- Privacy: recognized questions and any attached scene image are sent to Google
  Gemini; secrets and content are not added to diagnostics. Accessible cloud
  disclosure/consent remains a release gap.
- Blind participant experience: Not yet tested.

## LLM seam + voice-mode fixes + tour disable — 2026-09-07

Refactor/cleanup pass plus one product change (tutorial no longer auto-plays).

### Changes

- **`LlmBackend` seam.** `lib/services/llm/llm_backend.dart` defines one
  interface (`generate` → typed `LlmResult`/`LlmFailure`, `isReady`,
  `initialize`, `dispose`). `GeminiBackend` wraps the existing bounded REST
  client and owns the model-fallback list. `GemmaBackend` is a stub
  (`isReady == false`, returns `LlmFailure.unsupported`) whose class doc carries
  the full `flutter_gemma` wiring (install → `createModel` → `createChat` →
  `generateChatResponseAsync`) ready to paste. `AIService` now holds one cloud +
  one on-device backend, tries on-device first when ready, and maps
  `LlmFailure` to the same spoken recovery messages as before. Deleted the
  redundant `on_device_llm_service.dart` stub. Wiring a real on-device model —
  which is also what makes the Voice Chat mode run on-device, since that mode
  already routes through `AIService` — is now a change to `GemmaBackend` alone
  plus adding the `flutter_gemma` dependency and a model file.
- **First-run tutorial no longer auto-plays.** `homepage._loadAccessibilitySettings`
  no longer shows the 7-step overlay on launch; a fresh install lands straight
  on the camera and hears the readiness prompt. The tutorial stays reachable on
  demand from Settings > "How to use Logic Legends" (unchanged resume-hook
  path). Overlay/step code is retained, just not triggered at launch.
- **Demo-build cleanup.** Default landed mode is Read & Explain (`_selectedIndex`
  starts at 1) — confirmed, matches the readiness announcement. `DebugOverlay`
  and the floating GPS accuracy badge are now gated to `kDebugMode`, so the
  release/demo APK shows neither (GPS accuracy is still on the AppBar
  indicator). Two remaining "A I For All" spoken strings → "Logic Legends".
- **Voice mode consistency.** `voice_assistant_service` `_switchMode` and the
  command parser now cover all three home modes (0 Explore, 1 Read & Explain,
  2 Voice Chat) — "switch to voice chat" was previously unreachable by voice.
  `homepage._announceModeChange` now reuses `_getModeName` instead of a
  two-element list that would have thrown `RangeError` on mode 2.
  `homepage._captureImageByVoice` clamps the incoming mode.
- **Deprecation + stale strings.** `_startCommandListening` moves
  `listenFor`/`pauseFor` into `SpeechListenOptions` (removes deprecated-arg
  warnings). Settings commands list, debug overlay model label, and two
  "AIFORALL" code comments updated to match the current name and modes.

### Evidence

- `flutter analyze`: 0 error-level diagnostics (78 warning/info, down from 82).
- `flutter test` focused suite: 21 pass — `llm_backend_test.dart` (5, new),
  `voice_commands_test.dart` (5, +1 new voice-chat case), `gemini_api_client`,
  `read_explain_safety`, `voice_chat_logic` unchanged and green.
- Pure self-checks: `read_explain_logic`, `sms_classifier`, `intent_resolver`
  all pass.
- `flutter build apk --debug --target-platform android-arm64`: succeeds.
- **Not done:** device install, TalkBack/screen-covered walkthrough, blind-user
  validation. No behaviour change to capture/repeat/emergency paths, but the
  voice-chat-by-voice route and the mode-name announcement are untested on
  hardware.

| Date | Feature | New stage | Evidence | Blind-user finding | Follow-up |
| --- | --- | --- | --- | --- | --- |
| 2026-09-07 | LLM backend seam | Implemented; automated tested | One `LlmBackend` interface; `GeminiBackend` live, `GemmaBackend` stub; `AIService` refactored; 5 focused tests; analyze clean; arm64 APK builds. | Not applicable; internal refactor, no behaviour change. | Implement `GemmaBackend` with `flutter_gemma` behind the `on_device_llm` flag; benchmark on device. |
| 2026-09-07 | Voice reaches Voice Chat mode + mode-name fix | Implemented; automated tested | Parser + `_switchMode` cover modes 0–2; `_announceModeChange` reuses `_getModeName` (removes a latent `RangeError`); new parser test passes. | Not tested with a blind participant or on hardware. | Verify "switch to voice chat" by voice on I2305 with the screen covered; confirm the spoken mode name and traversal. |
| 2026-09-07 | First-run tutorial disabled at launch | Implemented | `_loadAccessibilitySettings` marks onboarding seen and skips the overlay; `_announceReady()` speaks instead. Settings replay path unchanged. arm64 APK builds. | Not tested on hardware. Confirm a clear-data install lands on the camera and speaks "ready", and that the Settings replay still plays all 7 steps. | Device-verify both paths with the screen covered. |
