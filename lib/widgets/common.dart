// FILE: widgets/common.dart
// SHARED WIDGETS used across the app: cards, pills, buttons, headers, backgrounds, bottom nav, app bar.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/tokens.dart';
import '../utils/app_feedback.dart';
import '../utils/notification_badge.dart';
import '../screens/notifications_screen.dart';
import '../screens/messages_screen.dart';

/// Aira Card widget.
class AiraCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Gradient? gradient;
  final Color borderColor;
  final double borderWidth;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;
  final Clip clipBehavior;

  const AiraCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.backgroundColor = AiraColors.pinkFill,
    this.gradient,
    this.borderColor = AiraColors.hair,
    this.borderWidth = 1,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.onTap,
    this.clipBehavior = Clip.none,
  });

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    final card = Container(
      clipBehavior: clipBehavior,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? backgroundColor : null,
        gradient: gradient,
        borderRadius: borderRadius,
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: const [
          BoxShadow(color: Color(0x14C2185B), blurRadius: 18, offset: Offset(0, 6)),
        ],
      ),
      child: child,
    );

    if (onTap == null) return card;

    return InkWell(
      onTap: onTap,
      borderRadius: borderRadius,
      child: card,
    );
  }
}

/// Aira Pill widget.
class AiraPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const AiraPill({super.key, required this.label, this.active = false, this.onTap});

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          gradient: active ? AiraGradients.button : null,
          color: active ? null : AiraColors.pinkFill,
          borderRadius: BorderRadius.circular(999),
          border: active ? null : Border.all(color: AiraColors.pinkBorder),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AiraText.sans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AiraColors.roseDeep,
          ),
        ),
      ),
    );
  }
}

/// Primary Button widget.
class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool small;
  final VoidCallback? onTap;
  final Color? background;
  final Color foreground;
  final bool expand;
  final bool arrow;

  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.small = false,
    this.onTap,
    this.background,
    this.foreground = Colors.white,
    this.expand = false,
    this.arrow = false,
  });

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: small ? 15 : 18, color: foreground),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: AiraText.sans(
              fontSize: small ? 13 : 16,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ),
        if (arrow) ...[
          const SizedBox(width: 8),
          Icon(Icons.arrow_forward_rounded, size: small ? 15 : 19, color: foreground),
        ],
      ],
    );

    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: background == null ? AiraGradients.button : null,
          color: background,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(color: Color(0x33C2185B), blurRadius: 16, offset: Offset(0, 6)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: small ? 18 : 24, vertical: small ? 10 : 16),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Ghost Button widget.
class GhostButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool small;
  final VoidCallback? onTap;
  final Color color;
  final bool expand;

  const GhostButton({
    super.key,
    required this.label,
    this.icon,
    this.small = false,
    this.onTap,
    this.color = AiraColors.roseDeep,
    this.expand = false,
  });

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: expand ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: small ? 16 : 22, vertical: small ? 10 : 14),
          decoration: BoxDecoration(
            color: AiraColors.pinkFill.withOpacity(0.7),
            border: Border.all(color: AiraColors.pinkBorder, width: 1.2),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: small ? 12 : 18, color: color),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: AiraText.sans(fontSize: small ? 11.5 : 14.5, fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sunndari Logo widget.
class SunndariLogo extends StatelessWidget {
  final double width;
  const SunndariLogo({super.key, this.width = 220});

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/sunndari_logo.png',
      width: width,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Text('Sunndari',
          style: AiraText.serif(fontSize: 26, fontWeight: FontWeight.w600)),
    );
  }
}

/// Aira Orb widget.
class AiraOrb extends StatelessWidget {
  final double size;
  final VoidCallback? onTap;

  const AiraOrb({super.key, this.size = 44, this.onTap});

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    final orb = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AiraGradients.avatarOrb,
        boxShadow: [
          BoxShadow(color: AiraColors.blush, blurRadius: 0, spreadRadius: 4),
        ],
      ),
      child: Icon(Icons.auto_awesome, color: Colors.white, size: size * 0.42),
    );

    if (onTap == null) return orb;
    return GestureDetector(onTap: onTap, child: orb);
  }
}

