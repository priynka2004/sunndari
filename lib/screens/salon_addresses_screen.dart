// FILE: screens/salon_addresses_screen.dart
// SCREEN: My Salons — the salons / studios the artist works from (Business → Salons).
//
// A customer who books In-Salon picks one of these; the booking then carries that salon with its latitude and
// longitude, and the artist sees the same salon on the booking.
//
// APIs (Salon Addresses API):
//   GET    /artists/salon_addresses/get_all/                 own active salons, oldest first (max 10)
//   POST   /artists/salon_addresses/create/                  name, address_line_1/2, city, pin_code, latitude, longitude
//   PUT    /artists/salon_addresses/update/                  salon_address_id + only the fields that changed
//   DELETE /artists/salon_addresses/delete/?salon_address_id=   switched off, not erased (past bookings keep it)
//
// Rules from the guide: max 10 active salons, a name must be unique among them (the server says so),
// latitude + longitude are required (both 0 is refused), so the map location has to be chosen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../models/artist/salon_address.dart';
import '../theme/tokens.dart';
import '../utils/app_feedback.dart';
import '../utils/service_locator.dart';
import '../widgets/common.dart';
import '../widgets/google_place_picker.dart';

const int kMaxSalonAddresses = 10;

class SalonAddressesScreen extends StatefulWidget {
  /// true when shown as a tab inside Business (no own header / Scaffold).
  final bool embedded;
  const SalonAddressesScreen({super.key, this.embedded = false});

  @override
  State<SalonAddressesScreen> createState() => _SalonAddressesScreenState();
}

class _SalonAddressesScreenState extends State<SalonAddressesScreen> {
  bool _loading = true;
  String? _error;
  List<SalonAddress> _salons = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// API: artistBusiness.getSalonAddresses → GET /artists/salon_addresses/get_all/
  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await ServiceLocator.artistBusiness.getSalonAddresses();
      if (!mounted) return;
      setState(() {
        _salons = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _openForm([SalonAddress? existing]) async {
    if (existing == null && _salons.length >= kMaxSalonAddresses) {
      AppFeedback.showInfo(context, 'You Can Have At Most $kMaxSalonAddresses Salon Addresses. Remove One To Add Another.');
      return;
    }
    // The form returns the success message when something was saved.
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AiraColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _SalonForm(existing: existing),
    );
    if (saved == null || !mounted) return;
    AppFeedback.showSuccess(context, saved);
    _load(showSpinner: false);
  }

  /// API: artistBusiness.deleteSalonAddress → DELETE /artists/salon_addresses/delete/
  Future<void> _delete(SalonAddress s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AiraColors.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Remove This Salon?', style: AiraText.serif(fontSize: 19)),
        content: Text('"${s.name}" Will No Longer Be Offered For New In-Salon Bookings. Past Bookings Keep This Address.'),
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
    try {
      await ServiceLocator.artistBusiness.deleteSalonAddress(s.salonAddressId);
      if (mounted) AppFeedback.showSuccess(context, 'Salon Removed ✓');
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    }
    if (mounted) _load(showSpinner: false);
  }

  Widget _card(SalonAddress s) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AiraCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
          onTap: () => _openForm(s),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.storefront_outlined, size: 22, color: AiraColors.roseDeep),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name, style: AiraText.sans(fontSize: 14.5, fontWeight: FontWeight.w700, color: AiraColors.charcoal)),
                    const SizedBox(height: 3),
                    Text(s.addressText, style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft, height: 1.35)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(s.hasCoordinates ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                            size: 14, color: s.hasCoordinates ? AiraColors.success : AiraColors.errorText),
                        const SizedBox(width: 5),
                        Text(s.hasCoordinates ? 'Location Pinned On Map' : 'Map Location Missing',
                            style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 19, color: AiraColors.roseDeep),
                onPressed: () => _openForm(s),
              ),
              IconButton(
                tooltip: 'Remove',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline_rounded, size: 19, color: AiraColors.rose),
                onPressed: () => _delete(s),
              ),
            ],
          ),
        ),
      );

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose));
    }
    if (_error != null) return AiraErrorState(message: _error!, onRetry: _load);
    final full = _salons.length >= kMaxSalonAddresses;
    return RefreshIndicator(
      color: AiraColors.rose,
      onRefresh: () => _load(showSpinner: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text('Add The Salons Or Studios You Work From. Clients Who Book In-Salon Choose One Of Them, And You See The Same Address On The Booking.',
              style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft, height: 1.4)),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('Your Salons', style: AiraText.serif(fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${_salons.length} / $kMaxSalonAddresses', style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
            ],
          ),
          const SizedBox(height: 10),
          if (_salons.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AiraColors.blush,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AiraColors.pinkBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, size: 18, color: AiraColors.rose),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('No Salon Added Yet. Until You Add One, Clients Cannot Book You In-Salon.',
                        style: AiraText.sans(fontSize: 12.5, color: AiraColors.roseDeep, height: 1.4)),
                  ),
                ],
              ),
            )
          else
            ..._salons.map(_card),
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'Add Salon / Studio',
            icon: Icons.add_rounded,
            expand: true,
            onTap: full ? null : () => _openForm(),
          ),
          if (full)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('You Can Have At Most $kMaxSalonAddresses Salon Addresses. Remove One To Add Another.',
                  textAlign: TextAlign.center, style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.embedded) AiraScreenHeader(title: 'My Salons', onBack: () => Navigator.of(context).pop()),
        Expanded(child: _body()),
      ],
    );
    if (widget.embedded) return content;
    return Scaffold(backgroundColor: AiraColors.bg, body: SafeArea(child: content));
  }
}

