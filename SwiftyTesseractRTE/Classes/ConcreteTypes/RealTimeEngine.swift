//
//  RealTimeEngine.swift
//  SwiftyTesseractRTE
//
//  Created by Steven Sherry on 3/5/18.
//  Copyright © 2018 Steven Sherry. All rights reserved.
//

import SwiftyTesseract
import AVFoundation
import Vision


/// A class to perform real-time optical character recognition
public class RealTimeEngine: NSObject, SceneStability {
    
    public enum RecognitionState: Equatable, CustomStringConvertible{
        case sceneUnstable
        case recognizing
        case stablyRecognized(text:String)
        case unknown
        
        public var description: String{
            switch self {
            case .recognizing:
                return "Recognizing..."
            case .sceneUnstable:
                return "Scene Unstable"
            case .stablyRecognized(let text):
                return "Recognized \(text)"
            case .unknown:
                return "unknown"
            }
        }
    }
  
      // MARK: - Private variables
      /// Used as a container to hold the last N frames OCR results to verify stability of recognition accuracy,
      /// where N is defined by the raw value of the RecognitionReliability set by the user during initialization.
    private var recognitionQueue: RecognitionQueue<String>
      
      // MARK: - Private constants
    private let swiftyTesseract: SwiftyTesseract
    private let imageProcessor: AVSampleProcessor
    private let avManager: AVManager
    lazy var sequenceRequestHandler = VNSequenceRequestHandler()
    
    internal var transpositionHistoryPoints: [CGPoint] = [ ]
    var previousPixelBuffer: CVPixelBuffer?
       
    var currentlyAnalyzedPixelBuffer: CVPixelBuffer?
    var currentFrame=0
    
