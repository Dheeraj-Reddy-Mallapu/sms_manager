class SmsPatterns {
  // Compiled once for maximum performance.
  static final RegExp phoneSender = RegExp(r'^\+?[0-9]{10,14}$');
  static final RegExp govtSender = RegExp(r'UIDAI|GOVT|ITDEPT|AADHAR|EPF');
  static final RegExp travelSender = RegExp(
    r'IRCTC|INDIGO|MAKEMY|YATRA|UBER|OLA',
  );

  static final RegExp otpKeywords = RegExp(
    r'\b(otp|one time password|verification code|pin code is|secret code)\b',
    caseSensitive: false,
  );
  static final RegExp otpValue = RegExp(r'\b(\d{4,8})\b'); // Extract 4-8 digits

  static final RegExp financeKeywords = RegExp(
    r'\b(debited|credited|a/c|acct|account|rs\.?|inr|transaction|due|payable|outstanding|bill)\b',
    caseSensitive: false,
  );
  static final RegExp financeAmount = RegExp(
    r'(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );
  static final RegExp financeDebited = RegExp(
    r'\b(debited|spent|paid|deducted)\b',
    caseSensitive: false,
  );
  static final RegExp financeCredited = RegExp(
    r'\b(credited|received|refunded|deposited)\b',
    caseSensitive: false,
  );
  static final RegExp financeBill = RegExp(
    r'\b(due|payable|outstanding|bill)\b',
    caseSensitive: false,
  );

  static final RegExp shoppingKeywords = RegExp(
    r'\b(order|delivery|delivered|shipped|out for delivery|amazon|flipkart|myntra|zomato|swiggy|blinkit)\b',
    caseSensitive: false,
  );
  static final RegExp shoppingImplicit = RegExp(
    r'\b(purchased? at|spent at|payment to|paid to)\s+([a-z\s]+)',
    caseSensitive: false,
  );

  static final RegExp travelKeywords = RegExp(
    r'\b(pnr|flight|ticket|boarding|hotel booking)\b',
    caseSensitive: false,
  );
  static final RegExp travelPnr = RegExp(
    r'\bPNR[:\s]*([A-Z0-9]{6})\b',
    caseSensitive: false,
  );

  static final RegExp healthKeywords = RegExp(
    r'\b(doctor|appointment|lab report|apollo|practo|health|clinic)\b',
    caseSensitive: false,
  );
  static final RegExp offerKeywords = RegExp(
    r'\b(offer|discount|cashback|coupon|sale|flat off)\b',
    caseSensitive: false,
  );

  static final RegExp urlLink = RegExp(
    r'(https?:\/\/[^\s]+|bit\.ly\/[^\s]+|wa\.me\/[^\s]+)',
    caseSensitive: false,
  );
}

class ExtractedData {
  final String? otp;
  final String? amount;
  final String? transactionType; // 'debit', 'credit'
  final String? merchant;
  final String? url;
  final String? pnr;

  ExtractedData({
    this.otp,
    this.amount,
    this.transactionType,
    this.merchant,
    this.url,
    this.pnr,
  });

  bool get hasAny =>
      otp != null || amount != null || url != null || pnr != null;
}

class SmsExtractor {
  static ExtractedData extract(String body) {
    String? otp;
    String? amount;
    String? type;
    String? merchant;
    String? url;
    String? pnr;

    // OTP
    if (SmsPatterns.otpKeywords.hasMatch(body)) {
      final match = SmsPatterns.otpValue.firstMatch(body);
      if (match != null) otp = match.group(1);
    }

    // Finance Amount
    final amountMatch = SmsPatterns.financeAmount.firstMatch(body);
    if (amountMatch != null) amount = amountMatch.group(1);

    if (SmsPatterns.financeBill.hasMatch(body)) {
      type = 'bill';
    } else if (SmsPatterns.financeDebited.hasMatch(body)) {
      type = 'debit';
    } else if (SmsPatterns.financeCredited.hasMatch(body)) {
      type = 'credit';
    }

    // Implicit Merchant (from "spent at X")
    final implicitMatch = SmsPatterns.shoppingImplicit.firstMatch(body);
    if (implicitMatch != null) merchant = implicitMatch.group(2)?.trim();

    // URLs & PNR
    final urlMatch = SmsPatterns.urlLink.firstMatch(body);
    if (urlMatch != null) url = urlMatch.group(1);

    final pnrMatch = SmsPatterns.travelPnr.firstMatch(body);
    if (pnrMatch != null) pnr = pnrMatch.group(1);

    return ExtractedData(
      otp: otp,
      amount: amount,
      transactionType: type,
      merchant: merchant,
      url: url,
      pnr: pnr,
    );
  }
}
