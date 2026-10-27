// FILE: screens/public_artist_profile_screen.dart
// SCREEN: Public Artist Profile — opened from a shared link (sunndari://app/profile?slug=...).
// Same look as PublicProfilePreviewScreen, but the data comes from the PUBLIC API by slug,
// so it shows the artist whose link was shared (not the logged-in artist).
//
// API used:
//   GET /public/artists/get/?slug=<publicSlug>   (no login needed)

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api/api_endpoints.dart';
import '../theme/tokens.dart';
import '../utils/artist_page_data.dart';
import '../utils/experience.dart';
import '../utils/media_url.dart';
import '../widgets/common.dart';

/// Package as returned by the public API.
class _PubPackage {
  final int packageId;
  final String name;
  final double price;
  final int durationMinutes;
  final String makeupType;
  final List<String> brands;
  final String? photoUrl;
  final List<String> inclusions;

  const _PubPackage({
    required this.packageId,
    required this.name,
    required this.price,
    required this.durationMinutes,
    this.makeupType = '',
    this.brands = const [],
    this.photoUrl,
    this.inclusions = const [],
  });

  factory _PubPackage.fromJson(Map<String, dynamic> j) => _PubPackage(
        packageId: (j['packageId'] as num?)?.toInt() ?? 0,
        name: '${j['name'] ?? ''}',
        price: double.tryParse('${j['price']}') ?? 0,
        durationMinutes: (j['durationMinutes'] as num?)?.toInt() ?? 0,
        makeupType: '${j['makeupType'] ?? ''}',
        brands: ((j['brands'] as List?) ?? const []).map((e) => '$e').toList(),
        photoUrl: j['photoUrl']?.toString(),
        inclusions: ((j['inclusions'] as List?) ?? const [])
            .map((e) => e is Map ? '${e['inclusionText'] ?? e['text'] ?? ''}' : '$e')
            .where((e) => e.trim().isNotEmpty)
            .toList(),
      );
}

/// Portfolio photo as returned by the public API.
class _PubPhoto {
  final String fileUrl;
  final String? caption;
  final String? category; // service / category name when the API sends one
  const _PubPhoto(this.fileUrl, this.caption, [this.category]);

  /// Label shown on the photo: category name, else caption.
  String get label => ((category ?? '').trim().isNotEmpty ? category! : (caption ?? '')).trim();
}

/// SCREEN: Public Artist Profile (opened from a shared link).
class PublicArtistProfileScreen extends StatefulWidget {
  final String slug;
  const PublicArtistProfileScreen({super.key, required this.slug});

  @override
  State<PublicArtistProfileScreen> createState() => _PublicArtistProfileScreenState();
}

class _PublicArtistProfileScreenState extends State<PublicArtistProfileScreen> {
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  int _tab = 0;
  bool _loading = true;
  String? _error;

  String _name = '';
  String _bio = '';
  String _city = '';
  int _years = 0;
  bool _accepting = true;
  String? _profilePhotoUrl;
  String? _coverPhotoUrl;
  List<String> _specialities = [];
  List<String> _areas = [];
  List<_PubPackage> _packages = [];
  List<_PubPhoto> _photos = [];

  // Not in the public API yet — shown only if the backend starts sending them.
  String? _venueLabel;
  String? _travelLabel;
  List<String> _workingDays = [];

