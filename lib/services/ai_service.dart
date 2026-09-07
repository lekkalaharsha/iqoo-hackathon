import '../screens/constapi.dart';
import 'package:flutter/foundation.dart';
import '../services/browsing_service.dart';
import '../services/config_service.dart';
import '../services/localization_service.dart';
import '../services/plain_text.dart';
import 'llm/llm_backend.dart';
import 'llm/gemini_backend.dart';
import 'llm/gemma_backend.dart';

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  final BrowsingService _browsing = BrowsingService();
  final ConfigService _configService = ConfigService();
  final LocalizationService _localization = LocalizationService();

  /// The one text-generation seam. On-device is tried first when ready; cloud
  /// is the fallback. Swapping the on-device path to a real model is a change
  /// to [GemmaBackend] alone — nothing here or in callers moves.
  final LlmBackend _cloud = GeminiBackend(apiKey: GEMINI_API_KEY);
  final LlmBackend _onDevice = GemmaBackend();

  bool get cloudConfigured => _cloud.isReady;
  String? lastFailureMessage;
  bool _useOnDevice = false;
  bool _initialized = false;

  bool get useOnDevice => _useOnDevice;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;

    await _configService.initialize();
    await _localization.initialize();
    await _cloud.initialize();

    if (_configService.appConfig.features.onDeviceLLM) {
      await _onDevice.initialize();
      _useOnDevice = _onDevice.isReady;
    }

    _initialized = true;
  }

  Future<String?> generateResponse({
    required String prompt,
    List<Uint8List>? images,
    required bool isTamil,
    bool enableBrowsing = true,
  }) async {
    lastFailureMessage = null;
    if (!_cloud.isReady && !_useOnDevice) {
      lastFailureMessage = _messageForFailure(LlmFailure.notReady);
      return null;
    }
    // Check if prompt needs real-world info
    String finalPrompt = prompt;
    String? browsingContext;

    if (enableBrowsing && _shouldBrowse(prompt)) {
      browsingContext = await _fetchBrowsingContext(prompt, isTamil);
      if (browsingContext != null && browsingContext.isNotEmpty) {
        finalPrompt = _injectBrowsingContext(prompt, browsingContext, isTamil);
      }
    }

    // On-device first when ready; cloud otherwise.
    if (_useOnDevice && _onDevice.isReady) {
      final onDeviceResult =
          await _onDevice.generate(prompt: finalPrompt, images: images);
      if (onDeviceResult.hasText) {
        return _formatResponse(onDeviceResult.value!, browsingContext);
      }
      // Fall through to cloud on any on-device failure.
    }

    // A photo is a few hundred KB of base64 on top of the request; on real
    // mobile data that upload alone can take longer than a text call's budget.
    final hasImage = images != null && images.isNotEmpty;
    final result = await _cloud.generate(
      prompt: finalPrompt,
      images: images,
      timeout: hasImage
          ? const Duration(seconds: 45)
          : const Duration(seconds: 25),
    );
    if (result.hasText) {
      return _formatResponse(result.value!, browsingContext);
    }
    if (result.failure != null) {
      lastFailureMessage = _messageForFailure(result.failure!);
    }
    return null;
  }

  /// Text-only explanation with the first sentence delivered fast. Used by the
  /// Read & Explain flow: OCR text in, spoken plain-language guidance out.
  ///
  /// [onSentence] fires as soon as each sentence is complete so TTS can begin
  /// before the whole answer generates. Returns the full text, or null on
  /// failure / timeout so the caller can speak its own fallback.
  Future<String?> explain(
    String promptText, {
    void Function(String sentence)? onSentence,
    // Generous — this is the "answer or we speak the template" budget, and on
    // mobile data 6s isn't enough for the round trip plus generation.
    Duration timeout = const Duration(seconds: 25),
  }) async {
    // On-device first once GemmaBackend is wired; cloud today. Either way the
    // full text is split into sentences here so TTS can start on sentence one.
    if (!_cloud.isReady && !(_useOnDevice && _onDevice.isReady)) return null;

    if (_useOnDevice && _onDevice.isReady) {
      final onDeviceResult =
          await _onDevice.generate(prompt: promptText, timeout: timeout);
      if (onDeviceResult.hasText) {
        final clean = toPlainSpeech(onDeviceResult.value!);
        _emitSentences(clean, onSentence);
        return clean;
      }
    }

    final result = await _cloud.generate(prompt: promptText, timeout: timeout);
    if (result.hasText) {
      final clean = toPlainSpeech(result.value!);
      _emitSentences(clean, onSentence);
      return clean;
    }
    return null;
  }

  void _emitSentences(String text, void Function(String)? onSentence) {
    for (final sentence in _spokenSentences(text)) {
      onSentence?.call(sentence);
    }
  }

  Iterable<String> _spokenSentences(String text) sync* {
    final matches = RegExp(r'[^.!?]+[.!?]?(?:\s+|$)').allMatches(text);
    for (final match in matches) {
      final sentence = match.group(0)?.trim() ?? '';
      if (sentence.isNotEmpty) yield sentence;
    }
  }

  String _messageForFailure(LlmFailure reason) => switch (reason) {
        LlmFailure.notReady || LlmFailure.unsupported =>
          'Scene descriptions are not set up yet. '
              'You can still use Read and Explain to read printed text.',
        LlmFailure.unauthorized =>
          'The assistant setup was rejected. Check the Gemini key.',
        LlmFailure.quota =>
          'The assistant usage limit was reached. Try again shortly.',
        LlmFailure.invalidRequest =>
          'The assistant could not process this photo. Try another photo.',
        LlmFailure.unavailable || LlmFailure.emptyResponse =>
          'The assistant is temporarily unavailable. Try again shortly.',
        LlmFailure.timeout || LlmFailure.network =>
          'The assistant could not connect. Check your internet and try again.',
      };

  bool _shouldBrowse(String prompt) {
    final lowerPrompt = prompt.toLowerCase();

    // Keywords that suggest need for real-time info
    final browseKeywords = [
      'latest',
      'current',
      'recent',
      'today',
      'now',
      '2024',
      '2025',
      'price',
      'cost',
      'rate',
      'weather',
      'news',
      'update',
      'near me',
      'nearby',
      'hours',
      'open',
      'contact',
      'phone',
      'nutrition',
      'calories',
      'ingredients',
      'allergen',
      'review',
      'rating',
      'best',
      'top',
      'compare',
      'how to',
      'tutorial',
      'guide',
      'steps',
      'definition',
      'meaning',
      'what is',
      'who is',
      'latest version',
      'release',
      'launch',
      'அद्यதன்',
      'தற்போதைய',
      'இன்று',
      'விலை',
      'வீட்டு',
      'வ Gefangenen',
      'செய்தி',
      'பதிவாதம்',
      'மு�தலியavel',
      'அருகே',
      'நேரம்',
      'தொடர்பு',
      'கலாரி',
      'விமர்சனம்',
      'எப்படி',
      'என்ன',
      'யார்',
    ];

    return browseKeywords.any((kw) => lowerPrompt.contains(kw));
  }

  Future<String?> _fetchBrowsingContext(String prompt, bool isTamil) async {
    try {
      final lowerPrompt = prompt.toLowerCase();

      // Determine search type based on prompt
      if (lowerPrompt.contains('food') ||
          lowerPrompt.contains('nutrition') ||
          lowerPrompt.contains('calorie') ||
          lowerPrompt.contains('உணவு') ||
          lowerPrompt.contains('கலாரி') ||
          lowerPrompt.contains('நீர்ப்பு')) {
        // Extract food name
        final foodName = _extractEntity(prompt,
            ['food', 'nutrition', 'calorie', 'ingredients', 'உணவு', 'கலாரி']);
        if (foodName != null) {
          return await _browsing.searchFoodInfo(foodName);
        }
      }

      if (lowerPrompt.contains('document') ||
          lowerPrompt.contains('template') ||
          lowerPrompt.contains('format') ||
          lowerPrompt.contains('ஆவண') ||
          lowerPrompt.contains('வடிவமைப்பு')) {
        final docType = _extractEntity(
            prompt, ['document', 'template', 'format', 'ஆவண', 'வடிவமைப்பு']);
        if (docType != null) {
          return await _browsing.searchDocumentInfo(docType);
        }
      }

      if (lowerPrompt.contains('near me') ||
          lowerPrompt.contains('nearby') ||
          lowerPrompt.contains('hours') ||
          lowerPrompt.contains('அருகே') ||
          lowerPrompt.contains('நேரம்')) {
        // Use GPS location if available
        return await _browsing.searchLocalInfo('current location', prompt);
      }

      if (lowerPrompt.contains('news') ||
          lowerPrompt.contains('latest') ||
          lowerPrompt.contains('update') ||
          lowerPrompt.contains('செய்தி') ||
          lowerPrompt.contains('புதுப்பித்தல்')) {
        return await _browsing.searchCurrentEvents(prompt);
      }

      // General search
      return await _browsing.searchAndSummarize(
          query: prompt, maxResults: 3, maxPagesToFetch: 2);
    } catch (e) {
      return null;
    }
  }

  String? _extractEntity(String prompt, List<String> keywords) {
    // Simple extraction - in production, use NER
    final words = prompt.split(' ');
    for (int i = 0; i < words.length; i++) {
      if (keywords.any((k) => words[i].toLowerCase().contains(k))) {
        // Return surrounding words as entity
        final start = (i - 2).clamp(0, words.length - 1);
        final end = (i + 3).clamp(0, words.length);
        return words.sublist(start, end).join(' ');
      }
    }
    return null;
  }

  String _injectBrowsingContext(
      String originalPrompt, String browsingContext, bool isTamil) {
    final contextLabel = isTamil
        ? 'வலை தேடல் சூழல் (Real-time info):'
        : 'Web Search Context (Real-time info):';

    return '''
$originalPrompt

$contextLabel
$browsingContext

Instructions: Use the above real-time information to provide an accurate, up-to-date answer. Cite sources when possible.
''';
  }

  String _formatResponse(String response, String? browsingContext) {
    // The app speaks this and shows it as one block — strip any Markdown the
    // model added (## headings, **bold**, - bullets, `code`).
    final clean = toPlainSpeech(response);

    if (browsingContext == null || browsingContext.isEmpty) {
      return clean;
    }

    // Add source attribution
    final sourceNote = _localization.isTamil
        ? '\n\n📱 தகவல் மூலம்: வலை தேடல் (Real-time web search)'
        : '\n\n📱 Source: Web search (Real-time)';

    return clean + sourceNote;
  }

  void setUseOnDevice(bool use) {
    _useOnDevice = use && _onDevice.isReady;
  }

  void dispose() {
    _onDevice.dispose();
    _cloud.dispose();
    _browsing.dispose();
  }
}
