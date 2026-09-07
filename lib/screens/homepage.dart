import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/assist_setup.dart';
import '../services/gps_service.dart';
import '../services/config_service.dart';
import '../services/localization_service.dart';
import '../services/ai_service.dart';
import '../services/offline_cache_service.dart';
import '../services/voice_assistant_service.dart';
import '../services/sms_service.dart';
import '../services/hardware_keys.dart';
import '../services/speech_config.dart';
import '../services/voice_prompt.dart';
import '../services/emergency_service.dart';
import '../widgets/debug_overlay.dart';
import 'chatscreen.dart';
import 'read_explain_screen.dart';
import 'inbox_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final CameraDescription? camera;

  const HomeScreen({super.key, required this.camera});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  // Reading printed text is the reliable local path and the app's primary
  // purpose. Explore requires separately configured cloud image AI.
  int _selectedIndex = 1;
  bool _showCameraError = false;

  final GPSService _gpsService = GPSService();
  final ConfigService _configService = ConfigService();
  final LocalizationService _localization = LocalizationService();
  final AIService _aiService = AIService();
  final OfflineCacheService _cacheService = OfflineCacheService();
  final VoiceAssistantService _voiceAssistant = VoiceAssistantService();
  final Connectivity _connectivity = Connectivity();
  final FlutterTts _tts = SpeechConfig.tts;
  final EmergencyService _emergency = EmergencyService();
  bool _showOnboarding = false;
  // True once 'onboarding_seen' has been read. Until then _announceReady() must
  // stay quiet, or on a first run it races the tutorial and clips step 1.
  bool _onboardingChecked = false;
  int _onboardingStep = 0;
  StreamSubscription<String>? _keySub;
  int? _emergencyCountdown;

  Position? _currentPosition;
  String? _currentAddress;
  bool _isGPSEnabled = false;
  StreamSubscription<Position>? _positionSubscription;
  ConnectivityResult _connectivityResult = ConnectivityResult.none;
  bool _initialized = false;
  bool _isProcessing = false;
  bool _voiceAssistantActive = false;
  String _voiceStatus = '';
  String _lastTranscription = '';

  // Accessibility
  bool _highContrast = false;
  bool _largeText = false;
  double _textScaleFactor = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _keySub = HardwareKeys.stream.listen((k) {
      // Only the visible screen reacts (chat screen sits on top of this one).
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      // Any key aborts a pending emergency call before doing anything else.
      if (_emergency.isCountingDown) {
        _cancelEmergency();
        return;
      }
      if (k == 'volume_up') {
        if (!_isProcessing) {
          if (_selectedIndex == 2) {
            _openVoiceChat();
          } else {
            _takePicture();
          }
        }
      } else if (k == 'volume_down') {
        _repeatSpoken();
      }
    });
    _initializeAll();
  }

  void _repeatSpoken() {
    final text = SpokenText.last;
    _tts.stop();
    if (text == null || text.isEmpty) {
      _tts.speak(_localization.isTamil
          ? 'மீண்டும் சொல்ல எதுவும் இல்லை.'
          : 'Nothing to repeat yet.');
    } else {
      _tts.speak(text);
    }
  }

  Future<void> _initializeAll() async {
    // Camera is the only thing the user is actually waiting to see, so start it
    // first and don't await it — the rest runs alongside instead of behind it.
    if (widget.camera != null) {
      _initializeCamera();
    } else if (mounted) {
      setState(() {
        _showCameraError = true;
        _initialized = true;
      });
    }

    // Config + localization gate the first frame. Run them together.
    await Future.wait([
      _configService.initialize(),
      _localization.initialize(),
    ]);
    if (mounted) setState(() {});

    // Everything below is off the critical path — kick it all off concurrently
    // and let each finish whenever. None of it blocks a frame.
    _listenConnectivity();
    _initializeGPS();
    _setupVoiceAssistantCallbacks(); // wire onError BEFORE init so failures surface

    unawaited(_cacheService
        .initialize()
        .then((_) => _loadAccessibilitySettings())
        .catchError((e) => debugPrint('Cache init failed: $e')));
    unawaited(_aiService
        .initialize()
        .catchError((e) => debugPrint('AI init failed: $e')));
    unawaited(SmsService()
        .initialize()
        .catchError((e) => debugPrint('SMS init failed: $e')));
    unawaited(_voiceAssistant
        .initialize()
        .catchError((e) => debugPrint('Voice assistant init failed: $e')));
  }

  void _setupVoiceAssistantCallbacks() {
    _voiceAssistant.onCommandRecognized = _onVoiceCommand;
    _voiceAssistant.onTranscriptionUpdate = (text) {
      if (mounted) setState(() => _lastTranscription = text);
    };
    _voiceAssistant.onListeningStateChange = (listening) {
      if (mounted)
        setState(() =>
            _voiceStatus = listening ? 'Listening...' : 'Wake word active');
    };
    _voiceAssistant.onStatusUpdate = (status) {
      _handleVoiceStatus(status);
    };
    _voiceAssistant.onError = (error) {
      _showSnackBar('Voice Error: $error');
    };
  }

  void _handleVoiceStatus(String status) {
    if (status.startsWith('capture_image:')) {
      final mode = int.tryParse(status.split(':')[1]) ?? 0;
      _captureImageByVoice(mode);
    } else if (status.startsWith('switch_mode:')) {
      final mode =
          (int.tryParse(status.split(':')[1]) ?? 0).clamp(0, _modeCount - 1);
      setState(() => _selectedIndex = mode);
      _announceModeChange(mode);
    } else if (status == 'open_settings') {
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    } else if (status == 'emergency') {
      _triggerEmergencySOS();
    } else if (status == 'repeat_response') {
      _repeatSpoken();
    } else if (status.startsWith('directions:') ||
        status.startsWith('web_search:') ||
        status.startsWith('ai_query:')) {
      // These voice outcomes have no working destination. A snackbar is
      // invisible to a blind user — say so out loud instead of silently.
      _voiceAssistant.announce('That is not available yet.');
    }
  }

  Future<void> _captureImageByVoice(int mode) async {
    if (!(_isCameraInitialized &&
        _cameraController != null &&
        _cameraController!.value.isInitialized)) {
      _voiceAssistant.announce('Camera not ready');
      return;
    }

    setState(() => _selectedIndex = mode.clamp(0, _modeCount - 1));
    await _takePicture();
  }

  void _announceModeChange(int mode) {
    // Reuse the single source of mode names so this can never index past the
    // list when a new mode (e.g. Voice Chat) is added.
    _voiceAssistant.announce('Switched to ${_getModeName(mode)} mode');
  }

  Future<void> _sendAIQuery(String query) async {
    // Navigate to chat screen with text query
    _showSnackBar('AI Query: $query');
  }

  Future<void> _triggerEmergencySOS() async {
    if (_emergency.isCountingDown)
      return; // already armed — ignore repeat presses
    HapticFeedback.heavyImpact();
    // No contact set: trigger() just speaks the hint. Don't show the red
    // countdown overlay — nothing ticks it down and it would stick on "5".
    final contact = await EmergencyService.getContact();
    if (contact == null || contact.isEmpty) {
      await _emergency.trigger();
      return;
    }
    setState(() => _emergencyCountdown = EmergencyService.countdownSeconds);
    await _emergency.trigger(onTick: (s) {
      if (mounted) setState(() => _emergencyCountdown = s > 0 ? s : null);
    });
  }

  Future<void> _cancelEmergency() async {
    await _emergency.cancel();
    if (mounted) setState(() => _emergencyCountdown = null);
  }

  void _loadAccessibilitySettings() async {
    final highContrast = await _cacheService.getBool('high_contrast');
    final largeText = await _cacheService.getBool('large_text');
    if (mounted) {
      setState(() {
        _highContrast = highContrast;
        _largeText = largeText;
        _textScaleFactor = largeText ? 1.5 : 1.0;
        // First-run tutorial is not shown automatically on launch. It stays
        // reachable on demand from Settings > "How to use Logic Legends",
        // which sets 'onboarding_seen' false and lets the resume hook below
        // play it. Mark it seen here so a fresh install still lands straight
        // on the camera.
        _showOnboarding = false;
        _onboardingChecked = true;
      });
      await _cacheService.setBool('onboarding_seen', true);
      _announceReady();
    }
  }

  // --- First-run tutorial -------------------------------------------------

  List<String> get _onboardingSteps => [
        'Welcome to Logic Legends. It looks at what your camera sees and tells '
            'you out loud what it means. Tap anywhere to hear the next tip.',
        'Point the phone at something and tap anywhere on the screen. It takes '
            'a photo and reads what is in front of you.',
        'Double-tap to ask a question first. For example: what is the dose, or '
            'when does this expire.',
        'Swipe left or right to switch between two modes. Explore describes a '
            'scene. Read and Explain reads printed text like medicine or bills.',
        'Press Volume Up to take a photo. Press Volume Down to repeat the last '
            'answer. Hold either volume key to change the speaking volume.',
        'Long-press the screen to call your emergency contact. A countdown '
            'gives you time to cancel by tapping.',
        'Last tip. To open this app without looking, set it as your assistant. '
            'Tap now to open assistant settings, or swipe to finish.',
      ];

  Future<void> _speakOnboardingStep() async {
    try {
      await SpeechConfig.apply(_tts);
      await _tts.stop();
      await _tts.speak(_onboardingSteps[_onboardingStep]);
    } catch (_) {}
  }

  void _advanceOnboarding() {
    HapticFeedback.lightImpact();
    if (_onboardingStep >= _onboardingSteps.length - 1) {
      _finishOnboarding(openAssist: true);
      return;
    }
    setState(() => _onboardingStep++);
    _speakOnboardingStep();
  }

  Future<void> _finishOnboarding({bool openAssist = false}) async {
    await _cacheService.setBool('onboarding_seen', true);
    if (mounted) {
      setState(() {
        _showOnboarding = false;
        _onboardingStep = 0;
      });
    }
    if (openAssist) {
      await _tts.stop();
      await AssistSetup.openSettings();
    } else {
      _announceReady();
    }
  }

  void _saveAccessibilitySetting(String key, bool value) async {
    await _cacheService.setBool(key, value);
  }

  Future<void> _announceReady() async {
    if (!_onboardingChecked) return; // don't race the first-run tutorial
    if (_showOnboarding) return; // the tutorial is talking
    if (!_configService.appConfig.features.ttsEnabled) return;
    try {
      await SpeechConfig.apply(_tts);
      // If the device's TTS engine has no usable English voice, say so once
      // (best effort — a fallback voice may still speak it) and show it for a
      // sighted helper, instead of the app just going silent.
      if (SpeechConfig.ttsHealthy.value == false) {
        _showSnackBar(SpeechConfig.ttsBrokenAdvice);
        SpokenText.last = SpeechConfig.ttsBrokenAdvice;
        await _tts.speak(SpeechConfig.ttsBrokenAdvice);
        return;
      }
      final msg = _localization.isTamil
          ? 'AI அனைவருக்கும் தயார். படம் எடுக்க எங்கும் தட்டவும்.'
          : 'Logic Legends ready. Read and Explain mode. Point at printed text '
              'and tap anywhere to read it. Swipe left or right to change mode.';
      SpokenText.last = msg;
      await _tts.speak(msg);
    } catch (_) {}
  }

  void _listenConnectivity() {
    _connectivity.onConnectivityChanged.listen((result) {
      if (mounted) setState(() => _connectivityResult = result);
    });
    _connectivity.checkConnectivity().then((r) {
      if (mounted) setState(() => _connectivityResult = r);
    });
  }

  Future<void> _initializeGPS() async {
    if (!_configService.appConfig.features.gpsEnabled) return;

    final enabled = await Geolocator.isLocationServiceEnabled();
    setState(() => _isGPSEnabled = enabled);

    if (!enabled) return;

    final hasPermission = await _gpsService.requestPermission();
    if (!hasPermission) return;

    try {
      final position = await _gpsService.getCurrentPosition();
      if (position != null && mounted) {
        setState(() {
          _currentPosition = position;
          _currentAddress = _gpsService.getLastKnownAddress();
        });
      }

      _positionSubscription?.cancel();
      _positionSubscription =
          _gpsService.getPositionStream().listen((position) {
        if (mounted) {
          setState(() {
            _currentPosition = position;
            _currentAddress = _gpsService.getLastKnownAddress();
          });
        }
      });
    } catch (e) {
      print('GPS init error: $e');
    }
  }

  Future<void> _initializeCamera() async {
    if (widget.camera == null) return;

    // high, not medium: the same capture feeds ML Kit OCR for Read & Explain,
    // and medium (~480p) can't resolve 6pt print on a medicine strip or a bill.
    // audio off since we never record video.
    _cameraController = CameraController(
      widget.camera!,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _showCameraError = false;
          _initialized = true;
        });
        _announceReady();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _showCameraError = true;
          _initialized = true;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _positionSubscription?.cancel();
    _gpsService.dispose();
    _voiceAssistant.dispose();
    _keySub?.cancel();
    _tts.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized)
      return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _suspendPreview();
      if (_voiceAssistantActive) _voiceAssistant.stopListening();
    } else if (state == AppLifecycleState.resumed) {
      // Only resume if we're the visible route — otherwise the chat screen is
      // still on top and the preview should stay suspended.
      if (ModalRoute.of(context)?.isCurrent ?? true) _resumePreview();
      if (_voiceAssistantActive) _voiceAssistant.startListening();
      // Settings can clear this flag to replay the tutorial.
      if (!_showOnboarding) {
        _cacheService.getBool('onboarding_seen').then((seen) {
          if (!seen && mounted) {
            setState(() {
              _onboardingStep = 0;
              _showOnboarding = true;
            });
            _speakOnboardingStep();
          }
        });
      }
    }
  }

  void _onItemTapped(int index) {
    if (_configService.appConfig.features.vibrationFeedback)
      HapticFeedback.lightImpact();
    _voiceAssistant.announce(_getModeName(index));
    setState(() {
      _selectedIndex = index;
    });
  }

  // Swipe cycle: scene description, printed-text reading, and voice chat.
  static const _modeCount = 3;

  String _getModeName(int index) {
    return _localization.isTamil
        ? [
            'ஆராய்வு',
            'படித்து விளக்கு',
            'குரல் அரட்டை'
          ][index.clamp(0, _modeCount - 1)]
        : [
            'Explore',
            'Read & Explain',
            'Voice Chat'
          ][index.clamp(0, _modeCount - 1)];
  }

  String _modeInstruction(bool isTamil) {
    if (_selectedIndex == 2) {
      return isTamil
          ? 'குரல் அரட்டையைத் தொடங்க தட்டவும்'
          : 'Tap to start listening · swipe to switch';
    }
    return isTamil
        ? 'தட்டவும் · ஸ்வைப் செய்து மாற்றவும்'
        : 'Tap anywhere · swipe to switch';
  }

  Future<void> _openVoiceChat() async {
    if (_isProcessing || _emergency.isCountingDown || !mounted) return;
    HapticFeedback.mediumImpact();
    _suspendPreview();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const Chatscreen(autoStartVoice: true),
      ),
    );
    _resumePreview();
  }

  /// Read & Explain only: double-tap the preview to speak a question, then
  /// capture and answer *that* instead of the mode's default prompt.
  Future<void> _askThenCapture() async {
    if (_isProcessing || _emergency.isCountingDown) return;
    HapticFeedback.mediumImpact();
    final q = await VoicePrompt.ask(announce: _voiceAssistant.announce);
    if (!mounted) return;
    if (q == null) {
      _voiceAssistant.announce(
          'Voice input is not available on this phone. Taking a normal photo.');
      return _takePicture();
    }
    if (q.isEmpty) {
      _voiceAssistant.announce("Didn't catch that. Taking a normal photo.");
      return _takePicture();
    }
    _takePicture(question: q);
  }

  Future<void> _takePicture({String? question}) async {
    if (_isProcessing) return;
    if (_selectedIndex == 2) {
      await _openVoiceChat();
      return;
    }

    if (!(_isCameraInitialized &&
        _cameraController != null &&
        _cameraController!.value.isInitialized)) {
      _showSnackBar(_localization.tr('camera_not_initialized'));
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final XFile file = await _cameraController!.takePicture();
      final String prompt = question != null && question.trim().isNotEmpty
          ? question.trim()
          : _buildPrompt();
      Map<String, dynamic>? locationData;

      if (_currentPosition != null &&
          _configService.appConfig.features.gpsEnabled) {
        locationData = await _gpsService.getLocationData();
      }

      if (mounted) {
        // Always-alive camera: suspend the preview stream while the next screen
        // is on top (frees CPU during inference) but never close the session —
        // reopening costs 1-2s, resuming is instant.
        _suspendPreview();
        // Explore (index 0) = scene description via the chat screen.
        // Everything else is document text -> two-stage Read & Explain.
        final Widget next = _selectedIndex == 0
            ? Chatscreen(
                imagePath: file.path,
                prompt: prompt,
                locationData: locationData,
              )
            : ReadExplainScreen(
                imagePath: file.path,
                question: question?.trim().isNotEmpty == true
                    ? question!.trim()
                    : null,
              );
        Navigator.push(context, MaterialPageRoute(builder: (_) => next))
            .then((_) => _resumePreview());
      }
    } catch (e) {
      _showSnackBar('${_localization.tr('error_occurred')}: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  bool _previewSuspended = false;

  void _suspendPreview() {
    final c = _cameraController;
    if (c == null || !c.value.isInitialized || _previewSuspended) return;
    _previewSuspended = true;
    c.pausePreview();
  }

  void _resumePreview() {
    final c = _cameraController;
    if (c == null || !c.value.isInitialized || !_previewSuspended) return;
    _previewSuspended = false;
    c.resumePreview();
  }

  String _buildPrompt() {
    final isTamil = _localization.isTamil;
    // Only Explore (index 0) uses this prompt now — Read & Explain runs its own
    // OCR + explanation pipeline and ignores it.
    String prompt = _configService.getPrompt('explore', isTamil: isTamil);

    if (_currentPosition != null) {
      final locationContext = _configService.getLocationContext(
        isTamil: isTamil,
        address: _currentAddress ?? 'Unknown',
        lat: _currentPosition!.latitude,
        lon: _currentPosition!.longitude,
        accuracy: _currentPosition!.accuracy,
      );
      prompt = '$prompt. $locationContext';
    }

    return prompt;
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.grey[900],
        duration: Duration(seconds: 3),
      ),
    );
  }

  // Voice Assistant Controls
  Future<void> _toggleVoiceAssistant() async {
    if (!_voiceAssistantActive && !_voiceAssistant.sttAvailable) {
      _voiceAssistant.announce(
          'Voice input is not available on this phone. Tap anywhere to capture, '
          'volume down to repeat, swipe to change mode.');
      return;
    }
    setState(() {
      _voiceAssistantActive = !_voiceAssistantActive;
    });

    if (_voiceAssistantActive) {
      await _voiceAssistant.startListening();
      _voiceAssistant
          .announce('Voice assistant activated. Say "Hey Assistant" to begin.');
    } else {
      await _voiceAssistant.stopListening();
      _voiceAssistant.announce('Voice assistant deactivated');
    }
  }

  void _onVoiceCommand(VoiceCommand command) {
    _showSnackBar(
        'Command: ${command.type.name} (${(command.confidence * 100).toInt()}%)');
  }

  @override
  Widget build(BuildContext context) {
    // _initializeAll() is async; the AppBar/body read _configService.appConfig,
    // which throws until configs are loaded. Hold a loader until then.
    if (!_configService.initialized || !_localization.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isTamil = _localization.isTamil;
    final isOnline = _connectivityResult != ConnectivityResult.none;
    final textScale = _textScaleFactor;

    return DebugOverlay(
      // Debug builds only — never on the demo / release APK.
      enabled: kDebugMode,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          // Respect the OS text-size slider, but never below the app's floor
          // (1.0, or 1.5 with Large Text on). Low-vision users lean on both.
          textScaler:
              MediaQuery.textScalerOf(context).clamp(minScaleFactor: textScale),
          boldText: _highContrast,
          highContrast: _highContrast,
        ),
        child: Semantics(
          label: isTamil
              ? 'Logic Legends मुख் ஸ்க்ரீன்'
              : 'Logic Legends Main Screen',
          // No bottom bar, no FAB: the whole preview is the shutter (tap), and a
          // horizontal swipe toggles the two modes. Nothing to find by sight.
          child: Scaffold(
            appBar: _buildAppBar(isTamil, isOnline),
            body: Stack(
              children: [
                _buildBody(isTamil, isOnline),
                if (_showOnboarding) _buildOnboardingOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isTamil, bool isOnline) {
    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: 72,
      titleSpacing: 8, // don't let the actions squeeze the mode name to "Rea…"
      // The most prominent text = what mode you're in and how to use it, big and
      // bold. The address lives in the spoken location sentence, not here.
      title: Semantics(
        header: true,
        liveRegion: true,
        label:
            '${_getModeName(_selectedIndex)} mode. ${_modeInstruction(isTamil)}',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getModeName(_selectedIndex),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              _modeInstruction(isTamil),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      backgroundColor: Colors.black,
      actions: [
        _buildGPSIndicator(),
        _buildNetworkIndicator(isOnline),
        _buildAccessibilityButton(isTamil),
        IconButton(
          icon: const Icon(Icons.mail_outline, color: Colors.blue),
          tooltip: 'Read my messages',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const InboxScreen()),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings, color: Colors.blue),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
          tooltip: _localization.tr('settings'),
        ),
      ],
    );
  }

  Widget _buildAccessibilityButton(bool isTamil) {
    return Semantics(
      button: true,
      label: isTamil ? 'அணுகல் அமைப்புகள்' : 'Accessibility Settings',
      child: PopupMenuButton<String>(
        icon: Icon(Icons.accessibility_new,
            color: _highContrast || _largeText ? Colors.amber : Colors.grey),
        tooltip: 'Accessibility Options',
        onSelected: (value) {
          setState(() {
            switch (value) {
              case 'high_contrast':
                _highContrast = !_highContrast;
                _saveAccessibilitySetting('high_contrast', _highContrast);
                break;
              case 'large_text':
                _largeText = !_largeText;
                _textScaleFactor = _largeText ? 1.5 : 1.0;
                _saveAccessibilitySetting('large_text', _largeText);
                break;
              case 'voice_assistant':
                _toggleVoiceAssistant();
                break;
            }
          });
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'high_contrast',
            child: Row(
              children: [
                Icon(
                    _highContrast
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    color: _highContrast ? Colors.green : null),
                const SizedBox(width: 8),
                Text(isTamil ? 'உயர் துவிர்ச்சி' : 'High Contrast'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'large_text',
            child: Row(
              children: [
                Icon(
                    _largeText
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    color: _largeText ? Colors.green : null),
                const SizedBox(width: 8),
                Text(isTamil ? 'மேல் வலியான உரை' : 'Large Text'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'voice_assistant',
            child: Row(
              children: [
                Icon(_voiceAssistantActive ? Icons.mic : Icons.mic_none,
                    color: _voiceAssistantActive ? Colors.green : null),
                const SizedBox(width: 8),
                Text(isTamil ? 'குரல் உதவியாளர்' : 'Voice Assistant'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkIndicator(bool isOnline) {
    return Semantics(
      label: isOnline ? 'Online' : 'Offline',
      child: IconButton(
        icon: Icon(
          isOnline ? Icons.wifi : Icons.wifi_off,
          color: isOnline ? Colors.green : Colors.red,
        ),
        onPressed: null,
        tooltip: isOnline
            ? _localization.tr('online_mode')
            : _localization.tr('offline_mode'),
      ),
    );
  }

  Widget _buildGPSIndicator() {
    if (!_configService.appConfig.features.gpsEnabled) {
      return Semantics(
        label: 'GPS Disabled',
        child: IconButton(
          icon: const Icon(Icons.gps_off, color: Colors.grey),
          onPressed: null,
          tooltip: _localization.tr('gps_disabled'),
        ),
      );
    }

    Color indicatorColor;
    IconData icon;
    String tooltip;

    if (!_isGPSEnabled) {
      indicatorColor = Colors.red;
      icon = Icons.gps_off;
      tooltip = _localization.tr('gps_disabled');
    } else if (_currentPosition == null) {
      indicatorColor = Colors.orange;
      icon = Icons.gps_fixed;
      tooltip = _localization.tr('gps_acquiring');
    } else {
      final accuracy = _currentPosition!.accuracy;
      if (accuracy <= _configService.appConfig.gps.accuracyThresholdHigh) {
        indicatorColor = Colors.green;
        icon = Icons.gps_fixed;
        tooltip =
            '${_localization.tr('high_accuracy')}: ${accuracy.toStringAsFixed(1)}m';
      } else if (accuracy <=
          _configService.appConfig.gps.accuracyThresholdMedium) {
        indicatorColor = Colors.yellow;
        icon = Icons.gps_fixed;
        tooltip =
            '${_localization.tr('medium_accuracy')}: ${accuracy.toStringAsFixed(1)}m';
      } else {
        indicatorColor = Colors.orange;
        icon = Icons.gps_fixed;
        tooltip =
            '${_localization.tr('low_accuracy')}: ${accuracy.toStringAsFixed(1)}m';
      }
    }

    return Semantics(
      label: tooltip,
      button: true,
      hint: 'Double tap for GPS details',
      child: IconButton(
        icon: Icon(icon, color: indicatorColor),
        onPressed: _showGPSDetails,
        tooltip: tooltip,
      ),
    );
  }

  Widget _buildBody(bool isTamil, bool isOnline) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_showCameraError) {
      return _buildCameraErrorView(isTamil);
    }

    if (!_isCameraInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _localization.tr('initializing_camera'),
              style: TextStyle(fontSize: 16 * _textScaleFactor),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Blind users can't find the shutter button — the whole preview is it.
        // Double-tap is reserved for the debug overlay, so use single tap.
        Semantics(
          button: true,
          label: isTamil
              ? 'படம் எடுக்க எங்கும் தட்டவும்'
              : (_selectedIndex == 2
                  ? 'Tap anywhere to start Voice Chat'
                  : 'Tap anywhere to take a photo'),
          hint: isTamil
              ? 'அவசரத்திற்கு நீண்ட நேரம் அழுத்தவும். ஸ்வைப் செய்து மோடு மாற்றவும்.'
              : (_selectedIndex == 1
                  ? 'Double-tap to ask a question first. Long-press for emergency. Swipe to change mode.'
                  : 'Long-press for emergency. Swipe to change mode.'),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_emergency.isCountingDown) {
                _cancelEmergency();
              } else if (!_isProcessing) {
                if (_selectedIndex == 2) {
                  _openVoiceChat();
                } else {
                  _takePicture();
                }
              }
            },
            // Double-tap = speak a question first — ONLY in Read & Explain
            // (index 1). Registering it only for that mode keeps the plain
            // capture tap in Explore instant (no ~300ms disambiguation wait).
            onDoubleTap: _selectedIndex == 1 ? _askThenCapture : null,
            // Long-press is the eyes-free way to reach emergency without voice.
            onLongPress: _triggerEmergencySOS,
            onHorizontalDragEnd: (d) {
              // A swipe during the countdown aborts it, like a tap does.
              if (_emergency.isCountingDown) {
                _cancelEmergency();
                return;
              }
              final v = d.primaryVelocity ?? 0;
              if (v.abs() < 200) return;
              final next =
                  (_selectedIndex + (v < 0 ? 1 : -1)).clamp(0, _modeCount - 1);
              if (next != _selectedIndex) _onItemTapped(next);
            },
            child: SizedBox.expand(child: CameraPreview(_cameraController!)),
          ),
        ),
        // GPS accuracy is on the AppBar indicator; the floating badge is
        // diagnostic clutter on the demo build.
        if (kDebugMode) _buildGPSOverlay(),
        if (!_isProcessing && _emergencyCountdown == null)
          _buildTapAffordance(isTamil),
        if (!isOnline) _buildOfflineBanner(isTamil),
        if (_isProcessing) _buildProcessingOverlay(isTamil),
        _buildVoiceAssistantOverlay(isTamil),
        if (_emergencyCountdown != null) _buildEmergencyOverlay(isTamil),
      ],
    );
  }

  /// Big, high-contrast "what do I do here" cue on the preview. Decorative —
  /// IgnorePointer lets the tap fall through to the shutter behind it, and the
  /// parent GestureDetector already carries the Semantics.
  Widget _buildTapAffordance(bool isTamil) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 48,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  _selectedIndex == 0
                      ? (isTamil ? 'விவரிக்க தட்டவும்' : 'TAP TO DESCRIBE')
                      : _selectedIndex == 1
                          ? (isTamil ? 'படிக்க தட்டவும்' : 'TAP TO READ')
                          : (isTamil
                              ? 'குரல் அரட்டைக்கு தட்டவும்'
                              : 'TAP TO START VOICE CHAT'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isTamil
                      ? 'மோடு மாற்ற ஸ்வைப் செய்யவும்'
                      : 'swipe  ←  →  to switch mode',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOnboardingOverlay() {
    final step = _onboardingStep;
    final total = _onboardingSteps.length;
    final isLast = step == total - 1;
    return Positioned.fill(
      child: Semantics(
        liveRegion: true,
        button: true,
        label: '${_onboardingSteps[step]} '
            '${isLast ? 'Tap to open settings.' : 'Tap for the next tip.'} '
            'Swipe to skip the tutorial.',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _advanceOnboarding,
          onHorizontalDragEnd: (_) => _finishOnboarding(),
          onVerticalDragEnd: (_) => _finishOnboarding(),
          child: Container(
            color: Colors.black.withValues(alpha: 0.95),
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Tip ${step + 1} of $total',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Text(
                        _onboardingSteps[step],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    isLast ? 'TAP TO OPEN SETTINGS' : 'TAP FOR NEXT TIP',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => _finishOnboarding(),
                  child: const Text(
                    'Skip tutorial',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmergencyOverlay(bool isTamil) {
    return Positioned.fill(
      child: Semantics(
        liveRegion: true,
        button: true,
        label: isTamil
            ? 'அவசர அழைப்பு $_emergencyCountdown வினாடிகளில். ரத்து செய்ய தட்டவும்.'
            : 'Emergency call in $_emergencyCountdown seconds. Tap to cancel.',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _cancelEmergency,
          child: Container(
            color: Colors.red.withValues(alpha: 0.85),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$_emergencyCountdown',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 96 * _textScaleFactor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    isTamil
                        ? 'அவசர தொடர்பை அழைக்கிறது.\nரத்து செய்ய எங்கும் தட்டவும்.'
                        : 'Calling your emergency contact.\nTap anywhere to cancel.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20 * _textScaleFactor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceAssistantOverlay(bool isTamil) {
    if (!_voiceAssistantActive) return const SizedBox.shrink();

    return Positioned(
      bottom: 100,
      left: 16,
      right: 16,
      child: Semantics(
        liveRegion: true,
        label:
            isTamil ? 'குரல் உதவியாளர் செயலாகிறது' : 'Voice Assistant Active',
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.greenAccent, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.mic, color: Colors.greenAccent, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _voiceStatus.isNotEmpty
                          ? _voiceStatus
                          : (isTamil
                              ? 'குரல் உதவியாளர் செயலாகிறது...'
                              : 'Voice Assistant Active...'),
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 14 * _textScaleFactor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_lastTranscription.isNotEmpty)
                    Flexible(
                      child: Text(
                        '"$_lastTranscription"',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12 * _textScaleFactor,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildVoiceCommandHint('Take Photo', Icons.camera_alt),
                  _buildVoiceCommandHint('Read Text', Icons.text_fields),
                  _buildVoiceCommandHint('Identify Food', Icons.restaurant),
                  _buildVoiceCommandHint('Where Am I', Icons.location_on),
                  _buildVoiceCommandHint('Search Web', Icons.search),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceCommandHint(String label, IconData icon) {
    final isTamil = _localization.isTamil;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: isTamil ? 'குரல் கட்டளை: "$label"' : 'Voice command: "$label"',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white54, size: 20),
            Text(
              label,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 9 * _textScaleFactor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineBanner(bool isTamil) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Semantics(
        liveRegion: true,
        label: isTamil ? 'ஆஃப்லைன் பதிவு செயல்படுகிறது' : 'Offline Mode Active',
        child: Container(
          color: Colors.orange[800],
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                isTamil
                    ? 'ஆஃப்லைன் பதிவு - சேமிக்கப்பட்ட பதில்கள் காட்டுகிறது'
                    : 'Offline Mode - Showing cached responses',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProcessingOverlay(bool isTamil) {
    return Semantics(
      liveRegion: true,
      label: isTamil ? 'செயலாக்குகிறது...' : 'Processing...',
      child: Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              Text(
                _localization.tr('processing'),
                style: TextStyle(
                    color: Colors.white, fontSize: 16 * _textScaleFactor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGPSOverlay() {
    if (!_configService.appConfig.features.gpsEnabled ||
        _currentPosition == null) {
      return const SizedBox.shrink();
    }

    final accuracy = _currentPosition!.accuracy;
    final color = accuracy <= 10
        ? Colors.green
        : (accuracy <= 50 ? Colors.yellow : Colors.orange);

    return Positioned(
      top: 10,
      right: 10,
      child: Semantics(
        label: 'GPS Accuracy: ${accuracy.toStringAsFixed(1)} meters',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                '${accuracy.toStringAsFixed(1)}m',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGPSDetails() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _buildGPSBottomSheet(),
    );
  }

  Widget _buildGPSBottomSheet() {
    final isTamil = _localization.isTamil;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _localization.tr('gps_status'),
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20 * _textScaleFactor,
                    fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildGPSInfoRow(
              _localization.tr('status'),
              _isGPSEnabled
                  ? _localization.tr('gps_enabled')
                  : _localization.tr('gps_disabled')),
          _buildGPSInfoRow(
              _localization.tr('permission'),
              _currentPosition != null
                  ? _localization.tr('granted')
                  : _localization.tr('pending')),
          if (_currentPosition != null) ...[
            _buildGPSInfoRow(_localization.tr('latitude'),
                _currentPosition!.latitude.toStringAsFixed(6)),
            _buildGPSInfoRow(_localization.tr('longitude'),
                _currentPosition!.longitude.toStringAsFixed(6)),
            _buildGPSInfoRow(_localization.tr('altitude'),
                '${_currentPosition!.altitude.toStringAsFixed(1)} m'),
            _buildGPSInfoRow(_localization.tr('accuracy'),
                '${_currentPosition!.accuracy.toStringAsFixed(1)} m'),
            _buildGPSInfoRow(_localization.tr('speed'),
                '${(_currentPosition!.speed * 3.6).toStringAsFixed(1)} km/h'),
            _buildGPSInfoRow(_localization.tr('heading'),
                '${_currentPosition!.heading.toStringAsFixed(0)}°'),
            _buildGPSInfoRow(_localization.tr('address'),
                _currentAddress ?? _localization.tr('resolving')),
            _buildGPSInfoRow(_localization.tr('last_update'),
                _currentPosition!.timestamp.toLocal().toString().split('.')[0]),
          ],
          const SizedBox(height: 20),
          if (!_isGPSEnabled)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.settings),
                label: Text(_localization.tr('enable_gps')),
                onPressed: () async {
                  Navigator.pop(context);
                  await _gpsService.openLocationSettings();
                },
              ),
            ),
          if (_isGPSEnabled && _currentPosition == null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: Text(_localization.tr('retry_gps')),
                onPressed: () async {
                  Navigator.pop(context);
                  _initializeGPS();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGPSInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                  color: Colors.white70, fontSize: 14 * _textScaleFactor),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                  color: Colors.white, fontSize: 14 * _textScaleFactor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraErrorView(bool isTamil) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.camera_alt, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            _localization.tr('camera_not_available'),
            style:
                TextStyle(fontSize: 18 * _textScaleFactor, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              if (widget.camera != null) {
                _initializeCamera();
              }
            },
            child: Text(_localization.tr('retry_camera')),
          ),
        ],
      ),
    );
  }
}