/// Aira Error State widget.
class AiraErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const AiraErrorState({super.key, required this.message, required this.onRetry});

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    final displayMessage = AppFeedback.friendlyMessage(message);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 28, color: AiraColors.errorText),
            const SizedBox(height: 10),
            Text(displayMessage,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: AiraText.sans(fontSize: 13.5, color: AiraColors.charcoalSoft)),
            const SizedBox(height: 14),
            GhostButton(label: 'Retry', icon: Icons.refresh, small: true, onTap: onRetry),
          ],
        ),
      ),
    );
  }
}

/// Aira Screen Header widget.
class AiraScreenHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;

  const AiraScreenHeader({super.key, required this.title, this.onBack});

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Row(
        children: [
          if (onBack != null || Navigator.of(context).canPop()) ...[
            SunndariBackChip(onTap: onBack ?? () => Navigator.of(context).maybePop()),
            const SizedBox(width: 4),
          ],
          Expanded(child: Text(title, style: AiraText.serif(fontSize: 22))),
        ],
      ),
    );
  }
}

/// Sunndari Background widget.
class SunndariBackground extends StatelessWidget {
  final Widget child;
  const SunndariBackground({super.key, required this.child});

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(gradient: AiraGradients.page),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -120,
            left: -90,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Colors.white.withOpacity(0.75), Colors.white.withOpacity(0)],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -140,
            right: -100,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AiraColors.rose.withOpacity(0.16), AiraColors.rose.withOpacity(0)],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Sunndari Flow Bar widget — centred title with the standard round back chip on the left
/// and an optional [trailing] action (e.g. Log Out) on the right.
class SunndariFlowBar extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  const SunndariFlowBar({super.key, required this.title, this.onBack, this.trailing});

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    // width: infinity → the bar always spans the full row (otherwise the Stack shrinks to the title's
    // width inside a Column and the back chip ends up next to the title instead of at the left edge).
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Title first, so it can never sit on top of (and swallow taps meant for) the buttons.
          Padding(
            padding: EdgeInsets.symmetric(horizontal: trailing != null ? 96 : 56),
            child: IgnorePointer(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AiraText.sans(fontSize: 15, color: AiraColors.rose, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          if (onBack != null)
            Positioned.fill(child: Align(alignment: Alignment.centerLeft, child: SunndariBackChip(onTap: onBack!))),
          if (trailing != null)
            Positioned.fill(child: Align(alignment: Alignment.centerRight, child: trailing!)),
        ],
      ),
    );
  }
}

/// Sunndari Title widget.
class SunndariTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double size;
  final TextAlign align;
  const SunndariTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.size = 34,
    this.align = TextAlign.center,
  });

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(title, textAlign: align, style: AiraText.serif(fontSize: size, height: 1.12)),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            textAlign: align,
            style: AiraText.sans(fontSize: 14, color: AiraColors.charcoalSoft, height: 1.45),
          ),
        ],
      ],
    );
  }
}

/// Round back button used on every inner screen (same size, same place).
class SunndariBackChip extends StatelessWidget {
  final VoidCallback onTap;
  const SunndariBackChip({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // 48x48 touch target around the 40px circle, so it is easy to hit.
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              shape: BoxShape.circle,
              border: Border.all(color: AiraColors.hair),
              boxShadow: [BoxShadow(color: AiraColors.rose.withOpacity(0.10), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: const Icon(Icons.chevron_left_rounded, size: 26, color: AiraColors.roseDeep),
          ),
        ),
      ),
    );
  }
}

/// Notification bell (with unread dot) — opens the Notifications screen.
class SunndariBell extends StatelessWidget {
  final VoidCallback? onTap;
  final int unread;
  const SunndariBell({super.key, this.onTap, this.unread = 0});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Messages — opens the list of customers; tap a customer to open the chat
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Navigates to MessagesScreen
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MessagesScreen())),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.chat_bubble_outline_rounded, size: 28, color: AiraColors.roseDeep),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap ??
                // Navigates to NotificationsScreen
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: ValueListenableBuilder<bool>(
                valueListenable: NotificationBadge.instance.hasUnread,
                builder: (_, hasUnread, __) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_none_rounded, size: 30, color: AiraColors.roseDeep),
                    if (unread > 0 || hasUnread)
                      Positioned(
                        right: -1,
                        top: -1,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(color: AiraColors.rose, shape: BoxShape.circle),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
}

