// FILE: widgets/google_place_picker.dart
// WIDGET: Google Location address picker (bottom sheet).
//
// The artist / customer searches an address (Google Places) or taps "Use My Current Location" and gets back a
// [PickedPlace] with the address parts AND the exact latitude / longitude, so the right location is saved.
//
// Usage:
//   final place = await showGooglePlacePicker(context, title: 'Search Your Salon / Studio');
//   if (place != null) { ...place.line1, place.area, place.city, place.pincode, place.lat, place.lng... }
//
// APIs (Google, key from GooglePlacesConfig):
//   Places API (New): POST places.googleapis.com/v1/places:autocomplete  +  GET places.googleapis.com/v1/places/{id}
//   (or the legacy maps.googleapis.com/maps/api/place/autocomplete + details when useNewPlacesApi is false)
//   GET maps.googleapis.com/maps/api/geocode/json   (reverse geocode for "current location")
// This file is self-contained so the same widget can be copied into the Customer app.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/tokens.dart';
import '../utils/api_logger.dart';
import '../utils/google_places_config.dart';

/// One address chosen on Google Maps.
class PickedPlace {
  final String placeId;
  final String formattedAddress;
  final String name; // building / business name when Google has one
  final String line1; // house no. / building / street
  final String area; // sub-locality
  final String city;
  final String state;
  final String pincode;
  final double lat;
  final double lng;

  const PickedPlace({
    required this.placeId,
    required this.formattedAddress,
    required this.name,
    required this.line1,
    required this.area,
    required this.city,
    required this.state,
    required this.pincode,
    required this.lat,
    required this.lng,
  });

  /// "house / street, area" — the address line the backend stores.
  String get addressLine {
    final parts = <String>[];
    for (final p in [line1, area]) {
      final t = p.trim();
      if (t.isEmpty) continue;
      if (parts.any((e) => e.toLowerCase().contains(t.toLowerCase()))) continue;
      parts.add(t);
    }
    if (parts.isEmpty) return formattedAddress;
    return parts.join(', ');
  }
}

/// Opens the picker. Returns null if the person closes it without choosing.
Future<PickedPlace?> showGooglePlacePicker(BuildContext context, {String title = 'Search Address'}) {
  return showModalBottomSheet<PickedPlace>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PlacePickerSheet(title: title),
  );
}

class _Prediction {
  final String placeId;
  final String main;
  final String secondary;
  const _Prediction(this.placeId, this.main, this.secondary);
}

class _PlacePickerSheet extends StatefulWidget {
  final String title;
  const _PlacePickerSheet({required this.title});

  @override
  State<_PlacePickerSheet> createState() => _PlacePickerSheetState();
}