    var deviceOrientation : UIDeviceOrientation = UIDevice.current.orientation{
        didSet{
            if let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation){
                self.avManager.videoOrientation = newVideoOrientation
            }
        }
    }
    
    lazy var ciContext:CIContext={
        guard let device=MTLCreateSystemDefaultDevice() else{fatalError()}
        let ctx=CIContext(mtlDevice: device)
        return ctx
    }()


      
      // MARK: - Public variables
      /// The region within the AVCaptureVideoPreviewLayer that OCR is to be performed. If using a UIView to
      /// define the region of interest this **must** be assigned as the UIView's frame and
      /// be a subview of the the AVCaptureVideoPreviewLayer's parent view.
    public var regionOfInterest: CGRect?{
        didSet{
            if let roi=regionOfInterest{
                self.avManager.focusPointOfInterest = CGPoint(x: roi.midX, y: roi.midY)
            }
        }
    }
    
    var zoomScale:CGFloat{
        set{
            if let z=self.avManager as? ZoomableAVManager{
                z.zoomFactor = newValue
            }
        }
        get{
            if let z=self.avManager as? ZoomableAVManager{
                return z.zoomFactor
            }
            else{
                return 1
            }
        }
    }

      /// Sets recognition to be running or not. Default is **true**. Setting the value to false will
      /// allow the preview to be active without processing incoming video frames.
      /// If it is not desired for recognition to be active after initialization, set this
      /// value to false immediately after creating an instance of SwiftyTesseractRTE
    public var recognitionIsActive: Bool = true
      
      /// The quality of the previewLayer video session. The default is set to .medium. Changing this
      /// setting will only affect how the video is displayed to the user and will not affect the
      /// results of OCR if set above `.medium`. Setting the quality higher will result in decreased performance.
    public var cameraQuality: AVCaptureSession.Preset {
        get {
            return avManager.cameraQuality
        }
        set {
            avManager.cameraQuality = newValue
        }
    }
      
      /// Action to be performed after successful recognition
    public var handler: ((RecognitionState) -> ())?

      // MARK: Initializers

      /// Primary Initializer - Uses SwiftyTesseractRTE defaults
      /// - Parameters:
      ///   - swiftyTesseract:    Instance of SwiftyTesseract
      ///   - desiredReliability: The desired reliability of the recognition results.
      ///   - cameraQuality:      The desired camera quality output to be seen by the end user. The default is `.medium`.
      ///   Anything higher than `.medium` has no impact on recognition reliability
      ///   - onRecognitionComplete: Action to be performed after successful recognition
      public convenience init(swiftyTesseract: SwiftyTesseract,
                              desiredReliability: RecognitionReliability,
                              cameraQuality: AVCaptureSession.Preset = .medium,
                              onRecognitionComplete: ((RecognitionState) -> ())? = nil) {
        
        let recognitionQueue = RecognitionQueue<String>(desiredReliability: desiredReliability)
        let videoManager = VideoManager(cameraQuality: cameraQuality)
        
        self.init(swiftyTesseract: swiftyTesseract,
                  recognitionQueue: recognitionQueue,
                  avManager: videoManager,
                  onRecognitionComplete: onRecognitionComplete)
      }

      /// - Parameters:
      ///   - swiftyTesseract:    Instance of SwiftyTesseract
      ///   - desiredReliability: The desired reliability of the recognition results.
      ///   - imageProcessor:     Performs conversion and processing from `CMSampleBuffer` to `UIImage`
      ///   - cameraQuality:      The desired camera quality output to be seen by the end user. The default is .medium.
      ///                         Anything higher than .medium has no impact on recognition reliability
      ///   - onRecognitionComplete: Action to be performed after successful recognition
      public convenience init(swiftyTesseract: SwiftyTesseract,
                              desiredReliability: RecognitionReliability,
                              imageProcessor: AVSampleProcessor,
                              cameraQuality: AVCaptureSession.Preset = .medium,
                              onRecognitionComplete: ((RecognitionState) -> ())? = nil) {
        
        let recognitionQueue = RecognitionQueue<String>(desiredReliability: desiredReliability)
        let avManager = VideoManager(cameraQuality: cameraQuality)
        
        self.init(swiftyTesseract: swiftyTesseract,
                  recognitionQueue: recognitionQueue,
                  imageProcessor: imageProcessor,
                  avManager: avManager,
                  onRecognitionComplete: onRecognitionComplete)
      }
      
      /// - Parameters:
      ///   - swiftyTesseract: Instance of SwiftyTesseract
      ///   - desiredReliability: The desired reliability of the recognition results.
      ///   - avManager: Manages the AVCaptureSession
      ///   - onRecognitionComplete: Action to be performed after successful recognition
      public convenience init(swiftyTesseract: SwiftyTesseract,
                              desiredReliability: RecognitionReliability,
                              avManager: AVManager,
                              onRecognitionComplete: ((RecognitionState) -> ())? = nil) {
        
        let recognitionQueue = RecognitionQueue<String>(desiredReliability: desiredReliability)
        
        self.init(swiftyTesseract: swiftyTesseract,
                  recognitionQueue: recognitionQueue,
                  avManager: avManager,
                  onRecognitionComplete: onRecognitionComplete)
      }
      
      /// - Parameters:
      ///   - swiftyTesseract: Instance of SwiftyTesseract
      ///   - desiredReliability: The desired reliability of the recognition results.
      ///   - imageProcessor: Performs conversion and processing from `CMSampleBuffer` to `UIImage`
      ///   - avManager: Manages the AVCaptureSession
      ///   - onRecognitionComplete: Action to be performed after successful recognition
      public convenience init(swiftyTesseract: SwiftyTesseract,
                              desiredReliability: RecognitionReliability,
                              imageProcessor: AVSampleProcessor,
                              avManager: AVManager,
                              onRecognitionComplete: ((RecognitionState) -> ())? = nil) {
        
        let recognitionQueue = RecognitionQueue<String>(desiredReliability: desiredReliability)
        
        self.init(swiftyTesseract: swiftyTesseract,
                  recognitionQueue: recognitionQueue,
                  imageProcessor: imageProcessor,
                  avManager: avManager,
                  onRecognitionComplete: onRecognitionComplete)
      }
      
      
      init(swiftyTesseract: SwiftyTesseract,
           recognitionQueue: RecognitionQueue<String>,
           imageProcessor: AVSampleProcessor = ImageProcessor(),
           avManager: AVManager,
           onRecognitionComplete: ((RecognitionState) -> ())? = nil) {
        
        self.swiftyTesseract = swiftyTesseract
        self.recognitionQueue = recognitionQueue
        self.imageProcessor = imageProcessor
        self.avManager = avManager
        self.handler = onRecognitionComplete
        super.init()
        
        if type(of: avManager) == VideoManager.self {
          self.avManager.delegate = self
        }
      }
      
      // MARK: - Public functions
      /// Stops the camera preview
      public func stopPreview() {
        avManager.captureSession.stopRunning()
      }
    
    public func tearDown(){
        avManager.delegate=nil
        avManager.captureSession.stopRunning()
    }
      
      /// Restarts the camera preview
      public func startPreview() {
        avManager.captureSession.startRunning()
      }
      
      /// Binds SwiftyTesseractRTE AVCaptureVideoPreviewLayer to UIView.
      ///
      /// - Parameter view: The view to present the live preview
      public func bindPreviewLayer(to view: UIView) {
        if !(view.layer.sublayers?.contains(where: {$0 is AVCaptureVideoPreviewLayer}) ?? false){
            view.layer.insertSublayer(avManager.previewLayer, at: 0)
        }
        avManager.previewLayer.frame = view.bounds
      }
    }
      // Helper functions
    extension RealTimeEngine {
      private func performOCR(on sampleBuffer: CMSampleBuffer) {
        guard
          recognitionIsActive,
          let croppedImage = convertAndCrop(sampleBuffer)
        else { return }
        
        enqueueAndEvalutateRecognitionResults(from: croppedImage)
      }
      
      private func convertAndCrop(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard
            let processedImage = imageProcessor.prepareUIImage(from: sampleBuffer, orientation: CGImagePropertyOrientation(deviceOrientation: self.deviceOrientation)),
            let regionOfInterest = regionOfInterest
        else { return nil }
        
        return imageProcessor.crop(processedImage,
                                   toBoundsOf: regionOfInterest,
                                   containedIn: avManager.previewLayer)
      }
      
      private func enqueueAndEvalutateRecognitionResults(from image: UIImage) {
        let result=swiftyTesseract.performOCR(on: image)
        switch result {
        case .success(let recognizedString):
            self.recognitionQueue.enqueue(recognizedString)
        case .failure(let errror):
            print(errror.localizedDescription)
        }
        guard self.recognitionQueue.allValuesMatch,
               let recognitionResult = self.recognitionQueue.dequeue()
             else { return }
          
        if let handler=self.handler{
            handler(.stablyRecognized(text: recognitionResult))
        }
        
        self.recognitionQueue.clear()
      }
}

extension RealTimeEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
  
  /// Provides conformance to `AVCaptureVideoDataOutputSampleBufferDelegate`
  /// - Parameters:
  ///   - output: `AVCaptureOutput`
  ///   - sampleBuffer: `CMSampleBuffer`
  ///   - connection: `AVCaptureConnection`
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let stability=self.assessStability(sampleBuffer: sampleBuffer)
        if stability == .steady && self.recognitionIsActive{
            performOCR <=< sampleBuffer
            if let handler=self.handler{
                handler(.recognizing)
            }
            
        }
        else{
            if let handler=self.handler{
                handler(.sceneUnstable)
            }
        }
        
    }
  
}
