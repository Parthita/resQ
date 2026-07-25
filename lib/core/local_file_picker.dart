import 'package:flutter/services.dart';

/// Android's system picker returns a copied, readable local file path.
/// The permanent import is handled by the document/model repositories.
class LocalFilePicker {
  static const _channel = MethodChannel('resq.file_picker');

  static Future<String?> pickSingle({required List<String> extensions}) {
    return _channel.invokeMethod<String>('pickSingle', <String, Object>{
      'extensions': extensions,
    });
  }
}
