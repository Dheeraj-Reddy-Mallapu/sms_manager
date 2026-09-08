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
  final String category; // E.g., 'Finance,Shopping'
  final String? contactName;
  final String? contactPhotoUri;
  final bool hasStarredMessages;
  final bool isArchived;
  final bool isMuted;
  final bool isBlocked;

  /// Returns the categories as a list, filtering out empty strings.
  List<String> get categoryList => category
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

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
    this.hasStarredMessages = false,
    this.isArchived = false,
    this.isMuted = false,
    this.isBlocked = false,
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
      hasStarredMessages:
          ((map['hasStarredMessages'] as num?)?.toInt() ?? 0) == 1,
      isArchived: ((map['isArchived'] as num?)?.toInt() ?? 0) == 1,
      isMuted: ((map['isMuted'] as num?)?.toInt() ?? 0) == 1,
      isBlocked: ((map['isBlocked'] as num?)?.toInt() ?? 0) == 1,
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
      'isArchived': isArchived ? 1 : 0,
      'isMuted': isMuted ? 1 : 0,
      'isBlocked': isBlocked ? 1 : 0,
      // hasStarredMessages is derived, not stored directly in threads table usually
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
    bool? isArchived,
    bool? isMuted,
    bool? isBlocked,
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
      isArchived: isArchived ?? this.isArchived,
      isMuted: isMuted ?? this.isMuted,
      isBlocked: isBlocked ?? this.isBlocked,
      hasStarredMessages: hasStarredMessages,
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
    hasStarredMessages,
    isArchived,
    isMuted,
    isBlocked,
  ];
}
