resQ

resQ is an offline-first emergency communication and coordination platform designed for situations where internet access, mobile networks, or central servers are unavailable.

The app enables nearby devices to form a Bluetooth Low Energy mesh network, allowing users to communicate, coordinate, and share critical information without relying on existing communication infrastructure. It also integrates on-device AI so assistance remains available even when completely offline.

---

Features

Bluetooth Mesh Communication

- Decentralized Bluetooth Low Energy mesh networking
- Multi-hop message relay using flood routing
- Automatic peer discovery
- Direct messaging between nearby users
- Presence announcements
- Offline operation with no servers or internet

Emergency Features

- One-tap SOS broadcasting
- GPS location sharing
- Live latitude and longitude
- Compass and heading
- Battery and power saver status
- Flashlight control
- Sensor dashboard

Offline AI

- Fully on-device inference using llama.cpp
- User-imported GGUF models
- Streaming responses
- No cloud APIs
- No internet required
- Privacy-first inference

Shared Coordination

- Conflict-free offline synchronization using Yjs CRDTs
- Automatic state convergence after reconnection
- Reliable chunked document resynchronization
- Persistent shared rescue information

Security

- X25519 identity keys
- Ed25519 packet signing
- Secure key storage using Android Keystore
- Privacy-focused Bluetooth advertising

---

Technology Stack

Frontend

- Flutter
- Dart

Native Android

- Kotlin
- Android MethodChannels
- JNI

AI

- llama.cpp
- GGUF models
- GGML
- OpenMP
- ARM CPU runtime optimizations

Networking

- Bluetooth Low Energy
- GATT Central + Peripheral
- Flood Routing
- CRDT Synchronization (Yjs)

Security

- X25519
- Ed25519
- SHA-256
- Flutter Secure Storage

Device Integration

- Geolocator
- Sensors Plus
- Battery Plus
- Permission Handler

---

Architecture

Flutter UI
      │
      ▼
MeshController
      │
 ┌───────────────┬────────────────┐
 │               │                │
 ▼               ▼                ▼
BLE Mesh      AI Engine       Device Services
 │             │               │
 ▼             ▼               ▼
Bluetooth   llama.cpp      GPS / Compass /
Mesh        (GGUF)         Battery / Sensors

---

How It Works

1. Users install resQ on nearby Android devices.
2. Devices automatically discover one another using Bluetooth Low Energy.
3. A decentralized mesh network forms without requiring internet access.
4. Messages, SOS alerts, and shared rescue information propagate through nearby devices using multi-hop routing.
5. The on-device AI assistant continues working entirely offline using a locally imported GGUF model.

---

Current Status

Implemented:

- Bluetooth mesh networking
- Peer discovery
- Multi-hop routing
- Direct messaging
- SOS broadcasting
- GPS location sharing
- Live sensor dashboard
- Offline AI with llama.cpp
- GGUF model import
- Streaming AI responses
- CRDT-based shared synchronization
- Android native optimizations
- Secure identity management

In Progress:

- End-to-end encryption
- Reliable delivery for all mesh messages
- Background execution improvements
- Persistent chat history
- Media and file sharing

---

Running the Project

Prerequisites

- Flutter SDK
- Android SDK
- Android NDK
- CMake
- Android device running Android 11 (API 30) or later

Build

flutter pub get
flutter run -d <device_id>

or build a debug APK:

flutter build apk --debug

---

Permissions

resQ requests only the permissions required for its offline functionality:

- Bluetooth Scan
- Bluetooth Connect
- Bluetooth Advertise
- Fine Location
- Coarse Location
- Camera (flashlight control)

---

Supported Platform

- Android (Primary platform)

---

Roadmap

- End-to-end encrypted messaging
- Reliable acknowledgements for all mesh packets
- Persistent chat database
- Media and file transfer
- Group conversations
- Offline OCR for scanned documents
- Expanded AI capabilities
- Improved battery optimisation

---

License

This project is developed for research, experimentation, and hackathon participation. Licensing will be defined before public release.
