// FILE: screens/onboarding/registration_fee_screen.dart
// SCREEN: Registration Fee — the one-time Sunndari registration fee (GST included), paid in onboarding BEFORE the
// profile is submitted for admin review. A promo code (100 / 75 / 50 / 25 %) can be applied.
//
// Rules from the backend guide ("Artist Registration Fee API"):
//   • The app never sends or calculates an amount or discount — it shows the figures the server returns.
//   • Starting a payment does not mark the fee paid; only POST payment/verify (or a 100 % code) does.
//   • Paying does not approve the artist — the profile still goes to admin review after submit.
//
// APIs: GET /artists/registration/fee/ · POST /artists/registration/promo/validate/ ·
//       POST /artists/registration/payment/initiate/ · POST /artists/registration/payment/verify/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/artist/registration_fee.dart';
import '../../theme/tokens.dart';
import '../../utils/app_feedback.dart';
import '../../utils/razorpay_checkout_service.dart';
import '../../utils/service_locator.dart';
import '../../widgets/common.dart';
import '../auth/logout_helper.dart';
import '../auth/post_login_router.dart';

/// WHEN the fee is demanded.
///  true  = before the profile is submitted for admin review (old backend rule).
///  false = only when the artist switches "Accepting New Bookings" ON (Home / Profile). This is the current
///          "Going Live API" rule: the fee is no longer needed to submit or to be approved; an unpaid artist
///          stays hidden and cannot switch bookings on until the fee is paid.
const bool kRegistrationFeeBeforeSubmit = false;

/// "Accepting New Bookings" switch: returns true when bookings may be switched on. If the fee is still due, opens
/// the (closable) fee screen and returns true only after the payment succeeds.
Future<bool> ensureFeePaidToAcceptBookings(BuildContext context) async {
  final fee = await pendingRegistrationFee();
  if (fee == null) return true;
  if (!context.mounted) return false;
  final paid = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => RegistrationFeeScreen(fee: fee, canClose: true)),
  );
  return paid == true;
}

/// The fee details when this artist still has to pay (null = nothing to pay, or the status could not be read —
/// the server then refuses an unpaid submit anyway).
Future<RegistrationFee?> pendingRegistrationFee() async {
  try {
    final fee = await ServiceLocator.artistBusiness.getRegistrationFee();
    return fee.registrationRequired ? fee : null;
  } catch (_) {
    return null;
  }
}

/// Opens the fee screen when this artist still has to pay. Returns true when there is nothing (more) to pay.
/// If the fee status cannot be read, it returns true and lets the server decide at submit (it refuses an unpaid fee).
Future<bool> ensureRegistrationFeePaid(BuildContext context) async {
  final RegistrationFee fee;
  try {
    fee = await ServiceLocator.artistBusiness.getRegistrationFee();
  } catch (_) {
    return true;
  }
  if (!fee.registrationRequired) return true;
  if (!context.mounted) return false;
  final paid = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => RegistrationFeeScreen(fee: fee)),
  );
  return paid == true;
}

/// SCREEN: Registration Fee.
class RegistrationFeeScreen extends StatefulWidget {
  final RegistrationFee fee;

  /// true = opened as the artist's home screen (app start / login): after paying it routes onward by itself.
  /// false = pushed from the submit step: after paying it returns `true` to the caller.
  final bool standalone;

  /// true = the artist may close the screen without paying (used from the "Accepting New Bookings" switch).
  final bool canClose;
  const RegistrationFeeScreen({super.key, required this.fee, this.standalone = false, this.canClose = false});

  @override
  State<RegistrationFeeScreen> createState() => _RegistrationFeeScreenState();
}

class _RegistrationFeeScreenState extends State<RegistrationFeeScreen> {
  final _promoCtrl = TextEditingController();
  final _razorpay = RazorpayCheckoutService();
  PromoPreview? _promo;
  String? _promoError;
  bool _applying = false;
  bool _busy = false;

  @override
  void dispose() {
    _razorpay.dispose();
    _promoCtrl.dispose();
    super.dispose();
  }

  double get _fee => widget.fee.feeAmount;
  double get _discount => _promo?.discountAmount ?? 0;
  double get _payable => _promo?.payableAmount ?? _fee;
  bool get _free => _promo != null && !_promo!.requiresPayment;