  int? _selectedPackage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// API: GET /public/artists/get/?slug=<slug>
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse('${ApiEndpoints.baseUrl}${ApiEndpoints.publicArtistGet}')
          .replace(queryParameters: {'slug': widget.slug});
      final r = await http.get(uri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
      final body = jsonDecode(r.body);
      if (r.statusCode != 200 || body is! Map || body['status'] == false || body['data'] is! Map) {
        throw Exception(body is Map && body['message'] != null ? '${body['message']}' : 'Profile Not Found');
      }
      final d = Map<String, dynamic>.from(body['data'] as Map);

      _name = '${d['displayName'] ?? ''}'.trim();
      _bio = '${d['bio'] ?? ''}'.trim();
      _city = '${d['city'] ?? ''}'.trim();
      _years = (d['yearsExperience'] as num?)?.toInt() ?? 0;
      _accepting = d['isAcceptingBookings'] != false;
      _profilePhotoUrl = d['profilePhotoUrl']?.toString();
      _coverPhotoUrl = d['coverPhotoUrl']?.toString();
      _specialities = ((d['specialities'] as List?) ?? const []).map((e) => e is Map ? '${e['name'] ?? ''}' : '$e').where((e) => e.isNotEmpty).toList();
      _areas = ((d['serviceAreas'] as List?) ?? const []).map((e) => '$e').where((e) => e.isNotEmpty).toList();
      _packages = ((d['packages'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => _PubPackage.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _photos = ((d['portfolio'] as List?) ?? const [])
          .whereType<Map>()
          .where((e) => (e['mediaType'] ?? 'image') == 'image' && e['fileUrl'] != null)
          .map((e) => _PubPhoto(
                '${e['fileUrl']}',
                e['caption']?.toString(),
                (e['subCategoryName'] ?? e['serviceName'] ?? e['categoryName'])?.toString(),
              ))
          .toList();

      // Optional fields (only if the backend adds them later).
      final venue = d['serviceMode'] ?? d['workLocation'] ?? d['venueLabel'];
      _venueLabel = venue == null ? null : '$venue';
      final travel = d['travelCharge'] ?? d['travelCharges'];
      _travelLabel = travel == null ? null : (double.tryParse('$travel') == 0 ? 'Free' : (double.tryParse('$travel') != null ? '₹${double.parse('$travel').toStringAsFixed(0)} ${'${d['travelChargeType'] ?? ''}'.toLowerCase().contains('km') ? 'per km' : 'per visit'}' : '$travel'));
      final days = d['workingDays'];
      if (days is List) {
        _workingDays = days.map((e) => e is num ? _dayNames[e.toInt().clamp(0, 6)] : '$e').toList();
      }
    } catch (e) {
      debugPrint('Public profile error = $e');
      _error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _loading = false);
  }

  String get _displayName => _name.isNotEmpty ? _name : 'Sunndari Artist';
  String get _cityLine => _areas.isNotEmpty ? _areas.first : _city;

  ImageProvider? _net(String? url) {
    final u = resolveMediaUrl(url);
    return u != null ? NetworkImage(u) : null;
  }

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

  _PubPackage? get _selected {
    final m = _packages.where((p) => p.packageId == _selectedPackage);
    return m.isNotEmpty ? m.first : null;
  }

  void _openAddOns() {
    final pkg = _selected;
    if (pkg == null) {
      _toast('Select A Package First To See Its Add-Ons');
      return;
    }
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
            Text('Optional Add-Ons', style: AiraText.serif(fontSize: 22, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
            Text('For ${pkg.name}', style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No Add-Ons For This Package.', style: AiraText.sans(color: AiraColors.charcoalSoft))),
            ),
            const SizedBox(height: 8),
            PrimaryButton(label: 'Done', expand: true, onTap: () => Navigator.of(ctx).pop()),
          ],
        ),
      ),
    );
  }

