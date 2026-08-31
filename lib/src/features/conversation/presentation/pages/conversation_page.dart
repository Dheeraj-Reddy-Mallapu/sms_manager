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
import 'package:sms_manager/src/core/widgets/timeline_scrollbar.dart';

class ConversationPage extends StatefulWidget {
  final int threadId;
  final String? address;
  final String? contactName;
  final String? contactPhotoUri;

  const ConversationPage({
    super.key,
    required this.threadId,
    this.address,
    this.contactName,
    this.contactPhotoUri,
  });

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final _scrollController = ScrollController();
  bool _showScrollToBottom = false;
  SmsMessage? _replyToMessage;
  bool _isSearching = false;

  // For read-tracking: set of message IDs currently visible
  Timer? _readDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    final address = widget.address ?? '';
    context.read<ConversationBloc>().add(
      LoadMessages(widget.threadId, address: address),
    );
  }

  @override
  void dispose() {
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
    final atBottom = pos.pixels >= pos.maxScrollExtent - 100;
    if (_showScrollToBottom == atBottom) {
      setState(() => _showScrollToBottom = !atBottom);
    }

    // Load more when user scrolls near the top
    if (pos.pixels <= 150) {
      final bloc = context.read<ConversationBloc>();
      if (bloc.state is ConversationLoaded) {
        bloc.add(LoadMoreMessages(widget.threadId));
      }
    }

    // Debounce visibility-based read marking
    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(milliseconds: 400), _markVisibleRead);
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    if (animated) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
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
        if (state is ConversationLoaded) {
          // Auto-scroll to bottom when a new message arrives and user is at bottom
          if (!_showScrollToBottom) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollController.hasClients) {
                _scrollToBottom();
              }
            });
          }
          // On initial load, scroll to bottom
          if (state.messages.isNotEmpty && !_scrollController.hasClients) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToBottom(animated: false);
            });
          }
        }
      },
      builder: (context, state) {
        final isMultiSelect =
            state is ConversationLoaded && state.selectedIds.isNotEmpty;

        return Scaffold(
          backgroundColor: colorScheme.surface,
          appBar: _buildAppBar(context, state, colorScheme, isMultiSelect),
          body: Column(
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
              // Compose bar (hidden in multi-select / search mode)
              if (!isMultiSelect)
                _canReply
                    ? BlocBuilder<ConversationBloc, ConversationState>(
                        builder: (context, state) {
                          final isSending =
                              state is ConversationLoaded && state.isSending;
                          return ComposeBar(
                            address: widget.address ?? '',
                            isSending: isSending,
                            replyToMessage: _replyToMessage,
                            onDismissReply: () =>
                                setState(() => _replyToMessage = null),
                            onSend: (body) {
                              context.read<ConversationBloc>().add(
                                    SendMessage(
                                      threadId: widget.threadId,
                                      address: widget.address ?? '',
                                      body: body,
                                      replyTo: _replyToMessage,
                                    ),
                                  );
                              setState(() => _replyToMessage = null);
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
        onTap: _openContactDetails,
        child: Row(
          children: [
            _buildAvatar(colorScheme, size: 18),
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
        if (_canReply)
          IconButton(
            icon: const Icon(Icons.call_outlined),
            tooltip: 'Call',
            onPressed: _call,
          ),
        PopupMenuButton<String>(
          onSelected: _onMenuAction,
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'search', child: Text('Search')),
            const PopupMenuItem(
              value: 'view_contact',
              child: Text('View contact'),
            ),
            const PopupMenuItem(value: 'block', child: Text('Block number')),
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

    // Find index of first unread incoming message
    int? firstUnreadIdx;
    for (int i = 0; i < messages.length; i++) {
      if (!messages[i].read && !messages[i].isOutgoing) {
        firstUnreadIdx = i;
        break;
      }
    }

    return TimelineScrollbar(
      controller: _scrollController,
      labelForFraction: (fraction) {
        if (messages.isEmpty) return '';
        // Conversation is reversed: bottom is newest (index length-1). 
        // Fraction 0.0 is top (oldest), 1.0 is bottom (newest).
        final idx = (fraction * messages.length).floor().clamp(0, messages.length - 1);
        return timelineLabel(messages[idx].date);
      },
      child: ListView.builder(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        itemCount: messages.length + (state.isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        // Spinner at top while loading older messages
        if (state.isLoadingMore && index == 0) {
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

        final msgIndex = state.isLoadingMore ? index - 1 : index;
        final message = messages[msgIndex];

        // Determine grouping position
        final prev = msgIndex > 0 ? messages[msgIndex - 1] : null;
        final next = msgIndex < messages.length - 1
            ? messages[msgIndex + 1]
            : null;

        final sameAsPrev =
            prev != null &&
            prev.isOutgoing == message.isOutgoing &&
            message.date - prev.date < 60000;
        final sameAsNext =
            next != null &&
            next.isOutgoing == message.isOutgoing &&
            next.date - message.date < 60000;

        BubblePosition pos;
        if (!sameAsPrev && !sameAsNext) {
          pos = BubblePosition.solo;
        } else if (!sameAsPrev && sameAsNext) {
          pos = BubblePosition.first;
        } else if (sameAsPrev && sameAsNext) {
          pos = BubblePosition.middle;
        } else {
          pos = BubblePosition.last;
        }

        // Date separator when day changes
        final showDate =
            prev == null ||
            !_sameDay(
              DateTime.fromMillisecondsSinceEpoch(prev.date),
              DateTime.fromMillisecondsSinceEpoch(message.date),
            );

        // Unread separator
        final showUnreadSep =
            firstUnreadIdx != null && msgIndex == firstUnreadIdx;

        return Column(
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
              searchQuery: state.searchQuery,
              onLongPress: (msg) => _showContextMenu(context, msg),
              onReply: (msg) => setState(() => _replyToMessage = msg),
              onTap: state.selectedIds.isNotEmpty
                  ? (msg) => context.read<ConversationBloc>().add(
                      SelectMessage(msg.id),
                    )
                  : null,
            ),
          ],
        );
      },
    ));
  }

  void _showContextMenu(BuildContext context, SmsMessage message) {
    MessageContextMenu.show(
      context,
      message: message,
      onReply: () => setState(() => _replyToMessage = message),
      onCopy: () {},
      onForward: () {
        context.go('/home/compose', extra: message.body);
      },
      onStar: () =>
          context.read<ConversationBloc>().add(ToggleStarMessage(message)),
      onDelete: () => _confirmDelete(context, message),
      onSelect: () =>
          context.read<ConversationBloc>().add(SelectMessage(message.id)),
      onDetails: () => MessageDetailsSheet.show(context, message),
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

  Widget _buildAvatar(ColorScheme colorScheme, {double size = 20}) {
    final displayName = _displayName;
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    const colors = [
      Color(0xFF6750A4),
      Color(0xFF0288D1),
      Color(0xFF00897B),
      Color(0xFFC62828),
      Color(0xFF558B2F),
      Color(0xFF6A1B9A),
    ];
    final avatarColor =
        colors[displayName.codeUnits.fold(0, (p, c) => p + c) % colors.length];

    if (widget.contactPhotoUri?.isNotEmpty == true) {
      return CircleAvatar(
        radius: size,
        backgroundColor: avatarColor,
        backgroundImage: NetworkImage(widget.contactPhotoUri!),
        onBackgroundImageError: (exception, stackTrace) {},
        child: null,
      );
    }
    return CircleAvatar(
      radius: size,
      backgroundColor: avatarColor,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _call() {
    final address = widget.address;
    if (address == null || address.isEmpty) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Calling $address…')));
  }

  void _openContactDetails() {
    // TODO: open Android contact card via url_launcher tel: or ContactsContract
  }

  void _onMenuAction(String action) {
    switch (action) {
      case 'search':
        setState(() => _isSearching = true);
        break;
      case 'view_contact':
        _openContactDetails();
        break;
      case 'block':
        // TODO: block via DB helper
        break;
      case 'delete':
        // TODO: delete entire thread
        break;
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
