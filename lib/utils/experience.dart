// FILE: utils/experience.dart
// Experience is chosen as one of five fixed ranges (e.g. "3-5 Years"). The server stores the range
// itself (experience_range) and shows it exactly as chosen. A plain number (years_experience) is still
// sent next to it for older app versions; when both arrive, the range wins.

/// Ranges shown to the artist (same list everywhere).
const List<String> kExperienceRanges = ['0-1 Years', '1-3 Years', '3-5 Years', '5-10 Years', '10+ Years'];

/// The exact values the server accepts for `experience_range` (same order as [kExperienceRanges]).
const List<String> kExperienceRangeKeys = ['0-1', '1-3', '3-5', '5-10', '10+'];

/// Number saved next to the range for older app versions (always inside its range).
const List<int> kExperienceYears = [1, 2, 4, 7, 10];

/// The ranges as they were before "0-1" existed — only used to read an onboarding draft saved by an older version.
const List<String> kLegacyExperienceRanges = ['1-3 Years', '3-5 Years', '5-10 Years', '10+ Years'];

/// Range → number for the API (older versions).
int experienceYearsFromLabel(String label) {
  final i = kExperienceRanges.indexOf(label);
  return i < 0 ? kExperienceYears[1] : kExperienceYears[i];
}

/// Range label → the value sent as `experience_range`.
String? experienceRangeKeyFromLabel(String? label) {
  final i = label == null ? -1 : kExperienceRanges.indexOf(label);
  return i < 0 ? null : kExperienceRangeKeys[i];
}

/// `experience_range` from the API → the range label shown to the artist (null when it is not one of the five).
String? experienceLabelFromRangeKey(String? key) {
  final i = key == null ? -1 : kExperienceRangeKeys.indexOf(key.trim());
  return i < 0 ? null : kExperienceRanges[i];
}

/// Number from the API → the range label shown to the artist.
/// Only a fallback for an artist who has not picked a range yet (experienceRange is null).
String experienceLabelFromYears(int years) {
  if (years >= 10) return kExperienceRanges[4];
  if (years >= 5) return kExperienceRanges[3];
  if (years >= 3) return kExperienceRanges[2];
  return kExperienceRanges[1];
}

/// What to show for an artist: the chosen range exactly as saved, else the label worked out from years.
/// Returns null when there is nothing to show (no range and no years).
String? experienceDisplay({String? rangeKey, int years = 0}) {
  final fromRange = experienceLabelFromRangeKey(rangeKey);
  if (fromRange != null) return fromRange;
  if (years > 0) return experienceLabelFromYears(years);
  return null;
}
