import 'dart:async';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';

import 'bitchat_link.dart';
import 'constants.dart';

/// Real BLE transport using bluetooth_low_energy (v6.2.1), dual-role.
///
/// Model: GATT server + client on one device.
///   - Peripheral role: advertise the bitchat service UUID; expose one
///     characteristic with read | write | writeWithoutResponse | notify.
///     Incoming peer writes arrive on [PeripheralManager.characteristicWriteRequested];
///     we push our outgoing frames to subscribed centrals via
///     [PeripheralManager.notifyCharacteristic].
///   - Central role: scan for the service; on discovery connect, discover GATT,
///     subscribe to the characteristic (notify state true), then write our
///     outgoing frames with [GATTCharacteristicWriteType.withoutResponse].
///
/// NOTE: this class only executes on a real device/emulator. On the host it
/// compiles and is analyzable, but CentralManager/PeripheralManager throw
/// UnimplementedError. The mesh layer sits behind [BitchatLink], so all higher
/// logic (flood router, fragmentation, sync tunnel) is tested via [MockBitchatLink].
/// Thrown by [BleLink.start] when the BLE adapter is powered off, so the UI
/// can tell the user to enable Bluetooth instead of failing silently.
class BluetoothOffException implements Exception {
  const BluetoothOffException();

  @override
  String toString() => 'Bluetooth is powered off';
}

class BleLink implements BitchatLink {
  BleLink({this.useMainnet = false});

  final bool useMainnet;

  final CentralManager _central = CentralManager();
  final PeripheralManager _peripheral = PeripheralManager();

  final StreamController<Uint8List> _received =
      StreamController<Uint8List>.broadcast();
  final StreamController<LinkPeer> _peersController =
      StreamController<LinkPeer>.broadcast();
  final Map<String, Peripheral> _connected = {};
  GATTCharacteristic? _centralChar;
  Peripheral? _centralPeripheral;
  final List<Central> _subscribedCentrals = [];
  bool _advertising = false;
  bool _scanning = false;

  late final UUID _serviceUuid;
  late final UUID _charUuid;
  late final GATTService _service;
  late final GATTCharacteristic _mutableChar;

  @override
  Stream<Uint8List> get received => _received.stream;

  @override
  Stream<LinkPeer> get peers => _peersController.stream;

  @override
  bool get isPoweredOn =>
      _central.state == BluetoothLowEnergyState.poweredOn;

  @override
  Future<void> start() async {
    // React to adapter state changes (e.g. auto-request authorization on
    // Android when the system reports 'unauthorized').
    _central.stateChanged.listen((args) {
      if (args.state == BluetoothLowEnergyState.unauthorized) {
        _central.authorize();
      }
    });

    // Authoritative adapter check: must be powered on to advertise/scan.
    if (!isPoweredOn) {
      debugPrint('[bitchat:ble] adapter not powered on — refusing to start');
      throw const BluetoothOffException();
    }

    _serviceUuid = UUID.fromString(useMainnet
        ? BitchatConstants.serviceUuidMainnet
        : BitchatConstants.serviceUuidTestnet);
    _charUuid = UUID.fromString(BitchatConstants.characteristicUuid);

    // --- peripheral setup ---
    _mutableChar = GATTCharacteristic.mutable(
      uuid: _charUuid,
      properties: const [
        GATTCharacteristicProperty.read,
        GATTCharacteristicProperty.write,
        GATTCharacteristicProperty.writeWithoutResponse,
        GATTCharacteristicProperty.notify,
      ],
      permissions: const [
        GATTCharacteristicPermission.read,
        GATTCharacteristicPermission.write,
      ],
      descriptors: const [],
    );
    _service = GATTService(
      uuid: _serviceUuid,
      isPrimary: true,
      includedServices: const [],
      characteristics: [_mutableChar],
    );

    _peripheral.characteristicWriteRequested.listen(_onWriteRequested);
    _peripheral.characteristicNotifyStateChanged.listen((args) {
      if (args.state) {
        _subscribedCentrals.add(args.central);
      } else {
        _subscribedCentrals.remove(args.central);
      }
    });
    await _peripheral.addService(_service);
    await _peripheral.startAdvertising(Advertisement(
      name: 'resQ',
      serviceUUIDs: [_serviceUuid],
    ));
    _advertising = true;
    debugPrint('[bitchat:ble] advertising service $_serviceUuid as "resQ"');

    // --- central setup ---
    _central.discovered.listen(_onDiscovered);
    _central.characteristicNotified.listen(_onNotified);
    await _central.startDiscovery(serviceUUIDs: [_serviceUuid]);
    _scanning = true;
    debugPrint('[bitchat:ble] scanning for service $_serviceUuid');
  }

