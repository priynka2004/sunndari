// FILE: screens/edit_travel_charges_screen.dart
// SCREEN: Profile → My Business → Travel Charges.
// The artist can see the travel charge of every city she travels to, change it (free / per visit) or
// remove the city — no need to ask the admin. Bookings already made keep the travel fee they were created with.
//
// APIs used:
//   GET    /artists/service_areas/get_all/
//   PUT    /artists/service_areas/update/
//   DELETE /artists/service_areas/remove/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/artist/artist_extras.dart';
import '../theme/tokens.dart';
import '../utils/app_feedback.dart';
import '../utils/service_locator.dart';
import '../utils/travel_charge_config.dart';
import '../widgets/city_autocomplete_field.dart';
import '../widgets/common.dart';

/// SCREEN: Travel Charges.
class EditTravelChargesScreen extends StatefulWidget {
  const EditTravelChargesScreen({super.key});

  @override
  State<EditTravelChargesScreen> createState() => _EditTravelChargesScreenState();
}

class _EditTravelChargesScreenState extends State<EditTravelChargesScreen> {
  bool _loading = true;
  String? _error;
  List<ArtistServiceArea> _areas = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ServiceLocator.artistBusiness.getServiceAreas();
      if (mounted) setState(() => _areas = list);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could Not Load Your Travel Charges. Please Try Again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _typeLabel(ArtistServiceArea a) {
    final free = a.freeKm > 0 ? ' · Free Up To ${a.freeKm.toStringAsFixed(a.freeKm % 1 == 0 ? 0 : 1)} Km' : '';
    switch (a.travelChargeType) {
      case 'per_visit':
        return '₹${a.travelCharge.toStringAsFixed(a.travelCharge % 1 == 0 ? 0 : 2)} Per Visit$free';
      case 'per_km':
        return '₹${a.travelCharge.toStringAsFixed(a.travelCharge % 1 == 0 ? 0 : 2)} Per Km$free';
      default:
        return 'Free Travel';
    }
  }

