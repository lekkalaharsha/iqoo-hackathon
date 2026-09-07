import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logic_legends/services/gemini_api_client.dart';
import 'package:logic_legends/services/llm/gemini_backend.dart';
import 'package:logic_legends/services/llm/gemma_backend.dart';
import 'package:logic_legends/services/llm/llm_backend.dart';

http.Response _okText(String text) => http.Response(
      jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': text},
              ],
            },
          },
        ],
      }),
      200,
    );

void main() {
  group('GemmaBackend (on-device seam, not wired yet)', () {
    test('is not ready and reports unsupported instead of throwing', () async {
      final backend = GemmaBackend();
      await backend.initialize();
      expect(backend.isReady, isFalse);

      final result = await backend.generate(prompt: 'anything');
      expect(result.hasText, isFalse);
      expect(result.failure, LlmFailure.unsupported);
    });
  });

  group('GeminiBackend', () {
    test('placeholder key is not ready and never calls the network', () async {
      var calls = 0;
      final backend = GeminiBackend(
        apiKey: 'YOUR_GEMINI_API_KEY',
        client: GeminiApiClient(
          apiKey: 'YOUR_GEMINI_API_KEY',
          httpClient: MockClient((_) async {
            calls++;
            return _okText('should not happen');
          }),
        ),
      );

      expect(backend.isReady, isFalse);
      final result = await backend.generate(prompt: 'hello');
      expect(result.failure, LlmFailure.notReady);
      expect(calls, 0);
    });

    test('returns text from the first healthy model', () async {
      var calls = 0;
      final backend = GeminiBackend(
        apiKey: 'real-key',
        client: GeminiApiClient(
          apiKey: 'real-key',
          httpClient: MockClient((_) async {
            calls++;
            return _okText('A bottle on a table.');
          }),
        ),
      );

      final result = await backend.generate(prompt: 'describe');
      expect(result.value, 'A bottle on a table.');
      expect(calls, 1); // no fallback needed
    });

    test('a model-specific quota error falls through every model', () async {
      var calls = 0;
      final backend = GeminiBackend(
        apiKey: 'real-key',
        client: GeminiApiClient(
          apiKey: 'real-key',
          httpClient: MockClient((_) async {
            calls++;
            return http.Response('quota exceeded', 429);
          }),
        ),
      );

      final result = await backend.generate(prompt: 'describe');
      expect(result.failure, LlmFailure.quota);
      expect(calls, GeminiBackend.models.length);
    });

    test('an auth error stops immediately without trying more models', () async {
      var calls = 0;
      final backend = GeminiBackend(
        apiKey: 'real-key',
        client: GeminiApiClient(
          apiKey: 'real-key',
          httpClient: MockClient((_) async {
            calls++;
            return http.Response('forbidden', 403);
          }),
        ),
      );

      final result = await backend.generate(prompt: 'describe');
      expect(result.failure, LlmFailure.unauthorized);
      expect(calls, 1);
    });
  });
}
