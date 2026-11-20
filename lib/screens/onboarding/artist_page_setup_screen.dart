// FILE: screens/onboarding/artist_page_setup_screen.dart
// SCREEN FLOW: Build My Artist Page (after admin approval)
// Profile -> Services -> Extra services -> Portfolio -> Location -> submit. Also Under-Review and Live screens.
//
// APIs used:
//   GET /artists/profile/get/
//   PUT /artists/profile/update/
//   GET /artists/packages/get_all/
//   GET /artists/portfolio/get_all/
//   POST /artists/profile/photo/upload/ · PUT /artists/profile/specialities/set/
//   GET /artists/onboarding/status/ · POST /artists/onboarding/submit/

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/artist/artist_profile.dart';
import '../../models/artist/artist_extras.dart';
import '../../models/artist/artist_profile_update.dart';
import '../../theme/tokens.dart';
import '../../utils/app_feedback.dart';
import '../../utils/app_session.dart';
import '../../utils/artist_extra_details.dart';
import '../../utils/profile_completeness.dart';
import '../../utils/onboarding_progress.dart' show kMinPortfolioPhotos;
import '../../utils/service_locator.dart';
import '../../widgets/common.dart';
import 'registration_fee_screen.dart';
import '../auth/logout_helper.dart';
import '../auth/registration_status_screen.dart' show goToAppShell;
import '../help_center_screen.dart';
import '../public_profile_preview_screen.dart';
import 'artist_page_portfolio_location_steps.dart';
import 'artist_page_services_steps.dart';
import 'package:flutter/services.dart';

/// Artist Page Setup.
class ArtistPageSetup {
  ArtistPageSetup._();

  static String get _key => 'artist_page_setup_done_${AppSession.instance.userId ?? 0}';

  /// Returns true if done.
  static Future<bool> isDone() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(_key) ?? false;
    } catch (_) {
      return true;
    }
  }

  /// Marks done.
  static Future<void> markDone() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, true);
    } catch (_) {}
  }

  /// Returns true if profile complete.
  static Future<bool> isProfileComplete({ArtistProfile? profile}) async {
    try {
      // Always re-check the real data; the saved flag is only an offline fallback.
      final c = await ProfileCompleteness.load(profile: profile);
      return c.isComplete;
    } catch (_) {
      return await ProfileCompleteness.wasMarkedComplete();
    }
  }

  static Future<bool> needed({ArtistProfile? profile}) async => !(await isProfileComplete(profile: profile));
}

// Approval is now decided by the admin through the API (GET /artists/onboarding/status/).
const bool kAutoApproveArtistPage = false;

/// Second approval is MANDATORY: the artist stays out of the app until the admin sets the portfolio/page
/// approval to true. If the backend does not send the flag, the artist is NOT let in (stays on "Under Review").
// Backend now sends `portfolioApprovalStatus` in GET /artists/profile/get/ (true = approved, false = waiting), so this is
// back to true: approval 1 alone never lets the artist in; the app opens only when the admin sets it to true.
const bool kRequireSecondApproval = true;

/// Second admin approval — the artist PAGE / PORTFOLIO approval (admin panel: "Portfolio approval status").
/// Flow: register → approval 1 (normal artist approval) → artist builds the page → the backend sets this to
/// pending (false) → admin switches it on (true) → the artist goes live.
/// true = approved · false = waiting for the admin · missing in the API = not rolled out yet (old behaviour).
/// If the API uses another field name, add it to [keys].
class PortfolioApproval {
  PortfolioApproval._();

  static const keys = <String>[
    'portfolioApprovalStatus', // admin panel label: "Portfolio approval status"
    'portfolio_approval_status',
    'portfolioApproval',
    'portfolio_approval',
    'isPortfolioApproved',
    'is_portfolio_approved',
    'portfolioApproved',
    'portfolio_approved',
  ];

