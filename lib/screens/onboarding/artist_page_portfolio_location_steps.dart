// FILE: screens/onboarding/artist_page_portfolio_location_steps.dart
// WIZARD STEPS: Portfolio step and Location step of Build My Artist Page.
//
// APIs used:
//   GET /artists/portfolio/get_all/
//   GET /core/service-sub-category/get_all/
//   POST /artists/portfolio/create/
//   PUT /artists/portfolio/update/
//   DELETE /artists/portfolio/delete/
//   GET /core/location-type/get_all/
//   GET /artists/availability/schedule/get_all/
//   GET /artists/locations/get_all/
//   POST /artists/locations/add/
//   DELETE /artists/locations/remove/
//   DELETE /artists/availability/schedule/remove/
//   POST /artists/availability/schedule/set/
//   PUT /artists/profile/update/            (city, travel_time_before_minutes, return_buffer_minutes)
//   GET/POST/PUT/DELETE /artists/service_areas/*   (travel charge: free | per_visit only)

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/artist/artist_profile_update.dart';
import '../../models/artist/create_portfolio.dart';
import '../../models/artist/portfolio.dart';
import '../../models/artist/update_portfolio.dart';
import '../../models/auth/add_location.dart';
import '../../models/auth/set_schedule.dart';
import '../../models/core/location_type.dart';
import '../../models/core/service_sub_category.dart';
import '../../models/user/customer_address_create.dart';
import '../../models/user/customer_address_update.dart';
import '../../models/enums/media_type_enum.dart';
import '../../theme/tokens.dart';
import '../../utils/api_logger.dart';
import '../../utils/app_feedback.dart';
import '../../utils/artist_page_data.dart';
import '../../utils/indian_cities.dart';
import '../../utils/media_url.dart';
import '../../utils/service_locator.dart';
import '../../widgets/city_autocomplete_field.dart';
import '../../widgets/common.dart';
import '../../widgets/sunndari_sheets.dart';
import 'artist_page_services_steps.dart' show ArtistPageStep;
import '../../widgets/sunndari_time_picker.dart';

/// Backend currently rejects `per_km` ("Per-kilometre travel charges are not available yet; use free or per_visit").
/// Set to true once /artists/service_areas/add/ and /update/ accept per_km.
const bool _kPerKmAvailable = false;

/// UI piece: heading.
Widget _heading(String title, String subtitle, {double size = 32}) => Padding(
  padding: const EdgeInsets.only(bottom: 18),
  child: Center(child: SunndariTitle(title: title, subtitle: subtitle, size: size)),
);

/// UI piece: section.
Widget _section(String t) => Padding(
  padding: const EdgeInsets.only(top: 6, bottom: 8),
  child: Text(t, style: AiraText.serif(fontSize: 18, fontWeight: FontWeight.w700)),
);

/// Portfolio Step widget.
class PortfolioStep extends StatefulWidget {
  const PortfolioStep({super.key});

  @override
  State<PortfolioStep> createState() => PortfolioStepState();
}

/// State of [PortfolioStep] — holds the screen data and logic.
class PortfolioStepState extends State<PortfolioStep> implements ArtistPageStep {
  bool _loading = true;
  bool _uploading = false;
  bool _reorder = false;
  List<Portfolio> _items = [];
  List<ServiceSubCategory> _subs = [];

