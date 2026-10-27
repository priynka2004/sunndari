// FILE: api/booking_service.dart
// Artist bookings APIs: get one booking, list bookings, update booking status.

import 'dart:convert';
import '../models/booking/booking.dart';
import 'api_endpoints.dart';
import 'api_service.dart';

/// Booking Service — API/data layer.
class BookingService {
  final ApiService _apiService;
  BookingService(this._apiService);

  Map<String, dynamic> _unwrap(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
  }

  /// Parses booking list.
  List<Booking> _parseBookingList(dynamic json) {
    final raw = json is Map ? (json['data'] ?? json) : json;
    final list = raw is List
        ? raw
        : (raw is Map ? (raw['data'] as List? ?? []) : []);
    return list.map((e) => Booking.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Gets booking.
  /// API: GET /artists/bookings/get/
  /// [paidOnly] (default true): sends filter_key=paymentStatus&filter_value=paid — an unpaid booking
  /// answers 400 "Booking not found", so the artist never sees it.
  Future<Booking> getBooking(int bookingId, {bool paidOnly = true}) async {
    final response = await _apiService.get(
      ApiEndpoints.artistBookingsGet,
      queryParameters: {
        'booking_id': bookingId.toString(),
        if (paidOnly) ...{'filter_key': 'paymentStatus', 'filter_value': 'paid'},
      },
    );
    return Booking.fromJson(_unwrap(response.body));
  }

  /// Gets all bookings.
  /// API: GET /artists/bookings/get_all/
  /// [paymentFilter]: 'paid' (default — the artist only ever sees paid bookings) or 'unpaid'.
  Future<List<Booking>> getAllBookings({
    String paymentFilter = 'paid',
    String? filterKey,
    String? filterValue,
    int pageNum = 1,
    int limit = 20,
  }) async {
    final response = await _apiService.get(
      ApiEndpoints.artistBookingsGetAll,
      queryParameters: {
        'page_num': pageNum.toString(),
        // The server rejects limit > 200 with a 400 "Validation Error", so never send more than that.
        'limit': limit.clamp(1, 200).toString(),
        if (filterKey != null && filterValue != null) ...{
          'filter_key': filterKey,
          'filter_value': filterValue,
        } else ...{
          'filter_key': 'paymentStatus',
          'filter_value': paymentFilter,
        },
      },
    );

    final bookings = _parseBookingList(jsonDecode(response.body));

    return bookings;
  }

  /// Updates booking status.
  /// API: PUT /artists/bookings/update_status/
  Future<Booking> updateBookingStatus(
    int bookingId,
    BookingStatusEnum status, {
    String? reason,
  }) async {
    final response = await _apiService.put(
      ApiEndpoints.artistBookingsUpdateStatus,
      data: {
        'booking_id': bookingId,
        'status': status.toJson(),
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
    return Booking.fromJson(_unwrap(response.body));
  }
}
