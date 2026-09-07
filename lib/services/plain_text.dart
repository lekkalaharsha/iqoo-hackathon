// Pure Dart — no Flutter imports, so `dart run` can execute the self-check.
//
// The app speaks model output aloud and shows it as one plain block. Language
// models answer in Markdown anyway (## headings, **bold**, `- bullets`,
// `code`), and a screen reader / TTS engine reads "hash hash", "star star",
// "backtick" literally. Strip the markup, keep the words.

/// Turn Markdown-ish model output into plain spoken text.
String toPlainSpeech(String input) {
  if (input.trim().isEmpty) return '';

  var s = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  // Fenced code blocks: keep the contents, drop the ``` fences.
  s = s.replaceAll(RegExp(r'^ {0,3}```[^\n]*$', multiLine: true), '');

  // Line-level markers.
  final out = <String>[];
  for (final raw in s.split('\n')) {
    // A horizontal rule / decorative "***" or "---" line — drop it entirely.
    if (RegExp(r'^\s*([-*_=])\1{2,}\s*$').hasMatch(raw)) continue;

    var line = raw
        .replaceFirst(RegExp(r'^\s{0,3}#{1,6}\s+'), '') // # heading
        .replaceFirst(RegExp(r'^\s{0,3}>\s?'), '') // > quote
        .replaceFirst(RegExp(r'^\s*[-*+]\s+'), '') // - bullet
        .replaceFirst(RegExp(r'^\s*\d+[.)]\s+'), '') // 1. numbered
        .replaceAll(RegExp(r'^\s*\|'), '') // leading table pipe
        .replaceAll(' | ', ', '); // table cell separators
    out.add(line);
  }
  s = out.join('\n');

  // Inline markup.
  s = s
      .replaceAllMapped(
          RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1] ?? '') // [text](url)
      .replaceAll(RegExp(r'\*\*\*|___'), '') // ***bolditalic***
      .replaceAll(RegExp(r'\*\*|__'), '') // **bold**
      .replaceAllMapped(
          RegExp(r'(?<![\w*])\*(?!\s)([^*\n]+?)(?<!\s)\*(?![\w*])'),
          (m) => m[1] ?? '') // *italic*
      .replaceAllMapped(RegExp(r'~~([^~\n]+?)~~'), (m) => m[1] ?? '') // ~~del~~
      .replaceAll('`', ''); // `code`

  // Whitespace: single spaces, no blank-line stacks, trimmed.
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
  s = s
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .join('\n');
  return s.trim();
}

/// Run: `dart run --enable-asserts lib/services/plain_text.dart`
void main() {
  assert(toPlainSpeech('## Heading\ntext') == 'Heading\ntext');
  assert(toPlainSpeech('This is **bold** and *italic*.') ==
      'This is bold and italic.');
  assert(toPlainSpeech('- one\n- two\n- three') == 'one\ntwo\nthree');
  assert(toPlainSpeech('1. first\n2. second') == 'first\nsecond');
  assert(toPlainSpeech('Use `flutter run` now.') == 'Use flutter run now.');
  assert(toPlainSpeech('***\ntext\n---') == 'text');
  assert(toPlainSpeech('See [the docs](https://x.com) here.') ==
      'See the docs here.');
  assert(toPlainSpeech('> a quoted line') == 'a quoted line');
  assert(toPlainSpeech('~~old~~ new') == 'old new');
  // Don't touch underscores in words or a lone arithmetic asterisk.
  assert(toPlainSpeech('file_name and 2 * 3 = 6') == 'file_name and 2 * 3 = 6');
  assert(toPlainSpeech('') == '');
  assert(toPlainSpeech('para one\n\n\npara two') == 'para one\npara two');
  print('plain_text: all checks passed');
}
