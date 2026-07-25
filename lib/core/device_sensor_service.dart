import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

enum SensorStatus { loading, available, unavailable, error }

class DeviceSensorService extends ChangeNotifier {
  final MethodChannel _platform = const MethodChannel('resq.platform');

  StreamSubscription<MagnetometerEvent>? _magnetometerSub;
  StreamSubscription<AccelerometerEvent>? _accelerometerSub;
  StreamSubscription<BarometerEvent>? _barometerSub;

  SensorStatus _compassStatus = SensorStatus.loading;
  SensorStatus _pressureStatus = SensorStatus.loading;
  SensorStatus _flashlightStatus = SensorStatus.loading;

  double _rawHeading = 0;
  double _smoothHeading = 0;
  double _pressureValue = 0;
  bool _flashlightOn = false;

  double _ax = 0, _ay = 0, _az = 0;
  double _mx = 0, _my = 0, _mz = 0;

  static const double _smoothing = 0.15;

  SensorStatus get compassStatus => _compassStatus;
  SensorStatus get pressureStatus => _pressureStatus;
  SensorStatus get flashlightStatus => _flashlightStatus;

  double get heading => _smoothHeading;
  double get pressureValue => _pressureValue;
  bool get isFlashlightOn => _flashlightOn;

  String get cardinalDirection {
    if (_compassStatus != SensorStatus.available) return '--';
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((_smoothHeading + 22.5) / 45.0).floor() % 8;
    return dirs[index];
  }

  Future<void> init() async {
    _startMagnetometer();
    _startAccelerometer();
    _startBarometer();
    await _checkFlashlight();
  }

  void _startMagnetometer() {
    try {
      _magnetometerSub?.cancel();
      _magnetometerSub = magnetometerEventStream(
        samplingPeriod: const Duration(milliseconds: 100),
      ).listen(
        (event) {
          _mx = event.x;
          _my = event.y;
          _mz = event.z;
          _computeHeading();
          _compassStatus = SensorStatus.available;
        },
        onError: (_) {
          _compassStatus = SensorStatus.unavailable;
          notifyListeners();
        },
      );
    } catch (_) {
      _compassStatus = SensorStatus.unavailable;
      notifyListeners();
    }
  }

  void _startAccelerometer() {
    try {
      _accelerometerSub?.cancel();
      _accelerometerSub = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 100),
      ).listen((event) {
        _ax = event.x;
        _ay = event.y;
        _az = event.z;
      }, onError: (_) {});
    } catch (_) {}
  }

  void _computeHeading() {
    final normA = sqrt(_ax * _ax + _ay * _ay + _az * _az);
    if (normA < 1e-6) return;
    final gx = _ax / normA, gy = _ay / normA, gz = _az / normA;

    final ex = _my * gz - _mz * gy;
    final ey = _mz * gx - _mx * gz;
    final ez = _mx * gy - _my * gx;

    final normE = sqrt(ex * ex + ey * ey + ez * ez);
    if (normE < 1e-6) return;

    final invX = gy * (ez / normE) - gz * (ey / normE);
    final invY = gz * (ex / normE) - gx * (ez / normE);

    _rawHeading = atan2(invX, invY) * 180 / pi;
    if (_rawHeading < 0) _rawHeading += 360;

    _smoothHeading =
        _smoothing * _rawHeading + (1 - _smoothing) * _smoothHeading;
    if (_smoothHeading < 0) _smoothHeading += 360;
    if (_smoothHeading >= 360) _smoothHeading -= 360;

    notifyListeners();
  }

  void _startBarometer() {
    try {
      _barometerSub?.cancel();
      _barometerSub = barometerEventStream(
        samplingPeriod: const Duration(milliseconds: 500),
      ).listen(
        (event) {
          _pressureValue = event.pressure;
          _pressureStatus = SensorStatus.available;
          notifyListeners();
        },
        onError: (_) {
          _pressureStatus = SensorStatus.unavailable;
          notifyListeners();
        },
      );
      Timer(const Duration(seconds: 2), () {
        if (_pressureStatus == SensorStatus.loading) {
          _pressureStatus = SensorStatus.unavailable;
          notifyListeners();
        }
      });
    } catch (_) {
      _pressureStatus = SensorStatus.unavailable;
      notifyListeners();
    }
  }

  Future<void> _checkFlashlight() async {
    try {
      final available =
          await _platform.invokeMethod<bool>('isFlashlightAvailable') ?? false;
      _flashlightStatus =
          available ? SensorStatus.available : SensorStatus.unavailable;
      _flashlightOn = false;
      notifyListeners();
    } catch (_) {
      _flashlightStatus = SensorStatus.unavailable;
      notifyListeners();
    }
  }

  Future<void> toggleFlashlight() async {
    if (_flashlightStatus != SensorStatus.available) return;
    try {
      if (_flashlightOn) {
        await _platform.invokeMethod('flashlightOff');
      } else {
        await _platform.invokeMethod('flashlightOn');
      }
      _flashlightOn = !_flashlightOn;
      notifyListeners();
    } catch (_) {
    }
  }

  @override
  void dispose() {
    _magnetometerSub?.cancel();
    _accelerometerSub?.cancel();
    _barometerSub?.cancel();
    super.dispose();
  }
}
