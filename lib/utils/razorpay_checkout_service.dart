import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:razorpay_flutter/razorpay_flutter.dart';

/// Outcome of a single Razorpay Checkout attempt for one booking's
/// — returned by [RazorpayCheckoutService.openCheckout].
class RazorpayCheckoutOutcome {
  final bool success;
  final String? razorpayOrderId;
  final String? razorpayPaymentId;
  final String? razorpaySignature;

  /// Human-readable reason. For a failure this is Checkout's own
  /// `response.message` — safe to show directly (per the guide's Error
  /// handling reference). Null on success.
  final String? errorMessage;

  /// Razorpay's numeric error code (e.g. 2 = payment cancelled by the
  /// user). Null on success.
  final int? errorCode;

  const RazorpayCheckoutOutcome.success({
    required this.razorpayOrderId,
    required this.razorpayPaymentId,
    required this.razorpaySignature,
  })  : success = true,
        errorMessage = null,
        errorCode = null;

  const RazorpayCheckoutOutcome.failure({this.errorMessage, this.errorCode})
      : success = false,
        razorpayOrderId = null,
        razorpayPaymentId = null,
        razorpaySignature = null;
}

/// Thin wrapper around the `razorpay_flutter` plugin that turns its
/// event-callback API into a plain awaitable [openCheckout] call, per
/// the Payments · Flutter guide's "Step 2 — Open Razorpay Checkout".
///
/// A brand-new `Razorpay()` instance is created for EVERY [openCheckout]
/// call and cleared right after it resolves — reusing one long-lived
/// instance across back-to-back checkouts (e.g. paying for a 2-item cart)
/// was seen to sometimes leave the native side in a bad state and throw
/// Razorpay's own generic "Something went wrong" native error screen on
/// the second open, before the checkout page even loaded. One instance
/// per attempt avoids that. Calls MUST still be awaited one at a time —
/// never call [openCheckout] again before the previous call's future has
/// completed.
class RazorpayCheckoutService {
  Completer<RazorpayCheckoutOutcome>? _pending;
  Razorpay? _current;
  // Only true once at least one checkout has already run in this
  // service's lifetime — used to skip the inter-checkout settle delay
  // below for the very first (and, for a single-item cart, only)
  // payment, so a normal single booking pays as fast as Razorpay itself
  // allows instead of always eating an extra fixed delay.
  bool _hasOpenedBefore = false;

