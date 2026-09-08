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
  final int? highlightMessageId;
  final int? targetDate;
  const LoadMessages(this.threadId, {this.address = '', this.highlightMessageId, this.targetDate});
  @override
  List<Object?> get props => [threadId, address, highlightMessageId, targetDate];
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
  final List<int> messageIds;
  const MarkVisibleAsRead(this.threadId, this.messageIds);
  @override
  List<Object?> get props => [threadId, messageIds];
}

class IncomingMessageReceived extends ConversationEvent {
  final Map<dynamic, dynamic> data;
  const IncomingMessageReceived(this.data);
  @override
  List<Object?> get props => [data];
}

class SystemMessagesChanged extends ConversationEvent {
  const SystemMessagesChanged();
}

class DeleteConversation extends ConversationEvent {
  final int threadId;
  const DeleteConversation(this.threadId);
  @override
  List<Object?> get props => [threadId];
}

class SelectSim extends ConversationEvent {
  final int simId;
  const SelectSim(this.simId);
  @override
  List<Object?> get props => [simId];
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
  final List<SmsMessage> messages;
  final int threadId;
  final String address;
  final bool hasMore;
  final bool isLoadingMore;
  final bool isSending;
  final Set<int> selectedIds;
  final bool isSearchActive;
  final String searchQuery;
  final int? selectedSimId;
  final int? highlightMessageId;
  final int? scrollToMessageId;
  final Set<int> alreadyReadIds;
  final List<Map<String, dynamic>> simInfoList;