  /// Runs once when the screen opens; starts: _load().
  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads this screen's data.
  /// Uses 2 APIs (see inline notes).
  Future<void> _load() async {
    try {
      final r = await Future.wait([
        // API call: artistService.getAllPortfolios → GET /artists/portfolio/get_all/
        ServiceLocator.artistService.getAllPortfolios(limit: 50),
        // API call: coreService.getAllServiceSubCategories → GET /core/service-sub-category/get_all/
        ServiceLocator.coreService.getAllServiceSubCategories(limit: 100),
        ArtistPageLocal.portfolioOrder(),
      ]);
      final list = (r[0] as dynamic).data as List<Portfolio>;
      _subs = ((r[1] as dynamic).data as List<ServiceSubCategory>).where((s) => s.isActive).toList();
      _items = ArtistPageLocal.applyOrder<Portfolio>(
        // all active photos/videos are shown here — including the ones added earlier during onboarding (work samples)
        list.where((p) => p.isActive).toList(),
        r[2] as List<int>,
            (p) => p.portfolioId,
      );
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Cat name.
  String _catName(int id) {
    final m = _subs.where((s) => s.subCategoryId == id);
    return m.isNotEmpty ? m.first.name : 'Makeup';
  }

  /// Saves the entered data.
  @override
  Future<bool> save() async {
    if (_uploading) return false;
    if (_items.isEmpty) {
      AppFeedback.showInfo(context, 'Add At Least One Photo To Your Portfolio To Continue');
      return false;
    }
    await ArtistPageLocal.savePortfolioOrder(_items.map((e) => e.portfolioId).toList());
    return true;
  }

  /// Chooses category.
  Future<int?> _chooseCategory() async {
    if (_subs.isEmpty) {
      AppFeedback.showWarning(context, 'Categories Are Not Available Right Now. Please Try Again.');
      return null;
    }
    final names = _subs.map((s) => s.name).toList();
    final v = await showSunndariChoiceSheet(
      context,
      title: 'Choose A Category',
      subtitle: 'Which Kind Of Look Is This?',
      options: names,
    );
    if (v == null) return null;
    return _subs.firstWhere((s) => s.name == v).subCategoryId;
  }

  /// API: artistService.createPortfolio → POST /artists/portfolio/create/
  Future<void> _upload(List<XFile> files, MediaTypeEnum type) async {
    if (files.isEmpty) return;
    final sub = await _chooseCategory();
    if (sub == null) return;
    setState(() => _uploading = true);
    var ok = 0;
    try {
      for (var i = 0; i < files.length; i++) {
        try {
          // API call: artistService.createPortfolio → POST /artists/portfolio/create/
          await ServiceLocator.artistService.createPortfolio(CreatePortfolio(
            mediaType: type,
            subCategoryId: sub,
            file: files[i],
            isWorkSample: true, // photos added here are the artist's work samples (admin review + public)
            caption: '${type == MediaTypeEnum.video ? 'Video' : 'Look'} ${_items.length + i + 1}',
          ));
          ok++;
        } catch (e) {
          if (mounted) AppFeedback.showError(context, e);
        }
      }
      if (ok > 0 && mounted) AppFeedback.showSuccess(context, ok == 1 ? 'Added To Your Portfolio ✓' : '$ok Added To Your Portfolio ✓');
      await _load();
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Adds photos.
  Future<void> _addPhotos() async {
    try {
      final picked = await ImagePicker().pickMultiImage(imageQuality: 85);
      await _upload(picked, MediaTypeEnum.image);
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    }
  }

  /// Adds video.
  Future<void> _addVideo() async {
    try {
      final v = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 2));
      if (v != null) await _upload([v], MediaTypeEnum.video);
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    }
  }

  /// Edit a look: change its name / category, and (new) replace the photo or video itself.
  /// API: artistService.updatePortfolio → PUT /artists/portfolio/update/   (name / category only)
  /// Replacing the file: the API cannot swap a file in place, so the new one is uploaded first and the
  /// old one is removed afterwards (same position in the gallery, nothing is lost if the upload fails).
  Future<void> _edit(Portfolio p) async {
    final c = TextEditingController(text: p.caption ?? '');
    int sub = p.subCategoryId;
    XFile? newFile;
    final isVideo = p.mediaType.toLowerCase().contains('video');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AiraColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(22, 18, 22, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edit Look', style: AiraText.serif(fontSize: 22, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
              const SizedBox(height: 14),
              // Current (or newly chosen) photo with a "Change" button
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 170,
                  width: double.infinity,
                  child: (newFile != null && !isVideo)
                      ? Image.file(File(newFile!.path), fit: BoxFit.cover)
                      : (newFile != null && isVideo)
                      ? Container(
                    color: AiraColors.blush,
                    alignment: Alignment.center,
                    child: const Icon(Icons.check_circle_rounded, size: 44, color: AiraColors.success),
                  )
                      : _thumb(p, h: 170),
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () async {
                  try {
                    final picker = ImagePicker();
                    final x = isVideo
                        ? await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 2))
                        : await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                    if (x != null) setS(() => newFile = x);
                  } catch (e) {
                    if (ctx.mounted) AppFeedback.showError(ctx, e);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: AiraColors.pinkFill,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AiraColors.rose, width: 1.2),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.swap_horiz_rounded, size: 19, color: AiraColors.roseDeep),
                      const SizedBox(width: 8),
                      Text(
                        newFile == null
                            ? (isVideo ? 'Change Video' : 'Change Photo')
                            : 'New ${isVideo ? 'video' : 'photo'} Selected ✓ — Tap To Pick Another',
                        style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w700, color: AiraColors.roseDeep),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SunndariField(label: 'Look Name', controller: c, hint: 'e.g. Classic Bridal', maxLength: 40,
                  capitalization: TextCapitalization.words),
              SunndariSelectField(
                label: 'Category',
                hint: 'Select Category',
                value: _catName(sub),
                onTap: () async {
                  final v = await showSunndariChoiceSheet(ctx,
                      title: 'Choose A Category',
                      subtitle: 'Which Kind Of Look Is This?',
                      options: _subs.map((s) => s.name).toList(),
                      selected: _catName(sub));
                  if (v != null) setS(() => sub = _subs.firstWhere((s) => s.name == v).subCategoryId);
                },
              ),
              PrimaryButton(label: 'Save', expand: true, onTap: () => Navigator.of(ctx).pop(true)),
            ],
          ),
        ),
      ),
    );
    final name = c.text.trim();
    if (saved != true) return;
    if (name.isEmpty) {
      if (mounted) AppFeedback.showInfo(context, 'Give This Look A Name');
      return;
    }
    if (mounted) setState(() => _uploading = true);
    try {
      if (newFile == null) {
        // API call: artistService.updatePortfolio → PUT /artists/portfolio/update/
        await ServiceLocator.artistService.updatePortfolio(
          UpdatePortfolio(portfolioId: p.portfolioId, caption: name, subCategoryId: sub),
        );
      } else {
        final beforeIds = _items.map((e) => e.portfolioId).toList();
        // 1) upload the new file first — if this fails the old one stays untouched
        // API call: artistService.createPortfolio → POST /artists/portfolio/create/
        await ServiceLocator.artistService.createPortfolio(CreatePortfolio(
          mediaType: isVideo ? MediaTypeEnum.video : MediaTypeEnum.image,
          subCategoryId: sub,
          file: newFile!,
          isWorkSample: true,
          caption: name,
        ));
        // 2) find the new item so it can take the old one's place
        // API call: artistService.getAllPortfolios → GET /artists/portfolio/get_all/
        final fresh = (await ServiceLocator.artistService.getAllPortfolios(limit: 50))
            .data
            .where((x) => x.isActive && !beforeIds.contains(x.portfolioId))
            .toList()
          ..sort((a, b) => a.portfolioId.compareTo(b.portfolioId));
        // 3) remove the old file
        try {
          // API call: artistService.deletePortfolio → DELETE /artists/portfolio/delete/
          await ServiceLocator.artistService.deletePortfolio(p.portfolioId);
        } catch (_) {
          if (mounted) AppFeedback.showWarning(context, 'New Photo Added, But The Old One Could Not Be Removed. Please Remove It Manually.');
        }
        if (fresh.isNotEmpty) {
          final order = [for (final id in beforeIds) id == p.portfolioId ? fresh.last.portfolioId : id];
          await ArtistPageLocal.savePortfolioOrder(order);
        }
      }
      if (mounted) AppFeedback.showSuccess(context, newFile == null ? 'Look Updated ✓' : 'Photo Changed ✓');
      await _load();
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Deletes the item.
  /// API: artistService.deletePortfolio → DELETE /artists/portfolio/delete/
  Future<void> _delete(Portfolio p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AiraColors.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Remove This Look?', style: AiraText.serif(fontSize: 19)),
        content: const Text('It Will Be Removed From Your Portfolio.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Remove', style: AiraText.sans(fontWeight: FontWeight.w700, color: AiraColors.errorText)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _items = _items.where((x) => x.portfolioId != p.portfolioId).toList());
    try {
      // API call: artistService.deletePortfolio → DELETE /artists/portfolio/delete/
      await ServiceLocator.artistService.deletePortfolio(p.portfolioId);
      await ArtistPageLocal.savePortfolioOrder(_items.map((e) => e.portfolioId).toList());
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
      _load();
    }
  }

  /// UI piece: thumb.
  Widget _thumb(Portfolio p, {double? h}) {
    final isVideo = p.mediaType.toLowerCase().contains('video');
    final url = resolveMediaUrl(p.fileUrl);
    Widget placeholder(IconData i) => Container(
      color: AiraColors.blush,
      alignment: Alignment.center,
      child: Icon(i, size: 34, color: AiraColors.rose),
    );
    if (isVideo || url == null) return placeholder(isVideo ? Icons.play_circle_outline_rounded : Icons.image_outlined);
    return Image.network(
      url,
      height: h,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => placeholder(Icons.broken_image_outlined),
      loadingBuilder: (c, child, prog) => prog == null ? child : placeholder(Icons.image_outlined),
    );
  }

  /// UI piece: card.
  Widget _card(Portfolio p) => Container(
    decoration: BoxDecoration(
      color: AiraColors.pinkFill,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AiraColors.pinkBorder, width: 1.1),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(onTap: () => _edit(p), child: AspectRatio(aspectRatio: 0.82, child: _thumb(p))),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 2, 6),
          child: Row(
            children: [
              const Icon(Icons.drag_indicator_rounded, size: 16, color: AiraColors.charcoalSoft),
              const SizedBox(width: 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.caption ?? 'My Work',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AiraText.sans(fontSize: 11.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                    Text(_catName(p.subCategoryId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AiraText.sans(fontSize: 10, color: AiraColors.charcoalSoft)),
                  ],
                ),
              ),
              InkWell(
                onTap: () => _edit(p),
                child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.edit_outlined, size: 16, color: AiraColors.roseDeep)),
              ),
              InkWell(
                onTap: () => _delete(p),
                child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.delete_outline_rounded, size: 16, color: AiraColors.rose)),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      children: [
        _heading('Let Your Work Speak', 'Curate The Looks Clients Will See On Your Artist Page.', size: 30),
        Row(
          children: [
            Expanded(child: _bigOutlined('Add Photos', Icons.add_rounded, _uploading ? null : _addPhotos)),
            const SizedBox(width: 12),
            Expanded(child: _bigOutlined('Add Videos', Icons.add_rounded, _uploading ? null : _addVideo)),
          ],
        ),
        if (_uploading)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(minHeight: 3, color: AiraColors.rose, backgroundColor: AiraColors.blush),
          ),
        const SizedBox(height: 18),
        Row(
          children: [
            Text('Your Gallery', style: AiraText.serif(fontSize: 20, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (_items.length > 1)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  if (_reorder) await ArtistPageLocal.savePortfolioOrder(_items.map((e) => e.portfolioId).toList());
                  setState(() => _reorder = !_reorder);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _reorder ? AiraColors.rose : AiraColors.pinkFill,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AiraColors.pinkBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(_reorder ? Icons.check_rounded : Icons.drag_handle_rounded,
                          size: 16, color: _reorder ? Colors.white : AiraColors.roseDeep),
                      const SizedBox(width: 6),
                      Text(_reorder ? 'Done' : 'Reorder',
                          style: AiraText.sans(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _reorder ? Colors.white : AiraColors.roseDeep)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(_items.isEmpty ? 'No Looks Yet — Add Your Best Work Above.' : 'Tap A Look To Change Its Photo, Name Or Category.',
            style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
        const SizedBox(height: 10),
        if (_items.isNotEmpty && !_reorder)
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.68,
            children: [for (final p in _items) _card(p)],
          ),
        if (_items.isNotEmpty && _reorder)
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: (o, n) => setState(() {
              if (n > o) n -= 1;
              final it = _items.removeAt(o);
              _items.insert(n, it);
            }),
            children: [
              for (final p in _items)
                Container(
                  key: ValueKey(p.portfolioId),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AiraColors.pinkFill,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AiraColors.pinkBorder),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 56, height: 56, child: _thumb(p, h: 56))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(p.caption ?? 'My Work',
                            style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                      ),
                      const Icon(Icons.drag_handle_rounded, color: AiraColors.charcoalSoft),
                    ],
                  ),
                ),
            ],
          ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AiraColors.blush,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AiraColors.pinkBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 18, color: AiraColors.rose),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Your Portfolio Will Appear After Your Artist Page Is Approved.',
                    style: AiraText.sans(fontSize: 12, color: AiraColors.roseDeep, height: 1.35)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// UI piece: big outlined.
  Widget _bigOutlined(String label, IconData icon, VoidCallback? onTap) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AiraColors.pinkFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AiraColors.rose, width: 1.2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 19, color: AiraColors.roseDeep),
          const SizedBox(width: 6),
          Text(label, style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
        ],
      ),
    ),
  );
}

