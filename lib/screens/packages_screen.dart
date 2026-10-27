// FILE: screens/packages_screen.dart
// SCREEN: My Packages — list, create, edit, delete packages.
//
// APIs used:
//   GET /artists/packages/get_all/
//   GET /core/service-sub-category/get_all/
//   DELETE /artists/packages/delete/
//   PUT /artists/packages/update/
//   POST /artists/packages/create/

import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../models/artist/package.dart';
import '../models/artist/create_package.dart';
import '../models/artist/update_package.dart';
import '../models/core/service_sub_category.dart';
import '../utils/app_feedback.dart';
import '../utils/service_locator.dart';
import 'onboarding/artist_page_services_steps.dart' show kMakeupTypeCategory, ServicesPricingStep, ServicesPricingStepState;

/// SCREEN: My Packages — list, create, edit, delete packages.
class PackagesScreen extends StatefulWidget {
  final bool embedded;
  const PackagesScreen({super.key, this.embedded = false});

  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

/// State of [PackagesScreen] — holds the screen data and logic.
class _PackagesScreenState extends State<PackagesScreen> {
  bool _loading = true;
  String? _error;
  List<Package> _items = [];
  List<ServiceSubCategory> _subCategories = [];

  bool _isMakeupType(ServiceSubCategory s) =>
      (s.categoryName ?? '').trim().toLowerCase() == kMakeupTypeCategory.toLowerCase();

  /// Real services only ("Makeup Type" entries are not services, so they are left out of the dropdown).
  List<ServiceSubCategory> get _services {
    final only = _subCategories.where((s) => !_isMakeupType(s)).toList();
    return only.isEmpty ? _subCategories : only;
  }


