import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';
import '../services/ai_service.dart';
import '../services/gps_service.dart';
import '../services/localization_service.dart';
import '../services/config_service.dart';
import '../services/browsing_service.dart';
import '../services/speech_config.dart';
import '../services/intent_resolver.dart';

enum VoiceCommandType {
  captureImage,
  describeScene,
  readText,
  identifyFood,
  analyzeDocument,
  getLocation,
  getDirections,
  searchWeb,
  readLastResponse,
  repeatLastResponse,
  switchMode,
  toggleFeature,
  openSettings,
  openApp,
  help,
  emergency,
  unknown,
}

class VoiceCommand {
  final VoiceCommandType type;
  final Map<String, dynamic> parameters;
  final String originalText;
  final double confidence;

  VoiceCommand({
    required this.type,
    required this.parameters,
    required this.originalText,
    required this.confidence,
  });
}

class VoiceAssistantService {
  static final VoiceAssistantService _instance = VoiceAssistantService._internal();
  factory VoiceAssistantService() => _instance;
  VoiceAssistantService._internal();

  final stt.SpeechToText _speech = SpeechConfig.speech;
  final FlutterTts _tts = SpeechConfig.tts;
  final AIService _aiService = AIService();
  final GPSService _gpsService = GPSService();
  final LocalizationService _localization = LocalizationService();
  final ConfigService _configService = ConfigService();
  final BrowsingService _browsingService = BrowsingService();

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<UserAccelerometerEvent>? _userAccelerometerSubscription;
  
  bool _isListening = false;
  bool _isWakeWordActive = false;
  bool _isProcessing = false;
  bool _isInitialized = false;
  bool _sttAvailable = false; // false on devices with no real recogniser (MIUI)

  /// Whether speech recognition actually works here. When false, every "listen"
  /// entry point speaks a notice instead of silently doing nothing.
  bool get sttAvailable => _sttAvailable;
  bool _accessibilityMode = false;
  String _wakeWord = 'hey assistant';
  double _shakeThreshold = 15.0;
  DateTime? _lastShakeTime;

  // Callbacks for UI updates
  Function(VoiceCommand)? onCommandRecognized;
  Function(String)? onTranscriptionUpdate;
  Function(bool)? onListeningStateChange;
  Function(String)? onStatusUpdate;
  Function(String)? onError;

  // Command patterns for different languages
  final Map<String, List<(RegExp, VoiceCommandType)>> _commandPatterns = {
    'en': [
      // Capture image
      (RegExp(r'(take|snap|capture|photo|picture|shoot).*(photo|picture|image)', caseSensitive: false), VoiceCommandType.captureImage),
      (RegExp(r'(what|describe).*(see|here|around|scene)', caseSensitive: false), VoiceCommandType.describeScene),
      
      // Text reading
      (RegExp(r'(read|scan|extract).*(text|words|writing)', caseSensitive: false), VoiceCommandType.readText),
      
      // Food
      (RegExp(r'(identify|what|recognize).*(food|meal|dish|eat)', caseSensitive: false), VoiceCommandType.identifyFood),
      (RegExp(r'(nutrition|calories|ingredients|allergens).*(food|meal)', caseSensitive: false), VoiceCommandType.identifyFood),
      
      // Document
      (RegExp(r'(analyze|read|scan|summarize).*(document|paper|letter|receipt|bill)', caseSensitive: false), VoiceCommandType.analyzeDocument),
      
      // Location
      (RegExp(r'(where|location|address|place).*(am i|here)', caseSensitive: false), VoiceCommandType.getLocation),
      (RegExp(r'(navigate|direction|route|go to).*(.*?)', caseSensitive: false), VoiceCommandType.getDirections),
      
      // Web search
      (RegExp(r'(search|look up|find|google).*(.*?)', caseSensitive: false), VoiceCommandType.searchWeb),
      (RegExp(r'(latest|current|news|weather|price).*(.*?)', caseSensitive: false), VoiceCommandType.searchWeb),
      
      // Response control
      (RegExp(r'(read|speak|say).*(last|previous|response|answer)', caseSensitive: false), VoiceCommandType.readLastResponse),
      (RegExp(r'\b(repeat|again|say again)\b', caseSensitive: false), VoiceCommandType.repeatLastResponse),
      
      // Mode switching
      (RegExp(r'(switch|change|mode).*(explore|text|document|read and explain|voice chat)', caseSensitive: false), VoiceCommandType.switchMode),
      
      // Features
      (RegExp(r'(turn|toggle|enable|disable).*(gps|location|tts|speech|vibration|browsing|offline)', caseSensitive: false), VoiceCommandType.toggleFeature),
      
      // Settings
      (RegExp(r'(open|go to|show).*(setting|config|menu)', caseSensitive: false), VoiceCommandType.openSettings),

      // Help
      (RegExp(r'(help|what can you do|commands|how to use)', caseSensitive: false), VoiceCommandType.help),

      // Emergency — deliberately narrow. "help me" / "urgent" / "danger" are
      // said in ordinary conversation; an accidental match arms a call.
      (RegExp(r'\b(emergency|s\.?\s?o\.?\s?s)\b', caseSensitive: false), VoiceCommandType.emergency),

      // Open an installed app by (mis-heard) name. LAST on purpose: this
      // pattern is broad ("open/launch/start <anything>"), so every reserved
      // command above — settings, help, emergency — must get first refusal.
      (RegExp(r'\b(open|launch|start)\b\s+(.+)', caseSensitive: false), VoiceCommandType.openApp),
    ],

  };

