import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:sms_manager/src/data/models/sms_message.dart';
import 'package:sms_manager/src/data/repositories/sms_repository.dart';

// ── Events ───────────────────────────────────────────────────────────────────

abstract class ConversationEvent extends Equatable {
  const ConversationEvent();
  @override
  List<Object?> get props => [];
}

class LoadMessages extends ConversationEvent {
  final int threadId;
  final String address;
  const LoadMessages(this.threadId, {this.address = ''});
  @override
  List<Object?> get props => [threadId, address];
}

class LoadMoreMessages extends ConversationEvent {
  final int threadId;
  const LoadMoreMessages(this.threadId);
  @override
  List<Object?> get props => [threadId];
}

class SendMessage extends ConversationEvent {
  final int threadId;
  final String address;
  final String body;
  final SmsMessage? replyTo; // for quoted reply context
  const SendMessage({
    required this.threadId,
    required this.address,
    required this.body,
    this.replyTo,
  });
  @override
  List<Object?> get props => [threadId, address, body];
}

class DeleteMessage extends ConversationEvent {
  final int messageId;
  const DeleteMessage(this.messageId);
  @override
  List<Object?> get props => [messageId];
}

class ToggleStarMessage extends ConversationEvent {
  final SmsMessage message;
  const ToggleStarMessage(this.message);
  @override
  List<Object?> get props => [message.id];
}

class SelectMessage extends ConversationEvent {
  final int messageId;
  const SelectMessage(this.messageId);
  @override
  List<Object?> get props => [messageId];
}

class ClearSelection extends ConversationEvent {
  const ClearSelection();
}

class SearchMessages extends ConversationEvent {
  final String query;
  const SearchMessages(this.query);
  @override
  List<Object?> get props => [query];
}

class ClearSearch extends ConversationEvent {
  const ClearSearch();
}

class MarkVisibleAsRead extends ConversationEvent {
  final int threadId;
  final List<int> visibleMessageIds;
  const MarkVisibleAsRead(this.threadId, this.visibleMessageIds);
  @override
  List<Object?> get props => [threadId, visibleMessageIds];
}

class IncomingMessageReceived extends ConversationEvent {
  final Map<String, dynamic> data;
  const IncomingMessageReceived(this.data);
  @override
  List<Object?> get props => [data];
}

// ── States ───────────────────────────────────────────────────────────────────

abstract class ConversationState extends Equatable {
  const ConversationState();
  @override
  List<Object?> get props => [];
}

class ConversationInitial extends ConversationState {}

class ConversationLoading extends ConversationState {}

class ConversationLoaded extends ConversationState {
  /// Messages in display order: oldest first (index 0) → newest last.
  final List<SmsMessage> messages;
  final int threadId;
  final String address;

  final bool hasMore; // older messages exist in Telephony provider
  final bool isLoadingMore; // spinner at top while fetching older page
  final bool isSending; // optimistic: send in progress

  final Set<int> selectedIds; // non-empty → multi-select mode
  final String searchQuery; // non-empty → search mode
  final Set<int> alreadyReadIds; // ids we've already sent markAsRead for

  const ConversationLoaded({
    required this.messages,
    required this.threadId,
    required this.address,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.isSending = false,
    this.selectedIds = const {},
    this.searchQuery = '',
    this.alreadyReadIds = const {},
  });

  /// Messages filtered by search query (empty = all)
  List<SmsMessage> get displayMessages {
    if (searchQuery.isEmpty) return messages;
    final q = searchQuery.toLowerCase();
    return messages.where((m) => m.body.toLowerCase().contains(q)).toList();
  }

  int get unreadBelow => messages.where((m) => !m.read && !m.isOutgoing).length;

  ConversationLoaded copyWith({
    List<SmsMessage>? messages,
    bool? hasMore,
    bool? isLoadingMore,
    bool? isSending,
    Set<int>? selectedIds,
    String? searchQuery,
    Set<int>? alreadyReadIds,
  }) => ConversationLoaded(
    messages: messages ?? this.messages,
    threadId: threadId,
    address: address,
    hasMore: hasMore ?? this.hasMore,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    isSending: isSending ?? this.isSending,
    selectedIds: selectedIds ?? this.selectedIds,
    searchQuery: searchQuery ?? this.searchQuery,
    alreadyReadIds: alreadyReadIds ?? this.alreadyReadIds,
  );

  @override
  List<Object?> get props => [
    messages,
    threadId,
    hasMore,
    isLoadingMore,
    isSending,
    selectedIds,
    searchQuery,
    alreadyReadIds,
  ];
}

