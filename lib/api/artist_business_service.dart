// FILE: api/artist_business_service.dart
// Sunndari API (security & features release) — artist side:
// onboarding status/submit, KYC documents, payout account, agreement, profile extras (photos, share link,
// accepting bookings, specialities), add-ons, service areas, brands, reschedule, reviews, clients, insights,
// support tickets, contact change, public pages.
//
// Conventions (from the guide): every path ends with '/', requests use snake_case, responses camelCase,
// booking dates in requests are DD-MM-YY (2-digit year), money is a string with 2 decimals, lists are paginated
// (page_num, limit, sort_by, sort_order, filter_key, filter_value, search_key).
//
// Field names below were checked against the full endpoint reference.

import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../models/artist/artist_extras.dart';
import 'api_endpoints.dart';
import 'api_service.dart';

/// Artist business service — API/data layer.
class ArtistBusinessService {
  final ApiService _api;
  ArtistBusinessService(this._api);

  Map<String, String> _page({int? pageNum, int? limit, String? sortBy, String? sortOrder, String? filterKey, String? filterValue, String? searchKey}) => {
        if (pageNum != null) 'page_num': '$pageNum',
        if (limit != null) 'limit': '$limit',
        if (sortBy != null) 'sort_by': sortBy,
        if (sortOrder != null) 'sort_order': sortOrder,
        if (filterKey != null) 'filter_key': filterKey,
        if (filterValue != null) 'filter_value': filterValue,
        if (searchKey != null) 'search_key': searchKey,
      };

  // ───────────────────────── Onboarding ─────────────────────────

  /// API: GET /artists/onboarding/status/ — checklist + overall status.
  Future<OnboardingStatus> getOnboardingStatus() async {
    final r = await _api.get(ApiEndpoints.artistsOnboardingStatus);
    return OnboardingStatus.fromJson(unwrapMap(jsonDecode(r.body)));
  }

  /// API: GET /artists/onboarding/status/ — raw `data` map (for fields the model does not carry).
  Future<Map<String, dynamic>> getOnboardingStatusRaw() async {
    final r = await _api.get(ApiEndpoints.artistsOnboardingStatus);
    return unwrapMap(jsonDecode(r.body));
  }

  /// API: POST /artists/onboarding/submit/ — 400 lists every unfinished step; on success status = submitted.
  Future<void> submitOnboarding() async {
    await _api.post(ApiEndpoints.artistsOnboardingSubmit);
  }

  /// API: GET /artists/review/feedback/get_all/ — admin feedback history (newest first; sort_order=asc for oldest).
  Future<List<ReviewFeedback>> getReviewFeedback({String? sortOrder}) async {
    final r = await _api.get(ApiEndpoints.artistsReviewFeedbackGetAll,
        queryParameters: _page(sortOrder: sortOrder));
    return unwrapList(jsonDecode(r.body)).map(ReviewFeedback.fromJson).toList();
  }

  /// API: PUT /artists/profile/agreement/accept/ — Terms & Privacy accepted (links from [getPages]).
  Future<void> acceptAgreement() async {
    await _api.put(ApiEndpoints.artistsProfileAgreementAccept);
  }

  /// API: GET /core/pages/get/ — Terms, Privacy, Contact (null until configured). Public.
  Future<Map<String, dynamic>> getPages() async {
    final r = await _api.get(ApiEndpoints.corePagesGet);
    return unwrapMap(jsonDecode(r.body));
  }

  // ───────────────────────── KYC documents ─────────────────────────

  /// API: POST /artists/documents/create/ (multipart).
  /// ID proof needs [idType] (aadhaar | voter_id | passport | driving_licence) + [documentNumber];
  /// [back] is required for aadhaar, voter_id and driving_licence. A new ID proof replaces the old one
  /// and goes back to `pending`. Files: JPEG/PNG/WEBP or PDF, max 5 MB.
  Future<void> createDocument({
    String documentType = 'id_proof',
    String? idType,
    String? documentNumber,
    required XFile file,
    XFile? backFile,
  }) async {
    await _api.postMultipart(
      ApiEndpoints.artistsDocumentsCreate,
      fields: {
        'document_type': documentType,
        if (idType != null) 'id_type': idType,
        if (documentNumber != null && documentNumber.isNotEmpty) 'document_number': documentNumber,
      },
      files: [
        UploadFile('file', file.path, filename: file.name),
        if (backFile != null) UploadFile('back_file', backFile.path, filename: backFile.name),
      ],
    );
  }

