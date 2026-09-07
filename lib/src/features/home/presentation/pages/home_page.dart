import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sms_manager/src/core/widgets/smart_avatar.dart';
import 'package:sms_manager/src/core/widgets/timeline_scrollbar.dart';
import 'package:sms_manager/src/data/models/sms_thread.dart';
import 'package:sms_manager/src/features/home/presentation/bloc/home_bloc.dart';
import 'package:sms_manager/src/services/ai_indexing_service.dart';
import 'package:sms_manager/src/services/native_sms_service.dart';

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
    // AI indexing is triggered automatically once SMS fetch completes (via notifySmsFetchComplete)
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
        child: BlocConsumer<HomeBloc, HomeState>(
          listener: (context, state) {
            if (state is HomeError) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(state.message)));
            }
          },
          builder: (context, state) {
            if (state is HomeInitial || state is HomeLoading) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is HomeError) {
              // This handles the initial load error, while the listener handles transient errors
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
              return _buildHomeContent(context, state, colorScheme);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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

    return TimelineScrollbar(
      controller: _scrollController,
      labelForFraction: (fraction) {
        if (filteredThreads.isEmpty) return '';
        final idx = (fraction * filteredThreads.length).floor().clamp(
          0,
          filteredThreads.length - 1,
        );
        return timelineLabel(filteredThreads[idx].date);
      },
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Persistent App Bar (OneUI style)
          if (state.isSelectionMode)
            SliverAppBar(
              pinned: true,
              backgroundColor: colorScheme.secondaryContainer,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () =>
                    context.read<HomeBloc>().add(const ClearHomeSelection()),
              ),
              title: Text(
                '${state.selectedThreadIds.length} selected',
                style: TextStyle(color: colorScheme.onSecondaryContainer),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: state.selectedThreadIds.isEmpty
                      ? null
                      : () => _showDeleteSelectionDialog(context, state),
                ),
                IconButton(
                  icon: const Icon(Icons.mark_email_read_outlined),
                  tooltip: 'Mark as read',
                  onPressed: state.selectedThreadIds.isEmpty
                      ? null
                      : () => context.read<HomeBloc>().add(
                          const MarkSelectedAsRead(),
                        ),
                ),
                const SizedBox(width: 8),
              ],
            )
          else
            SliverAppBar(
              pinned: true,
              floating: false,
              expandedHeight: 120,
              backgroundColor: colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => context.push('/home/search'),
                  tooltip: 'Search',
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _showMoreSheet(context, colorScheme),
                  tooltip: 'More',
                ),
                const SizedBox(width: 8),
              ],
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                        fontSize: 20,
                      ),
                    ),
                    StreamBuilder<AiProgress>(
                      stream: AiIndexingService.instance.progressStream,
                      initialData: AiProgress(false, 0, 0),
                      builder: (context, snapshot) {
                        final progress = snapshot.data!;
                        final phase = progress.fetchPhase;
                        final isIndexing = progress.isIndexing;

                        // Determine what to show based on the phase
                        String label;
                        IconData icon;
                        Color color;
                        bool showSpinner;

                        if (phase == SmsFetchPhase.fetchingMessages) {
                          label = 'Loading messages...';
                          icon = Icons.downloading_rounded;
                          color = colorScheme.tertiary;
                          showSpinner = true;
                        } else if (isIndexing) {
                          final pct = progress.total > 0
                              ? ' (${progress.completed}/${progress.total})'
                              : '';
                          label = 'AI indexing$pct...';
                          icon = Icons.auto_awesome;
                          color = colorScheme.primary;
                          showSpinner = true;
                        } else if (phase == SmsFetchPhase.ready || progress.completed > 0) {
                          label = 'Local AI search ready';
                          icon = Icons.check_circle;
                          color = Colors.green;
                          showSpinner = false;
                        } else {
                          // unknown phase on subsequent launches: just show ready if we have embeddings
                          label = progress.total > 0
                              ? 'AI search ready (${progress.completed}/${progress.total})'
                              : 'Local AI search ready';
                          icon = Icons.check_circle;
                          color = Colors.green;
                          showSpinner = false;
                        }

                        return Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              showSpinner
                                  ? SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: color,
                                      ),
                                    )
                                  : Icon(icon, size: 14, color: color),
                              const SizedBox(width: 6),
                              Text(
                                label,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
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
                        state,
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
      case 'Starred':
        return threads.where((t) => t.hasStarredMessages).toList();
      default:
        return threads;
    }
  }

  Widget _buildCategoryChips(
    BuildContext context,
    HomeLoaded state,
    ColorScheme colorScheme,
  ) {
    final categories = ['All', 'Unread', 'Personal', 'Transactions', 'Starred'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories.map((category) {
          final isSelected = state.activeCategory == category;
          final badgeCount = category == 'Unread'
              ? state.threads.where((t) => !t.read).length
              : (category == 'All' ? state.threads.length : 0);

          final displayLabel = category;

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilterChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(displayLabel),
                  if (badgeCount > 0) ...[
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
                        badgeCount > 9999 ? '9999+' : badgeCount.toString(),
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
    HomeLoaded state,
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

    final isSelected = state.selectedThreadIds.contains(thread.id);

    return InkWell(
      onLongPress: () {
        context.read<HomeBloc>().add(ToggleThreadSelection(thread.id));
      },
      onTap: () {
        if (state.isSelectionMode) {
          context.read<HomeBloc>().add(ToggleThreadSelection(thread.id));
        } else {
          context.go('/home/conversation/${thread.id}', extra: thread);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () {
                if (state.isSelectionMode) {
                  context.read<HomeBloc>().add(
                    ToggleThreadSelection(thread.id),
                  );
                } else {
                  _showContactSheet(context, thread, colorScheme);
                }
              },
              child: Stack(
                children: [
                  SmartAvatar(thread: thread, radius: 24),
                  if (isSelected)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colorScheme.surface,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.check,
                          size: 14,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            thread.unreadCount > 99
                                ? '99+'
                                : thread.unreadCount.toString(),
                            style: TextStyle(
                              color: colorScheme.onPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
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

  void _showMoreSheet(BuildContext context, ColorScheme colorScheme) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.done_all_rounded),
                title: const Text('Mark all as read'),
                onTap: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Mark all as read?'),
                      content: const Text(
                        'This will mark all messages as read.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () {
                            Navigator.pop(context);
                            context.read<HomeBloc>().add(const MarkAllAsRead());
                          },
                          child: const Text('Mark Read'),
                        ),
                      ],
                    ),
                  );
                },
              ),

              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('About'),
                onTap: () {
                  Navigator.pop(context);
                  showAboutDialog(
                    context: context,
                    applicationName: 'SMS Manager',
                    applicationVersion: '1.0.0',
                    applicationIcon: const Icon(Icons.message, size: 48),
                    children: [
                      const Text(
                        'A smart SMS manager with local AI categorization.',
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteSelectionDialog(BuildContext context, HomeLoaded state) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${state.selectedThreadIds.length} conversations?'),
        content: const Text(
          'This will permanently delete the selected conversations and all their messages. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<HomeBloc>().add(const DeleteSelectedThreads());
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showContactSheet(
    BuildContext context,
    SmsThread thread,
    ColorScheme colorScheme,
  ) {
    final isContact =
        thread.contactName != null && thread.contactName!.isNotEmpty;
    final displayName = isContact ? thread.contactName! : thread.address;
    final address = thread.address;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              SmartAvatar(thread: thread, radius: 40),
              const SizedBox(height: 16),
              Text(
                displayName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              if (isContact) ...[
                const SizedBox(height: 4),
                Text(
                  address,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _actionButton(
                    context: context,
                    icon: Icons.call_outlined,
                    label: 'Call',
                    onTap: () {
                      Navigator.pop(context);
                      NativeSmsService.dialNumber(address);
                    },
                  ),
                  _actionButton(
                    context: context,
                    icon: Icons.message_outlined,
                    label: 'Message',
                    onTap: () {
                      Navigator.pop(context);
                      context.push(
                        '/home/conversation/${thread.id}',
                        extra: thread,
                      );
                    },
                  ),
                  _actionButton(
                    context: context,
                    icon: isContact
                        ? Icons.person_outline
                        : Icons.person_add_alt_1_outlined,
                    label: isContact ? 'View' : 'Add',
                    onTap: () {
                      Navigator.pop(context);
                      NativeSmsService.openContactCard(address);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _actionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colorScheme.primary, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
