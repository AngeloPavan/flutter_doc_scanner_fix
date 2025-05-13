import 'package:flutter/services.dart';

import 'flutter_doc_scanner_platform_interface.dart';

class FlutterDocScanner {
  Future<String?> getPlatformVersion() {
    return FlutterDocScannerPlatform.instance.getPlatformVersion();
  }

  static const MethodChannel _channel = MethodChannel('flutter_doc_scanner');

  static Future<Uint8List?> scanDocument() async {
    final Uint8List? bytes = await _channel.invokeMethod('scanDocument');
    return bytes;
  }
}
