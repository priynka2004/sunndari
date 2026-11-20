// FILE: widgets/change_contact_sheet.dart
// WIDGET: bottom sheet to change the login email or phone number with a 6-digit code.
//
// APIs used:
//   POST /users/contact/change/request/   (code is sent to the NEW contact; valid 10 min; 1 request / minute)
//   POST /users/contact/change/verify/    (5 wrong tries burn the code → request a new one)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import '../utils/app_feedback.dart';
import '../utils/service_locator.dart';
import 'common.dart';

/// Opens the change-contact flow. Returns true when the contact was replaced.
Future<bool> showChangeContactSheet(BuildContext context, {required bool isEmail, String? initialValue}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AiraColors.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _ChangeContactSheet(isEmail: isEmail, initialValue: initialValue),
  );
  return ok == true;
}

class _ChangeContactSheet extends StatefulWidget {
  final bool isEmail;
  final String? initialValue;
  const _ChangeContactSheet({required this.isEmail, this.initialValue});

  @override
  State<_ChangeContactSheet> createState() => _ChangeContactSheetState();
}

class _ChangeContactSheetState extends State<_ChangeContactSheet> {
  final _value = TextEditingController();
  final _otp = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  int _cooldown = 0; // seconds until another code can be requested (server allows one per minute)
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if ((widget.initialValue ?? '').isNotEmpty) _value.text = widget.initialValue!;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _value.dispose();
    _otp.dispose();
    super.dispose();
  }

  String get _label => widget.isEmail ? 'Email Address' : 'Phone Number';

  String? _validate() {
    final v = _value.text.trim();
    if (widget.isEmail) {
      if (!RegExp(r'^[\w\.\-\+]+@[\w\-]+\.[A-Za-z]{2,}$').hasMatch(v)) return 'Please Enter A Valid Email Address.';
    } else {
      final d = v.replaceAll(RegExp(r'[^0-9]'), '');
      if (d.length != 10 || !RegExp(r'^[6-9]').hasMatch(d)) return 'Please Enter A Valid 10-digit Mobile Number.';
    }
    return null;
  }

  void _startCooldown() {
    _cooldown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  /// API: POST /users/contact/change/request/ — send exactly ONE of email / phone_number.
  Future<void> _request() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final v = _value.text.trim();
      final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
      await ServiceLocator.artistBusiness.requestContactChange(
        email: widget.isEmail ? v : null,
        phoneNumber: widget.isEmail ? null : digits,
      );
      if (!mounted) return;
      setState(() => _codeSent = true);
      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      final msg = AppFeedback.friendlyMessage(e);
      // Server allows one code per minute: a code was already sent, so let the user type it.
      if (msg.toLowerCase().contains('just sent') || msg.toLowerCase().contains('wait a minute')) {
        setState(() => _codeSent = true);
        _startCooldown();
      } else {
        setState(() => _error = msg);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// API: POST /users/contact/change/verify/ — the old contact keeps working until this succeeds.
  Future<void> _verify() async {
    final code = _otp.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter The 6-digit Code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ServiceLocator.artistBusiness.verifyContactChange(code);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = AppFeedback.friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Change $_label', style: AiraText.serif(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            _codeSent
                ? 'Enter The 6-digit Code We Sent To Your New $_label. It Is Valid For 10 Minutes.'
                : "We'll Send A 6-digit Code To Your New $_label. Your Current One Keeps Working Until You Verify.",
            style: AiraText.sans(fontSize: 13, color: AiraColors.charcoalSoft),
          ),
          const SizedBox(height: 16),
          if (!_codeSent)
            SunndariField(
              label: widget.isEmail ? 'New Email' : 'New Phone Number',
              controller: _value,
              hint: widget.isEmail ? 'name@example.com' : '10-digit Mobile Number',
              keyboardType: widget.isEmail ? TextInputType.emailAddress : TextInputType.phone,
              formatters: widget.isEmail ? null : [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            )
          else
            SunndariField(
              label: 'Verification Code',
              controller: _otp,
              hint: '6-digit Code',
              keyboardType: TextInputType.number,
              formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!, style: AiraText.sans(fontSize: 12.5, color: AiraColors.errorText)),
          ],
          const SizedBox(height: 14),
          PrimaryButton(
            label: _busy ? 'Please Wait…' : (_codeSent ? 'Verify & Change' : 'Send Code'),
            expand: true,
            onTap: _busy ? null : (_codeSent ? _verify : _request),
          ),
          if (_codeSent)
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: (_busy || _cooldown > 0) ? null : _request,
                child: Text(_cooldown > 0 ? 'Resend Code In ${_cooldown}s' : 'Resend Code'),
              ),
            ),
        ],
      ),
    );
  }
}
