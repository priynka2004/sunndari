// FILE: screens/public_profile_preview_screen.dart
// SCREEN: Public Profile Preview — what customers see (services, portfolio, about).
//
// APIs used:
//   GET /artists/profile/get/
//   GET /artists/packages/get_all/
//   GET /artists/portfolio/get_all/
//   GET /artists/availability/schedule/get_all/

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/artist/artist_profile.dart';
import '../models/artist/package.dart';
import '../models/artist/portfolio.dart';
import '../theme/tokens.dart';
import '../utils/app_session.dart';
import '../utils/artist_extra_details.dart';
import '../utils/artist_page_data.dart';
import '../utils/media_url.dart';
import '../utils/service_locator.dart';
import '../utils/experience.dart';
import '../widgets/common.dart';

/// SCREEN: Public Profile Preview — what customers see (services, portfolio, about).
class PublicProfilePreviewScreen extends StatefulWidget {
  final String name;
  final ArtistProfile? profile;

  final bool submittedPreview;
  const PublicProfilePreviewScreen({super.key, required this.name, this.profile, this.submittedPreview = false});

  @override
  State<PublicProfilePreviewScreen> createState() => _PublicProfilePreviewScreenState();
}

/// State of [PublicProfilePreviewScreen] — holds the screen data and logic.
class _PublicProfilePreviewScreenState extends State<PublicProfilePreviewScreen> {
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  int _tab = 0;
  bool _loading = true;
  ArtistExtraDetails _extra = const ArtistExtraDetails();
  ArtistProfile? _profile;
  List<Package> _packages = [];
  List<Portfolio> _photos = [];
  Map<int, String> _subNames = {}; // service (sub-category) id → name, used as the photo category label
  List<AddOn> _addOns = [];
  Map<int, String> _servicePhotos = {};
  ServiceLocationPrefs _loc = const ServiceLocationPrefs();
  List<Map<String, dynamic>> _schedule = [];
  String? _coverPath;

  int? _selectedPackage;
  final Set<int> _selectedAddOns = {};

