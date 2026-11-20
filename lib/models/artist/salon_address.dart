// FILE: models/artist/salon_address.dart
// MODEL: a salon / studio the artist works from (Salon Addresses API).
//
// Artist calls (snake_case):  /artists/salon_addresses/create | get_all | update | delete
// Customer artist page & bookings (camelCase): salonAddressId, name, addressLine1, addressLine2, city, pinCode, latitude, longitude
// A booking carries its own copy of the salon (edits and deletes never change past bookings).

import '../user/customer_address.dart';

double _d(dynamic v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);
int _i(dynamic v) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);

class SalonAddress {
  final int salonAddressId;
  final String name;
  final String addressLine1;
  final String? addressLine2;
  final String city;
  final String pinCode;
  final double latitude;
  final double longitude;

  const SalonAddress({
    required this.salonAddressId,
    required this.name,
    required this.addressLine1,
    this.addressLine2,
    required this.city,
    required this.pinCode,
    required this.latitude,
    required this.longitude,
  });

  /// Accepts both the artist list (snake_case) and the booking / artist page (camelCase).
  factory SalonAddress.fromJson(Map<String, dynamic> j) {
    final line2 = (j['addressLine2'] ?? j['address_line_2'])?.toString().trim();
    return SalonAddress(
      salonAddressId: _i(j['salonAddressId'] ?? j['salon_address_id']),
      name: (j['name'] ?? '').toString(),
      addressLine1: (j['addressLine1'] ?? j['address_line_1'] ?? '').toString(),
      addressLine2: (line2 == null || line2.isEmpty) ? null : line2,
      city: (j['city'] ?? '').toString(),
      pinCode: (j['pinCode'] ?? j['pin_code'] ?? '').toString(),
      latitude: _d(j['latitude']),
      longitude: _d(j['longitude']),
    );
  }

  /// "12 Vibhuti Khand, Near Metro Pillar 120, Lucknow, 226010"
  String get addressText => [addressLine1, addressLine2, city, pinCode]
      .where((e) => e != null && e.trim().isNotEmpty)
      .map((e) => e!.trim())
      .join(', ');

  bool get hasCoordinates => !(latitude == 0 && longitude == 0);

  /// Lets the existing booking screens (address text, "View Location On Map", "Get Directions") work for an
  /// In-Salon booking: the salon's name is put in front of its address.
  CustomerAddress toCustomerAddress() => CustomerAddress(
        addressId: 0,
        userId: 0,
        addressLine1: name.trim().isEmpty ? addressLine1 : '${name.trim()}, $addressLine1',
        addressLine2: addressLine2,
        city: city,
        pinCode: pinCode,
        isDefault: false,
        createdAt: DateTime.now(),
        latitude: hasCoordinates ? latitude : null,
        longitude: hasCoordinates ? longitude : null,
      );
}
