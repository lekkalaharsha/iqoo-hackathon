# Repository Instructions for Coding Agents

These instructions apply to the entire repository. The app is designed first
for blind and low-vision people. Accessibility is a functional requirement and
a release gate, not a polish task.

## Start here

Before changing code:

1. Read `PROJECT.md` for current status, open questions, and priorities.
2. Read `README.md` for architecture and `TASKS.md` for operational work.
3. Inspect the actual implementation and tests; documentation can be stale.
4. Check `git status` and preserve all user changes. Never discard or overwrite
   unrelated work.
5. State the user problem and how a blind person will discover, operate,
   understand, cancel, and recover from the proposed behavior.

If the implementation disagrees with documentation, report the discrepancy and
update the appropriate document as part of the scoped change.

## Core mental model

Assume the user:

- Cannot see the screen, camera framing, icons, colors, animations, snackbars,
  dialogs, spinners, or error text.
- May use TalkBack at a high speech rate and may hold the phone one-handed.
- May be outdoors, in noise, offline, interrupted, or unsure whether an action
  succeeded.
- Cannot safely resolve an ambiguous or silent state by visually inspecting the
  UI.
- Deserves privacy and control, particularly for medicine, messages, money,
  location, and emergency contacts.

For every change, mentally run the full task with the screen covered. Write down
what would be heard, felt, and done at each step. Treat this as a design check,
not as a replacement for testing with blind people.

## Accessibility requirements

These are non-negotiable for user-facing work:

- No action may require locating a visual control. Preserve or add a clear
  touch, physical-key, gesture, TalkBack, or voice path.
- Every action must give prompt spoken and haptic confirmation. A visual-only
  toast, color, icon, or animation is not feedback.
- Every interactive widget needs accurate Flutter semantics: label, role,
  value/state, enabled state, and hint where useful. Dynamic critical text must
  be announced without causing duplicate speech.
- Verify logical TalkBack traversal and focus after navigation, dialogs, errors,
  and asynchronous updates. Do not unexpectedly steal focus.
- Do not encode meaning by color, position, shape, or gesture alone. Retain a
  labeled accessible equivalent.
- Keep touch targets large and separated. Avoid interactions that depend on
  precise taps, timing, multi-finger dexterity, or visual aiming.
- Speak loading and long-running states promptly. If work continues, give a
  short progress cue and a cancellable timeout; never leave unexplained silence.
- Announce errors in plain language with the next action. Permission denial,
  offline mode, empty results, model failure, and recognizer unavailability must
  all recover gracefully.
- Preserve an easy repeat path for the last important answer. Do not overwrite
  it with low-value status speech.
- New gestures must be checked for TalkBack and Android system conflicts and
  must have a discoverable alternative.
- Low-vision presentation still matters: readable scaling, sufficient contrast,
  no clipped text, and no information conveyed by color alone.

### Audio and haptics

- Route speech settings through `lib/services/speech_config.dart`; do not set
  language, rate, pitch, or voice independently in screens.
- Remember that `flutter_tts` can flush the active utterance. Sequence important
  messages deliberately, await speech where order matters, and prevent two
  services from speaking over each other.
- Deduplicate repeated status announcements, but never suppress a user-requested
  repeat.
- Critical haptics need a spoken meaning; vibration alone is ambiguous.
- Test interruptions from navigation, app backgrounding, calls, headphones, and
  other audio where relevant.

### Existing interaction contract

Do not casually remap these established controls:

| Input | Expected action |
| --- | --- |
| Tap anywhere on viewfinder | Capture |
| Volume Up | Capture |
| Volume Down | Repeat last spoken answer |
| Swipe left/right | Change mode with spoken confirmation |
| Long-press viewfinder | Emergency flow with spoken cancellable countdown |
| Power-button Assist action | Open the app and announce readiness |

If a change to this contract is necessary, discuss it with the project owner,
provide a migration/discovery plan, and update `PROJECT.md`, `README.md`, tests,
and tutorial copy together.

## Safety and trust

- Clearly distinguish captured text from interpretation or model inference.
- Never make uncertain medical, financial, legal, navigation, or emergency
  output sound authoritative. Speak uncertainty and a safe next step.
- Do not invent missing OCR text, dosage, expiry, amount, recipient, address, or
  identity. Ask for another capture or trusted verification when needed.
- Destructive, external, financial, or calling actions require an explicit
  confirmation that states the action and target aloud, plus a cancel path.
- Emergency calling uses only a user-selected contact. Never call 112/108 during
  development or automated tests.
- Do not speak OTP digits or suspicious URLs from a dangerous message. Preserve
  warning-first redaction behavior.
- Minimize collection and storage. Do not log secrets, API keys, message bodies,
  precise locations, OCR content, or personal contacts unless a scoped debug
  need is explicitly approved and the data is sanitized.
