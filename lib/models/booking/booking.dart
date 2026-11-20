// FILE: models/booking/booking.dart  |  MODEL
// Booking returned by the backend (+ BookingStatusEnum).

import '../user/customer_address.dart';
import '../artist/salon_address.dart';
import '../../utils/payment_status.dart';

/// How an advance (20%) booking is paid: what is paid, what is still due, and whether the artist got the rest.
class PaymentSummary {
  final double totalAmount;
  final String paymentOption; // full | advance
  final double? advanceAmount;
  final double paidAmount;
  final double balanceDue;
  final String? balanceStatus; // null (not answered) | received | not_received

  const PaymentSummary({
    required this.totalAmount,
    required this.paymentOption,
    this.advanceAmount,
    required this.paidAmount,
    required this.balanceDue,
    this.balanceStatus,
  });

  bool get isAdvance => paymentOption.toLowerCase() == 'advance';

  /// The rest is still to be collected from the customer.
  bool get hasBalanceDue => balanceDue > 0;

  /// The artist has not answered "Did you receive the rest?" yet.
  bool get needsAnswer => isAdvance && hasBalanceDue && balanceStatus == null;

  /// The artist answered No — the rest is still owed (can still become Yes later).
  bool get notReceived => isAdvance && hasBalanceDue && balanceStatus == 'not_received';

  static double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  /// Builds this object from API JSON (`paymentSummary`).
  factory PaymentSummary.fromJson(Map<String, dynamic> j) => PaymentSummary(
    totalAmount: _d(j['totalAmount']),
    paymentOption: '${j['paymentOption'] ?? 'full'}',
    advanceAmount: j['advanceAmount'] == null ? null : _d(j['advanceAmount']),
    paidAmount: _d(j['paidAmount']),
    balanceDue: _d(j['balanceDue']),
    balanceStatus: j['balanceStatus']?.toString(),
  );
}

/// Model: Booking.
class Booking {
  final int bookingId;
  final int customerId;
  final int artistId;
  final int? subCategoryId;
  final int packageId;
  final int locationTypeId;
  final int? addressId;
  /// Customer address sent inside the artist booking response (GET /artists/bookings/get/ & get_all/).
  /// Artists are not allowed to call /users/address/get/, so this is the only source.
  final CustomerAddress? address;
  /// In-Salon bookings: the salon the customer chose, as saved when the booking was made (null for other bookings).
  final SalonAddress? salonAddress;
  final String bookingDate;
  final String startTime;
  final String? endTime;
  final int statusId;
  final int? paymentStatusId;
  final double totalAmount;
  final String? notes;
  final String? cancelledBy;
  final String? cancellationReason;
  final String? expiresAt;
  final String? createdAt;
  final String? updatedAt;
  final String? onMyWayAt;
  final String? arrivedAt;
  final String? serviceStartedAt;
  final String? serviceCompletedAt;
  // Added by the API (artist sees commission + net; null on older bookings)
  final double? platformFee;
  final double? netAmount;
  final double travelFee;
  final int travelTimeMinutes;
  final int returnBufferMinutes;
  final List<BookingAddOn> addons;
  /// The status in words, made by the server ("Pending", "Confirmed", "In Progress", "Cancelled", …;
  /// "Completed and Payment Received" only when completed AND paid). Show this instead of turning statusId into words.
  final String? statusLabel;
  /// `paid` (money is held), `refunded` (paid, then fully refunded) or `unpaid`.
  final String? paymentStatus;
  /// Advance booking details (null on old servers). Show these amounts as they are — never work out 20% in the app.
  final PaymentSummary? paymentSummary;
  /// The finished-service photo, or null until it is uploaded.
  final CompletionProof? completionProof;

