import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'gps_service.dart';
import 'localization_service.dart';
import 'speech_config.dart';

/// Calls a user-nominated emergency contact, with a spoken countdown that can
/// be cancelled.
///
/// Deliberately does NOT dial 112/108. An accidental shake or a misheard voice
/// command must never summon emergency services — the contact is someone the
/// user chose, and the countdown gives them time to stop it.
class EmergencyService {
  static final EmergencyService _instance = EmergencyService._internal();
  factory EmergencyService() => _instance;
  EmergencyService._internal();

  static const _channel = MethodChannel('aiforall/phone');
  static const _prefsKey = 'emergency_contact';
  static const _labelKey = 'emergency_contact_label';
  static const countdownSeconds = 5;

  final FlutterTts _tts = SpeechConfig.tts;
  final GPSService _gps = GPSService();
  final LocalizationService _localization = LocalizationService();

  Timer? _timer;
  // True from the moment trigger() commits (contact found) until the call is
  // placed or cancel() runs — covers the spoken preamble as well as the visible
  // countdown, so a tap/key during the preamble aborts too.
  bool _armed = false;
  bool _cancelled = false;
  bool get isCountingDown => _armed;

  static Future<String?> getContact() async =>
      (await SharedPreferences.getInstance()).getString(_prefsKey);

  static Future<void> setContact(String number) async =>
      (await SharedPreferences.getInstance()).setString(_prefsKey, number);

  /// Optional name spoken instead of "your emergency contact" ("Calling Amma").
  static Future<String?> getContactLabel() async =>
      (await SharedPreferences.getInstance()).getString(_labelKey);

  static Future<void> setContactLabel(String label) async {
    final p = await SharedPreferences.getInstance();
    final t = label.trim();
    if (t.isEmpty) {
      await p.remove(_labelKey);
    } else {
      await p.setString(_labelKey, t);
    }
  }

  /// Speaks the user's location, then counts down and calls.
  /// [onTick] reports seconds remaining so the UI can show it.
  Future<void> trigger({void Function(int)? onTick}) async {
    final number = await getContact();
    // apply() forces sequential mode (QUEUE_FLUSH + await-completion). Critical
    // here: the preamble and the "tap to stop" line MUST finish before the
    // 1-second countdown Timer starts, or the call can be placed before the user
    // has heard they can cancel. The shared engine may arrive in QUEUE_ADD.
    await SpeechConfig.apply(_tts);

    if (number == null || number.isEmpty) {
      await _speak(_localization.isTamil
          ? 'அவசர தொடர்பு எண் அமைக்கப்படவில்லை. அமைப்புகளில் சேர்க்கவும்.'
          : 'No emergency contact is set. Add one in settings.');
      return;
    }

    _armed = true;
    _cancelled = false;
    var remaining = countdownSeconds;
    onTick?.call(remaining);

    // Location first — it is the useful part even if the call never connects.
    // Re-check _cancelled after each spoken line: the preamble takes seconds and
    // the overlay/keys say "tap to cancel" the whole time.
    await _speak(await _locationSentence());
    if (_cancelled) return;

    final label = await getContactLabel();
    final who = (label == null || label.isEmpty)
        ? 'your emergency contact'
        : label;
    await _speak(_localization.isTamil
        ? 'அவசர அழைப்பு $remaining வினாடிகளில். நிறுத்த திரையைத் தட்டவும்.'
        : 'Calling $who in $remaining seconds. Tap the screen to stop.');
    if (_cancelled) return;

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (_cancelled) {
        t.cancel();
        return;
      }
      remaining--;
      onTick?.call(remaining);
      if (remaining <= 0) {
        t.cancel();
        _armed = false;
        await _placeCall(number);
      }
    });
  }

  /// Any tap / key press during the preamble or countdown stops it.
  Future<void> cancel() async {
    if (!_armed) return;
    _cancelled = true;
    _armed = false;
    _timer?.cancel();
    _timer = null;
    await _tts.stop();
    await _speak(_localization.isTamil
        ? 'அவசர அழைப்பு ரத்து செய்யப்பட்டது.'
        : 'Emergency call cancelled.');
  }

  Future<void> _placeCall(String number) async {
    if (_cancelled) return;
    try {
      final placed =
          await _channel.invokeMethod<bool>('call', {'number': number});
      if (placed != true) {
        await _speak(_localization.isTamil
            ? 'டயலரைத் திறக்கிறது. அழைக்க பச்சை பொத்தானை அழுத்தவும்.'
            : 'Opening the dialler. Press the green button to call.');
      }
    } on PlatformException catch (_) {
      await _speak(_localization.isTamil
          ? 'அழைப்பு தோல்வியடைந்தது.'
          : 'The call could not be placed.');
    }
  }

  Future<String> _locationSentence() async {
    final pos = _gps.getLastKnownPosition();
    final address = _gps.getLastKnownAddress();
    if (pos == null) {
      return _localization.isTamil
          ? 'அவசரம். இருப்பிடம் தெரியவில்லை.'
          : 'Emergency. Location is not available.';
    }
    final lat = pos.latitude.toStringAsFixed(5);
    final lon = pos.longitude.toStringAsFixed(5);
    return _localization.isTamil
        ? 'அவசரம். நீங்கள் ${address ?? ''} இல் உள்ளீர்கள். அட்சரேகை $lat, தீர்க்கரேகை $lon.'
        : 'Emergency. You are at ${address ?? 'an unknown address'}. '
            'Latitude $lat, longitude $lon.';
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  /// Ask for CALL_PHONE up front so the countdown does not stall on a dialog.
  static Future<void> ensurePermission() async {
    try {
      final has = await _channel.invokeMethod<bool>('hasCallPermission');
      if (has != true) await _channel.invokeMethod('requestCallPermission');
    } on PlatformException catch (_) {/* dialler fallback still works */}
  }

  void dispose() {
    _timer?.cancel();
    _tts.stop();
  }
}
