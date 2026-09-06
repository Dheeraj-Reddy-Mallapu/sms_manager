import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sms_manager/src/data/local/database_helper.dart';
import 'package:sms_manager/src/data/models/sms_thread.dart';
import 'package:sms_manager/src/services/ai_indexing_service.dart';

import 'search_event.dart';
import 'search_state.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  SearchBloc() : super(SearchInitial()) {
    on<PerformSearch>(_onPerformSearch);
    on<ClearSearch>((event, emit) => emit(SearchInitial()));
  }

  Future<void> _onPerformSearch(
    PerformSearch event,
    Emitter<SearchState> emit,
  ) async {
    if (event.query.trim().isEmpty) {
      emit(SearchInitial());
      return;
    }

    emit(SearchLoading());
    try {
      final results = await AiIndexingService.instance.search(
        event.query,
        event.filters,
      );

      final db = DatabaseHelper.instance;
      final enrichedResults = <SearchResultItem>[];
      for (final msg in results) {
        final thread =
            await db.getThreadById(msg.threadId) ??
            SmsThread(
              id: msg.threadId,
              address: msg.address,
              snippet: msg.body,
              date: msg.date,
              read: msg.read,
              unreadCount: 0,
              messageCount: 1,
              recipientIds: '',
            );
        enrichedResults.add(SearchResultItem(msg, thread));
      }
      emit(SearchSuccess(enrichedResults));
    } catch (e) {
      emit(SearchFailure(e.toString()));
    }
  }
}
