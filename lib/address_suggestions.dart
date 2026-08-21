import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geofence/utils.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class AddressSuggestion {
  final String placeId;
  final String label;
  final String street;
  final String suburb;
  final String city;
  final String postalCode;

  const AddressSuggestion({
    required this.placeId,
    required this.label,
    this.street = '',
    this.suburb = '',
    this.city = '',
    this.postalCode = '',
  });
}

class AddressSuggestionService {
  AddressSuggestionService();

  /// Default bias: Pietermaritzburg / KZN when GPS is unavailable.
  static const double _defaultLat = -29.6006;
  static const double _defaultLon = 30.3796;

  Position? _here;
  bool _askedLocation = false;

  Future<Position?> ensureLocation() async {
    if (_here != null) return _here;
    if (_askedLocation) return _here;
    _askedLocation = true;
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;

      _here = await Geolocator.getLastKnownPosition();
      _here ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );
    } catch (e) {
      printDebugMsg('Address location: $e');
    }
    return _here;
  }

  double get _lat => _here?.latitude ?? _defaultLat;
  double get _lon => _here?.longitude ?? _defaultLon;

  Future<List<AddressSuggestion>> search(String query) async {
    final q = query.trim();
    if (q.length < 3) return [];
    await loadMapsApiKey();
    await ensureLocation();

    // Google Places REST autocomplete is not CORS-friendly in browsers.
    // Only call it from native (Android/iOS/desktop) when a key is present.
    if (!kIsWeb && resolvedMapsApiKey.isNotEmpty) {
      try {
        final google = await _searchGoogle(q);
        if (google.isNotEmpty) return google;
      } catch (e) {
        printDebugMsg('Places autocomplete: $e');
      }
    }

    try {
      final nominatim = await _searchNominatim(q);
      if (nominatim.isNotEmpty) return nominatim;
    } catch (e) {
      printDebugMsg('Nominatim autocomplete: $e');
    }

    try {
      return await _searchPhoton(q);
    } catch (e) {
      printDebugMsg('Photon autocomplete: $e');
      return [];
    }
  }

  Future<AddressSuggestion> details(AddressSuggestion suggestion) async {
    if (suggestion.street.isNotEmpty &&
        (suggestion.postalCode.isNotEmpty || suggestion.city.isNotEmpty)) {
      return suggestion;
    }
    if (resolvedMapsApiKey.isEmpty ||
        suggestion.placeId.startsWith('photon:') ||
        suggestion.placeId.startsWith('nominatim:') ||
        kIsWeb) {
      return suggestion;
    }
    try {
      return await _googleDetails(suggestion.placeId) ?? suggestion;
    } catch (e) {
      printDebugMsg('Place details: $e');
      return suggestion;
    }
  }

  Future<List<AddressSuggestion>> _searchGoogle(String query) async {
    final params = <String, String>{
      'input': query,
      'key': resolvedMapsApiKey,
      'components': 'country:za',
      'language': 'en',
      // Broader than `address` so partial street names still match.
      'types': 'geocode',
      'location': '$_lat,$_lon',
      'radius': '50000',
    };
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      params,
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body);
    if (body is! Map) return [];
    final status = '${body['status'] ?? ''}';
    if (status != 'OK' && status != 'ZERO_RESULTS') {
      printDebugMsg(
        'Places autocomplete status=$status '
        'error=${body['error_message'] ?? ''}',
      );
      return [];
    }
    if (status != 'OK') return [];
    final predictions = body['predictions'];
    if (predictions is! List) return [];
    return predictions.take(6).map((raw) {
      final map = Map<String, dynamic>.from(raw as Map);
      return AddressSuggestion(
        placeId: '${map['place_id'] ?? ''}',
        label: '${map['description'] ?? ''}',
      );
    }).where((s) => s.placeId.isNotEmpty && s.label.isNotEmpty).toList();
  }

  Future<AddressSuggestion?> _googleDetails(String placeId) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      {
        'place_id': placeId,
        'fields': 'address_component,formatted_address',
        'key': resolvedMapsApiKey,
        'language': 'en',
      },
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body);
    if (body is! Map || body['status'] != 'OK') return null;
    final result = body['result'];
    if (result is! Map) return null;
    return _fromGoogleComponents(
      placeId,
      '${result['formatted_address'] ?? ''}',
      result['address_components'],
    );
  }

  AddressSuggestion _fromGoogleComponents(
    String placeId,
    String formatted,
    dynamic components,
  ) {
    String streetNumber = '';
    String route = '';
    String suburb = '';
    String city = '';
    String postal = '';
    if (components is List) {
      for (final raw in components) {
        if (raw is! Map) continue;
        final types = (raw['types'] as List?)?.map((e) => '$e').toList() ?? [];
        final long = '${raw['long_name'] ?? ''}';
        if (types.contains('street_number')) streetNumber = long;
        if (types.contains('route')) route = long;
        if (types.contains('sublocality') ||
            types.contains('sublocality_level_1') ||
            types.contains('neighborhood')) {
          suburb = suburb.isEmpty ? long : suburb;
        }
        if (types.contains('locality')) city = long;
        if (city.isEmpty && types.contains('administrative_area_level_2')) {
          city = long;
        }
        if (types.contains('postal_code')) postal = long;
      }
    }
    final street = [streetNumber, route]
        .where((s) => s.trim().isNotEmpty)
        .join(' ')
        .trim();
    return AddressSuggestion(
      placeId: placeId,
      label: formatted,
      street: street.isEmpty ? formatted.split(',').first.trim() : street,
      suburb: suburb,
      city: city,
      postalCode: postal,
    );
  }

  /// OpenStreetMap Nominatim — works from browsers (CORS) and needs no API key.
  Future<List<AddressSuggestion>> _searchNominatim(String query) async {
    final params = <String, String>{
      'q': query,
      'format': 'jsonv2',
      'addressdetails': '1',
      'countrycodes': 'za',
      'limit': '6',
      'viewbox':
          '${_lon - 0.35},${_lat + 0.35},${_lon + 0.35},${_lat - 0.35}',
      'bounded': '0',
    };
    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      params,
    );
    final headers = <String, String>{
      'Accept': 'application/json',
    };
    // Browsers forbid setting User-Agent; native can send a proper one.
    if (!kIsWeb) {
      headers['User-Agent'] = 'LimitlessIOT/1.0 (info@trinityglobal.co.za)';
    }
    final res = await http.get(
      uri,
      headers: headers,
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      printDebugMsg('Nominatim HTTP ${res.statusCode}');
      return [];
    }
    final body = jsonDecode(res.body);
    if (body is! List) return [];

    final out = <AddressSuggestion>[];
    for (final raw in body) {
      if (raw is! Map) continue;
      final parsed = _fromNominatim(raw);
      if (parsed.label.isEmpty) continue;
      out.add(parsed);
    }
    return out;
  }

  AddressSuggestion _fromNominatim(Map raw) {
    final address = raw['address'];
    final map = address is Map ? Map<String, dynamic>.from(address) : {};
    final number = '${map['house_number'] ?? ''}'.trim();
    final streetName = '${map['road'] ?? map['pedestrian'] ?? map['path'] ?? ''}'
        .trim();
    final name = '${raw['name'] ?? ''}'.trim();
    final street = [
      number,
      streetName.isNotEmpty ? streetName : name,
    ].where((s) => s.isNotEmpty).join(' ').trim();

    final suburb = '${map['suburb'] ?? map['neighbourhood'] ?? map['quarter'] ?? ''}'
        .trim();
    final city =
        '${map['city'] ?? map['town'] ?? map['village'] ?? map['municipality'] ?? ''}'
            .trim();
    final postal = '${map['postcode'] ?? ''}'.trim();
    final display = '${raw['display_name'] ?? ''}'.trim();
    final parts = <String>[
      if (street.isNotEmpty) street,
      if (suburb.isNotEmpty) suburb,
      if (city.isNotEmpty && city != suburb) city,
      if (postal.isNotEmpty) postal,
    ];

    return AddressSuggestion(
      placeId: 'nominatim:${raw['place_id'] ?? display}',
      label: parts.isNotEmpty ? parts.join(', ') : display,
      street: street.isNotEmpty ? street : display.split(',').first.trim(),
      suburb: suburb,
      city: city,
      postalCode: postal,
    );
  }

  Future<List<AddressSuggestion>> _searchPhoton(String query) async {
    final params = <String, String>{
      'q': query,
      'limit': '8',
      'lang': 'en',
      'lat': '$_lat',
      'lon': '$_lon',
    };
    final uri = Uri.https('photon.komoot.io', '/api/', params);
    final res = await http.get(
      uri,
      headers: {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body);
    if (body is! Map) return [];
    final features = body['features'];
    if (features is! List) return [];

    final za = <AddressSuggestion>[];
    final other = <AddressSuggestion>[];
    for (final raw in features) {
      if (raw is! Map) continue;
      final props = raw['properties'];
      if (props is! Map) continue;
      final parsed = _fromPhoton(props);
      if (parsed.label.isEmpty) continue;
      if (_isSouthAfrica(props)) {
        za.add(parsed);
      } else {
        other.add(parsed);
      }
    }
    // Prefer ZA, but don't return empty if the country field was missing.
    final preferred = za.isNotEmpty ? za : other;
    return preferred.take(6).toList();
  }

  bool _isSouthAfrica(Map props) {
    final country = '${props['countrycode'] ?? props['country'] ?? ''}'
        .toLowerCase()
        .trim();
    if (country.isEmpty) return true;
    return country == 'za' ||
        country == 'south africa' ||
        country == 'zaf';
  }

  AddressSuggestion _fromPhoton(Map props) {
    final number = '${props['housenumber'] ?? ''}'.trim();
    final streetName =
        '${props['street'] ?? props['name'] ?? ''}'.trim();
    final street = [number, streetName]
        .where((s) => s.isNotEmpty)
        .join(' ')
        .trim();
    final suburb =
        '${props['district'] ?? props['suburb'] ?? props['locality'] ?? ''}'
            .trim();
    final city = '${props['city'] ?? props['county'] ?? ''}'.trim();
    final postal = '${props['postcode'] ?? ''}'.trim();
    final parts = <String>[
      if (street.isNotEmpty) street,
      if (suburb.isNotEmpty) suburb,
      if (city.isNotEmpty && city != suburb) city,
      if (postal.isNotEmpty) postal,
    ];
    return AddressSuggestion(
      placeId: 'photon:${props['osm_id'] ?? street}',
      label: parts.join(', '),
      street: street,
      suburb: suburb,
      city: city,
      postalCode: postal,
    );
  }
}
