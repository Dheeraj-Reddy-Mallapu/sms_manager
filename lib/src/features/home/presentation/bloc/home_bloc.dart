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
  const LoadThreads({this.forceSync = false});
  @override
  List<Object?> get props => [forceSync];
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

// ── BLoC ─────────────────────────────────────────────────────────────────────

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final SmsRepository repository;
  StreamSubscription<Map<String, dynamic>>? _incomingSubscription;

  HomeBloc({required this.repository}) : super(HomeInitial()) {
    on<LoadThreads>(_onLoadThreads);
    on<BackgroundRefreshCompleted>(_onBackgroundRefreshCompleted);
    on<ChangeCategoryFilter>(_onChangeCategory);
    on<IncomingSmsReceived>(_onIncomingSms);
    on<RefreshReadState>(_onRefreshReadState);

    _incomingSubscription = repository.incomingSmsStream.listen(
      (data) => add(IncomingSmsReceived(data)),
      onError: (_) {},
    );
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
      // Fast path: SQLite cache (forceSync = false returns cache immediately)
      final cached = await repository.getThreads(
        limit: 10000,
        forceSync: event.forceSync,
      );

      final category = current is HomeLoaded ? current.activeCategory : 'All';
      emit(HomeLoaded(threads: cached, activeCategory: category, isRefreshing: true));

      // Background-refresh from native (always runs to pick up new messages)
      final fresh = await repository.backgroundRefresh(limit: 10000);
      add(BackgroundRefreshCompleted(fresh));
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
    return super.close();
  }
}
