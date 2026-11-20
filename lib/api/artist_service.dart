// FILE: api/artist_service.dart
// Artist APIs: profile, portfolio, packages, services, locations, availability (schedule + block).

import 'dart:convert';
import '../models/auth/add_block.dart';
import '../models/auth/add_location.dart';
import '../models/auth/set_schedule.dart';
import 'api_endpoints.dart';
import 'api_service.dart';
import '../utils/paginated_response.dart';
import '../utils/api_response.dart';
import '../models/artist/artist_extras.dart' show unwrapMap;
import '../models/artist/artist_profile.dart';
import '../models/artist/artist_profile_update.dart';
import '../models/artist/portfolio.dart';
import '../models/artist/create_portfolio.dart';
import '../models/artist/update_portfolio.dart';
import '../models/artist/package.dart';
import '../models/artist/create_package.dart';
import '../models/artist/update_package.dart';
import '../models/artist/add_service.dart';

/// Artist Service — API/data layer.
class ArtistService {
  final ApiService _apiService;
  ArtistService(this._apiService);

  /// Gets profile.
  /// API: GET /artists/profile/get/
  /// API: GET /artists/profile/get/ — the raw `data` map (used for fields the model does not carry).
  Future<Map<String, dynamic>> getProfileRaw() async {
    final response = await _apiService.get(ApiEndpoints.artistsProfileGet);
    return unwrapMap(jsonDecode(response.body));
  }

  Future<ArtistProfile> getProfile({int? artistId}) async {
    final response = await _apiService.get(
      ApiEndpoints.artistsProfileGet,
      queryParameters: artistId != null ? {'artist_id': artistId.toString()} : null,
    );
    final jsonData = jsonDecode(response.body);
    return ApiResponse.fromJson(jsonData, ArtistProfile.fromJson).data;
  }

  /// Updates profile.
  /// API: PUT /artists/profile/update/
  Future<void> updateProfile(ArtistProfileUpdate data) async {
    await _apiService.put(ApiEndpoints.artistsProfileUpdate, data: data.toJson());
  }

  /// Creates portfolio.
  /// API: POST /artists/portfolio/create/
  Future<void> createPortfolio(CreatePortfolio data) async {
    await _apiService.postMultipart(
      ApiEndpoints.artistsPortfolioCreate,
      fields: {
        'media_type': data.mediaType.name,
        'sub_category_id': data.subCategoryId.toString(),
        if (data.caption != null) 'caption': data.caption!,
        // The server only allows work samples to be images (a video with this flag gets a 400).
        if (data.isWorkSample && data.mediaType.name == 'image') 'is_work_sample': 'true',
      },
      files: [UploadFile('file', data.file.path, filename: data.file.name)],
      // Videos can be up to 300 MB now — give the upload time to finish on a slow connection.
      timeout: data.mediaType.name == 'video' ? const Duration(minutes: 15) : const Duration(seconds: 120),
    );
  }

  /// Gets portfolio.
  /// API: GET /artists/portfolio/get/
  Future<Portfolio> getPortfolio(int portfolioId) async {
    final response = await _apiService.get(
      ApiEndpoints.artistsPortfolioGet,
      queryParameters: {'portfolio_id': portfolioId.toString()},
    );
    final jsonData = jsonDecode(response.body);
    return ApiResponse.fromJson(jsonData, Portfolio.fromJson).data;
  }

  /// Gets all portfolios.
  /// API: GET /artists/portfolio/get_all/
  Future<PaginatedResponse<Portfolio>> getAllPortfolios({
    int limit = 10, int? pageNum, String? sortBy, String? sortOrder,
    String? searchKey, String? filterKey, String? filterValue,
  }) async {
    final response = await _apiService.get(
      ApiEndpoints.artistsPortfolioGetAll,
      queryParameters: {
        if (limit != 10) 'limit': limit.toString(),
        if (pageNum != null) 'page_num': pageNum.toString(),
        if (sortBy != null) 'sort_by': sortBy,
        if (sortOrder != null) 'sort_order': sortOrder,
        if (searchKey != null) 'search_key': searchKey,
        if (filterKey != null) 'filter_key': filterKey,
        if (filterValue != null) 'filter_value': filterValue,
      },
    );
    final jsonData = jsonDecode(response.body);
    return PaginatedResponse.fromJson(jsonData['data'], Portfolio.fromJson);
  }

  /// Updates portfolio.
  /// API: PUT /artists/portfolio/update/
  Future<void> updatePortfolio(UpdatePortfolio data) async {
    await _apiService.put(ApiEndpoints.artistsPortfolioUpdate, data: data.toJson());
  }

  /// Deletes portfolio.
  /// API: DELETE /artists/portfolio/delete/
  Future<void> deletePortfolio(int portfolioId) async {
    await _apiService.delete(
      ApiEndpoints.artistsPortfolioDelete,
      queryParameters: {'portfolio_id': portfolioId.toString()},
    );
  }

  /// Creates package.
  /// API: POST /artists/packages/create/
  Future<void> createPackage(CreatePackage data) async {
    await _apiService.post(
      ApiEndpoints.artistsPackagesCreate,
      data: data.toJson(),
    );
  }

  /// Gets package.
  /// API: GET /artists/packages/get/
  Future<Package> getPackage(int packageId) async {
    final response = await _apiService.get(
      ApiEndpoints.artistsPackagesGet,
      queryParameters: {'package_id': packageId.toString()},
    );
    final jsonData = jsonDecode(response.body);
    return ApiResponse.fromJson(jsonData, Package.fromJson).data;
  }