class ConversationError extends ConversationState {
  final String message;
  const ConversationError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── BLoC ─────────────────────────────────────────────────────────────────────

class ConversationBloc extends Bloc<ConversationEvent, ConversationState> {
  final SmsRepository repository;
  StreamSubscription<Map<String, dynamic>>? _incomingSubscription;

  static const _pageSize = 50;

  ConversationBloc({required this.repository}) : super(ConversationInitial()) {
    on<LoadMessages>(_onLoadMessages);
    on<LoadMoreMessages>(_onLoadMoreMessages);
    on<SendMessage>(_onSendMessage);
    on<DeleteMessage>(_onDeleteMessage);
    on<ToggleStarMessage>(_onToggleStar);
    on<SelectMessage>(_onSelectMessage);
    on<ClearSelection>(_onClearSelection);
    on<SearchMessages>(_onSearch);
    on<ClearSearch>(_onClearSearch);
    on<MarkVisibleAsRead>(_onMarkVisibleAsRead);
    on<IncomingMessageReceived>(_onIncomingMessage);
  }

  // ── Load initial page ──────────────────────────────────────────────────

  Future<void> _onLoadMessages(
    LoadMessages event,
    Emitter<ConversationState> emit,
  ) async {
    emit(ConversationLoading());

    // Subscribe to incoming stream for this conversation
    await _incomingSubscription?.cancel();
    _incomingSubscription = repository.incomingSmsStream.listen((data) {
      final addr = data['address'] as String? ?? '';
      if (addr == event.address || event.address.isEmpty) {
        add(IncomingMessageReceived(data));
      }
    }, onError: (_) {});

    try {
      // Fetch newest 50 from cache (fast), then refresh from native
      final cached = await repository.getMessages(
        event.threadId,
        limit: _pageSize,
        offset: 0,
      );
      final displayList = _toDisplayOrder(cached);

      // hasMore: if we got a full page, assume there are more
      final hasMore = cached.length >= _pageSize;

      emit(
        ConversationLoaded(
          messages: displayList,
          threadId: event.threadId,
          address: event.address,
          hasMore: hasMore,
        ),
      );

      // Background-refresh from native
      final fresh = await repository.getMessages(
        event.threadId,
        limit: _pageSize,
        offset: 0,
        forceSync: true,
      );
      final freshDisplay = _toDisplayOrder(fresh);

      if (!isClosed) {
        emit(
          ConversationLoaded(
            messages: freshDisplay,
            threadId: event.threadId,
            address: event.address,
            hasMore: fresh.length >= _pageSize,
          ),
        );
      }
    } catch (e) {
      emit(ConversationError('Failed to load: $e'));
    }
  }

  // ── Load older messages (scroll up) ───────────────────────────────────

