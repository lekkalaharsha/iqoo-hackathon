import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// One place to tune how the app sounds.
///
/// Daily screen-reader users run speech considerably faster than the default,
/// and a slightly lowered pitch keeps the app distinct from nearby human
/// voices. Values are deliberately in one file: four screens/services used to
/// each hardcode their own, which drifted.
class SpeechConfig {
  /// One shared engine each. Android allows a single active SpeechRecognizer,
  /// and multiple FlutterTts instances speak over each other — every screen and
  /// service used to `new` its own. Use these instead.
  static final FlutterTts tts = FlutterTts();
  static final stt.SpeechToText speech = stt.SpeechToText();

  /// flutter_tts on Android does NOT map 1.0 to the engine's natural pace — its
  /// scale runs hot, so 1.0 already sounds rushed and ~0.5 is a normal talking
  /// speed. iOS uses 0.0–1.0 with ~0.5 as normal.
  /// ponytail: this is the calibration knob — comfortable speed is personal and
  /// it's the one number a blind tester will comment on. Nudge, rebuild, listen.
  static double get rate => Platform.isIOS ? 0.5 : 0.4;

  /// Slightly below neutral so it does not blend with people talking nearby.
  static const double pitch = 0.9;

  static const double volume = 1.0;

  // --- TTS health safety net ---------------------------------------------------
  //
  // On several test phones Google TTS is installed but its offline English
  // voice data is incomplete/corrupt: every speak() spins ~7s and produces no
  // audio ("synthesizeWithoutLoadingVoice() failed"), and the engine lies about
  // which voices it can serve. The app can't fix a broken engine, but it can:
  //   1. prefer a voice whose name isn't one of the known-broken neural packs,
  //   2. probe the engine once (silent synthesize-to-file) to learn if it can
  //      actually produce audio, and
  //   3. expose that so a screen can tell the user what to do instead of just
  //      going silent for 7 seconds a line.

  /// null = not checked yet, true = the engine produced a probe render,
  /// false = no usable English voice / the probe failed or timed out.
  static final ValueNotifier<bool?> ttsHealthy = ValueNotifier<bool?>(null);

  static const String ttsBrokenAdvice =
      'Text to speech is not working on this phone. Open Settings, '
      'Text-to-speech output, and reinstall the English voice data.';

  /// Substrings of the neural voice packs that fail to synthesize on the broken
  /// installs we have seen. Prefer anything else when picking a voice.
  static const List<String> _brokenVoiceMarkers = [
    'lstm',
    'seanet',
    'iog',
    'hol',
    'network',
  ];

  static Future<void>? _probe;

  /// Applies rate/pitch/volume and the **sequential** speech mode: one utterance
  /// at a time, and `await tts.speak(x)` blocks until x finishes. This is what
  /// almost every caller wants. Streaming callers must follow with [streaming].
  ///
  /// Also runs the one-time TTS health check (see [ttsHealthy]); the first call
  /// waits for it, later calls are cheap.
  ///
  /// Always en-US: en-IN is frequently a network-only voice on Indian devices —
  /// speak() reports success and produces no audio.
  ///
  /// The mode matters because [tts] is a single shared engine ([SpeechConfig.tts]).
  /// QUEUE_ADD + awaitSpeakCompletion together make `speak()` NOT block on
  /// Android, so a screen left in that mode would let the next screen's lines
  /// stomp each other. Calling apply() on entry resets that.
  static Future<void> apply(FlutterTts tts) async {
    await tts.setLanguage('en-US');
    await _preferHealthyVoice(tts);
    await tts.setSpeechRate(rate);
    await tts.setPitch(pitch);
    await tts.setVolume(volume);
    await tts.setQueueMode(0); // QUEUE_FLUSH
    await tts.awaitSpeakCompletion(true);
    _probe ??= _probeEngine(tts);
    await _probe;
  }

