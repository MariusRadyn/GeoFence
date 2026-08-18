import 'dart:async';
import 'dart:convert';

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

  Future<List<AddressSuggestion>> search(String query) async {
    final q = query.trim();
    if (q.length < 3) return [];
    await loadMapsApiKey();
    await ensureLocation();

    if (resolvedMapsApiKey.isNotEmpty) {
      try {
        final google = await _searchGoogle(q);
        if (google.isNotEmpty) return google;
      } catch (e) {
        printDebugMsg('Places autocomplete: $e');
      }
    }

    try {
      return await _searchPhoton(q);
    } catch (e) {
      printDebugMsg('Photon autocomplete: $e');
      return [];
    }
  }

  Future<AddressSuggestion> details(AddressSuggestion suggestion) async {
    if (suggestion.street.isNotEmpty && suggestion.postalCode.isNotEmpty) {
      return suggestion;
    }
    if (resolvedMapsApiKey.isEmpty || suggestion.placeId.startsWith('photon:')) {
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
      'types': 'address',
      'language': 'en',
    };
    final here = _here;
    if (here != null) {
      params['location'] = '${here.latitude},${here.longitude}';
      params['radius'] = '35000';
    }
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      params,
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body);
    if (body is! Map || body['status'] != 'OK') return [];
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

  Future<List<AddressSuggestion>> _searchPhoton(String query) async {
    final params = <String, String>{
      'q': query,
      'limit': '6',
      'lang': 'en',
    };
    final here = _here;
    if (here != null) {
      params['lat'] = '${here.latitude}';
      params['lon'] = '${here.longitude}';
    }
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

    final out = <AddressSuggestion>[];
    for (final raw in features) {
      if (raw is! Map) continue;
      final props = raw['properties'];
      if (props is! Map) continue;
      final country = '${props['countrycode'] ?? props['country'] ?? ''}'
          .toLowerCase();
      if (country.isNotEmpty &&
          country != 'za' &&
          country != 'south africa') {
        continue;
      }
      final parsed = _fromPhoton(props);
      if (parsed.label.isEmpty) continue;
      out.add(parsed);
    }
    return out;
  }

  AddressSuggestion _fromPhoton(Map props) {
    final number = '${props['housenumber'] ?? ''}'.trim();
    final streetName =
        '${props['street'] ?? props['name'] ?? ''}'.trim();
    final street = [number, streetName]
        .where((s) => s.isNotEmpty)
        .join(' ')
        .trim();
    final suburb = '${props['district'] ?? props['suburb'] ?? props['locality'] ?? ''}'
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
