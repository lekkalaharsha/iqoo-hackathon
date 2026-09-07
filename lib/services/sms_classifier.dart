// Pure Dart — no Flutter imports, so `dart run` can execute the self-check.

enum SmsType { otp, spam, transaction, normal }

/// How dangerous the message looks. Rules are keyword/regex only, so they run
/// offline and instantly — and they catch the common scams aimed at blind and
/// elderly users, not every clever one. Warnings are a *caution to the user*,
/// never a verdict.
enum SmsRisk { none, caution, danger }

class SmsResult {
  final SmsType type;
  final String? code;
  final SmsRisk risk;

  /// Spoken caution, or null when [risk] is none.
  final String? warning;

  const SmsResult(
    this.type, {
    this.code,
    this.risk = SmsRisk.none,
    this.warning,
  });
}

/// Offline, instant classification of an SMS body — type + fraud risk.
SmsResult classifySms(String body) {
  final base = _classifyType(body);
  final risk = _assessRisk(body, base);
  return SmsResult(base.type, code: base.code, risk: risk.risk, warning: risk.warning);
}

/// A short, speakable sender name: the first alpha run of a sender ID
/// ("VM-HDFCBK" → "HDFCBK"), or the last 4 digits of a phone number.
/// Shared by the SMS reader and the inbox screen.
String shortSender(String sender) {
  final alpha = RegExp(r'[A-Za-z]{3,}').firstMatch(sender)?.group(0);
  if (alpha != null) return alpha;
  final digits = sender.replaceAll(RegExp(r'\D'), '');
  return digits.length >= 4 ? digits.substring(digits.length - 4) : sender;
}

SmsResult _classifyType(String body) {
  final t = body.toLowerCase();

  final otpWord = RegExp(
      r'otp|one[- ]?time|verification code|\bcode\b|passcode|secure code');
  final code = RegExp(r'(?<!\d)(\d{4,8})(?!\d)').firstMatch(body)?.group(1);
  if (otpWord.hasMatch(t) && code != null) {
    return SmsResult(SmsType.otp, code: code);
  }

  const spamHints = [
    'won', 'winner', 'lottery', 'prize', 'congratulations', 'click here',
    'claim now', 'limited offer', 'loan approved', 'free recharge', 'bit.ly',
    'earn money', 'work from home', 'get rich',
  ];
  if (spamHints.any(t.contains)) return const SmsResult(SmsType.spam);

  const txnHints = [
    'debited', 'credited', 'a/c', 'account', 'balance', 'txn', 'upi',
    'payment', 'received rs', 'spent', 'withdrawn', 'transferred',
  ];
  if (txnHints.any(t.contains)) return const SmsResult(SmsType.transaction);

  return const SmsResult(SmsType.normal);
}

// A URL: scheme, bare www, a known shortener, or word.tld for a scammy TLD set.
final _linkRe = RegExp(
  r'https?://|www\.\w|bit\.ly|tinyurl|t\.co/|cutt\.ly|rb\.gy|is\.gd|shorturl|'
  r'\b[a-z0-9][a-z0-9-]*\.(?:com|net|org|in|io|xyz|info|link|click|app|shop|'
  r'online|site|live|vip|top|buzz|biz|ru|tk|ml|ga|cf|gq)\b',
  caseSensitive: false,
);
// 10+ contiguous digits (with spaces/dashes) — a phone number, not a 4–8 digit code.
final _phoneRe = RegExp(r'(?<!\d)(?:\+?\d[\d\s-]{8,}\d)(?!\d)');

bool _hasLink(String body) => _linkRe.hasMatch(body);
bool _hasPhone(String body) => _phoneRe.hasMatch(body);

const _urgency = [
  'blocked', 'suspend', 'deactivat', 'expire', 'expiry', 'kyc',
  'within 24', 'within 12', 'immediately', 'urgent', 'last warning',
  'penalty', 'legal action', 'verify now', 're-activate', 'reactivate',
  'unlock your', 'update your',
];
const _bait = [
  'refund', 'cashback', 'reward point', 'redeem', 'lucky draw', 'gift card',
  'you have won', 'kbc',
];
const _authority = [
  'bank', 'sbi', 'hdfc', 'icici', 'axis', 'paytm', 'phonepe', 'income tax',
  'aadhaar', 'aadhar', 'govt', 'government', 'electricity board', 'customs',
  'courier', 'parcel', 'india post', 'fedex', 'dhl',
];

class _Risk {
  final SmsRisk risk;
  final String? warning;
  const _Risk(this.risk, [this.warning]);
}

// A link you're meant to tap: a real URL or a shortener. A bare vanity domain
// ("www.pw.live", "sbi.co.in") in an otherwise-normal message is not this.
final _actionableLinkRe = RegExp(
  r'https?://|bit\.ly|tinyurl|t\.co/|cutt\.ly|rb\.gy|is\.gd|shorturl|tny\.',
  caseSensitive: false,
);

