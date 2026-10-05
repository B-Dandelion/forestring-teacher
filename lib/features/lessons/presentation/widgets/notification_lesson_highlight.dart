import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/forestring_theme.dart';

class NotificationLessonHighlight extends StatefulWidget {
  const NotificationLessonHighlight({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<NotificationLessonHighlight> createState() =>
      _NotificationLessonHighlightState();
}

class _NotificationLessonHighlightState
    extends State<NotificationLessonHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..repeat(reverse: true);

    _settleTimer = Timer(
      const Duration(milliseconds: 1920),
      () {
        if (!mounted) {
          return;
        }

        _controller
          ..stop()
          ..value = 1;
      },
    );
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final value = _controller.value;

        return Transform.scale(
          scale: 1 + (0.016 * value),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              child!,
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: primaryColor.withValues(
                          alpha: 0.55 + (0.35 * value),
                        ),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withValues(
                            alpha: 0.10 + (0.16 * value),
                          ),
                          blurRadius: 6 + (4 * value),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
