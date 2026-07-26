import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistence for the user's mesh nickname.
///
/// Reuses the app's existing [FlutterSecureStorage] dependency (no new
/// package) so this is purely additive. The nickname is low-sensitivity UI
/// metadata; the keystore is already wired for the mesh identity, so reusing
/// it keeps the dependency surface unchanged.
///
/// The mesh itself (MeshController) stays Flutter-free and testable: it only
/// exposes a settable [nickname] field. This store is the UI-side loader that
/// feeds a persisted value into the controller before start().
class NicknameStore {
  NicknameStore._();

  static const _storage = FlutterSecureStorage();
  static const _key = 'resq.mesh.nickname.v1';

  /// Load the saved nickname, or null if none set (caller falls back to the
  /// controller's default 'resQ').
  static Future<String?> load() async {
    try {
      return await _storage.read(key: _key);
    } on Object {
      // Keystore unavailable (headless tests, unsupported platform): behave as
      // if unset rather than crashing the UI.
      return null;
    }
  }

  /// Persist the nickname. Empty/whitespace is treated as "clear" so the
  /// controller reverts to its default.
  static Future<void> save(String? value) async {
    try {
      final trimmed = value?.trim();
      if (trimmed == null || trimmed.isEmpty) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: trimmed);
      }
    } on Object {
      // Persistence best-effort; non-fatal.
    }
  }
}
