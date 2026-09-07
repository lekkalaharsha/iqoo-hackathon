import 'dart:async';
import 'dart:io';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import '../services/ai_service.dart';
import '../services/localization_service.dart';
import '../services/offline_cache_service.dart';
import '../services/config_service.dart';
import '../services/hardware_keys.dart';
import '../services/speech_config.dart';
import '../services/emergency_service.dart';
import '../services/voice_chat_logic.dart';

class Chatscreen extends StatefulWidget {
  final String? imagePath;
  final String? prompt;
  final Map<String, dynamic>? locationData;
  final bool autoStartVoice;

  const Chatscreen({
    super.key,
    this.imagePath,
    this.prompt,
    this.locationData,
    this.autoStartVoice = false,
  });

  @override
  State<Chatscreen> createState() => _ChatscreenState();
}

class _ChatscreenState extends State<Chatscreen> {
  final AIService _aiService = AIService();
  final LocalizationService _localization = LocalizationService();
  final OfflineCacheService _cacheService = OfflineCacheService();
  final ConfigService _configService = ConfigService();
  final FlutterTts _tts = SpeechConfig.tts;
  final stt.SpeechToText _stt = SpeechConfig.speech;
  StreamSubscription<String>? _keySub;

  List<ChatMessage> messages = [];
  bool _isLoading = false;
  String? _lastAIResponse;
  String? _imageHash;

  // Push-to-talk voice chat: hold anywhere on the screen to listen, release to
  // send that turn. The answer is spoken aloud; the next turn is another hold.
  // (Replaces a mic toggle + a spoken "clear over" terminator.)
  bool _sttReady = false;
  bool _sttSetupComplete = false;
  bool _holding = false; // finger is down for push-to-talk
  bool _listening = false; // mic is open
  String _pttWords = ''; // latest transcription for the current hold
  String? _speechLocaleId;

  ChatUser currentUser = ChatUser(id: "0", firstName: "User");
  ChatUser geminiUser = ChatUser(
    id: "1",
    firstName: "Logic Legends",
    // No profileImage: the asset was never bundled (no `assets:` in pubspec),
    // so dash_chat_2 falls back to the initials avatar.
  );

  @override
  void initState() {
    super.initState();
    // Either volume key re-speaks the last answer — or aborts a running
    // emergency countdown (it can be armed from any screen).
    _keySub = HardwareKeys.stream.listen((_) {
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      if (EmergencyService().isCountingDown) {
        EmergencyService().cancel();
        return;
      }
      _speakLastResponse();
    });
    _initializeServices();
    if (widget.imagePath != null) {
      _computeImageHash(widget.imagePath!);
      _sendMediaMessage(widget.imagePath!);
    }
  }

  Future<void> _initializeServices() async {
    await _configService.initialize();
    await _localization.initialize();
    await _aiService.initialize();
    await _cacheService.initialize();
    await _setupTTS();
    await _setupStt();
    if (widget.autoStartVoice && mounted) {
      await _speak(_sttReady
          ? 'Voice chat. Hold anywhere on the screen and speak. Release to send.'
          : 'Voice recognition is not available on this phone. You can type your message instead.');
    }
  }

