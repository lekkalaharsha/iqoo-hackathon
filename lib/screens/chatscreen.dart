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

  // ChatGPT-style voice chat: speak, it transcribes + sends, reads the answer
  // aloud, then re-opens the mic for the next turn until you toggle it off.
  bool _sttReady = false;
  bool _sttSetupComplete = false;
  bool _voiceMode = false;
  bool _listening = false;
  bool _turnSubmitted = false;
  String _voiceDraft = '';
  String? _speechLocaleId;
  Timer? _restartTimer;
  Timer? _turnTimeout;

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
      await _toggleVoiceMode();
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
          // A listen turn can end with only this callback (silence, no result).
          if (s == 'done' || s == 'notListening') {
            if (mounted) setState(() => _listening = false);
            // Android may end a recognition session after a pause. Re-open it
            // while retaining the question until the user says "clear over".
            if (_voiceMode && !_isLoading && !_turnSubmitted) {
              _restartTimer?.cancel();
              _restartTimer = Timer(const Duration(milliseconds: 1200), () {
                if (_voiceMode && !_isLoading && !_listening) _listenOnce();
              });
            }
          }
        },
        onError: (error) {
          if (!_voiceMode) return;
          final code = error.errorMsg;
          if (code.contains('no_match') || code.contains('speech_timeout')) {
            if (mounted) setState(() => _listening = false);
            _restartTimer?.cancel();
            _restartTimer = Timer(const Duration(milliseconds: 1200), () {
              if (_voiceMode && !_isLoading && !_listening && !_turnSubmitted) {
                _listenOnce();
              }
            });
            return;
          }
          if (mounted) {
            setState(() {
              _listening = false;
              _voiceMode = false;
            });
          }
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

  Future<void> _toggleVoiceMode() async {
    if (!_sttSetupComplete) {
      await _speak('Voice input is still getting ready. Try again shortly.');
      return;
    }
    if (!_sttReady) {
      final permission = await Permission.microphone.status;
      await _speak(permission.isPermanentlyDenied
          ? 'Microphone permission is blocked. Enable it in Android app settings, then try again.'
          : permission.isDenied
              ? 'Microphone permission is required for voice chat. Allow it, then try again.'
              : 'Voice recognition is not available on this phone. You can still type a message.');
      return;
    }
    setState(() => _voiceMode = !_voiceMode);
    HapticFeedback.mediumImpact();
    if (_voiceMode) {
      await _speak(
          'Voice chat on. Speak after the vibration. Say clear over when your question is finished. Tap anywhere to cancel.');
      await _beginNextVoiceTurn();
    } else {
      _restartTimer?.cancel();
      _turnTimeout?.cancel();
      _voiceDraft = '';
      await _stt.stop();
      await _speak('Voice chat off.');
    }
  }

  Future<void> _listenOnce() async {
    if (!_sttReady || !_voiceMode || _listening || _isLoading) return;
    await _tts.stop();
    setState(() => _listening = true);
    HapticFeedback.lightImpact();
    await _stt.listen(
      onResult: (r) {
        if (_turnSubmitted) return;
        final segment = r.recognizedWords.trim();
        if (segment.isEmpty) return;
        final combined = [_voiceDraft, segment]
            .where((part) => part.isNotEmpty)
            .join(' ')
            .trim();
        final utterance = parseVoiceChatUtterance(combined);
        if (!utterance.isComplete && !r.finalResult) return;
        if (!utterance.isComplete) {
          _voiceDraft = combined;
          return;
        }
        _turnSubmitted = true;
        _turnTimeout?.cancel();
        _restartTimer?.cancel();
        _stt.stop();
        if (mounted) setState(() => _listening = false);
        final text = utterance.text;
        if (text.isEmpty) {
          _turnSubmitted = false;
          _voiceDraft = '';
          _startTurnTimeout();
          _speak('Please say your question, then say clear over.').then((_) {
            if (_voiceMode && mounted) _listenOnce();
          });
          return;
        }
        final control = parseVoiceChatControl(text);
        if (control == VoiceChatControl.stop) {
          setState(() => _voiceMode = false);
          _turnTimeout?.cancel();
          _stt.stop();
          _speak('Voice chat off.');
          return;
        }
        if (control == VoiceChatControl.repeat) {
          if (_lastAIResponse == null) {
            _speak('There is no assistant answer to repeat yet.').then((_) {
              if (_voiceMode && mounted) _beginNextVoiceTurn();
            });
            return;
          }
          _speakLastResponse().then((_) {
            if (_voiceMode && mounted) _beginNextVoiceTurn();
          });
          return;
        }
        HapticFeedback.mediumImpact();
        _voiceDraft = '';
        _sendMessage(ChatMessage(
          user: currentUser,
          createdAt: DateTime.now(),
          text: text,
        ));
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        onDevice: false,
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
        localeId: _speechLocaleId,
      ),
    );
  }

  void _startTurnTimeout() {
    _turnTimeout?.cancel();
    _turnTimeout = Timer(const Duration(minutes: 2), () async {
      if (!_voiceMode || _isLoading || _turnSubmitted) return;
      _restartTimer?.cancel();
      await _stt.stop();
      if (mounted) {
        setState(() {
          _voiceMode = false;
          _listening = false;
        });
      }
      await _speak(
          'I did not hear clear over within two minutes. Voice chat is off. Tap the microphone to try again.');
    });
  }

  Future<void> _beginNextVoiceTurn() async {
    if (!_voiceMode || !mounted) return;
    _voiceDraft = '';
    _turnSubmitted = false;
    _startTurnTimeout();
    await _listenOnce();
  }

  String _speechErrorMessage(String code) {
    if (code.contains('permission')) {
      return 'Microphone permission was denied. Enable it in Android app settings, then try again.';
    }
    if (code.contains('network')) {
      return 'Voice recognition could not connect. Check your internet, or type your message.';
    }
    if (code.contains('no_match') || code.contains('speech_timeout')) {
      return "I didn't hear a clear question. Voice chat is off. Tap the microphone to try again.";
    }
    return 'Voice recognition stopped unexpectedly. Tap the microphone to try again.';
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
    final isTamil = _localization.isTamil;

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
      body: Stack(
        children: [
          _buildUI(),
          if (_listening) _buildListeningOverlay(isTamil),
        ],
      ),
    );
  }

  /// Full-screen, unmistakable "I'm listening" state — a small mic-icon swap in
  /// the input row is not enough for a low-vision user. Tap anywhere to stop.
  Widget _buildListeningOverlay(bool isTamil) {
    return Positioned.fill(
      child: Semantics(
        liveRegion: true,
        button: true,
        label: isTamil
            ? 'கேட்கிறது. நிறுத்த தட்டவும்.'
            : 'Listening. Tap to stop.',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleVoiceMode,
          child: Container(
            color: Colors.blue.shade900.withValues(alpha: 0.92),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.mic, color: Colors.white, size: 96),
                const SizedBox(height: 24),
                Text(
                  isTamil ? 'கேட்கிறது…' : 'Listening…',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  isTamil ? 'நிறுத்த எங்கும் தட்டவும்' : 'Tap anywhere to stop',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
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
    final isTamil = _localization.isTamil;

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
            onPressed: _toggleVoiceMode,
            icon: Icon(_listening
                ? Icons.mic
                : (_voiceMode ? Icons.graphic_eq : Icons.mic_none)),
            color: _voiceMode ? Colors.blueAccent : null,
            tooltip: _voiceMode ? 'Stop voice chat' : 'Start voice chat',
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

  void _sendMessage(ChatMessage chatMessage) {
    if (_configService.initialized &&
        _configService.appConfig.features.vibrationFeedback) {
      HapticFeedback.lightImpact();
    }

    setState(() {
      messages = [chatMessage, ...messages];
      _isLoading = true;
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

    // Accessibility: speak the answer aloud automatically, then in voice-chat
    // mode re-open the mic for the next turn (ChatGPT-style loop).
    if (_configService.initialized &&
        _configService.appConfig.features.ttsEnabled) {
      _speakLastResponse().then((_) {
        if (_voiceMode && mounted) _beginNextVoiceTurn();
      });
    } else if (_voiceMode && mounted) {
      _beginNextVoiceTurn();
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
    _restartTimer?.cancel();
    _turnTimeout?.cancel();
    _voiceMode = false;
    _stt.stop();
    _stt.cancel();
    _tts.stop();
    super.dispose();
  }
}
