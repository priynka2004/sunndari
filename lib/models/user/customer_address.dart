// FILE: models/user/customer_address.dart  |  MODEL
// Customer address returned by the API.

/// Model: Customer Address.
class CustomerAddress {
  final int addressId;
  final int userId;
  final String addressLine1;
  final String? addressLine2;
  final String city;
  final String pinCode;
  final bool isDefault;
  final DateTime createdAt;
  final double? latitude;
  final double? longitude;

  CustomerAddress({
    required this.addressId,
    required this.userId,
    required this.addressLine1,
    this.addressLine2,
    required this.city,
    required this.pinCode,
    required this.isDefault,
    required this.createdAt,
    this.latitude,
    this.longitude,
  });

  /// Builds this object from API JSON.
  factory CustomerAddress.fromJson(Map<String, dynamic> json) {
    double? d(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    int i(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
    final lat = d(json['latitude'] ?? json['lat']);
    final lng = d(json['longitude'] ?? json['lng'] ?? json['lon']);
    return CustomerAddress(
      addressId: i(json['addressId'] ?? json['address_id']),
      userId: i(json['userId'] ?? json['user_id']),
      addressLine1: (json['addressLine1'] ?? json['address_line1'] ?? json['address_line_1'] ?? '').toString(),
      addressLine2: (json['addressLine2'] ?? json['address_line2'] ?? json['address_line_2'])?.toString(),
      city: (json['city'] ?? '').toString(),
      pinCode: (json['pinCode'] ?? json['pin_code'] ?? '').toString(),
      isDefault: (json['isDefault'] ?? json['is_default']) == true,
      createdAt: DateTime.tryParse('${json['createdAt'] ?? json['created_at']}') ?? DateTime.now(),
      // 0,0 means "not set" — ignore it
      latitude: (lat == null || lng == null || (lat == 0 && lng == 0)) ? null : lat,
      longitude: (lat == null || lng == null || (lat == 0 && lng == 0)) ? null : lng,
    );
  }

  /// True when the API gave us exact coordinates.
  bool get hasCoordinates => latitude != null && longitude != null;

  /// Address text, most specific first.
  String get fullText => [addressLine1, addressLine2, city, pinCode]
      .where((e) => e != null && e.trim().isNotEmpty)
      .map((e) => e!.trim())
      .join(', ');

  /// Shorter fallbacks used when the full address cannot be geocoded.
  List<String> get geocodeQueries => [
    fullText,
    [addressLine1, city, pinCode].where((e) => e.trim().isNotEmpty).join(', '),
    [city, pinCode].where((e) => e.trim().isNotEmpty).join(', '),
    pinCode,
  ].where((q) => q.trim().isNotEmpty).toSet().toList();
}