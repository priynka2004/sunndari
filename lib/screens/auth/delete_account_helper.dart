// FILE: screens/auth/delete_account_helper.dart
// "Delete Account" flow for the ARTIST app (required by Apple 5.1.1(v) and Google Play).
//
//   Settings -> Delete Account -> confirm (type DELETE) -> DELETE /artists/account/delete/?user_id=<own id>
//   -> same cleanup as Log Out (push/notification state + session) -> Login screen.
//
// The account is only treated as deleted AFTER the server says so. If the server refuses
// (e.g. upcoming bookings or a pending payout) its message is shown inside the dialog and
// nothing is changed.

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../utils/app_feedback.dart';
import '../../utils/nav_key.dart';
import '../../utils/service_locator.dart';
import 'logout_helper.dart';

const String _kConfirmWord = 'DELETE';

/// Shows the confirmation, deletes the account and returns to Login.
/// Returns true if the account was deleted.
Future<bool> confirmAndDeleteAccount(BuildContext context) async {
  final deleted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _DeleteAccountDialog(),
  );
  if (deleted != true) return false;

  // The account is already gone on the server, so we must always finish by leaving the app's
  // signed-in area, even if the Settings screen was closed in the meantime.
  final ctx = context.mounted ? context : navigatorKey.currentContext;
  if (ctx == null) return true;

  // Session is still present here on purpose: performLogout() needs the userId to switch off
  // this device's push token before it clears the session and opens the Login screen.
  await performLogout(ctx);

  // performLogout() replaced the whole route stack, so the toast uses the app-wide navigator's
  // context (still mounted) instead of the Settings screen's context (gone).
  final rootContext = navigatorKey.currentContext;
  if (rootContext != null) {
    AppFeedback.showSuccess(rootContext, 'Your Account Has Been Deleted.');
  }
  return true;
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final TextEditingController _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _confirmed => _ctrl.text.trim().toUpperCase() == _kConfirmWord;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!_confirmed || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ServiceLocator.userService.deleteAccount(); // DELETE /artists/account/delete/?user_id=<own id>
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppFeedback.friendlyMessage(e,
            fallback: 'Could Not Delete Your Account Right Now. Please Try Again.');
      });
    }
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 7, right: 8),
              child: Icon(Icons.circle, size: 5, color: AiraColors.charcoalSoft),
            ),
            Expanded(
              child: Text(text, style: AiraText.sans(fontSize: 13.5, color: AiraColors.charcoal, height: 1.35)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy, // never let the artist back out while the request is running
      child: AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AiraColors.rose),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Delete Account?', style: AiraText.serif(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Artist Account Will Be Switched Off And You Will Be Signed Out. '
                'Clients Will No Longer Be Able To Find Or Book You.',
                style: AiraText.sans(fontSize: 13.5, color: AiraColors.charcoalSoft, height: 1.4),
              ),
              const SizedBox(height: 10),
              _bullet('Your profile, portfolio and services are hidden from clients'),
              _bullet('Your bookings are switched off'),
              _bullet('Your history (bookings, reviews, payments) is kept'),
              const SizedBox(height: 4),
              Text(
                'You Can Come Back Anytime: Sign In With The Same Mobile Number And Choose Artist. '
                'After You Return, Switch Bookings On To Be Visible Again.',
                style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft, height: 1.4),
              ),
              const SizedBox(height: 6),
              Text(
                'A Paid, Confirmed Or In-Progress Booking Must Be Completed Or Cancelled First.',
                style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft, height: 1.4),
              ),
              const SizedBox(height: 14),
              Text('Type DELETE To Confirm',
                  style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w700, color: AiraColors.charcoal)),
              const SizedBox(height: 6),
              TextField(
                controller: _ctrl,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
                style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: _kConfirmWord,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AiraColors.rose, width: 1.5),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: AiraText.sans(fontSize: 13, color: const Color(0xFFD64545), height: 1.3)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: Text('Cancel',
                style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w600, color: AiraColors.charcoalSoft)),
          ),
          ElevatedButton(
            onPressed: (_confirmed && !_busy) ? _delete : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD64545),
              disabledBackgroundColor: AiraColors.hair,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text('Delete Account',
                    style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