  static bool? _parse(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'approved' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'pending' || s == 'no' || s == 'rejected') return false;
    return null;
  }

  static bool? _fromMap(Map<String, dynamic> m) {
    for (final k in keys) {
      if (m.containsKey(k)) return _parse(m[k]);
    }
    // Any other spelling that has both "portfolio" and "approv" in the key (camelCase / snake_case / nested names).
    for (final e in m.entries) {
      final k = e.key.toLowerCase().replaceAll('_', '');
      if (k.contains('portfolio') && k.contains('approv')) return _parse(e.value);
    }
    debugPrint('[PortfolioApproval] no portfolio-approval key in response. Keys: ${m.keys.toList()}');
    return null;
  }

  /// true / false from the server, or null when the server does not send the field.
  /// API: GET /artists/profile/get/ · GET /artists/onboarding/status/
  static Future<bool?> read() async {
    try {
      final v = _fromMap(await ServiceLocator.artistService.getProfileRaw());
      if (v != null) return v;
    } catch (_) {}
    try {
      return _fromMap(await ServiceLocator.artistBusiness.getOnboardingStatusRaw());
    } catch (_) {
      return null;
    }
  }
}

/// Artist Page Review.
class ArtistPageReview {
  ArtistPageReview._();

  static String _k(String n) => 'artist_page_${n}_${AppSession.instance.userId ?? 0}';

  static Future<bool> _get(String n) async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_k(n)) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _set(String n, bool v) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_k(n), v);
    } catch (_) {}
  }

  /// Marks submitted.
  static Future<void> markSubmitted() => _set('submitted', true);
  /// Marks live seen.
  static Future<void> markLiveSeen() => _set('live_seen', true);

  /// True while the page is waiting for the admin.
  /// New: the portfolio approval flag from the backend (false = waiting). When the backend does not send it yet
  /// (or [useFlag] is false) the old rule applies: server status `submitted`.
  /// API: GET /artists/profile/get/ · GET /artists/onboarding/status/ — the on-device flag is only the offline fallback.
  static Future<bool> pending({bool useFlag = true}) async {
    if (useFlag) {
      final flag = await PortfolioApproval.read();
      if (flag != null) return !flag;
      // No flag from the server → never let the artist in on approval 1 alone (only if they were already approved earlier).
      if (kRequireSecondApproval) return !await _get('live_seen');
    }
    try {
      final s = await ServiceLocator.artistBusiness.getOnboardingStatus();
      if (s.isSubmitted) return true;
      if (s.isRejected || s.isSuspended) return false;
    } catch (_) {}
    return await _get('submitted') && !await _get('live_seen');
  }

  /// Returns true if the admin approved the application.
  /// API: GET /artists/onboarding/status/
  static Future<bool> isApproved() async {
    final flag = await PortfolioApproval.read();
    if (flag != null) return flag;
    if (kRequireSecondApproval) return false; // status "approved" is only approval 1
    try {
      return (await ServiceLocator.artistBusiness.getOnboardingStatus()).isApproved;
    } catch (_) {
      return false;
    }
  }
}

/// Artist Page Setup Screen.
class ArtistPageSetupScreen extends StatefulWidget {
  const ArtistPageSetupScreen({super.key});

  @override
  State<ArtistPageSetupScreen> createState() => _ArtistPageSetupScreenState();
}

/// State of [ArtistPageSetupScreen] — holds the screen data and logic.
class _ArtistPageSetupScreenState extends State<ArtistPageSetupScreen> {
  static const _titles = [
    'Artist Page Setup',
    'Services & Pricing',
    'Additional Services',
    'Your Portfolio',
    'Location & Availability',
  ];

  int _step = 0;
  bool _busy = false;

  final _displayName = TextEditingController();
  final _about = TextEditingController();
  ArtistExtraDetails _extra = const ArtistExtraDetails();
  String? _coverPath;
  bool _photoDirty = false; // profile photo picked but not uploaded yet
  bool _coverDirty = false; // cover photo picked but not uploaded yet
  bool _loaded = false;
  bool _brandLocked = false; // brand name is fixed once saved

