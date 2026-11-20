// FILE: models/artist/artist_profile_update.dart  |  MODEL
// Request body for PUT /artists/profile/update/.
// Commission, approval and rating fields are ignored by the server if sent.

/// Model: Artist Profile Update.
class ArtistProfileUpdate {
  final String? bio;
  final int? yearsExperience; // older apps; when experienceRange is sent too, the range wins
  final String? experienceRange; // 0-1 | 1-3 | 3-5 | 5-10 | 10+
  final String? city;
  final String? displayName; // max 100
  final String? dateOfBirth; // YYYY-MM-DD, age >= 18
  final String? instagramUrl; // https://instagram.com/<handle>
  final String? profileType; // freelance | studio (older apps; when profileTypes is sent too, the list wins)
  final List<String>? profileTypes; // 1 or 2 of freelance | studio, each once
  final int? travelTimeBeforeMinutes; // 0-240
  final int? returnBufferMinutes; // 0-240
  final int? baseAddressId;

  ArtistProfileUpdate({
    this.bio,
    this.yearsExperience,
    this.experienceRange,
    this.city,
    this.displayName,
    this.dateOfBirth,
    this.instagramUrl,
    this.profileType,
    this.profileTypes,
    this.travelTimeBeforeMinutes,
    this.returnBufferMinutes,
    this.baseAddressId,
  });

  /// Converts this object to JSON for the API.
  Map<String, dynamic> toJson() => {
        if (bio != null) 'bio': bio,
        if (yearsExperience != null) 'years_experience': yearsExperience,
        if (experienceRange != null) 'experience_range': experienceRange,
        if (city != null) 'city': city,
        if (displayName != null) 'display_name': displayName,
        if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
        if (instagramUrl != null) 'instagram_url': instagramUrl,
        if (profileType != null) 'profile_type': profileType,
        if (profileTypes != null && profileTypes!.isNotEmpty) 'profile_types': profileTypes,
        if (travelTimeBeforeMinutes != null) 'travel_time_before_minutes': travelTimeBeforeMinutes,
        if (returnBufferMinutes != null) 'return_buffer_minutes': returnBufferMinutes,
        if (baseAddressId != null) 'base_address_id': baseAddressId,
      };
}
