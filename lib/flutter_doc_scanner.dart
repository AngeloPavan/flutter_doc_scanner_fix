import 'package:flutter/services.dart';

import 'flutter_doc_scanner_platform_interface.dart';

class FlutterDocScanner {
  Future<String?> getPlatformVersion() {
    return FlutterDocScannerPlatform.instance.getPlatformVersion();
  }

  static const MethodChannel _channel = MethodChannel('flutter_doc_scanner');

  static Future<List<Uint8List>?> scanDocument() async {
    final List<Uint8List>? bytes = await _channel.invokeListMethod<Uint8List>('scanDocument');
    return bytes;
  }

  // static Future<List<Uint8List>?> scanDocumentIOS() async {
  //   final List<Uint8List>? bytes = await _channel.invokeListMethod<Uint8List>('scanDocument');
  //   return bytes;
  // }
}