  /// Bottom sheet to change the charge of one city — or, with [area] null, to add a new city.
  Future<void> _edit(ArtistServiceArea? area) async {
    final adding = area == null;
    final charge = area?.travelCharge ?? 0;
    final km = area?.freeKm ?? 0;
    final amountCtrl = TextEditingController(text: charge > 0 ? charge.toStringAsFixed(charge % 1 == 0 ? 0 : 2) : '');
    final freeKmCtrl = TextEditingController(text: km > 0 ? km.toStringAsFixed(km % 1 == 0 ? 0 : 1) : '');
    final currentType = area?.travelChargeType ?? 'free';
    var type = ['free', 'per_visit', if (kPerKmChargeEnabled) 'per_km'].contains(currentType) ? currentType : 'free';
    var cityName = '';
    String? cityErr;
    String? err;
    var saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> save() async {
            double? amt;
            double? freeKm;
            if (adding) {
              final c = cityName.trim();
              if (c.isEmpty) {
                setSheet(() => cityErr = 'Please Select A City.');
                return;
              }
              if (_areas.any((a) => a.city.trim().toLowerCase() == c.toLowerCase())) {
                setSheet(() => cityErr = 'You Have Already Added This City.');
                return;
              }
              setSheet(() => cityErr = null);
            }
            if (type != 'free') {
              final fk = freeKmCtrl.text.trim();
              if (fk.isNotEmpty) {
                freeKm = double.tryParse(fk);
                if (freeKm == null || freeKm < 0 || freeKm > 500) {
                  setSheet(() => err = 'Enter Free Km Between 0 And 500.');
                  return;
                }
              }
              amt = double.tryParse(amountCtrl.text.trim());
              if (amt == null || amt <= 0) {
                setSheet(() => err = 'Enter A Travel Charge Greater Than ₹0.');
                return;
              }
              if (amt > 100000) {
                setSheet(() => err = 'Travel Charge Looks Too High. Please Check The Amount.');
                return;
              }
            }
            setSheet(() {
              err = null;
              saving = true;
            });
            try {
              if (area == null) {
                // API: POST /artists/service_areas/add/ — a new city the artist travels to
                await ServiceLocator.artistBusiness.addServiceArea(
                  city: cityName.trim(),
                  travelChargeType: type,
                  travelCharge: type == 'free' ? 0 : (amt ?? 0),
                );
              } else {
                await ServiceLocator.artistBusiness.updateServiceArea(
                  area.serviceAreaId,
                  travelChargeType: type,
                  travelCharge: amt,
                  freeKm: freeKm,
                );
              }
              if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
              if (mounted) {
                AppFeedback.showSuccess(context, adding ? 'City Added ✓' : 'Travel Charge Updated ✓');
                _load();
              }
            } catch (e) {
              setSheet(() => saving = false);
              if (mounted) {
                AppFeedback.showError(
                  context,
                  e,
                  fallback: (freeKm ?? 0) > 0
                      ? 'Free Km Could Not Be Saved Right Now. Please Remove It Or Try Again Later.'
                      : null,
                );
              }
            }
          }

          Widget chip(String value, String label) => Expanded(
            child: GestureDetector(
              onTap: saving ? null : () => setSheet(() => type = value),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: type == value ? AiraColors.roseDeep : AiraColors.pinkFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: type == value ? AiraColors.roseDeep : AiraColors.pinkBorder),
                ),
                child: Text(label,
                    style: AiraText.sans(
                        fontSize: 12.5, fontWeight: FontWeight.w700, color: type == value ? Colors.white : AiraColors.charcoal)),
              ),
            ),
          );

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              decoration: const BoxDecoration(
                color: AiraColors.bg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(adding ? 'Add A City' : 'Travel Charge · ${area.city}',
                      style: AiraText.serif(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  if (adding) ...[
                    CityAutocompleteField(
                      label: 'City',
                      onChanged: (v) => cityName = v,
                    ),
                    if (cityErr != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(cityErr!, style: AiraText.sans(fontSize: 12.5, color: AiraColors.errorText)),
                      ),
                  ],
                  Row(children: [chip('free', 'Free'), chip('per_visit', 'Per Visit'), if (kPerKmChargeEnabled) chip('per_km', 'Per Km')]),
                  if (type != 'free') ...[
                    const SizedBox(height: 14),
                    SunndariField(
                      label: type == 'per_km' ? 'Rate Per Km (₹)' : 'Charge Per Visit (₹)',
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      formatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,6}(\.\d{0,2})?'))],
                      errorText: err,
                    ),
                    // "Free Travel Up To (Km)" is hidden for now: the server accepts free_km but does not save it,
                    // so the artist would think it worked. Show SunndariField(controller: freeKmCtrl …) again once it is saved.
                  ],
                  const SizedBox(height: 8),
                  if (type == 'per_km') ...[
                    Text('The Distance Between You And The Client Is Worked Out At Booking And Multiplied By This Rate.',
                        style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft, height: 1.4)),
                    const SizedBox(height: 8),
                  ],
                  Text(adding
                      ? 'Clients In This City Will Be Able To Book A Home Visit With You At This Travel Charge.'
                      : 'Bookings Already Made Keep The Travel Fee They Were Created With.',
                      style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft, height: 1.4)),
                  const SizedBox(height: 16),
                  PrimaryButton(label: saving ? 'Saving…' : 'Save', expand: true, onTap: saving ? null : save),
                ],
              ),
            ),
          );
        },
      ),
    );
    // showModalBottomSheet returns as soon as the sheet is popped, while it is still animating closed and its
    // TextFields still use these controllers. Disposing right away throws "used after being disposed".
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      amountCtrl.dispose();
      freeKmCtrl.dispose();
    });
  }

  Future<void> _remove(ArtistServiceArea area) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Remove ${area.city}?'),
        content: const Text('Clients Will No Longer Be Able To Book A Home Visit In This City. Existing Bookings Are Not Affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ServiceLocator.artistBusiness.removeServiceArea(area.serviceAreaId);
      if (mounted) {
        AppFeedback.showSuccess(context, '${area.city} Removed');
        _load();
      }
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AiraColors.bg,
      body: SunndariBackground(
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose))
              : ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              SunndariAppBar(onBack: () => Navigator.of(context).pop()),
              const SunndariPageHeading(
                  title: 'Travel Charges', subtitle: 'See And Change What You Charge For Home Visits In Each City.'),
              const SizedBox(height: 14),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(children: [
                    Text(_error!, textAlign: TextAlign.center, style: AiraText.sans(fontSize: 13.5, color: AiraColors.charcoalSoft)),
                    const SizedBox(height: 12),
                    TextButton(onPressed: _load, child: const Text('Try Again')),
                  ]),
                )
              else if (_areas.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('You Have Not Added Any Travel City Yet. Tap "Add City" Below To Start.',
                      textAlign: TextAlign.center, style: AiraText.sans(fontSize: 13.5, color: AiraColors.charcoalSoft)),
                )
              else
                for (final a in _areas)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
                    decoration: BoxDecoration(
                      color: AiraColors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AiraColors.hair),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.directions_car_outlined, size: 22, color: AiraColors.roseDeep),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.city, style: AiraText.sans(fontSize: 15, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(_typeLabel(a), style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Edit',
                          icon: const Icon(Icons.edit_outlined, size: 20, color: AiraColors.roseDeep),
                          onPressed: () => _edit(a),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AiraColors.charcoalSoft),
                          onPressed: () => _remove(a),
                        ),
                      ],
                    ),
                  ),
              if (_error == null) ...[
                const SizedBox(height: 6),
                PrimaryButton(label: 'Add City', icon: Icons.add_rounded, expand: true, onTap: () => _edit(null)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}