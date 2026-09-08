import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sms_manager/src/data/local/database_helper.dart';
import 'package:sms_manager/src/data/models/sms_thread.dart';
import 'package:sms_manager/src/services/smart_search_service.dart';

import 'search_event.dart';
import 'search_state.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  SearchBloc() : super(SearchInitial()) {
    on<PerformSearch>(_onPerformSearch);
    on<ClearSearch>((_, emit) => emit(SearchInitial()));
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
      final messages = await SmartSearchService.instance.search(
        event.query,
        event.filters,
      );

      final db = DatabaseHelper.instance;
      final enriched = <SearchResultItem>[];

      for (final msg in messages) {
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

        enriched.add(
          SearchResultItem(
            msg,
            thread,
            highlights: _computeHighlights(msg.body, event.query),
          ),
        );
      }

      emit(SearchSuccess(enriched, query: event.query));
    } catch (e) {
      emit(SearchFailure(e.toString()));
    }
  }

  /// Returns a list of [start, end) character offset pairs within [body]
  /// where any of the meaningful query tokens appear (case-insensitive).
  static List<(int, int)> _computeHighlights(String body, String rawQuery) {
    final bodyLower = body.toLowerCase();
    final spans = <(int, int)>[];

    // Extract meaningful tokens (skip stop-words and very short tokens)
    const stopWords = {
      'is',
      'in',
      'at',
      'on',
      'to',
      'by',
      'an',
      'of',
      'for',
      'the',
      'a',
      'from',
      'not',
      'or',
      'and',
    };
    final tokens = rawQuery
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 1 && !stopWords.contains(t))
        // Strip FTS wildcards / quotes
        .map((t) => t.replaceAll(RegExp(r'[*"]+'), ''))
        .where((t) => t.isNotEmpty)
        .toSet();

    for (final token in tokens) {
      int start = 0;
      while (true) {
        final idx = bodyLower.indexOf(token, start);
        if (idx == -1) break;
        spans.add((idx, idx + token.length));
        start = idx + token.length;
      }
    }

    // Sort and merge overlapping spans
    spans.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final span in spans) {
      if (merged.isEmpty || span.$1 > merged.last.$2) {
        merged.add(span);
      } else if (span.$2 > merged.last.$2) {
        merged[merged.length - 1] = (merged.last.$1, span.$2);
      }
    }
    return merged;
  }
}
