// FILE: screens/onboarding/onboarding_flow_screen.dart
// SCREEN FLOW: Artist Registration (first-time onboarding)
// Step 1 Identity -> Step 2 Artistry -> Step 3 KYC documents -> Step 4 Payout + agreement. Drafts saved on device.
//
// APIs used:
//   PUT /users/profile/update/
//   PUT /artists/profile/update/
//   POST /artists/kyc/submit/
//   PUT /artists/bank-details/update/

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/artist/artist_extras.dart';
import '../../models/artist/artist_profile_update.dart';
import '../../models/artist/create_portfolio.dart';
import '../../models/enums/media_type_enum.dart';
import '../../models/onboarrrding/onboarding_steps_model.dart';
import '../../models/user/user_profile_update.dart';
import '../../theme/tokens.dart';
import '../../utils/experience.dart';
import '../../utils/dob_input.dart';
import '../../utils/ifsc_lookup.dart';
import '../../utils/app_feedback.dart';
import '../../utils/app_session.dart';
import '../../utils/approval_status.dart';
import '../../utils/artist_extra_details.dart';
import '../../utils/onboarding_draft.dart';
import '../../utils/onboarding_progress.dart';
import '../../utils/service_locator.dart';
import '../../widgets/common.dart';
import '../auth/login_screen.dart';
import '../auth/logout_helper.dart';
import '../auth/post_login_router.dart';
import '../help_center_screen.dart';
import 'artist_page_services_steps.dart' show kMakeupTypeCategory, isAdditionalServiceSub;
import 'onboarding_agreement_step.dart';
import 'onboarding_widgets.dart' show aadhaarDigits;

// The backend now stores every onboarding step (profile fields, KYC documents, payout account, agreement),
// so a failed call must stop the user instead of silently continuing offline.
const bool kAllowOfflineOnboarding = false;

/// Input formatter: Doc Number Formatter.
class _DocNumberFormatter extends TextInputFormatter {
  final int maxChars;
  final bool digitsOnly;
  final int groupEvery;
  const _DocNumberFormatter({required this.maxChars, this.digitsOnly = false, this.groupEvery = 0});

  /// Formats the text while the user types.
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue value) {
    var raw = value.text.toUpperCase().replaceAll(RegExp(digitsOnly ? r'[^0-9]' : r'[^A-Z0-9]'), '');
    if (raw.length > maxChars) raw = raw.substring(0, maxChars);
    final out = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      if (groupEvery > 0 && i > 0 && i % groupEvery == 0) out.write(' ');
      out.write(raw[i]);
    }
    final text = out.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// Date-of-birth input: typing `15` shows `15/`, then `15/08` shows `15/08/`, then the 4-digit year.
/// The user never types the slash. Backspace works normally (no trailing slash is forced back).
class _DobSlashFormatter extends TextInputFormatter {
  const _DobSlashFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final d = digits.length > 8 ? digits.substring(0, 8) : digits;
    final deleting = newValue.text.length < oldValue.text.length;
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      b.write(d[i]);
      final endOfDayOrMonth = i == 1 || i == 3;
      // add "/" right after the 2nd and 4th digit; while deleting, don't re-add a trailing one
      if (endOfDayOrMonth && (i < d.length - 1 || !deleting)) b.write('/');
    }
    final text = b.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// SCREEN FLOW: Artist Registration (first-time onboarding)
class OnboardingFlowScreen extends StatefulWidget {
  /// true = opened from KYC & Bank to REPLACE the ID proof: only the ID upload is shown (no PAN), and the
  /// screen closes with `true` once the new ID is uploaded (POST /artists/documents/create/ replaces the old one).
  final bool updateIdProof;
  const OnboardingFlowScreen({super.key, this.updateIdProof = false});

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

/// State of [OnboardingFlowScreen] — holds the screen data and logic.
class _OnboardingFlowScreenState extends State<OnboardingFlowScreen> with WidgetsBindingObserver {
  static const _experiences = kExperienceRanges;
  static const _experienceYears = kExperienceYears;
  /// Speciality choices — loaded from the server (service sub-categories), never hardcoded.
  List<String> _specialities = [];
  bool _specialitiesLoading = true;
  bool _specialitiesFailed = false;

  /// API: coreService.getAllServiceSubCategories → GET /core/service-sub-category/get_all/
  /// The artist's own saved specialities come from GET /artists/profile/specialities/get_all/ and are ticked.
  Future<void> _loadSpecialities() async {
    if (mounted) setState(() {
      _specialitiesLoading = true;
      _specialitiesFailed = false;
    });
    try {
      final r = await ServiceLocator.coreService.getAllServiceSubCategories(limit: 100);
      // "Makeup Type" rows (HD / Airbrush …) are not services, so they are not specialities.
      final subs = r.data
          .where((x) => x.isActive && (x.categoryName ?? '').trim().toLowerCase() != kMakeupTypeCategory.toLowerCase() && !isAdditionalServiceSub(x))
          .toList();
      final names = <String>[];
      final byId = <int, String>{};
      for (final x in subs) {
        final n = x.name.trim();
        if (n.isEmpty) continue;
        byId[x.subCategoryId] = n;
        if (!names.contains(n)) names.add(n);
      }
      var saved = <int>[];
      try {
        saved = await ServiceLocator.artistBusiness.getSpecialities();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _specialities = names;
        // Already-saved specialities are ticked, without removing anything the artist ticked here.
        for (final id in saved) {
          final n = byId[id];
          if (n != null) _step2.specialities.add(n);
        }
        _specialitiesLoading = false;
        _specialitiesFailed = names.isEmpty;
      });
    } catch (_) {
      if (mounted) setState(() {
        _specialitiesLoading = false;
        _specialitiesFailed = true;
      });
    }
  }

  int _step = 1;
  bool _loading = true;
  bool _busy = false;
  Timer? _poll;
  bool _polling = false; // a silent status check is running
  bool _agreementOnly = false;
  String? _error;

  final _step1 = StepOneIdentityData();
  final _step2 = StepTwoArtistryData();
  final _step3 = StepThreeKycData();
  final _step4 = StepFourPayoutAgreementData();
  final _picker = ImagePicker();
  /// Signature of the ID documents already uploaded in this session (so going back and
  /// pressing Save & Continue again does not upload the same photos a second time).
  String? _uploadedDocSig;
  /// Same idea for the PAN card (number + photo already uploaded in this session).
  String? _uploadedPanSig;
  /// Work photos already saved on the server (so a returning artist is not forced to re-add them).
  int _uploadedWorkSamples = 0;

