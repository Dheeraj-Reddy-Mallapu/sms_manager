import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:sms_manager/src/data/models/sms_thread.dart';
import 'package:sms_manager/src/data/repositories/sms_repository.dart';
import 'package:sms_manager/src/services/native_sms_service.dart';

// ── Events ───────────────────────────────────────────────────────────────────

abstract class HomeEvent extends Equatable {
  const HomeEvent();
  @override
  List<Object?> get props => [];
}

class LoadThreads extends HomeEvent {
  final bool forceSync;
  final int? syncLimit;
  const LoadThreads({this.forceSync = false, this.syncLimit});
  @override
  List<Object?> get props => [forceSync, syncLimit];
}

class BackgroundRefreshCompleted extends HomeEvent {
  final List<SmsThread> threads;
  const BackgroundRefreshCompleted(this.threads);
  @override
  List<Object?> get props => [threads];
}

class ChangeCategoryFilter extends HomeEvent {
  final String category;
  const ChangeCategoryFilter(this.category);
  @override
  List<Object?> get props => [category];
}

class IncomingSmsReceived extends HomeEvent {
  final Map<String, dynamic> data;
  const IncomingSmsReceived(this.data);
  @override
  List<Object?> get props => [data];
}

/// Lightweight refresh from SQLite cache only — no native call.
/// Dispatched e.g. when returning from ConversationPage (to pick up read state).
class RefreshReadState extends HomeEvent {
  const RefreshReadState();
}

class ToggleSelectionMode extends HomeEvent {
  final bool active;
  const ToggleSelectionMode(this.active);
  @override
  List<Object?> get props => [active];
}

class ToggleThreadSelection extends HomeEvent {
  final int threadId;
  const ToggleThreadSelection(this.threadId);
  @override
  List<Object?> get props => [threadId];
}

class ClearHomeSelection extends HomeEvent {
  const ClearHomeSelection();
}

class DeleteSelectedThreads extends HomeEvent {
  const DeleteSelectedThreads();
}

class MarkSelectedAsRead extends HomeEvent {
  const MarkSelectedAsRead();
}

class MarkAllAsRead extends HomeEvent {
  const MarkAllAsRead();
}

// ── States ───────────────────────────────────────────────────────────────────

abstract class HomeState extends Equatable {
  const HomeState();
  @override
  List<Object?> get props => [];
}

class HomeInitial extends HomeState {}

class HomeLoading extends HomeState {}

class HomeLoaded extends HomeState {
  final List<SmsThread> threads;
  final String activeCategory;
  final bool isRefreshing; // subtle spinner — keeps threads visible

  final bool isSelectionMode;
  final Set<int> selectedThreadIds;

  const HomeLoaded({
    required this.threads,
    this.activeCategory = 'All',
    this.isRefreshing = false,
    this.isSelectionMode = false,
    this.selectedThreadIds = const {},
  });

  HomeLoaded copyWith({
    List<SmsThread>? threads,
    String? activeCategory,
    bool? isRefreshing,
    bool? isSelectionMode,
    Set<int>? selectedThreadIds,
  }) => HomeLoaded(
    threads: threads ?? this.threads,
    activeCategory: activeCategory ?? this.activeCategory,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isSelectionMode: isSelectionMode ?? this.isSelectionMode,
    selectedThreadIds: selectedThreadIds ?? this.selectedThreadIds,
  );

  @override
  List<Object?> get props => [
    threads,
    activeCategory,
    isRefreshing,
    isSelectionMode,
    selectedThreadIds,
  ];
}

class HomeError extends HomeState {
  final String message;
  const HomeError(this.message);
  @override
  List<Object?> get props => [message];
}

class SystemSmsChanged extends HomeEvent {
  const SystemSmsChanged();
}

