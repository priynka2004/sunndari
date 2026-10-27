// FILE: screens/onboarding/artist_page_services_steps.dart
// WIZARD STEPS: Services & Pricing step and Extra Services (add-ons) step of Build My Artist Page.
//
// APIs used:
//   GET /artists/packages/get_all/
//   GET /core/service-sub-category/get_all/
//   POST /artists/services/add/
//   POST /artists/packages/create/        (makeup_type, brands, product_details are real fields now)
//   PUT  /artists/packages/photo/upload/
//   DELETE /artists/packages/delete/
//   GET /core/brands/get_all/ · POST /artists/brands/request/
//   GET/POST/DELETE /artists/addons/*     (extra services)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/artist/add_service.dart';
import '../../models/artist/artist_extras.dart' show BrandRequest;
import '../../models/artist/create_package.dart';
import '../../models/artist/create_portfolio.dart';
import '../../models/enums/media_type_enum.dart';
import '../../models/artist/package.dart';
import '../../models/artist/update_package.dart';
import '../../models/core/service_sub_category.dart';
import '../../theme/tokens.dart';
import '../../utils/app_feedback.dart';
import '../../utils/artist_page_data.dart';
import '../../utils/service_locator.dart';
import '../../widgets/common.dart';
import '../../widgets/sunndari_sheets.dart';

/// Artist Page Step.
abstract class ArtistPageStep {
  /// Saves the entered data.
  Future<bool> save();
}

/// Backend category that holds the makeup types (Regular / HD / Airbrush ...).
const kMakeupTypeCategory = 'Makeup Type';

/// Shown only while the backend has no brands (GET /core/brands/get_all/ returns an empty list).
const kBrandsIfServerEmpty = [
  'M·A·C',
  'Huda Beauty',
  'NARS',
  'Kryolan',
  'Bobbi Brown',
  'Maybelline New York',
  'L’Oréal Paris',
  'Lakmé',
];

/// Shown only while the backend has no sub-categories under the "Makeup Type" category.
const kMakeupTypesIfServerEmpty = ['Regular Makeup', 'HD Makeup', 'Airbrush Makeup'];

/// UI piece: page heading.
Widget _pageHeading(String title, String subtitle, {double size = 32}) => Padding(
  padding: const EdgeInsets.only(bottom: 18),
  child: Center(child: SunndariTitle(title: title, subtitle: subtitle, size: size)),
);

/// UI piece: outlined action.
Widget _outlinedAction(String label, IconData icon, VoidCallback onTap, {bool expand = true, bool small = false}) {
  final btn = InkWell(
    borderRadius: BorderRadius.circular(small ? 999 : 10),
    onTap: onTap,
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 16 : 12, vertical: small ? 8 : 13),
      decoration: BoxDecoration(
        color: AiraColors.pinkFill,
        borderRadius: BorderRadius.circular(small ? 999 : 10),
        border: Border.all(color: AiraColors.rose, width: 1.2),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: AiraColors.roseDeep),
          const SizedBox(width: 8),
          Text(label, style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
        ],
      ),
    ),
  );
  return btn;
}

/// Services Pricing Step widget.
class ServicesPricingStep extends StatefulWidget {
  /// [editing] → the same full form, pre-filled, saved with PUT /artists/packages/update/.
  /// [standalone] → used on its own page (Profile → Edit & Add Service): no big heading, no "Added Services" list,
  /// no "Add Another Service" button (the page has one Save button).
  final Package? editing;
  final bool standalone;
  /// Opened from the admin's "add this special service" notification: the service is pre-selected
  /// (by id, else by name) when it exists in the server list. Ignored when [editing] is set.
  final int? presetSubCategoryId;
  final String? presetServiceName;
  const ServicesPricingStep({
    super.key,
    this.editing,
    this.standalone = false,
    this.presetSubCategoryId,
    this.presetServiceName,
  });

  @override
  State<ServicesPricingStep> createState() => ServicesPricingStepState();
}

/// State of [ServicesPricingStep] — holds the screen data and logic.
class ServicesPricingStepState extends State<ServicesPricingStep> implements ArtistPageStep {
  final _price = TextEditingController();
  final _included = TextEditingController();
  final _products = TextEditingController();

  String? _category;
  String? _makeupType;
  int? _minutes;
  final Set<String> _brands = {};
  /// Brand choices — loaded from the server (GET /core/brands/get_all/), never hardcoded.
  final List<String> _brandList = [];
  List<BrandRequest> _brandRequests = [];
  bool _loadFailed = false;
  bool _coverRemoved = false; // the current cover photo was removed in this session
  bool _removingCover = false;
  /// Service photos — as many as the artist wants (first one is the cover photo).
  final List<XFile> _photos = [];
  static const _maxPhotos = 10;

  bool _loading = true;
  bool _busy = false;
  bool _active = true; // only used when editing
  bool _savedAny = false; // standalone add page: at least one service was saved with "Save & Add Another"
  List<Package> _added = [];
  List<ServiceSubCategory> _subs = [];
  List<ServiceSubCategory> _makeupTypeSubs = [];

  /// Runs once when the screen opens; starts: _load().
  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Frees controllers / listeners when the screen closes.
  @override
  void dispose() {
    _price.dispose();
    _included.dispose();
    _products.dispose();
    super.dispose();
  }

