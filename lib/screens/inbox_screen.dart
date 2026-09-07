import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:another_telephony/telephony.dart' hide SmsType;
import '../services/sms_classifier.dart';
import '../services/offline_cache_service.dart';
import '../services/speech_config.dart';
import '../services/hardware_keys.dart';
import '../services/emergency_service.dart';

/// Reads the SMS inbox aloud for a blind user, one message at a time, tagged by
/// type and screened for scams. After each message there is a short window to
/// double-tap "this matters" — every message gets a spoken outcome, so the
/// timeout is never a silent decision. When the pass is done, double-tap
/// replays only the important ones.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

enum _Phase { loading, reading, marking, done, empty, denied }

class _Msg {
  final String sender;
  final String body;
  final String key; // stable id for the importance flag
  final SmsResult r;
  bool important;
  _Msg(this.sender, this.body, this.key, this.r, this.important);
}

class _InboxScreenState extends State<InboxScreen> {
  static const _maxMessages = 15;
  static const _markWindow = Duration(milliseconds: 2500);

  final _tts = SpeechConfig.tts;
  final _cache = OfflineCacheService();
  final _telephony = Telephony.instance;

  StreamSubscription<String>? _keySub;
  _Phase _phase = _Phase.loading;
  final _messages = <_Msg>[];
  int _index = 0;
  String _lastSpoken = '';
  bool _windowTapped = false; // set by a double-tap inside the mark window
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _keySub = HardwareKeys.stream.listen((_) {
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      if (EmergencyService().isCountingDown) {
        EmergencyService().cancel();
        return;
      }
      _repeat();
    });
    _run();
  }

  @override
  void dispose() {
    _cancelled = true;
    _keySub?.cancel();
    _tts.stop();
    super.dispose();
  }

  Future<void> _run() async {
    await _cache.initialize();
    // apply() sets sequential mode — one line at a time, `await speak()` blocks.
    await SpeechConfig.apply(_tts);

    if (!await Permission.sms.request().isGranted) {
      setState(() => _phase = _Phase.denied);
      await _say('I could not read your messages. Message permission is off.');
      return;
    }

    HapticFeedback.mediumImpact();
    await _say('Reading your messages.');

    final raw = await _telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
    );
    for (final m in raw.take(_maxMessages)) {
      final sender = m.address ?? 'unknown';
      final body = (m.body ?? '').trim();
      if (body.isEmpty) continue;
      final key = '${sender}_${m.date ?? 0}'.hashCode.toString();
      final flagged = await _cache.getBool('msg_imp_$key');
      _messages.add(_Msg(sender, body, key, classifySms(body), flagged));
    }

    if (_cancelled) return;
    if (_messages.isEmpty) {
      setState(() => _phase = _Phase.empty);
      await _say('Your inbox is empty.');
      return;
    }

    setState(() => _phase = _Phase.reading);
    for (_index = 0; _index < _messages.length; _index++) {
      if (_cancelled) return;
      await _readOne(_messages[_index]);
    }

    if (_cancelled) return;
    final n = _messages.where((m) => m.important).length;
    setState(() => _phase = _Phase.done);
    await _say('That is all ${_messages.length} messages. '
        '$n marked important. '
        'Double tap to hear the important ones again, or go back.');
  }

  Future<void> _readOne(_Msg m) async {
    setState(() => _phase = _Phase.reading);
    final pos = 'Message ${_index + 1} of ${_messages.length}';
    final who = shortSender(m.sender);

    if (m.r.risk == SmsRisk.danger) {
      // Warn first, then read a redacted version — no code digits, no URL.
      await _say('$pos. Warning. ${m.r.warning}');
      await _say('The message, with the risky parts removed, reads: '
          '${_redact(m.body)}');
    } else {
      final lead = switch (m.r.type) {
        SmsType.otp => 'a one-time code from $who',
        SmsType.spam => 'likely spam from $who',
        SmsType.transaction => 'a transaction alert from $who',
        SmsType.normal => 'a message from $who',
      };
      await _say('$pos, $lead. ${m.body}');
      if (m.r.risk == SmsRisk.caution) await _say('Note: ${m.r.warning}');
    }

    if (_cancelled) return;
    setState(() => _phase = _Phase.marking);
    await _say(m.important
        ? 'This is already marked important. Double tap to unmark it.'
        : 'Double tap now if this matters.');

    _windowTapped = false;
    await Future.delayed(_markWindow);
    if (_cancelled) return;

    if (_windowTapped) {
      m.important = !m.important;
      await _cache.setBool('msg_imp_${m.key}', m.important);
      await _say(m.important ? 'Marked important.' : 'Unmarked.');
    } else {
      await _say(m.important ? 'Kept important.' : 'Left unmarked.');
    }
  }

  Future<void> _replayImportant() async {
    final important = _messages.where((m) => m.important).toList();
    if (important.isEmpty) {
      await _say('Nothing is marked important.');
      return;
    }
    await _say('${important.length} important messages.');
    for (final m in important) {
      if (_cancelled) return;
      await _say('From ${shortSender(m.sender)}. '
          '${m.r.risk == SmsRisk.danger ? _redact(m.body) : m.body}');
    }
  }

  // --- gestures ---------------------------------------------------------------

  void _onDoubleTap() {
    if (_phase == _Phase.marking) {
      _windowTapped = true;
      HapticFeedback.selectionClick();
    } else if (_phase == _Phase.done) {
      _replayImportant();
    }
  }

  Future<void> _repeat() async {
    if (_lastSpoken.isEmpty) return;
    await _tts.stop();
    await _tts.speak(_lastSpoken);
  }

  Future<void> _say(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    _lastSpoken = t;
    SpokenText.last = t; // keep the app-wide Volume-Down repeat in sync
    await _tts.speak(t);
  }

  /// Strip URLs and long digit runs (OTP codes) so a scam message can be read
  /// without handing the user the thing the scammer wants them to act on.
  String _redact(String body) => body
      .replaceAll(RegExp(r'https?://\S+|www\.\S+|\b\S+\.(?:com|net|in|xyz|top|link|click)\S*',
          caseSensitive: false), 'a web link')
      .replaceAll(RegExp(r'(?<!\d)\d{4,8}(?!\d)'), 'a code');

  // --- ui (screen-second: for a sighted helper / judge) --------------------

  String get _status => switch (_phase) {
        _Phase.loading => 'Loading messages…',
        _Phase.reading => 'Reading ${_index + 1} of ${_messages.length}',
        _Phase.marking => 'Double-tap if important',
        _Phase.done => 'Done — double-tap to replay important',
        _Phase.empty => 'Inbox empty',
        _Phase.denied => 'Message permission off',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: Semantics(
        liveRegion: true,
        label: _status,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _repeat,
          onDoubleTap: _onDoubleTap,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(_status, style: const TextStyle(fontWeight: FontWeight.bold)),
              const Divider(height: 24),
              for (var i = 0; i < _messages.length; i++)
                _tile(_messages[i], i),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(_Msg m, int i) {
    final danger = m.r.risk == SmsRisk.danger;
    final caution = m.r.risk == SmsRisk.caution;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: danger
            ? Colors.red.withValues(alpha: 0.12)
            : caution
                ? Colors.orange.withValues(alpha: 0.10)
                : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: i == _index && _phase != _Phase.done
            ? Border.all(color: Colors.blue, width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (m.important)
                const Icon(Icons.star, size: 16, color: Colors.amber),
              if (danger)
                const Icon(Icons.warning, size: 16, color: Colors.red),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${shortSender(m.sender)} · ${m.r.type.name}'
                  '${danger ? ' · SCAM?' : caution ? ' · check' : ''}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(m.body, style: const TextStyle(fontSize: 15)),
          if (m.r.warning != null) ...[
            const SizedBox(height: 4),
            Text(m.r.warning!,
                style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: danger ? Colors.red[800] : Colors.orange[900])),
          ],
        ],
      ),
    );
  }
}
