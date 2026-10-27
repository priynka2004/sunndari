// FILE: models/artist/artist_extras.dart  |  MODELS
// Models for the Sunndari API security & features release (artist side):
// add-ons, service areas, KYC documents, payout account, onboarding status,
// brands, reviews, clients, insights, reschedule requests, support tickets.
// All parsers are tolerant (missing / null / string-number values never throw).

double _d(dynamic v, [double fb = 0]) {
  if (v == null) return fb;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? fb;
}

int _i(dynamic v, [int fb = 0]) {
  if (v == null) return fb;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fb;
}

String? _s(dynamic v) => v == null ? null : v.toString();
bool _b(dynamic v, [bool fb = false]) => v == null ? fb : (v is bool ? v : v.toString() == 'true');

/// Reads `data` out of an envelope, or returns the map itself.
Map<String, dynamic> unwrapMap(dynamic json) {
  if (json is Map && json['data'] is Map) return Map<String, dynamic>.from(json['data'] as Map);
  if (json is Map) return Map<String, dynamic>.from(json);
  return <String, dynamic>{};
}

/// Reads a list out of `data` / `data.data` / a bare list.
List<Map<String, dynamic>> unwrapList(dynamic json) {
  dynamic d = json;
  if (d is Map && d['data'] != null) d = d['data'];
  if (d is Map && d['data'] != null) d = d['data'];
  if (d is! List) return const [];
  return d.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

// ───────────────────────── Add-ons ─────────────────────────

/// Artist add-on (extra service). price >= 1, extra duration 0-480 min, max 50 linked packages.
class ArtistAddOn {
  final int addOnId;
  final String name;
  final double price;
  final int durationMinutes;
  final String? description;
  final bool isActive;
  final List<int> packageIds;

  const ArtistAddOn({
    required this.addOnId,
    required this.name,
    required this.price,
    this.durationMinutes = 0,
    this.description,
    this.isActive = true,
    this.packageIds = const [],
  });

  factory ArtistAddOn.fromJson(Map<String, dynamic> j) => ArtistAddOn(
        addOnId: _i(j['addOnId'] ?? j['addonId']),
        name: (j['name'] ?? '').toString(),
        price: _d(j['price']),
        durationMinutes: _i(j['durationMinutes']),
        description: _s(j['description']),
        isActive: _b(j['isActive'], true),
        packageIds: ((j['packageIds'] ?? j['packages']) is List)
            ? ((j['packageIds'] ?? j['packages']) as List).map((e) => e is Map ? _i(e['packageId']) : _i(e)).toList()
            : const [],
      );
}

// ───────────────────────── Service areas ─────────────────────────

/// Area the artist travels to. Travel charge is `free`, `per_visit` or `per_km`.
class ArtistServiceArea {
  final int serviceAreaId;
  final String city;
  final String travelChargeType; // free | per_visit | per_km
  final double travelCharge;
  final bool isActive;

  const ArtistServiceArea({
    required this.serviceAreaId,
    required this.city,
    this.travelChargeType = 'free',
    this.travelCharge = 0,
    this.isActive = true,
  });

  factory ArtistServiceArea.fromJson(Map<String, dynamic> j) => ArtistServiceArea(
        serviceAreaId: _i(j['areaId'] ?? j['serviceAreaId']),
        city: (j['city'] ?? j['areaName'] ?? '').toString(),
        travelChargeType: (j['travelChargeType'] ?? 'free').toString(),
        travelCharge: _d(j['chargeAmount'] ?? j['travelCharge'] ?? j['travelChargeAmount']),
        isActive: _b(j['isActive'], true),
      );
}

// ───────────────────────── KYC documents ─────────────────────────

/// Uploaded KYC / ID document. Number is returned masked; the file needs the Bearer header.
class ArtistDocument {
  final int documentId;
  final String documentType; // id_proof | address_proof | certification
  final String? idType; // aadhaar | voter_id | passport | driving_licence
  final String? documentNumberMasked;
  final int? verificationStatusId; // map with GET /core/approval-status/get_all/ (pending | approved | rejected)
  final String verificationStatus; // only if the server also sends a name; otherwise resolve the id
  final String? rejectionReason;
  final String? fileUrl; // API route — fetch with the Bearer header
  final bool hasBackFile;

  const ArtistDocument({
    required this.documentId,
    required this.documentType,
    this.idType,
    this.documentNumberMasked,
    this.verificationStatusId,
    this.verificationStatus = '',
    this.rejectionReason,
    this.fileUrl,
    this.hasBackFile = false,
  });

  factory ArtistDocument.fromJson(Map<String, dynamic> j) => ArtistDocument(
        documentId: _i(j['documentId']),
        documentType: (j['documentType'] ?? 'id_proof').toString(),
        idType: _s(j['idType']),
        documentNumberMasked: _s(j['documentNumber'] ?? j['documentNumberMasked']),
        verificationStatusId: j['verificationStatusId'] == null ? null : _i(j['verificationStatusId']),
        verificationStatus: (j['verificationStatus'] ?? '').toString(),
        rejectionReason: _s(j['rejectionReason']),
        fileUrl: _s(j['fileUrl']),
        hasBackFile: (j['backFileUrl'] ?? '').toString().isNotEmpty,
      );
}

// ───────────────────────── Payout account ─────────────────────────

/// Bank account saved for payouts. Changing it resets verification to pending.
class PayoutAccount {
  final String accountHolderName;
  final String accountNumberMasked;
  final String ifscCode;
  final String? upiId;
  final int? verificationStatusId;

  const PayoutAccount({
    this.accountHolderName = '',
    this.accountNumberMasked = '',
    this.ifscCode = '',
    this.upiId,
    this.verificationStatusId,
  });

  bool get isSaved => accountNumberMasked.isNotEmpty && ifscCode.isNotEmpty;

  factory PayoutAccount.fromJson(Map<String, dynamic> j) => PayoutAccount(
        accountHolderName: (j['accountHolderName'] ?? j['bankAccountHolderName'] ?? '').toString(),
        accountNumberMasked:
            (j['bankAccountNumberMasked'] ?? j['accountNumberMasked'] ?? j['bankAccountNumber'] ?? '').toString(),
        ifscCode: (j['ifscCode'] ?? '').toString(),
        upiId: _s(j['upiId']),
        verificationStatusId: j['verificationStatusId'] == null ? null : _i(j['verificationStatusId']),
      );
}

// ───────────────────────── Onboarding status ─────────────────────────

/// Checklist from GET /artists/onboarding/status/. Keys: basicInfo, registrationFields, location,
/// services, availability, workSamples, documents, payoutAccount, agreement.
class OnboardingStatus {
  final String status; // not_started | in_progress | submitted | approved | rejected | suspended
  final Map<String, bool> steps;
  final String? rejectionReason;
  final bool canSubmit;

  const OnboardingStatus({
    this.status = 'not_started',
    this.steps = const {},
    this.rejectionReason,
    this.canSubmit = false,
  });

  bool get isApproved => status == 'approved';
  bool get isSubmitted => status == 'submitted';
  bool get isRejected => status == 'rejected';
  bool get isSuspended => status == 'suspended';
  bool done(String key) => steps[key] == true;
  List<String> get pendingSteps => steps.entries.where((e) => !e.value).map((e) => e.key).toList();

  factory OnboardingStatus.fromJson(Map<String, dynamic> j) {
    final raw = j['steps'];
    final steps = <String, bool>{};
    if (raw is Map) {
      raw.forEach((k, v) => steps['$k'] = v == true);
    } else if (raw is List) {
      for (final e in raw) {
        if (e is Map) steps['${e['key']}'] = e['done'] == true;
      }
    }
    final allDone = steps.isNotEmpty && steps.values.every((v) => v);
    // latestFeedback: null or the last admin decision {decision, message, ...}
    final fb = j['latestFeedback'];
    String? reason = _s(j['rejectionReason']);
    if (fb is Map && (fb['decision'] == null || fb['decision'] == 'rejected')) {
      reason ??= _s(fb['message'] ?? fb['reason'] ?? fb['rejectionReason']);
    }
    return OnboardingStatus(
      status: (j['status'] ?? 'not_started').toString(),
      steps: steps,
      rejectionReason: reason,
      canSubmit: allDone,
    );
  }
}

/// One admin feedback entry from GET /artists/review/feedback/get_all/.
class ReviewFeedback {
  final String decision; // approved | rejected
  final String? message;
  final String? createdAt;

  const ReviewFeedback({required this.decision, this.message, this.createdAt});

  factory ReviewFeedback.fromJson(Map<String, dynamic> j) => ReviewFeedback(
        decision: (j['decision'] ?? '').toString(),
        message: _s(j['message'] ?? j['reason'] ?? j['rejectionReason']),
        createdAt: _s(j['createdAt']),
      );
}

// ───────────────────────── Brands ─────────────────────────

/// Brand suggestion from /core/brands/get_all/.
class BrandItem {
  final int brandId;
  final String name;

  const BrandItem({required this.brandId, required this.name});

  factory BrandItem.fromJson(Map<String, dynamic> j) =>
      BrandItem(brandId: _i(j['brandId']), name: (j['name'] ?? '').toString());
}

/// Brand request made by the artist (max 5 pending).
class BrandRequest {
  final int requestId;
  final String name;
  final String status; // pending | approved | rejected

  const BrandRequest({required this.requestId, required this.name, this.status = 'pending'});

  factory BrandRequest.fromJson(Map<String, dynamic> j) => BrandRequest(
        requestId: _i(j['requestId'] ?? j['brandRequestId']),
        name: (j['name'] ?? j['brandName'] ?? '').toString(),
        status: (j['status'] ?? 'pending').toString(),
      );
}

// ───────────────────────── Reviews / clients / insights ─────────────────────────

/// Customer review of the artist (with optional artist reply).
class ArtistReviewItem {
  final int reviewId;
  final int? bookingId;
  final int rating;
  final String? comment;
  final String? customerName;
  final String? reply;
  final String? repliedAt;
  final String? createdAt;

  const ArtistReviewItem({
    required this.reviewId,
    this.bookingId,
    this.rating = 0,
    this.comment,
    this.customerName,
    this.reply,
    this.repliedAt,
    this.createdAt,
  });

  factory ArtistReviewItem.fromJson(Map<String, dynamic> j) => ArtistReviewItem(
        reviewId: _i(j['reviewId']),
        bookingId: j['bookingId'] == null ? null : _i(j['bookingId']),
        rating: _i(j['rating']),
        comment: _s(j['comment']),
        customerName: _s(j['customerName']),
        reply: _s(j['reply']),
        repliedAt: _s(j['repliedAt']),
        createdAt: _s(j['createdAt']),
      );
}

/// Customer with a confirmed / started / completed booking. `note` is private to the artist.
class ArtistClient {
  final int customerId;
  final String name;
  final int bookingCount;
  final double totalSpent;
  final String? lastBookingAt;
  final String? note;

  const ArtistClient({
    required this.customerId,
    required this.name,
    this.bookingCount = 0,
    this.totalSpent = 0,
    this.lastBookingAt,
    this.note,
  });

  factory ArtistClient.fromJson(Map<String, dynamic> j) => ArtistClient(
        customerId: _i(j['customerId']),
        name: (j['name'] ?? j['customerName'] ?? '').toString(),
        bookingCount: _i(j['bookingsCount'] ?? j['bookingCount'] ?? j['totalBookings']),
        totalSpent: _d(j['totalSpent'] ?? j['lifetimeValue']),
        lastBookingAt: _s(j['lastBookingDate'] ?? j['lastBookingAt']),
        note: _s(j['note']),
      );
}

/// GET /artists/insights/summary/ — bookings by status, repeat clients, most-booked services, profile views.
/// Earnings are not included yet. Optional from_date / to_date (dd-mm-yy) filter on the booking date.
class InsightsSummary {
  final int totalBookings;
  final Map<String, int> bookingsByStatus;
  final int completedBookings;
  final int cancelledBookings;
  final int repeatClients;
  final List<TopService> topServices;
  final int profileViews;

  const InsightsSummary({
    this.totalBookings = 0,
    this.bookingsByStatus = const {},
    this.completedBookings = 0,
    this.cancelledBookings = 0,
    this.repeatClients = 0,
    this.topServices = const [],
    this.profileViews = 0,
  });

  int statusCount(String name) => bookingsByStatus[name] ?? 0;

  factory InsightsSummary.fromJson(Map<String, dynamic> j) {
    final by = <String, int>{};
    final raw = j['bookingsByStatus'];
    if (raw is Map) raw.forEach((k, v) => by['$k'] = _i(v));
    return InsightsSummary(
      totalBookings: _i(j['totalBookings']),
      bookingsByStatus: by,
      completedBookings: _i(j['completedBookings'] ?? by['completed']),
      cancelledBookings: _i(j['cancelledBookings'] ?? by['cancelled']),
      repeatClients: _i(j['repeatClients']),
      topServices: ((j['topServices'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => TopService.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      profileViews: _i(j['profileViews'] ?? j['profileViewCount']),
    );
  }
}

/// One entry of topServices: {subCategoryId, name, bookings}.
class TopService {
  final int subCategoryId;
  final String name;
  final int bookings;

  const TopService({required this.subCategoryId, required this.name, required this.bookings});

  factory TopService.fromJson(Map<String, dynamic> j) =>
      TopService(subCategoryId: _i(j['subCategoryId']), name: (j['name'] ?? '').toString(), bookings: _i(j['bookings']));
}

// ───────────────────────── Reschedule (artist proposes a new time) ─────────────────────────

/// Server-side reschedule request (artist proposes → customer answers):
/// pending → accepted | rejected | cancelled | expired.
class RescheduleRequestItem {
  final int requestId; // rescheduleId
  final int bookingId;
  final String status;
  final String? previousDate; // YYYY-MM-DD
  final String? previousStartTime; // HH:MM:SS
  final String? proposedDate;
  final String? proposedStartTime;
  final String? reason;
  final String? expiresAt;
  final String? createdAt;

  const RescheduleRequestItem({
    required this.requestId,
    required this.bookingId,
    required this.status,
    this.previousDate,
    this.previousStartTime,
    this.proposedDate,
    this.proposedStartTime,
    this.reason,
    this.expiresAt,
    this.createdAt,
  });

  bool get isPending => status == 'pending';

  factory RescheduleRequestItem.fromJson(Map<String, dynamic> j) => RescheduleRequestItem(
        requestId: _i(j['rescheduleId']),
        bookingId: _i(j['bookingId']),
        status: (j['status'] ?? 'pending').toString(),
        previousDate: _s(j['previousDate']),
        previousStartTime: _s(j['previousStartTime']),
        proposedDate: _s(j['proposedDate']),
        proposedStartTime: _s(j['proposedStartTime']),
        reason: _s(j['reason']),
        expiresAt: _s(j['expiresAt']),
        createdAt: _s(j['createdAt']),
      );
}

// ───────────────────────── Support tickets ─────────────────────────

/// Help-center ticket. Max 10 open tickets per user; status open → in_progress → resolved → closed.
class SupportTicket {
  final int ticketId;
  final String issueType; // booking | payment | service_quality | account | technical | other
  final String subject;
  final String? description;
  final String status;
  final int? bookingId;
  final String? resolutionNote;
  final List<TicketAttachment> attachments;
  final String? createdAt;

  const SupportTicket({
    required this.ticketId,
    required this.issueType,
    required this.subject,
    this.description,
    this.status = 'open',
    this.bookingId,
    this.resolutionNote,
    this.attachments = const [],
    this.createdAt,
  });

  bool get isClosed => status == 'closed' || status == 'resolved';

  factory SupportTicket.fromJson(Map<String, dynamic> j) => SupportTicket(
        ticketId: _i(j['ticketId']),
        issueType: (j['issueType'] ?? 'other').toString(),
        subject: (j['subject'] ?? '').toString(),
        description: _s(j['description']),
        status: (j['status'] ?? 'open').toString(),
        bookingId: j['bookingId'] == null ? null : _i(j['bookingId']),
        resolutionNote: _s(j['resolutionNote']),
        attachments: ((j['attachments'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => TicketAttachment.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        createdAt: _s(j['createdAt']),
      );
}

/// Ticket attachment — private; fetch bytes with the Bearer header.
class TicketAttachment {
  final int attachmentId;
  final String? fileName;
  final String? url;

  const TicketAttachment({required this.attachmentId, this.fileName, this.url});

  factory TicketAttachment.fromJson(Map<String, dynamic> j) => TicketAttachment(
        attachmentId: _i(j['attachmentId']),
        fileName: _s(j['fileName']),
        url: _s(j['url'] ?? j['fileUrl']),
      );
}