  void _onWriteRequested(GATTCharacteristicWriteRequestedEventArgs args) {
    debugPrint('[bitchat:ble] peripheral received write (${args.request.value.length} bytes)');
    if (!_received.isClosed) _received.add(Uint8List.fromList(args.request.value));
    _peripheral.respondWriteRequest(args.request);
  }

  void _onNotified(GATTCharacteristicNotifiedEventArgs args) {
    debugPrint('[bitchat:ble] central received notify (${args.value.length} bytes)');
    if (!_received.isClosed) _received.add(Uint8List.fromList(args.value));
  }

  Future<void> _onDiscovered(DiscoveredEventArgs args) async {
    final peripheral = args.peripheral;
    final id = peripheral.uuid.toString();
    if (_connected.containsKey(id)) return;
    debugPrint('[bitchat:ble] discovered $id ("${args.advertisement.name}")');
    // surface "discovered" so the UI can show it before the GATT link is up
    if (!_peersController.isClosed) {
      _peersController.add(LinkPeer(
        id: id,
        name: args.advertisement.name,
        connected: false,
      ));
    }
    try {
      await _central.connect(peripheral);
      final services = await _central.discoverGATT(peripheral);
      final svc = services.firstWhere((s) => s.uuid == _serviceUuid);
      final ch = svc.characteristics.firstWhere((c) => c.uuid == _charUuid);
      await _central.setCharacteristicNotifyState(peripheral, ch, state: true);
      _centralPeripheral = peripheral;
      _centralChar = ch;
      _connected[id] = peripheral;
      if (!_peersController.isClosed) {
        _peersController.add(LinkPeer(
          id: id,
          name: args.advertisement.name,
          connected: true,
        ));
      }
      debugPrint('[bitchat:ble] CONNECTED to $id — subscribed, ready to exchange');
    } on Object catch (e) {
      debugPrint('[bitchat:ble] connect failed: $e');
    }
  }

  @override
  Future<bool> send(Uint8List frame) async {
    var delivered = false;
    // peripheral side: notify every subscribed central
    for (final central in _subscribedCentrals) {
      try {
        await _peripheral.notifyCharacteristic(central, _mutableChar,
            value: frame);
        delivered = true;
      } on Object {
        // a disconnected central; drop it lazily
      }
    }
    // central side: write to the connected peripheral
    if (_centralPeripheral != null && _centralChar != null) {
      try {
        await _central.writeCharacteristic(
          _centralPeripheral!,
          _centralChar!,
          value: frame,
          type: GATTCharacteristicWriteType.withoutResponse,
        );
        delivered = true;
      } on Object {
        // ignore
      }
    }
    return delivered;
  }

  @override
  Future<void> stop() async {
    if (_scanning) await _central.stopDiscovery();
    if (_advertising) await _peripheral.stopAdvertising();
    for (final p in _connected.values) {
      try {
        await _central.disconnect(p);
      } on Object {
        // ignore
      }
    }
    _connected.clear();
    _subscribedCentrals.clear();
    // NOTE: do NOT close _received / _peersController here. A discovery or
    // notify callback may still be in flight; closing now throws
    // "Cannot add new events after calling close". The controllers are only
    // closed in dispose(), when the link is truly discarded.
  }

  /// Permanently release the link's streams. Call when the owning controller
  /// is disposed (and the link will not be reused).
  Future<void> dispose() async {
    if (!_received.isClosed) await _received.close();
    if (!_peersController.isClosed) await _peersController.close();
  }
}
