// FILE: screens/auth/register_screen.dart
// SCREEN: Register — create a new artist account.
//
// APIs used:
//   POST /auth/phone-otp/request/
//   POST /auth/phone-otp/verify/

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/auth/phone_otp_request.dart';
import '../../models/auth/phone_otp_verify.dart';
import '../../models/enums/role_enum.dart';
import '../../theme/tokens.dart';
import '../../utils/app_feedback.dart';
import '../../utils/approval_status.dart';
import '../../utils/onboarding_progress.dart';
import '../../utils/pending_email.dart';
import '../../utils/service_locator.dart';
import '../../widgets/common.dart';
import 'post_login_router.dart';
import 'secure_account_screen.dart';

/// SCREEN: Register — create a new artist account.
class RegisterScreen extends StatefulWidget {
  final bool loginMode;
  const RegisterScreen({super.key, this.loginMode = false});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

/// State of [RegisterScreen] — holds the screen data and logic.
class _RegisterScreenState extends State<RegisterScreen> {
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _otpFocus = FocusNode();

  bool _sending = false;
  bool _verifying = false;
  bool _codeSent = false;
  bool _locked = false; // 5 wrong codes → server locks the account for 30 minutes
  int _cooldown = 0; // seconds until a new code can be requested (server allows 1 per 60 s)
  Timer? _timer;
  String? _error;

  /// Runs once when the screen opens.
  @override
  void initState() {
    super.initState();
    _otpCtrl.addListener(() => setState(() {}));
  }