_Risk _assessRisk(String body, SmsResult base) {
  final t = body.toLowerCase();
  final link = _hasLink(body);
  final actionableLink = _actionableLinkRe.hasMatch(body);
  final phone = _hasPhone(body);
  final urgent = _urgency.any(t.contains);

  // OTP + a tappable link or a "call this number" — real OTP texts never do
  // this. A brand's own bare domain ("...-PWALLA @www.pw.live") is not enough.
  if (base.type == SmsType.otp) {
    if (actionableLink ||
        t.contains('click') ||
        (t.contains('call') && phone) ||
        (link && urgent)) {
      return const _Risk(
        SmsRisk.danger,
        'This message has a one-time code and wants you to open a link or make '
            'a call. Never share a code with anyone and do not open links. No '
            'real bank or company asks for your code.',
      );
    }
    if (link) {
      return const _Risk(
        SmsRisk.caution,
        'This message has a one-time code and mentions a website. Never share '
            'the code with anyone. If you need the site, type the address '
            'yourself — do not tap a link.',
      );
    }
  }
  // Urgency plus a way to act on it — the classic scam shape.
  if (urgent && (link || phone)) {
    return const _Risk(
      SmsRisk.danger,
      'This message is trying to rush you. Real banks and government offices '
          'do not work this way. Do not open any link or call any number in '
          'it. Ask someone you trust.',
    );
  }
  // Money or a prize behind a link.
  if (_bait.any(t.contains) && link) {
    return const _Risk(
      SmsRisk.danger,
      'This offers you money or a prize and wants you to open a link. That is '
          'almost always a scam. Do not open it.',
    );
  }
  // Claims to be a bank or an official body, and carries a link.
  if (_authority.any(t.contains) && link) {
    return const _Risk(
      SmsRisk.danger,
      'This claims to be from a bank or an official body and contains a link. '
          'They do not send links like this. Do not open it.',
    );
  }
  // A bare link you were not expecting.
  if (link) {
    return const _Risk(
      SmsRisk.caution,
      'This message contains a web link. Do not open links you were not '
          'expecting.',
    );
  }
  // Spam that wants you to phone a number.
  if (base.type == SmsType.spam && phone) {
    return const _Risk(
      SmsRisk.caution,
      'This looks like spam and wants you to call a number. Do not call it.',
    );
  }
  return const _Risk(SmsRisk.none);
}

/// Run: `dart run --enable-asserts lib/services/sms_classifier.dart`
/// (plain `dart run` does NOT execute `assert`s).
void main() {
  // Type classification.
  assert(classifySms('Your OTP is 449281. Do not share.').type == SmsType.otp);
  assert(classifySms('Use code 5567 to verify').code == '5567');
  assert(classifySms('Congratulations! You won a lottery prize').type ==
      SmsType.spam);
  assert(classifySms('Rs 500 debited from a/c XX1234').type ==
      SmsType.transaction);
  assert(classifySms('Are we meeting at 5?').type == SmsType.normal);
  assert(classifySms('Call me on 91234').type == SmsType.normal);

  // Fraud risk — danger.
  assert(classifySms('Your OTP is 4321. Enter it at http://sbi-verify.xyz')
          .risk ==
      SmsRisk.danger);
  assert(classifySms(
              'URGENT: your account is blocked. Verify at http://bit.ly/x now')
          .risk ==
      SmsRisk.danger);
  assert(classifySms('You won a refund of Rs 5000, claim at www.refund-portal.in')
          .risk ==
      SmsRisk.danger);
  assert(classifySms(
              'KYC update pending. Visit https://kyc-hdfc.top or call 1800-000-1111')
          .risk ==
      SmsRisk.danger);

  // Fraud risk — caution.
  assert(classifySms('Sale ends today, see items at www.myshop.in').risk ==
      SmsRisk.caution);
  // A legit brand OTP that carries only its own vanity domain — caution, not
  // danger (no scheme, no shortener, no "click"/"call", no urgency).
  assert(classifySms(
              '843508 is your OTP for PhysicsWallah, valid 10 minutes. '
              '-PWALLA @www.pw.live #843508')
          .risk ==
      SmsRisk.caution);
  // OTP + a real tappable link is still danger.
  assert(classifySms('OTP 4321. Enter it at http://sbi-verify.xyz to continue')
          .risk ==
      SmsRisk.danger);

  // Fraud risk — none (legit messages must not trip the rules).
  assert(classifySms('Your OTP is 449281. Do not share.').risk == SmsRisk.none);
  assert(classifySms('Rs 500 debited from a/c XX1234').risk == SmsRisk.none);
  assert(classifySms('Are we meeting at 5?').risk == SmsRisk.none);
  assert(classifySms('Reminder: electricity bill of Rs 840 due on 12 Sep')
          .risk ==
      SmsRisk.none);

  // A danger message always carries a spoken warning.
  final d = classifySms('URGENT account blocked, verify http://bit.ly/x');
  assert(d.risk == SmsRisk.danger && (d.warning?.isNotEmpty ?? false));

  // shortSender: alpha run wins, else last 4 digits, else the raw string.
  assert(shortSender('VM-HDFCBK') == 'HDFCBK');
  assert(shortSender('+91 98765 43210') == '3210');
  assert(shortSender('AD-720912') == '0912');
  assert(shortSender('12') == '12');

  print('sms_classifier: all checks passed');
}
