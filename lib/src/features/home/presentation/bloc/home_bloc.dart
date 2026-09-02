import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:sms_manager/src/data/models/sms_thread.dart';
import 'package:sms_manager/src/data/repositories/sms_repository.dart';

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

  const HomeLoaded({
    required this.threads,
    this.activeCategory = 'All',
    this.isRefreshing = false,
  });

  HomeLoaded copyWith({
    List<SmsThread>? threads,
    String? activeCategory,
    bool? isRefreshing,
  }) => HomeLoaded(
        threads:        threads        ?? this.threads,
        activeCategory: activeCategory ?? this.activeCategory,
        isRefreshing:   isRefreshing   ?? this.isRefreshing,
      );

  @override
  List<Object?> get props => [threads, activeCategory, isRefreshing];
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
    // When the system DB changes (e.g. after sending an SMS), we only need 
    // to sync the most recent threads to be fast.
    add(const LoadThreads(forceSync: true, syncLimit: 20));
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
      // Load all from SQLite (fast local cache)
      final cached = await repository.getThreads(
        limit: 10000,
        forceSync: false,
      );

      final category = current is HomeLoaded ? current.activeCategory : 'All';
      emit(HomeLoaded(threads: cached, activeCategory: category, isRefreshing: false));

      if (event.forceSync) {
        // Fast delta sync when an SMS is sent/received
        await repository.backgroundRefresh(limit: event.syncLimit ?? 50);
        final allThreads = await repository.getThreads(limit: 10000, forceSync: false);
        add(BackgroundRefreshCompleted(allThreads));
      } else {
        // Normal app launch: do a paginated sync to catch up or fill DB seamlessly
        // We sync up to 10000, but in chunks of 50. This way the user sees the first 50
        // almost instantly on first install, and the rest fill in seamlessly.
        // (For a production app you might only paginate fully if cache is empty, 
        // and just do a small sync if cache is full, but we will paginate fully here)
        final stream = repository.syncThreadsPaginated(maxLimit: 10000, chunkSize: 50);
        await for (final updatedThreads in stream) {
          if (isClosed) break;
          // Emit each chunk as it arrives
          add(BackgroundRefreshCompleted(updatedThreads));
          
          // Optimization: if cache was already full, maybe we only need one chunk to catch up
          if (cached.isNotEmpty && updatedThreads.length == cached.length) {
            // We could break early here if we implemented a proper SyncManager, 
            // but we'll let it paginate.
          }
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
    emit(HomeLoaded(
      threads:        event.threads,
      activeCategory: category,
      isRefreshing:   false,
    ));
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
      final updated = await repository.getThreads(limit: 10000, forceSync: false);
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

  @override
  Future<void> close() {
    _incomingSubscription?.cancel();
    _systemChangesSubscription?.cancel();
    return super.close();
  }
}