  /// API: GET /artists/documents/get_all/ — number is masked; status pending | approved | rejected.
  Future<List<ArtistDocument>> getDocuments() async {
    final r = await _api.get(ApiEndpoints.artistsDocumentsGetAll);
    return unwrapList(jsonDecode(r.body)).map(ArtistDocument.fromJson).toList();
  }

  /// API: GET /artists/documents/get/
  Future<ArtistDocument> getDocument(int documentId) async {
    final r = await _api.get(ApiEndpoints.artistsDocumentsGet, queryParameters: {'document_id': '$documentId'});
    return ArtistDocument.fromJson(unwrapMap(jsonDecode(r.body)));
  }

  /// API: DELETE /artists/documents/delete/ (also deletes the stored files).
  Future<void> deleteDocument(int documentId) async {
    await _api.delete(ApiEndpoints.artistsDocumentsDelete, queryParameters: {'document_id': '$documentId'});
  }

  /// API: GET /artists/documents/file/ — returns the file BYTES (needs the Bearer header, so a plain
  /// `Image.network` will not work). [side] = 'front' (default) | 'back'. Show with `Image.memory`.
  Future<Uint8List> getDocumentFile(int documentId, {String side = 'front'}) async {
    final r = await _api.get(ApiEndpoints.artistsDocumentsFile,
        queryParameters: {'document_id': '$documentId', 'side': side});
    return r.bodyBytes;
  }

  // ───────────────────────── Payout account ─────────────────────────

  /// API: GET /artists/payout_account/get/ — shows the account number masked only.
  Future<PayoutAccount> getPayoutAccount() async {
    final r = await _api.get(ApiEndpoints.artistsPayoutAccountGet);
    return PayoutAccount.fromJson(unwrapMap(jsonDecode(r.body)));
  }

  /// API: PUT /artists/payout_account/set/ — creates or replaces the single account; changing it resets
  /// verification to pending., account number 6–30 digits only, IFSC exactly 11 characters.
  Future<void> setPayoutAccount({
    required String accountHolderName,
    required String bankAccountNumber,
    required String ifscCode,
    String? upiId,
  }) async {
    await _api.put(ApiEndpoints.artistsPayoutAccountSet, data: {
      'account_holder_name': accountHolderName,
      'bank_account_number': bankAccountNumber,
      'ifsc_code': ifscCode,
      if (upiId != null && upiId.isNotEmpty) 'upi_id': upiId,
    });
  }

  // ───────────────────────── Profile extras ─────────────────────────

  /// API: PUT /artists/profile/accepting_bookings/ — off = hidden from search, cannot be booked
  /// (bookings that already exist are not affected).
  Future<void> setAcceptingBookings(bool value) async {
    await _api.put(ApiEndpoints.artistsProfileAcceptingBookings, data: {'is_accepting_bookings': value});
  }


  /// API: PUT /artists/profile/photo/upload/ (multipart)
  Future<void> uploadProfilePhotos({XFile? profilePhoto, XFile? coverPhoto}) async {
    await _api.putMultipart(
      ApiEndpoints.artistsProfilePhotoUpload,
      files: [
        if (profilePhoto != null) UploadFile('profile_photo', profilePhoto.path, filename: profilePhoto.name),
        if (coverPhoto != null) UploadFile('cover_photo', coverPhoto.path, filename: coverPhoto.name),
      ],
    );
  }

  /// API: DELETE /artists/profile/photo/delete/?kind=profile|cover
  Future<void> deleteProfilePhoto(String kind) async {
    await _api.delete(ApiEndpoints.artistsProfilePhotoDelete, queryParameters: {'kind': kind});
  }

