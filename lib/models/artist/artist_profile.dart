// FILE: models/artist/artist_profile.dart  |  MODEL
// Artist profile returned by GET /artists/profile/get/.
// Own profile = full; another artist's profile = public subset only (new fields may be null).

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

DateTime _dt(dynamic v) => DateTime.tryParse('${v ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);

/// Model: Artist Profile.
class ArtistProfile {
  final int artistId;
  final int userId;
  final String? bio;
  final int yearsExperience;
  final String? city;
  final double avgRating;
  final int totalReviews;
  final double commissionRate;
  final int? approvalStatusId;
  final DateTime createdAt;
  final DateTime updatedAt;

  // New in the security & features release
  final String? displayName;
  final String? dateOfBirth; // YYYY-MM-DD (own profile only)
  final String? instagramUrl;
  final String? profileType; // freelance | studio — first item of [profileTypes]
  /// Work types: one or both of `freelance` / `studio` (the server keeps `profileType` for older apps).
  final List<String> profileTypes;
  /// One of `0-1`, `1-3`, `3-5`, `5-10`, `10+` — or null until the artist picks one (then use [yearsExperience]).
  final String? experienceRange;
  final List<int> specialities; // sub-category ids
  final String? profilePhotoUrl;
  final String? coverPhotoUrl;
  final bool isAcceptingBookings;
  final bool registrationEligible; // fee paid or exempt (own profile only)
  final bool acceptingLockedByAdmin; // an admin switched bookings off (own profile only)
  final String? publicSlug;
  final int profileViewCount;
  final int travelTimeBeforeMinutes;
  final int returnBufferMinutes;
  final String? agreementVersion;
  final String? termsAcceptedAt;
  final String? submittedForReviewAt;
  final String? rejectionReason;
  final int? baseAddressId;

  ArtistProfile({
    required this.artistId,
    required this.userId,
    this.bio,
    required this.yearsExperience,
    this.city,
    required this.avgRating,
    required this.totalReviews,
    required this.commissionRate,
    this.approvalStatusId,
    required this.createdAt,
    required this.updatedAt,
    this.displayName,
    this.dateOfBirth,
    this.instagramUrl,
    this.profileType,
    this.profileTypes = const [],
    this.experienceRange,
    this.specialities = const [],
    this.profilePhotoUrl,
    this.coverPhotoUrl,
    this.isAcceptingBookings = false, // new artists start with bookings OFF
    this.registrationEligible = true,
    this.acceptingLockedByAdmin = false,
    this.publicSlug,
    this.profileViewCount = 0,
    this.travelTimeBeforeMinutes = 0,
    this.returnBufferMinutes = 0,
    this.agreementVersion,
    this.termsAcceptedAt,
    this.submittedForReviewAt,
    this.rejectionReason,
    this.baseAddressId,
  });

  /// Builds this object from API JSON.
  factory ArtistProfile.fromJson(Map<String, dynamic> json) => ArtistProfile(
        artistId: _i(json['artistId']),
        userId: _i(json['userId']),
        bio: json['bio'],
        yearsExperience: _i(json['yearsExperience']),
        city: json['city'],
        avgRating: _d(json['avgRating']),
        totalReviews: _i(json['totalReviews']),
        commissionRate: _d(json['commissionRate']),
        approvalStatusId: json['approvalStatusId'] == null ? null : _i(json['approvalStatusId']),
        createdAt: _dt(json['createdAt']),
        updatedAt: _dt(json['updatedAt']),
        displayName: json['displayName'],
        dateOfBirth: json['dateOfBirth']?.toString(),
        instagramUrl: json['instagramUrl'],
        profileType: json['profileType'],
        profileTypes: ((json['profileTypes'] as List?) ?? const []).map((e) => e.toString()).toList(),
        experienceRange: (json['experienceRange'] ?? '').toString().isEmpty ? null : json['experienceRange'].toString(),
        specialities: ((json['specialities'] as List?) ?? const [])
            .map((e) => e is Map ? _i(e['subCategoryId']) : _i(e))
            .toList(),
        profilePhotoUrl: json['profilePhotoUrl'],
        coverPhotoUrl: json['coverPhotoUrl'],
        isAcceptingBookings: json['isAcceptingBookings'] == true,
        registrationEligible: json['registrationEligible'] != false,
        acceptingLockedByAdmin: json['acceptingLockedByAdmin'] == true,
        publicSlug: json['publicSlug'],
        profileViewCount: _i(json['profileViewCount']),
        travelTimeBeforeMinutes: _i(json['travelTimeBeforeMinutes']),
        returnBufferMinutes: _i(json['returnBufferMinutes']),
        agreementVersion: json['agreementVersion']?.toString(),
        termsAcceptedAt: json['termsAcceptedAt']?.toString(),
        submittedForReviewAt: json['submittedForReviewAt']?.toString(),
        rejectionReason: json['rejectionReason']?.toString(),
        baseAddressId: json['baseAddressId'] == null ? null : _i(json['baseAddressId']),
      );
}