  /// Runs once when the screen opens; starts: _load().
  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads this screen's data.
  /// Uses 4 APIs (see inline notes).
  Future<void> _load() async {
    try {
      _extra = await ArtistExtraDetails.load();
      _profile = widget.profile;
      try {
        // API call: artistService.getProfile → GET /artists/profile/get/
        // Always ask the server: the profile passed in by the previous screen can be out of date
        // (e.g. photos just changed in Edit Profile). Falls back to the passed-in one if offline.
        _profile = await ServiceLocator.artistService.getProfile();
      } catch (_) {}
      try {
        // API call: artistService.getAllPackages → GET /artists/packages/get_all/
        final r = await ServiceLocator.artistService.getAllPackages(limit: 50);
        _packages = r.data.where((p) => p.isActive).toList();
      } catch (_) {}
      try {
        // API call: artistService.getAllPortfolios → GET /artists/portfolio/get_all/
        final r = await ServiceLocator.artistService.getAllPortfolios(limit: 50);
        final order = await ArtistPageLocal.portfolioOrder();
        // Work samples (photos added during onboarding) are part of the public portfolio too — hiding them made
        // an artist with 6 photos see only 1 here.
        _photos = ArtistPageLocal.applyOrder<Portfolio>(r.data.where((p) => p.isActive).toList(), order, (p) => p.portfolioId);
      } catch (_) {}
      try {
        // API call: coreService.getAllServiceSubCategories → GET /core/service-sub-category/get_all/ (photo category names)
        final r = await ServiceLocator.coreService.getAllServiceSubCategories(limit: 100);
        _subNames = {for (final s in r.data) s.subCategoryId: s.name.trim()};
      } catch (_) {}
      try {
        // API call: artistService.getAllSchedules → GET /artists/availability/schedule/get_all/
        final raw = await ServiceLocator.artistService.getAllSchedules();
        final rows = raw is List ? raw : (raw is Map && raw['data'] is List ? raw['data'] as List : const []);
        _schedule = rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          ..sort((a, b) => ((a['dayOfWeek'] as num?) ?? 0).compareTo((b['dayOfWeek'] as num?) ?? 0));
      } catch (_) {}
      _addOns = await ArtistPageLocal.addOns();
      _servicePhotos = await ArtistPageLocal.servicePhotos();
      _loc = await ArtistPageLocal.location();
      final prefs = await SharedPreferences.getInstance();
      _coverPath = prefs.getString('artist_cover_photo_${AppSession.instance.userId ?? 0}');
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  /// Display name.
  String get _displayName {
    final n = _extra.professionalName ?? _extra.displayName;
    return (n != null && n.trim().isNotEmpty) ? n.trim() : (widget.name.isNotEmpty ? widget.name : 'Your Studio');
  }

  String get _city {
    if (_loc.areas.isNotEmpty) return _loc.areas.first;
    return (_profile?.city ?? '').trim();
  }

  String get _bio => (_profile?.bio ?? '').trim();

  ImageProvider? _file(String? path) =>
      (path != null && path.isNotEmpty && File(path).existsSync()) ? FileImage(File(path)) : null;

  /// Photo from the server if there is one (that is what Edit Profile uploads), otherwise the local copy.
  ImageProvider? _remoteOrFile(String? url, String? localPath) {
    final u = resolveMediaUrl(url);
    return u != null ? NetworkImage(u) : _file(localPath);
  }

  /// UI piece: net image.
  Widget _netImage(String? url, {BoxFit fit = BoxFit.cover}) {
    final u = resolveMediaUrl(url);
    if (u == null) return Container(color: AiraColors.blush, child: const Icon(Icons.image_outlined, color: AiraColors.rose));
    return Image.network(
      u,
      fit: fit,
      errorBuilder: (_, __, ___) => Container(color: AiraColors.blush, child: const Icon(Icons.broken_image_outlined, color: AiraColors.rose)),
      loadingBuilder: (c, child, p) => p == null ? child : Container(color: AiraColors.blush),
    );
  }

  Package? get _selected {
    final m = _packages.where((p) => p.packageId == _selectedPackage);
    return m.isNotEmpty ? m.first : null;
  }

  /// Adds ons for selected.
  List<AddOn> get _addOnsForSelected {
    final p = _selected;
    if (p == null) return const [];
    return _addOns.where((a) => a.packageIds.isEmpty || a.packageIds.contains(p.packageId)).toList();
  }

  String _hhmm(dynamic v) {
    try {
      final p = v.toString().split(':');
      final h = int.parse(p[0]);
      final m = int.parse(p[1]);
      final hh = h % 12 == 0 ? 12 : h % 12;
      return '$hh:${m.toString().padLeft(2, '0')} ${h >= 12 ? 'PM' : 'AM'}';
    } catch (_) {
      return '$v';
    }
  }

  /// Opens add ons.
  void _openAddOns() {
    final pkg = _selected;
    if (pkg == null) {
      _toast('Select A Package First To See Its Add-Ons');
      return;
    }
    final items = _addOnsForSelected;
    showModalBottomSheet(
      context: context,
      backgroundColor: AiraColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Optional Add-Ons', style: AiraText.serif(fontSize: 22, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
              Text('For ${pkg.name}', style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
              const SizedBox(height: 12),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No Add-Ons For This Package.', style: AiraText.sans(color: AiraColors.charcoalSoft))),
                )
              else
                for (var i = 0; i < items.length; i++)
                  InkWell(
                    onTap: () {
                      final key = _addOns.indexOf(items[i]);
                      setState(() => _selectedAddOns.contains(key) ? _selectedAddOns.remove(key) : _selectedAddOns.add(key));
                      setS(() {});
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AiraColors.pinkFill,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: _selectedAddOns.contains(_addOns.indexOf(items[i])) ? AiraColors.rose : AiraColors.pinkBorder),
                      ),
                      child: Row(
                        children: [
                          Icon(
                              _selectedAddOns.contains(_addOns.indexOf(items[i]))
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              color: AiraColors.roseDeep),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(items[i].name,
                                    style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                                if (items[i].description.isNotEmpty)
                                  Text(items[i].description, style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
                                if (items[i].extraMinutes > 0)
                                  Text('+${formatDuration(items[i].extraMinutes)}',
                                      style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
                              ],
                            ),
                          ),
                          Text('+₹${items[i].price.toStringAsFixed(0)}',
                              style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w800, color: AiraColors.charcoal)),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 8),
              PrimaryButton(label: 'Done', expand: true, onTap: () => Navigator.of(ctx).pop()),
            ],
          ),
        ),
      ),
    );
  }

  /// Checks availability.
  void _checkAvailability() {
    final pkg = _selected;
    final addOns = _selectedAddOns.map((i) => _addOns[i]).where((a) => pkg != null && (a.packageIds.isEmpty || a.packageIds.contains(pkg.packageId))).toList();
    final total = (pkg?.price ?? 0) + addOns.fold<double>(0, (s, a) => s + a.price);
    final minutes = (pkg?.durationMinutes ?? 0) + addOns.fold<int>(0, (s, a) => s + a.extraMinutes);

    showModalBottomSheet(
      context: context,
      backgroundColor: AiraColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Availability', style: AiraText.serif(fontSize: 22, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
            const SizedBox(height: 10),
            if (pkg != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: AiraColors.blush, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${pkg.name}${addOns.isEmpty ? '' : ' + ${addOns.length} add-on${addOns.length == 1 ? '' : 's'}'}\n${formatDuration(minutes)}',
                          style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w600, color: AiraColors.roseDeep, height: 1.35)),
                    ),
                    Text('₹${total.toStringAsFixed(0)}',
                        style: AiraText.sans(fontSize: 17, fontWeight: FontWeight.w800, color: AiraColors.charcoal)),
                  ],
                ),
              ),
            if (_schedule.isEmpty)
              Text('Working Hours Have Not Been Set Yet.', style: AiraText.sans(color: AiraColors.charcoalSoft))
            else
              for (final d in _schedule)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 54,
                        child: Text(_dayNames[((d['dayOfWeek'] as num?)?.toInt() ?? 0).clamp(0, 6)],
                            style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                      ),
                      Text('${_hhmm(d['startTime'])} – ${_hhmm(d['endTime'])}', style: AiraText.sans(fontSize: 13.5)),
                    ],
                  ),
                ),
            const SizedBox(height: 10),
            if (!_loc.travelFree && _loc.travelAmount > 0)
              Text('Travel Charge: ₹${_loc.travelAmount.toStringAsFixed(0)} ${_loc.travelUnit.toLowerCase()}',
                  style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
            const SizedBox(height: 14),
            Text('This Is A Preview — Clients Will Pick A Date And Time Here Once Your Page Is Live.',
                style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft, height: 1.4)),
            const SizedBox(height: 14),
            PrimaryButton(label: 'Close', expand: true, onTap: () => Navigator.of(ctx).pop()),
          ],
        ),
      ),
    );
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating, backgroundColor: AiraColors.roseDeep));


  /// Small category label drawn over the bottom of a photo.
  Widget _catLabel(String text) => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          color: Colors.black45,
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AiraText.sans(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
      );

  /// Category of a photo: the service name, else its caption, else empty.
  String _photoCategory(Portfolio p) {
    final n = (_subNames[p.subCategoryId] ?? '').trim();
    return n.isNotEmpty ? n : (p.caption ?? '').trim();
  }

  /// Opens photo.
  void _viewPhoto(Portfolio p) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(16), child: InteractiveViewer(child: _netImage(p.fileUrl, fit: BoxFit.contain))),
            if (_photoCategory(p).isNotEmpty)
              Positioned(
                left: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                  child: Text(_photoCategory(p),
                      style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            Positioned(
              right: 6,
              top: 6,
              child: CircleAvatar(
                backgroundColor: Colors.white,
                child: IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close_rounded, color: AiraColors.roseDeep)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// UI piece: header.
  Widget _header() {
    final cover = _remoteOrFile(_profile?.coverPhotoUrl, _coverPath);
    final photo = _remoteOrFile(_profile?.profilePhotoUrl, _extra.profilePhotoPath);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: 210,
          decoration: BoxDecoration(
            gradient: AiraGradients.avatarOrb,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
            image: cover == null ? null : DecorationImage(image: cover, fit: BoxFit.cover),
          ),
        ),
        Container(
          height: 210,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white.withOpacity(0.6), Colors.transparent],
              stops: const [0, 0.5],
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SunndariBackChip(onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 10),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.92), borderRadius: BorderRadius.circular(999)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.visibility_outlined, size: 14, color: AiraColors.roseDeep),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(widget.submittedPreview ? 'Preview · Submitted Profile' : 'Preview · How Clients See You',
                            overflow: TextOverflow.ellipsis,
                            style: AiraText.sans(fontSize: 11.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 16,
          bottom: -44,
          child: Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AiraColors.blush,
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: [BoxShadow(color: AiraColors.rose.withOpacity(0.20), blurRadius: 16, offset: const Offset(0, 6))],
              image: photo == null ? null : DecorationImage(image: photo, fit: BoxFit.cover),
            ),
            child: photo != null ? null : const Icon(Icons.person_outline_rounded, size: 40, color: AiraColors.rose),
          ),
        ),
      ],
    );
  }

  /// UI piece: identity.
  Widget _identity() => Padding(
    padding: const EdgeInsets.fromLTRB(120, 10, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_displayName, style: AiraText.serif(fontSize: 21, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
        const SizedBox(height: 4),
        Row(
          children: [
            if (_city.isNotEmpty) ...[
              const Icon(Icons.location_on_outlined, size: 15, color: AiraColors.rose),
              const SizedBox(width: 2),
              Flexible(child: Text(_city, style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoal))),
              const SizedBox(width: 8),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFFE3F5EA), borderRadius: BorderRadius.circular(999)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.circle, size: 7, color: AiraColors.success),
                  const SizedBox(width: 4),
                  Text('Available For Bookings', style: AiraText.sans(fontSize: 10, fontWeight: FontWeight.w600, color: AiraColors.charcoal)),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );

  /// UI piece: about0.
  Widget _about0() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_bio.isNotEmpty) Text(_bio, maxLines: 3, overflow: TextOverflow.ellipsis, style: AiraText.sans(fontSize: 13, color: AiraColors.charcoal, height: 1.4)),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(Icons.home_outlined, size: 16, color: AiraColors.rose),
            const SizedBox(width: 6),
            Text(_loc.venueLabel, style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
          ],
        ),
      ],
    ),
  );

  /// UI piece: tab bar.
  Widget _tabBar() {
    const tabs = [('Services', Icons.brush_outlined), ('Portfolio', Icons.photo_library_outlined), ('About', Icons.description_outlined)];
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AiraColors.hair))),
      child: Row(
        children: List.generate(3, (i) {
          final sel = _tab == i;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _tab = i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: sel ? AiraColors.blush : Colors.transparent,
                  border: Border(bottom: BorderSide(color: sel ? AiraColors.rose : Colors.transparent, width: 2.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(tabs[i].$2, size: 17, color: sel ? AiraColors.rose : AiraColors.charcoalSoft),
                    const SizedBox(width: 6),
                    Text(tabs[i].$1,
                        style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: sel ? AiraColors.rose : AiraColors.charcoalSoft)),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// UI piece: package card.
  Widget _packageCard(Package p) {
    final meta = PackageMeta.fromPackage(p);
    final selected = _selectedPackage == p.packageId;
    final photo = (p.photoUrl != null && p.photoUrl!.isNotEmpty)
        ? NetworkImage(p.photoUrl!) as ImageProvider
        : _file(_servicePhotos[p.packageId]);
    final typeLine = [
      if (meta.makeupType.isNotEmpty) meta.makeupType,
      formatDuration(p.durationMinutes),
    ].join(' • ');
    final includes = p.inclusions.map((e) => e.inclusionText).join(', ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? AiraColors.rose : AiraColors.hair, width: selected ? 1.6 : 1),
        boxShadow: [BoxShadow(color: AiraColors.rose.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 88,
              height: 104,
              child: photo != null
                  ? Image(image: photo, fit: BoxFit.cover)
                  : Container(color: AiraColors.blush, child: const Icon(Icons.brush_outlined, size: 30, color: AiraColors.rose)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AiraText.sans(fontSize: 15, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
                Text(typeLine, style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
                const SizedBox(height: 2),
                Text('₹${p.price.toStringAsFixed(0)}', style: AiraText.sans(fontSize: 18, fontWeight: FontWeight.w800, color: AiraColors.charcoal)),
                if (includes.isNotEmpty)
                  Text(includes, maxLines: 2, overflow: TextOverflow.ellipsis, style: AiraText.sans(fontSize: 12, color: AiraColors.charcoal, height: 1.3)),
                if (meta.brands.isNotEmpty)
                  Text('Brands: ${meta.brands.join(' • ')}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() {
              _selectedPackage = selected ? null : p.packageId;
              _selectedAddOns.clear();
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? AiraColors.rose : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AiraColors.rose, width: 1.3),
              ),
              child: Text(selected ? 'Selected' : 'Select',
                  style: AiraText.sans(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : AiraColors.rose)),
            ),
          ),
        ],
      ),
    );
  }

  /// UI piece: services tab.
  Widget _servicesTab() {
    final addOnCount = _addOnsForSelected.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Services & Packages', style: AiraText.serif(fontSize: 19, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
          const SizedBox(height: 10),
          if (_packages.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: Text('No Services Added Yet.', style: AiraText.sans(color: AiraColors.charcoalSoft))),
            )
          else
            for (final p in _packages) _packageCard(p),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _openAddOns,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AiraColors.blush,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AiraColors.pinkBorder),
              ),
              child: Row(
                children: [
                  const SunndariIconBubble(icon: Icons.add_rounded, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Optional Add-Ons', style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
                        Text(
                            _selected == null
                                ? 'Select A Package To Explore Extras'
                                : (addOnCount == 0 ? 'No Extras For This Package' : 'Explore Extras With Your Selected Package'),
                            style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AiraColors.rose),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: Text('Portfolio', style: AiraText.serif(fontSize: 19, fontWeight: FontWeight.w700, color: AiraColors.roseDeep))),
              if (_photos.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _tab = 1),
                  child: Text('View All  ›', style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: AiraColors.rose)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _photoRow(),
          const SizedBox(height: 16),
          _serviceAreaCard(),
        ],
      ),
    );
  }

  /// UI piece: photo row.
  Widget _photoRow() {
    if (_photos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text('Portfolio Photos Will Appear Here.', style: AiraText.sans(color: AiraColors.charcoalSoft)),
      );
    }
    final first = _photos.take(3).toList();
    return Row(
      children: [
        for (var i = 0; i < first.length; i++) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => _viewPhoto(first[i]),
              child: AspectRatio(
                aspectRatio: 0.85,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(fit: StackFit.expand, children: [
                    _netImage(first[i].fileUrl),
                    if (_photoCategory(first[i]).isNotEmpty) _catLabel(_photoCategory(first[i])),
                  ]),
                ),
              ),
            ),
          ),
          if (i != first.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }

  /// UI piece: service area card.
  Widget _serviceAreaCard() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AiraColors.pinkFill, borderRadius: BorderRadius.circular(12), border: Border.all(color: AiraColors.hair)),
    child: Row(
      children: [
        const SunndariIconBubble(icon: Icons.location_on_outlined, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Service Area', style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
              Text(
                  '${_loc.areas.isEmpty ? (_city.isEmpty ? 'Not set yet' : _city) : _loc.areas.join(', ')}'
                      '${_loc.travelFree ? '' : ' • Travel charges shown before booking'}',
                  style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft, height: 1.35)),
            ],
          ),
        ),
      ],
    ),
  );

  /// UI piece: portfolio tab.
  Widget _portfolioTab() {
    if (_photos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: Text('No Photos Yet.', style: AiraText.sans(color: AiraColors.charcoalSoft))),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.85,
        children: [
          for (final p in _photos)
            GestureDetector(
              onTap: () => _viewPhoto(p),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(fit: StackFit.expand, children: [
                  _netImage(p.fileUrl),
                  if (_photoCategory(p).isNotEmpty) _catLabel(_photoCategory(p)),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  /// UI piece: about tab.
  Widget _aboutTab() {
    Widget row(IconData i, String t, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SunndariIconBubble(icon: i, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t, style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
                Text(v, style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w600, color: AiraColors.charcoal, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
    final days = _schedule.isEmpty
        ? 'Not Set Yet'
        : _schedule.map((d) => _dayNames[((d['dayOfWeek'] as num?)?.toInt() ?? 0).clamp(0, 6)]).join(', ');
    final years = _profile?.yearsExperience ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_bio.isNotEmpty) row(Icons.person_outline_rounded, 'About', _bio),
          if (years > 0) row(Icons.workspace_premium_outlined, 'Experience', experienceLabelFromYears(years)),
          if (_extra.specialities.isNotEmpty) row(Icons.brush_outlined, 'Specialities', _extra.specialities.join(', ')),
          row(Icons.home_outlined, 'Where I Work', _loc.venueLabel),
          row(Icons.location_on_outlined, 'Service Areas', _loc.areas.isEmpty ? (_city.isEmpty ? 'Not Set Yet' : _city) : _loc.areas.join(', ')),
          row(Icons.payments_outlined, 'Travel Charges',
              _loc.travelFree ? 'Free' : '₹${_loc.travelAmount.toStringAsFixed(0)} ${_loc.travelUnit.toLowerCase()}'),
          row(Icons.calendar_month_outlined, 'Working Days', days),
        ],
      ),
    );
  }

  /// UI piece: bottom bar.
  Widget _bottomBar() => Container(
    padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, -3))],
    ),
    child: Row(
      children: [
        GestureDetector(
          onTap: () => showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AiraColors.bg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: Text('Preview Only', style: AiraText.serif(fontSize: 19)),
              content: const Text('This Is How Clients Will See Your Page. Booking Is Disabled In The Preview.'),
              actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Got It'))],
            ),
          ),
          child: Row(
            children: [
              Text('Preview Only', style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
              const SizedBox(width: 4),
              const Icon(Icons.info_outline_rounded, size: 16, color: AiraColors.roseDeep),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: PrimaryButton(label: 'Check Availability', icon: Icons.calendar_month_outlined, expand: true, onTap: _checkAvailability),
        ),
      ],
    ),
  );

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AiraColors.bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose))
          : Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              color: AiraColors.rose,
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _header(),
                  Stack(children: [_identity()]),
                  const SizedBox(height: 0),
                  Padding(padding: const EdgeInsets.only(top: 0), child: _about0()),
                  _tabBar(),
                  if (_tab == 0) _servicesTab(),
                  if (_tab == 1) _portfolioTab(),
                  if (_tab == 2) _aboutTab(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }
}