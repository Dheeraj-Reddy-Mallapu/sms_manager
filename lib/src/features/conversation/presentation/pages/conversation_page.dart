import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:sms_manager/src/data/models/sms_message.dart';
import 'package:sms_manager/src/features/conversation/presentation/bloc/conversation_bloc.dart';
import 'package:sms_manager/src/features/conversation/presentation/widgets/message_bubble.dart';
import 'package:sms_manager/src/features/conversation/presentation/widgets/date_separator.dart';
import 'package:sms_manager/src/features/conversation/presentation/widgets/compose_bar.dart';
import 'package:sms_manager/src/features/conversation/presentation/widgets/message_context_menu.dart';
import 'package:sms_manager/src/features/conversation/presentation/widgets/scroll_to_bottom_fab.dart';
import 'package:sms_manager/src/features/home/presentation/bloc/home_bloc.dart';
import 'package:sms_manager/src/core/widgets/smart_avatar.dart';
import 'package:sms_manager/src/core/widgets/timeline_scrollbar.dart';
import 'package:sms_manager/src/services/native_sms_service.dart';

class ConversationPage extends StatefulWidget {
  final int threadId;
  final String? address;
  final String? contactName;
  final String? contactPhotoUri;
  final String? initialBody;
  final int? highlightMessageId;

  const ConversationPage({
    super.key,
    required this.threadId,
    this.address,
    this.contactName,
    this.contactPhotoUri,
    this.initialBody,
    this.highlightMessageId,
  });

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final _scrollController = ScrollController();
  final Map<int, GlobalKey> _messageKeys = {};
  bool _showScrollToBottom = false;
  bool _isSearching = false;
  bool _didHighlight = false;

  // For read-tracking: set of message IDs currently visible
  Timer? _readDebounce;

