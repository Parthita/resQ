# resQ

> Offline-first emergency communication powered by Bluetooth Mesh and on-device AI.

resQ is an Android application that enables communication during disasters, remote travel, or situations where internet and cellular networks are unavailable. It creates a Bluetooth Low Energy (BLE) mesh network between nearby devices, allowing messages, SOS alerts, and shared information to travel across multiple hops without requiring servers or cloud infrastructure.

The app also integrates an on-device AI assistant using **llama.cpp**, allowing users to access AI capabilities completely offline while keeping their data private.

---

## Features

### Bluetooth Mesh Networking

- Automatic peer discovery
- Multi-hop message relay
- Direct messaging
- Group communication
- Offline operation without internet
- Flood-routing based message propagation

### Emergency Features

- One-tap SOS broadcasting
- GPS location sharing
- Nearby device discovery
- Live battery status
- Compass
- Flashlight control
- Device sensor dashboard

### Offline AI

- On-device inference using **llama.cpp**
- Supports GGUF models
- Streaming responses
- No cloud APIs
- Fully offline
- Privacy-first AI assistant

### Collaboration

- CRDT-based offline synchronization
- Shared notes and rescue coordination
- Automatic conflict resolution
- Eventual consistency between devices

### Security

- Secure local identity
- Packet signing
- Encrypted local key storage
- No user data stored on servers

---

## Technology Stack

### Frontend

- Flutter
- Dart

### Native Android

- Kotlin
- Android MethodChannels
- JNI

### AI

- llama.cpp
- GGUF
- GGML
- OpenMP

### Networking

- Bluetooth Low Energy (BLE)
- GATT Central
- GATT Peripheral
- Multi-hop Mesh Routing

### Synchronization

- Yjs CRDT

### Device Integration

- Geolocator
- Sensors Plus
- Battery Plus
- Permission Handler

### Security

- X25519
- Ed25519
- SHA-256
- Flutter Secure Storage

---

## Architecture

```text
                 Flutter UI
                      │
        ┌─────────────┴─────────────┐
        │                           │
        ▼                           ▼
 Bluetooth Mesh               AI Assistant
        │                           │
        ▼                           ▼
 Mesh Controller            llama.cpp (JNI)
        │                           │
        ▼                           ▼
 Bluetooth LE              Local GGUF Model
        │
        ▼
 Nearby Devices
```

---

## Project Structure

```text
lib/
├── core/
│   ├── ai/
│   ├── bluetooth/
│   ├── mesh/
│   ├── services/
│   └── models/
├── screens/
├── widgets/
└── main.dart

android/
└── Native Android
    ├── Kotlin
    ├── JNI
    └── llama.cpp
```

---

## Getting Started

### Prerequisites

- Flutter SDK
- Android SDK
- Android NDK
- CMake
- Android device running Android 11 or later

### Clone the Repository

```bash
git clone <repository-url>
cd resQ
```

### Install Dependencies

```bash
flutter pub get
```

### Run the Application

```bash
flutter run
```

### Build Release APK

```bash
flutter build apk --release
```

---

## Permissions

The application requests only the permissions required for offline communication and emergency features.

- Bluetooth Scan
- Bluetooth Connect
- Bluetooth Advertise
- Fine Location
- Coarse Location
- Camera (Flashlight)

---

## Supported Platform

| Platform | Status |
|----------|--------|
| Android | ✅ Supported |
| iOS | 🚧 Planned |
| Web | ❌ Not Supported |
| Windows | ❌ Not Supported |
| Linux | Development Only |
| macOS | ❌ Not Supported |

---

## Roadmap

- End-to-end encrypted messaging
- Reliable message acknowledgements
- Media and file sharing over mesh
- Improved background mesh networking
- Offline OCR
- Expanded AI capabilities
- Battery optimisations
- Cross-platform support

---

## Contributing

Contributions are welcome. Please open an issue before submitting major feature changes so they can be discussed first.

---

## License

This project was developed as part of a hackathon and is currently intended for research and educational purposes.
