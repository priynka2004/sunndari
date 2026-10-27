// FILE: screens/home_screen.dart
// SCREEN: Home tab ("My Business") — accepting-bookings switch, profile-complete nudge, business overview numbers, quick actions.

import 'package:flutter/material.dart';
import '../models/artist/artist_profile.dart';
import '../models/booking/booking.dart'; // Added to use BookingSlot
import '../models/models.dart';
import '../theme/tokens.dart';
import '../utils/app_feedback.dart';
import '../widgets/common.dart';
import 'business_details_screen.dart';
import '../utils/service_locator.dart';
import 'edit_profile_screen.dart';

/// SCREEN: Home tab ("My Business") — accepting-bookings switch, profile-complete nudge, business overview numbers, quick actions.
class HomeScreen extends StatefulWidget {
  final void Function(String target, [String? tab]) onNavigate;
  final String artistName;
  final String dateLabel;
  final int bookingsThisMonth;
  final double expectedEarningsToday;
  final int pendingConfirmations;
  final double avgRating;
  final String briefingText;
  final bool loading;
  final bool showCompleteProfileBanner;
  final VoidCallback? onCompleteProfile;
  final String? profileHint;
  final List<BookingSlot> todaysBookings; // New parameter for today's schedule
  final bool acceptingBookings; // current Accept Booking switch value from the profile