/// Location Step widget.
class LocationStep extends StatefulWidget {
  const LocationStep({super.key});

  @override
  State<LocationStep> createState() => LocationStepState();
}

/// State of [LocationStep] — holds the screen data and logic.
class LocationStepState extends State<LocationStep> implements ArtistPageStep {
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  bool _loading = true;
  int _venue = 0;
  final Set<String> _areas = {};
  bool _travelFree = true;
  final _amount = TextEditingController();
  final _addr1 = TextEditingController(); // house / flat no., street (typed by the artist)
  final _pin = TextEditingController(); // base address pincode
  String _baseCity = ''; // filled from the pincode, can be changed with the city dropdown
  String? _area; // area / locality chosen from the pincode's post offices
  List<String> _pinAreas = []; // areas returned for the pincode
  bool _pinLoading = false;
  String? _pinMsg; // helper / problem text under the pincode field
  int? _baseAddressId; // existing base address on the server (update instead of duplicate)
  String _unit = 'Per visit';
  int _travelBefore = 0; // minutes blocked before a home visit (0-240)
  int _returnBuffer = 0; // minutes blocked after a home visit (0-240)
  final Set<int> _days = {0, 1, 2, 3, 4, 5};
  TimeOfDay _from = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _to = const TimeOfDay(hour: 19, minute: 0);
  bool _perDay = false;
  final Map<int, (TimeOfDay, TimeOfDay)> _dayHours = {};
  List<LocationType> _types = [];