  void _checkAvailability() {
    final pkg = _selected;
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
                      child: Text('${pkg.name}\n${formatDuration(pkg.durationMinutes)}',
                          style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w600, color: AiraColors.roseDeep, height: 1.35)),
                    ),
                    Text('₹${pkg.price.toStringAsFixed(0)}',
                        style: AiraText.sans(fontSize: 17, fontWeight: FontWeight.w800, color: AiraColors.charcoal)),
                  ],
                ),
              ),
            if (_workingDays.isEmpty)
              Text('Working Hours Have Not Been Set Yet.', style: AiraText.sans(color: AiraColors.charcoalSoft))
            else
              Text('Working Days: ${_workingDays.join(', ')}', style: AiraText.sans(fontSize: 13.5)),
            const SizedBox(height: 10),
            if (_travelLabel != null && _travelLabel != 'Free')
              Text('Travel Charge: $_travelLabel', style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
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

  void _viewPhoto(_PubPhoto p) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(16), child: InteractiveViewer(child: _netImage(p.fileUrl, fit: BoxFit.contain))),
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

  Widget _header() {
    final cover = _net(_coverPhotoUrl);
    final photo = _net(_profilePhotoUrl);
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
                SunndariBackChip(onTap: () => Navigator.of(context).maybePop()),
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

  Widget _identity() => Padding(
        padding: const EdgeInsets.fromLTRB(120, 10, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_displayName, style: AiraText.serif(fontSize: 21, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
            const SizedBox(height: 4),
            Row(
              children: [
                if (_cityLine.isNotEmpty) ...[
                  const Icon(Icons.location_on_outlined, size: 15, color: AiraColors.rose),
                  const SizedBox(width: 2),
                  Flexible(child: Text(_cityLine, style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoal))),
                  const SizedBox(width: 8),
                ],
                if (_accepting)
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

  Widget _about0() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_bio.isNotEmpty) Text(_bio, maxLines: 3, overflow: TextOverflow.ellipsis, style: AiraText.sans(fontSize: 13, color: AiraColors.charcoal, height: 1.4)),
            if (_venueLabel != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.home_outlined, size: 16, color: AiraColors.rose),
                  const SizedBox(width: 6),
                  Text(_venueLabel!, style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
                ],
              ),
            ],
          ],
        ),
      );

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

  Widget _packageCard(_PubPackage p) {
    final selected = _selectedPackage == p.packageId;
    final photo = _net(p.photoUrl);
    final typeLine = [
      if (p.makeupType.isNotEmpty) p.makeupType,
      formatDuration(p.durationMinutes),
    ].join(' • ');
    final includes = p.inclusions.join(', ');
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
                if (p.brands.isNotEmpty)
                  Text('Brands: ${p.brands.join(' • ')}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _selectedPackage = selected ? null : p.packageId),
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

  Widget _servicesTab() {
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
                        Text(_selected == null ? 'Select A Package To Explore Extras' : 'No Extras For This Package',
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
                    if (first[i].label.isNotEmpty) _catLabel(first[i].label),
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

  String get _areasText => _areas.isEmpty ? (_city.isEmpty ? 'Not Set Yet' : _city) : _areas.join(', ');

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
                      '$_areasText${(_travelLabel != null && _travelLabel != 'Free') ? ' • Travel charges shown before booking' : ''}',
                      style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft, height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      );

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
                  if (p.label.isNotEmpty) _catLabel(p.label),
                ]),
              ),
            ),
        ],
      ),
    );
  }

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_bio.isNotEmpty) row(Icons.person_outline_rounded, 'About', _bio),
          if (_years > 0) row(Icons.workspace_premium_outlined, 'Experience', experienceLabelFromYears(_years)),
          if (_specialities.isNotEmpty) row(Icons.brush_outlined, 'Specialities', _specialities.join(', ')),
          if (_venueLabel != null) row(Icons.home_outlined, 'Where I Work', _venueLabel!),
          row(Icons.location_on_outlined, 'Service Areas', _areasText),
          if (_travelLabel != null) row(Icons.payments_outlined, 'Travel Charges', _travelLabel!),
          if (_workingDays.isNotEmpty) row(Icons.calendar_month_outlined, 'Working Days', _workingDays.join(', ')),
        ],
      ),
    );
  }

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
                  content: const Text('This Is How Clients Will See This Page. Booking Is Disabled In The Preview.'),
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

  Widget _errorView() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Align(alignment: Alignment.centerLeft, child: SunndariBackChip(onTap: () => Navigator.of(context).maybePop())),
              const Spacer(),
              const Icon(Icons.person_search_outlined, size: 48, color: AiraColors.rose),
              const SizedBox(height: 12),
              Text(_error ?? 'Profile Not Found', textAlign: TextAlign.center, style: AiraText.sans(fontSize: 14, color: AiraColors.charcoalSoft)),
              const SizedBox(height: 16),
              PrimaryButton(label: 'Try Again', small: true, onTap: _load),
              const Spacer(),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AiraColors.bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose))
          : _error != null
              ? _errorView()
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
                            _identity(),
                            _about0(),
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