  /// API: GET /artists/profile/share_link/ — stable public link (handle is created on first call).
  Future<String?> getShareLink() async {
    final r = await _api.get(ApiEndpoints.artistsProfileShareLink);
    final m = unwrapMap(jsonDecode(r.body));
    return (m['shareUrl'] ?? m['shareLink'] ?? m['url'] ?? m['link'])?.toString();
  }

  /// API: GET /artists/profile/specialities/get_all/ — sub-category ids the artist specialises in.
  Future<List<int>> getSpecialities() async {
    final r = await _api.get(ApiEndpoints.artistsProfileSpecialitiesGetAll);
    return unwrapList(jsonDecode(r.body))
        .map((e) => ((e['subCategoryId'] ?? e['sub_category_id']) as num?)?.toInt())
        .whereType<int>()
        .toList();
  }

  /// API: PUT /artists/profile/specialities/set/ — replaces the list. Every id must already be one of the
  /// artist's offered services; max 10; send [] to clear.
  Future<void> setSpecialities(List<int> subCategoryIds) async {
    await _api.put(ApiEndpoints.artistsProfileSpecialitiesSet, data: {'sub_category_ids': subCategoryIds});
  }

  // ───────────────────────── Portfolio / package photo ─────────────────────────

  /// API: PUT /artists/portfolio/reorder/ — ids in the wanted order; unlisted items follow (max 100).
  Future<void> reorderPortfolio(List<int> portfolioIds) async {
    await _api.put(ApiEndpoints.artistsPortfolioReorder, data: {'portfolio_ids': portfolioIds});
  }

  /// API: PUT /artists/packages/photo/upload/ (multipart: package_id + photo; JPEG/PNG/WEBP ≤ 5 MB).
  Future<void> uploadPackagePhoto(int packageId, XFile photo) async {
    await _api.putMultipart(
      ApiEndpoints.artistsPackagesPhotoUpload,
      fields: {'package_id': '$packageId'},
      files: [UploadFile('photo', photo.path, filename: photo.name)],
    );
  }

  /// API: DELETE /artists/packages/photo/delete/
  Future<void> deletePackagePhoto(int packageId) async {
    await _api.delete(ApiEndpoints.artistsPackagesPhotoDelete, queryParameters: {'package_id': '$packageId'});
  }

  // ───────────────────────── Add-ons ─────────────────────────

  /// API: POST /artists/addons/create/ — [packageIds] are the artist's own packages it applies to;
  /// [durationMinutes] (0-480) extends the appointment; price ≥ 1; max 50 linked packages.
  Future<void> createAddOn({
    required String name,
    required double price,
    int durationMinutes = 0,
    String? description,
    List<int> packageIds = const [],
  }) async {
    await _api.post(ApiEndpoints.artistsAddonsCreate, data: {
      'name': name,
      'price': price.toStringAsFixed(2),
      'duration_minutes': durationMinutes,
      if (description != null && description.isNotEmpty) 'description': description,
      'package_ids': packageIds,
    });
  }

  /// API: GET /artists/addons/get_all/
  Future<List<ArtistAddOn>> getAddOns({int? limit, int? pageNum}) async {
    final r = await _api.get(ApiEndpoints.artistsAddonsGetAll, queryParameters: _page(limit: limit ?? 50, pageNum: pageNum));
    return unwrapList(jsonDecode(r.body)).map(ArtistAddOn.fromJson).toList();
  }

  /// API: GET /artists/addons/get/
  Future<ArtistAddOn> getAddOn(int addOnId) async {
    final r = await _api.get(ApiEndpoints.artistsAddonsGet, queryParameters: {'addon_id': '$addOnId'});
    return ArtistAddOn.fromJson(unwrapMap(jsonDecode(r.body)));
  }

