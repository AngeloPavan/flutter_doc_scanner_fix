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
        guard scan.pageCount > 0 else {
            controller.dismiss(animated: true, completion: nil)
            result?(FlutterError(code: "NO_DOCUMENT", message: "No document was scanned", details: nil))
            return
        }

        var imagesData: [FlutterStandardTypedData] = []

        for i in 0..<scan.pageCount {
            let image = scan.imageOfPage(at: i)
            if let data = image.jpegData(compressionQuality: 0.8) {
                imagesData.append(FlutterStandardTypedData(bytes: data))
            } else {
                // Se una pagina fallisce, la saltiamo o notifichiamo errore
                // Qui decidiamo di continuare con le altre pagine
                print("❌ Impossibile convertire la pagina \(i) in JPEG.")
            }
        }

        controller.dismiss(animated: true) {
            // Torniamo l'array di immagini al Dart side
            self.result?(imagesData)
        }
    }

    public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        controller.dismiss(animated: true, completion: nil)
        result?(FlutterError(code: "SCANNER_ERROR", message: error.localizedDescription, details: nil))
    }
}