  /// Loads this screen's data.
  /// Uses 2 APIs (see inline notes).
  Future<void> _load() async {
    try {
      // API call: artistService.getAllPackages → GET /artists/packages/get_all/
      final r = await ServiceLocator.artistService.getAllPackages(limit: 50);
      _added = r.data.where((p) => p.isActive).toList();
    } catch (_) {}
    var allSubRows = <ServiceSubCategory>[];
    try {
      // API call: coreService.getAllServiceSubCategories → GET /core/service-sub-category/get_all/
      // These names fill the "Service" dropdown.
      // The "Makeup Type" category also comes back in this list (HD / Airbrush share names with real services),
      // so it is left out here — otherwise the Service dropdown shows duplicates and _subFor() could pick the wrong id.
      final r = await ServiceLocator.coreService.getAllServiceSubCategories(limit: 100);
      allSubRows = r.data;
      _subs = r.data
          .where((s) => s.isActive && (s.categoryName ?? '').trim().toLowerCase() != kMakeupTypeCategory.toLowerCase())
          .toList();
    } catch (_) {}
    await _ensureEditedSubLoaded();
    try {
      // API call: coreService.getAllServiceSubCategories(categoryName) → GET /core/service-sub-category/get_all/?filter_key=categoryName&filter_value=Makeup Type
      // These names fill the "Makeup Type" dropdown.
      final t = await ServiceLocator.coreService.getAllServiceSubCategories(limit: 50, categoryName: kMakeupTypeCategory);
      _makeupTypeSubs = t.data.where((s) => s.isActive).toList();
    } catch (_) {}
    // The server-side filter can come back empty (category named differently / filter not supported) — then use
    // the rows of the full list that belong to the "Makeup Type" category.
    if (_makeupTypeSubs.isEmpty) {
      _makeupTypeSubs = allSubRows
          .where((s) => s.isActive && (s.categoryName ?? '').trim().toLowerCase() == kMakeupTypeCategory.toLowerCase())
          .toList();
    }
    try {
      // API call: artistBusiness.getBrands → GET /core/brands/get_all/ (suggestions for the picker)
      final b = await ServiceLocator.artistBusiness.getBrands();
      if (b.isNotEmpty) {
        _brandList
          ..clear()
          ..addAll(b.map((e) => e.name).where((e) => e.trim().isNotEmpty));
      }
    } catch (_) {}
    // The backend has no brands yet → show the temporary list so the picker is not empty.
    if (_brandList.isEmpty) _brandList.addAll(kBrandsIfServerEmpty);
    // Brands already chosen for this package stay selectable.
    for (final b in _brands) {
      if (!_brandList.contains(b)) _brandList.add(b);
    }
    await _refreshBrandRequests();
    _prefillForEdit();
    // Without the service list the form cannot be filled — show a Retry instead of an empty dropdown.
    _loadFailed = _subs.isEmpty;
    if (mounted) setState(() => _loading = false);
  }

  /// Edit mode: the package's service may be missing from the list (inactive, or beyond the first page) —
  /// fetch it by id so its name still shows.
  /// API: GET /core/service-sub-category/get/ (+ GET /core/service-category/get/ if the parent name is missing)
  Future<void> _ensureEditedSubLoaded() async {
    final e = widget.editing;
    if (e == null || _subs.any((x) => x.subCategoryId == e.subCategoryId)) return;
    try {
      final sub = await ServiceLocator.coreService.getServiceSubCategory(e.subCategoryId);
      var parent = (sub.categoryName ?? '').trim();
      if (parent.isEmpty) {
        try {
          parent = (await ServiceLocator.coreService.getServiceCategory(sub.categoryId)).name.trim();
        } catch (_) {}
      }
      if (parent.toLowerCase() != kMakeupTypeCategory.toLowerCase()) _subs = [..._subs, sub];
    } catch (_) {}
  }

  /// The artist's own brand requests with their status.
  /// API: artistBusiness.getBrandRequests → GET /artists/brands/requests/get_all/
  Future<void> _refreshBrandRequests() async {
    try {
      final list = await ServiceLocator.artistBusiness.getBrandRequests();
      if (mounted) setState(() => _brandRequests = list);
    } catch (_) {}
  }

  static String _brandStatusLabel(String s) => switch (s.trim().toLowerCase()) {
        'approved' => 'Added',
        'rejected' => 'Not Added',
        _ => 'Waiting For Approval',
      };

  /// Removes the current cover photo of the package being edited.
  /// API: artistBusiness.deletePackagePhoto → DELETE /artists/packages/photo/delete/
  Future<void> _removeCover() async {
    final e = widget.editing;
    if (e == null || _removingCover) return;
    setState(() => _removingCover = true);
    try {
      await ServiceLocator.artistBusiness.deletePackagePhoto(e.packageId);
      try {
        await ArtistPageLocal.saveServicePhoto(e.packageId, ''); // also forget the on-device copy
      } catch (_) {}
      if (!mounted) return;
      setState(() => _coverRemoved = true);
      AppFeedback.showSuccess(context, 'Cover Photo Removed');
    } catch (err) {
      if (mounted) AppFeedback.showError(context, err);
    } finally {
      if (mounted) setState(() => _removingCover = false);
    }
  }