  /// API: PUT /artists/addons/update/ — existing bookings are never changed.
  Future<void> updateAddOn(
    int addOnId, {
    String? name,
    double? price,
    int? durationMinutes,
    String? description,
    List<int>? packageIds,
    bool? isActive,
  }) async {
    await _api.put(ApiEndpoints.artistsAddonsUpdate, data: {
      'addon_id': addOnId,
      if (name != null) 'name': name,
      if (price != null) 'price': price.toStringAsFixed(2),
      if (durationMinutes != null) 'duration_minutes': durationMinutes,
      if (description != null) 'description': description,
      if (packageIds != null) 'package_ids': packageIds,
      if (isActive != null) 'is_active': isActive,
    });
  }

  /// API: DELETE /artists/addons/delete/
  Future<void> deleteAddOn(int addOnId) async {
    await _api.delete(ApiEndpoints.artistsAddonsDelete, queryParameters: {'addon_id': '$addOnId'});
  }

  // ───────────────────────── Service areas & travel charge ─────────────────────────

  /// API: POST /artists/service_areas/add/ — travel_charge_type `free`, `per_visit` or `per_km` (+ charge_amount).
  /// NOTE: the backend used to reject `per_km`; the app now sends it again, so the backend must accept it.
  /// Once an area is active, Home Visits are only accepted for addresses in your areas.
  Future<void> addServiceArea({required String city, String travelChargeType = 'free', double? travelCharge}) async {
    await _api.post(ApiEndpoints.artistsServiceAreasAdd, data: {
      'city': city,
      'travel_charge_type': travelChargeType,
      if (travelChargeType == 'per_visit' || travelChargeType == 'per_km') 'charge_amount': (travelCharge ?? 0).toStringAsFixed(2),
    });
  }

  /// API: GET /artists/service_areas/get_all/
  Future<List<ArtistServiceArea>> getServiceAreas() async {
    final r = await _api.get(ApiEndpoints.artistsServiceAreasGetAll, queryParameters: _page(limit: 100));
    return unwrapList(jsonDecode(r.body)).map(ArtistServiceArea.fromJson).toList();
  }

  /// API: PUT /artists/service_areas/update/ — existing bookings keep the travel fee they were created with.
  Future<void> updateServiceArea(int areaId,
      {String? city, String? travelChargeType, double? travelCharge, bool? isActive}) async {
    await _api.put(ApiEndpoints.artistsServiceAreasUpdate, data: {
      'area_id': areaId,
      if (city != null) 'city': city,
      if (travelChargeType != null) 'travel_charge_type': travelChargeType,
      if (travelChargeType == 'free') 'charge_amount': '0.00',
      if (travelCharge != null && travelChargeType != 'free') 'charge_amount': travelCharge.toStringAsFixed(2),
      if (isActive != null) 'is_active': isActive,
    });
  }

  /// API: DELETE /artists/service_areas/remove/?area_id=
  Future<void> removeServiceArea(int areaId) async {
    await _api.delete(ApiEndpoints.artistsServiceAreasRemove, queryParameters: {'area_id': '$areaId'});
  }

  // ───────────────────────── Brands ─────────────────────────

  /// API: GET /core/brands/get_all/ — suggestions for the package "brands" picker.
  Future<List<BrandItem>> getBrands() async {
    final r = await _api.get(ApiEndpoints.coreBrandsGetAll, queryParameters: _page(limit: 200));
    return unwrapList(jsonDecode(r.body)).map(BrandItem.fromJson).toList();
  }

  /// API: POST /artists/brands/request/ — ask for a missing brand (max 5 pending).
  Future<void> requestBrand(String name) async {
    await _api.post(ApiEndpoints.artistsBrandsRequest, data: {'name': name});
  }

  /// API: GET /artists/brands/requests/get_all/
  Future<List<BrandRequest>> getBrandRequests() async {
    final r = await _api.get(ApiEndpoints.artistsBrandsRequestsGetAll, queryParameters: _page(limit: 50));
    return unwrapList(jsonDecode(r.body)).map(BrandRequest.fromJson).toList();
  }

  // ───────────────────────── Customer reviews written by the artist ─────────────────────────

