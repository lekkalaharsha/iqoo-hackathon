# Run the Android demo on this laptop

Flutter is installed at `C:\flutter`. Flutter's Java setting now points to
`C:\Android\tooling\java17\jdk-17.0.20.1+1`.

## Local AI key

Open `lib/screens/constapi.dart`. Set the constant to your own Gemini key:

```dart
const String GEMINI_API_KEY = 'YOUR_KEY_HERE';
```

This file is ignored by Git. Keep it out of screenshots and recordings.
Without a configured key, local OCR and its fallback can still be tested;
cloud scene descriptions and AI explanations are unavailable.

## Start the app

Connect the phone, unlock it, and allow USB debugging. From the project terminal:

```powershell
C:\flutter\bin\flutter.bat devices
C:\flutter\bin\flutter.bat pub get
C:\flutter\bin\flutter.bat run -d 10BE8B088Q000E3
```

Use the current device ID from `devices` if testing another phone. After changing
the API key, stop and restart the app so Gemini is initialized with the new key.

## Phone checks before recording

1. Allow camera and microphone access when requested.
2. In Explore, capture a well-lit book and bottle. Check that the spoken answer
   matches the actual scene (requires a configured key and internet).
3. Switch to Read & Explain and capture a short printed notice. Check the spoken
   text against the notice, and distinguish OCR from the AI explanation.
4. Return to the home screen. Press Volume Down to repeat the last answer.
5. Activate voice input. Test `Take photo`, `Read text`, `Switch to explore`, and
   `Switch to read and explain`. On the home screen, test `Repeat`.
6. Return to the camera and capture again three times; check recovery and audio.
7. Disable internet and capture a NEW notice to establish the real offline
   behavior. Do not present cached cloud answers as offline scene understanding.

Keep recordings focused on verified behavior. On-device language-model inference
and continuous object detection are not implemented in this build.

## Validation

```powershell
C:\flutter\bin\flutter.bat test test/voice_commands_test.dart
C:\flutter\bin\flutter.bat build apk --debug --no-pub --target-platform android-arm64
```

APK output, after a successful build:
`build/app/outputs/flutter-apk/app-debug.apk`.

The legacy `test/widget_test.dart` currently fails in its Mockito setup and does
not validate the current two-mode interface. The focused command tests cover
parsing and missing-key fallback, not camera, microphone, or cloud behavior.

Build and installation verified on September 5, 2026 on iQOO I2305. Startup reached the Android permission prompt; camera/audio testing remains pending.
Start with a non-sensitive printed notice. Full TalkBack, failure, and cancellation
testing and blind-user validation remain pending; see PROJECT.md.
