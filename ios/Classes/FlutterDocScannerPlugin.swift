import UIKit
import AVFoundation
import Vision
import Flutter
import CoreImage


public class FlutterDocScannerPlugin: NSObject, FlutterPlugin {
    private var result: FlutterResult?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_doc_scanner", binaryMessenger: registrar.messenger())
        let instance = FlutterDocScannerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "scanDocument" {
            self.result = result
            DispatchQueue.main.async {
                if #available(iOS 13.0, *) {
                    let vc = OneShotDocumentScannerViewController()
                    vc.delegate = self
                    guard let root = UIApplication.shared.windows.first?.rootViewController else {
                        result(FlutterError(code: "NO_UI", message: "Unable to get root view controller", details: nil))
                        return
                    }
                    root.present(vc, animated: true)
                } else {
                    result(FlutterError(code: "UNSUPPORTED_VERSION", message: "Requires iOS 13 or newer", details: nil))
                }
            }
        } else {
            result(FlutterMethodNotImplemented)
        }
    }
}

extension FlutterDocScannerPlugin: OneShotDocumentScannerDelegate {
    public func documentScanner(_ scanner: UIViewController, didFinishWith data: Data) {
        scanner.dismiss(animated: true) {
            self.result?(FlutterStandardTypedData(bytes: data))
        }
    }
    public func documentScanner(_ scanner: UIViewController, didFailWith error: Error) {
        scanner.dismiss(animated: true) {
            self.result?(FlutterError(code: "SCANNER_ERROR", message: error.localizedDescription, details: nil))
        }
    }
}