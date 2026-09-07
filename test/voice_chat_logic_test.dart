import 'package:flutter_test/flutter_test.dart';
import 'package:logic_legends/services/voice_chat_logic.dart';

void main() {
  test('recognizes explicit voice-chat stop phrases', () {
    expect(parseVoiceChatControl('Stop voice chat!'), VoiceChatControl.stop);
    expect(parseVoiceChatControl('cancel voice chat'), VoiceChatControl.stop);
    expect(parseVoiceChatControl('stop sign ahead'), VoiceChatControl.none);
  });

  test('recognizes repeat phrases without swallowing ordinary questions', () {
    expect(parseVoiceChatControl('Say that again'), VoiceChatControl.repeat);
    expect(parseVoiceChatControl('repeat'), VoiceChatControl.repeat);
    expect(parseVoiceChatControl('repeat the recipe slowly'),
        VoiceChatControl.none);
  });

  test('clear over completes and is removed from the question', () {
    final complete =
        parseVoiceChatUtterance('What color is this object, clear over.');
    expect(complete.isComplete, isTrue);
    expect(complete.text, 'What color is this object,');

    final incomplete = parseVoiceChatUtterance('What color is this object');
    expect(incomplete.isComplete, isFalse);
  });

  test('clear over only ends speech when it is the final phrase', () {
    final result = parseVoiceChatUtterance(
        'Explain what clear over means in radio communication');
    expect(result.isComplete, isFalse);
  });
}
