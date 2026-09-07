> Historical plan/context: consult PROJECT.md for current verification.
> Offline, accessibility, latency, and device claims below are not current
> acceptance evidence. Follow AGENTS.md safety rules for all new work.

# Logic Legends — iQOO Hackathon 2026 (Chennai) Plan

**User:** blind and low-vision people (also serves low-literacy and elderly users — same flow, no extra build).

**Language: English only.** Scope decision — one language done well. Gemma 2B's non-English generation is weak, and the explanation layer is the whole product, so a second language would degrade the thing that differentiates us.

**What it does that Lookout / Seeing AI / Be My Eyes do not:** they *read text aloud*. We **explain what it means and what to do next** — on-device and offline.

That distinction now carries the entire pitch, so state it in those terms every time: **comprehension, not transcription.** Lookout will read "PARACETAMOL IP 650mg" off a strip. It will not tell you that is a fever tablet, that four a day is the ceiling, or that it expired last month.

> Point at a medicine strip → *"Crocin 650. Paracetamol, for fever and pain. I cannot determine safe dosing from this capture. Verify it with a pharmacist. Expires January 2026."*
>
> Point at a ration-shop notice → *"New ration card applications open September 20. Bring Aadhaar and an income certificate to the office."*

Reading the label is the easy half. Knowing you must not exceed four tablets is the half that matters, and nobody ships it offline.

---

## Two-stage architecture (the core design decision)

A single big multimodal model means 8–15 s of silence and one point of failure. Instead, two paths run from one capture:

