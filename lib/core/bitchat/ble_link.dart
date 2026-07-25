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
  final Set<String> _connecting = <String>{};
  final Set<String> _inboundCentrals = <String>{};
  GATTCharacteristic? _centralChar;
  Peripheral? _centralPeripheral;
  final List<Central> _subscribedCentrals = [];
  bool _advertising = false;
  bool _scanning = false;
  Timer? _scanHeartbeat;

  late final UUID _serviceUuid;
  late final UUID _charUuid;
  late final GATTService _service;
  late final GATTCharacteristic _mutableChar;

  @override
  Stream<Uint8List> get received => _received.stream;

  @override
  Stream<LinkPeer> get peers => _peersController.stream;

  @override
  bool get isPoweredOn => _central.state == BluetoothLowEnergyState.poweredOn;

  @override
  Future<void> start() async {
    // React to adapter state changes (e.g. auto-request authorization on
    // Android when the system reports 'unauthorized').
    _central.stateChanged.listen((args) {
      if (args.state == BluetoothLowEnergyState.unauthorized) {
        unawaited(_central.authorize());
      }
    });
    _peripheral.stateChanged.listen((args) {
      if (args.state == BluetoothLowEnergyState.unauthorized) {
        unawaited(_peripheral.authorize());
      }
    });
    // These are the authoritative disconnect callbacks.  Relying on a failed
    // write leaves the People UI showing a stale "Connected" state until the
    // next scan result arrives.
    _central.connectionStateChanged.listen((args) {
      final id = args.peripheral.uuid.toString();
      if (args.state == ConnectionState.disconnected) {
        _connecting.remove(id);
        _connected.remove(id);
        if (identical(_centralPeripheral, args.peripheral)) {
          _centralPeripheral = null;
          _centralChar = null;
        }
      }
      if (!_peersController.isClosed) {
        _peersController.add(
          LinkPeer(id: id, connected: args.state == ConnectionState.connected),
        );
      }
    });
    _peripheral.connectionStateChanged.listen((args) {
      final id = args.central.uuid.toString();
      if (args.state == ConnectionState.connected) {
        _inboundCentrals.add(id);
        debugPrint(
          '[bitchat:ble] inbound central connected $id; suppressing outbound races',
        );
      }
      if (args.state == ConnectionState.disconnected) {
        _subscribedCentrals.remove(args.central);
        _inboundCentrals.remove(id);
      }
      if (!_peersController.isClosed) {
        _peersController.add(
          LinkPeer(
            id: args.central.uuid.toString(),
            connected: args.state == ConnectionState.connected,
          ),
        );
      }
    });

    // The managers commonly begin as `unknown`, especially immediately after
    // the runtime permission prompt. Wait for the native callback instead of
    // treating that transient state as Bluetooth being off.
    await _waitForPoweredOn();

    _serviceUuid = UUID.fromString(
      useMainnet
          ? BitchatConstants.serviceUuidMainnet
          : BitchatConstants.serviceUuidTestnet,
    );
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
        debugPrint('[bitchat:ble] central subscribed ${args.central.uuid}');
        // A central has completed the GATT notify subscription.  This is the
        // first moment the peripheral can reliably send a packet back, so
        // surface a fresh connected event for the controller to announce its
        // signed BitChat identity (matching BitChat's didSubscribe flow).
        if (!_peersController.isClosed) {
          _peersController.add(
            LinkPeer(id: args.central.uuid.toString(), connected: true),
          );
        }
      } else {
        _subscribedCentrals.remove(args.central);
        debugPrint('[bitchat:ble] central unsubscribed ${args.central.uuid}');
      }
    });
    await _peripheral.addService(_service);
    try {
      await _peripheral.startAdvertising(
        Advertisement(name: 'resQ', serviceUUIDs: [_serviceUuid]),
      );
      _advertising = true;
      debugPrint('[bitchat:ble] advertising service $_serviceUuid as "resQ"');
    } on Object catch (error, stackTrace) {
      // Android may reject LE advertising when the controller has exhausted
      // advertiser slots or does not support the peripheral role. Scanning is
      // still useful: this phone can join a nearby resQ advertiser as central.
      // Do not take the entire mesh down for a peripheral-only limitation.
      _advertising = false;
      debugPrint(
        '[bitchat:ble] advertising unavailable; continuing scan: '
        '$error\n$stackTrace',
      );
    }

    // --- central setup ---
    _central.discovered.listen(_onDiscovered);
    _central.characteristicNotified.listen(_onNotified);
    _central.mtuChanged.listen((args) {
      debugPrint('[bitchat:ble] MTU updated peer=${args.peripheral.uuid} mtu=${args.mtu}');
    });
    _peripheral.mtuChanged.listen((args) {
      debugPrint('[bitchat:ble] MTU updated central=${args.central.uuid} mtu=${args.mtu}');
    });
    debugPrint(
      '[bitchat:ble] scan filter UUID = $_serviceUuid '
      '(advertise UUID = $_serviceUuid, char = $_charUuid)',
    );
    await _central.startDiscovery(serviceUUIDs: [_serviceUuid]);
    _scanning = true;
    debugPrint(
      '[bitchat:ble] scanning started; '
      'if no "discovered" lines appear, either no peer advertises '
      '$_serviceUuid or the OS filtered them out',
    );
    // Heartbeat: proves the scan loop is alive even when nothing is found.
    _scanHeartbeat?.cancel();
    _scanHeartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_scanning) {
        debugPrint(
          '[bitchat:ble] scan heartbeat: scanning=$_scanning '
          'connectedPeers=${_connected.length}',
        );
      }
    });
  }

  Future<void> _waitForPoweredOn() async {
    if (_central.state == BluetoothLowEnergyState.unauthorized) {
      await _central.authorize();
    }
    if (_peripheral.state == BluetoothLowEnergyState.unauthorized) {
      await _peripheral.authorize();
    }
    if (isPoweredOn) return;

    final ready = Completer<void>();
    late final StreamSubscription subscription;
    subscription = _central.stateChanged.listen((args) {
      if (args.state == BluetoothLowEnergyState.unauthorized) {
        unawaited(_central.authorize());
      }
      if (args.state == BluetoothLowEnergyState.poweredOn &&
          !ready.isCompleted) {
        ready.complete();
      }
    });
    try {
      await ready.future.timeout(const Duration(seconds: 6));
    } on TimeoutException {
      debugPrint('[bitchat:ble] adapter did not become powered on');
      throw const BluetoothOffException();
    } finally {
      await subscription.cancel();
    }
  }

  void _onWriteRequested(GATTCharacteristicWriteRequestedEventArgs args) {
    debugPrint(
      '[bitchat:ble] peripheral received write from=${args.central.uuid} '
      'bytes=${args.request.value.length}',
    );
    if (!_received.isClosed) {
      _received.add(Uint8List.fromList(args.request.value));
    }
    _peripheral.respondWriteRequest(args.request);
  }

  void _onNotified(GATTCharacteristicNotifiedEventArgs args) {
    debugPrint(
      '[bitchat:ble] central received notify from=${args.peripheral.uuid} '
      'bytes=${args.value.length}',
    );
    if (!_received.isClosed) _received.add(Uint8List.fromList(args.value));
  }

  Future<void> _onDiscovered(DiscoveredEventArgs args) async {
    final peripheral = args.peripheral;
    final id = peripheral.uuid.toString();
    if (_connected.containsKey(id) || _connecting.contains(id)) {
      debugPrint(
        '[bitchat:ble] skip discovery $id (already connected/connecting)',
      );
      return;
    }

    // Only talk to real resQ peers. The OS scan filter may deliver every BLE
    // device in range (Android often reports empty advertisedServices even for
    // matches), so we validate here: a peer must either advertise our service
    // UUID or be named "resQ". Without this we'd connect() to random devices
    // and flood the log with GATT 257/133 failures.
    final advertised = args.advertisement.serviceUUIDs;
    final isResQPeer =
        advertised.contains(_serviceUuid) || args.advertisement.name == 'resQ';
    if (!isResQPeer) {
      debugPrint(
        '[bitchat:ble] ignore non-resQ device '
        '$id name="${args.advertisement.name}" services=$advertised',
      );
      return;
    }

    // If the other phone has already dialled this device, use that stable
    // peripheral link instead of racing it with a second central connection.
    if (_inboundCentrals.isNotEmpty) {
      debugPrint(
        '[bitchat:ble] skip outbound $id (inbound link already exists)',
      );
      return;
    }
    debugPrint(
      '[bitchat:ble] discovered resQ peer $id rssi=${args.rssi} '
      'advertisedServices=$advertised',
    );
    // surface "discovered" so the UI can show it before the GATT link is up
    if (!_peersController.isClosed) {
      _peersController.add(
        LinkPeer(id: id, name: args.advertisement.name, connected: false),
      );
    }
    // Must be set before the first await: Android emits repeated discoveries
    // while connect/discoverGATT is pending.
    _connecting.add(id);
    try {
      await _central.connect(peripheral);
      // The BitChat fragment payload is up to 469 bytes. Without negotiating
      // MTU, Android silently breaks it into 20-byte ATT writes and the
      // receiver mistakes each piece for a complete BitChat fragment.
      try {
        final mtu = await _central.requestMTU(peripheral, mtu: 517);
        debugPrint('[bitchat:ble] requested MTU=517 peer=$id negotiated=$mtu');
      } on Object catch (error) {
        debugPrint('[bitchat:ble] MTU request failed peer=$id error=$error');
        rethrow;
      }
      final services = await _central.discoverGATT(peripheral);
      final svc = services.firstWhere((s) => s.uuid == _serviceUuid);
      final ch = svc.characteristics.firstWhere((c) => c.uuid == _charUuid);
      await _central.setCharacteristicNotifyState(peripheral, ch, state: true);
      _centralPeripheral = peripheral;
      _centralChar = ch;
      _connected[id] = peripheral;
      if (!_peersController.isClosed) {
        _peersController.add(
          LinkPeer(id: id, name: args.advertisement.name, connected: true),
        );
      }
      debugPrint(
        '[bitchat:ble] CONNECTED to $id — subscribed, ready to exchange',
      );
    } on Object catch (e) {
      debugPrint('[bitchat:ble] connect failed id=$id error=$e');
      // Cancel the failed GATT client so Android does not retain one of its
      // very limited per-process client slots (the source of status 133).
      try {
        await _central.disconnect(peripheral);
      } on Object {
        // It may never have reached the connected state; nothing to release.
      }
    } finally {
      _connecting.remove(id);
    }
  }

  @override
  Future<bool> send(Uint8List frame) async {
    var delivered = false;
    // peripheral side: notify every subscribed central
    for (final central in _subscribedCentrals) {
      try {
        await _peripheral.notifyCharacteristic(
          central,
          _mutableChar,
          value: frame,
        );
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
    debugPrint(
      '[bitchat:ble] send bytes=${frame.length} delivered=$delivered '
      'subscribers=${_subscribedCentrals.length} centralLink=${_centralPeripheral != null}',
    );
    return delivered;
  }

  @override
  Future<void> stop() async {
    _scanHeartbeat?.cancel();
    if (_scanning) await _central.stopDiscovery();
    if (_advertising) await _peripheral.stopAdvertising();
    // Iterate a snapshot: disconnect() can fire a connection-state callback
    // that mutates _connected/_subscribedCentrals, which would throw
    // "Concurrent modification during iteration" if we walked the live map.
    for (final p in List.of(_connected.values)) {
      try {
        await _central.disconnect(p);
      } on Object {
        // ignore
      }
    }
    _connected.clear();
    _connecting.clear();
    _inboundCentrals.clear();
    _subscribedCentrals.clear();
    // NOTE: do NOT close _received / _peersController here. A discovery or
    // notify callback may still be in flight; closing now throws
    // "Cannot add new events after calling close". The controllers are only
    // closed in dispose(), when the link is truly discarded.
  }

  /// Permanently release the link's streams. Call when the owning controller
  /// is disposed (and the link will not be reused).
  @override
  Future<void> dispose() async {
    if (!_received.isClosed) await _received.close();
    if (!_peersController.isClosed) await _peersController.close();
  }
}
