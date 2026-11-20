// FILE: utils/travel_charge_config.dart
// Visiting charge options for an artist's service areas.
//
//   Per Visit      → fixed amount per booking (e.g. ₹500).            travel_charge_type = per_visit
//   Per Kilometre  → rate per km (e.g. ₹10/km). At booking time the distance between the artist and the
//                    customer is multiplied by this rate.              travel_charge_type = per_km
//
// The distance calculation and the charge shown to the customer are done by the backend / Customer app.
// Keep this false until the backend accepts `per_km` on /artists/service_areas/add/ and /update/
// (today it answers 400: "Per-kilometre travel charges are not available yet"). Then set it to true:
// the "Per Km" choice appears in the Location step and in Edit Travel Charges.
const bool kPerKmChargeEnabled = false;
