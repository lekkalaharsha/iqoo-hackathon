enum VoiceChatControl { stop, repeat, none }

class VoiceChatUtterance {
  final bool isComplete;
  final String text;

  const VoiceChatUtterance({required this.isComplete, required this.text});
}

VoiceChatUtterance parseVoiceChatUtterance(String words) {
  final match = RegExp(r'\bclear\s+over\b[\s.!?]*$', caseSensitive: false)
      .firstMatch(words.trim());
  if (match == null) {
    return VoiceChatUtterance(isComplete: false, text: words.trim());
  }
  return VoiceChatUtterance(
    isComplete: true,
    text: words.substring(0, match.start).trim(),
  );
}

VoiceChatControl parseVoiceChatControl(String words) {
  final normalized = words
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (<String>{
    'stop',
    'stop listening',
    'stop voice chat',
    'exit voice chat',
    'cancel voice chat',
  }.contains(normalized)) {
    return VoiceChatControl.stop;
  }
  if (<String>{'repeat', 'repeat that', 'say that again', 'say again'}
      .contains(normalized)) {
    return VoiceChatControl.repeat;
  }
  return VoiceChatControl.none;
}