  const HomeScreen({
    super.key,
    required this.onNavigate,
    this.artistName = '',
    this.dateLabel = '',
    this.bookingsThisMonth = 0,
    this.expectedEarningsToday = 0,
    this.pendingConfirmations = 0,
    this.avgRating = 0,
    this.briefingText = '',
    this.loading = false,
    this.showCompleteProfileBanner = false,
    this.onCompleteProfile,
    this.profileHint,
    this.todaysBookings = const [], // Default to empty list
    this.acceptingBookings = true,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// State of [HomeScreen] — holds the screen data and logic.
class _HomeScreenState extends State<HomeScreen> {
  late bool _accepting = widget.acceptingBookings;

  @override
  void didUpdateWidget(covariant HomeScreen old) {
    super.didUpdateWidget(old);
    if (old.acceptingBookings != widget.acceptingBookings) _accepting = widget.acceptingBookings;
  }

  /// Turns new bookings on / off (same switch as Profile).
  /// API: artistBusiness.setAcceptingBookings → PUT /artists/profile/accepting_bookings/
  Future<void> _toggleAccepting(bool v) async {
    final before = _accepting;
    setState(() => _accepting = v);
    try {
      await ServiceLocator.artistBusiness.setAcceptingBookings(v);
    } catch (e) {
      if (mounted) {
        setState(() => _accepting = before);
        AppFeedback.showError(context, e);
      }
    }
  }

  /// UI piece: Accept Booking toggle card.
  Widget _acceptToggle() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
    child: AiraCard(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeColor: AiraColors.rose,
        title: Text('Accepting New Bookings',
            style: AiraText.sans(fontSize: 15, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
        subtitle: Text(
          _accepting ? 'Clients Can Find And Book You.' : 'Hidden From Search. Existing Bookings Are Not Affected.',
          style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft),
        ),
        value: _accepting,
        onChanged: _toggleAccepting,
      ),
    ),
  );

  /// Status pill for a Today's Schedule row.
  /// Same Missed rule as the Bookings screen (so both always agree):
  /// - Pending request: Missed once the appointment time has passed.
  /// - Confirmed, service never started (no OTP start): Missed once time (+2h grace to tap "On my way") has passed.
  /// - Service started (In Progress) but never completed after the day is over: needs Customer Care.
  /// - Completed / Cancelled / No-show: shown as they are.
  (String, Color, Color) _statusPill(BookingSlot s) {
    const green = Color(0xFFE3F5EA);
    final start = s.startDateTime;
    final pendingPassed = s.status == SlotStatus.pending &&
        (s.isPastDate || (start != null && !DateTime.now().isBefore(start)));
    final confirmedMissed = s.status == SlotStatus.confirmed && s.isMissed;

    if (pendingPassed || confirmedMissed) return ('Missed', AiraColors.errorBg, AiraColors.errorText);
    if (s.status == SlotStatus.inProgress && s.isPastDate) {
      return ('Needs Support', AiraColors.errorBg, AiraColors.errorText);
    }
    return switch (s.status) {
      SlotStatus.confirmed => ('Confirmed', green, AiraColors.success),
      SlotStatus.inProgress => ('In Progress', green, AiraColors.success),
      SlotStatus.completed => ('Completed', green, AiraColors.success),
      SlotStatus.noShow => ('No Show', AiraColors.pinkFill, AiraColors.roseDeep),
      SlotStatus.cancelled => ('Cancelled', AiraColors.pinkFill, AiraColors.roseDeep),
      _ => ('Pending', AiraColors.pinkFill, AiraColors.roseDeep),
    };
  }

  /// UI piece: section title.
  Widget _sectionTitle(String text, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
    child: Row(
      children: [
        Text(text, style: AiraText.serif(fontSize: 18)),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    ),
  );

  /// UI piece: stat tile.
  Widget _statTile(IconData icon, String label, String value) => Expanded(
    child: AiraCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(
        children: [
          SunndariIconBubble(icon: icon, size: 36),
          const SizedBox(height: 8),
          Text(label, style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
          const SizedBox(height: 2),
          Text(widget.loading ? '—' : value, style: AiraText.sans(fontSize: 22, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
        ],
      ),
    ),
  );

  /// UI piece: empty card.
  Widget _emptyCard(IconData icon, String title, String sub) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: AiraCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SunndariIconBubble(icon: icon, size: 40),
          const SizedBox(width: 14),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                const SizedBox(height: 2),
                Text(sub, style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    final showNumbers = !widget.showCompleteProfileBanner;

    return SunndariBackground(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SunndariTabHeader(title: 'My Business', subtitle: 'Let’s Grow Your Beauty Business.'),

          // ==========================================
          // 1. Profile banner (the accepting-bookings switch lives only in Profile → it is the one that works)
          // ==========================================
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: widget.showCompleteProfileBanner
                ? AiraCard(
              gradient: AiraGradients.button,
              borderWidth: 0,
              padding: const EdgeInsets.all(18),
              onTap: widget.onCompleteProfile,
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                    child: const Icon(Icons.person_add_alt_1_outlined, size: 22, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Complete Your Profile',
                            style: AiraText.serif(fontSize: 17, color: Colors.white)),
                        const SizedBox(height: 3),
                        Text(
                          widget.profileHint ?? 'Add Your Photo, Services & Gallery So Clients Can Find And Book You.',
                          style: AiraText.sans(fontSize: 12.5, color: Colors.white.withOpacity(0.92), height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white),
                ],
              ),
            )
                : (widget.bookingsThisMonth > 0 || widget.pendingConfirmations > 0)
                ? const SizedBox.shrink()
                : AiraCard(
              gradient: const LinearGradient(colors: [Color(0xFFFFDCE5), Color(0xFFFFEFF3)]),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('You’re Ready For Your First Booking!', style: AiraText.sans(fontSize: 15.5, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
                  const SizedBox(height: 4),
                  Text('Keep Your Services, Portfolio And Availability Updated So Clients Can Discover You.',
                      style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft, height: 1.4)),
                ],
              ),
            ),
          ),

          _acceptToggle(),

          // ==========================================
          // 2. Today’s Schedule (Moved Up & Detailed UI added)
          // ==========================================
          _sectionTitle('Today’s Schedule', trailing: null),
          if (widget.todaysBookings.isEmpty)
            _emptyCard(Icons.calendar_today_outlined, 'No Bookings Scheduled Today',
                widget.briefingText.isEmpty ? 'Your Day Is Clear. Enjoy The Time!' : widget.briefingText)
          else
            Column(
              children: widget.todaysBookings.map((slot) => Padding(
                padding: const EdgeInsets.only(left: 20, right: 20, bottom: 12),
                child: AiraCard(
                  // When tapped, it navigates to the booking details or calendar tab
                  onTap: () => widget.onNavigate('booking_detail', slot.bookingId.toString()),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      // Left Side: Time Box
                      Container(
                        width: 70,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.only(right: 12),
                        decoration: const BoxDecoration(
                          border: Border(right: BorderSide(color: AiraColors.hair)),
                        ),
                        child: Text(
                          slot.time,
                          style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w800, color: AiraColors.roseDeep, height: 1.2),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Right Side: Booking Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(slot.client, style: AiraText.sans(fontSize: 15.5, fontWeight: FontWeight.w700, color: AiraColors.charcoal)),
                            const SizedBox(height: 2),
                            Text(slot.service, style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
                            const SizedBox(height: 4),
                            // Small Status Pill (shows the REAL status, not just Confirmed/Pending)
                            Builder(builder: (_) {
                              final (label, bg, fg) = _statusPill(slot);
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
                                child: Text(label,
                                    style: AiraText.sans(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
                              );
                            }),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: AiraColors.rose, size: 22),
                    ],
                  ),
                ),
              )).toList(),
            ),

          // ==========================================
          // 3. New Booking Requests
          // ==========================================
          _sectionTitle(
            'New Booking Requests',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AiraColors.blush, borderRadius: BorderRadius.circular(10)),
              child: Text('${widget.pendingConfirmations}',
                  style: AiraText.sans(fontSize: 11.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
            ),
          ),
          widget.pendingConfirmations == 0
              ? _emptyCard(Icons.event_note_outlined, 'No New Requests Yet', 'New Requests Will Appear Here.')
              : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AiraCard(
              onTap: () => widget.onNavigate('bookings'),
              child: Row(
                children: [
                  const SunndariIconBubble(icon: Icons.event_available_outlined, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You Have ${widget.pendingConfirmations} Request${widget.pendingConfirmations == 1 ? '' : 's'} Waiting For You',
                      style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w700, color: AiraColors.roseDeep),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AiraColors.rose),
                ],
              ),
            ),
          ),

          // ==========================================
          // 4. Business Overview (Moved Down)
          // ==========================================
          if (showNumbers) ...[
            _sectionTitle('Business Overview'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _statTile(Icons.calendar_month_outlined, 'Total Bookings', '${widget.bookingsThisMonth}'),
                  const SizedBox(width: 10),
                  _statTile(Icons.currency_rupee_rounded, 'Earnings', '₹${widget.expectedEarningsToday.toStringAsFixed(0)}'),
                  const SizedBox(width: 10),
                  _statTile(Icons.access_time_rounded, 'Upcoming', '${widget.pendingConfirmations}'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}