// FILE: utils/responsive_scale.dart
// Keeps the whole app in proportion on every phone.
//
// The screens are designed for a ~390 dp wide phone. On bigger phones (iPhone Pro Max, large Androids) the same
// fixed sizes looked small. This wrapper scales the whole UI up by (screen width ÷ 390), at most 12 %,
// so layouts, text and buttons keep the same proportions on every screen size.
// Phones narrower than 390 dp are NOT changed (no risk of overflow).

import 'package:flutter/widgets.dart';

/// Design width the screens were built for (dp).
const double kDesignWidth = 390;

/// Largest enlargement allowed.
const double kMaxUiScale = 1.12;

/// Wrap the app's `MaterialApp.builder` child with this.
class ResponsiveScale extends StatelessWidget {
  final Widget child;
  const ResponsiveScale({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final width = mq.size.shortestSide; // phones in portrait; tablets are capped by kMaxUiScale
    final scale = (width / kDesignWidth).clamp(1.0, kMaxUiScale).toDouble();
    if (scale <= 1.01) return child;

    final logical = Size(mq.size.width / scale, mq.size.height / scale);
    return MediaQuery(
      data: mq.copyWith(
        size: logical,
        padding: mq.padding / scale,
        viewPadding: mq.viewPadding / scale,
        viewInsets: mq.viewInsets / scale,
        systemGestureInsets: mq.systemGestureInsets / scale,
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: logical.width,
          maxWidth: logical.width,
          minHeight: logical.height,
          maxHeight: logical.height,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox(width: logical.width, height: logical.height, child: child),
          ),
        ),
      ),
    );
  }
}
