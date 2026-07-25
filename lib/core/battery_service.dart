import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum BatteryStatus { loading, available, unavailable, error }

class BatteryService extends ChangeNotifier {
  final Battery _battery = Battery();
  final MethodChannel _platform = const MethodChannel('resq.platform');

  BatteryStatus _status = BatteryStatus.loading;
  int _level = 0;
  bool _isCharging = false;
  bool _isPowerSave = false;
  DateTime _lastUpdated = DateTime.now();
  StreamSubscription? _batterySubscription;

  BatteryStatus get status => _status;
  int get level => _level;
  bool get isCharging => _isCharging;
  bool get isPowerSave => _isPowerSave;
  DateTime get lastUpdated => _lastUpdated;

  Future<void> init() async {
    await refresh();
    try {
      _batterySubscription = _battery.onBatteryStateChanged.listen((state) {
        _isCharging = state == BatteryState.charging ||
            state == BatteryState.full;
        _lastUpdated = DateTime.now();
        notifyListeners();
      });
    } catch (_) {
    }
    Timer.periodic(const Duration(seconds: 60), (_) => refresh());
  }

  Future<void> refresh() async {
    try {
      _level = await _battery.batteryLevel;
      _isPowerSave = await _platform.invokeMethod('isPowerSaveMode') ?? false;
      _lastUpdated = DateTime.now();
      _status = BatteryStatus.available;
    } catch (e) {
      _status = BatteryStatus.error;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _batterySubscription?.cancel();
    super.dispose();
  }
}
