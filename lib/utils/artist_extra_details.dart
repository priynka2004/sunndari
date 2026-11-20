// FILE: utils/artist_extra_details.dart
// Extra artist details stored on device only (address, DOB, profile type, payout method).

import 'dart:convert';
import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_session.dart';

/// Enum: Artist Profile Type values.
enum ArtistProfileType {
  freelance('Freelance Artist'),
  studio('Studio / Salon');

  final String label;
  const ArtistProfileType(this.label);
}

/// Enum: Payout Method values.
enum PayoutMethod { upi, bank }

/// Artist Extra Details.
class ArtistExtraDetails {
  final String? aadharNumber;
  final DateTime? dob;
  final String? address;
  final String? pincode;
  final String? displayName;
  final String? professionalName;
  final List<ArtistProfileType> profileTypes;
  final PayoutMethod payoutMethod;
  final String? upiId;
  final Map<String, List<String>> serviceStyles;
  final String? profilePhotoPath;
  final Map<String, String> serviceDescriptions;
  final List<String> specialities;

  const ArtistExtraDetails({
    this.aadharNumber,
    this.dob,
    this.address,
    this.pincode,
    this.displayName,
    this.professionalName,
    this.profileTypes = const [],
    this.payoutMethod = PayoutMethod.upi,
    this.upiId,
    this.serviceStyles = const {},
    this.profilePhotoPath,
    this.serviceDescriptions = const {},
    this.specialities = const [],
  });

  /// Profile type.
  ArtistProfileType? get profileType => profileTypes.isEmpty ? null : profileTypes.first;

  /// Returns a copy with some fields changed.
  ArtistExtraDetails copyWith({
    String? aadharNumber,
    DateTime? dob,
    String? address,
    String? pincode,
    String? displayName,
    String? professionalName,
    List<ArtistProfileType>? profileTypes,
    PayoutMethod? payoutMethod,
    String? upiId,
    Map<String, List<String>>? serviceStyles,
    String? profilePhotoPath,
    Map<String, String>? serviceDescriptions,
    List<String>? specialities,
  }) {
    return ArtistExtraDetails(
      aadharNumber: aadharNumber ?? this.aadharNumber,
      dob: dob ?? this.dob,
      address: address ?? this.address,
      pincode: pincode ?? this.pincode,
      displayName: displayName ?? this.displayName,
      professionalName: professionalName ?? this.professionalName,
      profileTypes: profileTypes ?? this.profileTypes,
      payoutMethod: payoutMethod ?? this.payoutMethod,
      upiId: upiId ?? this.upiId,
      serviceStyles: serviceStyles ?? this.serviceStyles,
      profilePhotoPath: profilePhotoPath ?? this.profilePhotoPath,
      serviceDescriptions: serviceDescriptions ?? this.serviceDescriptions,
      specialities: specialities ?? this.specialities,
    );
  }

  /// Returns true if details complete.
  bool get isDetailsComplete => dob != null;

  /// Converts this object to JSON for the API.
  Map<String, dynamic> toJson() => {
        'aadharNumber': aadharNumber,
        'dob': dob?.toIso8601String(),
        'address': address,
        'pincode': pincode,
        'displayName': displayName,
        'professionalName': professionalName,
        'profileTypes': profileTypes.map((e) => e.name).toList(),
        'profileType': profileType?.name,
        'payoutMethod': payoutMethod.name,
        'upiId': upiId,
        'serviceStyles': serviceStyles,
        'profilePhotoPath': profilePhotoPath,
        'serviceDescriptions': serviceDescriptions,
        'specialities': specialities,
      };

  /// Builds this object from API JSON.
  factory ArtistExtraDetails.fromJson(Map<String, dynamic> j) {
    return ArtistExtraDetails(
      aadharNumber: j['aadharNumber'] as String?,
      dob: j['dob'] != null ? DateTime.tryParse(j['dob'] as String) : null,
      address: j['address'] as String?,
      pincode: j['pincode'] as String?,
      displayName: j['displayName'] as String?,
      professionalName: j['professionalName'] as String?,
      profileTypes: _readProfileTypes(j),
      payoutMethod: PayoutMethod.values
          .where((e) => e.name == j['payoutMethod'])
          .cast<PayoutMethod?>()
          .firstWhere((e) => e != null, orElse: () => null) ??
          PayoutMethod.upi,
      upiId: j['upiId'] as String?,
      serviceStyles: (j['serviceStyles'] is Map)
          ? (j['serviceStyles'] as Map).map(
              (k, v) => MapEntry(k.toString(), (v as List).map((e) => e.toString()).toList()))
          : const {},
      profilePhotoPath: j['profilePhotoPath'] as String?,
      serviceDescriptions: (j['serviceDescriptions'] is Map)
          ? (j['serviceDescriptions'] as Map)
              .map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {},
      specialities: (j['specialities'] is List)
          ? (j['specialities'] as List).map((e) => e.toString()).toList()
          : const [],
    );
  }

  /// Reads profile types.
  static List<ArtistProfileType> _readProfileTypes(Map<String, dynamic> j) {
    final names = <String>[];
    if (j['profileTypes'] is List) {
      names.addAll((j['profileTypes'] as List).map((e) => e.toString()));
    } else if (j['profileType'] is String) {
      names.add(j['profileType'] as String);
    }
    return [
      for (final t in ArtistProfileType.values)
        if (names.contains(t.name)) t,
    ];
  }

  static String get _key =>
      'artist_extra_details_${AppSession.instance.userId ?? 0}';

  /// Loads this screen's data.
  static Future<ArtistExtraDetails> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null || raw.isEmpty) return const ArtistExtraDetails();
      return ArtistExtraDetails.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const ArtistExtraDetails();
    }
  }

  /// Saves the entered data.
  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(toJson()));
  }

  /// Lets the user pick and save profile photo.
  static Future<String?> pickAndSaveProfilePhoto({required ImageSource source}) async {
    try {
      // The original photo is kept — the server shrinks it when it is uploaded.
      final picked = await ImagePicker().pickImage(source: source);
      if (picked == null) return null;
      final dir = await getApplicationDocumentsDirectory();
      final ext = picked.path.split('.').last;
      final uid = AppSession.instance.userId ?? 0;
      // A NEW file name every time — a fixed name makes Flutter keep showing the previous picture.
      final savedPath = '${dir.path}/profile_photo_${uid}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await File(picked.path).copy(savedPath);
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      return savedPath;
    } catch (_) {
      return null;
    }
  }

  /// Clears profile photo.
  Future<ArtistExtraDetails> clearProfilePhoto() async {
    if (profilePhotoPath != null) {
      try {
        final f = File(profilePhotoPath!);
        if (await f.exists()) await f.delete();
      } catch (_) {
      }
    }
    final updated = ArtistExtraDetails(
      aadharNumber: aadharNumber,
      dob: dob,
      address: address,
      pincode: pincode,
      displayName: displayName,
      professionalName: professionalName,
      profileTypes: profileTypes,
      payoutMethod: payoutMethod,
      upiId: upiId,
      serviceStyles: serviceStyles,
      profilePhotoPath: null,
      serviceDescriptions: serviceDescriptions,
      specialities: specialities,
    );
    await updated.save();
    return updated;
  }
}