  /// Cover key.
  String get _coverKey => 'artist_cover_photo_${AppSession.instance.userId ?? 0}';

  /// Runs once when the screen opens; starts: _init().
  @override
  void initState() {
    super.initState();
    _init();
  }

  /// Frees controllers / listeners when the screen closes.
  @override
  void dispose() {
    _displayName.dispose();
    _about.dispose();
    super.dispose();
  }

  /// Initial setup.
  /// API: artistService.getProfile → GET /artists/profile/get/
  Future<void> _init() async {
    try {
      _extra = await ArtistExtraDetails.load();
      final n = (_extra.professionalName ?? _extra.displayName ?? '').trim();
      _displayName.text = n.isNotEmpty ? n : (AppSession.instance.name ?? '');
      try {
        // API call: artistService.getProfile → GET /artists/profile/get/
        final profile = await ServiceLocator.artistService.getProfile();
        _about.text = profile.bio ?? '';
        if ((profile.displayName ?? '').trim().isNotEmpty) {
          _brandLocked = true;
          _displayName.text = profile.displayName!.trim();
        }
        final prefs0 = await SharedPreferences.getInstance();
        // A photo that exists on the device but not on the server still has to be uploaded.
        _photoDirty = (profile.profilePhotoUrl ?? '').isEmpty && (_extra.profilePhotoPath ?? '').isNotEmpty;
        _coverDirty = (profile.coverPhotoUrl ?? '').isEmpty && (prefs0.getString(_coverKey) ?? '').isNotEmpty;
      } catch (_) {}
      final prefs = await SharedPreferences.getInstance();
      _coverPath = prefs.getString(_coverKey);
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  /// Lets the user pick profile photo.
  Future<void> _pickProfilePhoto() async {
    final path = await ArtistExtraDetails.pickAndSaveProfilePhoto(source: ImageSource.gallery);
    if (path == null || !mounted) return;
    final updated = _extra.copyWith(profilePhotoPath: path);
    await updated.save();
    if (mounted) setState(() {
      _extra = updated;
      _photoDirty = true;
    });
  }

  /// Tap on a picture that is already chosen → change it or remove it (a wrong pick is never stuck).
  Future<void> _photoActions({required bool hasPhoto, required bool isCover}) async {
    if (!hasPhoto) {
      return isCover ? _pickCover() : _pickProfilePhoto();
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AiraColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AiraColors.hair, borderRadius: BorderRadius.circular(2))),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: AiraColors.roseDeep),
            title: Text(isCover ? 'Choose A Different Cover Photo' : 'Choose A Different Photo', style: AiraText.sans(fontSize: 14.5)),
            onTap: () => Navigator.of(ctx).pop('change'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: AiraColors.errorText),
            title: Text('Remove Photo', style: AiraText.sans(fontSize: 14.5, color: AiraColors.errorText)),
            onTap: () => Navigator.of(ctx).pop('remove'),
          ),
          const SizedBox(height: 6),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'change') return isCover ? _pickCover() : _pickProfilePhoto();
    if (isCover) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_coverKey);
      try {
        if (_coverPath != null) await File(_coverPath!).delete();
      } catch (_) {}
      if (mounted) setState(() => _coverPath = null);
    } else {
      final cleared = await _extra.clearProfilePhoto();
      if (mounted) setState(() => _extra = cleared);
    }
  }

  /// Lets the user pick cover.
  Future<void> _pickCover() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery); // original photo — the server shrinks it
      if (picked == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final ext = picked.path.split('.').last;
      final uid = AppSession.instance.userId ?? 0;
      final saved = '${dir.path}/cover_photo_${uid}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await File(picked.path).copy(saved);
      try {
        final old = _coverPath;
        if (old != null && old != saved && File(old).existsSync()) await File(old).delete();
      } catch (_) {}
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_coverKey, saved);
      if (mounted) {
        setState(() {
          _coverPath = saved;
          _coverDirty = true;
        });
      }
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    }
  }

  /// Saves brand.
  /// API: artistService.updateProfile → PUT /artists/profile/update/
  Future<bool> _saveBrand() async {
    final name = _displayName.text.trim();
    if (name.isEmpty) {
      AppFeedback.showInfo(context, 'Please Enter Your Brand Name.');
      return false;
    }
    if ((_extra.profilePhotoPath ?? '').isEmpty) {
      AppFeedback.showInfo(context, 'Add Your Profile Photo To Continue');
      return false;
    }
    try {
      final updated = _extra.copyWith(displayName: name, professionalName: name);
      await updated.save();
      _extra = updated;
      final bio = _about.text.trim();
      // API call: artistService.updateProfile → PUT /artists/profile/update/
      await ServiceLocator.artistService.updateProfile(ArtistProfileUpdate(
        displayName: name,
        bio: bio.isEmpty ? null : bio,
        profileTypes: _extra.profileTypes.isEmpty ? null : _extra.profileTypes.map((t) => t.name).toList(),
      ));
      if (_photoDirty || _coverDirty) {
        // API call: artistBusiness.uploadProfilePhotos → POST /artists/profile/photo/upload/ (multipart)
        await ServiceLocator.artistBusiness.uploadProfilePhotos(
          profilePhoto: _photoDirty && (_extra.profilePhotoPath ?? '').isNotEmpty ? XFile(_extra.profilePhotoPath!) : null,
          coverPhoto: _coverDirty && (_coverPath ?? '').isNotEmpty ? XFile(_coverPath!) : null,
        );
        _photoDirty = false;
        _coverDirty = false;
      }
      return true;
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
      return false;
    }
  }

  /// Returns true if it has packages.
  /// API: artistService.getAllPackages → GET /artists/packages/get_all/
  Future<bool> _hasPackages() async {
    try {
      // API call: artistService.getAllPackages → GET /artists/packages/get_all/
      final res = await ServiceLocator.artistService.getAllPackages(limit: 5);
      return res.data.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Returns true if it has portfolio.
  /// API: artistService.getAllPortfolios → GET /artists/portfolio/get_all/
  Future<bool> _hasPortfolio() async {
    try {
      // API call: artistService.getAllPortfolios → GET /artists/portfolio/get_all/
      final res = await ServiceLocator.artistService.getAllPortfolios(limit: 20);
      return res.data.length >= kMinPortfolioPhotos;
    } catch (_) {
      return false;
    }
  }

  /// Names of the server checklist steps, for messages.
  static const _stepLabels = {
    'basicInfo': 'Basic Info',
    'registrationFields': 'Profile Details',
    'location': 'Base Address',
    'services': 'A Service Package',
    'availability': 'Working Hours & Location Type',
    'workSamples': 'A Work-Sample Photo',
    'documents': 'ID Proof',
    'payoutAccount': 'Bank Account',
    'agreement': 'Terms & Privacy',
    'registrationFee': 'Registration Fee',
  };

  /// Pushes the artist's specialities (picked during onboarding) once their services exist — the server only
  /// accepts sub-categories the artist already offers (max 10).
  /// API: GET /artists/services/get_all/ · GET /core/service-sub-category/get_all/ · POST /artists/profile/specialities/set/
  Future<void> _pushSpecialities() async {
    try {
      final wanted = (await ArtistExtraDetails.load()).specialities.map((e) => e.toLowerCase()).toList();
      if (wanted.isEmpty) return;
      final raw = await ServiceLocator.artistService.getAllServices();
      final rows = raw is List ? raw : (raw is Map && raw['data'] is List ? raw['data'] as List : const []);
      final offered = rows.whereType<Map>().map((r) => (r['subCategoryId'] as num?)?.toInt()).whereType<int>().toSet();
      if (offered.isEmpty) return;
      final subs = (await ServiceLocator.coreService.getAllServiceSubCategories(limit: 100)).data;
      final ids = subs
          .where((x) => offered.contains(x.subCategoryId))
          .where((x) => wanted.any((w) => x.name.toLowerCase().contains(w) || w.contains(x.name.toLowerCase())))
          .map((x) => x.subCategoryId)
          .take(10)
          .toList();
      if (ids.isNotEmpty) await ServiceLocator.artistBusiness.setSpecialities(ids);
    } catch (_) {
      // specialities are optional for review — never block the submit on them
    }
  }

  /// Sends the application to the admin. The server rejects it with the list of unfinished steps if anything is
  /// missing, so the checklist is checked first to give a friendly message.
  /// API: GET /artists/onboarding/status/ · POST /artists/onboarding/submit/
  Future<bool> _submitForReview() async {
    final biz = ServiceLocator.artistBusiness;
    await _pushSpecialities();
    OnboardingStatus st;
    try {
      st = await biz.getOnboardingStatus();
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
      return false;
    }
    // Registration fee: must be paid before submitting (exempt / already-paid artists skip this).
    // The fee endpoint decides (registrationRequired is false for paid / exempt artists), so this also covers an
    // artist whose status already shows "approved" but who has not paid.
    if (!mounted) return false;
    if (kRegistrationFeeBeforeSubmit && !await ensureRegistrationFeePaid(context)) return false;
    try {
      st = await biz.getOnboardingStatus(); // refresh: steps.registrationFee is now true
    } catch (_) {}
    // Already approved: edits go live without another review. Already submitted: nothing to send.
    if (st.isApproved || st.isSubmitted) return true;
    if (st.steps.isNotEmpty && !st.canSubmit) {
      final missing = st.pendingSteps.map((k) => _stepLabels[k] ?? k).join(', ');
      if (mounted) AppFeedback.showInfo(context, 'Still To Finish: $missing');
      return false;
    }

    try {
      await biz.submitOnboarding();
      return true;
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
      return false;
    }
  }

  final _servicesKey = GlobalKey<ServicesPricingStepState>();
  final _extrasKey = GlobalKey<ExtraServicesStepState>();
  final _portfolioKey = GlobalKey<PortfolioStepState>();
  final _locationKey = GlobalKey<LocationStepState>();

  /// Current step.
  ArtistPageStep? get _currentStep => switch (_step) {
        1 => _servicesKey.currentState,
        2 => _extrasKey.currentState,
        3 => _portfolioKey.currentState,
        4 => _locationKey.currentState,
        _ => null,
      };

  Future<void> _next() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_step == 0) {
        if (!await _saveBrand()) return;
      } else {
        final step = _currentStep;
        if (step == null || !await step.save()) return;
      }

      if (_step == 4) {
        final c = await ProfileCompleteness.load();
        if (!c.isComplete) {
          if (mounted) AppFeedback.showInfo(context, c.nextHint ?? 'Please Complete Your Profile First');
          return;
        }
        if (!await _submitForReview()) return;
        await ArtistPageSetup.markDone();
        await ArtistPageReview.markSubmitted();
        if (!mounted) return;
        // Navigates to ArtistPageUnderReviewScreen
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ArtistPageUnderReviewScreen()),
          (r) => false,
        );
        return;
      }
      if (mounted) setState(() => _step++);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Skip extras.
  void _skipExtras() {
    if (_busy) return;
    setState(() => _step++);
  }

  /// True when there is a screen behind this one. After login this screen is the ROOT route
  /// (the back stack is cleared), so popping it would leave an empty navigator = black screen.
  bool get _canLeave => Navigator.of(context).canPop();

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
      return;
    }
    if (_canLeave) {
      Navigator.of(context).pop();
    } else {
      // Root screen: nothing to go back to — offer to log out and return to Sign In.
      confirmAndLogout(context);
    }
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    final isLast = _step == _titles.length - 1;
    return PopScope(
      // Never let Flutter pop the root route (black screen); _back() decides what to do.
      canPop: _step == 0 && _canLeave,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AiraColors.bg,
        body: SunndariBackground(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: SunndariFlowBar(
                    title: _titles[_step],
                    onBack: _back,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Row(
                    children: [
                      for (var i = 0; i < _titles.length; i++) ...[
                        Expanded(
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: i <= _step ? AiraColors.rose : AiraColors.hair,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        if (i != _titles.length - 1) const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
                Expanded(child: _loaded ? _content() : const Center(child: CircularProgressIndicator(color: AiraColors.rose))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PrimaryButton(
                        label: _busy ? 'Please Wait…' : (isLast ? 'Submit For Review' : 'Save & Continue'),
                        arrow: true,
                        expand: true,
                        onTap: _busy ? null : _next,
                      ),
                      if (_step == 2)
                        TextButton(
                          onPressed: _busy ? null : _skipExtras,
                          child: Text('Skip For Now',
                              style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// UI piece: content.
  Widget _content() {
    switch (_step) {
      case 0:
        return _brand();
      case 1:
        return ServicesPricingStep(key: _servicesKey);
      case 2:
        return ExtraServicesStep(key: _extrasKey);
      case 3:
        return PortfolioStep(key: _portfolioKey);
      default:
        return LocationStep(key: _locationKey);
    }
  }

  /// UI piece: brand.
  Widget _brand() {
    final photo = (_extra.profilePhotoPath ?? '').isNotEmpty && File(_extra.profilePhotoPath!).existsSync()
        ? FileImage(File(_extra.profilePhotoPath!))
        : null;
    final cover = (_coverPath ?? '').isNotEmpty && File(_coverPath!).existsSync() ? FileImage(File(_coverPath!)) : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      children: [
        const SunndariTitle(
          title: 'Your Profile,\nYour Brand',
          subtitle: 'Create A First Impression That Feels Like You.',
          size: 32,
        ),
        const SizedBox(height: 18),
        GestureDetector(
          onTap: () => _photoActions(hasPhoto: cover != null, isCover: true),
          child: Container(
            height: 150,
            decoration: BoxDecoration(
              color: AiraColors.pinkFill,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AiraColors.pinkBorder, width: 1.2),
              image: cover == null ? null : DecorationImage(image: cover, fit: BoxFit.cover),
            ),
            child: cover != null
                ? null
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_photo_alternate_outlined, size: 34, color: AiraColors.rose),
                      const SizedBox(height: 8),
                      Text('Add Cover Photo',
                          style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                      Text('Your Artist Page Banner',
                          style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            GestureDetector(
              onTap: () => _photoActions(hasPhoto: photo != null, isCover: false),
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AiraColors.pinkFill,
                  border: Border.all(color: AiraColors.pinkBorder, width: 1.2),
                  image: photo == null ? null : DecorationImage(image: photo, fit: BoxFit.cover),
                ),
                child: photo != null ? null : const Icon(Icons.add_a_photo_outlined, size: 28, color: AiraColors.rose),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add Profile Photo',
                      style: AiraText.sans(fontSize: 14.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                  Text('Your Photo Or Studio Logo',
                      style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SunndariField(
          label: 'Brand Name',
          controller: _displayName,
          hint: 'Enter Your Brand Name',
          helper: _brandLocked ? 'Your Brand Name Is Saved And Cannot Be Changed.' : null,
          readOnly: _brandLocked,
          capitalization: TextCapitalization.words,
        ),
        SunndariField(
          label: 'About You',
          controller: _about,
          hint: 'Tell Clients About Your Experience, Makeup Style And What Makes Your Work Special.',
          maxLines: 5,
          maxLength: 500,
        ),
        Text('Your Page Is A Draft Until It Is Reviewed And Approved.',
            style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
      ],
    );
  }
}

/// Artist Page Under Review Screen.
class ArtistPageUnderReviewScreen extends StatefulWidget {
  const ArtistPageUnderReviewScreen({super.key});

  @override
  State<ArtistPageUnderReviewScreen> createState() => _ArtistPageUnderReviewScreenState();
}

/// State of [ArtistPageUnderReviewScreen] — holds the screen data and logic.
class _ArtistPageUnderReviewScreenState extends State<ArtistPageUnderReviewScreen> {
  bool _checking = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Looks for the admin's decision by itself every 20 seconds.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _check(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Runs the check. [silent] = background check, no loader and no message.
  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    if (!silent) setState(() => _checking = true);
    try {
      final approved = await ArtistPageReview.isApproved();
      if (!mounted) return;
      if (approved) {
        _poll?.cancel();
        // Navigates to ArtistPageLiveScreen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => ArtistPageLiveScreen(name: AppSession.instance.name ?? '', fromReview: true)),
        );
      } else if (!silent) {
        AppFeedback.showInfo(context, 'Still Under Review — We’ll Notify You Once It’s Approved');
      }
    } finally {
      if (mounted && !silent) setState(() => _checking = false);
    }
  }

  /// UI piece: step.
  Widget _step(String title, String sub, int state, {bool last = false}) {
    final done = state == 0;
    final active = state == 1;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? AiraColors.roseDeep : (active ? AiraColors.rose.withOpacity(0.85) : Colors.white),
                  border: Border.all(color: done || active ? Colors.transparent : AiraColors.charcoalSoft.withOpacity(0.5), width: 1.4),
                ),
                child: Icon(done ? Icons.check_rounded : (active ? Icons.schedule_rounded : null),
                    size: 15, color: Colors.white),
              ),
              if (!last)
                Expanded(child: Container(width: 1.5, margin: const EdgeInsets.symmetric(vertical: 3), color: AiraColors.pinkBorder)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w700, color: AiraColors.charcoal)),
                  const SizedBox(height: 2),
                  Text(sub, style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft, height: 1.35)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AiraColors.bg,
      body: SunndariBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            children: [
              Center(
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(color: AiraColors.blush.withOpacity(0.7), shape: BoxShape.circle),
                  child: const Icon(Icons.pending_actions_rounded, size: 52, color: AiraColors.rose),
                ),
              ),
              const SizedBox(height: 18),
              Text('Artist Page\nUnder Review',
                  textAlign: TextAlign.center,
                  style: AiraText.sans(fontSize: 30, fontWeight: FontWeight.w800, color: AiraColors.roseDeep, height: 1.12)),
              const SizedBox(height: 12),
              Text('Your Artist Page Has Been Submitted!',
                  textAlign: TextAlign.center,
                  style: AiraText.sans(fontSize: 16, fontWeight: FontWeight.w800, color: AiraColors.charcoal)),
              const SizedBox(height: 6),
              Text('We’re Reviewing Your Services, Pricing And Portfolio. We’ll Notify You Once It’s Approved.',
                  textAlign: TextAlign.center,
                  style: AiraText.sans(fontSize: 13.5, color: AiraColors.charcoalSoft, height: 1.4)),
              const SizedBox(height: 14),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(color: AiraColors.blush, borderRadius: BorderRadius.circular(999)),
                  child: Text('Pending Final Approval',
                      style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: AiraColors.rose.withOpacity(0.12), blurRadius: 18, offset: const Offset(0, 6))],
                ),
                child: Column(
                  children: [
                    _step('Profile Submitted', 'Your Information Has Been Received.', 0),
                    _step('Final Review In Progress', 'We’re Reviewing Your Services, Pricing And Portfolio.', 1),
                    _step('Live After Approval', 'Your Profile Will Be Visible To Customers Once Approved.', 2, last: true),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text('Your Profile Is Not Visible To Customers Yet.',
                    style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'View Submitted Profile',
                expand: true,
                // Navigates to PublicProfilePreviewScreen
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PublicProfilePreviewScreen(name: AppSession.instance.name ?? '', submittedPreview: true),
                )),
              ),
              const SizedBox(height: 10),
              GhostButton(
                label: _checking ? 'Checking…' : 'Check Status',
                icon: Icons.refresh_rounded,
                expand: true,
                onTap: _checking ? null : _check,
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: () =>
                      // Navigates to HelpCenterScreen
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpCenterScreen())),
                  child: Text('Need Help?',
                      style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: AiraColors.rose)
                          .copyWith(decoration: TextDecoration.underline)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Artist Page Live Screen.
class ArtistPageLiveScreen extends StatelessWidget {
  final String name;
  final bool fromReview;
  const ArtistPageLiveScreen({super.key, this.name = '', this.fromReview = false});

  Future<void> _dashboard(BuildContext context) async {
    if (fromReview) {
      await ArtistPageReview.markLiveSeen();
      if (context.mounted) goToAppShell(context);
    } else {
      Navigator.of(context).pop();
    }
  }

  /// UI piece: row.
  Widget _row(IconData icon, String title, String sub, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(color: AiraColors.blush, shape: BoxShape.circle),
                child: Icon(icon, size: 22, color: AiraColors.rose),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AiraText.sans(fontSize: 14.5, fontWeight: FontWeight.w800, color: AiraColors.charcoal)),
                    Text(sub, style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AiraColors.rose, size: 26),
            ],
          ),
        ),
      );

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !fromReview,
      child: Scaffold(
        backgroundColor: AiraColors.bg,
        body: SunndariBackground(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              children: [
                if (!fromReview)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SunndariBackChip(onTap: () => Navigator.of(context).pop()),
                  ),
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(color: AiraColors.blush.withOpacity(0.7), shape: BoxShape.circle),
                      ),
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AiraColors.rose, width: 5),
                          color: Colors.white,
                        ),
                        child: const Icon(Icons.check_rounded, size: 46, color: AiraColors.roseDeep),
                      ),
                      const Positioned(top: 8, left: 14, child: Icon(Icons.auto_awesome, size: 18, color: AiraColors.rose)),
                      const Positioned(bottom: 14, right: 10, child: Icon(Icons.auto_awesome, size: 20, color: AiraColors.rose)),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text('Your Artist Page\nIs Live!',
                    textAlign: TextAlign.center,
                    style: AiraText.sans(fontSize: 30, fontWeight: FontWeight.w800, color: AiraColors.roseDeep, height: 1.12)),
                const SizedBox(height: 10),
                Text('Your Beauty Business Starts Here.',
                    textAlign: TextAlign.center,
                    style: AiraText.sans(fontSize: 16, fontWeight: FontWeight.w800, color: AiraColors.charcoal)),
                const SizedBox(height: 6),
                Text('Customers Can Now Discover Your Profile And Book Your Services.',
                    textAlign: TextAlign.center,
                    style: AiraText.sans(fontSize: 13.5, color: AiraColors.charcoalSoft, height: 1.4)),
                const SizedBox(height: 14),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(color: const Color(0xFFE3F5EA), borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.circle, size: 9, color: AiraColors.success),
                        const SizedBox(width: 8),
                        Text('Live On Sunndari',
                            style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: AiraColors.charcoal)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                AiraCard(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('What Happens Next', style: AiraText.serif(fontSize: 17)),
                      const SizedBox(height: 12),
                      for (final t in const [
                        (Icons.notifications_active_outlined, 'You Will Be Notified When A Client Sends A Booking Request.'),
                        (Icons.event_available_outlined, 'Keep Your Calendar And Working Hours Up To Date.'),
                        (Icons.photo_library_outlined, 'Add More Work To Your Portfolio To Attract More Clients.'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SunndariIconBubble(icon: t.$1, size: 34),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 7),
                                child: Text(t.$2, style: AiraText.sans(fontSize: 13, color: AiraColors.charcoal, height: 1.35)),
                              ),
                            ),
                          ]),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Navigates to PublicProfilePreviewScreen
                GhostButton(
                  label: 'View My Live Profile',
                  icon: Icons.person_outline_rounded,
                  expand: true,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PublicProfilePreviewScreen(name: name))),
                ),
                const SizedBox(height: 12),
                PrimaryButton(label: 'Go To Dashboard', arrow: true, expand: true, onTap: () => _dashboard(context)),
                const SizedBox(height: 14),
                Center(
                  child: Text('Makeup Artist To Beauty Entrepreneur.',
                      style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
