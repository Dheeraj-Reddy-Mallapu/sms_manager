import 'package:equatable/equatable.dart';

class SmsThread extends Equatable {
  final int id;
  final String recipientIds;
  final String address;
  final int messageCount;
  final String snippet;
  final int date;
  final bool read;
  final int unreadCount;
  final String category; // E.g., 'Personal', 'Transactions', 'Promotions'
  final String? contactName;
  final String? contactPhotoUri;

  const SmsThread({
    required this.id,
    required this.recipientIds,
    required this.address,
    required this.messageCount,
    required this.snippet,
    required this.date,
    required this.read,
    this.unreadCount = 0,
    this.category = 'All',
    this.contactName,
    this.contactPhotoUri,
  });

  factory SmsThread.fromMap(Map<String, dynamic> map) {
    return SmsThread(
      id: (map['id'] as num).toInt(),
      recipientIds: map['recipientIds'] as String? ?? '',
      address: map['address'] as String? ?? '',
      messageCount: (map['messageCount'] as num?)?.toInt() ?? 0,
      snippet: map['snippet'] as String? ?? '',
      date: (map['date'] as num?)?.toInt() ?? 0,
      read: ((map['read'] as num?)?.toInt() ?? 0) == 1,
      unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
      category: map['category'] as String? ?? 'All',
      contactName: map['contactName'] as String?,
      contactPhotoUri: map['contactPhotoUri'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'recipientIds': recipientIds,
      'address': address,
      'messageCount': messageCount,
      'snippet': snippet,
      'date': date,
      'read': read ? 1 : 0,
      'unreadCount': unreadCount,
      'category': category,
      'contactName': contactName,
      'contactPhotoUri': contactPhotoUri,
    };
  }

  SmsThread copyWith({
    String? category,
    String? contactName,
    String? contactPhotoUri,
    bool? read,
    int? unreadCount,
    String? snippet,
    int? date,
    String? address,
  }) {
    return SmsThread(
      id: id,
      recipientIds: recipientIds,
      address: address ?? this.address,
      messageCount: messageCount,
      snippet: snippet ?? this.snippet,
      date: date ?? this.date,
      read: read ?? this.read,
      unreadCount: unreadCount ?? this.unreadCount,
      category: category ?? this.category,
      contactName: contactName ?? this.contactName,
      contactPhotoUri: contactPhotoUri ?? this.contactPhotoUri,
    );
  }

  @override
  List<Object?> get props => [
    id,
    recipientIds,
    address,
    messageCount,
    snippet,
    date,
    read,
    unreadCount,
    category,
    contactName,
    contactPhotoUri,
  ];
}