  /// Runs once when the screen opens; starts: _load().
  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads this screen's data.
  /// Uses 2 APIs (see inline notes).
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        // API call: artistService.getAllPackages → GET /artists/packages/get_all/
        ServiceLocator.artistService.getAllPackages(limit: 30),
        // API call: coreService.getAllServiceSubCategories → GET /core/service-sub-category/get_all/
        ServiceLocator.coreService.getAllServiceSubCategories(limit: 100),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0].data as List<Package>;
        _subCategories = results[1].data as List<ServiceSubCategory>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  /// Deletes the item.
  /// API: artistService.deletePackage → DELETE /artists/packages/delete/
  Future<void> _delete(Package p) async {
    if (_items.where((x) => x.isActive).length <= 1 && p.isActive) {
      AppFeedback.showInfo(context, 'You Need At Least One Active Package. Add Another One First, Then Delete This One — Or Edit It.');
      return;
    }
    setState(() => _items = _items.where((x) => x.packageId != p.packageId).toList());
    try {
      // API call: artistService.deletePackage → DELETE /artists/packages/delete/
      await ServiceLocator.artistService.deletePackage(p.packageId);
      if (mounted) AppFeedback.showSuccess(context, 'Package Deleted');
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, e);
      }
      _load();
    }
  }

  /// Add / Edit Service: opens the SAME full Services & Pricing form that is used in onboarding.
  Future<void> _openAddService({Package? editing}) async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _AddServiceScreen(editing: editing)),
    );
    if (!mounted) return;
    await _load(); // also refreshes when the page was closed after "Save & Add Another"
    if (added == true && mounted) AppFeedback.showSuccess(context, 'Services Updated ✓');
  }

  /// Opens form (used for editing an existing package).
  /// Uses 2 APIs (see inline notes).
  Future<void> _openForm({Package? existing}) async {
    if (_subCategories.isEmpty) {
      AppFeedback.showWarning(context, 'Add A Service First, Then Create A Package For It');
      return;
    }
    final isEdit = existing != null;
    // Dropdown items: real services (+ the package's current one, so old packages never break the dropdown).
    final serviceItems = [..._services];
    if (existing != null && !serviceItems.any((x) => x.subCategoryId == existing.subCategoryId)) {
      serviceItems.addAll(_subCategories.where((x) => x.subCategoryId == existing.subCategoryId));
    }
    int subCategoryId = existing != null && serviceItems.any((x) => x.subCategoryId == existing.subCategoryId)
        ? existing.subCategoryId
        : serviceItems.first.subCategoryId;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(text: existing != null ? existing.price.toStringAsFixed(0) : '');
    final durationCtrl = TextEditingController(
      text: existing != null ? existing.durationMinutes.toString() : '',
    );
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    bool isActive = existing?.isActive ?? true;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AiraColors.card,
      isScrollControlled: true,
      useSafeArea: true, // keeps the title below the status bar
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          /// Label above a field (+ optional small helper line below it).
          Widget labeled(String label, Widget child, {String? helper, String? tag}) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(label, style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                    if (tag != null) ...[
                      const SizedBox(width: 6),
                      Text(tag, style: AiraText.sans(fontSize: 11, color: AiraColors.charcoalSoft)),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                child,
                if (helper != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 2),
                    child: Text(helper, style: AiraText.sans(fontSize: 11, color: AiraColors.charcoalSoft)),
                  ),
              ],
            ),
          );

          Widget box(Widget child) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
                color: AiraColors.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: AiraColors.hair)),
            child: child,
          );

          Widget field(String label, String hint, TextEditingController c,
              {TextInputType? type, String? helper, String? tag}) =>
              labeled(
                label,
                box(TextField(
                  controller: c,
                  keyboardType: type,
                  decoration: InputDecoration(border: InputBorder.none, hintText: hint),
                )),
                helper: helper,
                tag: tag,
              );

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // drag handle
                Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  decoration: BoxDecoration(color: AiraColors.hair, borderRadius: BorderRadius.circular(99)),
                ),
                // header: title + close
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 8, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(isEdit ? 'Edit Package' : 'New Package',
                            style: AiraText.serif(fontSize: 20, fontWeight: FontWeight.w700)),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded, color: AiraColors.charcoalSoft),
                      ),
                    ],
                  ),
                ),
                Container(height: 1, color: AiraColors.hair),
                // scrollable fields
                Flexible(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        labeled(
                          'Service',
                          box(DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              isExpanded: true,
                              value: subCategoryId,
                              items: serviceItems
                                  .map((s) => DropdownMenuItem(value: s.subCategoryId, child: Text(s.name)))
                                  .toList(),
                              onChanged: (v) => setSheet(() => subCategoryId = v!),
                            ),
                          )),
                          helper: 'The Occasion Or Look, E.g. Bridal Or Party Makeup',
                        ),
                        field('Package Name', 'e.g. Bridal Glam', nameCtrl),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: field('Price (₹)', 'Enter Price', priceCtrl, type: TextInputType.number)),
                            const SizedBox(width: 12),
                            Expanded(child: field('Duration (Min)', 'e.g. 60', durationCtrl, type: TextInputType.number)),
                          ],
                        ),
                        field('Description', 'Describe This Package', descCtrl, tag: 'Optional'),
                        if (isEdit)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                            decoration: BoxDecoration(
                              color: AiraColors.bg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AiraColors.hair),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Active',
                                          style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                                      Text('Clients Can Book This Package While It Is Active',
                                          style: AiraText.sans(fontSize: 11, color: AiraColors.charcoalSoft)),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: isActive,
                                  activeColor: AiraColors.rose,
                                  onChanged: (v) => setSheet(() => isActive = v),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // fixed bottom button
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
                  decoration: const BoxDecoration(
                    color: AiraColors.card,
                    border: Border(top: BorderSide(color: AiraColors.hair)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: PrimaryButton(
                      label: isEdit ? 'Save Changes' : 'Create Package',
                      expand: true,
                      onTap: () => Navigator.of(ctx).pop(true),
                    ),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );

    if (saved != true) return;
    final price = double.tryParse(priceCtrl.text.trim());
    final duration = int.tryParse(durationCtrl.text.trim());
    if (nameCtrl.text.trim().isEmpty) {
      AppFeedback.showWarning(context, 'Enter A Package Name.');
      return;
    }
    if (price == null || price <= 0) {
      AppFeedback.showWarning(context, 'Enter A Valid Price Greater Than ₹0.');
      return;
    }
    if (duration == null || duration <= 0) {
      AppFeedback.showWarning(context, 'Enter A Valid Duration In Minutes.');
      return;
    }

    try {
      if (isEdit) {
        // API call: artistService.updatePackage → PUT /artists/packages/update/
        await ServiceLocator.artistService.updatePackage(UpdatePackage(
          packageId: existing.packageId,
          subCategoryId: subCategoryId,
          name: nameCtrl.text.trim(),
          price: double.parse(priceCtrl.text.trim()),
          durationMinutes: int.tryParse(durationCtrl.text.trim()) ?? 60,
          description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
          isActive: isActive,
        ));
        await _load();
        if (mounted) AppFeedback.showSuccess(context, 'Package Updated ✓');
      } else {
        // API call: artistService.createPackage → POST /artists/packages/create/
        await ServiceLocator.artistService.createPackage(CreatePackage(
          subCategoryId: subCategoryId,
          name: nameCtrl.text.trim(),
          price: double.parse(priceCtrl.text.trim()),
          durationMinutes: int.tryParse(durationCtrl.text.trim()) ?? 60,
          description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        ));
        await _load();
        if (mounted) AppFeedback.showSuccess(context, 'Package Created ✓');
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, e);
      }
    }
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Row(
            children: [
              if (!widget.embedded) ...[
                SunndariBackChip(onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 12),
              ],
              Expanded(child: Text('Services & Pricing', style: AiraText.serif(fontSize: 19, fontWeight: FontWeight.w600))),
              PrimaryButton(label: 'Add', small: true, icon: Icons.add, onTap: () => _openAddService()),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose))
              : _error != null
              ? AiraErrorState(message: _error!, onRetry: _load)
              : _items.isEmpty
              ? Center(
            child: Text('No Services Yet. Add One So Clients Can Book You.',
                textAlign: TextAlign.center,
                style: AiraText.sans(fontSize: 13.5, color: AiraColors.charcoalSoft)),
          )
              : ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final p = _items[i];
              return AiraCard(
                padding: const EdgeInsets.all(14),
                onTap: () => _openAddService(editing: p),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Text('₹${p.price.toStringAsFixed(0)} · ${p.durationMinutes} min'
                              '${p.isActive ? '' : ' · Inactive'}',
                              style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 16, color: AiraColors.charcoalSoft),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _delete(p),
                      child: const Icon(Icons.delete_outline, size: 18, color: AiraColors.errorText),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
    if (widget.embedded) return content;
    return Scaffold(
      backgroundColor: AiraColors.bg,
      body: SafeArea(child: content),
    );
  }
}

