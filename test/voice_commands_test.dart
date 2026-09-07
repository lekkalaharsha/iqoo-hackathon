import 'package:flutter_test/flutter_test.dart';
import 'package:logic_legends/services/voice_assistant_service.dart';
import 'package:logic_legends/services/ai_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late VoiceAssistantService voice;
  setUp(() { voice = VoiceAssistantService(); });
  test('Text and document commands select the available reading mode', () {
    for (final command in ['Switch to text mode', 'Switch to document mode',
      'Switch to read and explain']) {
      final result = voice.parseCommand(command);
      expect(result.type, VoiceCommandType.switchMode);
      expect(result.parameters['mode'], 1);
    }
    expect(voice.parseCommand('Switch to explore').parameters['mode'], 0);
  });
  test('Short repeat commands work without falling through to AI', () {
    for (final command in ['Repeat', 'Again', 'Say again', 'Repeat last answer']) {
      expect(voice.parseCommand(command).type, VoiceCommandType.repeatLastResponse);
    }
  });
  test('Core commands and reserved commands retain their meaning', () {
    expect(voice.parseCommand('Take photo').type, VoiceCommandType.captureImage);
    expect(voice.parseCommand('Read text').type, VoiceCommandType.readText);
    expect(voice.parseCommand('Open settings').type, VoiceCommandType.openSettings);
    expect(voice.parseCommand('Open camera').type, VoiceCommandType.openApp);
    expect(voice.parseCommand('Help me').type, VoiceCommandType.help);
  });
  test('Missing cloud key does not crash the local reading fallback', () async {
    final ai = AIService();
    if (ai.cloudConfigured) return;
    expect(await ai.explain('Read this notice'), isNull);
    expect(await ai.generateResponse(prompt: 'Describe scene', isTamil: false), isNull);
  });
}