/// Header for the main tab pages (Home, Profile, Calendar...): page title on the left and the
/// notification bell on the SAME row on the right — no separate top bar, so no wasted space.
class SunndariTabHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBell;
  final int unread;

  /// Use inside a list that already has 20px side padding.
  final bool flush;

  const SunndariTabHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBell,
    this.unread = 0,
    this.flush = false,
  });

  @override
  Widget build(BuildContext context) {
    final bell = SunndariBell(onTap: onBell, unread: unread);
    return Padding(
      padding: flush ? const EdgeInsets.only(top: 8, bottom: 12) : const EdgeInsets.fromLTRB(20, 8, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: SunndariPageHeading(title: title, subtitle: subtitle)),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: flush ? Transform.translate(offset: const Offset(8, 0), child: bell) : bell,
          ),
        ],
      ),
    );
  }
}

/// Sunndari App Bar — slim top bar for inner pages: just the back button (no logo).
/// Main tab pages use [SunndariTabHeader] instead.
class SunndariAppBar extends StatelessWidget {
  final VoidCallback? onBell;
  final VoidCallback? onBack;
  final int unread;

  /// Optional right-side action (e.g. a share icon).
  final Widget? trailing;

  /// Kept for older callers; the bell only shows when there is no back button.
  final bool showBell;

  const SunndariAppBar({
    super.key,
    this.onBell,
    this.onBack,
    this.unread = 0,
    this.trailing,
    this.showBell = true,
  });

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    final right = trailing ?? ((onBack == null && showBell) ? SunndariBell(onTap: onBell, unread: unread) : null);
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          if (onBack != null)
            // +4 so the chip's left edge lines up with the 20px page heading below it.
            Padding(padding: const EdgeInsets.only(left: 4), child: SunndariBackChip(onTap: onBack!)),
          const Spacer(),
          if (right != null) right,
        ],
      ),
    );
  }
}

/// Sunndari Page Heading widget.
class SunndariPageHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  const SunndariPageHeading({super.key, required this.title, this.subtitle});

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AiraText.serif(fontSize: 30, height: 1.1)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: AiraText.sans(fontSize: 15, color: AiraColors.charcoalSoft)),
        ],
      ],
    );
  }
}