/// Add / edit form (bottom sheet). Owns its controllers, so they are disposed together with the sheet.
class _SalonForm extends StatefulWidget {
  final SalonAddress? existing;
  const _SalonForm({this.existing});

  @override
  State<_SalonForm> createState() => _SalonFormState();
}

class _SalonFormState extends State<_SalonForm> {
  final _name = TextEditingController();
  final _line1 = TextEditingController();
  final _line2 = TextEditingController();
  final _city = TextEditingController();
  final _pin = TextEditingController();
  double? _lat;
  double? _lng;
  bool _saving = false;
  bool _locating = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _line1.text = e.addressLine1;
      _line2.text = e.addressLine2 ?? '';
      _city.text = e.city;
      _pin.text = e.pinCode;
      if (e.hasCoordinates) {
        _lat = e.latitude;
        _lng = e.longitude;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _line1.dispose();
    _line2.dispose();
    _city.dispose();
    _pin.dispose();
    super.dispose();
  }

  String _clip(String s, int max) => s.length > max ? s.substring(0, max) : s;

  /// Search the salon on Google Maps: fills the address and the exact latitude / longitude.
  Future<void> _pickOnMap() async {
    final p = await showGooglePlacePicker(context, title: 'Search Your Salon / Studio');
    if (p == null || !mounted) return;
    setState(() {
      _lat = p.lat;
      _lng = p.lng;
      _message = null;
      if (_name.text.trim().isEmpty && p.name.isNotEmpty) _name.text = _clip(p.name, 100);
      final line1 = p.line1.isNotEmpty ? p.line1 : (p.name.isNotEmpty ? p.name : p.area);
      _line1.text = _clip(line1, 255);
      final extraArea = (p.area.isNotEmpty && !line1.toLowerCase().contains(p.area.toLowerCase())) ? p.area : '';
      _line2.text = _clip(extraArea, 255);
      if (p.city.isNotEmpty) _city.text = _clip(p.city, 100);
      if (p.pincode.isNotEmpty) _pin.text = _clip(p.pincode, 10);
    });
  }

