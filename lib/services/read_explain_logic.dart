// Pure Dart — no Flutter imports, so `dart run` can execute the self-check.
// Everything here is the fallback path: what the app says when the language
// model is slow, absent, or offline. It must never produce nothing.

enum DocType { medicine, notice, bill, generic }

/// Conservative classification of OCR output. False high-stakes labels are
/// worse than a generic result, so medicine requires several independent clues.
DocType classifyDocument(String ocrText) {
  final text = collapseWhitespace(ocrText.toLowerCase());

  bool hasTerm(String term) => RegExp(
        '(^|[^a-z0-9])${RegExp.escape(term)}([^a-z0-9]|\$)',
      ).hasMatch(text);
  int termScore(List<String> terms) => terms.where(hasTerm).length;

  const medicineIdentity = [
    'paracetamol',
    'ibuprofen',
    'amoxicillin',
    'antibiotic',
  ];
  const medicineForm = [
    'tablet',
    'tablets',
    'capsule',
    'capsules',
    'syrup',
    'dosage',
    'dose',
  ];
  const medicinePack = ['batch no', 'mfd', 'manufactured by', 'rx'];
  final hasDosageUnit = RegExp(
    r'\b\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml)\b',
    caseSensitive: false,
  ).hasMatch(text);
  final medicineScore =
      termScore(medicineIdentity) * 3 +
      termScore(medicineForm) * 2 +
      termScore(medicinePack) +
      (hasDosageUnit ? 2 : 0);

  const billTerms = [
    'amount due', 'total due', 'bill', 'invoice', 'receipt', 'due date',
    'meter', 'consumer no', 'account no', 'payable',
  ];
  const noticeContext = [
    'applications', 'office', 'government', 'scheme', 'eligible',
    'documents required', 'last date', 'submit', 'aadhaar',
  ];
  final billScore = termScore(billTerms) * 2 +
      (RegExp(r'(?:₹|\brs\.?|\binr\b)\s*\d', caseSensitive: false)
              .hasMatch(text)
          ? 1
          : 0);
  final noticeScore = (hasTerm('notice') ? 3 : 0) + termScore(noticeContext);

  if (medicineScore >= 3 &&
      medicineScore > billScore &&
      medicineScore > noticeScore) {
    return DocType.medicine;
  }
  if (billScore >= 2 && billScore >= noticeScore) return DocType.bill;
  if (noticeScore >= 3) return DocType.notice;
  return DocType.generic;
}

