import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

enum GeminiFailureReason {
  unauthorized,
  quota,
  invalidRequest,
  unavailable,
  timeout,
  network,
  emptyResponse,
}

class GeminiApiException implements Exception {
  const GeminiApiException(this.reason, {this.statusCode});

  final GeminiFailureReason reason;
  final int? statusCode;

  @override
  String toString() => 'GeminiApiException($reason, status: $statusCode)';
}

/// Small Gemini REST boundary. It never logs the key, prompt, image, or response.
class GeminiApiClient {
  GeminiApiClient({required this.apiKey, http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  static const int maxPromptCharacters = 16000;
  static const int maxImageBytes = 10 * 1024 * 1024;

  final String apiKey;
  final http.Client _httpClient;

  Future<String> generateContent({
    required String model,
    required String prompt,
    List<Uint8List>? images,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) {
      throw const GeminiApiException(GeminiFailureReason.invalidRequest);
    }
    if (cleanPrompt.length > maxPromptCharacters ||
        (images?.length ?? 0) > 1 ||
        (images?.any((image) => image.length > maxImageBytes) ?? false)) {
      throw const GeminiApiException(GeminiFailureReason.invalidRequest);
    }

    final modelId = model.startsWith('models/') ? model.substring(7) : model;
    final uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$modelId:generateContent',
    );
    final parts = <Map<String, Object>>[
      {'text': cleanPrompt},
      for (final image in images ?? const <Uint8List>[])
        {
          'inline_data': {
            'mime_type': _imageMimeType(image),
            'data': base64Encode(image),
          },
        },
    ];

    http.Response response;
    try {
      response = await _httpClient
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
            body: jsonEncode({
              'contents': [
                {'parts': parts},
              ],
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const GeminiApiException(GeminiFailureReason.timeout);
    } on Exception {
      throw const GeminiApiException(GeminiFailureReason.network);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GeminiApiException(
        _reasonForStatus(response.statusCode),
        statusCode: response.statusCode,
      );
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = json['candidates'] as List<dynamic>?;
      final content = candidates?.firstOrNull as Map<String, dynamic>?;
      final parts = (content?['content'] as Map<String, dynamic>?)?['parts']
          as List<dynamic>?;
      final text = parts
              ?.whereType<Map<String, dynamic>>()
              .map((part) => part['text'])
              .whereType<String>()
              .join()
              .trim() ??
          '';
      if (text.isEmpty) {
        throw const GeminiApiException(GeminiFailureReason.emptyResponse);
      }
      return text;
    } on GeminiApiException {
      rethrow;
    } on Exception {
      throw const GeminiApiException(GeminiFailureReason.emptyResponse);
    }
  }

  void close() => _httpClient.close();

  GeminiFailureReason _reasonForStatus(int status) => switch (status) {
        400 || 413 => GeminiFailureReason.invalidRequest,
        401 || 403 => GeminiFailureReason.unauthorized,
        429 => GeminiFailureReason.quota,
        >= 500 => GeminiFailureReason.unavailable,
        _ => GeminiFailureReason.invalidRequest,
      };

  String _imageMimeType(Uint8List bytes) {
    final isPng = bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47;
    return isPng ? 'image/png' : 'image/jpeg';
  }
}
