import 'package:material_ui/material_ui.dart';

class HighlightPulser extends StatefulWidget {
  final Widget child;
  final bool isHighlighted;
  final Color highlightColor;

  const HighlightPulser({
    super.key,
    required this.child,
    this.isHighlighted = false,
    required this.highlightColor,
  });

  @override
  State<HighlightPulser> createState() => _HighlightPulserState();
}

class _HighlightPulserState extends State<HighlightPulser> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Color?> _colorAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _colorAnim = TweenSequence<Color?>([
      TweenSequenceItem(tween: ColorTween(begin: Colors.transparent, end: widget.highlightColor), weight: 1),
      TweenSequenceItem(tween: ColorTween(begin: widget.highlightColor, end: widget.highlightColor), weight: 4),
      TweenSequenceItem(tween: ColorTween(begin: widget.highlightColor, end: Colors.transparent), weight: 3),
    ]).animate(_controller);

    if (widget.isHighlighted) _controller.forward();
  }

  @override
  void didUpdateWidget(HighlightPulser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isHighlighted && !oldWidget.isHighlighted) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _colorAnim,
      builder: (context, child) {
        return Container(
          color: _colorAnim.value,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