/// Sunndari Field widget.
class SunndariField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? optionalTag;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? prefix;
  final Widget? suffix;
  final int maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? formatters;
  /// null = automatic: first letter capital for normal text; none for email / number / phone / password / URL.
  final TextCapitalization? capitalization;
  final bool serifLabel;
  final String? helper;
  final bool readOnly;
  final String? errorText;

  const SunndariField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.optionalTag,
    this.keyboardType,
    this.obscure = false,
    this.prefix,
    this.suffix,
    this.maxLines = 1,
    this.maxLength,
    this.onChanged,
    this.textInputAction,
    this.onSubmitted,
    this.formatters,
    this.capitalization,
    this.serifLabel = true,
    this.helper,
    this.readOnly = false,
    this.errorText,
  });

  /// Fixed-format inputs must never be auto-capitalised.
  TextCapitalization _resolveCapitalization() {
    if (capitalization != null) return capitalization!;
    if (obscure) return TextCapitalization.none;
    final t = keyboardType;
    if (t == TextInputType.emailAddress ||
        t == TextInputType.number ||
        t == TextInputType.phone ||
        t == TextInputType.url ||
        t == TextInputType.visiblePassword ||
        t == TextInputType.datetime) {
      return TextCapitalization.none;
    }
    return TextCapitalization.sentences;
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(label,
                    style: serifLabel
                        ? AiraText.serif(fontSize: 15.5, fontWeight: FontWeight.w700)
                        : AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                if (optionalTag != null) ...[
                  const SizedBox(width: 8),
                  Text(optionalTag!, style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
                ],
              ],
            ),
            const SizedBox(height: 8),
          ],
          Container(
            decoration: BoxDecoration(
              color: readOnly ? AiraColors.blush.withOpacity(0.55) : AiraColors.pinkFill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: errorText != null ? AiraColors.errorText : AiraColors.pinkBorder, width: 1.1),
            ),
            child: Row(
              crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
              children: [
                if (prefix != null) prefix!,
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: keyboardType,
                    obscureText: obscure,
                    maxLines: obscure ? 1 : maxLines,
                    maxLength: maxLength,
                    onChanged: onChanged,
                    textInputAction: textInputAction,
                    onSubmitted: onSubmitted,
                    inputFormatters: formatters,
                    textCapitalization: _resolveCapitalization(),
                    readOnly: readOnly,
                    enableInteractiveSelection: !readOnly,
                    cursorColor: AiraColors.roseDeep,
                    style: AiraText.sans(fontSize: 14.5, color: readOnly ? AiraColors.charcoalSoft : AiraColors.charcoal),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      counterText: '',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      hintText: hint,
                      hintStyle: AiraText.sans(fontSize: 14, color: AiraColors.charcoalSoft.withOpacity(0.7)),
                    ),
                  ),
                ),
                if (suffix != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    child: Align(alignment: Alignment.center, widthFactor: 1, heightFactor: 1, child: suffix!),
                  ),
              ],
            ),
          ),
          if (errorText != null) ...[
            const SizedBox(height: 5),
            Text(errorText!, style: AiraText.sans(fontSize: 11.5, color: AiraColors.errorText)),
          ],
          if (helper != null) ...[
            const SizedBox(height: 5),
            Text(helper!, style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
          ],
        ],
      ),
    );
  }
}

/// Sunndari Icon Bubble widget.
class SunndariIconBubble extends StatelessWidget {
  final IconData icon;
  final double size;
  const SunndariIconBubble({super.key, required this.icon, this.size = 44});

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: AiraColors.blush, shape: BoxShape.circle),
      child: Icon(icon, size: size * 0.48, color: AiraColors.roseDeep),
    );
  }
}