  /// Runs once when the screen opens; starts: _load().
  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Frees controllers / listeners when the screen closes.
  @override
  void dispose() {
    _amount.dispose();
    _addr1.dispose();
    _pin.dispose();
    super.dispose();
  }

  TimeOfDay _parse(dynamic v, TimeOfDay fallback) {
    try {
      final p = v.toString().split(':');
      return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
    } catch (_) {
      return fallback;
    }
  }

  /// Loads this screen's data.
  /// Uses 2 APIs (see inline notes).
  Future<void> _load() async {
    try {
      final prefs = await ArtistPageLocal.location();
      _venue = prefs.venue;
      _areas.addAll(prefs.areas);
      _travelFree = prefs.travelFree;
      if (prefs.travelAmount > 0) _amount.text = prefs.travelAmount.toStringAsFixed(0);
      _unit = prefs.travelUnit == 'Per km' ? 'Per km' : 'Per visit';
      try {
        // API call: artistService.getProfile → GET /artists/profile/get/
        final prof = await ServiceLocator.artistService.getProfile();
        _travelBefore = prof.travelTimeBeforeMinutes;
        _returnBuffer = prof.returnBufferMinutes;
        _baseAddressId = prof.baseAddressId;
        if (_baseAddressId != null) {
          // API call: userService.getAllAddresses → GET /users/address/get_all/
          final all = (await ServiceLocator.userService.getAllAddresses(limit: 50)).data;
          final m = all.where((a) => a.addressId == _baseAddressId);
          if (m.isNotEmpty) {
            _addr1.text = m.first.addressLine1;
            _pin.text = m.first.pinCode;
            _baseCity = m.first.city;
          }
        }
      } catch (_) {}
      try {
        // API call: artistBusiness.getServiceAreas → GET /artists/service_areas/get_all/ (server is the source of truth)
        final areas = await ServiceLocator.artistBusiness.getServiceAreas();
        final active = areas.where((a) => a.isActive).toList();
        if (active.isNotEmpty) {
          _areas
            ..clear()
            ..addAll(active.map((a) => a.city));
          final type = active.first.travelChargeType;
          _travelFree = type != 'per_visit' && type != 'per_km';
          if (type == 'per_km') _unit = 'Per km';
          if (type == 'per_visit') _unit = 'Per visit';
          debugPrint('[LocationStep] loaded service area: ${active.first.city} ${active.first.travelChargeType} ${active.first.travelCharge}');
          if (!_travelFree && active.first.travelCharge > 0) {
            _amount.text = active.first.travelCharge.toStringAsFixed(0);
          }
        }
      } catch (_) {}
      try {
        // API call: coreService.getAllLocationTypes → GET /core/location-type/get_all/
        _types = (await ServiceLocator.coreService.getAllLocationTypes(limit: 50)).data.where((t) => t.isActive).toList();
      } catch (_) {}
      try {
        // API call: artistService.getAllSchedules → GET /artists/availability/schedule/get_all/
        final raw = await ServiceLocator.artistService.getAllSchedules();
        final rows = raw is List ? raw : (raw is Map && raw['data'] is List ? raw['data'] as List : const []);
        if (rows.isNotEmpty) {
          _days.clear();
          for (final r in rows) {
            if (r is! Map) continue;
            final d = (r['dayOfWeek'] as num).toInt();
            _days.add(d);
            _dayHours[d] = (_parse(r['startTime'], _from), _parse(r['endTime'], _to));
          }
          final first = _dayHours.values.first;
          _from = first.$1;
          _to = first.$2;
          _perDay = _dayHours.values.any((h) => h.$1 != _from || h.$2 != _to);
        }
      } catch (_) {}
    } catch (_) {}
    if (!_kPerKmAvailable) _unit = 'Per visit'; // an old saved "Per km" is shown / saved as "Per visit"
    if (mounted) setState(() => _loading = false);
  }

