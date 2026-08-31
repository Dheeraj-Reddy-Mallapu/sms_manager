import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sms_manager/src/data/models/sms_thread.dart';
import 'package:sms_manager/src/features/home/presentation/bloc/home_bloc.dart';
import 'package:sms_manager/src/core/widgets/timeline_scrollbar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  @override
  void initState() {
    super.initState();
    // Load from cache first (fast), then background-refresh from native
    context.read<HomeBloc>().add(const LoadThreads(forceSync: false));
  }

  Future<void> _onRefresh() async {
    if (!mounted) return;
    final bloc = context.read<HomeBloc>();
    bloc.add(const LoadThreads(forceSync: true));
    // Wait until background refresh completes
    await Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return false;
      final s = bloc.state;
      return s is HomeLoading || (s is HomeLoaded && s.isRefreshing);
    });
  }

  /// Returns a time-aware greeting
  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: BlocBuilder<HomeBloc, HomeState>(
          builder: (context, state) {
            if (state is HomeInitial || state is HomeLoading) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is HomeError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        state.message,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colorScheme.error),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => context.read<HomeBloc>().add(
                          const LoadThreads(forceSync: true),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            } else if (state is HomeLoaded) {
              return RefreshIndicator(
                onRefresh: _onRefresh,
                child: _buildHomeContent(context, state, colorScheme),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/home/compose'),
        backgroundColor: colorScheme.primaryContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Icon(Icons.edit_outlined, color: colorScheme.onPrimaryContainer),
      ),
    );
  }

  Widget _buildHomeContent(
    BuildContext context,
    HomeLoaded state,
    ColorScheme colorScheme,
  ) {
    // Filter threads based on active category
    final filteredThreads = _filterThreads(state.threads, state.activeCategory);
    final unreadCount = state.threads.where((t) => !t.read).length;

    return TimelineScrollbar(
      controller: _scrollController,
      labelForFraction: (fraction) {
        if (filteredThreads.isEmpty) return '';
        final idx = (fraction * filteredThreads.length)
            .floor()
            .clamp(0, filteredThreads.length - 1);
        return timelineLabel(filteredThreads[idx].date);
      },
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // App bar row
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting(),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              unreadCount > 0
                                  ? 'You have $unreadCount unread message${unreadCount == 1 ? '' : 's'}'
                                  : 'All messages read',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            if (state.isRefreshing) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () {},
                    tooltip: 'Search',
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () {},
                    tooltip: 'More',
                  ),
                ],
              ),
            ),
          ),

          // Category chips
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverToBoxAdapter(
              child: _buildCategoryChips(context, state, colorScheme),
            ),
          ),

          // Thread list
          filteredThreads.isEmpty
              ? SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inbox,
                          size: 64,
                          color: colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No messages',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 80),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildThreadTile(
                        context,
                        filteredThreads[index],
                        colorScheme,
                      ),
                      childCount: filteredThreads.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  List<SmsThread> _filterThreads(List<SmsThread> threads, String category) {
    switch (category) {
      case 'Unread':
        return threads.where((t) => !t.read).toList();
      case 'Personal':
        return threads.where((t) => t.contactName != null).toList();
      case 'Transactions':
        return threads.where((t) => t.category == 'Transactions').toList();
      default:
        return threads;
    }
  }

  Widget _buildCategoryChips(
    BuildContext context,
    HomeLoaded state,
    ColorScheme colorScheme,
  ) {
    final categories = ['All', 'Unread', 'Personal', 'Transactions'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories.map((category) {
          final isSelected = state.activeCategory == category;
          final unreadForChip = category == 'Unread'
              ? state.threads.where((t) => !t.read).length
              : 0;

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilterChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(category),
                  if (category == 'Unread' && unreadForChip > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colorScheme.onPrimary.withAlpha(204)
                            : colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        unreadForChip > 999 ? '999+' : unreadForChip.toString(),
                        style: TextStyle(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              selected: isSelected,
              onSelected: (_) =>
                  context.read<HomeBloc>().add(ChangeCategoryFilter(category)),
              backgroundColor: colorScheme.surfaceContainerHighest,
              selectedColor: colorScheme.primary,
              labelStyle: TextStyle(
                color: isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Colors.transparent),
              ),
              showCheckmark: false,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildThreadTile(
    BuildContext context,
    SmsThread thread,
    ColorScheme colorScheme,
  ) {
    final displayName = thread.contactName?.isNotEmpty == true
        ? thread.contactName!
        : thread.address.isNotEmpty
        ? thread.address
        : 'Unknown';

    final isUnread = !thread.read;
    final timeString = _formatDate(thread.date);

    return InkWell(
      onTap: () => context.go('/home/conversation/${thread.id}', extra: thread),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: isUnread
              ? colorScheme.primaryContainer.withAlpha(60)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildAvatar(thread, displayName, colorScheme),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: isUnread
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeString,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isUnread
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                          fontWeight: isUnread
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          thread.snippet.isNotEmpty
                              ? thread.snippet
                              : '(No message content)',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: isUnread
                                    ? colorScheme.onSurface
                                    : colorScheme.onSurfaceVariant,
                                fontWeight: isUnread
                                    ? FontWeight.w500
                                    : FontWeight.normal,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Smart avatar: real photo > colored initial from contact name/number
  Widget _buildAvatar(
    SmsThread thread,
    String displayName,
    ColorScheme colorScheme,
  ) {
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    // Generate a consistent color from the display name (for non-contact senders)
    final avatarColor = _colorFromString(displayName, colorScheme);

    if (thread.contactPhotoUri != null && thread.contactPhotoUri!.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: avatarColor,
        child: ClipOval(
          child: Image.network(
            thread.contactPhotoUri!,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (context, error, _) => Text(
              initial,
              style: TextStyle(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 24,
      backgroundColor: avatarColor,
      child: Text(
        initial,
        style: TextStyle(
          color: _onColor(avatarColor),
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }

  /// Generates a consistent, visually pleasing color from any string (name/number)
  Color _colorFromString(String input, ColorScheme colorScheme) {
    // A curated set of Material-ish colors that work on both light/dark
    const colors = [
      Color(0xFF6750A4), // purple
      Color(0xFF0288D1), // blue
      Color(0xFF00897B), // teal
      Color(0xFFC62828), // red
      Color(0xFFE65100), // orange
      Color(0xFF558B2F), // green
      Color(0xFF6A1B9A), // deep purple
      Color(0xFF00838F), // cyan
      Color(0xFF4527A0), // indigo
      Color(0xFFAD1457), // pink
    ];
    final hash = input.codeUnits.fold(0, (prev, c) => prev + c);
    return colors[hash % colors.length];
  }

  Color _onColor(Color bg) {
    // Simple luminance check
    final luminance = bg.computeLuminance();
    return luminance > 0.4 ? Colors.black : Colors.white;
  }

  String _formatDate(int timestampMs) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(dateDay).inDays;

    if (diff == 0) return DateFormat.jm().format(date); // 10:38 AM
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(date); // Tuesday
    if (date.year == now.year) {
      return DateFormat('MMM d').format(date); // Aug 24
    }
    return DateFormat('MM/dd/yy').format(date); // 08/24/23
  }
}