class _PlacePickerSheetState extends State<_PlacePickerSheet> {
  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;
  List<_Prediction> _results = [];
  bool _loading = false;
  bool _picking = false;
  bool _detecting = false;
  String? _message;
  final String _session = DateTime.now().microsecondsSinceEpoch.toString();

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.length < 3) {
      setState(() {
        _results = [];
        _message = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      if (!GooglePlacesConfig.isSet) throw Exception('REQUEST_DENIED'); // no key pasted yet
      final list = GooglePlacesConfig.useNewPlacesApi ? await _searchNew(q) : await _searchLegacy(q);
      if (!mounted || q != _ctrl.text.trim()) return;
      setState(() {
        _results = list;
        _message = list.isEmpty ? 'No Address Found. Try A Nearby Landmark Or Area.' : null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _message = '$e'.contains('REQUEST_DENIED')
            ? 'Google Maps Search Is Not Set Up Yet (API Key). Please Contact Support.'
            : 'Could Not Search Right Now. Please Check Your Internet And Try Again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  // ───────────── Places API (New) ─────────────

  bool _isDenied(int code, Map err) =>
      code == 401 || code == 403 || '${err['message'] ?? ''}'.toLowerCase().contains('api key');

  /// POST https://places.googleapis.com/v1/places:autocomplete
  Future<List<_Prediction>> _searchNew(String q) async {
    final r = await ApiLog.post(
      Uri.parse('https://places.googleapis.com/v1/places:autocomplete'),
      headers: {'Content-Type': 'application/json', 'X-Goog-Api-Key': GooglePlacesConfig.apiKey},
      body: jsonEncode({'input': q, 'includedRegionCodes': ['in'], 'sessionToken': _session}),
      tag: 'HTTP/places-address',
    );
    final data = jsonDecode(r.body);
    if (r.statusCode != 200) {
      final err = data is Map && data['error'] is Map ? data['error'] as Map : const {};
      ApiLog.info('Places', 'address autocomplete (new) ${r.statusCode} ${err['status'] ?? ''} ${err['message'] ?? ''}');
      throw Exception(_isDenied(r.statusCode, err) ? 'REQUEST_DENIED' : 'HTTP ${r.statusCode}');
    }
    String t(dynamic o) => o is Map ? (o['text'] ?? '').toString() : '';
    final suggestions = data is Map ? (data['suggestions'] as List? ?? const []) : const [];
    return suggestions
        .whereType<Map>()
        .map((s) {
          final p = s['placePrediction'];
          if (p is! Map) return null;
          final sf = p['structuredFormat'] is Map ? p['structuredFormat'] as Map : const {};
          final main = t(sf['mainText']).isNotEmpty ? t(sf['mainText']) : t(p['text']);
          return _Prediction((p['placeId'] ?? '').toString(), main, t(sf['secondaryText']));
        })
        .whereType<_Prediction>()
        .where((p) => p.placeId.isNotEmpty && p.main.isNotEmpty)
        .toList();
  }

  /// GET https://places.googleapis.com/v1/places/{placeId} — converted to the shape [_parse] already understands.
  Future<PickedPlace?> _detailsNew(_Prediction p) async {
    final r = await ApiLog.get(
      Uri.parse('https://places.googleapis.com/v1/places/${Uri.encodeComponent(p.placeId)}'
          '?languageCode=en&sessionToken=$_session'),
      headers: {
        'X-Goog-Api-Key': GooglePlacesConfig.apiKey,
        'X-Goog-FieldMask': 'id,displayName,formattedAddress,location,addressComponents',
      },
      tag: 'HTTP/places-details',
    );
    final d = jsonDecode(r.body);
    if (r.statusCode != 200 || d is! Map) throw Exception('HTTP ${r.statusCode}');
    final loc = d['location'] is Map ? d['location'] as Map : const {};
    final comps = (d['addressComponents'] as List? ?? const [])
        .whereType<Map>()
        .map((c) => <String, dynamic>{'long_name': c['longText'], 'short_name': c['shortText'], 'types': c['types'] ?? const []})
        .toList();
    return _parse(<String, dynamic>{
      'name': d['displayName'] is Map ? (d['displayName'] as Map)['text'] : '',
      'formatted_address': d['formattedAddress'] ?? '',
      'place_id': d['id'] ?? p.placeId,
      'geometry': {'location': {'lat': loc['latitude'], 'lng': loc['longitude']}},
      'address_components': comps,
    }, placeId: p.placeId);
  }

  // ───────────── Legacy Places API (only for Google projects created before 1 March 2025) ─────────────

  Future<List<_Prediction>> _searchLegacy(String q) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json'
      '?input=${Uri.encodeQueryComponent(q)}'
      '&components=country:in'
      '&sessiontoken=$_session'
      '&key=${GooglePlacesConfig.apiKey}',
    );
    final r = await ApiLog.get(url, tag: 'HTTP/places-address');
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final status = (data['status'] ?? '').toString();
    if (status != 'OK' && status != 'ZERO_RESULTS') {
      ApiLog.info('Places', 'address autocomplete status=$status ${data['error_message'] ?? ''}');
      throw Exception(status);
    }
    return (data['predictions'] as List? ?? []).whereType<Map>().map((p) {
      final sf = p['structured_formatting'] is Map ? p['structured_formatting'] as Map : const {};
      return _Prediction(
        (p['place_id'] ?? '').toString(),
        (sf['main_text'] ?? p['description'] ?? '').toString(),
        (sf['secondary_text'] ?? '').toString(),
      );
    }).where((p) => p.placeId.isNotEmpty && p.main.isNotEmpty).toList();
  }

  Future<PickedPlace?> _detailsLegacy(_Prediction p) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json'
      '?place_id=${Uri.encodeQueryComponent(p.placeId)}'
      '&fields=place_id,name,formatted_address,geometry,address_component'
      '&sessiontoken=$_session'
      '&key=${GooglePlacesConfig.apiKey}',
    );
    final r = await ApiLog.get(url, tag: 'HTTP/places-details');
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    if (data['status'] != 'OK' || data['result'] is! Map) throw Exception('${data['status']}');
    return _parse(Map<String, dynamic>.from(data['result'] as Map), placeId: p.placeId);
  }

  /// Parses Google address_components into a [PickedPlace].
  PickedPlace? _parse(Map<String, dynamic> result, {String placeId = ''}) {
    final loc = (result['geometry'] is Map && (result['geometry'] as Map)['location'] is Map)
        ? (result['geometry'] as Map)['location'] as Map
        : null;
    final lat = (loc?['lat'] as num?)?.toDouble();
    final lng = (loc?['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    String pick(List<String> types, {bool short = false}) {
      for (final c in (result['address_components'] as List? ?? []).whereType<Map>()) {
        final t = (c['types'] as List? ?? []).map((e) => '$e').toList();
        if (types.any(t.contains)) return ((short ? c['short_name'] : c['long_name']) ?? '').toString();
      }
      return '';
    }

    final streetNo = pick(['street_number']);
    final premise = pick(['premise', 'subpremise']);
    final route = pick(['route']);
    final neighbourhood = pick(['neighborhood']);
    final sub1 = pick(['sublocality_level_1', 'sublocality']);
    final sub2 = pick(['sublocality_level_2']);
    final city = pick(['locality']).isNotEmpty
        ? pick(['locality'])
        : (pick(['administrative_area_level_2']).isNotEmpty ? pick(['administrative_area_level_2']) : pick(['administrative_area_level_3']));
    final name = (result['name'] ?? '').toString();
    final formatted = (result['formatted_address'] ?? '').toString();

    final line1 = [
      [streetNo, premise].where((e) => e.isNotEmpty).join(' '),
      route,
      sub2,
    ].where((e) => e.trim().isNotEmpty).join(', ');
    final area = sub1.isNotEmpty ? sub1 : neighbourhood;

    return PickedPlace(
      placeId: placeId.isNotEmpty ? placeId : (result['place_id'] ?? '').toString(),
      formattedAddress: formatted,
      name: name == formatted ? '' : name,
      line1: line1.isNotEmpty ? line1 : (name != formatted ? name : ''),
      area: area,
      city: city,
      state: pick(['administrative_area_level_1']),
      pincode: pick(['postal_code']),
      lat: lat,
      lng: lng,
    );
  }

  Future<void> _choose(_Prediction p) async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _message = null;
    });
    try {
      final place = GooglePlacesConfig.useNewPlacesApi ? await _detailsNew(p) : await _detailsLegacy(p);
      if (place == null) throw Exception('No coordinates');
      if (mounted) Navigator.of(context).pop(place);
    } catch (_) {
      if (mounted) {
        setState(() {
          _picking = false;
          _message = 'Could Not Read This Address. Please Choose Another Result.';
        });
      }
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _detecting = true;
      _message = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _message = 'Location Permission Denied — Please Search Your Address Instead.');
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _message = 'Please Turn On Location Services And Try Again.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!GooglePlacesConfig.isSet) throw Exception('REQUEST_DENIED');
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${pos.latitude},${pos.longitude}&key=${GooglePlacesConfig.apiKey}',
      );
      final r = await ApiLog.get(url, tag: 'HTTP/reverse-geocode-google');
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      final list = (data['results'] as List? ?? []).whereType<Map>().toList();
      if (data['status'] != 'OK' || list.isEmpty) throw Exception('${data['status']}');
      final res = Map<String, dynamic>.from(list.first);
      res['geometry'] = {
        'location': {'lat': pos.latitude, 'lng': pos.longitude}, // the exact spot, not the street centre
      };
      final place = _parse(res);
      if (place == null) throw Exception('parse');
      if (mounted) Navigator.of(context).pop(place);
    } catch (_) {
      if (mounted) setState(() => _message = 'Could Not Detect Your Location — Please Search Your Address Instead.');
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        height: media.size.height * 0.88,
        decoration: const BoxDecoration(
          color: AiraColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AiraColors.hair, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Expanded(child: Text(widget.title, style: AiraText.serif(fontSize: 18, fontWeight: FontWeight.w600))),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: AiraColors.charcoal),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: AiraColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AiraColors.hair),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: AiraText.sans(fontSize: 15),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Search House, Street, Area Or Landmark…',
                    hintStyle: AiraText.sans(fontSize: 14, color: AiraColors.charcoalSoft),
                    icon: const Icon(Icons.search, size: 20, color: AiraColors.charcoalSoft),
                    suffixIcon: (_loading || _picking)
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AiraColors.rose),
                            ),
                          )
                        : null,
                  ),
                  onChanged: _onChanged,
                ),
              ),
            ),
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: _detecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AiraColors.rose),
                    )
                  : const Icon(Icons.my_location_rounded, size: 20, color: AiraColors.roseDeep),
              title: Text('Use My Current Location',
                  style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w600, color: AiraColors.roseDeep)),
              onTap: (_detecting || _picking) ? null : _useCurrentLocation,
            ),
            const Divider(height: 1, color: AiraColors.hair),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Text(_message!, style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft, height: 1.4)),
              ),
            Expanded(
              child: ListView.separated(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: AiraColors.hair),
                itemBuilder: (_, i) {
                  final p = _results[i];
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: const Icon(Icons.location_on_outlined, size: 20, color: AiraColors.roseDeep),
                    title: Text(p.main, style: AiraText.sans(fontSize: 14.5, fontWeight: FontWeight.w600, color: AiraColors.charcoal)),
                    subtitle: p.secondary.isEmpty
                        ? null
                        : Text(p.secondary, style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
                    onTap: _picking ? null : () => _choose(p),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Text('Powered by Google', style: AiraText.sans(fontSize: 10.5, color: AiraColors.charcoalSoft)),
            ),
          ],
        ),
      ),
    );
  }
}
