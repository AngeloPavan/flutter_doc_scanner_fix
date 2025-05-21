import Flutter
import UIKit
import VisionKit

public class FlutterDocScannerPlugin: NSObject, FlutterPlugin {
    
    var result: FlutterResult?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_doc_scanner", binaryMessenger: registrar.messenger())
        let instance = FlutterDocScannerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "scanDocument" {
            self.result = result

            // 🔹 Verifica la versione di iOS
            if #available(iOS 13.0, *) {
                startDocumentScanner()
            } else {
                result(FlutterError(code: "UNSUPPORTED_VERSION", message: "VisionKit non supportato su iOS < 13.0", details: nil))
            }
        } else {
            result(FlutterMethodNotImplemented)
        }
    }
    
    @available(iOS 13.0, *)  // 🔹 Evita errori di compilazione
    private func startDocumentScanner() {
        let scannerVC = VNDocumentCameraViewController()
        scannerVC.delegate = self
        UIApplication.shared.keyWindow?.rootViewController?.present(scannerVC, animated: true, completion: nil)
    }
}

// 🔹 Implementazione del delegate fuori dalla classe principale
@available(iOS 13.0, *)
extension FlutterDocScannerPlugin: VNDocumentCameraViewControllerDelegate {
    public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        if scan.pageCount > 0 {
            let image = scan.imageOfPage(at: 0)
            if let imageData = image.jpegData(compressionQuality: 0.8) {
                controller.dismiss(animated: true, completion: nil)
                result?(FlutterStandardTypedData(bytes: imageData))
            } else {
                result?(FlutterError(code: "IMAGE_ERROR", message: "Could not convert image to bytes", details: nil))
            }
        } else {
            result?(FlutterError(code: "NO_DOCUMENT", message: "No document was scanned", details: nil))
        }
    }

    public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        controller.dismiss(animated: true, completion: nil)
        result?(FlutterError(code: "SCANNER_ERROR", message: error.localizedDescription, details: nil))
    }
}