  Future<void> _setupStt() async {
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      _sttSetupComplete = true;
      if (mounted) setState(() {});
      return;
    }
    try {
      _sttReady = await _stt.initialize(
        onStatus: (s) {
          // The recogniser closed the session (silence, or our stop() on
          // release). Nothing to restart — the next turn is another hold.
          if (s == 'done' || s == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
        onError: (error) {
          final code = error.errorMsg;
          if (mounted) setState(() => _listening = false);
          // "no_match" / "speech_timeout" just means nothing was heard during
          // the hold — _endHold() already tells the user. Only surface the
          // harder failures.
          if (code.contains('no_match') || code.contains('speech_timeout')) {
            return;
          }
          if (!_holding) return; // stale error after release
          HapticFeedback.heavyImpact();
          _speak(_speechErrorMessage(code));
        },
      );
      if (_sttReady) {
        final locales = await _stt.locales();
        final usEnglish = locales.where((locale) =>
            locale.localeId.toLowerCase().replaceAll('-', '_') == 'en_us');
        final english = locales
            .where((locale) => locale.localeId.toLowerCase().startsWith('en'));
        _speechLocaleId = usEnglish.isNotEmpty
            ? usEnglish.first.localeId
            : (english.isNotEmpty ? english.first.localeId : null);
      }
    } catch (_) {
      _sttReady = false;
    }
    _sttSetupComplete = true;
    if (mounted) setState(() {});
  }

  /// Finger down anywhere on the screen — open the mic and keep it open until
  /// the finger lifts. No pause/length limit: the user decides when the turn
  /// ends by releasing.
  Future<void> _startHold() async {
    if (_holding || _listening || _isLoading) return;
    if (!_sttSetupComplete) {
      await _speak('Voice input is still getting ready. Try again in a moment.');
      return;
    }
    if (!_sttReady) {
      final permission = await Permission.microphone.status;
      await _speak(permission.isPermanentlyDenied
          ? 'Microphone permission is blocked. Enable it in Android app settings.'
          : permission.isDenied
              ? 'Microphone permission is required for voice chat. Allow it, then try again.'
              : 'Voice recognition is not available on this phone. You can still type a message.');
      return;
    }
    _holding = true;
    _pttWords = '';
    await _tts.stop(); // barge in over any answer being read
    if (!_holding) return; // released during the await
    setState(() => _listening = true);
    HapticFeedback.mediumImpact();
    await _stt.listen(
      onResult: (r) => _pttWords = r.recognizedWords.trim(),
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        onDevice: false,
        // Long ceilings — the release, not a timer, ends the turn.
        listenFor: const Duration(seconds: 120),
        pauseFor: const Duration(seconds: 120),
        localeId: _speechLocaleId,
      ),
    );
  }

  /// Finger lifted (or the long-press was cancelled). Stop the mic and send
  /// what was heard, unless [submit] is false (gesture cancelled).
  Future<void> _endHold({bool submit = true}) async {
    if (!_holding) return;
    _holding = false;
    HapticFeedback.lightImpact();
    await _stt.stop();
    // A final result can land just after stop() returns.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (mounted) setState(() => _listening = false);

    final text = _pttWords.trim();
    _pttWords = '';
    if (!submit) return;
    if (text.isEmpty) {
      await _speak("Didn't catch that. Hold the screen and speak again.");
      return;
    }
    // "repeat" / "say that again" replays the last answer instead of asking.
    if (parseVoiceChatControl(text) == VoiceChatControl.repeat) {
      if (_lastAIResponse == null) {
        await _speak('There is no assistant answer to repeat yet.');
      } else {
        await _speakLastResponse();
      }
      return;
    }
    _sendMessage(ChatMessage(
      user: currentUser,
      createdAt: DateTime.now(),
      text: text,
    ));
  }

