// FILE: utils/profile_completeness.dart
// Checks if the profile is complete (photo, services, portfolio, bank...) and the next hint.

import 'package:shared_preferences/shared_preferences.dart';
import '../models/artist/artist_profile.dart';
import 'app_session.dart';
import 'artist_extra_details.dart';
import 'onboarding_progress.dart';
import 'service_locator.dart';

/// Profile Completeness.
class ProfileCompleteness {
  final bool details;
  final bool services;
  final bool documents;
  final bool photo;

  /// Artist page really built on the server: >=1 active package, availability, location and >=1 portfolio photo.
  final bool page;

  const ProfileCompleteness({
    required this.details,
    required this.services,
    required this.documents,
    required this.photo,
    this.page = true,
  });

  /// Returns all.
  List<bool> get _all => [details, services, documents, photo, page];
  /// Returns true if complete.
  bool get isComplete => _all.every((c) => c);
  double get fraction => _all.where((c) => c).length / _all.length;

  /// Next hint.
  String? get nextHint {
    if (!details) return 'Finish Your Personal Details.';
    if (!photo) return 'Add Your Profile Photo.';
    if (!services) return 'Add Your Services And Portfolio Photos.';
    if (!documents) return 'Complete Your Documents And Payout Details.';
    if (!page) return 'Finish Your Artist Page — Services, Portfolio And Location.';
    return null;
  }

  /// Done key.
  static String get _doneKey => 'profile_complete_${AppSession.instance.userId ?? 0}';

  /// Returns true if it was marked complete.
  static Future<bool> wasMarkedComplete() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(_doneKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Marks complete.
  static Future<void> _markComplete() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_doneKey, true);
    } catch (_) {}
  }

  /// Resets to default.
  static Future<void> reset() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_doneKey);
    } catch (_) {}
  }

  /// Checks the REAL server data (never a saved flag): active package + availability + location + portfolio photo.
  /// API: GET /artists/onboarding/status/ · GET /artists/portfolio/get_all/
  static Future<bool> pageBuilt() async {
    final s = await ServiceLocator.artistBusiness.getOnboardingStatus();
    // A step the server does not report at all is not treated as missing (older accounts / older API).
    bool ok(String k) => !s.steps.containsKey(k) || s.done(k);
    if (!(ok('services') && ok('availability') && ok('location'))) return false;
    final res = await ServiceLocator.artistService.getAllPortfolios(limit: 50);
    return res.data.any((p) => p.isActive);
  }

  /// Loads this screen's data.
  static Future<ProfileCompleteness> load({ArtistProfile? profile}) async {
    // These three do not depend on each other, so they run together instead of one after another.
    final pageF = () async {
      try {
        return await pageBuilt();
      } catch (_) {
        // offline: fall back to the last known result instead of blocking the artist
        return await wasMarkedComplete();
      }
    }();
    final parts = await Future.wait<Object>([
      ArtistExtraDetails.load().then<Object>((v) => v),
      OnboardingProgress.load(profile: profile).then<Object>((v) => v),
      pageF.then<Object>((v) => v),
    ]);
    final extra = parts[0] as ArtistExtraDetails;
    final progress = parts[1] as OnboardingProgress;
    final bool page = parts[2] as bool;
    // The photo may only exist on the server (new phone / reinstall / cleared app data) → check both.
    var hasPhoto = (extra.profilePhotoPath ?? '').isNotEmpty || (profile?.profilePhotoUrl ?? '').isNotEmpty;
    if (!hasPhoto && profile == null) {
      try {
        hasPhoto = ((await ServiceLocator.artistService.getProfile()).profilePhotoUrl ?? '').isNotEmpty;
      } catch (_) {}
    }
    final result = ProfileCompleteness(
      page: page,
      details: progress.details,
      // The server-verified page (active package + availability + location + portfolio photo) already proves services exist;
      // the old "3 portfolio photos" rule must not send a finished artist back to "You're Approved".
      services: progress.services || page,
      documents: progress.documents,
      photo: hasPhoto,
    );
    if (result.isComplete) {
      await _markComplete();
    } else {
      await reset(); // data was deleted → the old "complete" flag must not stay
    }
    return result;
  }
}