import 'package:sms_manager/src/services/sms_extractor.dart';

class SmsClassifier {
  /// Analyzes a message and returns a comma-separated list of categories.
  /// Example: 'Finance,Shopping' or 'People'
  static String classify({required String address, required String body, String? contactName}) {
    final Set<String> categories = {};
    address = address.toUpperCase();

    // 1. SENDER-BASED
    // Phone numbers OR known contacts
    if (SmsPatterns.phoneSender.hasMatch(address) || contactName != null) {
      categories.add('People');
    }

    // Govt / Emergency namespaces
    if (SmsPatterns.govtSender.hasMatch(address)) {
      categories.add('Govt & Alerts');
    }

    // Travel namespaces
    if (SmsPatterns.travelSender.hasMatch(address)) {
      categories.add('Travel');
    }

    // 2. BODY KEYWORDS
    if (SmsPatterns.otpKeywords.hasMatch(body)) {
      categories.add('OTP');
    }

    bool isFinance = false;
    // Finance signals
    if (SmsPatterns.financeKeywords.hasMatch(body)) {
      categories.add('Finance');
      isFinance = true;
    }

    bool isShopping = false;
    // Explicit Shopping signals
    if (SmsPatterns.shoppingKeywords.hasMatch(body)) {
      categories.add('Shopping');
      isShopping = true;
    }

    // Explicit Travel signals
    if (SmsPatterns.travelKeywords.hasMatch(body)) {
      categories.add('Travel');
    }

    // Health signals
    if (SmsPatterns.healthKeywords.hasMatch(body)) {
      categories.add('Health');
    }
    
    // Offers signals
    if (SmsPatterns.offerKeywords.hasMatch(body)) {
      if (!categories.contains('OTP') && !categories.contains('Govt & Alerts')) {
        categories.add('Offers');
      }
    }

    // 3. NO-LIST IMPLICIT SHOPPING (Dual-labeling)
    if (isFinance && !isShopping) {
      if (SmsPatterns.shoppingImplicit.hasMatch(body)) {
        categories.add('Shopping');
      }
    }

    return categories.join(',');
  }
}
