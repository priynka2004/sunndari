// FILE: widgets/city_autocomplete_field.dart
// WIDGET: City field with search + bottom-sheet picker.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/tokens.dart';
import '../utils/api_logger.dart';
import '../utils/google_places_config.dart';
import '../utils/indian_cities.dart';

/// City Autocomplete Field widget.
class CityAutocompleteField extends StatefulWidget {
  final String label;
  final String? initialValue;
  final ValueChanged<String> onChanged;

  const CityAutocompleteField({super.key, required this.label, this.initialValue, required this.onChanged});

  @override
  State<CityAutocompleteField> createState() => _CityAutocompleteFieldState();
}

/// State of [CityAutocompleteField] — holds the screen data and logic.
class _CityAutocompleteFieldState extends State<CityAutocompleteField> {
  String? _value;

  /// Runs once when the screen opens.
  @override
  void initState() {
    super.initState();
    final v = (widget.initialValue ?? '').trim();
    _value = v.isEmpty ? null : v;
  }

  /// Opens the next screen.
  Future<void> _open() async {
    FocusScope.of(context).unfocus();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CityPickerSheet(selected: _value),
    );
    if (picked == null || !mounted) return;
    setState(() => _value = picked);
    widget.onChanged(picked);
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    final has = _value != null && _value!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label.toUpperCase(),
              style: AiraText.sans(fontSize: 12, fontWeight: FontWeight.w600, color: AiraColors.charcoalSoft)),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _open,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              decoration: BoxDecoration(
                color: AiraColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AiraColors.hair),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      has ? _value! : 'Select Your City',
                      style: AiraText.sans(
                        fontSize: has ? 15 : 14,
                        color: has ? AiraColors.charcoal : AiraColors.charcoalSoft,
                      ),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded, color: AiraColors.roseDeep),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Private City Picker Sheet widget.
class _CityPickerSheet extends StatefulWidget {
  final String? selected;
  const _CityPickerSheet({this.selected});

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

/// State of [_CityPickerSheet] — holds the screen data and logic.
class _CityPickerSheetState extends State<_CityPickerSheet> {
  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  List<IndianCity> _remote = [];
  bool _loading = false;
  bool _detecting = false;

  /// Frees controllers / listeners when the screen closes.
  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  List<IndianCity> get _results {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return kIndianCities;
    final starts = <IndianCity>[];
    final contains = <IndianCity>[];
    for (final c in kIndianCities) {
      final n = c.name.toLowerCase();
      if (n.startsWith(q)) {
        starts.add(c);
      } else if (n.contains(q) || c.state.toLowerCase().startsWith(q)) {
        contains.add(c);
      }
    }
    final seen = <String>{
      for (final c in starts) c.name.toLowerCase(),
      for (final c in contains) c.name.toLowerCase(),
    };
    final extra = _remote.where((c) => !seen.contains(c.name.toLowerCase())).toList();
    return [...starts, ...contains, ...extra];
  }

