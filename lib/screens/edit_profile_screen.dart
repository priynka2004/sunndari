// FILE: screens/edit_profile_screen.dart
// SCREEN: Edit Profile — photos, Brand Name, personal details, professional details, location.
//
// APIs used:
//   GET /users/profile/get/ · GET /artists/profile/get/
//   PUT /artists/profile/update/            (bio, city, years_experience, date_of_birth, profile_type, display_name)
//   PUT /users/profile/update/              (name only — email / phone are changed with a code)
//   PUT /artists/profile/photo/upload/      (profile photo + cover photo)
//   POST /users/contact/change/request/ · /verify/   (change email / phone with a code)

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, LengthLimitingTextInputFormatter;
import 'package:image_picker/image_picker.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/change_contact_sheet.dart';
import '../widgets/city_autocomplete_field.dart';
import '../models/artist/artist_profile.dart';
import '../models/artist/artist_profile_update.dart';
import '../models/user/user_profile.dart';
import '../models/user/customer_address_create.dart';
import '../models/user/customer_address_update.dart';
import '../utils/service_locator.dart';
import '../utils/app_session.dart';
import '../utils/app_feedback.dart';
import '../utils/artist_extra_details.dart';
import '../utils/pending_email.dart';
import '../utils/dob_input.dart';
import '../utils/experience.dart';
import '../utils/media_url.dart';
import '../widgets/google_place_picker.dart';

/// SCREEN: Edit Profile.
class EditProfileScreen extends StatefulWidget {
  final ArtistProfile? profile;
  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

/// State of [EditProfileScreen] — holds the screen data and logic.
class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  String _email = '';
  String _pendingEmail = ''; // typed at sign-up, not verified yet
  String _phone = '';

  String? _selectedCity;
  String? _experience; // one of kExperienceRanges — same value as Onboarding and Profile
  final Set<ArtistProfileType> _profileTypes = {}; // freelancer, studio, or both
  int _serverTypeCount = 0; // how many work types the server already has for this artist
  final _instaCtrl = TextEditingController();
  List<String> _specialities = const [];
  ArtistExtraDetails _existingExtra = const ArtistExtraDetails();

  int? _baseAddressId;
  String? _serverAddress;
  String? _serverPin;
  double? _baseLat; // exact Google Maps location of the address (saved with it)
  double? _baseLng;
  bool _geoDirty = false; // a new place was picked on the map and still has to be saved

  // Photos
  String? _photoUrl;
  String? _coverUrl;
  String? _newPhotoPath;
  String? _newCoverPath;

  int _cityKey = 0; // rebuilds the city field once the saved city has loaded
  bool _brandLocked = false; // fixed once saved
  bool _saving = false;
  bool _loadingAccount = true;
  String? _error;
  final Map<String, String> _errors = {};

