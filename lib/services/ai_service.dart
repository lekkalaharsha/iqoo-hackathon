import '../screens/constapi.dart';
import 'package:flutter/foundation.dart';
import '../services/on_device_llm_service.dart';
import '../services/browsing_service.dart';
import '../services/config_service.dart';
import '../services/localization_service.dart';
import '../services/gemini_api_client.dart';

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  final OnDeviceLLMService _onDeviceLLM = OnDeviceLLMService();
  final BrowsingService _browsing = BrowsingService();
  final ConfigService _configService = ConfigService();
  final LocalizationService _localization = LocalizationService();

  late final GeminiApiClient _gemini = GeminiApiClient(apiKey: GEMINI_API_KEY);
  bool get cloudConfigured =>
      GEMINI_API_KEY.trim().isNotEmpty && !GEMINI_API_KEY.startsWith('YOUR_');
  String? lastFailureMessage;
  bool _useOnDevice = false;
  bool _initialized = false;

  /// Prefer the stable alias. Quota and availability can differ by model, so a
  /// model-specific failure must not prevent trying the remaining choices.
  static const _models = <String>[
    'models/gemini-flash-latest',
    'models/gemini-3.7-flash',
    'models/gemini-3.6-flash',
  ];

  bool get useOnDevice => _useOnDevice;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;

    await _configService.initialize();
    await _localization.initialize();

    if (_configService.appConfig.features.onDeviceLLM) {
      _useOnDevice = await _onDeviceLLM.initialize();
    }

    // Cloud Gemini is initialised once in main.dart with GEMINI_API_KEY.
    // No re-init here — a second Gemini.init() with a bad key breaks every call.

    _initialized = true;
  }

  Future<String?> generateResponse({
    required String prompt,
    List<Uint8List>? images,
    required bool isTamil,
    bool enableBrowsing = true,
  }) async {
    lastFailureMessage = null;
    if (!cloudConfigured && !_useOnDevice) {
      lastFailureMessage = 'Scene descriptions are not set up yet. '
          'You can still use Read and Explain to read printed text.';
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

    // Try on-device first
    if (_useOnDevice && _onDeviceLLM.initialized) {
      final response =
          await _onDeviceLLM.generateResponse(finalPrompt, images: images);
      if (response != null) return _formatResponse(response, browsingContext);
      // Fall through to cloud if on-device fails
    }

    // Cloud fallback — try each model, move on when one 503s / times out.
    for (final model in _models) {
      try {
        final text = await _gemini.generateContent(
          model: model,
          prompt: finalPrompt,
          images: images,
        );

        if (text.trim().isNotEmpty) {
          return _formatResponse(text, browsingContext);
        }
      } on GeminiApiException catch (error) {
        lastFailureMessage = _messageForFailure(error.reason);
        debugPrint('AIService.generateResponse $model failed: '
            '${error.reason}, status ${error.statusCode}');
        if (error.reason == GeminiFailureReason.quota ||
            error.reason == GeminiFailureReason.unavailable ||
            error.reason == GeminiFailureReason.emptyResponse) {
          continue;
        }
        break;
      } catch (e) {
        lastFailureMessage = _messageForFailure(GeminiFailureReason.network);
        debugPrint('AIService.generateResponse failed without response data');
        break;
      }
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
    Duration timeout = const Duration(seconds: 6),
  }) async {
    // ponytail: on-device path lands here once flutter_gemma is wired; for now
    // it is the same cloud call, just text-only and sentence-streamed.
    if (!cloudConfigured) return null;
    for (final model in _models) {
      try {
        final full = await _gemini.generateContent(
          model: model,
          prompt: promptText,
          timeout: timeout,
        );
        for (final sentence in _spokenSentences(full)) {
          onSentence?.call(sentence);
        }
        return full;
      } on GeminiApiException catch (error) {
        debugPrint('AIService.explain $model failed: '
            '${error.reason}, status ${error.statusCode}');
        if (error.reason == GeminiFailureReason.quota ||
            error.reason == GeminiFailureReason.unavailable ||
            error.reason == GeminiFailureReason.emptyResponse) {
          continue;
        }
        break;
      }
    }
    return null;
  }

  Iterable<String> _spokenSentences(String text) sync* {
    final matches = RegExp(r'[^.!?]+[.!?]?(?:\s+|$)').allMatches(text);
    for (final match in matches) {
      final sentence = match.group(0)?.trim() ?? '';
      if (sentence.isNotEmpty) yield sentence;
    }
  }

  String _messageForFailure(GeminiFailureReason reason) => switch (reason) {
        GeminiFailureReason.unauthorized =>
          'The assistant setup was rejected. Check the Gemini key.',
        GeminiFailureReason.quota =>
          'The assistant usage limit was reached. Try again shortly.',
        GeminiFailureReason.invalidRequest =>
          'The assistant could not process this photo. Try another photo.',
        GeminiFailureReason.unavailable ||
        GeminiFailureReason.emptyResponse =>
          'The assistant is temporarily unavailable. Try again shortly.',
        GeminiFailureReason.timeout ||
        GeminiFailureReason.network =>
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
    if (browsingContext == null || browsingContext.isEmpty) {
      return response;
    }

    // Add source attribution
    final sourceNote = _localization.isTamil
        ? '\n\n📱 தகவல் மூலம்: வலை தேடல் (Real-time web search)'
        : '\n\n📱 Source: Web search (Real-time)';

    return response + sourceNote;
  }

  void setUseOnDevice(bool use) {
    _useOnDevice = use && _onDeviceLLM.initialized;
  }

  void dispose() {
    _onDeviceLLM.dispose();
    _browsing.dispose();
    _gemini.close();
  }
}