  /// Pin only: uses the phone's GPS for latitude / longitude (the address is typed). Works without Google search.
  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _message = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _message = 'Location Permission Denied. Please Search The Salon On The Map Instead.');
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _message = 'Please Turn On Location Services And Try Again.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Could Not Detect Your Location. Please Try Again.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Please Enter A Name For This Salon.';
    if (_line1.text.trim().isEmpty) return 'Please Enter The House / Building / Street.';
    if (_city.text.trim().isEmpty) return 'Please Enter The City.';
    if (_pin.text.trim().isEmpty) return 'Please Enter The Pincode.';
    if (_lat == null || _lng == null || (_lat == 0 && _lng == 0)) {
      return 'Please Pin The Salon Location On The Map.';
    }
    return null;
  }

  /// API: POST /artists/salon_addresses/create/  or  PUT /artists/salon_addresses/update/ (changed fields only).
  Future<void> _save() async {
    if (_saving) return;
    final problem = _validate();
    if (problem != null) {
      setState(() => _message = problem);
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final biz = ServiceLocator.artistBusiness;
      final ex = widget.existing;
      if (ex == null) {
        await biz.addSalonAddress(
          name: _name.text.trim(),
          addressLine1: _line1.text.trim(),
          addressLine2: _line2.text.trim(),
          city: _city.text.trim(),
          pinCode: _pin.text.trim(),
          latitude: _lat!,
          longitude: _lng!,
        );
        if (mounted) Navigator.of(context).pop('Salon Added ✓');
        return;
      }
      final changes = <String, dynamic>{};
      if (_name.text.trim() != ex.name) changes['name'] = _name.text.trim();
      if (_line1.text.trim() != ex.addressLine1) changes['address_line_1'] = _line1.text.trim();
      if (_line2.text.trim() != (ex.addressLine2 ?? '')) {
        changes['address_line_2'] = _line2.text.trim().isEmpty ? null : _line2.text.trim(); // null clears it
      }
      if (_city.text.trim() != ex.city) changes['city'] = _city.text.trim();
      if (_pin.text.trim() != ex.pinCode) changes['pin_code'] = _pin.text.trim();
      if ((_lat! - ex.latitude).abs() > 0.0000005 || (_lng! - ex.longitude).abs() > 0.0000005) {
        // Both are sent together so the pair can never be left at 0, 0.
        changes['latitude'] = double.parse(_lat!.toStringAsFixed(6));
        changes['longitude'] = double.parse(_lng!.toStringAsFixed(6));
      }
      if (changes.isEmpty) {
        setState(() {
          _saving = false;
          _message = 'Nothing Has Changed Yet.';
        });
        return;
      }
      await biz.updateSalonAddress(ex.salonAddressId, changes);
      if (mounted) Navigator.of(context).pop('Salon Updated ✓');
    } catch (e) {
      // The server's own message is shown as it is (duplicate name, 10-salon limit, map pin missing …).
      if (mounted) {
        setState(() {
          _saving = false;
          _message = AppFeedback.friendlyMessage(e);
        });
      }
    }
  }

  Widget _pinTile() {
    final has = _lat != null && _lng != null && !(_lat == 0 && _lng == 0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _saving ? null : _pickOnMap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: AiraColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: has ? AiraColors.roseDeep : AiraColors.hair),
          ),
          child: Row(
            children: [
              Icon(has ? Icons.check_circle_rounded : Icons.map_outlined, size: 22, color: AiraColors.roseDeep),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(has ? 'Location Pinned On Map' : 'Search Salon On Google Maps',
                        style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: AiraColors.charcoal)),
                    const SizedBox(height: 2),
                    Text(
                      has
                          ? '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)} · Tap To Change'
                          : 'Required. Fills The Address And The Exact Map Pin.',
                      style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft, height: 1.3),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AiraColors.charcoalSoft),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(22, 18, 22, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(editing ? 'Edit Salon' : 'Add Salon / Studio',
                    style: AiraText.serif(fontSize: 22, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20, color: AiraColors.charcoal),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _pinTile(),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: (_saving || _locating) ? null : _useCurrentLocation,
              icon: _locating
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AiraColors.rose))
                  : const Icon(Icons.my_location_rounded, size: 17, color: AiraColors.roseDeep),
              label: Text('Pin My Current Location (I Am At The Salon)',
                  style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w600, color: AiraColors.roseDeep)),
            ),
          ),
          const SizedBox(height: 6),
          SunndariField(
            label: 'Salon Name',
            controller: _name,
            hint: 'e.g. Gomti Nagar Studio',
            maxLength: 100,
            capitalization: TextCapitalization.words,
            helper: 'Clients See This Name When They Choose A Salon. It Must Be Different For Each Salon.',
          ),
          SunndariField(
            label: 'House / Building, Street',
            controller: _line1,
            hint: 'e.g. 12 Vibhuti Khand',
            maxLength: 255,
            capitalization: TextCapitalization.words,
          ),
          SunndariField(
            label: 'Area / Landmark',
            optionalTag: 'Optional',
            controller: _line2,
            hint: 'e.g. Near Metro Pillar 120',
            maxLength: 255,
            capitalization: TextCapitalization.words,
          ),
          SunndariField(
            label: 'City',
            controller: _city,
            hint: 'e.g. Lucknow',
            maxLength: 100,
            capitalization: TextCapitalization.words,
          ),
          SunndariField(
            label: 'Pincode',
            controller: _pin,
            hint: '6-digit Pincode',
            keyboardType: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_message!, style: AiraText.sans(fontSize: 12.5, color: AiraColors.errorText, height: 1.4)),
            ),
          PrimaryButton(
            label: _saving ? 'Saving…' : (editing ? 'Save Changes' : 'Add Salon'),
            expand: true,
            onTap: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
