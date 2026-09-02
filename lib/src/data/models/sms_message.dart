import 'package:equatable/equatable.dart';

class SmsMessage extends Equatable {
  final int id;
  final int threadId;
  final String address;
  final String body;
  final int date;
  final bool read;
  final int type; // 1=Inbox, 2=Sent, 3=Draft, 4=Outbox, 5=Failed, 6=Queued
  final bool isStarred;
  final int subscriptionId; // -1 = unknown, 0 = SIM 1, 1 = SIM 2 etc.
  final int status; // -1 = None, 0 = Complete, 32 = Pending, 64 = Failed (as per Telephony.Sms.STATUS)

  /// True for optimistically-inserted outgoing messages that haven't been
  /// confirmed by the native SMS stack yet.
  final bool isOptimistic;

  const SmsMessage({
    required this.id,
    required this.threadId,
    required this.address,
    required this.body,
    required this.date,
    required this.read,
    required this.type,
    this.isStarred = false,
    this.subscriptionId = -1,
    this.status = -1,
    this.isOptimistic = false,
  });

  bool get isOutgoing =>
      type == 2 || type == 3 || type == 4 || type == 5 || type == 6;
  bool get isSent => type == 2;
  bool get isFailed => type == 5;
  bool get isDelivered => status == 0; // STATUS_COMPLETE

  factory SmsMessage.fromMap(Map<String, dynamic> map) {
    return SmsMessage(
      id: (map['id'] as num).toInt(),
      threadId: (map['threadId'] as num).toInt(),
      address: map['address'] as String? ?? '',
      body: map['body'] as String? ?? '',
      date: (map['date'] as num?)?.toInt() ?? 0,
      read: ((map['read'] as num?)?.toInt() ?? 0) == 1,
      type: (map['type'] as num?)?.toInt() ?? 1,
      isStarred: ((map['isStarred'] as num?)?.toInt() ?? 0) == 1,
      subscriptionId: (map['subscriptionId'] as num?)?.toInt() ?? -1,
      status: (map['status'] as num?)?.toInt() ?? -1,
      isOptimistic: false, // never persisted
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'threadId': threadId,
      'address': address,
      'body': body,
      'date': date,
      'read': read ? 1 : 0,
      'type': type,
      'isStarred': isStarred ? 1 : 0,
      'subscriptionId': subscriptionId,
      'status': status,
    };
  }

  SmsMessage copyWith({
    int? id,
    bool? read,
    bool? isStarred,
    bool? isOptimistic,
    int? type,
    int? subscriptionId,
  }) => SmsMessage(
    id: id ?? this.id,
    threadId: threadId,
    address: address,
    body: body,
    date: date,
    read: read ?? this.read,
    type: type ?? this.type,
    isStarred: isStarred ?? this.isStarred,
    subscriptionId: subscriptionId ?? this.subscriptionId,
    isOptimistic: isOptimistic ?? this.isOptimistic,
  );

  @override
  List<Object?> get props => [
    id,
    threadId,
    address,
    body,
    date,
    read,
    type,
    isStarred,
    subscriptionId,
    isOptimistic,
  ];
}