/// The fact the user is usually hunting for on a strip / bill / notice — an
/// expiry-or-due date, or a bill amount — so the spoken fallback can lead with
/// it instead of raw branding text. Null when nothing obvious is present.
String? keyFact(DocType type, String ocrText) {
  final date = RegExp(
    r'\b(\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{1,2}[/-]\d{4}|'
    r'(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s*\d{4})\b',
    caseSensitive: false,
  ).firstMatch(ocrText)?.group(0);
  final amount = RegExp(
    r'(?:₹|rs\.?|inr)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  ).firstMatch(ocrText)?.group(1);

  switch (type) {
    case DocType.medicine:
      return date == null ? null : 'Date on the pack: $date.';
    case DocType.bill:
      final parts = [
        if (amount != null) 'Amount: $amount rupees',
        if (date != null) 'date: $date',
      ];
      return parts.isEmpty ? null : '${parts.join(', ')}.';
    case DocType.notice:
      return date == null ? null : 'Date mentioned: $date.';
    case DocType.generic:
      return null;
  }
}

/// Spoken fallback when no explanation arrives. Names the document type, leads
/// with the key fact if one was found, then reads what was seen — so the user
/// always learns something.
String fallbackSentence(DocType type, String ocrText) {
  final trimmed = collapseWhitespace(ocrText);
  final snippet =
      trimmed.length > 200 ? '${trimmed.substring(0, 200)}…' : trimmed;
  final fact = keyFact(type, ocrText);
  final f = fact == null ? '' : '$fact ';
  switch (type) {
    case DocType.medicine:
      return 'This looks like medicine packaging. ${f}It reads: $snippet';
    case DocType.bill:
      return 'This looks like a bill. ${f}It reads: $snippet';
    case DocType.notice:
      return 'This looks like an official notice. ${f}It reads: $snippet';
    case DocType.generic:
      return trimmed.isEmpty
          ? 'No readable text found. Try moving closer, or hold the phone steadier.'
          : 'It reads: $snippet';
  }
}

/// The instruction sent to the language model. Deliberately asks for actions,
/// not a summary — explaining what to do is the whole product.
///
/// [brief] (Settings > Brief answers) asks for a single sentence.
String explainPrompt(DocType type, String ocrText,
    {String? userQuestion, bool brief = false}) {
  final length = brief
      ? 'Answer in one short sentence'
      : 'Answer in at most three short sentences';
  final base =
      'You are helping a blind person who cannot see this document. '
      '$length, plain spoken English, no '
      'formatting or bullet points. Do not repeat the raw text back. Use only '
      'facts stated in the captured text. Never infer a medicine purpose, safe '
      'dose, expiry, bill amount, due date, legal requirement, or identity. '
      'If a requested fact is missing or unclear, say that it could not be '
      'confirmed and suggest checking the original with a trusted person.';
  final q = userQuestion?.trim();
  final ask = (q != null && q.isNotEmpty)
      ? 'The person asks: "$q". Answer that using the document; '
          'if the document does not say, tell them so.'
      : switch (type) {
          DocType.medicine =>
            'State the medicine name, purpose, dose instructions, and expiry '
              'only when each is explicitly present and clear.',
          DocType.bill =>
            'Say who the bill is from, how much is owed, and the due date.',
          DocType.notice =>
            'Say what this notice is about, what the person must do, and by when.',
          DocType.generic => 'Say what this document is and what it means.',
        };
  return '$base $ask\n\nText from the document:\n$ocrText';
}

/// If this looks like a bill that prints a UPI payee, build a `upi://pay`
/// deep link. The user's own UPI app then shows payee + amount and demands the
/// UPI PIN — we never see or move the money. Returns null when there is no
/// payee to pay, so the caller only offers "pay" when it can actually work.
///
/// ponytail: reads a VPA printed as plain text. Bills that carry only a UPI
/// *QR* need ML Kit barcode scanning — add that if the Sept spike shows plain
/// VPAs are rare on real bills.
String? buildUpiUri(String ocrText) {
  // UPI handle: name@bank. The bank suffix is letters only; reject a following
  // ".letter" (an e-mail domain like `billing@company.com`) but allow a plain
  // sentence period right after the id (`...pay to x@ybl.`).
  final vpa = RegExp(
    r'(?<![\w.@])[A-Za-z0-9.\-_]{2,}@[A-Za-z]{2,}(?![A-Za-z])(?!\.[A-Za-z])',
  ).firstMatch(ocrText);
  if (vpa == null) return null;

  final params = <String, String>{
    'pa': vpa.group(0)!,
    'pn': 'Biller',
    'cu': 'INR',
  };

  final amt = RegExp(
    r'(?:₹|rs\.?|inr)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  ).firstMatch(ocrText);
  final n = amt == null ? null : double.tryParse(amt.group(1)!.replaceAll(',', ''));
  if (n != null && n > 0) params['am'] = n.toStringAsFixed(2);

  final q = params.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');
  return 'upi://pay?$q';
}

/// First complete sentence, so speech can start before generation finishes.
/// Returns null until at least one sentence terminator has arrived.
String? firstSentence(String partial) {
  final match = RegExp(r'^.*?[.!?](\s|$)').firstMatch(partial);
  final s = match?.group(0)?.trim();
  return (s == null || s.isEmpty) ? null : s;
}

String collapseWhitespace(String s) =>
    s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Run: `dart run --enable-asserts lib/services/read_explain_logic.dart`
/// (plain `dart run` does NOT execute `assert`s — the checks would be no-ops).
void main() {
  assert(classifyDocument('PARACETAMOL IP 650mg Tablets Exp. 01/2026') ==
      DocType.medicine);
  assert(classifyDocument('Electricity bill. Amount due Rs. 840. Due date 12/09') ==
      DocType.bill);
  assert(classifyDocument(
          'NOTICE: Ration card applications open. Submit Aadhaar at the office.') ==
      DocType.notice);
  assert(classifyDocument('hello world') == DocType.generic);

  // Empty OCR must still say something useful, never an empty utterance.
  assert(fallbackSentence(DocType.generic, '   ').contains('No readable text'));
  assert(fallbackSentence(DocType.medicine, 'Crocin 650').contains('medicine'));

  // keyFact: lead with the date / amount the user is hunting for.
  assert(fallbackSentence(DocType.medicine, 'CROCIN 650 Exp. 01/2026 Batch X7')
      .contains('01/2026'));
  assert(fallbackSentence(
          DocType.bill, 'Electricity bill amount due Rs. 840 due date 12/09/2026')
      .contains('840 rupees'));
  assert(keyFact(DocType.notice, 'Apply before 20/09/2026 at the office')
          ?.contains('20/09/2026') ??
      false);
  assert(keyFact(DocType.medicine, 'no dates on this pack') == null);
  assert(keyFact(DocType.generic, 'ignore 01/2026 here') == null);

  // Streaming: nothing to speak until a terminator arrives.
  assert(firstSentence('This is parac') == null);
  assert(firstSentence('This is paracetamol. It treats') ==
      'This is paracetamol.');

  assert(explainPrompt(DocType.medicine, 'x')
      .contains('only when each is explicitly present and clear'));
  assert(explainPrompt(DocType.bill, 'x').contains('at most three short'));
  assert(explainPrompt(DocType.bill, 'x', brief: true)
      .contains('one short sentence'));
  assert(collapseWhitespace(' a \n\n b  ') == 'a b');

  // UPI deep link: only when a real VPA is present; amount is optional.
  assert(buildUpiUri('EB bill. Pay to tneb@okhdfcbank. Amount due Rs. 1,240.50') ==
      'upi://pay?pa=tneb%40okhdfcbank&pn=Biller&cu=INR&am=1240.50');
  assert(buildUpiUri('UPI ID 9876543210@ybl total ₹840') ==
      'upi://pay?pa=9876543210%40ybl&pn=Biller&cu=INR&am=840.00');
  assert(buildUpiUri('Pay at counter to water.board@sbi') ==
      'upi://pay?pa=water.board%40sbi&pn=Biller&cu=INR');
  assert(buildUpiUri('Queries: billing@company.com, amount due Rs. 500') == null);
  assert(buildUpiUri('Electricity bill, amount due Rs. 840, no online payment') ==
      null);

  print('read_explain_logic: all checks passed');
}
