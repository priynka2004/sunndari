// FILE: utils/accepting_bookings.dart
// HELPERS: the "Accepting New Bookings" switch and accepting a booking request, following the
// "Going Live API" rules. The server enforces everything; the app only shows the right prompt.
//
// Server messages handled (error[0]):
//   • "Complete your registration payment before you can turn bookings on"  → opens the fee screen
//   • "Your profile must be approved by an admin before you can turn bookings on" → waiting for approval
//   • "Bookings were switched off by an admin; contact support to turn them back on" → contact support
//   • "Turn bookings on before you accept a booking request" → offers to switch bookings on

import 'package:flutter/material.dart';
import '../screens/onboarding/registration_fee_screen.dart';
import '../theme/tokens.dart';
import 'app_feedback.dart';
import 'service_locator.dart';

const String _kSupportMsg =
    'Bookings Were Switched Off By Sunndari Support. Please Contact Support To Turn Them Back On.';
const String _kApprovalMsg =
    'Your Profile Is Waiting For Admin Approval. You Can Turn Bookings On Once It Is Approved.';

/// ONE shared value for the "Accepting New Bookings" switch, so Home and Profile always show the same state.
/// null = not known yet (screens fall back to the profile they were given).
final ValueNotifier<bool?> acceptingBookingsNotifier = ValueNotifier<bool?>(null);

bool _has(Object e, String text) => e.toString().toLowerCase().contains(text);

/// Switches bookings ON / OFF. Returns true only when the server accepted the change.
/// [lockedByAdmin] comes from GET /artists/profile/get/ (`acceptingLockedByAdmin`).
/// API: PUT /artists/profile/accepting_bookings/
Future<bool> changeAcceptingBookings(BuildContext context, bool value, {bool lockedByAdmin = false}) async {
  if (value && lockedByAdmin) {
    AppFeedback.showWarning(context, _kSupportMsg);
    return false;
  }
  // Fee still due → opens the (closable) payment screen first; true only after it is paid.
  if (value && !await ensureFeePaidToAcceptBookings(context)) return false;
  if (!context.mounted) return false;
  try {
    await ServiceLocator.artistBusiness.setAcceptingBookings(value);
    acceptingBookingsNotifier.value = value;
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    if (_has(e, 'registration payment')) {
      // The server says the fee is still owed → pay, then try once more.
      final fee = await pendingRegistrationFee();
      if (fee != null && context.mounted) {
        final paid = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => RegistrationFeeScreen(fee: fee, canClose: true)),
        );
        if (paid == true && context.mounted) {
          try {
            await ServiceLocator.artistBusiness.setAcceptingBookings(value);
            acceptingBookingsNotifier.value = value;
            return true;
          } catch (e2) {
            if (context.mounted) AppFeedback.showError(context, e2);
          }
        }
        return false;
      }
    }
    if (_has(e, 'approved by an admin')) {
      AppFeedback.showInfo(context, _kApprovalMsg);
    } else if (_has(e, 'switched off by an admin')) {
      AppFeedback.showWarning(context, _kSupportMsg);
    } else {
      AppFeedback.showError(context, e);
    }
    return false;
  }
}

/// Call this from the catch of "accept a booking request" (PUT /artists/bookings/update_status/).
/// If the server refused because the artist's own switch is off, it offers to switch bookings on.
/// Returns null when [error] is something else (the caller shows it as usual), true when bookings were
/// switched on (the artist should accept the request again), false when the artist said no / it failed.
Future<bool?> offerTurnOnBookings(BuildContext context, Object error) async {
  if (!_has(error, 'turn bookings on before you accept')) return null;
  if (!context.mounted) return false;
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AiraColors.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text('Bookings Are Off', style: AiraText.serif(fontSize: 19)),
      content: const Text('Turn Bookings On To Accept This Request.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Not Now')),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('Turn On', style: AiraText.sans(fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
        ),
      ],
    ),
  );
  if (yes != true || !context.mounted) return false;
  final ok = await changeAcceptingBookings(context, true);
  if (ok && context.mounted) {
    AppFeedback.showSuccess(context, 'Bookings Are On ✓ Please Accept The Request Again.');
  }
  return ok;
}