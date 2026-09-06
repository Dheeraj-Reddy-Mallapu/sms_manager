import 'package:equatable/equatable.dart';
import 'package:sms_manager/src/data/models/sms_message.dart';

import 'package:sms_manager/src/data/models/sms_thread.dart';

class SearchResultItem {
  final SmsMessage message;
  final SmsThread thread;
  SearchResultItem(this.message, this.thread);
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

  const SearchSuccess(this.results);

  @override
  List<Object?> get props => [results];
}

class SearchFailure extends SearchState {
  final String message;

  const SearchFailure(this.message);

  @override
  List<Object?> get props => [message];
}
