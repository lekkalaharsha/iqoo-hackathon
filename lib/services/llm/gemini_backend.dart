import 'package:flutter/foundation.dart';

import '../gemini_api_client.dart';
import 'llm_backend.dart';

/// Cloud backend: Google Gemini over the bounded REST client in
/// [GeminiApiClient]. Owns the model-fallback list — a model-specific quota or
/// outage must not stop the remaining choices from being tried.
class GeminiBackend implements LlmBackend {
  GeminiBackend({required String apiKey, GeminiApiClient? client})
      : _apiKey = apiKey,
        _client = client ?? GeminiApiClient(apiKey: apiKey);

  /// Prefer the stable alias; the pinned versions are fallbacks for when the
  /// alias itself is briefly unavailable.
  static const models = <String>[
    'models/gemini-flash-latest',
    'models/gemini-3.7-flash',
    'models/gemini-3.6-flash',
  ];

  final String _apiKey;
  final GeminiApiClient _client;

  @override
  String get id => 'cloud-gemini';

  @override
  bool get isReady =>
      _apiKey.trim().isNotEmpty && !_apiKey.startsWith('YOUR_');

  @override
  Future<void> initialize() async {}

  @override
  Future<LlmResult> generate({
    required String prompt,
    List<Uint8List>? images,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!isReady) return const LlmResult.failed(LlmFailure.notReady);

    LlmFailure lastFailure = LlmFailure.unavailable;
    for (final model in models) {
      try {
        final text = await _client.generateContent(
          model: model,
          prompt: prompt,
          images: images,
          timeout: timeout,
        );
        if (text.trim().isNotEmpty) return LlmResult.text(text);
        lastFailure = LlmFailure.emptyResponse;
      } on GeminiApiException catch (error) {
        lastFailure = _map(error.reason);
        debugPrint('GeminiBackend $model failed: ${error.reason}');
        // Retry the next model only when the fault is model-specific.
        if (lastFailure == LlmFailure.quota ||
            lastFailure == LlmFailure.unavailable ||
            lastFailure == LlmFailure.emptyResponse) {
          continue;
        }
        break;
      } catch (_) {
        // Never leak an unexpected exception type to the caller.
        lastFailure = LlmFailure.network;
        debugPrint('GeminiBackend $model failed without response data');
        break;
      }
    }
    return LlmResult.failed(lastFailure);
  }

  @override
  void dispose() => _client.close();

  LlmFailure _map(GeminiFailureReason reason) => switch (reason) {
        GeminiFailureReason.unauthorized => LlmFailure.unauthorized,
        GeminiFailureReason.quota => LlmFailure.quota,
        GeminiFailureReason.invalidRequest => LlmFailure.invalidRequest,
        GeminiFailureReason.unavailable => LlmFailure.unavailable,
        GeminiFailureReason.timeout => LlmFailure.timeout,
        GeminiFailureReason.network => LlmFailure.network,
        GeminiFailureReason.emptyResponse => LlmFailure.emptyResponse,
      };
}
