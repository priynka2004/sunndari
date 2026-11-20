// FILE: models/user/customer_address_update.dart  |  MODEL
// Request body to update a customer address.

/// Model: Customer Address Update.
class CustomerAddressUpdate {
  final int addressId;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? pinCode;
  final bool? isDefault;
  /// Exact Google Maps location (sent only when the address was chosen on the map).
  final double? latitude;
  final double? longitude;

  CustomerAddressUpdate({
    required this.addressId,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.pinCode,
    this.isDefault,
    this.latitude,
    this.longitude,
  });

  /// Converts this object to JSON for the API.
  Map<String, dynamic> toJson() => {
    'address_id': addressId,
    if (addressLine1 != null) 'address_line_1': addressLine1,
    if (addressLine2 != null) 'address_line_2': addressLine2,
    if (city != null) 'city': city,
    if (pinCode != null) 'pin_code': pinCode,
    if (isDefault != null) 'is_default': isDefault,
    if (latitude != null && longitude != null) ...{'latitude': latitude, 'longitude': longitude},
  };
}
