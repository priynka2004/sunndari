class GooglePlacesConfig {
  static const String apiKey = String.fromEnvironment(
    'MAPS_KEY',
    defaultValue: 'AIzaSyBZYExBAEPU7F1d_BmQoziP2Udf4MLlB2o',
  );

  static bool get isSet =>
      apiKey.isNotEmpty && !apiKey.startsWith('PASTE_');

  static const bool useNewPlacesApi = true;
}