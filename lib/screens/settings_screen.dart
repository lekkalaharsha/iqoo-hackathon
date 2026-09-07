import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/config_service.dart';
import '../services/localization_service.dart';
import '../services/ai_service.dart';
import '../services/offline_cache_service.dart';
import '../services/voice_assistant_service.dart';
import '../services/emergency_service.dart';
import '../services/speech_config.dart';
import '../widgets/debug_overlay.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ConfigService _configService = ConfigService();
  final LocalizationService _localization = LocalizationService();
  final AIService _aiService = AIService();
  final OfflineCacheService _cacheService = OfflineCacheService();
  final VoiceAssistantService _voiceAssistant = VoiceAssistantService();

  bool _offlineMode = false;
  bool _gpsEnabled = false;
  bool _ttsEnabled = false;
  bool _vibrationFeedback = false;
  bool _voiceAssistantEnabled = false;
  bool _shakeWakeWord = false;
  bool _highContrast = false;
  bool _largeText = false;
  bool _accessibilityMode = false;
  bool _debugOverlay = false;
  String _locale = 'en';
  String? _emergencyContact;
  String? _emergencyLabel;
  double _speechRate = SpeechConfig.rate;
  bool _briefAnswers = false;
  Map<String, dynamic>? _cacheStats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _configService.initialize();
    await _localization.initialize();
    await _cacheService.initialize();
    // Don't block the UI on voice-assistant init (it can hang on the mic
    // permission dialog / recorder). Fire it off; toggles work regardless.
    _voiceAssistant.initialize().catchError(
        (e) => debugPrint('Voice assistant init failed: $e'));

    setState(() {
      _offlineMode = _configService.appConfig.features.offlineMode;
      _gpsEnabled = _configService.appConfig.features.gpsEnabled;
      _ttsEnabled = _configService.appConfig.features.ttsEnabled;
      _vibrationFeedback = _configService.appConfig.features.vibrationFeedback;
      _voiceAssistantEnabled = _configService.appConfig.features.voiceAssistant;
      _shakeWakeWord = _configService.appConfig.features.shakeWakeWord;
      _highContrast = _configService.appConfig.features.highContrast;
      _largeText = _configService.appConfig.features.largeText;
      _accessibilityMode = _configService.appConfig.features.accessibilityMode;
      _locale = _localization.currentLocale;
      _loading = false;
    });
    await SpeechConfig.ensurePrefs();
    final contact = await EmergencyService.getContact();
    final label = await EmergencyService.getContactLabel();
    if (mounted) {
      setState(() {
        _emergencyContact = contact;
        _emergencyLabel = label;
        _speechRate = SpeechConfig.rate;
        _briefAnswers = SpeechConfig.briefAnswers;
      });
    }
    await _loadCacheStats();
  }

  Future<void> _nudgeRate(double delta) async {
    final next = (_speechRate + delta)
        .clamp(SpeechConfig.minRate, SpeechConfig.maxRate);
    await SpeechConfig.setRate(next);
    if (mounted) setState(() => _speechRate = SpeechConfig.rate);
    await SpeechConfig.tts.stop();
    await SpeechConfig.tts
        .speak(delta < 0 ? 'Slower. This is the new speed.' : 'Faster. This is the new speed.');
  }

  Future<void> _loadCacheStats() async {
    final stats = await _cacheService.getCacheStats();
    if (mounted) setState(() => _cacheStats = stats);
  }

  Future<void> _toggleFeature(String feature, bool value) async {
    setState(() {
      switch (feature) {
        case 'on_device_llm':
          _aiService.setUseOnDevice(value);
          break;
        case 'offline_mode':
          _offlineMode = value;
          break;
        case 'gps_enabled':
          _gpsEnabled = value;
          break;
        case 'tts_enabled':
          _ttsEnabled = value;
          break;
        case 'vibration_feedback':
          _vibrationFeedback = value;
          break;
        case 'web_browsing':
          break;
        case 'voice_assistant':
          _voiceAssistantEnabled = value;
          if (value) {
            _voiceAssistant.startListening();
          } else {
            _voiceAssistant.stopListening();
          }
          break;
        case 'shake_wake_word':
          _shakeWakeWord = value;
          _voiceAssistant.setShakeThreshold(value ? 15.0 : 100.0);
          break;
        case 'high_contrast':
          _highContrast = value;
          break;
        case 'large_text':
          _largeText = value;
          break;
        case 'accessibility_mode':
          _accessibilityMode = value;
          _voiceAssistant.setAccessibilityMode(value);
          break;
        case 'debug_overlay':
          _debugOverlay = value;
          break;
      }
    });
    
    await _configService.updateFeature(feature, value);
  }

  Future<void> _clearCache() async {
    await _cacheService.clearCache();
    await _loadCacheStats();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_localization.tr('cache_cleared', params: {}))),
      );
    }
  }

  Future<void> _testVoiceAssistant() async {
    _voiceAssistant.announce('Voice assistant test successful. All systems operational.');
  }

  Future<void> _setEmergencyContact() async {
    final numberCtl =
        TextEditingController(text: await EmergencyService.getContact() ?? '');
    final labelCtl = TextEditingController(
        text: await EmergencyService.getContactLabel() ?? '');
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emergency contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name (spoken aloud)',
                hintText: 'e.g. Amma',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: numberCtl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                hintText: '+91…',
                helperText: 'A person you trust — not emergency services.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != true) return;
    final number = numberCtl.text.trim();
    if (number.isEmpty) return;
    await EmergencyService.setContact(number);
    await EmergencyService.setContactLabel(labelCtl.text);
    await EmergencyService.ensurePermission();
    if (!mounted) return;
    final label = labelCtl.text.trim();
    setState(() {
      _emergencyContact = number;
      _emergencyLabel = label.isEmpty ? null : label;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(label.isEmpty
              ? 'Emergency contact set to $number'
              : 'Emergency contact set to $label ($number)')),
    );
  }

  Future<void> _setWakeWord() async {
    final controller = TextEditingController(text: _configService.voiceAssistantConfig.wakeWord);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_localization.tr('wake_word')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: _localization.tr('wake_word_desc'),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_localization.tr('try_again')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(_localization.tr('settings')),
          ),
        ],
      ),
    );
    
    if (result != null && result.isNotEmpty) {
      _voiceAssistant.setWakeWord(result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Wake word set to: $result')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTamil = _locale == 'ta';
    
    return Scaffold(
      appBar: AppBar(
        title: Text(isTamil ? 'அமைப்புகள்' : 'Settings'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSection(isTamil ? 'AI மாதிரி' : 'AI Model', [
                  // On-Device LLM and Web Browsing toggles removed: neither is
                  // wired (the on-device seam GemmaBackend is a stub; web
                  // browsing has no working destination). Re-add when they
                  // actually do something.
                  _buildSwitchTile(
                    title: 'Offline Mode',
                    subtitle: 'Use cached responses when offline',
                    value: _offlineMode,
                    onChanged: (v) => _toggleFeature('offline_mode', v),
                    leading: Icon(_offlineMode ? Icons.wifi_off : Icons.wifi, color: _offlineMode ? Colors.green : Colors.grey),
                  ),
                  _buildSwitchTile(
                    title: 'Cache Responses',
                    subtitle: _cacheStats != null ? '${_cacheStats!['entries']} entries, ${_cacheStats!['sizeKB']} KB' : 'Loading...',
                    value: true,
                    onChanged: (v) {},
                    leading: const Icon(Icons.storage),
                    trailing: TextButton(
                      onPressed: _clearCache,
                      child: Text(isTamil ? 'தீர்ப்பு' : 'Clear Cache'),
                    ),
                  ),
                ]),
                _buildSection(isTamil ? 'குரல் உதவியாளர்' : 'Voice Assistant', [
                  _buildSwitchTile(
                    title: _localization.tr('voice_assistant'),
                    subtitle: _localization.tr('voice_assistant_desc'),
                    value: _voiceAssistantEnabled,
                    onChanged: (v) => _toggleFeature('voice_assistant', v),
                    leading: Icon(_voiceAssistantEnabled ? Icons.mic : Icons.mic_none, color: _voiceAssistantEnabled ? Colors.green : Colors.grey),
                    trailing: TextButton(
                      onPressed: _testVoiceAssistant,
                      child: Text(isTamil ? 'சோதி' : 'Test'),
                    ),
                  ),
                  _buildSwitchTile(
                    title: _localization.tr('shake_wake_word'),
                    subtitle: _localization.tr('shake_wake_word_desc'),
                    value: _shakeWakeWord,
                    onChanged: (v) => _toggleFeature('shake_wake_word', v),
                    leading: Icon(_shakeWakeWord ? Icons.sensors : Icons.sensors_off, color: _shakeWakeWord ? Colors.green : Colors.grey),
                  ),
                  ListTile(
                    leading: Icon(_voiceAssistantEnabled ? Icons.mic : Icons.mic_none, color: _voiceAssistantEnabled ? Colors.green : Colors.grey),
                    title: Text(_localization.tr('wake_word')),
                    subtitle: Text(_configService.voiceAssistantConfig.wakeWord),
                    onTap: _setWakeWord,
                    trailing: const Icon(Icons.edit, color: Colors.blue),
                  ),
                ]),
                _buildSection('Speaking', [
                  ListTile(
                    leading: const Icon(Icons.speed),
                    title: const Text('Speaking speed'),
                    subtitle: Text(
                        '${(_speechRate * 100).round()}% — use the buttons to adjust'),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.remove),
                            label: const Text('Slower'),
                            onPressed: _speechRate <= SpeechConfig.minRate
                                ? null
                                : () => _nudgeRate(-0.05),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Faster'),
                            onPressed: _speechRate >= SpeechConfig.maxRate
                                ? null
                                : () => _nudgeRate(0.05),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () async {
                            await SpeechConfig.tts.stop();
                            await SpeechConfig.tts.speak(
                                'This is a test of the speaking speed. Adjust it until it is comfortable.');
                          },
                          child: const Text('Test'),
                        ),
                      ],
                    ),
                  ),
                  _buildSwitchTile(
                    title: 'Brief answers',
                    subtitle: 'One short sentence instead of up to three',
                    value: _briefAnswers,
                    onChanged: (v) async {
                      await SpeechConfig.setBriefAnswers(v);
                      setState(() => _briefAnswers = v);
                    },
                    leading: Icon(_briefAnswers ? Icons.short_text : Icons.notes,
                        color: _briefAnswers ? Colors.green : Colors.grey),
                  ),
                ]),
                _buildSection('Accessibility', [
                  _buildSwitchTile(
                    title: _localization.tr('tts_enabled'),
                    subtitle: _localization.tr('tts_desc'),
                    value: _ttsEnabled,
                    onChanged: (v) => _toggleFeature('tts_enabled', v),
                    leading: Icon(_ttsEnabled ? Icons.volume_up : Icons.volume_off, color: _ttsEnabled ? Colors.green : Colors.grey),
                  ),
                  _buildSwitchTile(
                    title: _localization.tr('vibration_feedback'),
                    subtitle: _localization.tr('vibration_desc'),
                    value: _vibrationFeedback,
                    onChanged: (v) => _toggleFeature('vibration_feedback', v),
                    leading: Icon(_vibrationFeedback ? Icons.vibration : Icons.vibration_outlined, color: _vibrationFeedback ? Colors.green : Colors.grey),
                  ),
                  _buildSwitchTile(
                    title: _localization.tr('high_contrast'),
                    subtitle: _localization.tr('high_contrast_desc'),
                    value: _highContrast,
                    onChanged: (v) => _toggleFeature('high_contrast', v),
                    leading: Icon(_highContrast ? Icons.contrast : Icons.contrast_outlined, color: _highContrast ? Colors.green : Colors.grey),
                  ),
                  _buildSwitchTile(
                    title: _localization.tr('large_text'),
                    subtitle: _localization.tr('large_text_desc'),
                    value: _largeText,
                    onChanged: (v) => _toggleFeature('large_text', v),
                    leading: Icon(_largeText ? Icons.text_increase : Icons.text_decrease, color: _largeText ? Colors.green : Colors.grey),
                  ),
                  _buildSwitchTile(
                    title: _localization.tr('accessibility_mode'),
                    subtitle: _localization.tr('accessibility_desc'),
                    value: _accessibilityMode,
                    onChanged: (v) => _toggleFeature('accessibility_mode', v),
                    leading: Icon(_accessibilityMode ? Icons.accessibility : Icons.accessibility_outlined, color: _accessibilityMode ? Colors.green : Colors.grey),
                  ),
                ]),
                _buildSection(isTamil ? 'அம்சங்கள்' : 'Features', [
                  _buildSwitchTile(
                    title: 'GPS Enabled',
                    subtitle: 'Location context for AI prompts',
                    value: _gpsEnabled,
                    onChanged: (v) => _toggleFeature('gps_enabled', v),
                    leading: Icon(_gpsEnabled ? Icons.gps_fixed : Icons.gps_off, color: _gpsEnabled ? Colors.green : Colors.grey),
                  ),
                  ListTile(
                    leading: Icon(Icons.emergency_share,
                        color: _emergencyContact == null ? Colors.grey : Colors.red),
                    title: Text(isTamil ? 'அவசர தொடர்பு' : 'Emergency contact'),
                    subtitle: Text(_emergencyContact == null
                        ? 'Not set — long-press the camera to call'
                        : _emergencyLabel == null
                            ? _emergencyContact!
                            : '$_emergencyLabel · $_emergencyContact'),
                    onTap: _setEmergencyContact,
                    trailing: const Icon(Icons.edit, color: Colors.blue),
                  ),
                ]),
                _buildSection(isTamil ? 'அதிகமொழி' : 'Advanced', [
                  _buildSwitchTile(
                    title: 'Debug Overlay',
                    subtitle: 'FPS, GPS, Cache, Network stats (double-tap to toggle)',
                    value: _debugOverlay,
                    onChanged: (v) => _toggleFeature('debug_overlay', v),
                    leading: Icon(_debugOverlay ? Icons.bug_report : Icons.bug_report_outlined, color: _debugOverlay ? Colors.red : Colors.grey),
                  ),
                ]),
                _buildSection(isTamil ? 'உதவி & கட்டளைகள்' : 'Help & Commands', [
                  ListTile(
                    leading: const Icon(Icons.school_outlined),
                    title: const Text('How to use Logic Legends'),
                    subtitle: const Text('Replay the spoken tutorial'),
                    onTap: () async {
                      await _cacheService.setBool('onboarding_seen', false);
                      if (mounted) Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: Text(_localization.tr('help')),
                    subtitle: Text(_localization.tr('help_text')),
                    onTap: () => _showHelpDialog(),
                  ),
                  ListTile(
                    leading: const Icon(Icons.keyboard_voice),
                    title: Text(_localization.tr('commands')),
                    subtitle: Text(_localization.tr('capture_photo') + ', ' + _localization.tr('describe_scene') + ', ' + _localization.tr('identify_food') + ', ' + _localization.tr('read_text') + ', ' + _localization.tr('analyze_document') + ', ' + _localization.tr('get_location') + ', ' + _localization.tr('search_web') + ', ' + _localization.tr('read_last_response') + ', ' + _localization.tr('switch_mode') + ', ' + _localization.tr('emergency')),
                    onTap: () => _showCommandsDialog(),
                  ),
                ]),
                _buildSection(isTamil ? 'பற்றி' : 'About', [
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(isTamil ? 'பதிப்பு' : 'Version'),
                    subtitle: Text('${_configService.appConfig.app.version} (${_configService.appConfig.app.build})'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.code),
                    title: Text(isTamil ? 'ஐகூ ஹேக்கதான் 2026 - சென்னை' : 'iQOO Hackathon 2026 - Chennai'),
                    subtitle: Text(isTamil ? 'தொலைநிலை-முதலமையான AI உதவி' : 'Phone-first AI Assistant'),
                  ),
                ]),
              ],
            ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_localization.tr('help')),
        content: SingleChildScrollView(
          child: Text(_localization.tr('help_text')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_localization.tr('try_again')),
          ),
        ],
      ),
    );
  }

  void _showCommandsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_localization.tr('commands')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCommandRow(_localization.tr('capture_photo'), '"Take photo", "Snap picture"'),
              _buildCommandRow(_localization.tr('describe_scene'), '"Describe scene", "What do you see"'),
              _buildCommandRow(_localization.tr('identify_food'), '"Identify food", "Nutrition info"'),
              _buildCommandRow(_localization.tr('read_text'), '"Read text", "Scan text"'),
              _buildCommandRow(_localization.tr('analyze_document'), '"Analyze document", "Read document"'),
              _buildCommandRow(_localization.tr('get_location'), '"Where am I", "My location"'),
              _buildCommandRow(_localization.tr('get_directions'), '"Navigate to [place]"'),
              _buildCommandRow(_localization.tr('search_web'), '"Search [topic]", "Weather", "News"'),
              _buildCommandRow(_localization.tr('read_last_response'), '"Read last response", "Repeat"'),
              _buildCommandRow(_localization.tr('switch_mode'), '"Switch to explore / read and explain / voice chat"'),
              _buildCommandRow(_localization.tr('toggle_feature'), '"Enable GPS/TTS/Vibration/Browsing"'),
              _buildCommandRow(_localization.tr('emergency'), '"Emergency", "Help me", "SOS"'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_localization.tr('try_again')),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandRow(String command, String examples) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              command,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              examples,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent),
          ),
        ),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(children: children),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Widget leading,
    Widget? trailing,
  }) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
      secondary: leading,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}