// FILE: api/api_endpoints.dart
// All backend URL paths in one place (base URL + every endpoint constant).

/// All backend endpoint paths.
class ApiEndpoints {
//  static const String baseUrl = 'https://sundari.checkour.work';

  static const String baseUrl = 'https://app.sunndari.com';

  // Public (no login): artist page by slug -> ?slug=<publicSlug>
  static const String publicArtistGet = '/public/artists/get/';

  static const String authRegister = '/auth/register/';
  static const String authLogin = '/auth/login/';
  static const String authEmailOtpRequest = '/auth/email-otp/request/';
  static const String authEmailOtpVerify = '/auth/email-otp/verify/';
  static const String authPhoneOtpRequest = '/auth/phone-otp/request/';
  static const String authPhoneOtpVerify = '/auth/phone-otp/verify/';
  static const String authGoogle = '/auth/google/';
  static const String authTokenRefresh = '/auth/token/refresh/';
  static const String authPasswordForgot = '/auth/forgot-password/';
  static const String authPasswordReset = '/auth/reset-password/';
  // Not in the Sunndari API guide (security release) — kept only so old callers compile.
  static const String authPasswordSet = '/auth/password/set/';

  static const String artistsProfileGet = '/artists/profile/get/';
  static const String artistsProfileUpdate = '/artists/profile/update/';

  static const String artistsPortfolioCreate = '/artists/portfolio/create/';
  static const String artistsPortfolioGet = '/artists/portfolio/get/';
  static const String artistsPortfolioGetAll = '/artists/portfolio/get_all/';
  static const String artistsPortfolioUpdate = '/artists/portfolio/update/';
  static const String artistsPortfolioDelete = '/artists/portfolio/delete/';

  static const String artistsPackagesCreate = '/artists/packages/create/';
  static const String artistsPackagesGet = '/artists/packages/get/';
  static const String artistsPackagesGetAll = '/artists/packages/get_all/';
  static const String artistsPackagesUpdate = '/artists/packages/update/';
  static const String artistsPackagesDelete = '/artists/packages/delete/';

  static const String artistsServicesAdd = '/artists/services/add/';
  static const String artistsServicesGetAll = '/artists/services/get_all/';
  static const String artistsServicesRemove = '/artists/services/remove/';

  static const String artistsLocationsAdd = '/artists/locations/add/';
  static const String artistsLocationsGetAll = '/artists/locations/get_all/';
  static const String artistsLocationsRemove = '/artists/locations/remove/';

  static const String artistsAvailabilityScheduleSet = '/artists/availability/schedule/set/';
  static const String artistsAvailabilityScheduleGetAll = '/artists/availability/schedule/get_all/';
  static const String artistsAvailabilityScheduleRemove = '/artists/availability/schedule/remove/';
  /// The artist's own day as customers see it — the exact bookable start times, made by the server.
  static const String artistsAvailabilitySlots = '/artists/availability/slots/';
  static const String artistsAvailabilityBlockAdd = '/artists/availability/block/add/';
  static const String artistsAvailabilityBlockGetAll = '/artists/availability/block/get_all/';
  static const String artistsAvailabilityBlockRemove = '/artists/availability/block/remove/';

  // ── Artist profile extras (Sunndari API – security & features release) ──
  static const String artistsProfileAcceptingBookings = '/artists/profile/accepting_bookings/';
  static const String artistsProfilePhotoUpload = '/artists/profile/photo/upload/';
  static const String artistsProfilePhotoDelete = '/artists/profile/photo/delete/';
  static const String artistsProfileShareLink = '/artists/profile/share_link/';
  static const String artistsProfileSpecialitiesGetAll = '/artists/profile/specialities/get_all/';
  static const String artistsProfileSpecialitiesSet = '/artists/profile/specialities/set/';
  static const String artistsProfileAgreementAccept = '/artists/profile/agreement/accept/';