  Booking({
    required this.bookingId,
    required this.customerId,
    required this.artistId,
    this.subCategoryId,
    required this.packageId,
    required this.locationTypeId,
    this.addressId,
    this.address,
    this.salonAddress,
    required this.bookingDate,
    required this.startTime,
    this.endTime,
    required this.statusId,
    this.paymentStatusId,
    required this.totalAmount,
    this.notes,
    this.cancelledBy,
    this.cancellationReason,
    this.expiresAt,
    this.createdAt,
    this.updatedAt,
    this.onMyWayAt,
    this.arrivedAt,
    this.serviceStartedAt,
    this.serviceCompletedAt,
    this.platformFee,
    this.netAmount,
    this.travelFee = 0,
    this.travelTimeMinutes = 0,
    this.returnBufferMinutes = 0,
    this.addons = const [],
    this.statusLabel,
    this.paymentStatus,
    this.paymentSummary,
    this.completionProof,
  });

  /// True for an In-Salon booking (the customer comes to the salon). It has no On My Way / Arrived step:
  /// the artist taps Start Service, the customer reads out a PIN, and the artist enters it.
  /// A booking with a saved salon address is In-Salon; location type 2 is In-Salon too.
  /// Partly paid (advance paid, the rest not settled yet).
  bool get isPaymentInProgress => PaymentStatusX.isInProgress(paymentStatus);

  bool get isInSalon => salonAddress != null || locationTypeId == 2;

