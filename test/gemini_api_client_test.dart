import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logic_legends/services/gemini_api_client.dart';

void main() {
  test('sends authenticated image request and extracts response text',
      () async {
    late http.Request captured;
    final client = GeminiApiClient(
      apiKey: 'test-secret',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'A blue bottle is on a table.'},
                  ],
                },
              },
            ],
          }),
          200,
        );
      }),
    );

    final result = await client.generateContent(
      model: 'models/gemini-3.6-flash',
      prompt: 'Describe this scene.',
      images: [
        Uint8List.fromList([0xff, 0xd8, 0xff])
      ],
    );

    expect(result, 'A blue bottle is on a table.');
    expect(
        captured.url.path, '/v1beta/models/gemini-3.6-flash:generateContent');
    expect(captured.headers['x-goog-api-key'], 'test-secret');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    final parts = ((body['contents'] as List).first['parts'] as List);
    expect(parts.last['inline_data']['mime_type'], 'image/jpeg');
  });

  test('maps quota errors without retaining response content', () async {
    final client = GeminiApiClient(
      apiKey: 'test-secret',
      httpClient: MockClient(
        (_) async => http.Response('sensitive server details', 429),
      ),
    );

    await expectLater(
      client.generateContent(model: 'gemini-3.6-flash', prompt: 'hello'),
      throwsA(
        isA<GeminiApiException>()
            .having(
                (error) => error.reason, 'reason', GeminiFailureReason.quota)
            .having(
              (error) => error.toString(),
              'sanitized error',
              isNot(contains('sensitive')),
            ),
      ),
    );
  });

  test('rejects oversized images before a network request', () async {
    var called = false;
    final client = GeminiApiClient(
      apiKey: 'test-secret',
      httpClient: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      client.generateContent(
        model: 'gemini-3.6-flash',
        prompt: 'describe',
        images: [Uint8List(GeminiApiClient.maxImageBytes + 1)],
      ),
      throwsA(
        isA<GeminiApiException>().having(
          (error) => error.reason,
          'reason',
          GeminiFailureReason.invalidRequest,
        ),
      ),
    );
    expect(called, isFalse);
  });
}