  /// Retry button after a failed load.
  void _retryLoad() {
    setState(() => _loading = true);
    _load();
  }

  /// Add mode opened from a notification: pre-selects the special service (nothing else is filled in).
  void _applyPreset() {
    if (_category != null) return;
    final id = widget.presetSubCategoryId;
    final name = (widget.presetServiceName ?? '').trim().toLowerCase();
    for (final s in _subs) {
      if ((id != null && s.subCategoryId == id) || (name.isNotEmpty && s.name.trim().toLowerCase() == name)) {
        _category = s.name;
        return;
      }
    }
  }

  /// Edit mode: fills the form with the package being edited.
  void _prefillForEdit() {
    final e = widget.editing;
    if (e == null) {
      _applyPreset();
      return;
    }
    if (_category != null) return;
    final match = _subs.where((x) => x.subCategoryId == e.subCategoryId);
    _category = match.isNotEmpty ? match.first.name : e.name;
    _makeupType = (e.makeupType ?? '').isEmpty ? null : e.makeupType;
    _price.text = e.price.toStringAsFixed(0);
    _minutes = e.durationMinutes;
    _included.text = e.inclusions.map((i) => i.inclusionText).join(', ');
    _products.text = e.productDetails ?? '';
    for (final b in e.brands) {
      _brands.add(b);
      if (!_brandList.contains(b)) _brandList.add(b);
    }
    _active = e.isActive;
  }

  /// Service names from the API.
  List<String> get _serviceOptions => _subs.map((s) => s.name).toList();

  /// Makeup types from the API. Only if the backend has no "Makeup Type" sub-categories at all, the dropdown
  /// shows [kMakeupTypesIfServerEmpty] so the screen stays usable (remove once the backend data exists).
  List<String> get _makeupTypeOptions =>
      _makeupTypeSubs.isNotEmpty ? _makeupTypeSubs.map((s) => s.name).toList() : kMakeupTypesIfServerEmpty;

  /// Form empty.
  bool get _formEmpty =>
      _price.text.trim().isEmpty &&
          _included.text.trim().isEmpty &&
          _products.text.trim().isEmpty &&
          _category == null &&
          _makeupType == null &&
          _minutes == null &&
          _brands.isEmpty &&
          _photos.isEmpty;

  /// Validates the input.
  String? _validate() {
    if (_category == null) return 'Please Select A Service.';
    if (_makeupType == null) return 'Please Select A Makeup Type.';
    final price = double.tryParse(_price.text.trim());
    if (price == null || price <= 0) return 'Please Enter A Valid Price.';
    if (price < 500) return 'Price Must Be At Least ₹500.';
    if (price > 500000) return 'Price Looks Too High. Please Check It.';
    if (_minutes == null) return 'Please Select The Service Duration.';
    if (_included.text.trim().isEmpty) return 'Please Enter What Is Included.';
    if (_brands.isEmpty) return 'Please Select At Least One Brand.';
    if (_brands.length > 10) return 'You Can Add Up To 10 Brands Per Package';
    if (_brands.any((b) => b.length > 50)) return 'A Brand Name Can Be At Most 50 Characters';
    if (_makeupType!.length > 50) return 'Makeup Type Can Be At Most 50 Characters';
    return null;
  }

  /// Sub for.
  int? _subFor(String category) {
    if (_subs.isEmpty) return null;
    // Exact name match first (the dropdown is filled from the API names).
    final exact = _subs.where((s) => s.name.trim().toLowerCase() == category.trim().toLowerCase());
    if (exact.isNotEmpty) return exact.first.subCategoryId;
    final key = category.toLowerCase().split(RegExp(r'[ /]')).first;
    final m = _subs.where((s) => s.name.toLowerCase().contains(key));
    // No match → null (never fall back to the first category, that would save the package under the wrong service).
    return m.isNotEmpty ? m.first.subCategoryId : null;
  }

  /// Clears form.
  void _clearForm() {
    _price.clear();
    _included.clear();
    _products.clear();
    _category = null;
    _makeupType = null;
    _minutes = null;
    _brands.clear();
    _photos.clear();
  }