  /// Admin verification of the ID proof, shown under "Admin Review" on the Under Review screen.
  /// null = not loaded yet / no ID proof found.
  bool _idProofLoadStarted = false;
  ApprovalStatusKind? _idProofStatus;
  String? _idProofRejection;

  /// Loads the ID proof verification status.
  /// First time: GET /artists/documents/get_all/ (finds the ID proof). After that only this one document is
  /// re-read with GET /artists/documents/get/ (+ GET /core/approval-status/get_all/ when only an id is returned).
  int? _idProofDocId;
  Future<void> _loadIdProof() async {
    try {
      final ArtistDocument d;
      if (_idProofDocId != null) {
        d = await ServiceLocator.artistBusiness.getDocument(_idProofDocId!);
      } else {
        final docs = await ServiceLocator.artistBusiness.getDocuments();
        final ids = docs.where((d) => d.documentType == 'id_proof').toList();
        if (ids.isEmpty) return;
        d = ids.first;
        _idProofDocId = d.documentId;
      }
      final name = d.verificationStatus.trim().toLowerCase();
      ApprovalStatusKind kind;
      if (name.isNotEmpty) {
        kind = name.contains('approv') || name.contains('verif')
            ? ApprovalStatusKind.approved
            : name.contains('reject')
            ? ApprovalStatusKind.rejected
            : ApprovalStatusKind.pending;
      } else {
        kind = await resolveApprovalStatusKind(d.verificationStatusId);
        if (kind == ApprovalStatusKind.unknown) kind = ApprovalStatusKind.pending;
      }
      if (!mounted) return;
      setState(() {
        _idProofStatus = kind;
        _idProofRejection = d.rejectionReason;
      });
    } catch (_) {}
  }

  final _fullNameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  /// Artist name comes from registration and cannot be changed during onboarding.
  bool _artistNameLocked = false;
  /// Brand name is fixed once it has been saved on the server.
  bool _brandLocked = false;
  final _dispNameCtrl = TextEditingController();
  final _instaCtrl = TextEditingController();
  final _idNumCtrl = TextEditingController();
  final _panNumCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();
  final _accCtrl = TextEditingController();
  final _confirmAccCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();