  static const _bufferOptions = ['None', '30 min', '1 hr', '1 Hr 30 Min', '2 hr', '3 hr', '4 hr'];
  static const _bufferValues = [0, 30, 60, 90, 120, 180, 240]; // minutes, same order as _bufferOptions

  /// Minutes → label for the buffer pickers (0-240).
  String _bufferLabel(int m) {
    // A value saved earlier that is no longer in the list (e.g. 15 / 45 min) still shows as "<m> min".
    final i = _bufferValues.indexOf(m);
    return i >= 0 ? _bufferOptions[i] : '$m min';
  }

  /// Label → minutes.
  int _bufferMinutes(String label) {
    final i = _bufferOptions.indexOf(label);
    return i >= 0 ? _bufferValues[i] : 0;
  }

  double _mins(TimeOfDay t) => t.hour * 60.0 + t.minute;

  /// Full address line sent to the server: "house / street, area".
  String get _addressLine {
    final house = _addr1.text.trim();
    final area = (_area ?? '').trim();
    final hasArea = area.isNotEmpty && !house.toLowerCase().contains(area.toLowerCase());
    return [house, if (hasArea) area].where((e) => e.isNotEmpty).join(', ');
  }

  /// Called when the pincode changes — at 6 digits the city and areas are filled in automatically.
  void _onPinChanged(String v) {
    final pin = v.trim();
    if (pin.length != 6) {
      if (_pinAreas.isNotEmpty || _pinMsg != null) {
        setState(() {
          _pinAreas = [];
          _area = null;
          _pinMsg = null;
        });
      }
      return;
    }
    _lookupPin(pin);
  }

  /// Looks the pincode up (India Post data) → city + area list. If it fails, the city dropdown is used.
  /// API: GET https://api.postalpincode.in/pincode/<pin>  (third-party, not the Sunndari backend)
  Future<void> _lookupPin(String pin) async {
    setState(() {
      _pinLoading = true;
      _pinMsg = null;
    });
    try {
      final r = await ApiLog.get(Uri.parse('https://api.postalpincode.in/pincode/$pin'), tag: 'HTTP/pincode');
      if (!mounted || _pin.text.trim() != pin) return; // user already typed something else
      final j = jsonDecode(r.body);
      final first = (j is List && j.isNotEmpty && j.first is Map) ? j.first as Map : const {};
      final offices = (first['Status'] == 'Success' && first['PostOffice'] is List)
          ? (first['PostOffice'] as List).whereType<Map>().toList()
          : <Map>[];
      if (offices.isEmpty) {
        setState(() {
          _pinLoading = false;
          _pinAreas = [];
          _area = null;
          _pinMsg = "We Couldn't Find This Pincode. Please Choose Your City Below.";
        });
        return;
      }
      final district = (offices.first['District'] ?? offices.first['Block'] ?? '').toString().trim();
      final areas = offices.map((o) => (o['Name'] ?? '').toString().trim()).where((e) => e.isNotEmpty).toSet().toList();
      setState(() {
        _pinLoading = false;
        if (district.isNotEmpty) _baseCity = district;
        _pinAreas = areas;
        _area = areas.length == 1 ? areas.first : (areas.contains(_area) ? _area : null);
        _pinMsg = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pinLoading = false;
        _pinMsg = "Couldn't Look Up The Pincode. Please Choose Your City Below.";
      });
    }
  }

  /// Validates the input.
  String? _validate() {
    if (_areas.isEmpty) return 'Please Select At Least One City Or Locality.';
    if (!RegExp(r'^\d{6}$').hasMatch(_pin.text.trim())) return 'Please Enter A Valid 6-digit Pincode.';
    if (_baseCity.trim().isEmpty) return 'Please Select Your City.';
    if (_addressLine.length < 3) return 'Please Enter Your Area Or House / Street.';
    if (!_travelFree) {
      final a = double.tryParse(_amount.text.trim());
      if (a == null || a <= 0) return 'Please Enter The Travel Charge Amount.';
    }
    if (_days.isEmpty) return 'Please Select At Least One Working Day.';
    for (final d in _days) {
      final h = _perDay ? (_dayHours[d] ?? (_from, _to)) : (_from, _to);
      if (_mins(h.$2) <= _mins(h.$1)) {
        return 'Closing Time Must Be After Opening Time${_perDay ? ' (${_dayNames[d]})' : ''}';
      }
    }
    return null;
  }