  /// Runs once when the screen opens.
  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _bioCtrl.text = p?.bio ?? '';
    _brandCtrl.text = p?.displayName ?? '';
    _brandLocked = (p?.displayName ?? '').trim().isNotEmpty;
    _selectedCity = (p?.city != null && p!.city!.isNotEmpty) ? p.city : null;
    if (p != null) _experience = experienceDisplay(rangeKey: p.experienceRange, years: p.yearsExperience) ?? _experience;
    _photoUrl = p?.profilePhotoUrl;
    _coverUrl = p?.coverPhotoUrl;
    _nameCtrl.text = AppSession.instance.name ?? '';
    _loadAccount();
    _loadExtra();
  }

  /// Loads the artist profile (own).
  /// API: GET /artists/profile/get/ · GET /users/address/get_all/
  Future<void> _loadExtra() async {
    try {
      final p = await ServiceLocator.artistService.getProfile();
      // The server keeps one or both work types now (profileTypes); profileType is only its first item.
      final serverTypes = p.profileTypes.isNotEmpty ? p.profileTypes : (p.profileType == null ? <String>[] : [p.profileType!]);
      _serverTypeCount = serverTypes.length;
      if (serverTypes.contains('studio')) _profileTypes.add(ArtistProfileType.studio);
      if (serverTypes.contains('freelance')) _profileTypes.add(ArtistProfileType.freelance);
      if ((p.instagramUrl ?? '').isNotEmpty) _instaCtrl.text = p.instagramUrl!;
      final d = DateTime.tryParse(p.dateOfBirth ?? '');
      if (d != null) _dobCtrl.text = formatDob(d);
      if ((p.displayName ?? '').isNotEmpty) {
        _brandCtrl.text = p.displayName!;
        _brandLocked = true;
      }
      if ((p.bio ?? '').isNotEmpty && _bioCtrl.text.isEmpty) _bioCtrl.text = p.bio!;
      _experience = experienceDisplay(rangeKey: p.experienceRange, years: p.yearsExperience) ?? _experience;
      if ((p.city ?? '').isNotEmpty) _selectedCity = p.city;
      _photoUrl = p.profilePhotoUrl ?? _photoUrl;
      _coverUrl = p.coverPhotoUrl ?? _coverUrl;
      _baseAddressId = p.baseAddressId;
      if (_baseAddressId != null) {
        final all = (await ServiceLocator.userService.getAllAddresses(limit: 50)).data;
        final m = all.where((a) => a.addressId == _baseAddressId);
        if (m.isNotEmpty) {
          _serverAddress = m.first.addressLine1;
          _serverPin = m.first.pinCode;
          _baseLat = m.first.latitude;
          _baseLng = m.first.longitude;
        }
      }
    } catch (_) {}
    // Older profiles stored ONE profile_type, but the venues saved in the Location step are location types:
    // In-Salon (id 2) = studio, Home Visit / On-Site Event (ids 1, 3) = freelance. Both present → tick both.
    final venueTypes = <ArtistProfileType>[];
    try {
      // API call: GET /artists/locations/get_all/
      final raw = await ServiceLocator.artistService.getAllLocations();
      final rows = raw is List ? raw : (raw is Map && raw['data'] is List ? raw['data'] as List : const []);
      final ids = rows.whereType<Map>().map((r) => (r['locationTypeId'] as num?)?.toInt()).whereType<int>().toSet();
      if (ids.contains(2) && (ids.contains(1) || ids.contains(3))) {
        venueTypes..add(ArtistProfileType.studio)..add(ArtistProfileType.freelance); // studio first = same value the server keeps
      }
    } catch (_) {}
    final extra = await ArtistExtraDetails.load();
    if (!mounted) return;
    setState(() {
      _cityKey++;
      _existingExtra = extra;
      _addressCtrl.text = _serverAddress ?? extra.address ?? '';
      _pinCtrl.text = _serverPin ?? extra.pincode ?? '';
      if (_dobCtrl.text.isEmpty && extra.dob != null) _dobCtrl.text = formatDob(extra.dob);
      // The server keeps both work types now. An artist who chose both before that, and whose server profile
      // still has only one, keeps both ticked here (they are sent to the server when the profile is saved).
      if (_serverTypeCount < 2) {
        if (extra.profileTypes.isNotEmpty) _profileTypes..clear()..addAll(extra.profileTypes);
        if (venueTypes.length == 2) _profileTypes..clear()..addAll(venueTypes);
      }
      _specialities = extra.specialities;
      if (_brandCtrl.text.isEmpty) _brandCtrl.text = extra.professionalName ?? extra.displayName ?? '';
    });
  }

  /// Loads account (name, email, phone).
  /// API: GET /users/profile/get/
  Future<void> _loadAccount() async {
    final userId = AppSession.instance.userId;
    if (userId == null) {
      setState(() => _loadingAccount = false);
      return;
    }
    try {
      final UserProfile account = await ServiceLocator.userService.getProfile(userId);
      if (!mounted) return;
      final pending = (account.email ?? '').isNotEmpty ? '' : await PendingEmail.load();
      if ((account.email ?? '').isNotEmpty) PendingEmail.clear();
      if (!mounted) return;
      setState(() {
        _nameCtrl.text = account.name;
        _email = account.email ?? '';
        _pendingEmail = pending;
        _phone = account.phoneNumber ?? '';
        _loadingAccount = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingAccount = false);
      AppFeedback.showWarning(context, "Couldn't Load Your Account Details — You Can Still Edit Your Artist Profile Below.");
    }
  }

  /// Frees controllers when the screen closes.
  @override
  void dispose() {
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _instaCtrl.dispose();
    _bioCtrl.dispose();
    _dobCtrl.dispose();
    _addressCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  // ───────────────────────── Photos ─────────────────────────

  Future<void> _pickProfilePhoto() async {
    final path = await ArtistExtraDetails.pickAndSaveProfilePhoto(source: ImageSource.gallery);
    if (path != null && mounted) setState(() => _newPhotoPath = path);
  }

  Future<void> _pickCoverPhoto() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery); // original photo — the server shrinks it
      if (x != null && mounted) setState(() => _newCoverPath = x.path);
    } catch (_) {}
  }

  ImageProvider? _imageFor(String? localPath, String? url) {
    if (localPath != null && localPath.isNotEmpty && File(localPath).existsSync()) return FileImage(File(localPath));
    final full = resolveMediaUrl(url);
    return full == null ? null : NetworkImage(full);
  }

  /// Cover photo with the profile photo overlapping its bottom edge.
  Widget _photoHeader() {
    final cover = _imageFor(_newCoverPath, _coverUrl);
    final avatar = _imageFor(_newPhotoPath, _photoUrl);
    final initial = _brandCtrl.text.trim().isNotEmpty
        ? _brandCtrl.text.trim()[0].toUpperCase()
        : (_nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim()[0].toUpperCase() : 'S');
    return SizedBox(
      height: 190,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            bottom: 40,
            child: GestureDetector(
              onTap: _pickCoverPhoto,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: cover == null ? AiraGradients.hero : null,
                  border: Border.all(color: AiraColors.hair),
                  image: cover == null ? null : DecorationImage(image: cover, fit: BoxFit.cover),
                ),
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: _pill(Icons.photo_camera_outlined, cover == null ? 'Add Cover Photo' : 'Change Cover'),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 18,
            bottom: 0,
            child: GestureDetector(
              onTap: _pickProfilePhoto,
              child: Stack(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: avatar == null ? AiraGradients.avatarOrb : null,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: [BoxShadow(color: AiraColors.rose.withOpacity(0.18), blurRadius: 14, offset: const Offset(0, 5))],
                      image: avatar == null ? null : DecorationImage(image: avatar, fit: BoxFit.cover),
                    ),
                    alignment: Alignment.center,
                    child: avatar == null
                        ? Text(initial, style: AiraText.serif(fontSize: 30, fontWeight: FontWeight.w600, color: Colors.white))
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 2,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AiraColors.roseDeep,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.photo_camera_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 118,
            bottom: 6,
            right: 0,
            child: Text('Tap A Photo To Change It.',
                style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
          ),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.92), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: AiraColors.roseDeep),
          const SizedBox(width: 5),
          Text(text, style: AiraText.sans(fontSize: 11.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
        ]),
      );

  // ───────────────────────── UI pieces ─────────────────────────

  Widget _section(IconData icon, String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AiraCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              SunndariIconBubble(icon: icon, size: 34),
              const SizedBox(width: 10),
              Text(title, style: AiraText.serif(fontSize: 17)),
            ]),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  /// Read-only value with a lock icon (cannot be changed in the app).
  Widget _lockedRow(String label, String value, String note) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AiraColors.blush.withOpacity(0.55),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AiraColors.pinkBorder, width: 1.1),
            ),
            child: Row(children: [
              Expanded(child: Text(value, style: AiraText.sans(fontSize: 14.5, color: AiraColors.charcoalSoft))),
              const Icon(Icons.lock_outline_rounded, size: 18, color: AiraColors.charcoalSoft),
            ]),
          ),
          const SizedBox(height: 5),
          Text(note, style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
        ],
      ),
    );
  }

  /// Email: can be added once. After it is saved it is locked and cannot be changed.
  Widget _emailRow() {
    if (_email.isNotEmpty) return _lockedRow('Email', _email, 'Your Email Cannot Be Changed.');
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Email', style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.only(left: 14, right: 4),
            decoration: BoxDecoration(
              color: AiraColors.pinkFill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AiraColors.pinkBorder, width: 1.1),
            ),
            child: Row(children: [
              Expanded(
                child: Text(_pendingEmail.isEmpty ? 'Not Added' : _pendingEmail,
                    style: AiraText.sans(fontSize: 14.5, color: _pendingEmail.isEmpty ? AiraColors.charcoalSoft : AiraColors.charcoal)),
              ),
              TextButton(
                onPressed: () async {
                  final added = await showChangeContactSheet(context, isEmail: true, initialValue: _pendingEmail);
                  if (added && mounted) {
                    PendingEmail.clear();
                    AppFeedback.showSuccess(context, 'Email Added ✓');
                    _loadAccount();
                  }
                },
                child: Text(_pendingEmail.isEmpty ? 'Add' : 'Verify', style: AiraText.sans(fontWeight: FontWeight.w700, color: AiraColors.rose)),
              ),
            ]),
          ),
          const SizedBox(height: 5),
          Text(
              _pendingEmail.isEmpty
                  ? 'Once Added, Your Email Cannot Be Changed.'
                  : 'You Entered This While Signing Up. Verify It With A Code To Save It. Once Added, It Cannot Be Changed.',
              style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
        ],
      ),
    );
  }

  /// Phone number: changing it asks for permission first, then a code is sent to the NEW number.
  Widget _phoneRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mobile Number', style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.only(left: 14, right: 4),
            decoration: BoxDecoration(
              color: AiraColors.blush.withOpacity(0.55),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AiraColors.pinkBorder, width: 1.1),
            ),
            child: Row(children: [
              Expanded(
                child: Text(_phone.isEmpty ? 'Not Added' : _phone,
                    style: AiraText.sans(fontSize: 14.5, color: _phone.isEmpty ? AiraColors.charcoalSoft : AiraColors.charcoal)),
              ),
              TextButton(
                onPressed: _changePhone,
                child: Text(_phone.isEmpty ? 'Add' : 'Change', style: AiraText.sans(fontWeight: FontWeight.w700, color: AiraColors.rose)),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _changePhone() async {
    final allow = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AiraColors.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Change Mobile Number?', style: AiraText.serif(fontSize: 19)),
        content: Text(
          'This Is Your Login Number. A Code Will Be Sent To The New Number To Confirm The Change.',
          style: AiraText.sans(fontSize: 13.5, color: AiraColors.charcoalSoft, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Continue', style: AiraText.sans(fontWeight: FontWeight.w700, color: AiraColors.rose)),
          ),
        ],
      ),
    );
    if (allow != true || !mounted) return;
    final changed = await showChangeContactSheet(context, isEmail: false);
    if (changed && mounted) {
      AppFeedback.showSuccess(context, 'Mobile Number Updated ✓');
      _loadAccount();
    }
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            gradient: selected ? AiraGradients.aira : null,
            color: selected ? null : AiraColors.pinkFill,
            borderRadius: BorderRadius.circular(999),
            border: selected ? null : Border.all(color: AiraColors.pinkBorder, width: 1.1),
          ),
          child: Text(label,
              style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? Colors.white : AiraColors.charcoal)),
        ),
      );

  Widget _label(String text, {String? error}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
      );

  // ───────────────────────── Save ─────────────────────────

  /// Validates every field and fills [_errors] with clear messages.
  bool _validate() {
    _errors.clear();
    if (!_brandLocked && _brandCtrl.text.trim().isEmpty) _errors['brand'] = 'Please Enter Your Brand Name.';
    final dobProblem = validateDob(_dobCtrl.text);
    if (dobProblem != null) _errors['dob'] = dobProblem;
    if (_experience == null) _errors['exp'] = 'Please Select Your Experience.';
    if (_profileTypes.isEmpty) _errors['type'] = 'Please Select Freelancer, Studio Or Both.';
    final insta = _instaCtrl.text.trim();
    if (insta.isNotEmpty && !RegExp(r'^(https?://)?(www\.)?instagram\.com/[\w.]+/?.*$', caseSensitive: false).hasMatch(insta)) {
      _errors['insta'] = 'Please Enter A Valid Instagram Link, Or Leave It Empty.';
    }
    final line = _addressCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    if (line.isNotEmpty || pin.isNotEmpty) {
      if (line.length < 3) _errors['address'] = 'Please Enter Your Full Address.';
      if (!RegExp(r'^\d{6}$').hasMatch(pin)) _errors['pin'] = 'Please Enter A Valid 6-digit Pincode.';
    }
    return _errors.isEmpty;
  }

  /// Keeps the server base address in sync (needed by the onboarding "location" step).
  /// API: PUT /users/address/update/ (existing) or POST /users/address/create/ + PUT /artists/profile/update/ (base_address_id)
  Future<void> _saveBaseAddress() async {
    final line = _addressCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    if (line.isEmpty && pin.isEmpty) return;
    if (line == (_serverAddress ?? '') && pin == (_serverPin ?? '') && _baseAddressId != null && !_geoDirty) return;
    final city = (_selectedCity ?? '').trim().isEmpty ? 'India' : _selectedCity!.trim();
    final user = ServiceLocator.userService;
    if (_baseAddressId != null) {
      await user.updateAddress(CustomerAddressUpdate(addressId: _baseAddressId!, addressLine1: line, city: city, pinCode: pin, latitude: _baseLat, longitude: _baseLng));
    } else {
      final before = (await user.getAllAddresses(limit: 50)).data.map((a) => a.addressId).toSet();
      await user.createAddress(CustomerAddressCreate(addressLine1: line, city: city, pinCode: pin, latitude: _baseLat, longitude: _baseLng));
      final created = (await user.getAllAddresses(limit: 50)).data.where((a) => !before.contains(a.addressId)).toList();
      if (created.isEmpty) throw Exception('Could Not Save Your Address. Please Try Again.');
      final newId = created.last.addressId;
      try {
        await ServiceLocator.artistService.updateProfile(ArtistProfileUpdate(baseAddressId: newId));
        _baseAddressId = newId;
      } catch (_) {
        // The new address could not be linked to the profile — remove it so no unused address is left behind.
        // API: userService.deleteAddress → DELETE /users/address/delete/
        try {
          await user.deleteAddress(newId);
        } catch (_) {}
        rethrow;
      }
    }
    _serverAddress = line;
    _serverPin = pin;
    _geoDirty = false;
  }

  /// Choose the address on Google Maps: fills address, pincode and city and keeps the exact latitude / longitude.
  Future<void> _pickOnGoogle() async {
    final place = await showGooglePlacePicker(context, title: 'Search Your Address');
    if (place == null || !mounted) return;
    setState(() {
      _baseLat = place.lat;
      _baseLng = place.lng;
      _geoDirty = true;
      _addressCtrl.text = place.addressLine;
      if (place.pincode.isNotEmpty) _pinCtrl.text = place.pincode;
      if (place.city.isNotEmpty) {
        _selectedCity = place.city;
        _cityKey++;
      }
      _errors.remove('address');
      _errors.remove('pin');
    });
  }

  /// Saves everything.
  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_validate()) {
      setState(() => _error = 'Please Fix The Highlighted Fields.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final dob = parseDob(_dobCtrl.text)!;
      final iso = '${dob.year.toString().padLeft(4, '0')}-${dob.month.toString().padLeft(2, '0')}-${dob.day.toString().padLeft(2, '0')}';
      final brand = _brandCtrl.text.trim();
      await Future.wait([
        // API call: PUT /artists/profile/update/
        ServiceLocator.artistService.updateProfile(ArtistProfileUpdate(
          bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
          city: _selectedCity,
          yearsExperience: experienceYearsFromLabel(_experience!), // older app versions; the range below wins
          experienceRange: experienceRangeKeyFromLabel(_experience),
          dateOfBirth: iso,
          profileTypes: _profileTypes.isEmpty ? null : _profileTypes.map((t) => t.name).toList(), // one or both
          displayName: _brandLocked ? null : brand,
          instagramUrl: _instaCtrl.text.trim().isEmpty ? null : _instaCtrl.text.trim(),
        )),
      ]);
      // API call: PUT /artists/profile/photo/upload/ — only when a photo was changed.
      if (_newPhotoPath != null || _newCoverPath != null) {
        await ServiceLocator.artistBusiness.uploadProfilePhotos(
          profilePhoto: _newPhotoPath != null ? XFile(_newPhotoPath!) : null,
          coverPhoto: _newCoverPath != null ? XFile(_newCoverPath!) : null,
        );
      }
      await _saveBaseAddress();
      final extra = _existingExtra.copyWith(
        dob: dob,
        displayName: brand,
        professionalName: brand,
        address: _addressCtrl.text.trim().isEmpty ? _existingExtra.address : _addressCtrl.text.trim(),
        pincode: _pinCtrl.text.trim().isEmpty ? _existingExtra.pincode : _pinCtrl.text.trim(),
        profilePhotoPath: _newPhotoPath ?? _existingExtra.profilePhotoPath,
        profileTypes: _profileTypes.toList(),
      );
      await extra.save();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = AppFeedback.friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AiraColors.bg,
      body: SunndariBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SunndariAppBar(onBack: () => Navigator.of(context).pop()),
              ),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  children: [
                    const SunndariPageHeading(title: 'Edit Profile', subtitle: 'Keep Your Details Up To Date.'),
                    const SizedBox(height: 16),
                    _photoHeader(),
                    const SizedBox(height: 14),
                    if (_loadingAccount)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose)),
                      ),

                    _section(Icons.storefront_outlined, 'Brand', [
                      SunndariField(
                        label: 'Brand Name',
                        controller: _brandCtrl,
                        hint: 'Enter Your Brand Name',
                        helper: _brandLocked
                            ? 'Your Brand Name Cannot Be Changed. Contact Support To Correct It.'
                            : 'This Is The Name Clients See On Sunndari. It Cannot Be Changed Later.',
                        capitalization: TextCapitalization.words,
                        maxLength: 100,
                        readOnly: _brandLocked,
                        suffix: _brandLocked
                            ? const Padding(
                                padding: EdgeInsets.only(right: 12),
                                child: Icon(Icons.lock_outline_rounded, size: 18, color: AiraColors.charcoalSoft),
                              )
                            : null,
                        serifLabel: false,
                        errorText: _errors['brand'],
                        onChanged: (_) => setState(() => _errors.remove('brand')),
                      ),
                      SunndariField(
                        label: 'About You',
                        optionalTag: 'Optional',
                        controller: _bioCtrl,
                        hint: 'Tell Clients About Your Experience And Makeup Style.',
                        maxLines: 4,
                        maxLength: 500,
                        serifLabel: false,
                      ),
                    ]),

                    _section(Icons.person_outline_rounded, 'Personal Details', [
                      SunndariField(
                        label: 'Artist Name',
                        controller: _nameCtrl,
                        readOnly: true,
                        serifLabel: false,
                        suffix: const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: Icon(Icons.lock_outline_rounded, size: 18, color: AiraColors.charcoalSoft),
                        ),
                        helper: 'Your Name Cannot Be Changed. Contact Support To Correct It.',
                      ),
                      _emailRow(),
                      _phoneRow(),
                      SunndariField(
                        label: 'Date Of Birth',
                        controller: _dobCtrl,
                        hint: 'DD/MM/YYYY',
                        keyboardType: TextInputType.number,
                        formatters: const [DobInputFormatter()],
                        serifLabel: false,
                        errorText: _errors['dob'],
                        onChanged: (_) => setState(() => _errors.remove('dob')),
                        suffix: IconButton(
                          icon: const Icon(Icons.calendar_today_outlined, size: 20, color: AiraColors.roseDeep),
                          onPressed: () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: parseDob(_dobCtrl.text) ?? DateTime(now.year - 25, now.month, now.day),
                              firstDate: DateTime(now.year - 80),
                              lastDate: DateTime(now.year - 18, now.month, now.day),
                              builder: (ctx, child) => Theme(
                                data: Theme.of(ctx).copyWith(
                                  colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AiraColors.rose),
                                ),
                                child: child!,
                              ),
                            );
                            if (picked != null) {
                              setState(() {
                                _dobCtrl.text = formatDob(picked);
                                _errors.remove('dob');
                              });
                            }
                          },
                        ),
                      ),
                    ]),

                    _section(Icons.workspace_premium_outlined, 'Professional Details', [
                      _label('I Am A (You Can Select Both)'),
                      Row(children: [
                        for (final type in ArtistProfileType.values) ...[
                          Expanded(child: _typeTile(type)),
                          if (type != ArtistProfileType.values.last) const SizedBox(width: 10),
                        ],
                      ]),
                      if (_errors['type'] != null) _inlineError(_errors['type']!),
                      const SizedBox(height: 16),
                      _label('Experience'),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final e in kExperienceRanges)
                          _chip(e, _experience == e, () => setState(() {
                                _experience = e;
                                _errors.remove('exp');
                              })),
                      ]),
                      if (_errors['exp'] != null) _inlineError(_errors['exp']!),
                      const SizedBox(height: 16),
                      if (_specialities.isNotEmpty) ...[
                        _label('Specialities'),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final sp in _specialities)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(color: AiraColors.blush, borderRadius: BorderRadius.circular(999)),
                              child: Text(sp, style: AiraText.sans(fontSize: 12, fontWeight: FontWeight.w600, color: AiraColors.roseDeep)),
                            ),
                        ]),
                        const SizedBox(height: 16),
                      ],
                      SunndariField(
                        label: 'Instagram Profile Link',
                        optionalTag: 'Optional',
                        controller: _instaCtrl,
                        hint: 'https://instagram.com/yourhandle',
                        keyboardType: TextInputType.url,
                        serifLabel: false,
                        errorText: _errors['insta'],
                        onChanged: (_) => setState(() => _errors.remove('insta')),
                      ),
                      CityAutocompleteField(key: ValueKey(_cityKey), label: 'City', initialValue: _selectedCity, onChanged: (v) => setState(() => _selectedCity = v)),
                    ]),

                    _section(Icons.location_on_outlined, 'Location', [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: OutlinedButton.icon(
                          onPressed: _pickOnGoogle,
                          icon: Icon((_baseLat != null && _baseLng != null) ? Icons.check_circle_rounded : Icons.map_outlined, size: 18),
                          label: Text((_baseLat != null && _baseLng != null) ? 'Location Pinned — Change On Google Maps' : 'Choose Address On Google Maps'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AiraColors.roseDeep,
                            side: const BorderSide(color: AiraColors.hair),
                            minimumSize: const Size(double.infinity, 46),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      SunndariField(
                        label: 'Address',
                        controller: _addressCtrl,
                        hint: 'House / Flat No., Street, Area',
                        maxLines: 2,
                        capitalization: TextCapitalization.words,
                        serifLabel: false,
                        errorText: _errors['address'],
                        onChanged: (_) => setState(() => _errors.remove('address')),
                      ),
                      SunndariField(
                        label: 'Pincode',
                        controller: _pinCtrl,
                        hint: 'Enter 6-digit Pincode',
                        keyboardType: TextInputType.number,
                        formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                        serifLabel: false,
                        errorText: _errors['pin'],
                        onChanged: (_) => setState(() => _errors.remove('pin')),
                      ),
                    ]),
                  ],
                ),
              ),
              // Sticky save bar
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                decoration: BoxDecoration(
                  color: AiraColors.bg,
                  border: const Border(top: BorderSide(color: AiraColors.hair)),
                  boxShadow: [BoxShadow(color: AiraColors.rose.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, -4))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error != null) ...[
                      Row(children: [
                        const Icon(Icons.info_outline_rounded, size: 16, color: AiraColors.errorText),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!, style: AiraText.sans(fontSize: 12.5, color: AiraColors.errorText))),
                      ]),
                      const SizedBox(height: 10),
                    ],
                    PrimaryButton(label: _saving ? 'Saving…' : 'Save Changes', expand: true, onTap: _saving ? null : _save),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inlineError(String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text, style: AiraText.sans(fontSize: 11.5, color: AiraColors.errorText)),
      );

  Widget _typeTile(ArtistProfileType type) {
    final selected = _profileTypes.contains(type);
    return GestureDetector(
      onTap: () => setState(() {
        selected ? _profileTypes.remove(type) : _profileTypes.add(type);
        _errors.remove('type');
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected ? AiraGradients.aira : null,
          color: selected ? null : AiraColors.pinkFill,
          borderRadius: BorderRadius.circular(12),
          border: selected ? null : Border.all(color: AiraColors.pinkBorder, width: 1.1),
        ),
        child: Text(type.label,
            textAlign: TextAlign.center,
            style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? Colors.white : AiraColors.charcoal)),
      ),
    );
  }
}