/// Add Service page opened from the admin's "add this special service" notification
/// (service name, makeup types, price, additional services and photos — the normal Add Service form).
class AddServiceFromNotificationScreen extends StatelessWidget {
  final int? subCategoryId;
  final String? serviceName;
  const AddServiceFromNotificationScreen({super.key, this.subCategoryId, this.serviceName});

  @override
  Widget build(BuildContext context) =>
      _AddServiceScreen(presetSubCategoryId: subCategoryId, presetServiceName: serviceName);
}

/// Add Service page — re-uses the onboarding Services & Pricing step as-is.
class _AddServiceScreen extends StatefulWidget {
  final Package? editing; // null → add a new service, otherwise edit this package
  final int? presetSubCategoryId; // opened from the "add this special service" notification
  final String? presetServiceName;
  const _AddServiceScreen({this.editing, this.presetSubCategoryId, this.presetServiceName});

  @override
  State<_AddServiceScreen> createState() => _AddServiceScreenState();
}

class _AddServiceScreenState extends State<_AddServiceScreen> {
  final _stepKey = GlobalKey<ServicesPricingStepState>();
  bool _busy = false;

  /// Saves through the onboarding step (same validation + API calls), then closes the page.
  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await _stepKey.currentState?.save() ?? false;
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AiraColors.bg,
      body: SunndariBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: SunndariFlowBar(title: widget.editing != null ? 'Edit Service' : 'Add Service', onBack: () => Navigator.of(context).pop()),
              ),
              Expanded(child: ServicesPricingStep(
                key: _stepKey,
                editing: widget.editing,
                standalone: true,
                presetSubCategoryId: widget.presetSubCategoryId,
                presetServiceName: widget.presetServiceName,
              )),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: PrimaryButton(
                  label: _busy ? 'Please Wait…' : (widget.editing != null ? 'Save Changes' : 'Save & Finish'),
                  expand: true,
                  onTap: _busy ? null : _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}