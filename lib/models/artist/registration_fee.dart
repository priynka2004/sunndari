// FILE: models/artist/registration_fee.dart  |  MODELS
// Artist registration fee (backend guide "Artist Registration Fee API").
// The server calculates every figure; the app only displays what it returns. Amounts arrive as strings ("1999.00"),
// except `amount` in the initiate response, which is an integer in paise.

double _money(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}'.replaceAll(',', '').trim()) ?? 0;
}

bool _flag(dynamic v) => v == true || v == 1 || '$v'.toLowerCase() == 'true';

/// GET /artists/registration/fee/
class RegistrationFee {
  final double feeAmount; // before any promo
  final String currency;
  final bool paid;
  final bool exempt;
  final bool registrationRequired; // true only when paid and exempt are both false → show the fee screen

  const RegistrationFee({
    this.feeAmount = 0,
    this.currency = 'INR',
    this.paid = false,
    this.exempt = false,
    this.registrationRequired = false,
  });

  factory RegistrationFee.fromJson(Map<String, dynamic> j) => RegistrationFee(
        feeAmount: _money(j['feeAmount']),
        currency: '${j['currency'] ?? 'INR'}',
        paid: _flag(j['paid']),
        exempt: _flag(j['exempt']),
        registrationRequired: _flag(j['registrationRequired']),
      );
}

/// POST /artists/registration/promo/validate/ — preview of a promo code.
class PromoPreview {
  final String promoCode;
  final double feeAmount;
  final double discountPercent;
  final double discountAmount;
  final double payableAmount;
  final bool requiresPayment; // false for a 100% code → show "Free" and skip checkout

  const PromoPreview({
    required this.promoCode,
    required this.feeAmount,
    required this.discountPercent,
    required this.discountAmount,
    required this.payableAmount,
    required this.requiresPayment,
  });

  factory PromoPreview.fromJson(Map<String, dynamic> j) => PromoPreview(
        promoCode: '${j['promoCode'] ?? ''}',
        feeAmount: _money(j['feeAmount']),
        discountPercent: _money(j['discountPercent']),
        discountAmount: _money(j['discountAmount']),
        payableAmount: _money(j['payableAmount']),
        requiresPayment: j.containsKey('requiresPayment') ? _flag(j['requiresPayment']) : _money(j['payableAmount']) > 0,
      );
}

/// POST /artists/registration/payment/initiate/
class RegistrationPaymentInit {
  final int registrationPaymentId;
  final String? gatewayOrderId;
  final String? razorpayKeyId;
  final int amountPaise; // integer, rupees × 100 — pass to Razorpay as-is
  final String currency;
  final double feeAmount;
  final double discountAmount;
  final double payableAmount;
  final bool fullyCoveredByPromo; // true → fee already paid, no Razorpay and no verify call

  const RegistrationPaymentInit({
    required this.registrationPaymentId,
    required this.gatewayOrderId,
    required this.razorpayKeyId,
    required this.amountPaise,
    required this.currency,
    required this.feeAmount,
    required this.discountAmount,
    required this.payableAmount,
    required this.fullyCoveredByPromo,
  });

  factory RegistrationPaymentInit.fromJson(Map<String, dynamic> j) {
    String? s(dynamic v) {
      final t = (v ?? '').toString().trim();
      return t.isEmpty ? null : t;
    }

    return RegistrationPaymentInit(
      registrationPaymentId: (j['registration_payment_id'] as num?)?.toInt() ?? int.tryParse('${j['registration_payment_id']}') ?? 0,
      gatewayOrderId: s(j['gateway_order_id']),
      razorpayKeyId: s(j['razorpay_key_id']),
      amountPaise: (j['amount'] as num?)?.toInt() ?? int.tryParse('${j['amount']}') ?? 0,
      currency: '${j['currency'] ?? 'INR'}',
      feeAmount: _money(j['fee_amount']),
      discountAmount: _money(j['discount_amount']),
      payableAmount: _money(j['payable_amount']),
      fullyCoveredByPromo: _flag(j['fully_covered_by_promo']),
    );
  }
}
