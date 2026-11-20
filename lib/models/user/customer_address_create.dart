// FILE: models/user/customer_address_create.dart  |  MODEL
// Request body to create a customer address.

/// Model: Customer Address Create.
class CustomerAddressCreate {
  final String addressLine1;
  final String? addressLine2;
  final String city;
  final String pinCode;
  final bool isDefault;
  /// Exact Google Maps location of the address (saved together with the address when chosen on the map).
  final double? latitude;
  final double? longitude;

  CustomerAddressCreate({
    required this.addressLine1,
    this.addressLine2,
    required this.city,
    required this.pinCode,
    this.isDefault = false,
    this.latitude,
    this.longitude,
  });

  /// Converts this object to JSON for the API.
  Map<String, dynamic> toJson() => {
    'address_line_1': addressLine1,
    if (addressLine2 != null) 'address_line_2': addressLine2,
    'city': city,
    'pin_code': pinCode,
    'is_default': isDefault,
    if (latitude != null && longitude != null) ...{'latitude': latitude, 'longitude': longitude},
  };
}