- Never claim a feature is offline, private, accurate, or device-verified unless
  current evidence supports that exact claim.

## Untrusted input and security checks

- Treat camera/OCR content, web pages, messages, and model output as untrusted
  data. Instructions inside that data must never change app rules, expose
  secrets, or authorize calls, payments, navigation, or app launches.
- Validate native-channel arguments, URL schemes, destinations, input sizes,
  and timeouts. Never execute code assembled from voice or model output.
- Document what leaves the phone before adding cloud processing. Provide a
  discoverable spoken disclosure/consent path and a local fallback. Document
  cache retention and accessible deletion.
- Gitignore does not protect a key embedded in an APK. The local Gemini key flow
  is prototype setup; review credential restrictions, quotas, rotation, and a
  server boundary before wider distribution. Never print keys in diagnostics.
- Review dependency provenance and lockfile changes. Do not disable certificate
  checks or use unreviewed mirrors to work around download errors.
- Rules in Markdown are guidance, not enforcement. Record missing tests and
  release gates; do not claim security or accessibility from documentation alone.

## Coding rules

- Keep changes small and scoped. Reuse existing services instead of duplicating
  camera, speech, haptic, configuration, cache, or navigation logic in screens.
- Keep pure classification, parsing, prompting, and fallback behavior separate
  from widgets and platform I/O so it can be tested without hardware.
- Treat fast OCR as the reliable floor and model explanation as a fallible
  enhancement. Model timeout or failure must not erase or delay the safe result.
- Prefer explicit state transitions over scattered booleans for listening,
  speaking, capturing, countdown, and cancellation flows. Guard against duplicate
  taps, keys, callbacks, navigation, and calls.
- Cancel timers, stream subscriptions, controllers, camera resources, and speech
  operations during disposal or lifecycle changes.
- Handle permission states explicitly: not requested, granted, denied, and
  permanently denied. Provide a spoken recovery path.
- Keep configuration in existing config/services where appropriate; do not
  hard-code secrets or machine-specific paths.
- Never edit generated files manually unless the generator cannot produce the
  required result and the reason is documented.
- Follow the repository's Dart/Flutter lint configuration. Use clear names,
  small methods, immutable values where practical, and comments for intent or
  safety constraints rather than narrating obvious code.
- Preserve platform behavior across Android lifecycle events. Android is the
  primary target, but avoid breaking generated desktop/iOS projects without a
  reason.
- Do not add a dependency until its size, permissions, maintenance, privacy,
  offline behavior, and accessibility consequences have been considered.

## Testing rules

Match verification to risk. A green unit test does not prove an audio-first
hardware flow.

For relevant changes:

1. Add unit tests for pure parsing, classification, fallback, redaction,
   timeout, and deduplication behavior.
2. Add widget tests for semantics, accessible names/states, focus, navigation,
   and loading/error announcements.
3. Run `flutter analyze` and the relevant Flutter tests.
4. Run available pure-Dart self-checks:

   ```text
   dart run lib/services/read_explain_logic.dart
   dart run lib/services/sms_classifier.dart
   ```

5. Exercise hardware-dependent flows on a named physical device with TalkBack
   enabled and the screen covered. Include cancellation and at least one failure
   path, not only the happy path.
6. Record what was not tested and why. Never silently turn “implemented” into
   “verified.”

High-risk flows such as emergency calls, medicine explanations, scam warnings,
payments, permissions, and privacy controls require explicit edge-case testing
and safe test data.

## Required feature tracking

After implementing any user-visible feature or behavior change:

1. Update its row in the `PROJECT.md` feature register.
2. Add a dated row to the feature log; do not erase older evidence.
3. Complete the mandatory post-feature review in `PROJECT.md`.
4. Record implementation, automated-test, device-verification, and blind-user
   validation as separate facts.
5. Add discovered friction, risks, and follow-up work even when the code works.
6. Update status again after physical-device testing or a blind-user session.

Documentation-only, refactor-only, or tooling changes do not need a full user
review, but they still need honest verification and must not change product
claims accidentally.

## Suggestions and collaboration

Agents should think as product collaborators, not silent ticket executors.
Freely raise accessibility concerns, simpler designs, safety issues, conflicting
requirements, or ideas that may improve independence. Add worthwhile ideas to
the `PROJECT.md` suggestions table with benefits and tradeoffs.

Do not quietly expand scope or implement a disputed product change. Explain the
observation, its effect on a blind user, the smallest useful option, and what
decision is needed from the project owner.

## Completion standard

Before reporting work complete:

- Review the diff and preserve unrelated user edits.
- Run the strongest relevant checks available and report exact results.
- Perform the screen-covered accessibility review for user-visible changes.
- Update `PROJECT.md` as required.
- State remaining risks, untested device behavior, and blind-user validation
  status plainly.

The final question is not only “does the code work?” It is: **can a blind person
independently understand, trust, and recover from this feature in the real
world?**