  // ── Onboarding / KYC documents / payout account ──
  static const String artistsOnboardingStatus = '/artists/onboarding/status/';
  static const String artistsOnboardingSubmit = '/artists/onboarding/submit/';
  static const String artistsReviewFeedbackGetAll = '/artists/review/feedback/get_all/';
  static const String artistsDocumentsCreate = '/artists/documents/create/';
  static const String artistsDocumentsGet = '/artists/documents/get/';
  static const String artistsDocumentsGetAll = '/artists/documents/get_all/';
  static const String artistsDocumentsDelete = '/artists/documents/delete/';
  static const String artistsDocumentsFile = '/artists/documents/file/';
  static const String artistsPayoutAccountGet = '/artists/payout_account/get/';
  static const String artistsPayoutAccountSet = '/artists/payout_account/set/';

  // ── Artist registration fee (paid in onboarding, BEFORE submitting for admin review) ──
  static const String artistsRegistrationFee = '/artists/registration/fee/';
  static const String artistsRegistrationPromoValidate = '/artists/registration/promo/validate/';
  static const String artistsRegistrationPaymentInitiate = '/artists/registration/payment/initiate/';
  static const String artistsRegistrationPaymentVerify = '/artists/registration/payment/verify/';

  // ── Catalogue: portfolio order, package photo, add-ons, service areas, brands ──
  static const String artistsPortfolioReorder = '/artists/portfolio/reorder/';
  static const String artistsPackagesPhotoUpload = '/artists/packages/photo/upload/';
  static const String artistsPackagesPhotoDelete = '/artists/packages/photo/delete/';
  static const String artistsAddonsCreate = '/artists/addons/create/';
  static const String artistsAddonsGet = '/artists/addons/get/';
  static const String artistsAddonsGetAll = '/artists/addons/get_all/';
  static const String artistsAddonsUpdate = '/artists/addons/update/';
  static const String artistsAddonsDelete = '/artists/addons/delete/';
  static const String artistsServiceAreasAdd = '/artists/service_areas/add/';
  static const String artistsServiceAreasGetAll = '/artists/service_areas/get_all/';
  static const String artistsServiceAreasRemove = '/artists/service_areas/remove/';
  static const String artistsServiceAreasUpdate = '/artists/service_areas/update/';
  // Salon addresses (the salons / studios an artist works from; max 10 active)
  static const String artistsSalonAddressesCreate = '/artists/salon_addresses/create/';
  static const String artistsSalonAddressesGetAll = '/artists/salon_addresses/get_all/';
  static const String artistsSalonAddressesUpdate = '/artists/salon_addresses/update/';
  static const String artistsSalonAddressesDelete = '/artists/salon_addresses/delete/';
  static const String artistsBrandsRequest = '/artists/brands/request/';
  static const String artistsBrandsRequestsGetAll = '/artists/brands/requests/get_all/';
  static const String coreBrandsGetAll = '/core/brands/get_all/';
  static const String corePagesGet = '/core/pages/get/';

  // ── Bookings & business ──
  static const String artistBookingsRescheduleRequest = '/artists/bookings/reschedule/request/';
  static const String artistBookingsRescheduleCancel = '/artists/bookings/reschedule/cancel/';
  static const String artistBookingsRescheduleGetAll = '/artists/bookings/reschedule/get_all/';
  static const String artistsReviewsGetAll = '/artists/reviews/get_all/';
  static const String artistsReviewsReply = '/artists/reviews/reply/';
  static const String artistsCustomerReviewsCreate = '/artists/customer_reviews/create/';
  static const String artistsCustomerReviewsGetAll = '/artists/customer_reviews/get_all/';
  static const String artistsClientsGetAll = '/artists/clients/get_all/';
  static const String artistsClientsNoteSet = '/artists/clients/note/set/';
  static const String artistsInsightsSummary = '/artists/insights/summary/';

  // ── Contact change (email / phone) ──
  static const String usersContactChangeRequest = '/users/contact/change/request/';
  static const String usersContactChangeVerify = '/users/contact/change/verify/';

