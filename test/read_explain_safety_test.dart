import 'package:flutter_test/flutter_test.dart';
import 'package:logic_legends/services/read_explain_logic.dart';

void main() {
  test('medicine prompt forbids unsupported high-stakes facts', () {
    final prompt = explainPrompt(DocType.medicine, 'CROCIN 650');

    expect(prompt, contains('Use only facts stated in the captured text'));
    expect(prompt, contains('Never infer a medicine purpose, safe dose'));
    expect(prompt, contains('only when each is explicitly present and clear'));
  });

  test('empty OCR fallback gives an actionable retry', () {
    final fallback = fallbackSentence(DocType.generic, '');

    expect(fallback, contains('No readable text found'));
    expect(fallback, contains('moving closer'));
  });

  test('ordinary text is not misclassified by medicine substrings', () {
    expect(
      classifyDocument('Management report for image processing project'),
      DocType.generic,
    );
    expect(
      classifyDocument('The membership agreement expires next year'),
      DocType.generic,
    );
    expect(classifyDocument('Trip plan and office timings'), DocType.generic);
  });

  test('document types require meaningful evidence', () {
    expect(
      classifyDocument('Paracetamol tablets 650 mg batch no X7'),
      DocType.medicine,
    );
    expect(
      classifyDocument('Electricity bill amount due Rs. 840'),
      DocType.bill,
    );
    expect(
      classifyDocument('Government notice: applications submit at office'),
      DocType.notice,
    );
  });
}
