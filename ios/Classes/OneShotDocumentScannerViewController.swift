import UIKit
import AVFoundation
import Vision
import CoreImage

@available(iOS 13.0, *)
public protocol OneShotDocumentScannerDelegate: AnyObject {
    func documentScanner(_ scanner: UIViewController, didFinishWith data: Data)
    func documentScanner(_ scanner: UIViewController, didFailWith error: Error)
}

@available(iOS 13.0, *)
public class OneShotDocumentScannerViewController: UIViewController {
    // AVCapture
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!

    // Vision
    private var sequenceHandler = VNSequenceRequestHandler()
    private var lastObservation: VNRectangleObservation?
    private var stableCount = 0
    private let requiredStableCount = 5

    // UI
    private let shutterButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("📷", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 36)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    public weak var delegate: OneShotDocumentScannerDelegate?

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupUI()
    }

    private func setupCamera() {
        session.beginConfiguration()
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            delegate?.documentScanner(self, didFailWith: NSError(domain: "camera", code: -1, userInfo: nil))
            return
        }
        session.addInput(input)
        session.addOutput(photoOutput)

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "VideoDataOutput"))
        session.addOutput(videoOutput)
        session.commitConfiguration()

        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)

        session.startRunning()
    }

    private func setupUI() {
        view.addSubview(shutterButton)
        NSLayoutConstraint.activate([
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
        shutterButton.addTarget(self, action: #selector(manualCapture), for: .touchUpInside)
    }

    @objc private func manualCapture() {
        capturePhoto()
    }

    private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.isAutoStillImageStabilizationEnabled = true
        photoOutput.capturePhoto(with: settings, delegate: self)
        session.stopRunning()
    }

    private func processCapturedImage(_ image: UIImage) {
        let handler = VNImageRequestHandler(cgImage: image.cgImage!, options: [:])
        do {
            if #available(iOS 15.0, *) {
                let segReq = VNDetectDocumentSegmentationRequest()
                try handler.perform([segReq])
                guard let docObs = segReq.results?.first as? VNRectangleObservation else {
                    throw NSError(domain: "vision", code: -1, userInfo: nil)
                }
                applyPerspectiveCorrection(for: docObs, on: image)
            } else {
                let rectReq = VNDetectRectanglesRequest()
                rectReq.minimumConfidence = 0.8
                rectReq.minimumAspectRatio = 0.5
                rectReq.maximumObservations = 1
                try handler.perform([rectReq])
                guard let docObs = rectReq.results?.first as? VNRectangleObservation else {
                    throw NSError(domain: "vision", code: -1, userInfo: nil)
                }
                applyPerspectiveCorrection(for: docObs, on: image)
            }
        } catch {
            delegate?.documentScanner(self, didFailWith: error)
        }
    }

    private func applyPerspectiveCorrection(for docObs: VNRectangleObservation, on image: UIImage) {
        let ciImage = CIImage(cgImage: image.cgImage!)
        let w = image.size.width
        let h = image.size.height

        let topLeft = docObs.topLeft.scaled(to: w, h: h)
        let topRight = docObs.topRight.scaled(to: w, h: h)
        let bottomLeft = docObs.bottomLeft.scaled(to: w, h: h)
        let bottomRight = docObs.bottomRight.scaled(to: w, h: h)

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            delegate?.documentScanner(self, didFailWith: NSError(domain: "vision", code: -1, userInfo: nil))
            return
        }
        filter.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")
        filter.setValue(ciImage, forKey: kCIInputImageKey)

        let context = CIContext()
        guard let outputCI = filter.outputImage,
              let cgImg = context.createCGImage(outputCI, from: outputCI.extent) else {
            delegate?.documentScanner(self, didFailWith: NSError(domain: "vision", code: -1, userInfo: nil))
            return
        }
        let corrected = UIImage(cgImage: cgImg)
        if let data = corrected.jpegData(compressionQuality: 0.8) {
            delegate?.documentScanner(self, didFinishWith: data)
        } else {
            delegate?.documentScanner(self, didFailWith: NSError(domain: "vision", code: -1, userInfo: nil))
        }
    }
}

// MARK: - Stability Detection

@available(iOS 13.0, *)
extension OneShotDocumentScannerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let rectReq = VNDetectRectanglesRequest { [weak self] req, _ in
            guard let self = self,
                  let obs = req.results?.first as? VNRectangleObservation else {
                self?.stableCount = 0
                return
            }
            if let last = self.lastObservation, obs.isSimilar(to: last, threshold: 0.02) {
                self.stableCount += 1
            } else {
                self.stableCount = 0
            }
            self.lastObservation = obs
            if self.stableCount >= self.requiredStableCount {
                self.capturePhoto()
            }
        }
        rectReq.minimumConfidence = 0.8
        rectReq.minimumAspectRatio = 0.5
        rectReq.maximumObservations = 1
        try? sequenceHandler.perform([rectReq], on: pixelBuffer)
    }
}


// MARK: - Similarity & Scaling Helpers

@available(iOS 13.0, *)
extension VNRectangleObservation {
    func isSimilar(to other: VNRectangleObservation, threshold: Float) -> Bool {
        let dxs = [abs(topLeft.x - other.topLeft.x), abs(topRight.x - other.topRight.x),
                   abs(bottomLeft.x - other.bottomLeft.x), abs(bottomRight.x - other.bottomRight.x)]
        let dys = [abs(topLeft.y - other.topLeft.y), abs(topRight.y - other.topRight.y),
                   abs(bottomLeft.y - other.bottomLeft.y), abs(bottomRight.y - other.bottomRight.y)]
        return dxs.max()! < CGFloat(threshold) && dys.max()! < CGFloat(threshold)
    }
}

extension CGPoint {
    fileprivate func scaled(to w: CGFloat, h: CGFloat) -> CGPoint {
        return CGPoint(x: x * w, y: (1 - y) * h)
    }
}

// MARK: - Photo Capture Delegate


@available(iOS 13.0, *)
extension OneShotDocumentScannerViewController: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput,
                            didFinishProcessingPhoto photo: AVCapturePhoto,
                            error: Error?) {
        if let err = error {
            delegate?.documentScanner(self, didFailWith: err)
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            delegate?.documentScanner(self, didFailWith: NSError(domain: "capture", code: -1, userInfo: nil))
            return
        }
        processCapturedImage(image)
    }
}