  // ── Support tickets ──
  static const String helpCenterTicketsCreate = '/help_center/tickets/create/';
  static const String helpCenterTicketsGet = '/help_center/tickets/get/';
  static const String helpCenterTicketsGetAll = '/help_center/tickets/get_all/';
  static const String helpCenterTicketsClose = '/help_center/tickets/close/';
  static const String helpCenterTicketsAttachment = '/help_center/tickets/attachment/';

  static const String usersProfileGet = '/users/profile/get/';
  static const String usersProfileUpdate = '/users/profile/update/';

  static const String usersAddressCreate = '/users/address/create/';
  static const String usersAddressGet = '/users/address/get/';
  static const String usersAddressGetAll = '/users/address/get_all/';
  static const String usersAddressUpdate = '/users/address/update/';
  static const String usersAddressDelete = '/users/address/delete/';

  static const String coreApprovalStatusGetAll = '/core/approval-status/get_all/';
  static const String coreBookingStatusGetAll = '/core/booking-status/get_all/';
  static const String corePaymentStatusGetAll = '/core/payment-status/get_all/';
  static const String coreLocationTypeGet = '/core/location-type/get/';
  static const String coreLocationTypeGetAll = '/core/location-type/get_all/';
  static const String coreServiceCategoryGet = '/core/service-category/get/';
  static const String coreServiceCategoryGetAll = '/core/service-category/get_all/';
  static const String coreServiceSubCategoryGet = '/core/service-sub-category/get/';
  static const String coreServiceSubCategoryGetAll = '/core/service-sub-category/get_all/';
  /// Artist only: services the admin announced in the last 15 days that this artist has not added yet.
  static const String coreServiceSubCategoryRecentlyActivated = '/core/service-sub-category/recently_activated/';

  static const String apiSchema = '/api/schema/';

  static const String artistBookingsGet = '/artists/bookings/get/';
  static const String artistBookingsGetAll = '/artists/bookings/get_all/';
  static const String artistBookingsUpdateStatus = '/artists/bookings/update_status/';
  static const String artistBookingsOnMyWay = '/artists/bookings/on_my_way/';
  static const String artistBookingsArrived = '/artists/bookings/arrived/';
  /// In-Salon only: the artist taps "Start Service" → backend creates the Start Service PIN and notifies the customer.
  static const String artistBookingsStartPinRequest = '/artists/bookings/start_pin/request/';
  static const String artistBookingsStartPinVerify = '/artists/bookings/start_pin/verify/';
  /// Photo of the finished service (camera): PUT multipart booking_id + photo. Needed before the completion PIN.
  static const String artistBookingsCompletionProofUpload = '/artists/bookings/completion_proof/upload/';
  /// The completion photo itself (authenticated image): GET ?booking_id=
  static const String artistBookingsCompletionProofFile = '/artists/bookings/completion_proof/file/';
  /// Artist taps "Complete service" → backend creates the Completion PIN and notifies the customer.
  static const String artistBookingsCompletionPinRequest = '/artists/bookings/completion_pin/request/';
  static const String artistBookingsCompletionPinVerify = '/artists/bookings/completion_pin/verify/';
  /// Advance (20%) bookings: the artist answers Yes / No "did you receive the rest?" before completing. PUT {booking_id, received}.
  static const String artistBookingsBalanceConfirm = '/artists/bookings/balance/confirm/';

  static const String notificationsGet = '/notifications/get/';
  static const String notificationsGetAll = '/notifications/get_all/';
  static const String notificationsMarkRead = '/notifications/mark_read/';
  static const String notificationsMarkAllRead = '/notifications/mark_all_read/';

  static const String chatConversationGet = '/chat/conversation/get/';
  static const String chatMessagesGetAll = '/chat/messages/get_all/';
  static const String chatMessagesCreate = '/chat/messages/create/';

  static const String helpCenterConversationGet = '/help_center/artist/conversation/get/';
  static const String helpCenterMessagesGetAll = '/help_center/artist/messages/get_all/';
  static const String helpCenterMessagesCreate = '/help_center/artist/messages/create/';
}