  /// Gets all packages.
  /// API: GET /artists/packages/get_all/
  Future<PaginatedResponse<Package>> getAllPackages({
    int limit = 10, int? pageNum, String? sortBy, String? sortOrder,
    String? filterKey, String? filterValue, String? searchKey,
  }) async {
    final response = await _apiService.get(
      ApiEndpoints.artistsPackagesGetAll,
      queryParameters: {
        if (limit != 10) 'limit': limit.toString(),
        if (pageNum != null) 'page_num': pageNum.toString(),
        if (sortBy != null) 'sort_by': sortBy,
        if (sortOrder != null) 'sort_order': sortOrder,
        if (filterKey != null) 'filter_key': filterKey,
        if (filterValue != null) 'filter_value': filterValue,
        if (searchKey != null) 'search_key': searchKey,
      },
    );
    final jsonData = jsonDecode(response.body);
    return PaginatedResponse.fromJson(jsonData['data'], Package.fromJson);
  }

  /// Updates package.
  /// API: PUT /artists/packages/update/
  Future<void> updatePackage(UpdatePackage data) async {
    await _apiService.put(ApiEndpoints.artistsPackagesUpdate, data: data.toJson());
  }

  /// Deletes package.
  /// API: DELETE /artists/packages/delete/
  Future<void> deletePackage(int packageId) async {
    await _apiService.delete(
      ApiEndpoints.artistsPackagesDelete,
      queryParameters: {'package_id': packageId.toString()},
    );
  }

  /// Adds service.
  /// API: POST /artists/services/add/
  Future<void> addService(AddService data) async {
    await _apiService.post(ApiEndpoints.artistsServicesAdd, data: data.toJson());
  }

  /// Gets all services.
  /// API: GET /artists/services/get_all/
  Future<dynamic> getAllServices() async {
    final response = await _apiService.get(ApiEndpoints.artistsServicesGetAll);
    return jsonDecode(response.body);
  }

  /// Removes service.
  /// API: DELETE /artists/services/remove/
  Future<void> removeService(int subCategoryId) async {
    await _apiService.delete(
      ApiEndpoints.artistsServicesRemove,
      queryParameters: {'sub_category_id': subCategoryId.toString()},
    );
  }

  /// Adds location.
  /// API: POST /artists/locations/add/
  Future<void> addLocation(AddLocation data) async {
    await _apiService.post(ApiEndpoints.artistsLocationsAdd, data: data.toJson());
  }

  /// Gets all locations.
  /// API: GET /artists/locations/get_all/
  Future<dynamic> getAllLocations() async {
    final response = await _apiService.get(ApiEndpoints.artistsLocationsGetAll);
    return jsonDecode(response.body);
  }

  /// Removes location.
  /// API: DELETE /artists/locations/remove/
  Future<void> removeLocation(int locationTypeId) async {
    await _apiService.delete(
      ApiEndpoints.artistsLocationsRemove,
      queryParameters: {'location_type_id': locationTypeId.toString()},
    );
  }

  /// Sets schedule.
  /// API: POST /artists/availability/schedule/set/
  Future<void> setSchedule(SetSchedule data) async {
    await _apiService.post(ApiEndpoints.artistsAvailabilityScheduleSet, data: data.toJson());
  }

  /// Gets all schedules.
  /// API: GET /artists/availability/schedule/get_all/
  Future<dynamic> getAllSchedules() async {
    final response = await _apiService.get(ApiEndpoints.artistsAvailabilityScheduleGetAll);
    return jsonDecode(response.body);
  }

  /// Removes schedule.
  /// API: DELETE /artists/availability/schedule/remove/
  Future<void> removeSchedule(int dayOfWeek) async {
    await _apiService.delete(
      ApiEndpoints.artistsAvailabilityScheduleRemove,
      queryParameters: {'day_of_week': dayOfWeek.toString()},
    );
  }

  /// Adds block.
  /// API: POST /artists/availability/block/add/
  Future<void> addBlock(AddBlock data) async {
    await _apiService.post(ApiEndpoints.artistsAvailabilityBlockAdd, data: data.toJson());
  }

  /// The artist's own day as customers see it: the exact bookable start times, made by the server
  /// (every 30 minutes, with buffers and Home Visit chains). Never cached.
  /// API: GET /artists/availability/slots/?booking_date=dd-mm-yy[&package_id=][&addon_ids=3,7][&location_type_id=]
  Future<Map<String, dynamic>> getAvailabilitySlots({
    required DateTime date,
    int? packageId,
    List<int> addonIds = const [],
    int? locationTypeId,
  }) async {
    String two(int n) => n.toString().padLeft(2, '0');
    final response = await _apiService.get(
      ApiEndpoints.artistsAvailabilitySlots,
      queryParameters: {
        'booking_date': '${two(date.day)}-${two(date.month)}-${two(date.year % 100)}',
        if (packageId != null) 'package_id': '$packageId',
        if (addonIds.isNotEmpty) 'addon_ids': addonIds.join(','),
        if (locationTypeId != null) 'location_type_id': '$locationTypeId',
      },
    );
    final j = jsonDecode(response.body);
    final data = j is Map ? j['data'] : null;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// Gets all blocks.
  /// API: GET /artists/availability/block/get_all/
  Future<dynamic> getAllBlocks() async {
    final response = await _apiService.get(ApiEndpoints.artistsAvailabilityBlockGetAll);
    return jsonDecode(response.body);
  }

  /// Removes block.
  /// API: DELETE /artists/availability/block/remove/
  Future<void> removeBlock(String blockDate) async {
    await _apiService.delete(
      ApiEndpoints.artistsAvailabilityBlockRemove,
      queryParameters: {'block_date': blockDate},
    );
  }

  // KYC documents, payout account, onboarding status/submit, agreement, photos, add-ons,
  // service areas, brands, reviews, clients, insights and tickets live in ArtistBusinessService
  // (api/artist_business_service.dart).
}
