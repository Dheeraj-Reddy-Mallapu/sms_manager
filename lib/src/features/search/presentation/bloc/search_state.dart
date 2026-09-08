import 'package:equatable/equatable.dart';
import 'package:sms_manager/src/data/models/sms_message.dart';
import 'package:sms_manager/src/data/models/sms_thread.dart';

/// A single search result — message + its parent thread + pre-computed
/// highlight spans so the UI can bold matching terms without extra work.
class SearchResultItem {
  final SmsMessage message;
  final SmsThread thread;

  /// Byte offsets [start, end) within [message.body] that matched the query.
  /// Empty when no highlighting is available.
  final List<(int, int)> highlights;

  const SearchResultItem(
    this.message,
    this.thread, {
    this.highlights = const [],
  });
}

abstract class SearchState extends Equatable {
  const SearchState();

  @override
  List<Object?> get props => [];
}

class SearchInitial extends SearchState {}

class SearchLoading extends SearchState {}

class SearchSuccess extends SearchState {
  final List<SearchResultItem> results;
  final String query; // kept so UI can rebuild highlights if needed

  const SearchSuccess(this.results, {this.query = ''});

  @override
  List<Object?> get props => [results, query];
}

class SearchFailure extends SearchState {
  final String message;

  const SearchFailure(this.message);

  @override
  List<Object?> get props => [message];
}