  /// API: GET /artists/customer_reviews/get_all/ — the customer reviews this artist wrote.
  /// One booking: filter_key=bookingId (rows: customerReviewId, bookingId, customerId, customerName, rating, comment).
  Future<List<Map<String, dynamic>>> getCustomerReviewsGiven({int? bookingId}) async {
    final r = await _api.get(
      ApiEndpoints.artistsCustomerReviewsGetAll,
      queryParameters: _page(
        limit: 50,
        filterKey: bookingId == null ? null : 'bookingId',
        filterValue: bookingId == null ? null : '$bookingId',
      ),
    );
    return unwrapList(jsonDecode(r.body));
  }

  // ───────────────────────── Reschedule (artist proposes) ─────────────────────────

  /// API: POST /artists/bookings/reschedule/request/ — only `confirmed` bookings the artist has not set off for;
  /// one open request per booking; the new slot must pass all booking rules (≥ 2 h ahead, buffers, hours).
  /// [proposedDate] is DD-MM-YY, [proposedStartTime] HH:MM.
  Future<void> requestReschedule({
    required int bookingId,
    required String proposedDate,
    required String proposedStartTime,
    String? reason,
  }) async {
    await _api.post(ApiEndpoints.artistBookingsRescheduleRequest, data: {
      'booking_id': bookingId,
      'proposed_date': proposedDate,
      'proposed_start_time': proposedStartTime,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
  }

  /// API: PUT /artists/bookings/reschedule/cancel/ — artist withdraws their own pending request.
  Future<void> cancelReschedule({required int rescheduleId}) async {
    await _api.put(ApiEndpoints.artistBookingsRescheduleCancel, data: {'reschedule_id': rescheduleId});
  }

  /// API: GET /artists/bookings/reschedule/get_all/ — newest first; one booking via filter_key=bookingId.
  Future<List<RescheduleRequestItem>> getReschedules({int? bookingId, int? pageNum, int? limit}) async {
    final r = await _api.get(ApiEndpoints.artistBookingsRescheduleGetAll, queryParameters: {
      ..._page(
        pageNum: pageNum,
        limit: limit,
        filterKey: bookingId != null ? 'bookingId' : null,
        filterValue: bookingId?.toString(),
      ),
    });
    return unwrapList(jsonDecode(r.body)).map(RescheduleRequestItem.fromJson).toList();
  }

  // ───────────────────────── Reviews ─────────────────────────

  /// API: GET /artists/reviews/get_all/ — reviews now include `reply` and `repliedAt`.
  Future<List<ArtistReviewItem>> getReviews({int? pageNum, int? limit}) async {
    final r = await _api.get(ApiEndpoints.artistsReviewsGetAll, queryParameters: _page(pageNum: pageNum, limit: limit));
    return unwrapList(jsonDecode(r.body)).map(ArtistReviewItem.fromJson).toList();
  }

  /// API: PUT /artists/reviews/reply/ — replying again edits the reply.
  Future<void> replyToReview({required int reviewId, required String reply}) async {
    await _api.put(ApiEndpoints.artistsReviewsReply, data: {'review_id': reviewId, 'reply': reply});
  }

  /// API: POST /artists/customer_reviews/create/ — rate the customer after a completed booking
  /// (once per booking, private to the artist).
  Future<void> reviewCustomer({required int bookingId, required int rating, String? comment}) async {
    await _api.post(ApiEndpoints.artistsCustomerReviewsCreate, data: {
      'booking_id': bookingId,
      'rating': rating,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    });
  }

  // ───────────────────────── Clients & insights ─────────────────────────

  /// API: GET /artists/clients/get_all/ — customers with a confirmed / started / completed booking.
  /// sort_by: name | lastBookingDate | bookingsCount; search_key matches the name.
  Future<List<ArtistClient>> getClients({int? pageNum, int? limit, String? sortBy, String? sortOrder, String? searchKey}) async {
    final r = await _api.get(ApiEndpoints.artistsClientsGetAll,
        queryParameters: _page(pageNum: pageNum, limit: limit, sortBy: sortBy, sortOrder: sortOrder, searchKey: searchKey));
    return unwrapList(jsonDecode(r.body)).map(ArtistClient.fromJson).toList();
  }

  /// API: PUT /artists/clients/note/set/ — private note (max 1000); a blank note clears it.
  Future<void> setClientNote({required int customerId, required String note}) async {
    await _api.put(ApiEndpoints.artistsClientsNoteSet, data: {'customer_id': customerId, 'note': note});
  }

  /// API: GET /artists/insights/summary/ — bookings by status, repeat clients, top services,
  /// lifetime profile views, optional from_date / to_date (DD-MM-YY). No earnings (payouts not exposed).
  Future<InsightsSummary> getInsights({String? fromDate, String? toDate}) async {
    final r = await _api.get(ApiEndpoints.artistsInsightsSummary, queryParameters: {
      if (fromDate != null) 'from_date': fromDate,
      if (toDate != null) 'to_date': toDate,
    });
    return InsightsSummary.fromJson(unwrapMap(jsonDecode(r.body)));
  }

  // ───────────────────────── Support tickets ─────────────────────────

  /// API: POST /help_center/tickets/create/ (multipart) — issue_type: booking | payment | service_quality |
  /// account | technical | other; subject ≤ 150, description ≤ 2000, optional booking_id (must belong to the user),
  /// up to 5 attachments (images or PDF ≤ 5 MB). Max 10 open tickets per user.
  Future<void> createTicket({
    required String issueType,
    required String subject,
    required String description,
    int? bookingId,
    List<XFile> attachments = const [],
  }) async {
    await _api.postMultipart(
      ApiEndpoints.helpCenterTicketsCreate,
      fields: {
        'issue_type': issueType,
        'subject': subject,
        'description': description,
        if (bookingId != null) 'booking_id': '$bookingId',
      },
      files: [for (final f in attachments) UploadFile('attachments', f.path, filename: f.name)],
    );
  }

  /// API: GET /help_center/tickets/get_all/ — filters: filter_key=status|bookingId|issueType.
  Future<List<SupportTicket>> getTickets({String? filterKey, String? filterValue, int? pageNum, int? limit}) async {
    final r = await _api.get(ApiEndpoints.helpCenterTicketsGetAll,
        queryParameters: _page(pageNum: pageNum, limit: limit, filterKey: filterKey, filterValue: filterValue));
    return unwrapList(jsonDecode(r.body)).map(SupportTicket.fromJson).toList();
  }

  /// API: GET /help_center/tickets/get/
  Future<SupportTicket> getTicket(int ticketId) async {
    final r = await _api.get(ApiEndpoints.helpCenterTicketsGet, queryParameters: {'ticket_id': '$ticketId'});
    return SupportTicket.fromJson(unwrapMap(jsonDecode(r.body)));
  }

  /// API: PUT /help_center/tickets/close/
  Future<void> closeTicket(int ticketId) async {
    await _api.put(ApiEndpoints.helpCenterTicketsClose, data: {'ticket_id': ticketId});
  }

  /// API: GET /help_center/tickets/attachment/ — bytes (private; needs the Bearer header).
  Future<Uint8List> getTicketAttachment(int attachmentId) async {
    final r = await _api.get(ApiEndpoints.helpCenterTicketsAttachment, queryParameters: {'attachment_id': '$attachmentId'});
    return r.bodyBytes;
  }

  // ───────────────────────── Change email / phone ─────────────────────────

  /// API: POST /users/contact/change/request/ — send exactly ONE of [email] / [phoneNumber];
  /// a 6-digit code goes to the NEW contact (valid 10 min, one request per minute).
  Future<void> requestContactChange({String? email, String? phoneNumber}) async {
    assert((email != null) != (phoneNumber != null), 'send exactly one of email / phoneNumber');
    await _api.post(ApiEndpoints.usersContactChangeRequest, data: {
      if (email != null) 'email': email,
      if (phoneNumber != null) 'phone_number': phoneNumber,
    });
  }

  /// API: POST /users/contact/change/verify/ — 5 wrong tries burn the code; old contact keeps working for login
  /// until verified, then it is replaced.
  Future<void> verifyContactChange(String otp) async {
    await _api.post(ApiEndpoints.usersContactChangeVerify, data: {'otp': otp});
  }
}