  String _speechErrorMessage(String code) {
    if (code.contains('permission')) {
      return 'Microphone permission was denied. Enable it in Android app settings, then try again.';
    }
    if (code.contains('network')) {
      return 'Voice recognition could not connect. Check your internet, or type your message.';
    }
    return 'Voice recognition stopped unexpectedly. Hold the screen to try again.';
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _setupTTS() async {
    // apply() sets sequential mode (QUEUE_FLUSH + await-completion) so a _speak()
    // finishes before the mic re-opens in voice-chat.
    await SpeechConfig.apply(_tts);
  }

  void _computeImageHash(String path) {
    _imageHash = path.hashCode.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(_localization.tr('app_title')),
        actions: [
          if (widget.locationData != null && widget.locationData!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.location_on),
              onPressed: _showLocationDetails,
              tooltip: _localization.tr('location_details'),
            ),
          if (_configService.appConfig.features.ttsEnabled &&
              _lastAIResponse != null)
            IconButton(
              icon: const Icon(Icons.volume_up),
              onPressed: _speakLastResponse,
              tooltip: _localization.tr('speak'),
            ),
        ],
      ),
      // Hold anywhere = talk; release = send. translucent so the whole screen
      // (including gaps between messages) starts a hold, without blocking taps
      // on the text field / send button or scrolling the transcript.
      // Note: TalkBack claims long-press for its own menu — this gesture is for
      // the app's own spoken-feedback model, not a TalkBack session.
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (_) => _startHold(),
        onLongPressEnd: (_) => _endHold(),
        onLongPressCancel: () => _endHold(submit: false),
        child: Stack(
          children: [
            _buildUI(),
            if (_listening) _buildListeningOverlay(),
          ],
        ),
      ),
    );
  }

  /// Full-screen, unmistakable "I'm listening" state. Non-interactive — the
  /// hold that opened the mic is still in progress underneath it; lifting the
  /// finger is what sends.
  Widget _buildListeningOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Semantics(
          liveRegion: true,
          label: 'Listening. Release to send.',
          child: Container(
            color: Colors.blue.shade900.withValues(alpha: 0.92),
            alignment: Alignment.center,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.mic, color: Colors.white, size: 96),
                SizedBox(height: 24),
                Text(
                  'Listening…',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Release to send',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLocationDetails() {
    final data = widget.locationData!;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _localization.tr('image_location_data'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _buildInfoRow(
                _localization.tr('address'), data['address'] ?? 'N/A'),
            _buildInfoRow(_localization.tr('coordinates'),
                '${data['latitude']?.toStringAsFixed(6)}, ${data['longitude']?.toStringAsFixed(6)}'),
            _buildInfoRow(_localization.tr('altitude'),
                '${data['altitude']?.toStringAsFixed(1)} m'),
            _buildInfoRow(_localization.tr('gps_accuracy'),
                '${data['accuracy']?.toStringAsFixed(1)} m'),
            _buildInfoRow(
                _localization.tr('timestamp'), data['timestamp'] ?? 'N/A'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUI() {
    return DashChat(
      inputOptions: InputOptions(
        trailing: [
          IconButton(
            onPressed: () => _speak(
                'Hold anywhere on the screen and speak. Release to send.'),
            icon: Icon(_listening ? Icons.mic : Icons.touch_app),
            color: _listening ? Colors.blueAccent : null,
            tooltip: 'Hold anywhere to talk',
          ),
          IconButton(
            onPressed: _sendMediaMessageFromCamera,
            icon: const Icon(Icons.image),
            tooltip: 'Add image',
          ),
          if (_configService.appConfig.features.ttsEnabled)
            IconButton(
              onPressed: _speakLastResponse,
              icon: const Icon(Icons.volume_up),
              tooltip: 'Speak last response',
            ),
        ],
        sendButtonBuilder: (onSend) => _isLoading
            ? const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.send),
                onPressed: () => onSend(),
              ),
      ),
      currentUser: currentUser,
      onSend: _sendMessage,
      messages: messages,
      messageOptions: MessageOptions(
        currentUserContainerColor: Colors.blueAccent,
        containerColor: Colors.grey[800]!,
        textColor: Colors.white,
      ),
    );
  }

  Timer? _waitCue; // "still working" heartbeat while an answer is pending

  void _sendMessage(ChatMessage chatMessage) {
    if (_configService.initialized &&
        _configService.appConfig.features.vibrationFeedback) {
      HapticFeedback.lightImpact();
    }

    setState(() {
      messages = [chatMessage, ...messages];
      _isLoading = true;
    });

    _waitCue?.cancel();
    _waitCue = Timer.periodic(const Duration(seconds: 6), (_) {
      if (_isLoading && !_listening) _speak('Still working.');
    });

    _getAIResponse(chatMessage);
  }

  void _sendMediaMessage(String imagePath) {
    _computeImageHash(imagePath);

    final chatMessage = ChatMessage(
      user: currentUser,
      createdAt: DateTime.now(),
      text: widget.prompt ?? _localization.tr('describe_picture'),
      medias: [
        ChatMedia(
          url: imagePath,
          fileName: "",
          type: MediaType.image,
        )
      ],
    );
    _sendMessage(chatMessage);
  }

  void _sendMediaMessageFromCamera() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.camera);
    if (file != null) {
      _sendMediaMessage(file.path);
    }
  }

  Future<void> _getAIResponse(ChatMessage chatMessage) async {
    try {
      // Check cache first if offline mode enabled
      String? cachedResponse;
      if (_configService.appConfig.features.offlineMode) {
        cachedResponse = await _cacheService.getCachedResponse(
          prompt: chatMessage.text,
          imageHash: _imageHash,
        );
      }

      if (cachedResponse != null) {
        _handleResponse(cachedResponse, fromCache: true);
        return;
      }

      String question = chatMessage.text;
      List<Uint8List>? images;

      if (chatMessage.medias?.isNotEmpty ?? false) {
        final file = File(chatMessage.medias!.first.url);
        if (file.existsSync()) {
          images = [file.readAsBytesSync()];
        }
      }

      final response = await _aiService.generateResponse(
        prompt: question,
        images: images,
        isTamil: _localization.isTamil,
        enableBrowsing: true,
      );

      if (response != null && response.trim().isNotEmpty) {
        // Cache the response
        if (_configService.appConfig.features.offlineMode) {
          await _cacheService.cacheResponse(
            prompt: question,
            response: response,
            imageHash: _imageHash,
            locationData: widget.locationData,
          );
        }
        _handleResponse(response);
      } else {
        _handleResponse(_aiService.lastFailureMessage ??
            'The assistant did not return a description. Try another photo.');
      }
    } catch (e) {
      debugPrint('chatscreen generateResponse threw: $e');
      _handleResponse(
          "Something went wrong reaching the assistant. Please try again.");
    }
  }

  void _handleResponse(String response, {bool fromCache = false}) {
    _waitCue?.cancel();
    if (!mounted) return;

    final displayResponse =
        fromCache ? '${_localization.tr('offline_mode')}: $response' : response;

    if (messages.isNotEmpty && messages.first.user == geminiUser) {
      final lastMessage = messages.removeAt(0);
      final updatedMessage = ChatMessage(
        user: geminiUser,
        createdAt: lastMessage.createdAt,
        text: lastMessage.text + displayResponse,
        medias: lastMessage.medias,
      );
      setState(() {
        messages = [updatedMessage, ...messages];
        _lastAIResponse = displayResponse;
        _isLoading = false;
      });
    } else {
      final message = ChatMessage(
        user: geminiUser,
        createdAt: DateTime.now(),
        text: displayResponse,
      );
      setState(() {
        messages = [message, ...messages];
        _lastAIResponse = displayResponse;
        _isLoading = false;
      });
    }

    // Speak the answer aloud. With push-to-talk the next turn is another hold,
    // so there is no mic to re-open here.
    if (_configService.initialized &&
        _configService.appConfig.features.ttsEnabled) {
      _speakLastResponse();
    }
  }

  Future<void> _speakLastResponse() async {
    if (_lastAIResponse == null) return;
    SpokenText.last = _lastAIResponse; // so Home's Volume-Down repeats it too
    await _tts.stop();
    await _tts.speak(_lastAIResponse!);
  }

  @override
  void dispose() {
    _keySub?.cancel();
    _waitCue?.cancel();
    _holding = false;
    _stt.stop();
    _stt.cancel();
    _tts.stop();
    super.dispose();
  }
}
