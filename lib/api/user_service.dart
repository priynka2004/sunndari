// FILE: api/user_service.dart
// User APIs: profile get/update, FCM token, customer address CRUD.

import 'dart:convert';
import 'api_endpoints.dart';
import 'api_service.dart';
import '../utils/paginated_response.dart';
import '../utils/api_response.dart';
import '../utils/app_session.dart';
import '../models/user/user_profile.dart';
import '../models/user/user_profile_update.dart';
import '../models/user/customer_address.dart';
import '../models/user/customer_address_create.dart';
import '../models/user/customer_address_update.dart';

/// User Service — API/data layer.
class UserService {
  final ApiService _apiService;

  UserService(this._apiService);

  /// Gets profile.
  /// API: GET /users/profile/get/
  Future<UserProfile> getProfile(int userId) async {
    final response = await _apiService.get(
      ApiEndpoints.usersProfileGet,
      queryParameters: {'user_id': userId.toString()},
    );
    final jsonData = jsonDecode(response.body);
    return ApiResponse.fromJson(jsonData, UserProfile.fromJson).data;
  }

  /// Updates profile.
  /// API: PUT /users/profile/update/
  Future<void> updateProfile(UserProfileUpdate data) async {
    await _apiService.put(
      ApiEndpoints.usersProfileUpdate,
      data: data.toJson(),
    );
  }

  /// Updates FCM token.
  Future<void> updateFcmToken(String fcmToken, {String? platform}) async {
    await updateProfile(UserProfileUpdate(fcmToken: fcmToken));
  }

  /// Creates address.
  /// API: POST /users/address/create/
  Future<void> createAddress(CustomerAddressCreate data) async {
    await _apiService.post(
      ApiEndpoints.usersAddressCreate,
      data: data.toJson(),
    );
  }

  /// Gets address.
  /// API: GET /users/address/get/
  Future<CustomerAddress> getAddress(int addressId) async {
    final response = await _apiService.get(
      ApiEndpoints.usersAddressGet,
      queryParameters: {'address_id': addressId.toString()},
    );
    final jsonData = jsonDecode(response.body);
    return ApiResponse.fromJson(jsonData, CustomerAddress.fromJson).data;
  }

  /// Gets all addresses.
  /// API: GET /users/address/get_all/
  Future<PaginatedResponse<CustomerAddress>> getAllAddresses({
    int limit = 10,
    int? pageNum,
  }) async {
    final response = await _apiService.get(
      ApiEndpoints.usersAddressGetAll,
      queryParameters: {
        if (limit != 10) 'limit': limit.toString(),
        if (pageNum != null) 'page_num': pageNum.toString(),
      },
    );
    final jsonData = jsonDecode(response.body);
    return PaginatedResponse.fromJson(
      jsonData['data'],
      CustomerAddress.fromJson,
    );
  }

  /// Updates address.
  /// API: PUT /users/address/update/
  Future<void> updateAddress(CustomerAddressUpdate data) async {
    await _apiService.put(
      ApiEndpoints.usersAddressUpdate,
      data: data.toJson(),
    );
  }

  /// Deletes address.
  /// API: DELETE /users/address/delete/
  Future<void> deleteAddress(int addressId) async {
    await _apiService.delete(
      ApiEndpoints.usersAddressDelete,
      queryParameters: {'address_id': addressId.toString()},
    );
  }

  /// Artist deletes their own account (switched off, not erased; can return later with the same phone number).
  /// API: DELETE /artists/account/delete/?user_id=<own user_id>
  /// 200 → the caller must sign out locally. 400 → the backend message (e.g. a paid / confirmed / in-progress
  /// booking is still open) is thrown as an Exception and nothing changes. Any later call with the old token → 401.
  Future<void> deleteAccount() async {
    final userId = AppSession.instance.userId;
    if (userId == null || userId == 0) {
      throw Exception('Please Sign In Again And Try Once More.');
    }
    await _apiService.delete(
      ApiEndpoints.artistsAccountDelete,
      queryParameters: {'user_id': userId.toString()},
    );
  }
}