  /// Opens Checkout with the values from POST /initiate/ and resolves
  /// once the customer's attempt actually finishes (success or error).
  /// Passing [gatewayOrderId] pins the amount server-side on Razorpay's
  /// end — the Checkout UI cannot be tampered with client-side to charge
  /// a different amount, regardless of what's displayed in the app.
  ///
  /// [isAutoRetry] is internal-only (never pass it from a caller): set
  /// when this call is itself the one automatic retry after a
  /// suspiciously-fast failure — see the note above the retry check
  /// below. It exists purely so that failure can only ever trigger ONE
  /// silent retry, never an infinite loop of them.
  Future<RazorpayCheckoutOutcome> openCheckout({
    required String description,
    required String gatewayOrderId,
    required String razorpayKeyId,
    required int amountInPaise,
    required String currency,
    String name = 'Sunndari',
    String contact = '',
    String email = '',
    bool isAutoRetry = false,
  }) async {
    // Tear down any previous instance first (belt-and-braces — normally
    // already cleared right after its own future completed below).
    _current?.clear();
    _current = null;

    final razorpay = Razorpay();
    _current = razorpay;
    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onError);
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);

    // A gap before opening lets the PREVIOUS checkout's native
    // activity/webview fully finish tearing down before a new one is
    // launched — opening immediately back-to-back is what triggered the
    // native "Something went wrong" error screen on the 2nd+ attempt,
    // whether that's the 2nd booking of a multi-item cart OR a same-
    // booking Retry tap after a failed/cancelled first attempt (both
    // set _hasOpenedBefore). Skipped entirely for the very first
    // checkout of the session (the common single-item, first-try case)
    // since there's no previous one to wait on — no reason to slow that
    // down. Bumped from 400ms to 900ms — 400ms wasn't always enough for
    // the previous native activity to finish tearing down on slower or
    // more heavily-loaded devices, which is exactly the "Something went
    // wrong" native error the field reports kept describing.
    if (_hasOpenedBefore) {
      await Future.delayed(const Duration(milliseconds: 900));
    }
    _hasOpenedBefore = true;

    final completer = Completer<RazorpayCheckoutOutcome>();
    _pending = completer;

    final options = {
      'key': razorpayKeyId, // from /initiate/ response — never hardcode
      'order_id': gatewayOrderId, // from /initiate/ response
      'amount': amountInPaise, // paise, already correct — pass through as-is
      'currency': currency,
      'name': name,
      'description': description,
      'prefill': {'contact': contact, 'email': email},
    };

    final openedAt = DateTime.now();

    try {
      razorpay.open(options);
    } catch (e) {
      // Malformed options map (e.g. a null/empty required field) throws
      // synchronously here, before Checkout even opens — handled
      // separately from EVENT_PAYMENT_ERROR.
      if (kDebugMode) print('[RazorpayCheckoutService] open() threw: $e');
      if (!completer.isCompleted) {
        completer.complete(const RazorpayCheckoutOutcome.failure(
          errorMessage: 'Could not open the payment screen. Please try again.',
        ));
      }
      _pending = null;
    }

    final outcome = await completer.future;
    razorpay.clear();
    if (identical(_current, razorpay)) _current = null;

    // A failure that comes back within ~1.5s of calling open() — before
    // the customer could realistically have looked at, let alone
    // dismissed, the Checkout sheet — is the native
    // "Something went wrong" teardown-race error described above, not a
    // real declined payment or a deliberate cancel (error code 2, which
    // Razorpay only reports once the user has actually tapped a close/
    // back button, is excluded from this check for that reason). Retry
    // it ONCE automatically, silently, with a fresh instance and a
    // longer settle gap, instead of surfacing a confusing generic error
    // for something that was never really about the payment itself.
    final tookLessThan1500ms = DateTime.now().difference(openedAt) < const Duration(milliseconds: 1500);
    if (!outcome.success && !isAutoRetry && tookLessThan1500ms && outcome.errorCode != 2) {
      if (kDebugMode) {
        print('[RazorpayCheckoutService] suspiciously-fast failure '
            '(${outcome.errorCode}: ${outcome.errorMessage}) — auto-retrying once');
      }
      await Future.delayed(const Duration(milliseconds: 900));
      return openCheckout(
        description: description,
        gatewayOrderId: gatewayOrderId,
        razorpayKeyId: razorpayKeyId,
        amountInPaise: amountInPaise,
        currency: currency,
        name: name,
        contact: contact,
        email: email,
        isAutoRetry: true,
      );
    }

    return outcome;
  }

  void _onSuccess(PaymentSuccessResponse response) {
    if (kDebugMode) print('[RazorpayCheckoutService] success: ${response.paymentId}');
    _pending?.complete(RazorpayCheckoutOutcome.success(
      razorpayOrderId: response.orderId!,
      razorpayPaymentId: response.paymentId!,
      razorpaySignature: response.signature!,
    ));
    _pending = null;
  }

  void _onError(PaymentFailureResponse response) {
    // response.code: Razorpay's numeric error code (e.g. 2 = payment
    // cancelled by user). response.message: human-readable reason, safe
    // to show directly. No backend call needed here — nothing was
    // verified, so nothing to undo. A declined card never produces a
    // signature, so /verify/ must never be called on this path; only
    // ever call it from EVENT_PAYMENT_SUCCESS (_onSuccess above).
    if (kDebugMode) print('[RazorpayCheckoutService] error: ${response.code} ${response.message}');
    _pending?.complete(RazorpayCheckoutOutcome.failure(
      errorMessage: response.message,
      errorCode: response.code,
    ));
    _pending = null;
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    // User picked a wallet app (Paytm, etc.) outside Razorpay's own
    // flow. Treat as pending — deliberately do NOT complete the
    // completer here; Razorpay will call _onSuccess or _onError once
    // that external flow resolves, just like a normal card/UPI attempt.
    if (kDebugMode) print('[RazorpayCheckoutService] external wallet: ${response.walletName}');
  }

  /// Call from the owning widget's dispose().
  void dispose() => _current?.clear();
}