  @override
  void initState() {
    super.initState();
    NativeSmsService.setActiveThread(widget.threadId);
    _scrollController.addListener(_onScroll);
    final address = widget.address ?? '';
    context.read<ConversationBloc>().add(
      LoadMessages(
        widget.threadId, 
        address: address, 
        highlightMessageId: widget.highlightMessageId,
      ),
    );
    // Ensure we always start at the bottom (newest messages) after first frame.
    // reverse:true should do this automatically, but an explicit jump handles edge cases.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients &&
          widget.highlightMessageId == null) {
        _scrollController.jumpTo(0.0);
      }
    });
  }

  @override
  void dispose() {
    NativeSmsService.setActiveThread(null);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    if (_readDebounce != null && _readDebounce!.isActive) {
      _readDebounce!.cancel();
      _markVisibleRead(); // ensure we mark as read even if user closes quickly
    }
    // Notify HomeBloc to refresh read states from SQLite — instant, no native call
    try {
      context.read<HomeBloc>().add(const RefreshReadState());
    } catch (_) {}
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    // In reverse:true, pixels=0 is the BOTTOM of screen (newest messages).
    // pixels=maxScrollExtent is the TOP of screen (oldest messages).
    final atBottom = pos.pixels <= 100;
    if (_showScrollToBottom != !atBottom) {
      setState(() => _showScrollToBottom = !atBottom);
    }

    // Load more older messages when user scrolls near the TOP (maxScrollExtent)
    if (pos.hasContentDimensions && pos.pixels >= pos.maxScrollExtent - 150) {
      final bloc = context.read<ConversationBloc>();
      final bstate = bloc.state;
      if (bstate is ConversationLoaded && bstate.hasMore && !bstate.isLoadingMore) {
        bloc.add(LoadMoreMessages(widget.threadId));
      }
    }

    // Debounce visibility-based read marking
    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(milliseconds: 400), _markVisibleRead);
  }

  // In reverse:true, "bottom" (newest) = pixels 0.0 = minScrollExtent
  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    if (animated) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(0.0);
    }
  }

  /// Scrolls to a highlighted message from a search result tap.
  /// Two-phase:
  ///   1. Rough scroll: jump to an estimated pixel offset based on message index
  ///      (forces the virtualized ListView to build items around the target).
  ///   2. Fine scroll: once the item's GlobalKey is attached, center it exactly.
  void _scrollToHighlight(int messageId, {int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) {
        if (attempt < 40) _scrollToHighlight(messageId, attempt: attempt + 1);
        return;
      }

      final key = _messageKeys[messageId];
      final ctx = key?.currentContext;

      if (ctx == null) {
        // Item not built yet. On first attempts, do a rough positional scroll
        // to force the virtualized list to render items near the target.
        if (attempt == 0) {
          // Find message index in the current state to estimate offset
          final bstate = context.read<ConversationBloc>().state;
          if (bstate is ConversationLoaded) {
            final idx = bstate.messages.indexWhere((m) => m.id == messageId);
            if (idx >= 0) {
              // Estimate: each message ~60px average. Scroll partway there.
              final total = bstate.messages.length;
              // In DESC list, idx=0 is newest (pixels=0), idx=total-1 is oldest (maxExtent).
              final fraction = idx / (total > 1 ? total - 1 : 1);
              final target = fraction * _scrollController.position.maxScrollExtent;
              _scrollController.jumpTo(target.clamp(0.0, _scrollController.position.maxScrollExtent));
            }
          }
        }
        if (attempt < 40) _scrollToHighlight(messageId, attempt: attempt + 1);
        return;
      }

      // Item is built — fine-tune to center it in the viewport
      final renderBox = ctx.findRenderObject() as RenderBox?;
      if (renderBox == null) {
        if (attempt < 40) _scrollToHighlight(messageId, attempt: attempt + 1);
        return;
      }

      final scrollRenderBox = _scrollController
          .position.context.storageContext
          .findRenderObject() as RenderBox?;
      if (scrollRenderBox == null) return;

      final itemOffset = renderBox.localToGlobal(Offset.zero, ancestor: scrollRenderBox);
      final viewportHeight = _scrollController.position.viewportDimension;
      final currentPixels = _scrollController.position.pixels;
      final targetPixels = (currentPixels + itemOffset.dy - (viewportHeight / 2) + (renderBox.size.height / 2))
          .clamp(0.0, _scrollController.position.maxScrollExtent);

      _scrollController.animateTo(
        targetPixels,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    });
  }

  void _markVisibleRead() {
    final state = context.read<ConversationBloc>().state;
    if (state is! ConversationLoaded) return;

    // All currently-loaded messages that are unread and not outgoing
    final unreadIds = state.messages
        .where((m) => !m.read && !m.isOutgoing)
        .map((m) => m.id)
        .toList();
    if (unreadIds.isEmpty) return;

    context.read<ConversationBloc>().add(
      MarkVisibleAsRead(widget.threadId, unreadIds),
    );
  }

  String get _displayName => widget.contactName?.isNotEmpty == true
      ? widget.contactName!
      : widget.address?.isNotEmpty == true
      ? widget.address!
      : 'Unknown';

  bool get _canReply {
    final addr = widget.address ?? '';
    if (addr.isEmpty) return false;
    // If it contains a letter, it's an alphanumeric sender ID (not replyable via SMS)
    // except if it is an email address (has '@'), some carriers support email to SMS but mostly no.
    return !RegExp(r'[a-zA-Z]').hasMatch(addr);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BlocConsumer<ConversationBloc, ConversationState>(
      listener: (context, state) {
        if (state is ConversationError) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.message)));
        } else if (state is ConversationLoaded) {
          // Trigger read marking immediately for small conversations that don't scroll
          if (state.messages.any((m) => !m.read && !m.isOutgoing)) {
            _readDebounce?.cancel();
            _readDebounce = Timer(
              const Duration(milliseconds: 400),
              _markVisibleRead,
            );
          }

          // Scroll to highlighted message (from search result tap)
          if (state.highlightMessageId != null && !_didHighlight) {
            _didHighlight = true;
            _scrollToHighlight(state.highlightMessageId!);
          }
        }
      },
      builder: (context, state) {
        final isMultiSelect =
            state is ConversationLoaded && state.selectedIds.isNotEmpty;

        return Scaffold(
          backgroundColor: colorScheme.surface,
          appBar: _buildAppBar(context, state, colorScheme, isMultiSelect),
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.translucent,
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      _buildMessageList(context, state, colorScheme),
                      // Scroll-to-bottom FAB
                      if (_showScrollToBottom && state is ConversationLoaded)
                        Positioned(
                          right: 0,
                          bottom: 8,
                          child: ScrollToBottomFab(
                            unreadCount: state.unreadBelow,
                            onTap: _scrollToBottom,
                          ),
                        ),
                    ],
                  ),
                ),
                // Compose bar (hidden in multi-select mode)
                if (!isMultiSelect)
                  _canReply
                      ? BlocBuilder<ConversationBloc, ConversationState>(
                          builder: (context, state) {
                            final isSending =
                                state is ConversationLoaded && state.isSending;
                            final simInfoList = state is ConversationLoaded
                                ? state.simInfoList
                                : const <Map<String, dynamic>>[];
                            final selectedSimId = state is ConversationLoaded
                                ? state.selectedSimId
                                : null;

                            return ComposeBar(
                              address: widget.address ?? '',
                              isSending: isSending,
                              simInfoList: simInfoList,
                              selectedSimId: selectedSimId,
                              initialBody: widget.initialBody,
                              onSend: (body) {
                                context.read<ConversationBloc>().add(
                                  SendMessage(
                                    threadId: widget.threadId,
                                    address: widget.address ?? '',
                                    body: body,
                                  ),
                                );
                              },
                              onSimSelected: (id) {
                                context.read<ConversationBloc>().add(
                                  SelectSim(id),
                                );
                              },
                            );
                          },
                        )
                      : Container(
                          padding: const EdgeInsets.all(16),
                          alignment: Alignment.center,
                          color: colorScheme.surfaceContainerHighest,
                          child: Text(
                            'Sender does not support replies',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ),
              ],
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ConversationState state,
    ColorScheme colorScheme,
    bool isMultiSelect,
  ) {
    if (isMultiSelect && state is ConversationLoaded) {
      return _buildMultiSelectAppBar(context, state, colorScheme);
    }
    if (_isSearching) {
      return _buildSearchAppBar(context, colorScheme);
    }
    return _buildNormalAppBar(context, colorScheme);
  }

  AppBar _buildNormalAppBar(BuildContext context, ColorScheme colorScheme) {
    return AppBar(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      title: GestureDetector(
        onTap: () {
          if (widget.address != null && widget.address!.isNotEmpty) {
            NativeSmsService.openContactCard(widget.address!);
          }
        },
        child: Row(
          children: [
            SmartAvatar(
              overrideAddress: widget.address,
              overrideContactName: widget.contactName,
              overrideContactPhotoUri: widget.contactPhotoUri,
              radius: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.address != null &&
                      widget.address!.isNotEmpty &&
                      widget.contactName != null)
                    Text(
                      widget.address!,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        // Search always visible in the app bar
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search',
          onPressed: () => setState(() => _isSearching = true),
        ),
        PopupMenuButton<String>(
          onSelected: _onMenuAction,
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete conversation'),
            ),
          ],
        ),
      ],
    );
  }

  AppBar _buildSearchAppBar(BuildContext context, ColorScheme colorScheme) {
    return AppBar(
      backgroundColor: colorScheme.surface,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () {
          setState(() => _isSearching = false);
          context.read<ConversationBloc>().add(const ClearSearch());
        },
      ),
      title: TextField(
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Search messages…',
          border: InputBorder.none,
        ),
        onChanged: (q) =>
            context.read<ConversationBloc>().add(SearchMessages(q)),
      ),
    );
  }

  AppBar _buildMultiSelectAppBar(
    BuildContext context,
    ConversationLoaded state,
    ColorScheme colorScheme,
  ) {
    final count = state.selectedIds.length;
    return AppBar(
      backgroundColor: colorScheme.primaryContainer,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () =>
            context.read<ConversationBloc>().add(const ClearSelection()),
      ),
      title: Text('$count selected'),
      actions: [
        IconButton(
          icon: const Icon(Icons.copy_rounded),
          tooltip: 'Copy',
          onPressed: () {
            final selected = state.messages
                .where((m) => state.selectedIds.contains(m.id))
                .map((m) => m.body)
                .join('\n\n');
            Clipboard.setData(ClipboardData(text: selected));
            context.read<ConversationBloc>().add(const ClearSelection());
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied'),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded),
          tooltip: 'Delete',
          onPressed: () => _deleteSelected(context, state),
        ),
      ],
    );
  }

  Widget _buildMessageList(
    BuildContext context,
    ConversationState state,
    ColorScheme colorScheme,
  ) {
    if (state is ConversationLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state is ConversationError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 12),
            Text(state.message, style: TextStyle(color: colorScheme.error)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.read<ConversationBloc>().add(
                LoadMessages(widget.threadId, address: widget.address ?? ''),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (state is! ConversationLoaded) return const SizedBox.shrink();

    final messages = state.displayMessages;
    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: colorScheme.outlineVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No messages yet',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              'Send a message to start the conversation',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // In DESC list: oldest unread is at the HIGHEST index (visually top of screen).
    // We scan backwards to find the last unread — this is where the separator
    // should appear (just below visually, i.e. the highest-index unread).
    int? firstUnreadIdx;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (!messages[i].read && !messages[i].isOutgoing) {
        firstUnreadIdx = i;
        break;
      }
    }

    return TimelineScrollbar(
      controller: _scrollController,
      reversed: true,
      // The scrollbar gives us displayFraction where 1.0=bottom=newest (index 0).
      // So array index = (1.0 - fraction) * (length-1).
      labelForFraction: (fraction) {
        if (messages.isEmpty) return '';
        final idx = ((1.0 - fraction) * (messages.length - 1)).round().clamp(
          0,
          messages.length - 1,
        );
        return timelineLabel(messages[idx].date);
      },
      child: ListView.builder(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        reverse: true,
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        itemCount: messages.length + (state.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          // Spinner at the top of screen = highest index in reverse list
          if (state.isLoadingMore && index == messages.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final msgIndex = index;
          final message = messages[msgIndex];

          // In DESC list: index+1 = older message, index-1 = newer message
          final olderMsg = msgIndex < messages.length - 1 ? messages[msgIndex + 1] : null;
          final newerMsg = msgIndex > 0 ? messages[msgIndex - 1] : null;

          final sameAsOlder = olderMsg != null &&
              olderMsg.isOutgoing == message.isOutgoing &&
              message.date - olderMsg.date < 60000;
          final sameAsNewer = newerMsg != null &&
              newerMsg.isOutgoing == message.isOutgoing &&
              newerMsg.date - message.date < 60000;

          BubblePosition pos;
          if (!sameAsOlder && !sameAsNewer) {
            pos = BubblePosition.solo;
          } else if (!sameAsOlder && sameAsNewer) {
            pos = BubblePosition.first;
          } else if (sameAsOlder && !sameAsNewer) {
            pos = BubblePosition.last;
          } else {
            pos = BubblePosition.middle;
          }

          // Show date separator when day changes; olderMsg is visually above on screen
          final showDate =
              olderMsg == null ||
              !_sameDay(
                DateTime.fromMillisecondsSinceEpoch(olderMsg.date),
                DateTime.fromMillisecondsSinceEpoch(message.date),
              );

          // Show unread separator above the oldest unread block
          final showUnreadSep =
              firstUnreadIdx != null && msgIndex == firstUnreadIdx;
              
          final isHighlighted = state.highlightMessageId == message.id;

          return Column(
            key: _messageKeys.putIfAbsent(message.id, () => GlobalKey()),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showDate)
                DateSeparator(
                  date: DateTime.fromMillisecondsSinceEpoch(message.date),
                ),
              if (showUnreadSep) const UnreadSeparator(),
              MessageBubble(
                message: message,
                position: pos,
                isSelected: state.selectedIds.contains(message.id),
                isHighlighted: isHighlighted,
                searchQuery: state.searchQuery,
                onShowMenu: (msg) => _showContextMenu(context, msg),
                onTap: state.selectedIds.isNotEmpty
                    ? (msg) => context.read<ConversationBloc>().add(
                        SelectMessage(msg.id),
                      )
                    : null,
              ),
            ],
          );
        },
      ),
    );
  }

  void _showContextMenu(BuildContext context, SmsMessage message) {
    MessageSheet.show(
      context,
      message: message,
      onCopy: () {
        Clipboard.setData(ClipboardData(text: message.body));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      onForward: () {
        context.go('/home/compose', extra: message.body);
      },
      onStar: () =>
          context.read<ConversationBloc>().add(ToggleStarMessage(message)),
      onDelete: () => _confirmDelete(context, message),
      onSelect: () =>
          context.read<ConversationBloc>().add(SelectMessage(message.id)),
    );
  }

  void _confirmDelete(BuildContext context, SmsMessage message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete message'),
        content: const Text('This will permanently delete this message.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<ConversationBloc>().add(DeleteMessage(message.id));
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _deleteSelected(BuildContext context, ConversationLoaded state) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${state.selectedIds.length} messages'),
        content: const Text('These messages will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              for (final id in state.selectedIds) {
                context.read<ConversationBloc>().add(DeleteMessage(id));
              }
              context.read<ConversationBloc>().add(const ClearSelection());
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _onMenuAction(String action) {
    switch (action) {
      case 'delete':
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete conversation'),
            content: const Text(
              'This will permanently delete the entire conversation. Are you sure?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context); // close dialog
                  context.read<ConversationBloc>().add(
                    DeleteConversation(widget.threadId),
                  );
                  context.pop(); // exit conversation page
                },
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        break;
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