  Future<void> initialize() async {
    if (_isInitialized) return;

    await _configService.initialize();
    await _localization.initialize();
    await _aiService.initialize();

    await _setupTTS();
    await _requestPermissions();

    // Speech recognition. debugLogging surfaces why it fails on odd OEM builds.
    bool available = false;
    try {
      available = await _speech.initialize(
        onError: (error) => _handleError('Speech recognition error: $error'),
        onStatus: (status) => _handleStatus(status),
        debugLogging: true,
      );
    } catch (e) {
      _handleError('Speech init threw: $e');
    }

    _sttAvailable = available;

    if (!available) {
      // Not an error the user should hear on every launch — it's a known
      // device limitation. Just note it; the listen entry points announce it
      // when the user actually tries to use voice.
      onStatusUpdate?.call('stt_unavailable');
      _setupShakeDetection();
      _isInitialized = true;
      return;
    }

    _setupShakeDetection();
    _isInitialized = true;
    _announce('Voice assistant ready. Say "$_wakeWord" to activate.');
  }

  Future<void> _setupTTS() async {
    await SpeechConfig.apply(_tts);
    // Small pause before speaking (milliseconds)
    await _tts.setSilence(50);
  }

  Future<void> _requestPermissions() async {
    await Permission.microphone.request();
  }

  void _setupShakeDetection() {
    _accelerometerSubscription = accelerometerEvents.listen((event) {
      final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      if (magnitude > _shakeThreshold) {
        final now = DateTime.now();
        if (_lastShakeTime == null || now.difference(_lastShakeTime!).inSeconds > 2) {
          _lastShakeTime = now;
          _onShakeDetected();
        }
      }
    });
  }

  void _toggleWakeWordListening() {
    if (_isWakeWordActive) {
      stopWakeWordListening();
    } else {
      startWakeWordListening();
    }
  }

  void _onShakeDetected() {
    if (_accessibilityMode) {
      _toggleWakeWordListening();
      _announce('Wake word listening ' + (_isWakeWordActive ? 'activated' : 'deactivated'));
    }
  }

  void _handleError(String error) {
    onError?.call(error);
    _announce('Error: $error');
  }

  void _handleStatus(String status) {
    if (status == 'listening') {
      _isListening = true;
      onListeningStateChange?.call(true);
      _announce('Listening...', interrupt: false);
    } else if (status == 'notListening') {
      _isListening = false;
      onListeningStateChange?.call(false);
    }
  }

  Future<void> startWakeWordListening() async {
    if (!_isInitialized || _isWakeWordActive) return;
    if (!_sttAvailable) {
      _announce('Voice input is not available on this phone. '
          'Use the buttons and the volume keys instead.');
      return;
    }
    _isWakeWordActive = true;
    _listenForWakeWord();
  }

  Future<void> stopWakeWordListening() async {
    _isWakeWordActive = false;
    await _speech.stop();
  }

  Future<void> _listenForWakeWord() async {
    if (!_isWakeWordActive) return;

    // No localeId => use the device's default recogniser locale. A missing
    // locale (e.g. en-IN not installed) makes listen() fail silently.
    await _speech.listen(
      onResult: (result) {
        onTranscriptionUpdate?.call(result.recognizedWords);
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          _processWakeWordResult(result.recognizedWords);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.confirmation,
        partialResults: true,
      ),
    );
  }