  /// Starts date time.
  DateTime? get startDateTime {
    if (bookingDate.isEmpty || startTime.isEmpty) return null;
    try {
      final dateParts = bookingDate.split('-').map(int.parse).toList();
      final timeParts = startTime.split(':').map(int.parse).toList();
      return DateTime(
        dateParts[0], dateParts[1], dateParts[2],
        timeParts[0], timeParts.length > 1 ? timeParts[1] : 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns true if it has start time passed.
  bool get hasStartTimePassed {
    final start = startDateTime;
    if (start == null) return false;
    return !DateTime.now().isBefore(start.add(const Duration(hours: 2)));
  }

  /// Builds this object from API JSON.
  factory Booking.fromJson(Map<String, dynamic> json) {
    double parseAmount(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    int parseInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    String? asString(dynamic v) => v?.toString();

    // Address object inside the booking (backend key may differ — all common ones are tried).
    CustomerAddress? parseAddress() {
      for (final k in const ['address', 'customerAddress', 'customer_address', 'clientAddress', 'client_address']) {
        final v = json[k];
        if (v is Map) {
          try {
            return CustomerAddress.fromJson(Map<String, dynamic>.from(v));
          } catch (_) {}
        }
      }
      return null;
    }
    final parsedAddress = parseAddress();
    SalonAddress? salon;
    final rawSalon = json['salonAddress'] ?? json['salon_address'];
    if (rawSalon is Map) {
      try {
        salon = SalonAddress.fromJson(Map<String, dynamic>.from(rawSalon));
      } catch (_) {}
    }

    CompletionProof? proof;
    final rawProof = json['completionProof'] ?? json['completion_proof'];
    if (rawProof is Map) {
      try {
        proof = CompletionProof.fromJson(Map<String, dynamic>.from(rawProof));
      } catch (_) {}
    }

    return Booking(
      bookingId: parseInt(json['bookingId'] ?? json['booking_id']),
      customerId: parseInt(json['customerId'] ?? json['customer_id']),
      artistId: parseInt(json['artistId'] ?? json['artist_id']),
      subCategoryId: json['subCategoryId'] ?? json['sub_category_id'],
      packageId: parseInt(json['packageId'] ?? json['package_id']),
      locationTypeId: parseInt(json['locationTypeId'] ?? json['location_type_id']),
      addressId: json['addressId'] ?? json['address_id'] ?? (parsedAddress != null && parsedAddress.addressId != 0 ? parsedAddress.addressId : null),
      // In-Salon bookings have no customer address; the salon takes its place so the map / directions keep working.
      address: parsedAddress ?? salon?.toCustomerAddress(),
      salonAddress: salon,
      bookingDate: asString(json['bookingDate'] ?? json['booking_date']) ?? '',
      startTime: asString(json['startTime'] ?? json['start_time']) ?? '',
      endTime: asString(json['endTime'] ?? json['end_time']),
      statusId: parseInt(json['statusId'] ?? json['status_id']),
      paymentStatusId: (json['paymentStatusId'] ?? json['payment_status_id']) == null
          ? null
          : parseInt(json['paymentStatusId'] ?? json['payment_status_id']),
      totalAmount: parseAmount(json['totalAmount'] ?? json['total_amount']),
      notes: asString(json['notes']),
      cancelledBy: asString(json['cancelledBy'] ?? json['cancelled_by']),
      cancellationReason:
      asString(json['cancellationReason'] ?? json['cancellation_reason']),
      expiresAt: asString(json['expiresAt'] ?? json['expires_at']),
      createdAt: asString(json['createdAt'] ?? json['created_at']),
      updatedAt: asString(json['updatedAt'] ?? json['updated_at']),
      onMyWayAt: asString(json['onMyWayAt'] ?? json['on_my_way_at']),
      arrivedAt: asString(json['arrivedAt'] ?? json['arrived_at']),
      serviceStartedAt: asString(json['serviceStartedAt'] ?? json['service_started_at']),
      serviceCompletedAt: asString(json['serviceCompletedAt'] ?? json['service_completed_at']),
      platformFee: json['platformFee'] == null ? null : parseAmount(json['platformFee']),
      netAmount: json['netAmount'] == null ? null : parseAmount(json['netAmount']),
      travelFee: parseAmount(json['travelFee']),
      travelTimeMinutes: parseInt(json['travelMinutesBefore'] ?? json['travelTimeMinutes']),
      returnBufferMinutes: parseInt(json['returnBufferMinutes']),
      addons: ((json['addOns'] ?? json['addons'] as List?) as List? ?? const [])
          .whereType<Map>()
          .map((e) => BookingAddOn.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      statusLabel: (asString(json['statusLabel'] ?? json['status_label']) ?? '').trim().isEmpty
          ? null
          : asString(json['statusLabel'] ?? json['status_label'])!.trim(),
      paymentStatus: asString(json['paymentStatus'] ?? json['payment_status']),
      paymentSummary: json['paymentSummary'] is Map
          ? PaymentSummary.fromJson(Map<String, dynamic>.from(json['paymentSummary'] as Map))
          : null,
      completionProof: proof,
    );
  }
}

/// The photo of the finished service. [url] is an authenticated route (relative to the base URL):
/// it must be opened with the Bearer header, it is not a public image link.
class CompletionProof {
  final String? uploadedAt;
  final String url;

  const CompletionProof({required this.url, this.uploadedAt});

  factory CompletionProof.fromJson(Map<String, dynamic> j) => CompletionProof(
    url: (j['url'] ?? '').toString(),
    uploadedAt: j['uploadedAt']?.toString() ?? j['uploaded_at']?.toString(),
  );
}

/// Enum: Booking Status Enum values.
enum BookingStatusEnum {
  confirmed,
  inProgress,
  completed,
  cancelled,
  noShow;

  String toJson() {
    switch (this) {
      case BookingStatusEnum.confirmed:
        return 'confirmed';
      case BookingStatusEnum.inProgress:
        return 'in_progress';
      case BookingStatusEnum.completed:
        return 'completed';
      case BookingStatusEnum.cancelled:
        return 'cancelled';
      case BookingStatusEnum.noShow:
        return 'no_show';
    }
  }
}

/// Add-on chosen on a booking (snapshot: later edits to the add-on do not change it).
class BookingAddOn {
  final int addOnId;
  final String name;
  final double price;
  final int durationMinutes;

  const BookingAddOn({required this.addOnId, required this.name, required this.price, this.durationMinutes = 0});

  factory BookingAddOn.fromJson(Map<String, dynamic> j) => BookingAddOn(
    addOnId: (j['addOnId'] as num?)?.toInt() ?? 0,
    name: (j['name'] ?? '').toString(),
    price: double.tryParse('${j['price']}') ?? 0,
    durationMinutes: (j['durationMinutes'] as num?)?.toInt() ?? 0,
  );
}