import 'package:equatable/equatable.dart';

enum TokenType { text, url, phone, email, date, otp }

class MessageToken extends Equatable {
  final TokenType type;
  final String text;
  final int start;
  final int end;

  const MessageToken(this.type, this.text, this.start, this.end);

  @override
  List<Object?> get props => [type, text, start, end];
}

class SmartTextParser {
  static List<MessageToken> parse(String body) {
    if (body.isEmpty) return [];

    final List<MessageToken> matches = [];

    // 1. OTP
    final hasOtpKeyword = RegExp(
      r'\b(code|otp|pin|verification|password)\b',
      caseSensitive: false,
    ).hasMatch(body);
    if (hasOtpKeyword) {
      final otpMatches = RegExp(r'(?<!\d)\d{4,8}(?!\d)').allMatches(body);
      for (final m in otpMatches) {
        matches.add(MessageToken(TokenType.otp, m.group(0)!, m.start, m.end));
      }
    }

    // 2. Date
    final dateMatches = RegExp(r'\b\d{1,4}[-/.]\d{1,2}[-/.]\d{1,4}\b')
        .allMatches(body);
    for (final m in dateMatches) {
      matches.add(MessageToken(TokenType.date, m.group(0)!, m.start, m.end));
    }

    // 3. URL
    final urlMatches = RegExp(r'(https?://[^\s]+)|(www\.[^\s]+)')
        .allMatches(body);
    for (final m in urlMatches) {
      matches.add(MessageToken(TokenType.url, m.group(0)!, m.start, m.end));
    }

    // 4. Email
    final emailMatches = RegExp(
      r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}',
    ).allMatches(body);
    for (final m in emailMatches) {
      matches.add(MessageToken(TokenType.email, m.group(0)!, m.start, m.end));
    }

    // 5. Phone (must be careful not to match dates, but overlap logic handles it)
    final phoneMatches = RegExp(r'\+?[0-9][\d\s\-(]{7,}[0-9]').allMatches(body);
    for (final m in phoneMatches) {
      matches.add(MessageToken(TokenType.phone, m.group(0)!, m.start, m.end));
    }

    // Resolve overlaps by priority
    int getPriority(TokenType type) {
      switch (type) {
        case TokenType.otp:
          return 5;
        case TokenType.date:
          return 4;
        case TokenType.url:
          return 3;
        case TokenType.email:
          return 2;
        case TokenType.phone:
          return 1;
        case TokenType.text:
          return 0;
      }
    }

    matches.sort((a, b) {
      final p1 = getPriority(a.type);
      final p2 = getPriority(b.type);
      if (p1 != p2) return p2.compareTo(p1);
      // If same priority, favor longer match
      final len1 = a.end - a.start;
      final len2 = b.end - b.start;
      if (len1 != len2) return len2.compareTo(len1);
      return a.start.compareTo(b.start);
    });

    final List<MessageToken> nonOverlapping = [];
    for (final m in matches) {
      bool overlaps = false;
      for (final existing in nonOverlapping) {
        if (m.start < existing.end && m.end > existing.start) {
          overlaps = true;
          break;
        }
      }
      if (!overlaps) {
        nonOverlapping.add(m);
      }
    }

    // Sort valid matches by start index
    nonOverlapping.sort((a, b) => a.start.compareTo(b.start));

    // Fill gaps with text tokens
    final List<MessageToken> finalTokens = [];
    int lastEnd = 0;

    for (final m in nonOverlapping) {
      if (m.start > lastEnd) {
        finalTokens.add(
          MessageToken(
            TokenType.text,
            body.substring(lastEnd, m.start),
            lastEnd,
            m.start,
          ),
        );
      }
      finalTokens.add(m);
      lastEnd = m.end;
    }

    if (lastEnd < body.length) {
      finalTokens.add(
        MessageToken(
          TokenType.text,
          body.substring(lastEnd),
          lastEnd,
          body.length,
        ),
      );
    }

    return finalTokens;
  }
}