  /// Frees controllers / listeners when the screen closes.
  @override
  void dispose() {
    _timer?.cancel();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  /// Starts the "Resend in Ns" countdown.
  void _startCooldown([int seconds = 60]) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown = _cooldown > 0 ? _cooldown - 1 : 0);
      if (_cooldown == 0) t.cancel();
    });
  }

  /// Validates phone.
  String? _validatePhone(String raw) {
    final digits = raw.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 10) return 'Enter A Valid 10-digit Mobile Number';
    if (!RegExp(r'^[6-9]').hasMatch(digits)) return 'Enter A Valid Indian Mobile Number';
    return null;
  }

  /// Sends code.
  /// API: authService.requestPhoneOtp → POST /auth/phone-otp/request/
  Future<void> _sendCode() async {
    if (_locked || _cooldown > 0) return;
    final phone = _phoneCtrl.text.trim();
    final problem = _validatePhone(phone);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      // API call: authService.requestPhoneOtp → POST /auth/phone-otp/request/
      await ServiceLocator.authService.requestPhoneOtp(
        PhoneOtpRequest(phoneNumber: phone, role: RoleEnum.artist),
      );
      if (!mounted) return;
      setState(() => _codeSent = true);
      _startCooldown();
      _otpFocus.requestFocus();
      AppFeedback.showSuccess(context, 'Code Sent To +91 $phone');
    } catch (e) {
      if (!mounted) return;
      final msg = AppFeedback.friendlyMessage(e);
      final low = msg.toLowerCase();
      setState(() {
        _error = msg;
        if (low.contains('locked')) _locked = true;
        // "A code was just sent; please wait a minute" → a code already exists, show the resend timer.
        if (low.contains('just sent') || low.contains('wait a minute')) _codeSent = true;
      });
      if (low.contains('just sent') || low.contains('wait a minute')) _startCooldown();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Verifies the entered code.
  /// API: authService.verifyPhoneOtp → POST /auth/phone-otp/verify/
  Future<void> _verify() async {
    if (_locked) return;
    final phone = _phoneCtrl.text.trim();
    final otp = _otpCtrl.text.trim();
    if (_validatePhone(phone) != null) {
      setState(() => _error = _validatePhone(phone));
      return;
    }
    if (!_codeSent) {
      setState(() => _error = 'Tap "Send SUNNDARI CODE" First');
      return;
    }
    if (otp.length != 6) {
      setState(() => _error = 'Enter The 6-digit Code Sent To Your Mobile');
      return;
    }
    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Enter A Valid Email Address Or Leave It Empty');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      // API call: authService.verifyPhoneOtp → POST /auth/phone-otp/verify/
      await ServiceLocator.authService.verifyPhoneOtp(PhoneOtpVerify(phoneNumber: phone, otp: otp));
      if (!mounted) return;
      if (widget.loginMode) {
        await routeAfterLogin(context);
      } else if (await _isExistingOnboardedArtist()) {
        // The number already belongs to an artist who finished onboarding (e.g. "Start Onboarding" tapped
        // by mistake) — sign them in to the right screen instead of walking them through onboarding again.
        if (!mounted) return;
        AppFeedback.showInfo(context, 'You Already Have An Account. Signing You In…');
        await routeAfterLogin(context);
      } else {
        _toSecureAccount(email, phone);
      }
    } catch (e) {
      // A wrong / expired code must never let the user in.
      if (mounted) {
        final msg = AppFeedback.friendlyMessage(e);
        setState(() {
          _error = msg;
          if (msg.toLowerCase().contains('locked')) {
            _locked = true; // disable the form and explain
          } else {
            _otpCtrl.clear(); // wrong / expired code → let the artist retype or resend
          }
        });
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  /// True when the verified number already has an approved / fully onboarded artist account.
  Future<bool> _isExistingOnboardedArtist() async {
    try {
      final profile = await ServiceLocator.artistService.getProfile();
      final kind = await resolveArtistStatusKind(profile);
      if (kind == ApprovalStatusKind.approved) return true;
      final progress = await OnboardingProgress.load(profile: profile);
      return progress.allDone;
    } catch (_) {
      return false; // unknown → keep the normal new-artist flow
    }
  }

  /// Converts to secure account.
  void _toSecureAccount(String email, String phone) {
    // The server saves an email only after a code check, so keep it for the profile's "Verify" button.
    if (email.isNotEmpty) PendingEmail.save(email);
    // Navigates to SecureAccountScreen
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SecureAccountScreen(email: email, phone: phone)));
  }

  /// UI piece: OTP boxes.
  Widget _otpBoxes() {
    final text = _otpCtrl.text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _otpFocus.requestFocus(),
      child: Stack(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (i) {
              final filled = i < text.length;
              final current = i == text.length && _otpFocus.hasFocus;
              return Container(
                width: 46,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AiraColors.pinkFill,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: current ? AiraColors.rose : AiraColors.pinkBorder,
                    width: current ? 1.8 : 1.1,
                  ),
                ),
                child: Text(filled ? text[i] : '', style: AiraText.serif(fontSize: 22)),
              );
            }),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: _otpCtrl,
                focusNode: _otpFocus,
                enabled: !_locked,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(counterText: '', border: InputBorder.none),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SunndariBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: SunndariFlowBar(
                  title: 'Contact & Verification',
                  onBack: () => Navigator.of(context).pop(),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(28, 4, 28, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Center(child: SunndariLogo(width: 120)),
                      const SizedBox(height: 10),
                      Center(
                        child: SunndariTitle(
                          title: widget.loginMode ? 'Welcome Back' : 'Let’s Get\nConnected',
                          subtitle: widget.loginMode
                              ? 'Enter Your Mobile Number To Get A SUNNDARI CODE.'
                              : 'Verify Your Mobile Number To Continue\nYour Sunndari Journey.',
                          size: 38,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SunndariField(
                        label: 'Mobile Number',
                        controller: _phoneCtrl,
                        hint: 'Enter Mobile Number',
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        formatters: [FilteringTextInputFormatter.digitsOnly],
                        prefix: Container(
                          padding: const EdgeInsets.only(left: 14, right: 10),
                          height: 26,
                          decoration: const BoxDecoration(border: Border(right: BorderSide(color: AiraColors.pinkBorder))),
                          alignment: Alignment.center,
                          child: Row(
                            children: [
                              Text('+91', style: AiraText.sans(fontSize: 14.5, fontWeight: FontWeight.w600)),
                              const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AiraColors.roseDeep),
                            ],
                          ),
                        ),
                      ),
                      GhostButton(
                        label: _sending ? 'Sending…' : (_cooldown > 0 ? 'Resend In ${_cooldown}s' : 'Send SUNNDARI CODE'),
                        expand: true,
                        onTap: (_sending || _locked || _cooldown > 0) ? null : _sendCode,
                      ),
                      const SizedBox(height: 22),
                      Text('SUNNDARI CODE', style: AiraText.serif(fontSize: 15.5)),
                      const SizedBox(height: 10),
                      _otpBoxes(),
                      const SizedBox(height: 10),
                      Center(
                        child: Text(
                          'Enter The 6-digit Code Sent To Your Mobile.',
                          style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft),
                        ),
                      ),
                      Center(
                        child: TextButton(
                          onPressed: (_sending || _locked || _cooldown > 0) ? null : _sendCode,
                          child: Text(
                            _cooldown > 0 ? 'Resend Code In ${_cooldown}s' : 'Resend Code',
                            style: AiraText.sans(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AiraColors.roseDeep,
                            ).copyWith(decoration: TextDecoration.underline),
                          ),
                        ),
                      ),
                      if (!widget.loginMode) ...[
                        const SizedBox(height: 6),
                        SunndariField(
                          label: 'Email Address',
                          optionalTag: 'Optional',
                          controller: _emailCtrl,
                          hint: 'Enter Your Email Address',
                          keyboardType: TextInputType.emailAddress,
                        ),
                      ],
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline_rounded, size: 16, color: AiraColors.errorText),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_error!,
                                    style: AiraText.sans(fontSize: 13, color: AiraColors.errorText, height: 1.35)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 4, 28, 20),
                child: PrimaryButton(
                  label: _verifying ? 'Verifying…' : 'Verify & Continue',
                  arrow: true,
                  expand: true,
                  onTap: (_verifying || _locked) ? null : _verify,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}