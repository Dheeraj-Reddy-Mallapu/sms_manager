import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:sms_manager/src/core/widgets/smart_avatar.dart';
import 'package:sms_manager/src/features/search/presentation/bloc/search_bloc.dart';
import 'package:sms_manager/src/features/search/presentation/bloc/search_event.dart';
import 'package:sms_manager/src/features/search/presentation/bloc/search_state.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final List<String> _selectedFilters = [];
  Timer? _debounce;

  String _sortBy = 'Relevance'; // or 'Date'

  final List<String> _filters = [
    'Has Link',
    'Has Date',
    'Has Number',
    'Unread',
    'Starred',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _submitSearch(_searchController.text);
    });
  }

  void _submitSearch(String query) {
    if (query.trim().isNotEmpty) {
      context.read<SearchBloc>().add(
        PerformSearch(query.trim(), filters: List.from(_selectedFilters)),
      );
    } else {
      context.read<SearchBloc>().add(ClearSearch());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(context, colorScheme),
            _buildFiltersAndSort(colorScheme),
            Expanded(
              child: BlocBuilder<SearchBloc, SearchState>(
                builder: (context, state) {
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _buildBodyContent(state, colorScheme, textTheme),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: colorScheme.onSurfaceVariant),
            onPressed: () => context.pop(),
          ),
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: TextStyle(color: colorScheme.onSurface, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Search with Hybrid AI...',
                hintStyle: TextStyle(
                  color: colorScheme.onSurfaceVariant.withAlpha(150),
                ),
                border: InputBorder.none,
                isDense: true,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: _submitSearch,
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchController,
            builder: (context, value, child) {
              if (value.text.isNotEmpty) {
                return IconButton(
                  icon: Icon(Icons.close, color: colorScheme.onSurfaceVariant),
                  onPressed: () {
                    _searchController.clear();
                    _submitSearch('');
                  },
                );
              }
              return const SizedBox(width: 48); // placeholder for symmetry
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersAndSort(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          children: [
            // Sort Dropdown
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(16),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _sortBy,
                  icon: Icon(
                    Icons.sort,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Relevance',
                      child: Text('Relevance'),
                    ),
                    DropdownMenuItem(value: 'Date', child: Text('Date')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _sortBy = val);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(width: 1, height: 20, color: colorScheme.outlineVariant),
            const SizedBox(width: 12),
            // Chips
            ..._filters.map((filter) {
              final isSelected = _selectedFilters.contains(filter);
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilterChip(
                  label: Text(filter, style: const TextStyle(fontSize: 13)),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedFilters.add(filter);
                      } else {
                        _selectedFilters.remove(filter);
                      }
                    });
                    _submitSearch(_searchController.text);
                  },
                  backgroundColor: colorScheme.surface,
                  selectedColor: colorScheme.primaryContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.outlineVariant,
                    ),
                  ),
                  showCheckmark: false,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyContent(
    SearchState state,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    if (state is SearchInitial) {
      return _buildEmptyState(
        icon: Icons.auto_awesome,
        message: 'Search smarter.',
        submessage:
            'Find messages instantly using keywords or semantic AI matching.',
        colorScheme: colorScheme,
      );
    } else if (state is SearchLoading) {
      return _buildSkeletonLoader(colorScheme);
    } else if (state is SearchFailure) {
      return _buildEmptyState(
        icon: Icons.error_outline,
        message: 'Something went wrong.',
        submessage: state.message,
        colorScheme: colorScheme,
      );
    } else if (state is SearchSuccess) {
      var results = state.results;
      if (results.isEmpty) {
        return _buildEmptyState(
          icon: Icons.search_off,
          message: 'No results found',
          submessage: 'Try adjusting your search query or filters.',
          colorScheme: colorScheme,
        );
      }

      if (_sortBy == 'Date') {
        results = List.from(results)
          ..sort((a, b) => b.message.date.compareTo(a.message.date));
      }

      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: results.length,
        itemBuilder: (context, index) {
          final item = results[index];
          final msg = item.message;
          final thread = item.thread;

          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            color: colorScheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colorScheme.surfaceContainerHighest),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                context.push(
                  '/home/conversation/${msg.threadId}?messageId=${msg.id}',
                  extra: thread,
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SmartAvatar(thread: thread, radius: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  thread.contactName ?? msg.address,
                                  style: textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatDate(msg.date),
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            msg.body,
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
    return const SizedBox();
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
    required String submessage,
    required ColorScheme colorScheme,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: colorScheme.primaryContainer),
            const SizedBox(height: 24),
            Text(
              message,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              submessage,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonLoader(ColorScheme colorScheme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Searching your messages...',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: 6,
            itemBuilder: (context, index) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.surfaceContainerHighest,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 120,
                            height: 16,
                            color: colorScheme.surfaceContainerHighest,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            height: 14,
                            color: colorScheme.surfaceContainerHighest,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 200,
                            height: 14,
                            color: colorScheme.surfaceContainerHighest,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatDate(int timestampMs) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final now = DateTime.now();
    final diff = now.difference(date).inDays;

    if (diff == 0) {
      return '${date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour)}:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';
    } else if (diff < 7) {
      return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][date.weekday -
          1];
    } else {
      return '${date.month}/${date.day}/${date.year.toString().substring(2)}';
    }
  }
}