  Future<void> _onLoadMoreMessages(
    LoadMoreMessages event,
    Emitter<ConversationState> emit,
  ) async {
    final current = state;
    if (current is! ConversationLoaded) return;
    if (current.isLoadingMore || !current.hasMore) return;

    emit(current.copyWith(isLoadingMore: true));

    try {
      final offset = current.messages.length;
      final older = await repository.getMessages(
        event.threadId,
        limit: _pageSize,
        offset: offset,
        forceSync: true,
      );

      // Prepend older messages (they come DESC from native, reverse to ASC)
      final olderAsc = older.reversed.toList();
      final merged = [...olderAsc, ...current.messages];

      emit(
        current.copyWith(
          messages: merged,
          hasMore: older.length >= _pageSize,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      emit(current.copyWith(isLoadingMore: false));
    }
  }

  // ── Send message ───────────────────────────────────────────────────────

  Future<void> _onSendMessage(
    SendMessage event,
    Emitter<ConversationState> emit,
  ) async {
    final current = state;
    if (current is! ConversationLoaded) return;

    // Optimistic insert
    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final optimistic = SmsMessage(
      id: tempId,
      threadId: event.threadId,
      address: event.address,
      body: event.body,
      date: DateTime.now().millisecondsSinceEpoch,
      read: true,
      type: 2, // Sent
      isOptimistic: true,
    );
    emit(
      current.copyWith(
        messages: [...current.messages, optimistic],
        isSending: true,
      ),
    );

    try {
      final success = await repository.sendSms(
        event.threadId,
        event.address,
        event.body,
      );

      if (success) {
        // Re-fetch to get the real message ID from Telephony provider
        final fresh = await repository.getMessages(
          event.threadId,
          limit: _pageSize,
          offset: 0,
          forceSync: true,
        );
        final freshDisplay = _toDisplayOrder(fresh);
        if (!isClosed) {
          emit(current.copyWith(messages: freshDisplay, isSending: false));
        }
      } else {
        // Mark optimistic as failed
        final updated = current.messages.map((m) {
          return m.id == tempId ? m.copyWith(type: 5) : m; // type 5 = Failed
        }).toList();
        if (!isClosed) {
          emit(current.copyWith(messages: updated, isSending: false));
        }
      }
    } catch (_) {
      if (!isClosed) emit(current.copyWith(isSending: false));
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────

  Future<void> _onDeleteMessage(
    DeleteMessage event,
    Emitter<ConversationState> emit,
  ) async {
    final current = state;
    if (current is! ConversationLoaded) return;

    await repository.deleteMessageById(event.messageId);
    emit(
      current.copyWith(
        messages: current.messages
            .where((m) => m.id != event.messageId)
            .toList(),
      ),
    );
  }

  // ── Star / Bookmark ────────────────────────────────────────────────────

  Future<void> _onToggleStar(
    ToggleStarMessage event,
    Emitter<ConversationState> emit,
  ) async {
    final current = state;
    if (current is! ConversationLoaded) return;

    final toggled = !event.message.isStarred;
    await repository.setMessageStarred(event.message.id, starred: toggled);

    emit(
      current.copyWith(
        messages: current.messages
            .map(
              (m) =>
                  m.id == event.message.id ? m.copyWith(isStarred: toggled) : m,
            )
            .toList(),
      ),
    );
  }

  // ── Multi-select ───────────────────────────────────────────────────────

  void _onSelectMessage(SelectMessage event, Emitter<ConversationState> emit) {
    final current = state;
    if (current is! ConversationLoaded) return;
    final ids = Set<int>.from(current.selectedIds);
    if (ids.contains(event.messageId)) {
      ids.remove(event.messageId);
    } else {
      ids.add(event.messageId);
    }
    emit(current.copyWith(selectedIds: ids));
  }

  void _onClearSelection(
    ClearSelection event,
    Emitter<ConversationState> emit,
  ) {
    final current = state;
    if (current is! ConversationLoaded) return;
    emit(current.copyWith(selectedIds: {}));
  }

  // ── Search ─────────────────────────────────────────────────────────────

  void _onSearch(SearchMessages event, Emitter<ConversationState> emit) {
    final current = state;
    if (current is! ConversationLoaded) return;
    emit(current.copyWith(searchQuery: event.query));
  }

  void _onClearSearch(ClearSearch event, Emitter<ConversationState> emit) {
    final current = state;
    if (current is! ConversationLoaded) return;
    emit(current.copyWith(searchQuery: ''));
  }

  // ── Mark visible messages as read ──────────────────────────────────────

  Future<void> _onMarkVisibleAsRead(
    MarkVisibleAsRead event,
    Emitter<ConversationState> emit,
  ) async {
    final current = state;
    if (current is! ConversationLoaded) return;

    // Only mark IDs we haven't marked yet
    final newToMark = event.visibleMessageIds
        .where((id) => !current.alreadyReadIds.contains(id))
        .toList();
    if (newToMark.isEmpty) return;

    final updatedReadIds = Set<int>.from(current.alreadyReadIds)
      ..addAll(newToMark);

    // Mark in Telephony provider (debounced — done as one call)
    await repository.markThreadAsRead(event.threadId);

    // Update local state
    final updatedMessages = current.messages.map((m) {
      return newToMark.contains(m.id) ? m.copyWith(read: true) : m;
    }).toList();

    emit(
      current.copyWith(
        messages: updatedMessages,
        alreadyReadIds: updatedReadIds,
      ),
    );
  }

  // ── Real-time incoming SMS ─────────────────────────────────────────────

  Future<void> _onIncomingMessage(
    IncomingMessageReceived event,
    Emitter<ConversationState> emit,
  ) async {
    final current = state;
    if (current is! ConversationLoaded) return;

    // Re-fetch latest page to get the proper message ID from Telephony
    final fresh = await repository.getMessages(
      current.threadId,
      limit: _pageSize,
      offset: 0,
      forceSync: true,
    );
    final freshDisplay = _toDisplayOrder(fresh);

    if (!isClosed) {
      emit(current.copyWith(messages: freshDisplay));
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  /// Reverses DESC result from DB/native into ASC (oldest→newest) for display.
  List<SmsMessage> _toDisplayOrder(List<SmsMessage> descList) {
    return descList.reversed.toList();
  }

  @override
  Future<void> close() {
    _incomingSubscription?.cancel();
    return super.close();
  }
}