  /// Runs once when the screen opens; starts: _init().
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
    _loadSpecialities();
    // While "Under Review" is showing, look for the admin's decision every 20 seconds.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_step == 5) {
        _loadIdProof(); // keeps the "ID Proof" line up to date
        _refreshStatus(silent: true);
      }
    });
  }

  /// Coming back to the app (e.g. after a notification) re-checks the status straight away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _step == 5) _refreshStatus(silent: true);
  }

  /// Frees controllers / listeners when the screen closes.
  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final c in [
      _fullNameCtrl, _dobCtrl, _dispNameCtrl, _instaCtrl, _idNumCtrl, _panNumCtrl,
      _holderCtrl, _accCtrl, _confirmAccCtrl, _ifscCtrl, _bankCtrl, _upiCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Initial setup.
  Future<void> _init() async {
    try {
      final progress = await OnboardingProgress.load();
      final extra = await ArtistExtraDetails.load();
      final draft = await OnboardingDraft.load('flow');

      String? str(String k) => draft[k] is String && (draft[k] as String).isNotEmpty ? draft[k] as String : null;

      final sessionName = AppSession.instance.name ?? '';
      _artistNameLocked = looksLikeRealName(sessionName);
      _fullNameCtrl.text = _artistNameLocked ? sessionName : (str('fullName') ?? '');
      _dispNameCtrl.text = extra.displayName ?? str('displayName') ?? '';
      try {
        // API call: artistService.getProfile → GET /artists/profile/get/
        final saved = await ServiceLocator.artistService.getProfile();
        if ((saved.displayName ?? '').trim().isNotEmpty) {
          _brandLocked = true;
          _dispNameCtrl.text = saved.displayName!.trim();
        }
      } catch (_) {}
      _instaCtrl.text = str('instagram') ?? '';
      _step1.dob = extra.dob;
      _dobCtrl.text = formatDob(extra.dob);
      _step1.sameAsFullName = draft['same'] == true;

      // 'expKey' = the range as the server names it; 'exp' = index in the list used before "0-1 Years" existed.
      final expKey = draft['expKey'];
      final exp = draft['exp'];
      if (expKey is String && experienceLabelFromRangeKey(expKey) != null) {
        _step2.experience = experienceLabelFromRangeKey(expKey);
      } else if (exp is int && exp >= 0 && exp < kLegacyExperienceRanges.length) {
        _step2.experience = kLegacyExperienceRanges[exp];
      }
      _step2.specialities.addAll(extra.specialities);
      try {
        // API call: artistService.getAllPortfolios → GET /artists/portfolio/get_all/
        final saved = await ServiceLocator.artistService.getAllPortfolios(limit: 50);
        _uploadedWorkSamples = saved.data.where((p) => p.isWorkSample).length;
      } catch (_) {}

      final idType = str('idType');
      if (idType != null) {
        for (final t in GovIdType.values) {
          if (t.name == idType) _step3.idType = t;
        }
      }
      _holderCtrl.text = str('holder') ?? _fullNameCtrl.text;
      _bankCtrl.text = str('bankName') ?? '';
      _upiCtrl.text = extra.upiId ?? '';

      if (progress.allDone) {
        _step = 5;
      } else if (!progress.isDone(0)) {
        _step = 1;
      } else if (!progress.isDone(1)) {
        _step = 2;
      } else if (!progress.isDone(2)) {
        _step = 3;
      } else {
        _step = 4;
        _agreementOnly = true;
      }
      if (widget.updateIdProof) {
        _step = 3;
        _agreementOnly = false;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loading = false);
    if (_agreementOnly) WidgetsBinding.instance.addPostFrameCallback((_) => _openAgreement());
  }

  /// Saves draft.
  Future<void> _saveDraft() => OnboardingDraft.save('flow', {
    'fullName': _fullNameCtrl.text.trim(),
    'displayName': _dispNameCtrl.text.trim(),
    'instagram': _instaCtrl.text.trim(),
    'same': _step1.sameAsFullName,
    'expKey': experienceRangeKeyFromLabel(_step2.experience),
    'idType': _step3.idType.name,
    'holder': _holderCtrl.text.trim(),
    'bankName': _bankCtrl.text.trim(),
  });

  static final _panRe = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
  static final _ifscRe = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
  static final _upiRe = RegExp(r'^[\w.\-]{2,}@[A-Za-z]{2,}$');

  /// Validates ID number.
  String? _validateIdNumber() {
    final raw = _idNumCtrl.text.trim().toUpperCase().replaceAll(' ', '');
    switch (_step3.idType) {
      case GovIdType.aadhaar:
        if (!RegExp(r'^\d{12}$').hasMatch(aadhaarDigits(raw))) return 'Aadhaar Number Must Be 12 Digits';
        break;
      case GovIdType.voterId:
        if (!RegExp(r'^[A-Z]{3}[0-9]{7}$').hasMatch(raw)) return 'Enter A Valid Voter ID (e.g. ABC1234567)';
        break;
      case GovIdType.passport:
        if (!RegExp(r'^[A-Z][0-9]{7}$').hasMatch(raw)) return 'Enter A Valid Passport Number (e.g. A1234567)';
        break;
      case GovIdType.drivingLicense:
        if (!RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z0-9]{9,12}$').hasMatch(raw)) return 'Enter A Valid Driving Licence Number (e.g. MH12 20110012345)';
        break;
    }
    return null;
  }

  bool _ifscLooking = false;
  String? _ifscError;

  /// Valid IFSC → bank name is fetched and filled automatically.
  Future<void> _onIfscChanged(String raw) async {
    final code = raw.trim().toUpperCase();
    if (code.length < 11) {
      if (_ifscError != null || _bankCtrl.text.isNotEmpty || _ifscLooking) {
        setState(() {
          _ifscError = null;
          _ifscLooking = false;
          _bankCtrl.clear();
        });
      }
      return;
    }
    if (!IfscLookup.isValidFormat(code)) {
      setState(() {
        _ifscError = 'Please Enter A Valid IFSC Code.';
        _bankCtrl.clear();
      });
      return;
    }
    setState(() {
      _ifscError = null;
      _ifscLooking = true;
    });
    final info = await IfscLookup.fetch(code);
    if (!mounted || _ifscCtrl.text.trim().toUpperCase() != code) return;
    setState(() {
      _ifscLooking = false;
      if (info == null) {
        _bankCtrl.clear();
        _ifscError = 'Please Enter A Valid IFSC Code.';
      } else {
        _bankCtrl.text = info.bank;
      }
    });
  }

  /// Validates the input.
  String? _validate() {
    switch (_step) {
      case 1:
        final name = _fullNameCtrl.text.trim();
        if (name.length < 3 || !RegExp(r"^[A-Za-z][A-Za-z .'-]+$").hasMatch(name)) {
          return 'Please Enter A Valid Artist Name.';
        }
        if (_dispNameCtrl.text.trim().isEmpty && !_step1.sameAsFullName) {
          return 'Please Enter Your Brand Name.';
        }
        final dobProblem = validateDob(_dobCtrl.text);
        if (dobProblem != null) return dobProblem;
        _step1.dob = parseDob(_dobCtrl.text);
        final insta = _instaCtrl.text.trim();
        if (insta.isNotEmpty && !RegExp(r'^(https?://)?(www\.)?instagram\.com/[\w.]+/?.*$', caseSensitive: false).hasMatch(insta)) {
          return 'Please Enter A Valid Instagram Link, Or Leave It Empty.';
        }
        return null;
      case 2:
        if (_step2.experience == null) return 'Please Select Your Experience.';
        if (_step2.specialities.isEmpty) return 'Please Select At Least One Speciality.';
        if (_step2.workPhotos.isEmpty && _uploadedWorkSamples == 0) {
          return 'Please Add At Least 1 Photo Of Your Work (Up To 5).';
        }
        return null;
      case 3:
        final id = _validateIdNumber();
        if (id != null) return id;
        final vanished = _vanishedDocs();
        if (vanished != null) return vanished;
        if (_step3.idFront == null) return 'Please Upload The Front Side Of Your ${_step3.idType.label}.';
        if (widget.updateIdProof) return null; // only the ID proof is replaced
        if (!_panRe.hasMatch(_panNumCtrl.text.trim().toUpperCase())) return 'Please Enter A Valid PAN Number.';
        if (_step3.panImage == null) return 'Please Upload Your PAN Card.';
        return null;
      case 4:
        if (_holderCtrl.text.trim().length < 3) return "Please Enter The Account Holder's Name.";
        final acc = _accCtrl.text.trim();
        if (!RegExp(r'^\d{9,18}$').hasMatch(acc)) return 'Please Enter A Valid Bank Account Number (9–18 Digits).';
        if (acc != _confirmAccCtrl.text.trim()) return 'Bank Account Numbers Do Not Match.';
        if (!_ifscRe.hasMatch(_ifscCtrl.text.trim().toUpperCase())) return 'Please Enter A Valid IFSC Code.';
        if (_bankCtrl.text.trim().isEmpty) return 'Bank Name Could Not Be Found. Please Check Your IFSC Code.';
        final upi = _upiCtrl.text.trim();
        if (upi.isNotEmpty && !_upiRe.hasMatch(upi)) return 'Please Enter A Valid UPI ID, Or Leave It Empty.';
        return null;
    }
    return null;
  }

  Future<void> _next() async {
    if (_busy) return;
    setState(() => _error = null);
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() => _busy = true);
    try {
      switch (_step) {
        case 1:
          await _saveIdentity();
          if (mounted) setState(() => _step = 2);
          break;
        case 2:
          await _saveArtistry();
          if (mounted) setState(() => _step = 3);
          break;
        case 3:
          await _saveDocuments();
          if (widget.updateIdProof) {
            if (mounted) Navigator.of(context).pop(true); // back to KYC & Bank, which reloads
            return;
          }
          if (mounted) setState(() => _step = 4);
          break;
        case 4:
          await _savePayout();
          await _openAgreement();
          break;
      }
    } catch (e) {
      if (mounted) {
        // Say WHAT could not be saved, then WHY — so the artist knows what to fix.
        const what = {1: 'Could Not Save Your Details', 2: 'Could Not Save Your Professional Details',
          3: 'Could Not Upload Your Documents', 4: 'Could Not Save Your Payout Details'};
        final why = e is FileSystemException || e.toString().contains('PathNotFound')
            ? 'A Selected Photo Is No Longer Available. Please Select Your Document Photos Again.'
            : AppFeedback.friendlyMessage(e);
        setState(() => _error = '${what[_step] ?? 'Could not continue'}. $why');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Instagram link normalised to the only accepted form: https://instagram.com/<handle>.
  String? _instagramUrl() {
    final raw = _instaCtrl.text.trim();
    if (raw.isEmpty) return null;
    final m = RegExp(r'instagram\.com/([\w.]+)', caseSensitive: false).firstMatch(raw);
    return m == null ? null : 'https://instagram.com/${m.group(1)}';
  }

  /// YYYY-MM-DD.
  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Saves identity.
  /// API: PUT /users/profile/update/ (name) + PUT /artists/profile/update/ (display_name, date_of_birth, instagram_url)
  Future<void> _saveIdentity() async {
    final name = _fullNameCtrl.text.trim();
    final display = _step1.sameAsFullName || _dispNameCtrl.text.trim().isEmpty ? name : _dispNameCtrl.text.trim();

    // API call: userService.updateProfile → PUT /users/profile/update/
    await ServiceLocator.userService.updateProfile(UserProfileUpdate(name: name));
    final s = AppSession.instance;
    await s.save(
      accessToken: s.accessToken ?? '',
      refreshToken: s.refreshToken ?? '',
      userId: s.userId ?? 0,
      name: name,
      role: s.role ?? '',
    );

    final prev = await ArtistExtraDetails.load();
    // API call: artistService.updateProfile → PUT /artists/profile/update/
    // (registrationFields step: display_name + date_of_birth (18+) + profile_type; instagram optional)
    await ServiceLocator.artistService.updateProfile(ArtistProfileUpdate(
      displayName: display,
      dateOfBirth: _isoDate(_step1.dob!),
      instagramUrl: _instagramUrl(),
      profileTypes: prev.profileTypes.isEmpty ? null : prev.profileTypes.map((t) => t.name).toList(),
    ));

    final extra = prev.copyWith(
      dob: _step1.dob,
      displayName: display,
      professionalName: display,
    );
    await extra.save();
    await _saveDraft();
    await OnboardingProgress.markDetailsCompletedLocally();
  }

  /// Saves artistry.
  /// API: PUT /artists/profile/update/ (years_experience) + POST /artists/portfolio/create/ (work samples)
  Future<void> _saveArtistry() async {
    final years = _experienceYears[_experiences.indexOf(_step2.experience!)];
    // API call: artistService.updateProfile → PUT /artists/profile/update/
    // (experience_range is what the server shows; years_experience is only kept for older app versions)
    await ServiceLocator.artistService.updateProfile(ArtistProfileUpdate(
      yearsExperience: years,
      experienceRange: experienceRangeKeyFromLabel(_step2.experience),
    ));
    await _uploadWorkSamples();
    // Specialities must be one of the artist's OFFERED services, which are added later in
    // "Build My Artist Page" — they are kept here and pushed to the server from there.
    final extra = (await ArtistExtraDetails.load()).copyWith(specialities: _step2.specialities.toList());
    await extra.save();
    await _saveDraft();
    await OnboardingProgress.markServicesCompletedLocally();
  }

  /// Uploads the picked work photos as work samples (max 5 in total, images only).
  /// API: GET /artists/portfolio/get_all/ · GET /core/service-sub-category/get_all/ · POST /artists/portfolio/create/
  Future<void> _uploadWorkSamples() async {
    if (_step2.workPhotos.isEmpty) return;
    final existing = await ServiceLocator.artistService.getAllPortfolios(limit: 50);
    final have = existing.data.where((p) => p.isWorkSample).length;
    final room = 5 - have;
    _uploadedWorkSamples = have;
    if (room <= 0) {
      setState(() => _step2.workPhotos.clear());
      return;
    }
    // A work sample needs a valid sub-category; use the first one that matches a picked speciality, else the first active.
    final subs = (await ServiceLocator.coreService.getAllServiceSubCategories(limit: 100)).data.where((x) => x.isActive).toList();
    if (subs.isEmpty) throw Exception('Service Categories Are Not Available Right Now. Please Try Again.');
    final picked = _step2.specialities.map((e) => e.toLowerCase()).toList();
    final match = subs.where((x) => picked.any((p) => x.name.toLowerCase().contains(p) || p.contains(x.name.toLowerCase())));
    final subId = (match.isNotEmpty ? match.first : subs.first).subCategoryId;
    final batch = _step2.workPhotos.take(room).toList();
    for (final f in batch) {
      // API call: artistService.createPortfolio → POST /artists/portfolio/create/ (is_work_sample=true)
      await ServiceLocator.artistService.createPortfolio(CreatePortfolio(
        mediaType: MediaTypeEnum.image,
        subCategoryId: subId,
        file: f,
        isWorkSample: true,
      ));
    }
    _uploadedWorkSamples = have + batch.length;
    if (mounted) setState(() => _step2.workPhotos.clear());
  }

  /// API id_type value for the picked ID.
  String get _apiIdType => switch (_step3.idType) {
    GovIdType.aadhaar => 'aadhaar',
    GovIdType.voterId => 'voter_id',
    GovIdType.passport => 'passport',
    GovIdType.drivingLicense => 'driving_licence',
  };

  /// Saves documents.
  /// API: POST /artists/documents/create/ (multipart: document_type=id_proof, id_type, document_number, file, back_file)
  /// API: POST /artists/documents/create/ (multipart: document_type=pan, document_number, file)
  Future<void> _saveDocuments() async {
    final idNumber = _step3.idType == GovIdType.aadhaar
        ? aadhaarDigits(_idNumCtrl.text)
        : _idNumCtrl.text.trim().toUpperCase().replaceAll(' ', '');
    // The full ID / PAN number is never stored on the device (the server keeps it masked).
    await _saveDraft();

    // ── ID proof ──
    // Same ID, number and photos as the last successful upload → nothing new to send.
    final sig = '${_apiIdType}|$idNumber|${_step3.idFront?.path}|${_step3.idBack?.path}';
    if (_uploadedDocSig != sig) {
      try {
        // API call: artistBusiness.createDocument → POST /artists/documents/create/
        // (a new ID proof replaces the previous one and goes back to `pending`)
        await ServiceLocator.artistBusiness.createDocument(
          documentType: 'id_proof',
          idType: _apiIdType,
          documentNumber: idNumber,
          file: _step3.idFront!,
          backFile: _step3.idBack,
        );
        _uploadedDocSig = sig;
      } catch (e) {
        if (!kAllowOfflineOnboarding) rethrow;
        debugPrint('KYC submit failed, kept on device: $e');
      }
    }

    // ── PAN card ── (not shown when only the ID proof is being replaced)
    if (widget.updateIdProof) return;
    final panImage = _step3.panImage;
    if (panImage == null) return;
    final panNumber = _panNumCtrl.text.trim().toUpperCase();
    final panSig = '$panNumber|${panImage.path}';
    if (_uploadedPanSig == panSig) return;
    try {
      // API call: artistBusiness.createDocument → POST /artists/documents/create/
      // document_type=pan, document_number=ABCDE1234F, file=<PAN photo> (multipart)
      await ServiceLocator.artistBusiness.createDocument(
        documentType: 'pan',
        documentNumber: panNumber,
        file: panImage,
      );
      _uploadedPanSig = panSig;
    } catch (e) {
      if (!kAllowOfflineOnboarding) rethrow;
      debugPrint('PAN submit failed, kept on device: $e');
    }
  }

  /// Saves payout.
  /// API: PUT /artists/payout_account/set/
  Future<void> _savePayout() async {
    final upi = _upiCtrl.text.trim();
    final extra = (await ArtistExtraDetails.load()).copyWith(
      payoutMethod: PayoutMethod.bank,
      upiId: upi.isEmpty ? null : upi,
    );
    await extra.save();
    await _saveDraft();
    try {
      // API call: artistBusiness.setPayoutAccount → PUT /artists/payout_account/set/
      await ServiceLocator.artistBusiness.setPayoutAccount(
        accountHolderName: _holderCtrl.text.trim(),
        bankAccountNumber: _accCtrl.text.trim(),
        ifscCode: _ifscCtrl.text.trim().toUpperCase(),
        upiId: upi,
      );
    } catch (e) {
      if (!kAllowOfflineOnboarding) rethrow;
      debugPrint('Payout account failed, kept on device: $e');
    }
    await OnboardingProgress.markDocumentsCompletedLocally();
  }

  /// Opens agreement.
  Future<void> _openAgreement() async {
    if (!mounted) return;
    // Navigates to AgreementStepScreen
    final agreed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AgreementStepScreen()),
    );
    if (agreed == true && mounted) setState(() => _step = 5);
  }

  String get _title => widget.updateIdProof ? 'Update ID Proof' : switch (_step) {
    1 => 'About You',
    2 => 'Professional Details',
    3 => 'Document Verification',
    4 => 'Payout Details',
    _ => 'Application Status',
  };

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AiraColors.bg,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose)),
      );
    }
    if (_step == 5) return _underReview();

    // After registration this screen is the ROOT route (back stack cleared), so there is nothing to pop.
    // Back on the first step then offers to log out and return to Sign In instead of doing nothing.
    final canLeave = Navigator.of(context).canPop();
    return PopScope(
      canPop: widget.updateIdProof || (_step == 1 && canLeave),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_step > 1) {
          setState(() => _step--);
        } else {
          confirmAndLogout(context);
        }
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
                    title: _title,
                    onBack: () {
                      if (widget.updateIdProof) {
                        Navigator.of(context).pop();
                      } else if (_step > 1) {
                        setState(() => _step--);
                      } else if (canLeave) {
                        Navigator.of(context).pop();
                      } else {
                        confirmAndLogout(context);
                      }
                    },
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        switch (_step) {
                          1 => _identity(),
                          2 => _artistry(),
                          3 => _documents(),
                          _ => _payout(),
                        },
                      ],
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_error != null) ...[
                        Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, size: 16, color: AiraColors.errorText),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_error!,
                                  style: AiraText.sans(fontSize: 12.5, color: AiraColors.errorText, height: 1.35)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      PrimaryButton(
                        label: _busy ? 'Saving…' : (widget.updateIdProof ? 'Update ID Proof' : 'Save & Continue'),
                        arrow: true,
                        expand: true,
                        onTap: _busy ? null : _next,
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

  /// UI piece: heading.
  Widget _heading(String t, {String? sub}) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t, style: AiraText.serif(fontSize: 18, fontWeight: FontWeight.w700)),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(sub, style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
        ],
      ],
    ),
  );

  /// UI piece: box.
  Widget _box({required Widget child}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: AiraColors.pinkFill,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AiraColors.pinkBorder, width: 1.1),
    ),
    child: child,
  );

  /// UI piece: identity.
  Widget _identity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text('LET’S GET TO KNOW YOU',
              style: AiraText.sans(fontSize: 10.5, letterSpacing: 2, color: AiraColors.charcoalSoft)),
        ),
        const SizedBox(height: 6),
        const Center(
          child: SunndariTitle(
            title: 'Your Artist Identity',
            subtitle: 'Tell Us Who You Are And How Clients Should Know You.',
            size: 32,
          ),
        ),
        const SizedBox(height: 22),
        SunndariField(
          label: 'Artist Name',
          controller: _fullNameCtrl,
          hint: 'Enter Your Name',
          helper: _artistNameLocked ? 'This Is The Name You Registered With.' : 'As Mentioned On Your ID.',
          capitalization: TextCapitalization.words,
          readOnly: _artistNameLocked,
          onChanged: (v) {
            if (_step1.sameAsFullName) setState(() => _dispNameCtrl.text = v);
          },
        ),
        SunndariField(
          label: 'Brand Name',
          controller: _dispNameCtrl,
          hint: 'Enter Your Brand Name',
          helper: _brandLocked
              ? 'Your Brand Name Is Saved And Cannot Be Changed.'
              : 'This Is The Name Clients Will See On Sunndari. It Cannot Be Changed Later.',
          capitalization: TextCapitalization.words,
          readOnly: _brandLocked,
          onChanged: (_) {
            if (_step1.sameAsFullName) setState(() => _step1.sameAsFullName = false);
          },
        ),
        if (!_brandLocked) InkWell(
          onTap: () => setState(() {
            _step1.sameAsFullName = !_step1.sameAsFullName;
            if (_step1.sameAsFullName) _dispNameCtrl.text = _fullNameCtrl.text;
          }),
          child: Row(
            children: [
              Checkbox(
                value: _step1.sameAsFullName,
                activeColor: AiraColors.roseDeep,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => setState(() {
                  _step1.sameAsFullName = v ?? false;
                  if (_step1.sameAsFullName) _dispNameCtrl.text = _fullNameCtrl.text;
                }),
              ),
              Text('Same As Artist Name', style: AiraText.sans(fontSize: 13, color: AiraColors.roseDeep)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SunndariField(
          label: 'Date Of Birth',
          controller: _dobCtrl,
          hint: 'DD/MM/YYYY',
          keyboardType: TextInputType.number,
          formatters: const [_DobSlashFormatter()],
          onChanged: (v) => _step1.dob = parseDob(v),
          suffix: IconButton(
            icon: const Icon(Icons.calendar_today_outlined, size: 20, color: AiraColors.roseDeep),
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                // day-first (DD/MM/YYYY) so the picker's own typing mode matches this field
                locale: const Locale('en', 'GB'),
                initialDate: _step1.dob ?? DateTime(now.year - 25, now.month, now.day),
                firstDate: DateTime(1950),
                lastDate: DateTime(now.year - 18, now.month, now.day),
                helpText: 'Select Date Of Birth',
                // Calendar only (no pencil/typing mode): Flutter's built-in typing box cannot add the "/"
                // automatically. Typing is done in the field itself, which adds the "/" as you type.
                initialEntryMode: DatePickerEntryMode.calendarOnly,
                builder: (ctx, child) => Theme(
                  data: Theme.of(ctx).copyWith(
                    colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AiraColors.rose),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) {
                setState(() {
                  _step1.dob = picked;
                  _dobCtrl.text = formatDob(picked);
                });
              }
            },
          ),
        ),
        SunndariField(
          label: 'Instagram Profile Link',
          optionalTag: 'Optional',
          controller: _instaCtrl,
          hint: 'https://instagram.com/yourhandle',
          keyboardType: TextInputType.url,
          suffix: const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.camera_alt_outlined, size: 20, color: AiraColors.roseDeep),
          ),
        ),
      ],
    );
  }

  /// UI piece: artistry.
  Widget _artistry() {
    final tileW = (MediaQuery.of(context).size.width - 58) / 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(
          child: SunndariTitle(
            title: 'Your Artistry',
            subtitle: 'Tell Us About Your Experience And Show Us Your Work.',
            size: 32,
          ),
        ),
        const SizedBox(height: 18),
        _heading('Makeup Experience'),
        _box(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _step2.experience,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AiraColors.roseDeep),
              hint: Text('Select Years Of Experience',
                  style: AiraText.sans(fontSize: 14, color: AiraColors.charcoalSoft.withOpacity(0.7))),
              items: _experiences.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setState(() => _step2.experience = v),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _heading('Your Specialities', sub: 'Select All That Apply.'),
        if (_specialitiesLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose)),
          )
        else if (_specialitiesFailed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Could Not Load Specialities.',
                      style: AiraText.sans(fontSize: 13, color: AiraColors.errorText)),
                ),
                TextButton(onPressed: _loadSpecialities, child: const Text('Retry')),
              ],
            ),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _specialities.map((item) {
              final on = _step2.specialities.contains(item);
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => on ? _step2.specialities.remove(item) : _step2.specialities.add(item)),
                child: Container(
                  width: tileW,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  decoration: BoxDecoration(
                    color: AiraColors.pinkFill,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: on ? AiraColors.roseDeep : AiraColors.pinkBorder, width: on ? 1.5 : 1.1),
                  ),
                  child: Row(
                    children: [
                      Icon(on ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                          size: 19, color: on ? AiraColors.roseDeep : AiraColors.charcoalSoft),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item, style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w600))),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: 16),
        _heading('Your Work, In Pictures', sub: 'Upload 1 To 5 Photos Of Makeup You’ve Done (At Least 1 Is Required).'),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            try {
              final picked = await _picker.pickMultiImage(); // originals — the server shrinks them
              if (picked.isEmpty) return;
              final room = 5 - _step2.workPhotos.length;
              if (picked.length > room && mounted) {
                AppFeedback.showInfo(context, 'You Can Add Up To 5 Photos');
              }
              if (room > 0) setState(() => _step2.workPhotos.addAll(picked.take(room)));
            } catch (e) {
              if (mounted) AppFeedback.showError(context, e);
            }
          },
          child: Container(
            width: double.infinity,
            height: 120,
            decoration: BoxDecoration(
              color: AiraColors.pinkFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AiraColors.pinkBorder, width: 1.1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add_photo_alternate_outlined, size: 30, color: AiraColors.roseDeep),
                const SizedBox(height: 6),
                Text('Add Work Photos',
                    style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: AiraColors.charcoal)),
                Text(
                  _step2.workPhotos.isEmpty ? (_uploadedWorkSamples > 0 ? '$_uploadedWorkSamples Already Saved — Tap To Add More' : 'Required · Choose From Your Gallery') : '${_step2.workPhotos.length} Of 5 Selected — Tap To Add More',
                  style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft),
                ),
              ],
            ),
          ),
        ),
        if (_step2.workPhotos.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _step2.workPhotos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(_step2.workPhotos[i].path), width: 64, height: 64, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: -6,
                    top: -6,
                    child: GestureDetector(
                      onTap: () => setState(() => _step2.workPhotos.removeAt(i)),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(color: AiraColors.roseDeep, shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded, size: 13, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text('These Photos Help Our Team Review Your Application.',
            style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
      ],
    );
  }

  /// Lets the user pick doc.
  Future<void> _pickDoc(void Function(XFile) set) async {
    try {
      // Phone photos can be 5–10 MB; shrink them so the upload does not fail or time out.
      final x = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1800, imageQuality: 80);
      if (x == null) return;
      final bytes = await x.length();
      if (bytes > 8 * 1024 * 1024) {
        if (mounted) AppFeedback.showWarning(context, 'This Photo Is Too Large (Over 8 MB). Please Choose A Smaller One.');
        return;
      }
      // The picker's own copy lives in the cache folder, which Android can clean at any time
      // (e.g. while the artist reads the agreement). Keep a copy in app storage instead.
      final kept = await _keepPickedFile(x);
      if (mounted) setState(() => set(kept));
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    }
  }

  /// Copies a picked photo from the (temporary) cache into the app's own documents folder.
  /// Falls back to the original file if the copy cannot be made.
  Future<XFile> _keepPickedFile(XFile x) async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}kyc_photos');
      if (!await dir.exists()) await dir.create(recursive: true);
      final dot = x.name.lastIndexOf('.');
      final ext = dot == -1 ? '.jpg' : x.name.substring(dot);
      final dest = '${dir.path}${Platform.pathSeparator}doc_${DateTime.now().microsecondsSinceEpoch}$ext';
      await File(x.path).copy(dest);
      return XFile(dest, name: x.name);
    } catch (_) {
      return x;
    }
  }

  /// If a selected photo no longer exists on the phone, un-select it and say which one to re-pick.
  String? _vanishedDocs() {
    bool gone(XFile? f) => f != null && !File(f.path).existsSync();
    final lost = <String>[];
    if (gone(_step3.idFront)) { _step3.idFront = null; lost.add('Front Side'); }
    if (gone(_step3.idBack)) { _step3.idBack = null; lost.add('Back Side'); }
    if (gone(_step3.panImage)) { _step3.panImage = null; lost.add('PAN Card'); }
    if (lost.isEmpty) return null;
    return 'Your ${lost.join(' And ')} Photo Is No Longer Available On The Phone. Please Select It Again.';
  }

  /// Id hint.
  String get _idHint => switch (_step3.idType) {
    GovIdType.aadhaar => '1234 5678 9012',
    GovIdType.voterId => 'e.g. ABC1234567',
    GovIdType.passport => 'e.g. A1234567',
    GovIdType.drivingLicense => 'MH12 20110012345',
  };

  /// UI piece: documents.
  Widget _documents() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: SunndariTitle(
            title: widget.updateIdProof ? 'Update Your\nID Proof' : 'Your Documents',
            subtitle: widget.updateIdProof
                ? 'Upload A New ID. It Replaces The Old One And Is Verified Again.'
                : 'Upload Clear, Readable Copies For Your Onboarding Review.',
            size: 32,
          ),
        ),
        const SizedBox(height: 18),
        _heading('Government-Issued ID', sub: 'Choose Any One Of These Documents.'),
        Text('Document Type', style: AiraText.sans(fontSize: 13, color: AiraColors.charcoalSoft)),
        const SizedBox(height: 6),
        _box(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<GovIdType>(
              value: _step3.idType,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AiraColors.roseDeep),
              items: GovIdType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label))).toList(),
              onChanged: (v) {
                if (v == null || v == _step3.idType) return;
                setState(() {
                  _step3.idType = v;
                  _idNumCtrl.clear();
                  _step3.idFront = null;
                  _step3.idBack = null;
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 14),
        SunndariField(
          key: ValueKey('doc-${_step3.idType.name}'),
          label: 'Document Number',
          controller: _idNumCtrl,
          hint: _idHint,
          helper: switch (_step3.idType) {
            GovIdType.aadhaar => '12 Digits — Spaces Are Added Automatically.',
            GovIdType.voterId => '10 Characters: 3 Letters + 7 Digits.',
            GovIdType.passport => '8 Characters: 1 Letter + 7 Digits.',
            GovIdType.drivingLicense => 'State Code + RTO + Year + Number (13–16 Characters).',
          },
          capitalization: TextCapitalization.characters,
          keyboardType: _step3.idType == GovIdType.aadhaar ? TextInputType.number : TextInputType.visiblePassword,
          formatters: [
            switch (_step3.idType) {
              GovIdType.aadhaar => const _DocNumberFormatter(maxChars: 12, digitsOnly: true, groupEvery: 4),
              GovIdType.voterId => const _DocNumberFormatter(maxChars: 10),
              GovIdType.passport => const _DocNumberFormatter(maxChars: 8),
              GovIdType.drivingLicense => const _DocNumberFormatter(maxChars: 16, groupEvery: 4),
            },
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _uploadBox('Front Side', 'Upload Document', _step3.idFront, () => _pickDoc((x) => _step3.idFront = x)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _uploadBox('Back Side', _step3.idType == GovIdType.passport ? 'If Applicable' : 'Upload Document',
                  _step3.idBack, () => _pickDoc((x) => _step3.idBack = x)),
            ),
          ],
        ),
        if (!widget.updateIdProof) ...[
          const SizedBox(height: 20),
          _heading('PAN Number'),
          Divider(thickness: 1,),
          SunndariField(
            label: 'Enter Your PAN Number',
            controller: _panNumCtrl,
            hint: 'Enter PAN Number',
            capitalization: TextCapitalization.characters,
            helper: '10 Characters, e.g. ABCDE1234F',
            formatters: const [_DocNumberFormatter(maxChars: 10)],
          ),
          const SizedBox(height: 6),
          _heading('PAN Card Document'),
          _uploadBox('Upload PAN Card', 'Choose A Photo Or File', _step3.panImage, () => _pickDoc((x) => _step3.panImage = x),
              full: true),
        ],
        const SizedBox(height: 6),
        Text('Make Sure The Text And Photo Are Easy To Read.',
            style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
      ],
    );
  }

  /// UI: uploads box.
  Widget _uploadBox(String title, String hint, XFile? file, VoidCallback onTap, {bool full = false}) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: full ? 110 : 104,
        width: full ? double.infinity : null,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AiraColors.pinkFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: file != null ? AiraColors.success : AiraColors.pinkBorder, width: 1.1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(file != null ? Icons.check_circle_rounded : Icons.upload_file_outlined,
                size: 26, color: file != null ? AiraColors.success : AiraColors.roseDeep),
            const SizedBox(height: 4),
            Text(title, style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w700)),
            Text(file != null ? 'Selected ✓ (Tap To Change)' : hint,
                textAlign: TextAlign.center,
                style: AiraText.sans(fontSize: 11, color: AiraColors.charcoalSoft)),
          ],
        ),
      ),
    );
  }

  /// UI piece: payout.
  Widget _payout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(
          child: SunndariTitle(
            title: 'Your Payout Details',
            subtitle: 'Add Your Bank Details To Receive Your Payouts.',
            size: 32,
          ),
        ),
        const SizedBox(height: 22),
        SunndariField(
          label: 'Account Holder’s Name',
          controller: _holderCtrl,
          hint: 'Name As Per Bank Account',
          formatters: [FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z .'-]")), LengthLimitingTextInputFormatter(60)],
          capitalization: TextCapitalization.words,
        ),
        SunndariField(
          label: 'Bank Account Number',
          controller: _accCtrl,
          hint: 'Enter Account Number',
          helper: 'Bank Account Numbers Are 9 To 18 Digits.',
          keyboardType: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(18)],
        ),
        SunndariField(
          label: 'Confirm Account Number',
          controller: _confirmAccCtrl,
          hint: 'Re-Enter Account Number',
          keyboardType: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(18)],
        ),
        SunndariField(
          label: 'IFSC Code',
          controller: _ifscCtrl,
          hint: 'Enter IFSC Code',
          helper: _ifscLooking ? 'Checking IFSC…' : '11 Characters, e.g. SBIN0001234',
          errorText: _ifscError,
          capitalization: TextCapitalization.characters,
          formatters: const [_DocNumberFormatter(maxChars: 11)],
          onChanged: _onIfscChanged,
          suffix: _ifscLooking
              ? const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AiraColors.rose)),
          )
              : null,
        ),
        SunndariField(
          label: 'Bank Name',
          controller: _bankCtrl,
          hint: 'Fills Automatically From IFSC',
          readOnly: true,
          capitalization: TextCapitalization.words,
        ),
        SunndariField(
          label: 'UPI ID',
          optionalTag: 'Optional',
          controller: _upiCtrl,
          hint: 'Enter UPI ID',
          capitalization: TextCapitalization.none,
        ),
        Text('Please Check Your Account Details Carefully.',
            style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
      ],
    );
  }

  /// Checks with the server whether the admin has approved the application.
  /// Approved → opens the next screen (Artist Page Setup) by itself. Still pending → stays here.
  /// [silent] = background check (timer / app resume): no loader, no messages.
  Future<void> _refreshStatus({bool silent = false}) async {
    if (_busy || _polling) return;
    if (silent) {
      _polling = true;
    } else {
      setState(() => _busy = true);
    }
    try {
      final screen = await resolvePostAuthScreen();
      if (!mounted) return;
      if (screen is OnboardingFlowScreen) {
        // Not approved yet — nothing to open.
        if (!silent) AppFeedback.showInfo(context, 'Still Under Review — We’ll Notify You Once It’s Approved');
        return;
      }
      _poll?.cancel();
      // Navigates to the next screen (Artist Page Setup / Under Review / Home)
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => screen), (r) => false);
    } catch (e) {
      if (mounted && !silent) AppFeedback.showError(context, e, onRetry: _refreshStatus);
    } finally {
      _polling = false;
      if (mounted && !silent) setState(() => _busy = false);
    }
  }

  /// Logs the user out.
  Future<void> _logout() async {
    await AppSession.instance.clear();
    if (!mounted) return;
    // Navigates to LoginScreen
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
  }

  /// UI piece: under review.
  Widget _underReview() {
    if (!_idProofLoadStarted) {
      _idProofLoadStarted = true;
      _loadIdProof();
    }
    return Scaffold(
      backgroundColor: AiraColors.bg,
      body: SunndariBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            children: [
              Center(
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: const BoxDecoration(color: AiraColors.blush, shape: BoxShape.circle),
                  child: const Icon(Icons.pending_actions_rounded, size: 42, color: AiraColors.roseDeep),
                ),
              ),
              const SizedBox(height: 18),
              const SunndariTitle(
                title: 'Onboarding\nUnder Review',
                subtitle: 'Your Application Has Been Received. Our Team Is Reviewing Your Details And Documents.',
                size: 34,
              ),
              const SizedBox(height: 22),
              AiraCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _statusTile('Application Submitted', 'Your Details Have Been Received.', 0),
                    const Divider(color: AiraColors.hair, height: 18),
                    _statusTile('Admin Review', 'In Progress', 1),
                    _idProofLine(),
                    const Divider(color: AiraColors.hair, height: 18),
                    _statusTile('Set Up Your Artist Page', 'Available After Approval', 2),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: AiraColors.charcoalSoft),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Your Artist Profile Is Not Live Yet. We’ll Notify You When Your Application Status Changes.',
                        style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft, height: 1.4)),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              PrimaryButton(
                label: _busy ? 'Checking…' : 'Check Application Status',
                expand: true,
                onTap: _busy ? null : () => _refreshStatus(),
              ),
              const SizedBox(height: 10),
              GhostButton(
                label: 'Contact Support',
                icon: Icons.headset_mic_outlined,
                expand: true,
                // Navigates to HelpCenterScreen
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpCenterScreen())),
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: _logout,
                  child: Text('Log Out',
                      style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w700, color: AiraColors.charcoalSoft)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ID proof verification line (Verified / Pending / Rejected) shown inside the Admin Review step.
  Widget _idProofLine() {
    final st = _idProofStatus;
    if (st == null) return const SizedBox.shrink();
    final IconData icon;
    final Color color;
    final String label;
    switch (st) {
      case ApprovalStatusKind.approved:
        icon = Icons.verified_rounded;
        color = AiraColors.success;
        label = 'ID Proof: Verified';
        break;
      case ApprovalStatusKind.rejected:
        icon = Icons.error_outline_rounded;
        color = AiraColors.errorText;
        label = 'ID Proof: Rejected';
        break;
      default:
        icon = Icons.hourglass_bottom_rounded;
        color = AiraColors.roseDeep;
        label = 'ID Proof: Verification Pending';
    }
    final reason = st == ApprovalStatusKind.rejected && (_idProofRejection ?? '').isNotEmpty ? _idProofRejection! : null;
    return Padding(
      padding: const EdgeInsets.only(left: 34, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w600, color: color))),
            ],
          ),
          if (reason != null) ...[
            const SizedBox(height: 3),
            Text(reason, style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft, height: 1.35)),
          ],
        ],
      ),
    );
  }

  /// UI piece: status tile.
  Widget _statusTile(String title, String desc, int state) {
    final IconData icon = state == 0
        ? Icons.check_circle_rounded
        : state == 1
        ? Icons.hourglass_top_rounded
        : Icons.radio_button_unchecked;
    final Color color = state == 0
        ? AiraColors.success
        : state == 1
        ? AiraColors.roseDeep
        : AiraColors.charcoalSoft;
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w700)),
              Text(desc, style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
            ],
          ),
        ),
      ],
    );
  }
}