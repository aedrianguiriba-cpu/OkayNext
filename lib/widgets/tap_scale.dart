import 'package:flutter/material.dart';

/// Wraps any widget with a subtle scale-down animation on press.
class TapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  const TapScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.92,
  });

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _pressed = false;

  void _down(_) {
    if (widget.onTap != null) setState(() => _pressed = true);
  }

  void _up(_) {
    if (!_pressed) return;
    setState(() => _pressed = false);
    widget.onTap?.call();
  }

  void _cancel() => setState(() => _pressed = false);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _down,
      onTapUp: _up,
      onTapCancel: _cancel,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: (_pressed && widget.onTap != null) ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
