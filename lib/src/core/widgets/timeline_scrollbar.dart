import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

/// A scrollbar that shows a floating date label while the user drags the thumb.
///
/// Usage:
/// ```dart
/// TimelineScrollbar(
///   controller: _scrollController,
///   labelForFraction: (fraction) {
///     final idx = (fraction * dates.length).floor().clamp(0, dates.length - 1);
///     return _formatDate(dates[idx]);
///   },
///   child: ListView.builder(...),
/// )
/// ```
class TimelineScrollbar extends StatefulWidget {
  final ScrollController controller;
  final Widget child;

  /// Given the scroll fraction (0.0 = top, 1.0 = bottom), return the label
  /// to show in the floating bubble next to the thumb.
  final String Function(double fraction) labelForFraction;

  const TimelineScrollbar({
    super.key,
    required this.controller,
    required this.child,
    required this.labelForFraction,
  });

  @override
  State<TimelineScrollbar> createState() => _TimelineScrollbarState();
}

class _TimelineScrollbarState extends State<TimelineScrollbar>
    with SingleTickerProviderStateMixin {
  double _fraction = 0.0;
  bool _isDragging = false;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  bool _isScrolling = false;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(TimelineScrollbar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = widget.controller.position;
    if (pos.maxScrollExtent <= 0) return;
    setState(() {
      _fraction = (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0);
      _isScrolling = true;
    });
    _fadeCtrl.forward();
    // Hide label 1.5s after scrolling stops
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && !_isDragging) {
        _fadeCtrl.reverse().then((_) {
          if (mounted) setState(() => _isScrolling = false);
        });
      }
    });
  }

  void _onDragUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    final trackHeight = constraints.maxHeight;
    final dy = details.localPosition.dy.clamp(0.0, trackHeight);
    setState(() {
      _fraction = (dy / trackHeight).clamp(0.0, 1.0);
      _isDragging = true;
    });
    _fadeCtrl.forward();

    // Jump scroll to the new position
    final pos = widget.controller.position;
    if (pos.maxScrollExtent > 0) {
      widget.controller.jumpTo(_fraction * pos.maxScrollExtent);
    }
  }

  void _onDragEnd(DragEndDetails _) {
    setState(() => _isDragging = false);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        _fadeCtrl.reverse().then((_) {
          if (mounted) setState(() => _isScrolling = false);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Thumb position: fraction of (track height - thumb size)
        const thumbHeight = 48.0;
        const trackPadding = 8.0;
        final trackH = constraints.maxHeight - trackPadding * 2 - thumbHeight;
        final thumbTop = trackPadding + _fraction * trackH;

        final label = (_isDragging || _isScrolling)
            ? widget.labelForFraction(_fraction)
            : '';

        return Stack(
          children: [
            widget.child,

            // Scrollbar track + thumb (always visible, subtle)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: (d) => _onDragUpdate(d, constraints),
                onVerticalDragEnd: _onDragEnd,
                onVerticalDragStart: (_) {
                  setState(() => _isDragging = true);
                  _fadeCtrl.forward();
                },
                child: SizedBox(
                  width: 24,
                  child: Stack(
                    children: [
                      // Track line
                      Positioned(
                        right: 10,
                        top: trackPadding,
                        bottom: trackPadding,
                        child: Container(
                          width: 2,
                          decoration: BoxDecoration(
                            color: colorScheme.outlineVariant.withAlpha(80),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                      // Thumb
                      Positioned(
                        right: 6,
                        top: thumbTop,
                        child: AnimatedOpacity(
                          opacity: (_isDragging || _isScrolling) ? 1.0 : 0.4,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            width: 10,
                            height: thumbHeight,
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Floating date label — shown while scrolling/dragging
            if (label.isNotEmpty)
              Positioned(
                right: 28,
                top: (thumbTop + thumbHeight / 2 - 18).clamp(
                  0.0,
                  constraints.maxHeight - 36,
                ),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.inverseSurface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(40),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: colorScheme.onInverseSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Helpers for building labels ───────────────────────────────────────────────

/// Formats a timestamp for the timeline scrollbar label.
String timelineLabel(int timestampMs) {
  final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final msgDay = DateTime(date.year, date.month, date.day);
  final diff = today.difference(msgDay).inDays;

  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return DateFormat('EEE').format(date); // "Tue"
  if (date.year == now.year) {
    return DateFormat('MMM d').format(date); // "Aug 24"
  }
  return DateFormat('MMM d, yy').format(date); // "Aug 24, 23"
}