  /// ₹1,999 / ₹1,99,999 (Indian digit grouping); paise shown only when present.
  String _inr(double v) {
    final whole = v == v.roundToDouble();
    final parts = (whole ? v.toStringAsFixed(0) : v.toStringAsFixed(2)).split('.');
    final digits = parts[0];
    var grouped = digits;
    if (digits.length > 3) {
      final last3 = digits.substring(digits.length - 3);
      var r = digits.substring(0, digits.length - 3);
      final groups = <String>[];
      while (r.length > 2) {
        groups.insert(0, r.substring(r.length - 2));
        r = r.substring(0, r.length - 2);
      }
      if (r.isNotEmpty) groups.insert(0, r);
      grouped = '${groups.join(',')},$last3';
    }
    return '₹$grouped${parts.length > 1 ? '.${parts[1]}' : ''}';
  }

  /// Previews a promo code (records nothing on the server).
  Future<void> _applyPromo() async {
    final code = _promoCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _promoError = 'Please Enter A Promo Code.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _applying = true;
      _promoError = null;
    });
    try {
      final p = await ServiceLocator.artistBusiness.validatePromoCode(code);
      if (!mounted) return;
      setState(() => _promo = p);
      AppFeedback.showSuccess(context, 'Promo Code Applied');
    } catch (e) {
      // The server's message says why (invalid, expired, already used, fully redeemed …).
      if (mounted) {
        setState(() {
          _promo = null;
          _promoError = AppFeedback.friendlyMessage(e, fallback: 'This Promo Code Cannot Be Applied.');
        });
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _removePromo() => setState(() {
        _promo = null;
        _promoError = null;
        _promoCtrl.clear();
      });

  /// Asks the server whether the fee is already settled (webhook, earlier attempt, exempt…).
  Future<bool> _alreadySettled() async {
    try {
      final f = await ServiceLocator.artistBusiness.getRegistrationFee();
      return f.paid || f.exempt || !f.registrationRequired;
    } catch (_) {
      return false;
    }
  }

  void _done() {
    if (!mounted) return;
    AppFeedback.showSuccess(context, 'Registration Fee Paid ✓');
    if (widget.standalone) {
      routeAfterLogin(context); // continue to the page builder / review / app
    } else {
      Navigator.of(context).pop(true);
    }
  }

  /// initiate → (Razorpay Checkout → verify) — or finished at once for a 100 % code.
  Future<void> _pay() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final biz = ServiceLocator.artistBusiness;
      final RegistrationPaymentInit init;
      try {
        init = await biz.initiateRegistrationPayment(promoCode: _promo != null ? _promoCtrl.text : null);
      } catch (e) {
        // "Already paid / does not apply" → just move on; anything else → show the server's message.
        if (await _alreadySettled()) {
          _done();
          return;
        }
        if (mounted) AppFeedback.showError(context, e, onRetry: _pay);
        return;
      }
      if (!mounted) return;

      if (init.fullyCoveredByPromo) {
        _done(); // fee already paid — no Razorpay, no verify
        return;
      }
      if (init.gatewayOrderId == null || init.razorpayKeyId == null) {
        AppFeedback.showWarning(context, 'Payment Could Not Be Started. Please Try Again.');
        return;
      }

      final outcome = await _razorpay.openCheckout(
        description: 'Sunndari Registration Fee',
        gatewayOrderId: init.gatewayOrderId!,
        razorpayKeyId: init.razorpayKeyId!,
        amountInPaise: init.amountPaise,
        currency: init.currency,
      );
      if (!mounted) return;
      if (!outcome.success) {
        // Nothing was charged and nothing to verify.
        AppFeedback.showInfo(
          context,
          outcome.errorCode == 2 ? 'Payment Cancelled. You Can Try Again Any Time.' : (outcome.errorMessage ?? 'Payment Failed. Please Try Again.'),
        );
        return;
      }

      try {
        await biz.verifyRegistrationPayment(
          razorpayOrderId: outcome.razorpayOrderId!,
          razorpayPaymentId: outcome.razorpayPaymentId!,
          razorpaySignature: outcome.razorpaySignature!,
        );
        _done();
      } catch (e) {
        // Paid but not confirmed yet (gateway delay) → the webhook settles it; check the status again.
        for (var i = 0; i < 3; i++) {
          await Future.delayed(const Duration(seconds: 3));
          if (!mounted) return;
          if (await _alreadySettled()) {
            _done();
            return;
          }
        }
        if (mounted) {
          AppFeedback.showError(
            context,
            e,
            fallback: 'We Could Not Confirm Your Payment Yet. If Money Was Deducted, It Will Be Confirmed Automatically — Please Reopen The App In A Few Minutes.',
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: AiraText.sans(fontSize: bold ? 15 : 13.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color ?? AiraColors.charcoal)),
            ),
            Text(value,
                style: AiraText.sans(fontSize: bold ? 18 : 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color ?? AiraColors.charcoal)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final applied = _promo != null;
    // The screen cannot be left until the fee is paid (the system back button is blocked too).
    return PopScope(
      canPop: widget.canClose,
      child: Scaffold(
      backgroundColor: AiraColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                children: [
                  if (widget.canClose)
                    SunndariAppBar(onBack: () => Navigator.of(context).pop(false))
                  else
                    const SizedBox(height: 16),
                  const SunndariTitle(
                    title: 'Registration\nFee',
                    subtitle: 'Pay The One-Time Registration Fee To Submit Your Profile For Review.',
                    size: 32,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AiraColors.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AiraColors.hair),
                    ),
                    child: Column(
                      children: [
                        _row('Registration Fee (GST Included)', _inr(_fee)),
                        if (applied)
                          _row('Promo Discount (${_promo!.discountPercent.toStringAsFixed(_promo!.discountPercent % 1 == 0 ? 0 : 2)}%)',
                              '- ${_inr(_discount)}',
                              color: const Color(0xFF1F9254)),
                        const Divider(height: 20, color: AiraColors.hair),
                        _row('Amount To Pay', _free ? 'Free' : _inr(_payable), bold: true, color: AiraColors.roseDeep),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('PROMO CODE', style: AiraText.sans(fontSize: 12, fontWeight: FontWeight.w600, color: AiraColors.charcoalSoft)),
                  const SizedBox(height: 8),
                  if (applied)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9F6EE),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF1F9254)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 20, color: Color(0xFF1F9254)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${(_promo!.promoCode.isNotEmpty ? _promo!.promoCode : _promoCtrl.text).toUpperCase()} Applied',
                              style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1F9254)),
                            ),
                          ),
                          TextButton(onPressed: _busy ? null : _removePromo, child: const Text('Remove')),
                        ],
                      ),
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AiraColors.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _promoError != null ? AiraColors.errorText : AiraColors.hair),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: TextField(
                              controller: _promoCtrl,
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_-]')), LengthLimitingTextInputFormatter(40)],
                              style: AiraText.sans(fontSize: 15),
                              onChanged: (_) {
                                if (_promoError != null) setState(() => _promoError = null);
                              },
                              onSubmitted: (_) => _applyPromo(),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: 'Enter Promo Code',
                                hintStyle: AiraText.sans(fontSize: 14, color: AiraColors.charcoalSoft),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 50,
                          child: PrimaryButton(label: _applying ? '…' : 'Apply', small: true, onTap: (_applying || _busy) ? null : _applyPromo),
                        ),
                      ],
                    ),
                  if (_promoError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Text(_promoError!, style: AiraText.sans(fontSize: 12, color: AiraColors.errorText)),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 16, color: AiraColors.charcoalSoft),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You Can Submit Your Profile For Review Only After The Fee Is Paid. Paying Does Not Approve Your Profile — Our Team Still Reviews It.',
                          style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PrimaryButton(
                    label: _busy ? 'Please Wait…' : (_free ? 'Continue — Free' : 'Pay ${_inr(_payable)}'),
                    expand: true,
                    onTap: _busy ? null : _pay,
                  ),
                  if (!widget.canClose)
                    TextButton(
                      onPressed: _busy ? null : () => confirmAndLogout(context),
                      child: Text('Log Out',
                          style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w600, color: AiraColors.errorText)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