  /// Creates from form.
  /// Uses 3 APIs (see inline notes).
  Future<bool> _createFromForm() async {
    final problem = _validate();
    if (problem != null) {
      AppFeedback.showInfo(context, problem);
      return false;
    }
    final sub = _subFor(_category!);
    if (sub == null) {
      AppFeedback.showWarning(
          context,
          _subs.isEmpty
              ? 'Service Categories Are Not Available Right Now. Please Try Again.'
              : 'This Service Is Not Available Yet. Please Choose One From The List.');
      return false;
    }
    setState(() => _busy = true);
    try {
      try {
        // API call: artistService.addService → POST /artists/services/add/
        await ServiceLocator.artistService.addService(AddService(subCategoryId: sub));
      } catch (_) {}

      final inclusions = _included.text
          .split(RegExp(r'[\n,;]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final name = _category!; // the selected service is the service name
      // API call: artistService.createPackage → POST /artists/packages/create/
      // makeup_type / brands / product_details are first-class fields now (no more hiding them in the description).
      await ServiceLocator.artistService.createPackage(CreatePackage(
        subCategoryId: sub,
        name: name,
        price: double.parse(_price.text.trim()),
        durationMinutes: _minutes!,
        description: _category!,
        inclusions: inclusions,
        makeupType: _makeupType!,
        brands: _brands.toList(),
        productDetails: _products.text.trim(),
      ));

      // API call: artistService.getAllPackages → GET /artists/packages/get_all/
      // The package already exists on the server at this point, so a failed refresh must NOT fail the whole save
      // (the artist would retry and create a duplicate).
      var all = _added;
      var refreshed = false;
      try {
        final res = await ServiceLocator.artistService.getAllPackages(limit: 50);
        all = res.data.where((p) => p.isActive).toList();
        refreshed = true;
      } catch (_) {}
      if (!refreshed && mounted) {
        AppFeedback.showWarning(context, 'Service Saved, But The List Could Not Be Refreshed. Photos Were Not Uploaded — Please Re-Open This Step.');
      }
      if (refreshed && _photos.isNotEmpty) {
        final mine = all.where((p) => p.name == name).toList()..sort((a, b) => b.packageId.compareTo(a.packageId));
        if (mine.isNotEmpty) {
          final pkgId = mine.first.packageId;
          // 1st photo = the package's cover photo.
          try {
            // API call: artistBusiness.uploadPackagePhoto → PUT /artists/packages/photo/upload/ (one cover photo per package)
            await ServiceLocator.artistBusiness.uploadPackagePhoto(pkgId, _photos.first);
            final again = await ServiceLocator.artistService.getAllPackages(limit: 50);
            all = again.data.where((p) => p.isActive).toList();
          } catch (e) {
            // Keep a local copy so the artist still sees it, and tell them the upload failed.
            await ArtistPageLocal.saveServicePhoto(pkgId, _photos.first.path);
            if (mounted) AppFeedback.showWarning(context, 'Service Saved, But The Cover Photo Could Not Be Uploaded: ${e.toString().replaceFirst('Exception: ', '')}');
          }
          // The package API keeps only ONE cover photo, so the other photos are saved to the artist's
          // portfolio under this service, where clients can see them too.
          var failed = 0;
          for (final extra in _photos.skip(1)) {
            try {
              // API call: artistService.createPortfolio → POST /artists/portfolio/create/
              await ServiceLocator.artistService.createPortfolio(CreatePortfolio(
                mediaType: MediaTypeEnum.image,
                subCategoryId: sub,
                file: extra,
                caption: name,
              ));
            } catch (_) {
              failed++;
            }
          }
          if (failed > 0 && mounted) {
            AppFeedback.showWarning(context, '$failed Of ${_photos.length - 1} Extra Photos Could Not Be Uploaded. You Can Add Them Later From Portfolio.');
          }
        }
      }
      if (!mounted) return true;
      setState(() {
        _added = all;
        _clearForm();
      });
      return true;
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Edit mode save: updates the package with every field of the form (+ new photos if picked).
  /// APIs: POST /artists/services/add/ · PUT /artists/packages/update/ · PUT /artists/packages/photo/upload/
  Future<bool> _updateFromForm() async {
    final problem = _validate();
    if (problem != null) {
      AppFeedback.showInfo(context, problem);
      return false;
    }
    final sub = _subFor(_category!);
    if (sub == null) {
      AppFeedback.showWarning(
          context,
          _subs.isEmpty
              ? 'Service Categories Are Not Available Right Now. Please Try Again.'
              : 'This Service Is Not Available Yet. Please Choose One From The List.');
      return false;
    }
    setState(() => _busy = true);
    try {
      try {
        await ServiceLocator.artistService.addService(AddService(subCategoryId: sub));
      } catch (_) {}
      final inclusions = _included.text
          .split(RegExp(r'[\n,;]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final pkgId = widget.editing!.packageId;
      await ServiceLocator.artistService.updatePackage(UpdatePackage(
        packageId: pkgId,
        subCategoryId: sub,
        name: _category!,
        price: double.parse(_price.text.trim()),
        durationMinutes: _minutes!,
        isActive: _active,
        inclusions: inclusions,
        makeupType: _makeupType!,
        brands: _brands.toList(),
        productDetails: _products.text.trim(),
      ));
      if (_photos.isNotEmpty) {
        try {
          await ServiceLocator.artistBusiness.uploadPackagePhoto(pkgId, _photos.first); // new cover photo
        } catch (e) {
          if (mounted) AppFeedback.showWarning(context, 'Saved, But The Cover Photo Could Not Be Uploaded: ${e.toString().replaceFirst('Exception: ', '')}');
        }
        var failed = 0;
        for (final extra in _photos.skip(1)) {
          try {
            await ServiceLocator.artistService.createPortfolio(CreatePortfolio(
              mediaType: MediaTypeEnum.image,
              subCategoryId: sub,
              file: extra,
              caption: _category!,
            ));
          } catch (_) {
            failed++;
          }
        }
        if (failed > 0 && mounted) {
          AppFeedback.showWarning(context, '$failed Of ${_photos.length - 1} Extra Photos Could Not Be Uploaded. You Can Add Them Later From Portfolio.');
        }
      }
      return true;
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Adds another.
  Future<void> _addAnother() async {
    if (_busy) return;
    if (_formEmpty) {
      AppFeedback.showInfo(context, 'Fill In This Service First, Then Add Another');
      return;
    }
    if (await _createFromForm() && mounted) {
      _savedAny = true;
      AppFeedback.showSuccess(context, 'Service Added ✓');
    }
  }

  /// Saves the entered data.
  @override
  Future<bool> save() async {
    if (_busy) return false;
    if (widget.editing != null) return _updateFromForm();
    if (widget.standalone) {
      if (_formEmpty) {
        if (_savedAny) return true; // already saved with "Save & Add Another" → just finish
        AppFeedback.showInfo(context, 'Please Fill In The Service Details First.');
        return false;
      }
      return _createFromForm();
    }
    if (!_formEmpty && !await _createFromForm()) return false;
    if (_added.isEmpty) {
      if (mounted) AppFeedback.showInfo(context, 'Add At Least One Service To Continue');
      return false;
    }
    return true;
  }

  /// Deletes the item.
  /// API: artistService.deletePackage → DELETE /artists/packages/delete/
  Future<void> _delete(Package p) async {
    // Backend rule: an artist must keep at least 1 active package → explain instead of showing a raw error.
    if (_added.length <= 1) {
      AppFeedback.showInfo(context, 'You Need At Least One Service. Add Another Service First, Then Delete This One — Or Edit It.');
      return;
    }
    final before = _added;
    setState(() => _added = _added.where((x) => x.packageId != p.packageId).toList());
    try {
      // API call: artistService.deletePackage → DELETE /artists/packages/delete/
      await ServiceLocator.artistService.deletePackage(p.packageId);
    } catch (e) {
      if (!mounted) return;
      // Put the item back so it doesn't vanish from the screen if the refresh below also fails.
      setState(() => _added = before);
      AppFeedback.showError(context, e);
      _load();
    }
  }

  /// Lets the user pick brands.
  Future<void> _pickBrands() async {
    final v = await showSunndariMultiSheet(
      context,
      title: 'Products & Brands Used',
      subtitle: 'Select All Brands Used In This Package.',
      items: _brandList,
      selected: _brands,
      searchHint: 'Search Brands',
      addLabel: 'Other Brand',
      addPrompt: 'Brand Name',
    );
    if (v == null || !mounted) return;
    for (final b in v) {
      if (!_brandList.contains(b)) {
        // API call: artistBusiness.requestBrand → POST /artists/brands/request/ (max 5 pending; failure is harmless —
        // the brand is still saved on this package as free text)
        ServiceLocator.artistBusiness.requestBrand(b).then((_) => _refreshBrandRequests()).catchError((_) {});
      }
    }
    setState(() {
      for (final b in v) {
        if (!_brandList.contains(b)) _brandList.add(b);
      }
      _brands
        ..clear()
        ..addAll(v);
    });
  }

  /// Lets the user pick photos — several at once, as many as they like (up to [_maxPhotos]).
  Future<void> _pickPhoto() async {
    try {
      final room = _maxPhotos - _photos.length;
      if (room <= 0) {
        AppFeedback.showInfo(context, 'You Can Add Up To $_maxPhotos Photos Per Service');
        return;
      }
      final picked = await ImagePicker().pickMultiImage(imageQuality: 85);
      if (picked.isEmpty) return;
      final added = <XFile>[];
      var tooBig = 0;
      for (final x in picked) {
        if (_photos.any((e) => e.path == x.path)) continue;
        if (await x.length() > 5 * 1024 * 1024) {
          tooBig++;
          continue;
        }
        if (added.length < room) added.add(x);
      }
      if (!mounted) return;
      setState(() => _photos.addAll(added));
      if (tooBig > 0) {
        AppFeedback.showWarning(context, '$tooBig Photo${tooBig == 1 ? '' : 's'} Skipped (Over 5 MB). Please Choose Smaller Photos.');
      } else if (picked.length > room) {
        AppFeedback.showInfo(context, 'Only $_maxPhotos Photos Can Be Added Per Service');
      }
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    }
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (!widget.standalone) _pageHeading('Your Services & Pricing', 'Build Packages That Reflect Your Artistry.', size: 30),
        if (_loadFailed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text('Could Not Load The Services List.',
                      style: AiraText.sans(fontSize: 13, color: AiraColors.errorText)),
                ),
                TextButton(onPressed: _retryLoad, child: const Text('Retry')),
              ],
            ),
          ),
        if (!widget.standalone && _added.isNotEmpty) ...[
          Text('Added Services (${_added.length})', style: AiraText.serif(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final p in _added)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AiraCard(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 20, color: AiraColors.success),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                          Text('₹${p.price.toStringAsFixed(0)} · ${formatDuration(p.durationMinutes)}',
                              style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _delete(p),
                      icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AiraColors.charcoalSoft),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SunndariSelectField(
                label: 'Service',
                hint: 'Select Service',
                value: _category,
                onTap: () async {
                  final v = await showSunndariChoiceSheet(context,
                      title: 'Choose A Service',
                      subtitle: 'Select One For This Service.',
                      options: _serviceOptions,
                      selected: _category,
                      // No "Other / Add Your Own Service" here on purpose: a typed-in name has no service id on the
                      // server (so saving always failed with "not available") and free-text names bring spelling
                      // mistakes. Special-occasion services (Karwa Chauth, Diwali, New Year…) are opened by the admin
                      // from the backend and then simply appear in this list.
                      );
                  if (v != null) setState(() => _category = v);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SunndariSelectField(
                label: 'Makeup Type',
                hint: 'Select Type',
                value: _makeupType,
                onTap: () async {
                  final v = await showSunndariChoiceSheet(context,
                      title: 'Choose Makeup Type',
                      subtitle: 'Select One For This Service.',
                      options: _makeupTypeOptions,
                      selected: _makeupType,
                      otherSubtitle: 'Add Your Own Makeup Type',
                      boxed: true,
                      centeredTitle: true);
                  if (v != null) setState(() => _makeupType = v);
                },
              ),
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SunndariField(
                label: 'Price',
                controller: _price,
                hint: 'Enter Price',
                keyboardType: TextInputType.number,
                formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                prefix: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  child: Text('₹', style: AiraText.sans(fontSize: 15, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SunndariSelectField(
                label: 'Duration',
                hint: 'Select Duration',
                value: _minutes == null ? null : formatDuration(_minutes!),
                onTap: () async {
                  final v = await showSunndariDurationSheet(context, initial: _minutes);
                  if (v != null) setState(() => _minutes = v);
                },
              ),
            ),
          ],
        ),
        SunndariField(
          label: 'What’s Included',
          controller: _included,
          hint: 'List Everything Included In This Package',
          maxLines: 3,
          maxLength: 300,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 8),
          child: Text('Products & Brands Used', style: AiraText.serif(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        SunndariSelectField(
          label: '',
          hint: 'Select Brands',
          value: _brands.isEmpty ? null : _brands.join(', '),
          helper: 'You Can Select Multiple Brands.',
          onTap: _pickBrands,
          bottomPadding: false,
        ),
        if (_brandRequests.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your Brand Requests',
                    style: AiraText.sans(fontSize: 12, fontWeight: FontWeight.w700, color: AiraColors.charcoalSoft)),
                for (final r in _brandRequests.take(5))
                  Text('${r.name} — ${_brandStatusLabel(r.status)}',
                      style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
              ],
            ),
          ),
        const SizedBox(height: 14),
        SunndariField(
          label: 'Product Details',
          optionalTag: 'Optional',
          controller: _products,
          hint: 'e.g. Foundation — Brand; Lipstick — Brand',
          maxLines: 2,
          maxLength: 200,
          serifLabel: false,
        ),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _pickPhoto,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AiraColors.pinkFill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AiraColors.pinkBorder, width: 1.1),
            ),
            child: Row(
              children: [
                const Icon(Icons.add_photo_alternate_outlined, size: 32, color: AiraColors.roseDeep),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Add Service Photos',
                          style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                      Text(
                          _photos.isEmpty
                              ? 'Optional · Select As Many As You Like'
                              : '${_photos.length} Selected · Tap To Add More',
                          style: AiraText.sans(fontSize: 11, color: AiraColors.charcoalSoft)),
                    ],
                  ),
                ),
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(color: AiraColors.rose, shape: BoxShape.circle),
                  child: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        if (_photos.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: _photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(_photos[i].path), width: 72, height: 72, fit: BoxFit.cover),
                  ),
                  if (i == 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          color: AiraColors.roseDeep.withOpacity(0.85),
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                        ),
                        child: Text('Cover',
                            textAlign: TextAlign.center,
                            style: AiraText.sans(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  Positioned(
                    right: -6,
                    top: -6,
                    child: GestureDetector(
                      onTap: () => setState(() => _photos.removeAt(i)),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(color: AiraColors.roseDeep, shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (widget.editing != null) ...[
          if ((widget.editing!.photoUrl ?? '').isNotEmpty && _photos.isEmpty && !_coverRemoved) ...[
            const SizedBox(height: 10),
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(widget.editing!.photoUrl!, width: 56, height: 56, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 56, height: 56)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Current Cover Photo. Add A New Photo To Replace It.',
                    style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
              ),
              TextButton(
                onPressed: _removingCover ? null : _removeCover,
                child: Text(_removingCover ? 'Removing…' : 'Remove',
                    style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w600, color: AiraColors.rose)),
              ),
            ]),
          ],
          const SizedBox(height: 14),
          AiraCard(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Active', style: AiraText.sans(fontSize: 14.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                      Text('Clients Can Book This Package While It Is Active',
                          style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
                    ],
                  ),
                ),
                Switch(
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  thumbColor: const WidgetStatePropertyAll(Colors.white),
                  trackColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected) ? AiraColors.success : null,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (!widget.standalone || widget.editing == null) ...[
          const SizedBox(height: 12),
          _outlinedAction(
              _busy ? 'Saving…' : (widget.standalone ? 'Save & Add Another Service' : 'Add Another Service'),
              Icons.add_rounded,
              _busy ? () {} : _addAnother),
        ],
      ],
    );
  }
}

/// Extra Services Step widget.
class ExtraServicesStep extends StatefulWidget {
  /// [standalone] → used on its own page (Profile → Edit & Add Service → Optional Services): no big heading and
  /// no "Add Another" button (the page has one Save button). Tap an add-on to edit it.
  final bool standalone;
  const ExtraServicesStep({super.key, this.standalone = false});

  @override
  State<ExtraServicesStep> createState() => ExtraServicesStepState();
}

/// State of [ExtraServicesStep] — holds the screen data and logic.
class ExtraServicesStepState extends State<ExtraServicesStep> implements ArtistPageStep {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _desc = TextEditingController();
  int? _extraMinutes;
  final Set<String> _selectedPackages = {};
  int? _editingId; // add-on being edited (null → adding a new one)

  bool _loading = true;
  List<Package> _packages = [];
  List<AddOn> _items = [];

  /// Runs once when the screen opens; starts: _load().
  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Frees controllers / listeners when the screen closes.
  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _desc.dispose();
    super.dispose();
  }

  /// Loads this screen's data.
  /// API: GET /artists/packages/get_all/ · GET /artists/addons/get_all/
  Future<void> _load() async {
    var packagesOk = false;
    try {
      final res = await ServiceLocator.artistService.getAllPackages(limit: 50);
      _packages = res.data.where((p) => p.isActive).toList();
      packagesOk = true;
    } catch (_) {}
    // Separate from the packages call: a failed packages request must not stop the saved add-ons from loading.
    try {
      // ArtistPageLocal.addOns() fetches GET /artists/addons/get_all/ (offline cache on failure).
      final saved = await ArtistPageLocal.addOns();
      final ids = _packages.map((p) => p.packageId).toSet();
      _items = !packagesOk
          ? saved
          : saved.where((a) => a.packageIds.any(ids.contains) || a.packageIds.isEmpty).toList();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  /// Label shown in the packages picker. Two packages with the same name and price would otherwise get the same
  /// label (and be selected together), so those get their id appended to tell them apart.
  String _label(Package p) {
    final base = '${p.name} · ₹${p.price.toStringAsFixed(0)}';
    final clash = _packages.where((x) => x.packageId != p.packageId && '${x.name} · ₹${x.price.toStringAsFixed(0)}' == base).isNotEmpty;
    return clash ? '$base (#${p.packageId})' : base;
  }

  /// Form empty.
  bool get _formEmpty =>
      _name.text.trim().isEmpty && _price.text.trim().isEmpty && _desc.text.trim().isEmpty && _selectedPackages.isEmpty && _extraMinutes == null;

  /// Validates the input.
  String? _validate() {
    if (_name.text.trim().length < 3) return 'Please Enter The Add-On Name.';
    final price = double.tryParse(_price.text.trim());
    if (price == null || price < 1) return 'Please Enter A Valid Price (At Least ₹1).';
    if ((_extraMinutes ?? 0) > 480) return 'Extra Time Can Be At Most 8 Hours';
    if (_selectedPackages.isEmpty) return 'Choose Which Packages Can Offer This Add-On';
    return null;
  }

  /// Adds current.
  Future<bool> _addCurrent() async {
    final problem = _validate();
    if (problem != null) {
      AppFeedback.showInfo(context, problem);
      return false;
    }
    final ids = _packages.where((p) => _selectedPackages.contains(_label(p))).map((p) => p.packageId).toList();
    try {
      if (_editingId != null) {
        // API call: artistBusiness.updateAddOn → PUT /artists/addons/update/ (existing bookings never change)
        await ServiceLocator.artistBusiness.updateAddOn(
          _editingId!,
          name: _name.text.trim(),
          price: double.parse(_price.text.trim()),
          durationMinutes: _extraMinutes ?? 0,
          description: _desc.text.trim(),
          packageIds: ids,
        );
      } else {
        // API call: artistBusiness.createAddOn → POST /artists/addons/create/
        await ServiceLocator.artistBusiness.createAddOn(
          name: _name.text.trim(),
          price: double.parse(_price.text.trim()),
          durationMinutes: _extraMinutes ?? 0,
          description: _desc.text.trim(),
          packageIds: ids,
        );
      }
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
      return false;
    }
    final fresh = await ArtistPageLocal.addOns(); // GET /artists/addons/get_all/
    if (!mounted) return true;
    setState(() {
      _items = fresh;
      _name.clear();
      _price.clear();
      _desc.clear();
      _extraMinutes = null;
      _selectedPackages.clear();
      _editingId = null;
    });
    return true;
  }

  /// Loads an existing add-on into the form so it can be edited.
  /// The latest copy is fetched first (GET /artists/addons/get/); if that fails the list copy is used.
  Future<void> _startEdit(AddOn listed) async {
    var a = listed;
    if (listed.addOnId != null) {
      try {
        // API call: artistBusiness.getAddOn → GET /artists/addons/get/
        final f = await ServiceLocator.artistBusiness.getAddOn(listed.addOnId!);
        a = AddOn(
          addOnId: f.addOnId,
          name: f.name,
          price: f.price,
          extraMinutes: f.durationMinutes,
          description: f.description ?? '',
          packageIds: f.packageIds,
        );
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _editingId = a.addOnId;
      _name.text = a.name;
      _price.text = a.price.toStringAsFixed(0);
      _desc.text = a.description;
      _extraMinutes = a.extraMinutes > 0 ? a.extraMinutes : null;
      _selectedPackages
        ..clear()
        ..addAll(_packages.where((p) => a.packageIds.contains(p.packageId)).map(_label));
    });
  }

  /// Clears the form (cancel editing).
  void _cancelEdit() {
    setState(() {
      _editingId = null;
      _name.clear();
      _price.clear();
      _desc.clear();
      _extraMinutes = null;
      _selectedPackages.clear();
    });
  }

  /// Adds another.
  Future<void> _addAnother() async {
    if (_formEmpty) {
      AppFeedback.showInfo(context, 'Fill In This Add-On First, Then Add Another');
      return;
    }
    if (await _addCurrent() && mounted) AppFeedback.showSuccess(context, 'Add-On Saved ✓');
  }

  /// Saves the entered data.
  @override
  Future<bool> save() async {
    if (_formEmpty) {
      if (widget.standalone && mounted) AppFeedback.showInfo(context, 'Please Fill In The Add-On Details First.');
      return !widget.standalone;
    }
    return _addCurrent();
  }

  /// Removes item.
  /// API: DELETE /artists/addons/delete/ (existing bookings keep their add-ons)
  Future<void> _removeItem(int i) async {
    final item = _items[i];
    final next = [..._items]..removeAt(i);
    setState(() => _items = next);
    try {
      if (item.addOnId != null) {
        // API call: artistBusiness.deleteAddOn → DELETE /artists/addons/delete/
        await ServiceLocator.artistBusiness.deleteAddOn(item.addOnId!);
      }
      await ArtistPageLocal.saveAddOns(next);
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
      _load();
    }
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (!widget.standalone) _pageHeading('A Little Extra,\nYour Way', 'Offer Optional Add-Ons Alongside Your Makeup Packages.'),
        if (_items.isNotEmpty) ...[
          Text('Your Add-Ons (${_items.length})', style: AiraText.serif(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AiraCard(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 20, color: AiraColors.success),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_items[i].name,
                              style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                          Text(
                              '+₹${_items[i].price.toStringAsFixed(0)}'
                                  '${_items[i].extraMinutes > 0 ? ' · +${formatDuration(_items[i].extraMinutes)}' : ''}',
                              style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
                        ],
                      ),
                    ),
                    if (widget.standalone)
                      IconButton(
                        onPressed: () => _startEdit(_items[i]),
                        icon: const Icon(Icons.edit_outlined, size: 20, color: AiraColors.roseDeep),
                      ),
                    IconButton(
                      onPressed: () => _removeItem(i),
                      icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AiraColors.charcoalSoft),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
        Text(_editingId != null ? 'Edit Extra Service' : 'Add An Extra Service',
            style: AiraText.serif(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        SunndariField(
          label: 'Add-On Name',
          controller: _name,
          hint: 'e.g. Saree Draping Or Extra Touch-Up',
          capitalization: TextCapitalization.sentences,
          maxLength: 60,
          serifLabel: false,
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SunndariField(
                label: 'Price',
                controller: _price,
                hint: 'Enter Price',
                keyboardType: TextInputType.number,
                formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                serifLabel: false,
                prefix: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  child: Text('₹', style: AiraText.sans(fontSize: 15, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SunndariSelectField(
                label: 'Extra Duration',
                optionalTag: 'Optional',
                hint: 'Select Time',
                value: _extraMinutes == null ? null : formatDuration(_extraMinutes!),
                onTap: () async {
                  final v = await showSunndariDurationSheet(context, initial: _extraMinutes);
                  if (v != null) setState(() => _extraMinutes = v);
                },
              ),
            ),
          ],
        ),
        SunndariField(
          label: 'Short Description',
          controller: _desc,
          hint: 'Describe What This Add-On Includes',
          maxLines: 3,
          maxLength: 200,
          serifLabel: false,
        ),
        SunndariSelectField(
          label: 'Applicable Packages',
          hint: _packages.isEmpty ? 'Add A Service First' : 'Select Packages',
          value: _selectedPackages.isEmpty ? null : _selectedPackages.join(', '),
          helper: 'Choose Which Packages Can Offer This Add-On.',
          onTap: () async {
            if (_packages.isEmpty) {
              AppFeedback.showInfo(context, 'Add At Least One Service Package First (Previous Step)');
              return;
            }
            final v = await showSunndariMultiSheet(
              context,
              title: 'Applicable Packages',
              subtitle: 'Choose Which Packages Can Offer This Add-On.',
              items: _packages.map(_label).toList(),
              selected: _selectedPackages,
              searchHint: 'Search Packages',
            );
            if (v != null) {
              setState(() => _selectedPackages
                ..clear()
                ..addAll(v));
            }
          },
        ),
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 14),
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
                child: Text('Only Add Extras That Are Not Already Included In The Selected Packages.',
                    style: AiraText.sans(fontSize: 12, color: AiraColors.roseDeep, height: 1.35)),
              ),
            ],
          ),
        ),
        if (_editingId != null)
          _outlinedAction('Cancel Editing', Icons.close_rounded, _cancelEdit)
        else if (!widget.standalone)
          _outlinedAction('Add Another', Icons.add_rounded, _addAnother),
      ],
    );
  }
}