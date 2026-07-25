import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum GpsStatus { loading, available, unavailable, permissionDenied, error }

class LocationService extends ChangeNotifier {
  GpsStatus _status = GpsStatus.loading;
  Position? _position;
  bool _isGpsEnabled = false;
  StreamSubscription<Position>? _positionSubscription;

  GpsStatus get status => _status;
  Position? get position => _position;
  bool get isGpsEnabled => _isGpsEnabled;
  double? get latitude => _position?.latitude;
  double? get longitude => _position?.longitude;
  double? get accuracy => _position?.accuracy;
  double? get altitude => _position?.altitude;
  double? get speed => _position?.speed;
  DateTime? get lastFix => _position?.timestamp;

  Future<void> init() async {
    await _checkStatus();
    if (_status == GpsStatus.available) {
      _startListening();
    }
  }

  Future<void> _checkStatus() async {
    try {
      _isGpsEnabled = await Geolocator.isLocationServiceEnabled();
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _status = GpsStatus.permissionDenied;
        notifyListeners();
        return;
      }
      if (!_isGpsEnabled) {
        _status = GpsStatus.unavailable;
        notifyListeners();
        return;
      }
      _status = GpsStatus.available;
      notifyListeners();
    } catch (e) {
      _status = GpsStatus.error;
      notifyListeners();
    }
  }

  void _startListening() {
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1,
      ),
    ).listen(
      (pos) {
        _position = pos;
        _status = GpsStatus.available;
        notifyListeners();
      },
      onError: (e) {
        _status = GpsStatus.error;
        notifyListeners();
      },
    );
  }

  Future<void> refresh() async {
    await _checkStatus();
    if (_status == GpsStatus.available) {
      _startListening();
      try {
        _position = await Geolocator.getLastKnownPosition();
        notifyListeners();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }
}