  void _processWakeWordResult(String text) {
    final lowerText = text.toLowerCase();
    
    if (lowerText.contains(_wakeWord.toLowerCase())) {
      _onWakeWordDetected(text);
    } else if (_isListening) {
      // Already in command mode, process as command
      _processCommand(text);
    }
  }

  void _onWakeWordDetected(String text) {
    _announce('Yes? How can I help?', interrupt: true);
    _startCommandListening();
  }

  Future<void> _startCommandListening() async {
    await _speech.listen(
      onResult: (result) {
        onTranscriptionUpdate?.call(result.recognizedWords);
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          _processCommand(result.recognizedWords);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  void _processCommand(String text) {
    if (_isProcessing) return;
    _isProcessing = true;

    final command = parseCommand(text);
    onCommandRecognized?.call(command);
    
    _executeCommand(command).then((_) {
      _isProcessing = false;
      if (_isWakeWordActive) {
        _listenForWakeWord(); // Return to wake word listening
      }
    }).catchError((e) {
      _isProcessing = false;
      _handleError('Command execution failed: $e');
      if (_isWakeWordActive) {
        _listenForWakeWord();
      }
    });
  }

  @visibleForTesting
  VoiceCommand parseCommand(String text) {
    final patterns = _commandPatterns['en']!;
    
    for (final entry in patterns) {
      final match = entry.$1.firstMatch(text);
      if (match != null) {
        final params = _extractParameters(text, entry.$2);
        return VoiceCommand(
          type: entry.$2,
          parameters: params,
          originalText: text,
          confidence: 0.9,
        );
      }
    }

    // Fallback: send to AI for interpretation
    return VoiceCommand(
      type: VoiceCommandType.unknown,
      parameters: {'raw_text': text},
      originalText: text,
      confidence: 0.3,
    );
  }

  Map<String, dynamic> _extractParameters(String text, VoiceCommandType type) {
    final params = <String, dynamic>{};
    final lowerText = text.toLowerCase();

    switch (type) {
      case VoiceCommandType.switchMode:
        // Home screen order: 0 Explore, 1 Read & Explain, 2 Voice Chat.
        // "text" / "document" collapse into the single reading mode (1).
        if (lowerText.contains('explore')) {
          params['mode'] = 0;
        } else if (lowerText.contains('voice chat')) {
          params['mode'] = 2;
        } else {
          params['mode'] = 1;
        }
        break;
      case VoiceCommandType.toggleFeature:
        if (lowerText.contains('gps') || lowerText.contains('location') || lowerText.contains('இடம்')) params['feature'] = 'gps_enabled';
        else if (lowerText.contains('tts') || lowerText.contains('speech') || lowerText.contains('பேச்சு')) params['feature'] = 'tts_enabled';
        else if (lowerText.contains('vibration') || lowerText.contains('நடை')) params['feature'] = 'vibration_feedback';
        else if (lowerText.contains('browsing') || lowerText.contains('web') || lowerText.contains('உலாவல்')) params['feature'] = 'web_browsing';
        else if (lowerText.contains('offline') || lowerText.contains('ஆஃப்லைன்')) params['feature'] = 'offline_mode';
        params['enable'] = lowerText.contains('enable') || lowerText.contains('turn on') || lowerText.contains('இயக்கு') || lowerText.contains('on');
        break;
      case VoiceCommandType.searchWeb:
        params['query'] = text.replaceAll(RegExp(r'(search|look up|find|google|தேடு|பாரு|காண்|கூகிள்)\s*', caseSensitive: false), '');
        break;
      case VoiceCommandType.openApp:
        params['app'] = text.replaceAll(
            RegExp(r'^\s*(open|launch|start|திற|தொடங்கு)\s+', caseSensitive: false), '');
        break;
      case VoiceCommandType.getDirections:
        params['destination'] = text.replaceAll(RegExp(r'(navigate|direction|route|go to|நாவிகேட்|திசை|செல்)\s*', caseSensitive: false), '');
        break;
      default:
        break;
    }

    return params;
  }

  Future<void> _executeCommand(VoiceCommand command) async {
    try {
      switch (command.type) {
        case VoiceCommandType.captureImage:
        case VoiceCommandType.describeScene:
          await _executeCaptureCommand(command.type == VoiceCommandType.describeScene);
          break;
        case VoiceCommandType.readText:
          await _executeCaptureCommand(false, mode: 1); // Read & Explain
          break;
        case VoiceCommandType.identifyFood:
          await _executeCaptureCommand(false, mode: 0); // Explore
          break;
        case VoiceCommandType.analyzeDocument:
          await _executeCaptureCommand(false, mode: 1); // Read & Explain
          break;
        case VoiceCommandType.getLocation:
          await _announceLocation();
          break;
        case VoiceCommandType.getDirections:
          await _announceDirections(command.parameters['destination'] as String?);
          break;
        case VoiceCommandType.searchWeb:
          await _executeWebSearch(command.parameters['query'] as String? ?? command.originalText);
          break;
        case VoiceCommandType.readLastResponse:
        case VoiceCommandType.repeatLastResponse:
          await _repeatLastResponse();
          break;
        case VoiceCommandType.switchMode:
          _switchMode(command.parameters['mode'] as int?);
          break;
        case VoiceCommandType.toggleFeature:
          _toggleFeature(command.parameters['feature'] as String?, command.parameters['enable'] as bool?);
          break;
        case VoiceCommandType.openSettings:
          onStatusUpdate?.call('open_settings');
          _announce('Opening settings');
          break;
        case VoiceCommandType.openApp:
          await _openApp(command.parameters['app'] as String?);
          break;
        case VoiceCommandType.help:
          _announceHelp();
          break;
        case VoiceCommandType.emergency:
          await _triggerEmergency();
          break;
        case VoiceCommandType.unknown:
          await _handleUnknownCommand(command.originalText);
          break;
      }
    } catch (e) {
      _handleError('Command failed: $e');
    }
  }

  Future<void> _executeCaptureCommand(bool describeScene, {int mode = 0}) async {
    _announce(describeScene ? 'Describing scene...' : 'Capturing image...');
    onStatusUpdate?.call('capture_image:$mode');
  }

  Future<void> _announceLocation() async {
    final position = _gpsService.getLastKnownPosition();
    final address = _gpsService.getLastKnownAddress();
    
    if (position == null) {
      _announce('Location not available. Please enable GPS.');
      return;
    }

    final accuracy = position.accuracy;
    String accuracyDesc;
    if (accuracy <= 10) accuracyDesc = 'high accuracy';
    else if (accuracy <= 50) accuracyDesc = 'medium accuracy';
    else accuracyDesc = 'low accuracy';

    final message = _localization.isTamil
        ? 'நீங்கள் $address இல் உள்ளீர்கள். GPS துல்லியம்: ${accuracy.toStringAsFixed(1)} மீட்டர் ($accuracyDesc).'
        : 'You are at $address. GPS accuracy: ${accuracy.toStringAsFixed(1)} meters ($accuracyDesc).';
    
    _announce(message);
  }

  Future<void> _announceDirections(String? destination) async {
    if (destination == null || destination.isEmpty) {
      _announce('Where would you like to go? Please specify a destination.');
      return;
    }
    
    _announce('Getting directions to $destination...');
    onStatusUpdate?.call('directions:$destination');
  }

  Future<void> _executeWebSearch(String query) async {
    _announce('Searching the web for $query...');
    onStatusUpdate?.call('web_search:$query');
  }

  Future<void> _repeatLastResponse() async {
    onStatusUpdate?.call('repeat_response');
    _announce('Repeating last response');
  }

  void _switchMode(int? mode) {
    if (mode == null || mode < 0 || mode > 2) return;
    const names = ['Explore', 'Read & Explain', 'Voice Chat'];
    _announce('Switching to ${names[mode]} mode');
    onStatusUpdate?.call('switch_mode:$mode');
  }

  void _toggleFeature(String? feature, bool? enable) {
    if (feature == null) return;
    final shouldEnable = enable ?? true;
    
    const featureNames = {
      'gps_enabled': 'GPS',
      'tts_enabled': 'Text to Speech',
      'vibration_feedback': 'Vibration',
      'web_browsing': 'Web Browsing',
      'offline_mode': 'Offline Mode',
    };
    
    const featureNamesTa = {
      'gps_enabled': 'GPS',
      'tts_enabled': 'எழுத்து-பேச்சு',
      'vibration_feedback': 'நடை',
      'web_browsing': 'வலை உலாவல்',
      'offline_mode': 'ஆஃப்லைன் பதிவு',
    };
    
    final name = _localization.isTamil ? (featureNamesTa[feature] ?? feature) : (featureNames[feature] ?? feature);
    final action = shouldEnable ? (_localization.isTamil ? 'இயக்கப்பட்டது' : 'enabled') : (_localization.isTamil ? 'நிறுத்தப்பட்டது' : 'disabled');
    
    _configService.updateFeature(feature, shouldEnable);
    _announce('$name $action');
  }

  void _announceHelp() {
    final helpText = _localization.isTamil
        ? '''உதவி: "ஹேי 어시스턴트" என்று சொல்லுங்கள், பின்னர்:
        - "புகைப்படம் எடு" அல்லது "சூழலை விவரி"
        - "எழுத்து வாசி" அல்லது "உணவு அடையாளம்" 
        - "ஆவணம் பகுப்பாய்வு" அல்லது "எங்கே இருக்கிறேன்"
        - "தேடு [விஷயம்]" அல்லது "திசை [இடம்]"
        - "கடைசி பதில் வாசி" அல்லது "மோடு மாற்று"
        - "GPS இயக்கு" அல்லது "ஆஃப்லைன் চালு"
        - "அவசரம்".Threading'''
        : '''Help: Say "Hey Assistant" then:
        - "Take photo" or "Describe scene"
        - "Read text" or "Identify food"
        - "Analyze document" or "Where am I"
        - "Search [topic]" or "Navigate to [place]"
        - "Read last response" or "Switch mode"
        - "Open WhatsApp" or "Open" any installed app
        - "Enable GPS" or "Turn on offline mode"
        - "Emergency" for SOS''';
    
    _announce(helpText);
  }

  Future<void> _triggerEmergency() async {
    // Calls the user's own nominated contact after a cancellable countdown —
    // never 112/108. The homepage speaks the countdown + "tap to cancel".
    _announce('Starting the emergency countdown. Tap the screen to stop it.',
        interrupt: true);
    HapticFeedback.heavyImpact();
    onStatusUpdate?.call('emergency');
  }

  static const _phone = MethodChannel('aiforall/phone');

  /// Resolve a spoken (often mis-heard) app name against the phone's real
  /// launchable-app list and open it. The inventory is fetched once, lazily.
  Future<void> _openApp(String? phrase) async {
    final p = (phrase ?? '').trim();
    if (p.isEmpty) {
      _announce('Which app should I open?');
      return;
    }
    try {
      if (IntentResolver.isEmpty) {
        final raw =
            await _phone.invokeMethod<List<dynamic>>('listLaunchableApps');
        IntentResolver.setInventory([
          for (final m in raw ?? const [])
            AppEntry((m as Map)['label'] as String, m['package'] as String),
        ]);
      }
      final hit = IntentResolver.resolve(p);
      if (hit == null) {
        _announce("I couldn't find $p. Try the exact app name.");
        return;
      }
      final ok = await _phone
              .invokeMethod<bool>('launchApp', {'packageName': hit.package}) ??
          false;
      _announce(ok ? 'Opening ${hit.label}.' : "I couldn't open ${hit.label}.");
    } on PlatformException catch (e) {
      _handleError('Open app failed: ${e.message}');
    }
  }

  Future<void> _handleUnknownCommand(String text) async {
    // Send to AI for general response
    _announce('Let me help with that...');
    onStatusUpdate?.call('ai_query:$text');
  }

  // ponytail: public wrapper so other screens can trigger TTS announcements
  void announce(String text, {bool interrupt = true}) =>
      _announce(text, interrupt: interrupt);

  void _announce(String text, {bool interrupt = true}) {
    if (interrupt) {
      _tts.stop();
    }
    _tts.speak(text);
    if (_configService.appConfig.features.vibrationFeedback) {
      HapticFeedback.lightImpact();
    }
  }

  // Public API for UI
  Future<void> startListening() async {
    if (!_isInitialized) await initialize();
    await startWakeWordListening();
  }

  Future<void> stopListening() async {
    await stopWakeWordListening();
  }

  void setAccessibilityMode(bool enabled) {
    _accessibilityMode = enabled;
    _configService.updateFeature('accessibility_mode', enabled);
  }

  void setWakeWord(String word) {
    _wakeWord = word.toLowerCase();
  }

  void setShakeThreshold(double threshold) {
    _shakeThreshold = threshold;
  }

  bool get isListening => _isListening;
  bool get isWakeWordActive => _isWakeWordActive;
  bool get isProcessing => _isProcessing;
  bool get accessibilityMode => _accessibilityMode;

  void dispose() {
    _speech.stop();
    _speech.cancel();
    _tts.stop();
    _accelerometerSubscription?.cancel();
    _userAccelerometerSubscription?.cancel();
    _browsingService.dispose();
    _isInitialized = false;
  }
}