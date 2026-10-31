import 'dart:math' as math;

import 'package:flutter/material.dart';

export '../features/mobile/responsive/breakpoints.dart';

class CashierResponsiveViewport extends StatelessWidget {
  const CashierResponsiveViewport({
    super.key,
    required this.child,
    this.designSize = const Size(1920, 1080),
  });

  final Widget child;
  final Size designSize;

  @override
  Widget build(BuildContext context) {
    assert(designSize.width > 0 && designSize.height > 0);
    final media = MediaQuery.of(context);
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(
            constraints.hasBoundedWidth
                ? constraints.maxWidth
                : media.size.width,
            constraints.hasBoundedHeight
                ? constraints.maxHeight
                : media.size.height,
          );
          if (viewport.isEmpty) {
            return const SizedBox.shrink();
          }



          final scale = math.min(
            viewport.width / designSize.width,
            viewport.height / designSize.height,
          );
          final logicalSize = Size(
            viewport.width / scale,
            viewport.height / scale,
          );

          return SizedBox.fromSize(
            size: viewport,
            child: FittedBox(
              alignment: Alignment.topLeft,
              fit: BoxFit.contain,
              clipBehavior: Clip.hardEdge,
              child: SizedBox.fromSize(
                size: logicalSize,
                child: MediaQuery(
                  data: media.copyWith(size: logicalSize),
                  child: child,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
