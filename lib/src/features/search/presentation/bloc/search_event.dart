import 'package:equatable/equatable.dart';

abstract class SearchEvent extends Equatable {
  const SearchEvent();

  @override
  List<Object?> get props => [];
}

class PerformSearch extends SearchEvent {
  final String query;
  final List<String> filters;

  const PerformSearch(this.query, {this.filters = const []});

  @override
  List<Object?> get props => [query, filters];
}

class ClearSearch extends SearchEvent {}
