import Flutter
import UIKit
import VisionKit
import AVFoundation

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
        // let scannerVC = VNDocumentCameraViewController()
        // scannerVC.delegate = self
        // UIApplication.shared.keyWindow?.rootViewController?.present(scannerVC, animated: true, completion: nil)
        let scannerVC = AutoScanViewController()
    scannerVC.result = self.result
    UIApplication.shared.keyWindow?.rootViewController?.present(scannerVC, animated: true)
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

public class AutoScanViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var photoOutput: AVCapturePhotoOutput!
    var isCapturing = false
    var result: FlutterResult?

    let sequenceHandler = VNSequenceRequestHandler()

    override public func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            result?(FlutterError(code: "CAMERA_ERROR", message: "Errore fotocamera", details: nil))
            return
        }

        captureSession.addInput(input)

        // Preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        // Photo output
        photoOutput = AVCapturePhotoOutput()
        captureSession.addOutput(photoOutput)

        // Video output per analisi dei frame
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(videoOutput)

        captureSession.startRunning()
    }

    // Vision - detect rectangles
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isCapturing else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectRectanglesRequest { [weak self] (request, error) in
            guard let self = self else { return }

            if let results = request.results as? [VNRectangleObservation], let _ = results.first {
                self.isCapturing = true
                self.capturePhoto()
            }
        }

        request.minimumConfidence = 0.8
        request.maximumObservations = 1

        try? sequenceHandler.perform([request], on: pixelBuffer)
    }

    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    public func photoOutput(_ output: AVCapturePhotoOutput,
                            didFinishProcessingPhoto photo: AVCapturePhoto,
                            error: Error?) {
        captureSession.stopRunning()
        dismiss(animated: true)

        if let error = error {
            result?(FlutterError(code: "PHOTO_ERROR", message: error.localizedDescription, details: nil))
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            result?(FlutterError(code: "DATA_ERROR", message: "Impossibile ottenere i dati della foto", details: nil))
            return
        }

        result?(FlutterStandardTypedData(bytes: imageData))
    }
}