| | Fast path | Slow path |
| --- | --- | --- |
| **Does** | extract the text verbatim | explain it in plain language |
| **Uses** | **ML Kit OCR** (on-device, bundled) | **Gemma 2B** (on-device, on the organisers' supported list) |
| **Latency** | ~100–300 ms | 2–6 s, streamed |
| **Speaks** | immediately: *"Crocin 650mg, expiry 01/2026."* | continues: *"This is paracetamol, for fever…"* |

**Why this wins:** first audio in under a second, so the app always feels instant. And it has a floor — if the LLM stalls, crashes, or OOMs, OCR has *already spoken the answer*. The demo cannot go silent.

**Rules:**
- TTS starts on the first complete sentence, never waits for the full generation.
- LLM slower than ~6 s → speak a rule-based template over the OCR text and move on.
- Cache by image hash, so a repeat capture answers instantly.
- Volume-Down always re-speaks the last answer — manual recovery at any moment.

---

## Model plan

**Primary (build this): ML Kit OCR + Gemma 2B via `flutter_gemma`.**
Both on-device. Gemma 2B is explicitly named by the organisers as supported, is ~1.5 GB, and is far less likely to OOM on a hot loaner than a 4.5 GB multimodal model.

**Stretch (only if the spike proves it): Gemma 3n E4B.** Multimodal, would let us describe arbitrary scenes rather than only text. ~4.5 GB, needs ~8 GB RAM, 8–15 s per image. The iQOO 15's 12–16 GB makes it *possible*, not *safe*. Attempt only after the primary path works end to end.

**Fallback ladder if Gemma 2B underperforms:** Phi-3-mini (also supported) → SmolVLM-500M (~0.6 GB, ~7 s) → pure OCR with rule-based templates (still a working product).

### Sept 4 spike — measure, do not assume

1. Does `flutter_gemma` actually place Gemma 2B on the **Hexagon NPU**, or silently fall back to GPU/CPU?
2. **Benchmark `.npu` / `.gpu` / `.cpu`.** The VisionAId paper (arXiv 2607.02371) measured NNAPI at >4200 ms vs ~500 ms CPU-only on some chipsets — unsupported operators. NPU is not automatically faster.
3. **ML Kit OCR accuracy on real printed material** — a medicine strip (tiny type, foil glare) and a notice, under normal phone lighting. Clean digital text is not the test.
4. Peak RAM with the model loaded *and* the camera pipeline running.
5. Check **Qualcomm AI Hub** for pre-optimised Snapdragon weights before quantising anything ourselves.

Do not write "runs on the NPU" in the pitch until step 1 is measured. Say "on-device" until then.

---

## Honesty about what runs where

| Phase | Inference | Why |
| --- | --- | --- |
| **Phase 1 submission video (now)** | Cloud Gemini | Proves the flow and the UX. Labelled as the cloud prototype — no offline claims. |
| **Hackathon build (Sept 12–13)** | On-device ML Kit + Gemma 2B | The graded version. Airplane mode on stage. |

Never claim offline operation in the submission video. Make that claim only after device tests establish the exact offline behavior.

---

## Blind-first interaction (built, needs device testing)

The user never sees the screen, so nothing depends on finding a control.

| Input | Action |
| --- | --- |
| **Tap anywhere** on the viewfinder | Capture |
| **Volume Up** | Capture |
| **Volume Down** | Repeat last spoken answer |
| **Swipe left / right** | Change mode (spoken confirmation) |
| **Hold power button** | Opens the app — registered as an Android ASSIST provider |
| TalkBack | Full semantics on every control |

On launch it speaks: *"AI For All ready. Tap anywhere to read something."*
Every action confirms by haptic **and** voice. Feedback is de-duplicated — never re-speak unchanged information.

**TTS tuning:** ~1.3× rate, slightly lowered pitch. Daily screen-reader users run speech fast, and a lower pitch keeps it distinct from nearby human voices. (Currently 0.5× — fix before the demo.)

---

## Modes — reduced to two

1. **Read & Explain** — medicine, notices, bills, forms, labels, signs. The primary mode; merges the old Text / Documents / Food Labels.
2. **Explore** — general scene description. Only meaningful with the Gemma 3n stretch goal; keep it out of the demo unless it works.

---

## Kept in the build, cut from the demo

Working code, real telemetry for the auto-measured "creative phone use" (15%), but not shown on stage — they dilute a 90-second story:

- Offline SMS triage (OTP / spam / transaction, read aloud)
- GPS reverse-geocode + accuracy badge
- Web-augmented lookups
- Response cache + debug overlay

---

## Scoring the auto-measured criteria

**Creative phone use (15%, HackTracker telemetry)** — exercise these *in normal testing*, not as theatre: camera, torch (low-light label capture), microphone, volume keys, accelerometer (shake to repeat), haptics, GPS at startup, ASSIST launch. All are already wired.

**Office Kit (10%, HackTracker telemetry)** — make it a habit, not a final step. Every 25–30 minutes of laptop time: screen-mirror to debug, shared clipboard for logcat lines and prompts, file transfer for APKs and model files, remote control to tap through a build.

---

## 90-second demo script

Assume one live failure. The fast path carries it.

**0:00–0:15** — *"Airplane mode is on. No cloud."* Hold the power button; the app opens as an Assist provider and speaks *"Ready. Point at a document or medicine."* Pick up a medicine strip.

**0:15–0:40** — Volume Up. Haptic + shutter fire instantly. OCR speaks within a second: *"Crocin 650mg. Expiry 01/2026."* Gemma 2B then streams: *"Paracetamol, for fever and pain. I cannot determine safe dosing from this capture. Verify it with a pharmacist."*

**0:40–1:05** — A government notice or utility bill. Volume Up. OCR reads the dense official wording; the model reduces it to the action: *"Ration card applications open September 20. Bring Aadhaar and income proof."* Say the contrast out loud here — *"a screen reader would have read you four paragraphs of that."*
*If the model stalls here:* "The OCR answer was already spoken — Volume Down repeats the last safe answer. The user is never left in silence." **The failure becomes a feature demonstration.**

**1:05–1:20** — Shake to repeat. Note that every control is a physical gesture: no button to find, nothing to see.

**1:20–1:30** — *"Everything you heard ran on this phone. OCR, the language model, the speech. No cloud, no Wi-Fi, no subscription — so it works anywhere, on a phone someone already owns. And it doesn't just read the label. It tells you what the label means."*

---

## 5-minute demo script (stage) + video walkthrough

The 90-second version above is the elevator pitch. This is the full run for a
5+ minute slot and the submission video. Same beats, more of them.

**Two framings — say the right one:**
- **Stage (Sept 12–13):** "Airplane mode is on." On-device ML Kit + Gemma 2B.
- **Submission video (now):** "This is the cloud prototype." Cloud Gemini.
  **Never say offline in the video.** It remains a goal until device tests establish it.

Assume one live failure somewhere. The fast path carries it — turn it into a
feature demo when it happens.

| Time | Beat | What you do / what it says |
| --- | --- | --- |
| **0:00–0:40** | Problem | A blind person hands their medicine strip, their bank letter, their phone to a sighted relative to know what it says — every day, a loss of privacy and independence. On a phone with no signal, nothing today helps them. |
| **0:40–1:10** | Eyes-free launch | Hold the power button → app opens as the device Assistant, speaks *"Ready. Point at a document or medicine."* Show the gestures by using them: swipe to switch mode (spoken confirmation), explain there is no button to find. |
| **1:10–2:00** | Read & Explain — medicine | Volume Up. Haptic + shutter. OCR speaks in <1 s: *"Crocin 650mg. Expiry 01/2026."* Then the model streams: *"Paracetamol, for fever and pain. I cannot determine safe dosing from this capture. Verify it with a pharmacist."* Contrast out loud: *"a screen reader stops at the first line."* |
| **2:00–2:40** | Read & Explain — government notice | Volume Up. Dense official wording in; one action out: *"Ration card applications open September 20. Bring Aadhaar and an income certificate to the office."* *"That was four paragraphs. It told you the one thing you have to do."* |
| **2:40–3:25** | Read & Explain — bill + pay | A utility bill. It reads the amount and due date, detects the UPI payee printed on it: *"This bill can be paid by U P I. Press and hold anywhere to pay 840 rupees."* Long-press → it speaks the amount + payee → the user's own UPI app opens for the PIN. *"The payment never touches our app. We removed the step where someone else has to read the bill and type the amount."* |
| **3:25–4:20** | Messages + fraud protection | Open the inbox. It reads today's messages, tags each — OTP, transaction, spam — all offline. Hits a scam SMS: **warning first**, refuses to read the link aloud, refuses to read the OTP digits: *"This looks like a scam. It rushes you and contains a link. Do not open it. Ask someone you trust."* Double-tap to mark the electricity-bill reminder important; *"read important messages"* replays just that one. |
| **4:20–4:45** | Explore *(only if the spike proved it)* | Point at the table: *"What's in my hand?"* → spoken description. **If on-device multimodal isn't fast enough, show this on cloud in the video and say so — do not fake it on stage.** |
| **4:45–5:05** | Rehearsed failure | Deliberately stall the model on one capture. *"The OCR answer was already spoken. Volume Down repeats the last safe answer. The user is never left in silence."* The failure is the demo. |
| **5:05–5:30** | Close | *"Everything you heard ran on this phone — the OCR, the language model, the speech, the scam detection. No cloud, no Wi-Fi, no subscription, so it works anywhere on a phone someone already owns. It doesn't just read the label. It tells you what it means — and warns you when something is trying to cheat you."* |

### Video walkthrough — differences from the live run

- **Caption every spoken line on screen** — judges may watch muted, and captions are the accessible choice anyway.
- Show the **airplane-mode toggle** (event) / a **"cloud prototype" title card** (submission) on screen so the claim is visible, not just spoken.
- Picture-in-picture: the physical phone + the real object (strip, bill, letter) in frame — proves it's live, not a mockup.
- Keep it one continuous take per feature. No cuts inside a capture→answer — the latency *is* the point.
- **Recorded on the Redmi:** `speech_to_text` is dead there, so no voice-input beats (double-tap-to-ask, Explore voice chat) in this video. Volume keys, tap, swipe, long-press all work.
- Screen-record with on-device audio capture so the TTS is in the track, not a room mic.

---

## Judging criteria map

| Criterion | Weight | Covered by |
| --- | --- | --- |
| End product quality | 30% | Two-stage architecture with a guaranteed floor; small scope, finished |
| Novelty & impact | 20% | Explains rather than reads — dosage ceiling, expiry, what a notice requires; offline scam warnings for the users scams target most |
| Creative phone use | 15% | Volume keys, ASSIST, shake, torch, haptics, camera, mic, GPS, UPI deep link |
| Technical depth | 15% | On-device OCR + LLM pipeline, streaming TTS, timeout/fallback design, NPU benchmarking |
| Office Kit usage | 10% | Continuous use during Green Light |
| Demo & presentation | 10% | Airplane mode, high-stakes objects, rehearsed failure recovery |

---

## Pre-event checklist

- [ ] Sept 4: run the spike above; record real numbers
- [ ] Fix TTS rate 0.5 → 1.3× and add feedback de-duplication
- [ ] Build the two-stage pipeline; verify the fallback by killing the LLM deliberately
- [ ] Test ML Kit OCR on a real medicine strip and a real printed notice
- [ ] USB stick with Gemma 2B, Phi-3-mini, SmolVLM-500M, Gemma 3n E2B/E4B (~9 GB) — venue wifi will not carry this
- [ ] Verify `flutter build apk --release` (only debug tested so far)
- [ ] Find one blind tester for 20 minutes before Sept 12 — worth more than any feature
- [ ] Rehearse the 90-second script ten times, including the failure branch
- [ ] Rehearse the 5-minute script five times; time each beat, cut anything that runs long
- [ ] Record the video walkthrough with captions (cloud framing, no offline claim)