// ── BLoC ─────────────────────────────────────────────────────────────────────

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final SmsRepository repository;
  StreamSubscription<Map<String, dynamic>>? _incomingSubscription;
  StreamSubscription<void>? _systemChangesSubscription;
  DateTime? _lastSystemChange;

  HomeBloc({required this.repository}) : super(HomeInitial()) {
    on<LoadThreads>(_onLoadThreads);
    on<BackgroundRefreshCompleted>(_onBackgroundRefreshCompleted);
    on<ChangeCategoryFilter>(_onChangeCategory);
    on<IncomingSmsReceived>(_onIncomingSms);
    on<RefreshReadState>(_onRefreshReadState);
    on<SystemSmsChanged>(_onSystemSmsChanged);
    on<ToggleSelectionMode>(_onToggleSelectionMode);
    on<ToggleThreadSelection>(_onToggleThreadSelection);
    on<ClearHomeSelection>(_onClearHomeSelection);
    on<DeleteSelectedThreads>(_onDeleteSelectedThreads);
    on<MarkSelectedAsRead>(_onMarkSelectedAsRead);
    on<MarkAllAsRead>(_onMarkAllAsRead);

    _incomingSubscription = repository.incomingSmsStream.listen(
      (data) => add(IncomingSmsReceived(data)),
      onError: (_) {},
    );

    _systemChangesSubscription = repository.systemSmsChanges.listen(
      (_) => add(const SystemSmsChanged()),
      onError: (_) {},
    );
  }

  Future<void> _onSystemSmsChanged(
    SystemSmsChanged event,
    Emitter<HomeState> emit,
  ) async {
    // Basic throttle since Kotlin already debounces, just to be safe
    final now = DateTime.now();
    if (_lastSystemChange != null &&
        now.difference(_lastSystemChange!).inMilliseconds < 400) {
      return;
    }
    _lastSystemChange = now;
    // System DB changed (e.g., incoming SMS or deleted externally).
    // Do a quick smart sync to catch new messages, then reload UI.
    await repository.smartSync(maxLimit: 1000, chunkSize: 50);
    final cached = await repository.getThreads(limit: 10000, forceSync: false);
    add(BackgroundRefreshCompleted(cached));
  }

  Future<void> _onLoadThreads(
    LoadThreads event,
    Emitter<HomeState> emit,
  ) async {
    final current = state;

    // ── Only show full-screen spinner on the very first load ──────────────
    if (current is! HomeLoaded) {
      emit(HomeLoading());
    } else {
      // Keep existing threads visible; show subtle refresh indicator
      emit(current.copyWith(isRefreshing: true));
    }

    try {
      // 1. Instantly load all from SQLite (fast local cache)
      final cached = await repository.getThreads(
        limit: 10000,
        forceSync: false,
      );

      final category = current is HomeLoaded ? current.activeCategory : 'All';
      emit(
        HomeLoaded(
          threads: cached,
          activeCategory: category,
          isRefreshing: false,
        ),
      );

      if (event.forceSync) {
        // Fast smart sync for manual refreshes
        await repository.smartSync();
        final allThreads = await repository.getThreads(
          limit: 10000,
          forceSync: false,
        );
        add(BackgroundRefreshCompleted(allThreads));
      } else {
        // Normal app launch: do smart paginated sync
        final stream = repository.syncThreadsPaginated(
          maxLimit: 10000,
          chunkSize: 50,
        );
        await for (final updatedThreads in stream) {
          if (isClosed) break;
          add(BackgroundRefreshCompleted(updatedThreads));
        }
      }
    } catch (e) {
      if (current is HomeLoaded) {
        emit(current.copyWith(isRefreshing: false));
      } else {
        emit(HomeError('Failed to load messages: $e'));
      }
    }
  }

  void _onBackgroundRefreshCompleted(
    BackgroundRefreshCompleted event,
    Emitter<HomeState> emit,
  ) {
    final current = state;
    final category = current is HomeLoaded ? current.activeCategory : 'All';
    
    // Push top 4 threads to native for dynamic shortcuts / Direct Share
    final topThreads = event.threads.take(4).map((t) => {
      'threadId': t.id,
      'address': t.address,
      'contactName': t.contactName ?? t.address,
    }).toList();
    NativeSmsService.pushShortcuts(topThreads);

    emit(
      HomeLoaded(
        threads: event.threads,
        activeCategory: category,
        isRefreshing: false,
      ),
    );
  }

  /// Fast SQLite-only refresh — no native call, near-instant.
  Future<void> _onRefreshReadState(
    RefreshReadState event,
    Emitter<HomeState> emit,
  ) async {
    final current = state;
    if (current is! HomeLoaded) return;
    try {
      // Small delay to allow ConversationBloc's async DB write to complete
      await Future.delayed(const Duration(milliseconds: 150));
      final updated = await repository.getThreads(
        limit: 10000,
        forceSync: false,
      );
      emit(current.copyWith(threads: updated, isRefreshing: false));
    } catch (_) {}
  }

  Future<void> _onIncomingSms(
    IncomingSmsReceived event,
    Emitter<HomeState> emit,
  ) async {
    await repository.upsertThreadFromIncomingSms(event.data);
    final threads = await repository.getThreads(limit: 10000);
    final current = state;
    final category = current is HomeLoaded ? current.activeCategory : 'All';
    emit(HomeLoaded(threads: threads, activeCategory: category));
  }

  void _onChangeCategory(ChangeCategoryFilter event, Emitter<HomeState> emit) {
    final current = state;
    if (current is HomeLoaded) {
      emit(current.copyWith(activeCategory: event.category));
    }
  }

  void _onToggleSelectionMode(
    ToggleSelectionMode event,
    Emitter<HomeState> emit,
  ) {
    final current = state;
    if (current is! HomeLoaded) return;
    emit(
      current.copyWith(
        isSelectionMode: event.active,
        selectedThreadIds: event.active ? current.selectedThreadIds : const {},
      ),
    );
  }

  void _onToggleThreadSelection(
    ToggleThreadSelection event,
    Emitter<HomeState> emit,
  ) {
    final current = state;
    if (current is! HomeLoaded) return;
    final ids = Set<int>.from(current.selectedThreadIds);
    if (ids.contains(event.threadId)) {
      ids.remove(event.threadId);
    } else {
      ids.add(event.threadId);
    }
    emit(
      current.copyWith(
        selectedThreadIds: ids,
        isSelectionMode: ids.isNotEmpty || current.isSelectionMode,
      ),
    );
  }

  void _onClearHomeSelection(
    ClearHomeSelection event,
    Emitter<HomeState> emit,
  ) {
    final current = state;
    if (current is! HomeLoaded) return;
    emit(current.copyWith(isSelectionMode: false, selectedThreadIds: const {}));
  }

  Future<void> _onDeleteSelectedThreads(
    DeleteSelectedThreads event,
    Emitter<HomeState> emit,
  ) async {
    final current = state;
    if (current is! HomeLoaded) return;

    emit(current.copyWith(isRefreshing: true));
    try {
      for (final threadId in current.selectedThreadIds) {
        await repository.deleteThread(threadId);
      }

      final updated = current.threads
          .where((t) => !current.selectedThreadIds.contains(t.id))
          .toList();
      emit(
        current.copyWith(
          threads: updated,
          isSelectionMode: false,
          selectedThreadIds: const {},
          isRefreshing: false,
        ),
      );
    } catch (e) {
      emit(current.copyWith(isRefreshing: false));
      emit(HomeError('Failed to delete threads: $e'));
      emit(current);
    }
  }

  Future<void> _onMarkSelectedAsRead(
    MarkSelectedAsRead event,
    Emitter<HomeState> emit,
  ) async {
    final current = state;
    if (current is! HomeLoaded) return;

    emit(current.copyWith(isRefreshing: true));
    try {
      for (final threadId in current.selectedThreadIds) {
        await repository.markThreadAsRead(threadId);
      }
      // Re-fetch threads from sqlite
      final threads = await repository.getThreads(
        limit: 10000,
        forceSync: false,
      );
      emit(
        current.copyWith(
          threads: threads,
          isSelectionMode: false,
          selectedThreadIds: const {},
          isRefreshing: false,
        ),
      );
    } catch (e) {
      emit(current.copyWith(isRefreshing: false));
      emit(HomeError('Failed to mark as read: $e'));
      emit(current);
    }
  }

  Future<void> _onMarkAllAsRead(
    MarkAllAsRead event,
    Emitter<HomeState> emit,
  ) async {
    final current = state;
    if (current is! HomeLoaded) return;

    emit(current.copyWith(isRefreshing: true));
    try {
      // Actually we need a repository method for this!
      // For now, let's call repository.markAllAsRead()
      await repository.markAllAsRead();
      final threads = await repository.getThreads(
        limit: 10000,
        forceSync: false,
      );
      emit(current.copyWith(threads: threads, isRefreshing: false));
    } catch (e) {
      emit(current.copyWith(isRefreshing: false));
      emit(HomeError('Failed to mark all as read: $e'));
      emit(current);
    }
  }

  @override
  Future<void> close() {
    _incomingSubscription?.cancel();
    _systemChangesSubscription?.cancel();
    return super.close();
  }
}