  String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  /// Type ids for.
  List<int> _typeIdsFor(int venue) {
    bool isClient(LocationType t) {
      final n = t.name.toLowerCase();
      return n.contains('client') || n.contains('home') || n.contains('venue') || n.contains('travel');
    }

    bool isStudio(LocationType t) {
      final n = t.name.toLowerCase();
      return n.contains('studio') || n.contains('salon');
    }

    return _types
        .where((t) => venue == 2 ? (isClient(t) || isStudio(t)) : venue == 1 ? isStudio(t) : isClient(t))
        .map((t) => t.locationTypeId)
        .toList();
  }

  /// Saves the entered data.
  /// Uses 7 APIs (see inline notes).
  @override
  Future<bool> save() async {
    final problem = _validate();
    if (problem != null) {
      AppFeedback.showInfo(context, problem);
      return false;
    }
    try {
      final api = ServiceLocator.artistService;

      final want = _typeIdsFor(_venue).toSet();
      try {
        // API call: artistService.getAllLocations → GET /artists/locations/get_all/
        final raw = await api.getAllLocations();
        final rows = raw is List ? raw : (raw is Map && raw['data'] is List ? raw['data'] as List : const []);
        final have = rows.whereType<Map>().map((r) => (r['locationTypeId'] as num).toInt()).toSet();
        for (final id in want.difference(have)) {
          // API call: artistService.addLocation → POST /artists/locations/add/
          await api.addLocation(AddLocation(locationTypeId: id));
        }
        final allKnown = _types.map((t) => t.locationTypeId).toSet();
        for (final id in have.difference(want)) {
          // API call: artistService.removeLocation → DELETE /artists/locations/remove/
          if (allKnown.contains(id)) await api.removeLocation(id);
        }
      } catch (e) {
        rethrow; // a missing location type blocks the "availability" onboarding step — show the error
      }

      final existing = <int>{};
      try {
        // API call: artistService.getAllSchedules → GET /artists/availability/schedule/get_all/
        final raw = await api.getAllSchedules();
        final rows = raw is List ? raw : (raw is Map && raw['data'] is List ? raw['data'] as List : const []);
        existing.addAll(rows.whereType<Map>().map((r) => (r['dayOfWeek'] as num).toInt()));
      } catch (_) {}
      for (final d in existing.difference(_days)) {
        // API call: artistService.removeSchedule → DELETE /artists/availability/schedule/remove/
        await api.removeSchedule(d);
      }
      for (final d in _days) {
        final h = _perDay ? (_dayHours[d] ?? (_from, _to)) : (_from, _to);
        // API call: artistService.setSchedule → POST /artists/availability/schedule/set/
        await api.setSchedule(SetSchedule(dayOfWeek: d, startTime: _hhmm(h.$1), endTime: _hhmm(h.$2)));
      }

      // Base address (onboarding "location" step) → POST/PUT /users/address/*, then linked via base_address_id
      final user = ServiceLocator.userService;
      final baseCity = _baseCity.trim();
      if (_baseAddressId != null) {
        // API call: userService.updateAddress → PUT /users/address/update/
        await user.updateAddress(CustomerAddressUpdate(
          addressId: _baseAddressId!,
          addressLine1: _addressLine,
          city: baseCity,
          pinCode: _pin.text.trim(),
        ));
      } else {
        // API call: userService.getAllAddresses → GET /users/address/get_all/
        final before = (await user.getAllAddresses(limit: 50)).data.map((a) => a.addressId).toSet();
        // API call: userService.createAddress → POST /users/address/create/
        await user.createAddress(CustomerAddressCreate(
          addressLine1: _addressLine,
          city: baseCity,
          pinCode: _pin.text.trim(),
        ));
        final after = (await user.getAllAddresses(limit: 50)).data;
        final created = after.where((a) => !before.contains(a.addressId)).toList();
        if (created.isEmpty) throw Exception('Could Not Save Your Address. Please Try Again.');
        _baseAddressId = created.last.addressId;
      }

      // API call: artistService.updateProfile → PUT /artists/profile/update/
      // profile_type (registrationFields step): Client's venue → freelance, My studio / Both → studio
      await api.updateProfile(ArtistProfileUpdate(
        city: baseCity,
        profileType: _venue == 0 ? 'freelance' : 'studio',
        baseAddressId: _baseAddressId,
        travelTimeBeforeMinutes: _travelBefore,
        returnBufferMinutes: _returnBuffer,
      ));

      // Service areas: make the server list match the cities picked here.
      final biz = ServiceLocator.artistBusiness;
      final chargeType = _travelFree ? 'free' : (_unit == 'Per km' ? 'per_km' : 'per_visit');
      final amount = _travelFree ? 0.0 : (double.tryParse(_amount.text.trim()) ?? 0);
      final wanted = _areas.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      // API call: artistBusiness.getServiceAreas → GET /artists/service_areas/get_all/
      final existingAreas = await biz.getServiceAreas();
      final byCity = {for (final a in existingAreas) a.city.toLowerCase(): a};
      for (final c in wanted) {
        final ex = byCity[c.toLowerCase()];
        try {
          if (ex == null) {
            // API call: artistBusiness.addServiceArea → POST /artists/service_areas/add/
            await biz.addServiceArea(city: c, travelChargeType: chargeType, travelCharge: amount);
          } else if (ex.travelChargeType != chargeType || ex.travelCharge != amount) {
            // API call: artistBusiness.updateServiceArea → PUT /artists/service_areas/update/
            await biz.updateServiceArea(ex.serviceAreaId, travelChargeType: chargeType, travelCharge: amount);
          }
        } catch (_) {
          // The server may not accept "Per km" yet — say so clearly instead of a confusing error.
          if (chargeType == 'per_km') {
            throw Exception('Per km Travel Charge Could Not Be Saved Right Now. Please Choose "Per visit" Or Try Again Later.');
          }
          rethrow;
        }
      }
      final keep = wanted.map((e) => e.toLowerCase()).toSet();
      for (final a in existingAreas) {
        if (!keep.contains(a.city.toLowerCase())) {
          // API call: artistBusiness.removeServiceArea → DELETE /artists/service_areas/remove/
          await biz.removeServiceArea(a.serviceAreaId);
        }
      }
      await ArtistPageLocal.saveLocation(ServiceLocationPrefs(
        venue: _venue,
        areas: _areas.toList(),
        travelFree: _travelFree,
        travelAmount: _travelFree ? 0 : (double.tryParse(_amount.text.trim()) ?? 0),
        travelUnit: _unit,
      ));
      return true;
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
      return false;
    }
  }