  /// Callback when query changed happens.
  void _onQueryChanged(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    if (v.trim().length < 2) {
      setState(() => _remote = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _fetchRemote(v.trim()));
  }

  /// Fetches remote.
  Future<void> _fetchRemote(String query) async {
    setState(() => _loading = true);
    try {
      if (!GooglePlacesConfig.isSet) return; // no key pasted yet → the built-in city list is used
      if (GooglePlacesConfig.useNewPlacesApi) {
        // Places API (New): POST https://places.googleapis.com/v1/places:autocomplete
        final res = await ApiLog.post(
          Uri.parse('https://places.googleapis.com/v1/places:autocomplete'),
          headers: {'Content-Type': 'application/json', 'X-Goog-Api-Key': GooglePlacesConfig.apiKey},
          body: jsonEncode({'input': query, 'includedPrimaryTypes': ['(cities)'], 'includedRegionCodes': ['in']}),
          tag: 'HTTP/places-autocomplete',
        );
        if (res.statusCode != 200) {
          ApiLog.info('Places', 'city autocomplete (new) failed: ${res.statusCode}');
          return;
        }
        final d = jsonDecode(res.body);
        String t(dynamic o) => o is Map ? (o['text'] ?? '').toString() : '';
        final fromNew = (d is Map ? (d['suggestions'] as List? ?? const []) : const [])
            .whereType<Map>()
            .map((s) {
              final p = s['placePrediction'];
              if (p is! Map) return null;
              final sf = p['structuredFormat'] is Map ? p['structuredFormat'] as Map : const {};
              final main = t(sf['mainText']).isNotEmpty ? t(sf['mainText']) : t(p['text']);
              return IndianCity(main, t(sf['secondaryText']));
            })
            .whereType<IndianCity>()
            .where((c) => c.name.isNotEmpty)
            .toList();
        if (mounted && query == _query.trim()) setState(() => _remote = fromNew);
        return;
      }
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeQueryComponent(query)}'
        '&types=(cities)'
        '&components=country:in'
        '&key=${GooglePlacesConfig.apiKey}',
      );
      final response = await ApiLog.get(url, tag: 'HTTP/places-autocomplete');
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body);
      final status = data['status'];
      if (status != null && status != 'OK' && status != 'ZERO_RESULTS') {
        ApiLog.info('Places', 'autocomplete status=$status message=${data['error_message']}');
      }
      final raw = (data['predictions'] as List<dynamic>? ?? []);
      final parsed = raw.map((p) {
        final structured = p['structured_formatting'] ?? {};
        final main = (structured['main_text'] ?? p['description'] ?? '').toString();
        final secondary = (structured['secondary_text'] ?? '').toString();
        return IndianCity(main, secondary);
      }).where((c) => c.name.isNotEmpty).toList();
      if (mounted && query == _query.trim()) setState(() => _remote = parsed);
    } catch (e) {
      ApiLog.info('Places', 'autocomplete failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Lets the user pick.
  void _pick(String name) => Navigator.of(context).pop(name);

  /// Use current location.
  Future<void> _useCurrentLocation() async {
    setState(() => _detecting = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _snack('Location Permission Denied — Please Search Your City Instead');
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack('Please Turn On Location Services And Try Again');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json&lat=${pos.latitude}&lon=${pos.longitude}&zoom=10&addressdetails=1',
      );
      final response = await ApiLog.get(
        url,
        headers: {'Accept-Language': 'en', 'User-Agent': 'SunndariArtistApp/1.0'},
        tag: 'HTTP/reverse-geocode',
      );
      if (response.statusCode != 200) throw Exception('Geocode Failed');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final addr = data['address'] as Map<String, dynamic>? ?? {};
      final city = (addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['county'] ?? '').toString();
      if (city.isEmpty) throw Exception('No City In Geocode Result');
      if (mounted) _pick(city);
    } catch (e) {
      _snack('Could Not Detect Your Location — Please Search Your City Instead');
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    final results = _results;
    final typed = _query.trim();
    final hasExact = results.any((c) => c.name.toLowerCase() == typed.toLowerCase());
    final showUseTyped = typed.length >= 2 && !hasExact;
    final itemCount = results.length + (showUseTyped ? 1 : 0);
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        height: media.size.height * 0.85,
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
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Select Your City', style: AiraText.serif(fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
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
                  textCapitalization: TextCapitalization.words,
                  style: AiraText.sans(fontSize: 15),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Search City…',
                    hintStyle: AiraText.sans(fontSize: 14, color: AiraColors.charcoalSoft),
                    icon: const Icon(Icons.search, size: 20, color: AiraColors.charcoalSoft),
                    suffixIcon: _loading
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
                  onChanged: _onQueryChanged,
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
              title: Text(
                'Use My Current Location',
                style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w600, color: AiraColors.roseDeep),
              ),
              onTap: _detecting ? null : _useCurrentLocation,
            ),
            const Divider(height: 1, color: AiraColors.hair),
            Expanded(
              child: itemCount == 0
                  ? Center(
                      child: Text('No City Found', style: AiraText.sans(fontSize: 13, color: AiraColors.charcoalSoft)),
                    )
                  : ListView.separated(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: itemCount,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: AiraColors.hair),
                      itemBuilder: (_, i) {
                        if (i >= results.length) {
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                            leading: const Icon(Icons.add_location_alt_outlined, size: 18, color: AiraColors.roseDeep),
                            title: Text(
                              'Use "$typed"',
                              style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w600, color: AiraColors.roseDeep),
                            ),
                            onTap: () => _pick(typed),
                          );
                        }
                        final c = results[i];
                        final isSelected = widget.selected != null &&
                            widget.selected!.toLowerCase() == c.name.toLowerCase();
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                          leading: const Icon(Icons.location_city_rounded, size: 18, color: AiraColors.charcoalSoft),
                          title: Text(
                            c.name,
                            style: AiraText.sans(
                              fontSize: 14.5,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: AiraColors.charcoal,
                            ),
                          ),
                          subtitle: c.state.isEmpty
                              ? null
                              : Text(c.state, style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
                          trailing: isSelected
                              ? const Icon(Icons.check_rounded, size: 18, color: AiraColors.roseDeep)
                              : null,
                          onTap: () => _pick(c.name),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
