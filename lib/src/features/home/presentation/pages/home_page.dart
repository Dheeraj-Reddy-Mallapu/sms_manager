import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sms_manager/src/services/sms_extractor.dart';
import 'package:sms_manager/src/core/widgets/smart_avatar.dart';
import 'package:sms_manager/src/core/widgets/timeline_scrollbar.dart';
import 'package:sms_manager/src/data/models/sms_thread.dart';
import 'package:sms_manager/src/features/home/presentation/bloc/home_bloc.dart';
import 'package:sms_manager/src/core/utils/date_formatter.dart';
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
                titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
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
                    if (state.activeCategory != 'Smart ✦')
                      Text(
                        '${filteredThreads.length} conversation${filteredThreads.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.normal,
                        ),
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
          if (state.activeCategory == 'Smart ✦')
            _buildSmartView(context, state, state.threads, colorScheme)
          else if (filteredThreads.isEmpty)
            SliverFillRemaining(
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
          else
            SliverPadding(
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
    if (category == 'Smart ✦' || category == 'All') return threads;
    
    switch (category) {
      case 'Unread':
        return threads.where((t) => !t.read).toList();
      case 'Starred':
        return threads.where((t) => t.hasStarredMessages).toList();
      default:
        // Multi-label matching logic (e.g. category 'Finance' matches 'Finance,Shopping')
        return threads.where((t) => t.categoryList.contains(category)).toList();
    }
  }

  Widget _buildCategoryChips(
    BuildContext context,
    HomeLoaded state,
    ColorScheme colorScheme,
  ) {
    final categories = [
      'Smart ✦', 'All', 'Unread', 'Finance', 'OTP', 
      'Shopping', 'Travel', 'Govt & Alerts', 'Health', 'People', 'Starred'
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories.map((category) {
          final isSelected = state.activeCategory == category;

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilterChip(
              label: Text(category),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) context.read<HomeBloc>().add(ChangeCategoryFilter(category));
              },
              backgroundColor: colorScheme.surfaceContainerHighest,
              selectedColor: colorScheme.primary,
              labelStyle: TextStyle(
                color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
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

  /// The Smart View is injected natively as Slivers into the CustomScrollView
  Widget _buildSmartView(BuildContext context, HomeLoaded state, List<SmsThread> threads, ColorScheme colorScheme) {
    final now = DateTime.now();
    final fifteenMinsAgo = now.subtract(const Duration(minutes: 15));
    final startOfToday = DateTime(now.year, now.month, now.day);
    
    // HERO ZONE: Active OTPs (< 15 mins)
    final activeOtps = threads.where((t) {
      if (!t.categoryList.contains('OTP')) return false;
      final tDate = DateTime.fromMillisecondsSinceEpoch(t.date);
      return tDate.isAfter(fifteenMinsAgo);
    }).toList();

    // HERO ZONE: Urgent Alerts (Govt alerts < 24h)
    final twentyFourHoursAgo = now.subtract(const Duration(hours: 24));
    final urgentAlerts = threads.where((t) {
      if (!t.categoryList.contains('Govt & Alerts')) return false;
      final tDate = DateTime.fromMillisecondsSinceEpoch(t.date);
      return tDate.isAfter(twentyFourHoursAgo);
    }).toList();

    // DIGEST: Today's stuff
    final todaysFinance = threads.where((t) {
      if (!t.categoryList.contains('Finance')) return false;
      return DateTime.fromMillisecondsSinceEpoch(t.date).isAfter(startOfToday);
    }).toList();
    
    final todaysShopping = threads.where((t) {
      if (!t.categoryList.contains('Shopping') && !t.categoryList.contains('Travel')) return false;
      return DateTime.fromMillisecondsSinceEpoch(t.date).isAfter(startOfToday);
    }).toList();

    final unreadPeople = threads.where((t) {
      return !t.read && t.categoryList.contains('People');
    }).toList();

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          
          if (activeOtps.isNotEmpty) ...[
            Text('Right Now', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...activeOtps.map((t) => _buildHeroCard(context, t, colorScheme, isOtp: true)),
            const SizedBox(height: 16),
          ],

          if (urgentAlerts.isNotEmpty) ...[
            if (activeOtps.isEmpty)
               Text('Right Now', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...urgentAlerts.map((t) => _buildHeroCard(context, t, colorScheme, isAlert: true)),
            const SizedBox(height: 16),
          ],
          
          if (todaysFinance.isNotEmpty || todaysShopping.isNotEmpty || unreadPeople.isNotEmpty) ...[
            Text("Today's Digest", style: Theme.of(context).textTheme.titleSmall?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            
            if (unreadPeople.isNotEmpty)
              _buildDigestCard(context, state, 'Unread Personal', '${unreadPeople.length} unread messages from contacts', Icons.person, unreadPeople, colorScheme),
              
            if (todaysFinance.isNotEmpty)
              _buildDigestCard(context, state, 'Financial Updates', '${todaysFinance.length} transactions today', Icons.account_balance_wallet, todaysFinance, colorScheme),
              
            if (todaysShopping.isNotEmpty)
              _buildDigestCard(context, state, 'Orders & Travel', '${todaysShopping.length} updates today', Icons.local_shipping, todaysShopping, colorScheme),
              
            const SizedBox(height: 24),
          ],
          
          Center(
             child: Text("— You're all caught up —", style: TextStyle(color: colorScheme.onSurfaceVariant.withAlpha(128))),
          ),
          const SizedBox(height: 80),

        ]),
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context, SmsThread thread, ColorScheme colorScheme, {bool isOtp = false, bool isAlert = false}) {
    final bgColor = isAlert ? colorScheme.errorContainer : colorScheme.primaryContainer;
    final fgColor = isAlert ? colorScheme.onErrorContainer : colorScheme.onPrimaryContainer;
    
    IconData icon = Icons.notifications;
    if (isOtp) icon = Icons.password;
    if (isAlert) icon = Icons.warning;

    return Card(
      elevation: 0,
      color: bgColor,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/home/conversation/${thread.id}?targetDate=${thread.date}', extra: thread),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: fgColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      thread.contactName ?? thread.address,
                      style: TextStyle(fontWeight: FontWeight.bold, color: fgColor),
                    ),
                  ),
                  Text(DateFormatter.formatShortDate(thread.date), style: TextStyle(fontSize: 12, color: fgColor.withAlpha(200))),
                ],
              ),
              const SizedBox(height: 12),
              if (isOtp) ...[
                Builder(
                  builder: (context) {
                    final extracted = SmsExtractor.extract(thread.snippet);
                    if (extracted.otp != null) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            extracted.otp!,
                            style: TextStyle(
                              color: fgColor,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 4,
                            ),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: colorScheme.onPrimaryContainer,
                              foregroundColor: colorScheme.primaryContainer,
                            ),
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('Copy'),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: extracted.otp!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('OTP Copied!')),
                              );
                            },
                          ),
                        ],
                      );
                    }
                    return Text(
                      thread.snippet,
                      style: TextStyle(color: fgColor, fontSize: 16),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    );
                  }
                ),
              ] else ...[
                Text(
                  thread.snippet,
                  style: TextStyle(color: fgColor, fontSize: 16),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDigestCard(BuildContext context, HomeLoaded state, String title, String subtitle, IconData icon, List<SmsThread> threads, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLowest,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.surfaceContainerHighest),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.all(8.0),
          leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: colorScheme.secondaryContainer, shape: BoxShape.circle),
            child: Icon(icon, color: colorScheme.onSecondaryContainer),
          ),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface, fontSize: 16)),
          subtitle: Text(subtitle, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14)),
          children: threads.map((thread) => _buildThreadTile(context, state, thread, colorScheme, isDigest: true)).toList(),
        ),
      ),
    );
  }

  Widget _buildThreadTile(
    BuildContext context,
    HomeLoaded state,
    SmsThread thread,
    ColorScheme colorScheme, {
    bool isDigest = false,
  }) {
    final displayName = thread.contactName?.isNotEmpty == true
        ? thread.contactName!
        : thread.address.isNotEmpty
        ? thread.address
        : 'Unknown';

    final isUnread = !thread.read;
    final timeString = DateFormatter.formatShortDate(thread.date);

    final isSelected = state.selectedThreadIds.contains(thread.id);

    return InkWell(
      onLongPress: () {
        context.read<HomeBloc>().add(ToggleThreadSelection(thread.id));
      },
      onTap: () {
        if (state.isSelectionMode) {
          context.read<HomeBloc>().add(ToggleThreadSelection(thread.id));
        } else {
          context.go('/home/conversation/${thread.id}?targetDate=${thread.date}', extra: thread);
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
                        child: Builder(
                          builder: (context) {
                            final ext = SmsExtractor.extract(thread.snippet);
                            
                            if (ext.amount != null || ext.pnr != null || ext.url != null || ext.otp != null) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (ext.amount != null)
                                    Text(
                                      '${ext.transactionType == 'bill' ? '🗓️ Due' : (ext.transactionType == 'debit' ? '🔴 Debited' : '🟢 Credited')} ${ext.amount}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: isUnread ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  if (ext.otp != null)
                                    Text(
                                      '🔑 OTP: ${ext.otp}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        letterSpacing: 1.5,
                                        color: isUnread ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  const SizedBox(height: 2),
                                  Text(
                                    thread.snippet.isNotEmpty ? thread.snippet : '(No message content)',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: isUnread ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                                      fontWeight: isUnread ? FontWeight.w500 : FontWeight.normal,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (ext.pnr != null || ext.url != null) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        if (ext.url != null)
                                          ActionChip(
                                            label: const Text('🔗 Open Link', style: TextStyle(fontSize: 11)),
                                            onPressed: () {}, 
                                            padding: EdgeInsets.zero,
                                            visualDensity: VisualDensity.compact,
                                          ),
                                        if (ext.pnr != null)
                                          ActionChip(
                                            label: Text('✈️ Copy PNR: ${ext.pnr}', style: const TextStyle(fontSize: 11)),
                                            onPressed: () {
                                              Clipboard.setData(ClipboardData(text: ext.pnr!));
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PNR Copied!')));
                                            },
                                            padding: EdgeInsets.zero,
                                            visualDensity: VisualDensity.compact,
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              );
                            }

                            return Text(
                              thread.snippet.isNotEmpty ? thread.snippet : '(No message content)',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: isUnread ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                                fontWeight: isUnread ? FontWeight.w500 : FontWeight.normal,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            );
                          }
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
                onTap: () async {
                  Navigator.pop(context);
                  final info = await PackageInfo.fromPlatform();
                  if (!context.mounted) return;
                  
                  showDialog(
                    context: context,
                    builder: (context) => Dialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.asset(
                                'assets/launcher_icon.webp',
                                width: 72,
                                height: 72,
                                errorBuilder: (_, __, ___) => Icon(Icons.message_rounded, size: 72, color: Theme.of(context).colorScheme.primary),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'SMS Manager',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'v${info.version}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Made with ♥ by Dheeru',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () {
                                  launchUrl(Uri.parse('https://play.google.com/store/apps/developer?id=Dheeru'));
                                },
                                icon: const Icon(Icons.apps),
                                label: const Text('More Apps'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    showLicensePage(
                                      context: context,
                                      applicationName: 'SMS Manager',
                                      applicationVersion: info.version,
                                      applicationIcon: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Image.asset('assets/launcher_icon.webp', width: 48, height: 48),
                                      ),
                                    );
                                  },
                                  child: const Text('Licenses'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
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