  /// Streaming mode: queue utterances (QUEUE_ADD) and let them play back to back
  /// without `speak()` blocking. For sentence-by-sentence readout where the
  /// caller does not await each line. Call [apply] first, then this.
  static Future<void> streaming(FlutterTts tts) async {
    await tts.setQueueMode(1); // QUEUE_ADD
    await tts.awaitSpeakCompletion(false);
  }

  /// Pick an en-US voice that is not one of the known-broken neural packs, and
  /// prefer one that does not need the network. Best-effort: any failure leaves
  /// the engine on its own default. Sets [ttsHealthy] to false only when there
  /// is no English-US voice at all.
  static Future<void> _preferHealthyVoice(FlutterTts tts) async {
    try {
      final raw = await tts.getVoices;
      if (raw is! List) return;

      final enUs = raw
          .whereType<Map>()
          .where((v) => _str(v, 'locale')
              .toLowerCase()
              .replaceAll('-', '_')
              .startsWith('en_us'))
          .toList();

      if (enUs.isEmpty) {
        ttsHealthy.value = false;
        return;
      }

      bool broken(Map v) {
        final n = _str(v, 'name').toLowerCase();
        return _brokenVoiceMarkers.any(n.contains);
      }

      bool offline(Map v) {
        final nr = _str(v, 'network_required').toLowerCase();
        return nr == '0' || nr == 'false' || nr.isEmpty;
      }

      final pick = _firstOrNull(enUs.where((v) => !broken(v) && offline(v))) ??
          _firstOrNull(enUs.where((v) => !broken(v)));
      if (pick == null) return; // only broken packs — the probe will confirm

      await tts.setVoice({
        'name': _str(pick, 'name'),
        'locale':
            _str(pick, 'locale').isEmpty ? 'en-US' : _str(pick, 'locale'),
      });
    } catch (e) {
      debugPrint('SpeechConfig: voice selection skipped: $e');
    }
  }

  /// Silent one-time check: render a short phrase to an app-private file (no
  /// audio played) and confirm the engine both *completed* it and wrote a
  /// non-trivial WAV. The broken installs "complete" a synthesis but leave an
  /// empty file, so the size check is the part that actually catches them.
  static Future<void> _probeEngine(FlutterTts tts) async {
    if (ttsHealthy.value == false) {
      _installSteadyErrorHandler(tts);
      return;
    }
    final done = Completer<bool>();
    void finish(bool ok) {
      if (!done.isCompleted) done.complete(ok);
    }

    tts.setCompletionHandler(() => finish(true));
    tts.setErrorHandler((dynamic m) {
      debugPrint('SpeechConfig: TTS probe error: $m');
      finish(false);
    });

    File? probe;
    try {
      final dir = await getTemporaryDirectory();
      probe = File('${dir.path}/ll_tts_probe.wav');
      if (probe.existsSync()) probe.deleteSync();

      unawaited(tts.synthesizeToFile(
          'logic legends assistant', probe.path, true /* isFullPath */));
      final completed = await done.future
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
      final bytes = probe.existsSync() ? probe.lengthSync() : 0;
      ttsHealthy.value = completed && bytes > 2048;
      debugPrint('SpeechConfig: TTS probe completed=$completed bytes=$bytes '
          '-> healthy=${ttsHealthy.value}');
    } catch (e) {
      debugPrint('SpeechConfig: TTS probe threw: $e');
      ttsHealthy.value = false;
    } finally {
      try {
        probe?.deleteSync();
      } catch (_) {}
      tts.setCompletionHandler(() {});
      _installSteadyErrorHandler(tts);
    }
  }

  static void _installSteadyErrorHandler(FlutterTts tts) {
    tts.setErrorHandler((dynamic m) {
      debugPrint('SpeechConfig: TTS error: $m');
      ttsHealthy.value = false;
    });
  }

  static String _str(Map v, String key) => (v[key] ?? '').toString();

  static T? _firstOrNull<T>(Iterable<T> it) {
    final i = it.iterator;
    return i.moveNext() ? i.current : null;
  }
}