  /// Lets the user pick time.
  Future<void> _pickTime(bool from, {int? day}) async {
    final current = day != null ? (from ? (_dayHours[day] ?? (_from, _to)).$1 : (_dayHours[day] ?? (_from, _to)).$2) : (from ? _from : _to);
    final t = await pickSunndariTime(context, initial: current, helpText: from ? 'Start Time' : 'End Time');
    if (t == null) return;
    setState(() {
      if (day != null) {
        final h = _dayHours[day] ?? (_from, _to);
        _dayHours[day] = from ? (t, h.$2) : (h.$1, t);
      } else if (from) {
        _from = t;
      } else {
        _to = t;
      }
    });
  }

  /// UI piece: venue tile.
  Widget _venueTile(int i, IconData icon, String label) {
    final on = _venue == i;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _venue = i),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: on ? AiraColors.blush : AiraColors.pinkFill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? AiraColors.rose : AiraColors.pinkBorder, width: on ? 1.5 : 1.1),
          ),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    Icon(icon, size: 26, color: AiraColors.roseDeep),
                    const SizedBox(height: 4),
                    Text(label,
                        textAlign: TextAlign.center,
                        style: AiraText.sans(fontSize: 12, fontWeight: FontWeight.w600, color: AiraColors.roseDeep)),
                  ],
                ),
              ),
              if (on)
                Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(color: AiraColors.roseDeep, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, size: 11, color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// UI piece: time box.
  Widget _timeBox(String label, TimeOfDay t, VoidCallback onTap) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
        const SizedBox(height: 4),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AiraColors.pinkFill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AiraColors.pinkBorder, width: 1.1),
            ),
            child: Row(
              children: [
                Expanded(child: Text(t.format(context), style: AiraText.sans(fontSize: 13.5))),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AiraColors.roseDeep),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _heading('Where & When\nYou’re Available', 'Set Your Service Areas And Working Hours.', size: 30),
        _section('Where Do You Offer Services?'),
        Row(
          children: [
            _venueTile(0, Icons.home_outlined, 'Client’s Venue'),
            const SizedBox(width: 8),
            _venueTile(1, Icons.storefront_outlined, 'My Studio'),
            const SizedBox(width: 8),
            _venueTile(2, Icons.swap_horiz_rounded, 'Both'),
          ],
        ),
        const SizedBox(height: 16),
        _section('Service Areas'),
        SunndariSelectField(
          label: '',
          leading: Icons.location_on_outlined,
          hint: 'Select Cities / Localities',
          value: _areas.isEmpty ? null : _areas.join(', '),
          helper: 'Add All The Areas You Cover.',
          bottomPadding: false,
          onTap: () async {
            final v = await showSunndariMultiSheet(
              context,
              title: 'Service Areas',
              subtitle: 'Select Every City Or Locality You Cover.',
              items: kIndianCities.map((c) => c.name).toSet().toList(),
              selected: _areas,
              searchHint: 'Search Cities',
              addLabel: 'Other City / Locality',
              addPrompt: 'City Or Locality',
              itemSubtitles: {for (final c in kIndianCities) c.name: c.state},
            );
            if (v != null) {
              setState(() => _areas
                ..clear()
                ..addAll(v));
            }
          },
        ),
        const SizedBox(height: 16),
        _section('Your Base Address'),
        SunndariField(
          label: 'Pincode',
          controller: _pin,
          hint: '6-digit Pincode',
          keyboardType: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          onChanged: _onPinChanged,
          helper: _pinLoading ? 'Finding Your Area…' : (_pinMsg ?? 'Enter Your Pincode — City And Area Fill In Automatically.'),
        ),
        CityAutocompleteField(
          key: ValueKey('base-city-$_baseCity'),
          label: 'City',
          initialValue: _baseCity.isEmpty ? null : _baseCity,
          onChanged: (v) => setState(() => _baseCity = v),
        ),
        if (_pinAreas.isNotEmpty)
          SunndariSelectField(
            label: 'Area / Locality',
            hint: 'Select Your Area',
            value: _area,
            onTap: () async {
              final v = await showSunndariChoiceSheet(context,
                  title: 'Select Your Area',
                  subtitle: 'Areas For Pincode ${_pin.text.trim()}',
                  options: _pinAreas,
                  selected: _area);
              if (v != null) setState(() => _area = v);
            },
          ),
        SunndariField(
          label: 'House / Flat No., Street',
          optionalTag: _pinAreas.isNotEmpty ? 'Optional' : null,
          controller: _addr1,
          hint: 'e.g. 12, Gandhi Road',
          maxLength: 100,
          capitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 16),
        _section('Travel Charges'),
        Row(
          children: [
            Expanded(child: _radio('Free', _travelFree, () => setState(() => _travelFree = true))),
            Expanded(child: _radio('Additional Charge', !_travelFree, () => setState(() => _travelFree = false))),
          ],
        ),
        if (!_travelFree) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: SunndariField(
                  label: '',
                  controller: _amount,
                  hint: 'Enter Amount',
                  keyboardType: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                  prefix: Padding(
                    padding: const EdgeInsets.only(left: 12, right: 4),
                    child: Text('₹', style: AiraText.sans(fontSize: 15, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SunndariSelectField(
                  label: '',
                  hint: 'Per visit',
                  value: _unit,
                  onTap: () async {
                    final v = await showSunndariChoiceSheet(context,
                        title: 'Charge Type', subtitle: 'Choose How Your Travel Is Charged.', options: _kPerKmAvailable ? const ['Per visit', 'Per km'] : const ['Per visit'], selected: _unit, boxed: true);
                    if (v != null) setState(() => _unit = v);
                  },
                ),
              ),
            ],
          ),
          Text('Travel Charges Will Be Shown Separately To Clients.',
              style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
        ],
        const SizedBox(height: 16),
        _section('Travel & Buffer Time'),
        Text('Used For Home Visits. This Time Is Blocked On Your Calendar So Bookings Never Overlap.',
            style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft, height: 1.35)),
        const SizedBox(height: 10),
        SunndariSelectField(
          label: 'Travel Time Before The Appointment',
          hint: 'No Travel Time',
          value: _travelBefore == 0 ? null : _bufferLabel(_travelBefore),
          onTap: () async {
            final v = await showSunndariChoiceSheet(context,
                title: 'Travel Time Before',
                subtitle: 'Time Blocked So You Can Reach The Client.',
                options: _bufferOptions,
                selected: _bufferLabel(_travelBefore),
                boxed: true);
            if (v != null) setState(() => _travelBefore = _bufferMinutes(v));
          },
        ),
        SunndariSelectField(
          label: 'Buffer Time After The Appointment',
          hint: 'No Buffer',
          value: _returnBuffer == 0 ? null : _bufferLabel(_returnBuffer),
          onTap: () async {
            final v = await showSunndariChoiceSheet(context,
                title: 'Buffer After The Appointment',
                subtitle: 'Time Blocked For Your Return Journey Or A Break.',
                options: _bufferOptions,
                selected: _bufferLabel(_returnBuffer),
                boxed: true);
            if (v != null) setState(() => _returnBuffer = _bufferMinutes(v));
          },
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: AiraColors.blush, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            const Icon(Icons.schedule_rounded, size: 16, color: AiraColors.roseDeep),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Calendar Reserved: ${_travelBefore == 0 ? 'no travel' : _bufferLabel(_travelBefore)} Before + Service + '
                    '${_returnBuffer == 0 ? 'no buffer' : _bufferLabel(_returnBuffer)} after.',
                style: AiraText.sans(fontSize: 12, color: AiraColors.roseDeep, height: 1.35),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        _section('Working Days'),
        Row(
          children: [
            for (var d = 0; d < 7; d++) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _days.contains(d) ? _days.remove(d) : _days.add(d)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _days.contains(d) ? AiraColors.roseDeep : AiraColors.pinkFill,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _days.contains(d) ? AiraColors.roseDeep : AiraColors.pinkBorder),
                    ),
                    child: Text(_dayNames[d],
                        style: AiraText.sans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _days.contains(d) ? Colors.white : AiraColors.roseDeep)),
                  ),
                ),
              ),
              if (d != 6) const SizedBox(width: 5),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _section('Working Hours'),
        if (!_perDay)
          Row(
            children: [
              _timeBox('From', _from, () => _pickTime(true)),
              const SizedBox(width: 12),
              _timeBox('To', _to, () => _pickTime(false)),
            ],
          )
        else
          for (final d in (_days.toList()..sort())) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(width: 38, child: Text(_dayNames[d], style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w700, color: AiraColors.roseDeep))),
                  _timeBox('From', (_dayHours[d] ?? (_from, _to)).$1, () => _pickTime(true, day: d)),
                  const SizedBox(width: 10),
                  _timeBox('To', (_dayHours[d] ?? (_from, _to)).$2, () => _pickTime(false, day: d)),
                ],
              ),
            ),
          ],
        const SizedBox(height: 6),
        InkWell(
          onTap: () => setState(() => _perDay = !_perDay),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(_perDay ? Icons.toggle_on_rounded : Icons.access_time_rounded, size: _perDay ? 30 : 18, color: AiraColors.rose),
                const SizedBox(width: 8),
                Text('Set Different Hours By Day',
                    style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: AiraColors.rose)),
              ],
            ),
          ),
        ),
        Text(_perDay ? 'Each Selected Day Has Its Own Hours.' : 'These Hours Apply To The Selected Days.',
            style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
      ],
    );
  }

  /// UI piece: radio.
  Widget _radio(String label, bool on, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(on ? Icons.radio_button_checked : Icons.radio_button_off, size: 22, color: AiraColors.roseDeep),
          const SizedBox(width: 8),
          Text(label, style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w600, color: AiraColors.roseDeep)),
        ],
      ),
    ),
  );
}