  const ConversationLoaded({
    required this.messages,
    required this.threadId,
    required this.address,
    this.hasMore = true,
    this.isLoadingMore = false,
    this.isSending = false,
    this.selectedIds = const {},
    this.isSearchActive = false,
    this.searchQuery = '',
    this.selectedSimId,
    this.highlightMessageId,
    this.scrollToMessageId,
    this.alreadyReadIds = const {},
    this.simInfoList = const [],
  });

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
    bool? isSearchActive,
    String? searchQuery,
    int? selectedSimId,
    int? highlightMessageId,
    int? scrollToMessageId,
    Set<int>? alreadyReadIds,
    List<Map<String, dynamic>>? simInfoList,
  }) {
    return ConversationLoaded(
      messages: messages ?? this.messages,
      threadId: threadId,
      address: address,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isSending: isSending ?? this.isSending,
      selectedIds: selectedIds ?? this.selectedIds,
      isSearchActive: isSearchActive ?? this.isSearchActive,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedSimId: selectedSimId ?? this.selectedSimId,
      highlightMessageId: highlightMessageId ?? this.highlightMessageId,
      scrollToMessageId: scrollToMessageId ?? this.scrollToMessageId,
      alreadyReadIds: alreadyReadIds ?? this.alreadyReadIds,
      simInfoList: simInfoList ?? this.simInfoList,
    );
  }

  @override
  List<Object?> get props => [
        messages,
        threadId,
        address,
        hasMore,
        isLoadingMore,
        isSending,
        selectedIds,
        isSearchActive,
        searchQuery,
        selectedSimId,
        highlightMessageId,
        scrollToMessageId,
        alreadyReadIds,
        simInfoList,
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
  StreamSubscription? _incomingSubscription;
  StreamSubscription? _systemChangesSubscription;
  DateTime? _lastSystemChange;

  static const _pageSize = 50;

  ConversationBloc({required this.repository}) : super(ConversationInitial()) {
    on<LoadMessages>(_onLoadMessages);
    on<LoadMoreMessages>(_onLoadMoreMessages);
    on<SendMessage>(_onSendMessage);
    on<DeleteMessage>(_onDeleteMessage);
    on<DeleteConversation>(_onDeleteConversation);
    on<ToggleStarMessage>(_onToggleStar);
    on<SelectMessage>(_onSelectMessage);
    on<ClearSelection>(_onClearSelection);
    on<SearchMessages>(_onSearch);
    on<ClearSearch>(_onClearSearch);
    on<MarkVisibleAsRead>(_onMarkVisibleAsRead);
    on<IncomingMessageReceived>(_onIncomingMessage);
    on<SystemMessagesChanged>(_onSystemMessagesChanged);
    on<SelectSim>(_onSelectSim);

    _systemChangesSubscription = repository.systemSmsChanges.listen((_) {
      add(const SystemMessagesChanged());
    }, onError: (_) {});
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
      final limit = (event.highlightMessageId != null || event.targetDate != null) ? 5000 : _pageSize;
      
      // Fetch newest 50 (or 5000) from cache (fast), then refresh from native
      final cached = await repository.getMessages(
        event.threadId,
        limit: limit,
        offset: 0,
      );
      
      int? effectiveHighlightId = event.highlightMessageId;
      int? effectiveScrollId = event.highlightMessageId;
      
      if (effectiveScrollId == null && event.targetDate != null) {
        // Try to find the message that matches this exact date to scroll to (no highlight)
        try {
          final targetMsg = cached.firstWhere((m) => m.date == event.targetDate);
          effectiveScrollId = targetMsg.id;
        } catch (_) {}
      }
      
      final displayList = _toDisplayOrder(cached);

      // hasMore: if we got a full page, assume there are more
      final hasMore = cached.length >= limit;

      emit(
        ConversationLoaded(
          messages: displayList,
          threadId: event.threadId,
          address: event.address,
          hasMore: hasMore,
          highlightMessageId: effectiveHighlightId,
          scrollToMessageId: effectiveScrollId,
        ),
      );

      // Background-refresh from native
      final fresh = await repository.getMessages(
        event.threadId,
        limit: limit,
        offset: 0,
        forceSync: true,
      );
      final freshDisplay = _toDisplayOrder(fresh);

      final simInfoList = await repository.getSimInfo();
      int? defaultSimId;
      if (simInfoList.isNotEmpty) {
        final defaultSim = simInfoList.cast<Map<String, dynamic>>().firstWhere(
          (sim) => sim['isDefault'] == true,
          orElse: () => simInfoList.first,
        );
        defaultSimId = defaultSim['subscriptionId'] as int?;
      }

      if (!isClosed) {
        emit(
          ConversationLoaded(
            messages: freshDisplay,
            threadId: event.threadId,
            address: event.address,
            hasMore: fresh.length >= limit,
            simInfoList: simInfoList,
            selectedSimId: defaultSimId,
            highlightMessageId: effectiveHighlightId,
            scrollToMessageId: effectiveScrollId,
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

      // older messages come from DB in DESC order (newest-of-batch first).
      // current.messages is also DESC (newest first).
      // To keep DESC: put current (newer) first, then older at the end.
      // De-dupe by id in case of overlap.
      final existingIds = current.messages.map((m) => m.id).toSet();
      final newOlder = older.where((m) => !existingIds.contains(m.id)).toList();
      final merged = [...current.messages, ...newOlder];

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

    emit(current.copyWith(isSending: true));

    try {
      final success = await repository.sendSms(
        event.threadId,
        event.address,
        event.body,
        subscriptionId: current.selectedSimId,
      );

      if (success) {
        // Just reload from local DB since repository.sendSms did the optimistic insert.
        // The background native broadcast will later trigger SystemMessagesChanged to update to Sent status.
        final fresh = await repository.getMessages(
          event.threadId,
          limit: _pageSize,
          offset: 0,
          forceSync: false,
        );
        final freshDisplay = _toDisplayOrder(fresh);
        final merged = _mergeMessages(current.messages, freshDisplay);

        if (!isClosed) {
          emit(current.copyWith(messages: merged, isSending: false));
        }
      } else {
        // If native send completely failed before even queueing
        // Just reload from DB (optimistic message type was set to 5 by repository)
        final fresh = await repository.getMessages(
          event.threadId,
          limit: _pageSize,
          offset: 0,
          forceSync: false,
        );
        final freshDisplay = _toDisplayOrder(fresh);
        final merged = _mergeMessages(current.messages, freshDisplay);
        if (!isClosed) {
          emit(current.copyWith(messages: merged, isSending: false));
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

  Future<void> _onDeleteConversation(
    DeleteConversation event,
    Emitter<ConversationState> emit,
  ) async {
    final current = state;
    if (current is! ConversationLoaded) return;

    try {
      await repository.deleteThread(current.threadId);
      // We don't emit a new state here; UI will pop itself
    } catch (e) {
      emit(ConversationError('Failed to delete conversation: $e'));
      emit(current);
    }
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
    final newToMark = event.messageIds
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
    final merged = _mergeMessages(current.messages, freshDisplay);

    if (!isClosed) {
      emit(current.copyWith(messages: merged));
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  /// Keep DESC order (newest first) for display with reverse: true ListView.
  List<SmsMessage> _toDisplayOrder(List<SmsMessage> descList) {
    return descList;
  }

  /// Merges a fresh page of newest messages with the currently loaded older messages.
  /// Returns DESC order (newest first) for reverse:true ListView.
  List<SmsMessage> _mergeMessages(
    List<SmsMessage> currentList,
    List<SmsMessage> freshNewestList,
  ) {
    final freshIds = freshNewestList.map((m) => m.id).toSet();
    final olderKeep = currentList
        .where((m) => !freshIds.contains(m.id))
        .toList();
    // DESC: fresh (newer) first, then older kept at end
    return [...freshNewestList, ...olderKeep];
  }

  // ── Database System Changes ────────────────────────────────────────────

  void _onSelectSim(SelectSim event, Emitter<ConversationState> emit) {
    final current = state;
    if (current is ConversationLoaded) {
      emit(current.copyWith(selectedSimId: event.simId));
    }
  }

  Future<void> _onSystemMessagesChanged(
    SystemMessagesChanged event,
    Emitter<ConversationState> emit,
  ) async {
    final current = state;
    if (current is! ConversationLoaded) return;

    // Debounce rapid system changes
    final now = DateTime.now();
    if (_lastSystemChange != null &&
        now.difference(_lastSystemChange!).inMilliseconds < 500) {
      return;
    }
    _lastSystemChange = now;

    try {
      // Small delay to allow any local SQLite writes to settle, although NativeSmsService
      // systemSmsChanges actually fires from Android content observer.
      await Future.delayed(const Duration(milliseconds: 300));

      // Fetch latest messages from Native to get external changes
      final fresh = await repository.getMessages(
        current.threadId,
        limit: _pageSize,
        offset: 0,
        forceSync: true,
      );
      final freshDisplay = _toDisplayOrder(fresh);

      // We only merge the first page so we don't overwrite older loaded messages.
      // If the user scrolled deep and an old message was deleted by another app,
      // they might still see it until they refresh, but that's a rare edge case.
      final merged = _mergeMessages(current.messages, freshDisplay);

      if (!isClosed) {
        emit(current.copyWith(messages: merged));
      }
    } catch (_) {}
  }

  @override
  Future<void> close() {
    _systemChangesSubscription?.cancel();
    _incomingSubscription?.cancel();
    return super.close();
  }
}