/// Aira Toast widget.
class AiraToast extends StatelessWidget {
  final String text;
  const AiraToast({super.key, required this.text});

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 96,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AiraColors.charcoal,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 30, offset: Offset(0, 10))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(color: AiraColors.success, shape: BoxShape.circle),
                child: const Icon(Icons.check, size: 11, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Text(text, style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nav Item Data.
class NavItemData {
  final IconData icon;
  final String label;
  final String key;
  const NavItemData({required this.icon, required this.label, required this.key});
}

const kNavItems = [
  NavItemData(icon: Icons.home_outlined, label: 'Home', key: 'home'),
  NavItemData(icon: Icons.calendar_today_outlined, label: 'Bookings', key: 'bookings'),
  NavItemData(icon: Icons.event_note_outlined, label: 'Calendar', key: 'calendar'),
  NavItemData(icon: Icons.bar_chart_rounded, label: 'Earnings', key: 'earnings'),
  NavItemData(icon: Icons.person_outline_rounded, label: 'Profile', key: 'profile'),
];

/// Aira Bottom Nav widget.
class AiraBottomNav extends StatelessWidget {
  final String active;
  final ValueChanged<String> onSelect;

  const AiraBottomNav({super.key, required this.active, required this.onSelect});

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        border: const Border(top: BorderSide(color: AiraColors.hair)),
        boxShadow: const [BoxShadow(color: Color(0x14C2185B), blurRadius: 14, offset: Offset(0, -4))],
      ),
      child: Row(
        children: kNavItems.map((item) {
          final isActive = active == item.key;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(item.key),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.icon, size: 22, color: isActive ? AiraColors.rose : AiraColors.charcoalSoft),
                  const SizedBox(height: 4),
                  Text(
                    item.label,
                    style: AiraText.sans(
                      fontSize: 10.5,
                      color: isActive ? AiraColors.rose : AiraColors.charcoalSoft,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Formats aira date range.
String formatAiraDateRange(DateTimeRange range) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String short(DateTime d) => '${d.day} ${months[d.month - 1]}';
  String full(DateTime d) => '${d.day} ${months[d.month - 1]} ${d.year}';
  if (range.start.year != range.end.year) {
    return '${full(range.start)} – ${full(range.end)}';
  }
  return '${short(range.start)} – ${short(range.end)}';
}

/// Lets the user pick aira date range.
Future<DateTimeRange?> pickAiraDateRange(
    BuildContext context, {
      DateTimeRange? initialRange,
      DateTime? firstDate,
      DateTime? lastDate,
    }) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return showDateRangePicker(
    context: context,
    firstDate: firstDate ?? DateTime(now.year - 3),
    lastDate: lastDate ?? today,
    initialDateRange: initialRange,
    builder: (context, child) {
      return Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AiraColors.rose,
            onPrimary: Colors.white,
            surface: AiraColors.card,
            onSurface: AiraColors.charcoal,
          ),
        ),
        child: child!,
      );
    },
  );
}

/// Aira Date Range Button widget.
class AiraDateRangeButton extends StatelessWidget {
  final DateTimeRange? range;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final String placeholder;

  const AiraDateRangeButton({
    super.key,
    required this.range,
    required this.onTap,
    this.onClear,
    this.placeholder = 'Date Range',
  });

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    final active = range != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: active ? AiraColors.blush : AiraColors.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? AiraColors.rose : AiraColors.hair),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined, size: 14, color: active ? AiraColors.roseDeep : AiraColors.charcoalSoft),
            const SizedBox(width: 6),
            Text(
              active ? formatAiraDateRange(range!) : placeholder,
              style: AiraText.sans(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: active ? AiraColors.roseDeep : AiraColors.charcoalSoft,
              ),
            ),
            if (active && onClear != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 14, color: AiraColors.roseDeep),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Seg Tab Item.
class SegTabItem {
  final String key;
  final String label;
  const SegTabItem(this.key, this.label);
}

/// Shows aira cancel reason dialog.
Future<String?> showAiraCancelReasonDialog(BuildContext context, {String clientName = '', bool isReject = false}) {
  final controller = TextEditingController();
  const presets = [
    'Not Available On This Date',
    'Not Available At This Time',
    'Personal Emergency',
  ];
  final verb = isReject ? 'Reject' : 'Cancel';

  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              '$verb booking${clientName.isNotEmpty ? ' with $clientName' : ''}?',
              style: AiraText.serif(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isReject
                      ? "Let The Client Know Why — This Is Shown To Them As The Reason You're Not Available."
                      : 'Let The Client Know Why — This Is Shown To Them As The Cancellation Reason.',
                  style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: presets.map((p) {
                    return GestureDetector(
                      onTap: () => setState(() => controller.text = p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: controller.text == p ? AiraColors.rose.withOpacity(0.12) : AiraColors.bg,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: controller.text == p ? AiraColors.rose : AiraColors.hair),
                        ),
                        child: Text(p, style: AiraText.sans(fontSize: 11.5)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 2,
                  style: AiraText.sans(fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: isReject ? 'Reason For Declining (Optional)' : 'Reason For Cancelling (Optional)',
                    hintStyle: AiraText.sans(fontSize: 13, color: AiraColors.charcoalSoft),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(isReject ? 'Keep Request' : 'Keep Booking',
                    style: AiraText.sans(fontSize: 13.5, color: AiraColors.charcoalSoft)),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
                child: Text('$verb booking',
                    style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w600, color: AiraColors.errorText)),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Aira Seg Tabs widget.
class AiraSegTabs extends StatelessWidget {
  final List<SegTabItem> tabs;
  final String active;
  final ValueChanged<String> onSelect;

  const AiraSegTabs({super.key, required this.tabs, required this.active, required this.onSelect});

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 24, bottom: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tabs
              .map((t) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AiraPill(
              label: t.label,
              active: active == t.key,
              onTap: () => onSelect(t.key),
            ),
          ))
              .toList(),
        ),
      ),
    );
  }
}
