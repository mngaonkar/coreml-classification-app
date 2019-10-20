//
//  ImageCapture.swift
//  rock-finder
//
//  Created by Mahadev Gaonkar on 20/10/19.
//  Copyright © 2019 Mahadev Gaonkar. All rights reserved.
//

import SwiftUI
import MapKit
import AVFoundation
import Vision

struct ImageCapture: UIViewControllerRepresentable {
    
    typealias UIViewControllerType = ViewController
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<ImageCapture>) -> ImageCapture.UIViewControllerType {
        return ViewController()
    }
    
    func updateUIViewController(_ uiViewController: ImageCapture.UIViewControllerType, context: UIViewControllerRepresentableContext<ImageCapture>) {
    }
    
}

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let output = AVCaptureVideoDataOutput()
    var bufferSize: CGSize = .zero
    var rootLayer: CALayer! = nil
    private var previewLayer: AVCaptureVideoPreviewLayer! = nil
    let overlayLayer = CALayer()
    private let outputQueue = DispatchQueue(label: "VideoDataOutput", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    private var requests = [VNRequest]()
    private var rockFound: Bool = false
    private var debounceCount: Int = 0
    
    public func exifOrientationFromDeviceOrientation() -> CGImagePropertyOrientation {
        let curDeviceOrientation = UIDevice.current.orientation
        let exifOrientation: CGImagePropertyOrientation
        
        switch curDeviceOrientation {
        case UIDeviceOrientation.portraitUpsideDown:  // Device oriented vertically, home button on the top
            exifOrientation = .left
        case UIDeviceOrientation.landscapeLeft:       // Device oriented horizontally, home button on the right
            exifOrientation = .upMirrored
        case UIDeviceOrientation.landscapeRight:      // Device oriented horizontally, home button on the left
            exifOrientation = .down
        case UIDeviceOrientation.portrait:            // Device oriented vertically, home button on the bottom
            exifOrientation = .up
        default:
            exifOrientation = .up
        }
        return exifOrientation
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // print("frame dropped")
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let exifOrientation = exifOrientationFromDeviceOrientation()
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: exifOrientation, options: [:])
        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print(error)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .blue
        
        print("checking camera authorization")
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: // The user has previously granted access to the camera.
                self.setupCapture()
                print("camera access granted")
                self.setupVision()
                self.startCapture()
                break;
            
            case .notDetermined: // The user has not yet been asked for camera access.
                print("camera access not determined")
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted {
                        self.setupCapture()
                    }
                }
                break;
        
            case .denied: // The user has previously denied access.
                print("camera access denied")
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted {
                        self.setupCapture()
                    }
                }
                break;

            case .restricted: // The user can't grant access due to restrictions.
                return
            
            default:
            print("unknown error")
        }
    }
    
    func startCapture(){
        session.startRunning()

    }
    
    func stopCapture(){
        session.stopRunning()
    }
    
    func drawResponseOnUI(_ results: [Any]){
        for observation in results where observation is VNClassificationObservation{
            CATransaction.begin()
            CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
            guard let validObservation = observation as? VNClassificationObservation else {
                continue
            }
            
            self.overlayLayer.sublayers = nil
            let textLayer = CATextLayer()
            textLayer.string = ""
            textLayer.alignmentMode = .center
            textLayer.contentsScale = 2.0
            textLayer.foregroundColor = UIColor.yellow.cgColor
            //textLayer.backgroundColor = UIColor.red.cgColor
            textLayer.position = CGPoint(x: self.previewLayer.frame.midX, y: self.previewLayer.frame.midY)
            textLayer.bounds = self.view.bounds
            //textLayer.name = "classification"
            //let formattedString = NSMutableAttributedString(string: String(format: "\(validObservation.identifier)\nConfidence:  %.2f", validObservation.confidence))
            //let largeFont = UIFont(name: "Helvetica", size: 44.0)!
            //formattedString.addAttributes([NSAttributedString.Key.font: largeFont], range: NSRange(location: 0, length: validObservation.identifier.count))
            //textLayer.string = formattedString
            
            if validObservation.confidence > 0.80 {
                if validObservation.identifier == "rock"{
                    debounceCount += 1
                    if debounceCount > 3 {
                        debounceCount = 3
                    }
                
                    print("object detected is \(validObservation.identifier) with confidence \(validObservation.confidence)")
                } else {
                    debounceCount -= 1
                    if debounceCount < 0 {
                        debounceCount = 0
                    }
                    print("Good to go!")
                    //textLayer.string = "Good to go!"
                }
            } else {
                // print("unknown object")
            }
            
            if debounceCount == 3 {
                textLayer.string = "Rock found!"
            }
            else if debounceCount == 0 {
                textLayer.string = "Good to go!"
            }
            
            self.overlayLayer.addSublayer(textLayer)
            CATransaction.commit()
        }
    }
    
    func setupVision() {
        guard let url = Bundle.main.url(forResource: "rock-data", withExtension: "mlmodelc") else {
            print("model file missing")
            return
        }
        
        do {
            let model = try VNCoreMLModel(for: MLModel(contentsOf: url))
            let request = VNCoreMLRequest(model: model) { (request, error) in
                DispatchQueue.main.async(execute: {
                    // perform all the UI updates on the main queue
                    if let results = request.results {
                        self.drawResponseOnUI(results)
                    }
                })
            }
            self.requests = [request]
        } catch let error as NSError{
            print(error)
        }
    }
    
    func setupCapture(){
        var deviceInput: AVCaptureDeviceInput!
        
        let videoDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back)
        
        do {
            deviceInput = try AVCaptureDeviceInput(device: videoDevices.devices[0])
        } catch {
            print("device initialization failed \(error)")
            return
        }
        
        session.beginConfiguration()
        // session.sessionPreset = .vga640x480
        
        guard session.canAddInput(deviceInput) else {
            print("could not add video device to session")
            session.commitConfiguration()
            return
        }
        session.addInput(deviceInput)
        
        if session.canAddOutput(output) {
            session.addOutput(output)
            // Add a video data output
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
            output.setSampleBufferDelegate(self, queue: outputQueue)
            session.commitConfiguration()
        } else {
            print("Could not add video data output to the session")
            session.commitConfiguration()
            return
        }
                
        let captureConnection = output.connection(with: .video)
        captureConnection?.isEnabled = true
        
        do {
            try  videoDevices.devices[0].lockForConfiguration()
            let dimensions = CMVideoFormatDescriptionGetDimensions((videoDevices.devices[0].activeFormat.formatDescription))
                bufferSize.width = CGFloat(dimensions.width)
                bufferSize.height = CGFloat(dimensions.height)
            videoDevices.devices[0].unlockForConfiguration()
        } catch {
            print(error)
        }
        
        session.commitConfiguration()
        
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        previewLayer.masksToBounds = true
        previewLayer.backgroundColor = UIColor.clear.cgColor
        previewLayer.frame = self.view.frame
        //overlayLayer.position = CGPoint(x: self.previewLayer.frame.midX, y: self.previewLayer.frame.midY)
        //self.previewLayer.addSublayer(overlayLayer)
        //self.view.layer.addSublayer(overlayLayer)
        self.view.layer.addSublayer(previewLayer)
        self.view.layer.addSublayer(overlayLayer)
    }
}

struct ImageCapture_Previews: PreviewProvider {
    static var previews: some View {
        ImageCapture()
    }
}
