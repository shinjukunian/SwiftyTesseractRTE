//
//  VideoManager.swift
//  SwiftyTesseractRTE
//
//  Created by Steven Sherry on 3/19/18.
//  Copyright © 2018 Steven Sherry. All rights reserved.
//

import AVFoundation
import UIKit

class VideoManager: AVManager, ZoomableAVManager {
  
    private let sessionQueue: DispatchQueue
    private let mediaType: AVMediaType
    
    var videoOrientation: AVCaptureVideoOrientation{
        didSet{
            if let videoPreviewLayerConnection = self.previewLayer.connection {
                videoPreviewLayerConnection.videoOrientation = videoOrientation
            }
        }
    }
    
    private let cameraPosition: AVCaptureDevice.Position

    private(set) var previewLayer: AVCaptureVideoPreviewLayer
    private(set) var captureSession: AVCaptureSession

    var cameraQuality: AVCaptureSession.Preset {
    didSet {
            suspendQueueAndConfigureSession()
        }
    }

    weak var delegate: AVCaptureVideoDataOutputSampleBufferDelegate? {
    didSet {
            suspendQueueAndConfigureSession()
        }
    }
    
    var minZoomFactor: CGFloat{
        return (self.captureSession.inputs.first as? AVCaptureDeviceInput)?.device.minAvailableVideoZoomFactor ?? 1
    }
    
    var maxZoomFactor: CGFloat{
        return (self.captureSession.inputs.first as? AVCaptureDeviceInput)?.device.maxAvailableVideoZoomFactor ?? 1
    }
    
    
    fileprivate var photoCaptureDelegate:PhotoCaptureDelegate?

    init(previewLayer: AVCaptureVideoPreviewLayer = AVCaptureVideoPreviewLayer(),
       captureSession: AVCaptureSession = AVCaptureSession(),
       sessionQueue: DispatchQueue = DispatchQueue(queueLabel: .session),
       cameraPosition: AVCaptureDevice.Position = .back,
       cameraQuality: AVCaptureSession.Preset = .medium,
       videoOrientation: AVCaptureVideoOrientation = .portrait,
       mediaType: AVMediaType = .video) {

        self.previewLayer = previewLayer
        self.captureSession = captureSession
        self.sessionQueue = sessionQueue
        self.cameraPosition = cameraPosition
        self.cameraQuality = cameraQuality
        self.videoOrientation = videoOrientation
        self.mediaType = mediaType

        self.previewLayer.session = self.captureSession
        self.previewLayer.videoGravity = .resizeAspectFill
    }
        
    
    private func isAuthorized(for mediaType: AVMediaType) -> Bool {
            switch AVCaptureDevice.authorizationStatus(for: mediaType) {
            case .authorized:
              return true
            case .notDetermined:
              requestPermission(for: mediaType)
              return false
            default:
              return false
        }
    }

    private func requestPermission(for mediaType: AVMediaType) {
        sessionQueue.suspend()
        AVCaptureDevice.requestAccess(for: mediaType) { [weak self] granted in
          guard let strongSelf = self else { return }
          if granted {
            strongSelf.configure(strongSelf.captureSession)
            strongSelf.sessionQueue.resume()
          }
        }
    }

    private func configure(_ captureSession: AVCaptureSession) {
        guard isAuthorized(for: mediaType) else { return }
        captureSession.beginConfiguration()
        captureSession.sessionPreset = cameraQuality
        configureInput(for: captureSession)

        let connection = configureOutputConnection(for: captureSession)
        configureOutput(for: connection)
        captureSession.commitConfiguration()
    }

    private func configureInput(for captureSession: AVCaptureSession) {
        guard
          let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: mediaType, position: cameraPosition),
          let captureDeviceInput = try? AVCaptureDeviceInput(device: captureDevice),
          captureSession.canAddInput(captureDeviceInput)
        else { return }

        captureSession.addInput(captureDeviceInput)
    }

    private func configureOutputConnection(for captureSession: AVCaptureSession) -> AVCaptureConnection? {
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(delegate, queue: DispatchQueue(queueLabel: .videoOutput))

        guard captureSession.canAddOutput(videoOutput) else { return nil }
        captureSession.addOutput(videoOutput)
        
        let photoOutput = AVCapturePhotoOutput()
        photoOutput.isHighResolutionCaptureEnabled = true
        
        guard captureSession.canAddOutput(photoOutput) else { return nil}
        captureSession.sessionPreset = .photo
        captureSession.addOutput(photoOutput)

        return videoOutput.connection(with: mediaType)
    }

    private func configureOutput(for captureConnection: AVCaptureConnection?) {
        guard
          let captureConnection = captureConnection,
          captureConnection.isVideoOrientationSupported
        else { return }

        captureConnection.videoOrientation = videoOrientation
    }

    private func suspendQueueAndConfigureSession() {
        sessionQueue.suspend()
        configure(captureSession)
        sessionQueue.resume()
    }
    
    var focusPointOfInterest: CGPoint{
        get{
            if let input =  self.captureSession.inputs.first as? AVCaptureDeviceInput{
                let pt=self.previewLayer.layerPointConverted(fromCaptureDevicePoint: input.device.focusPointOfInterest)
                return pt
            }
            return .zero
        }
        set{
            guard let input =  self.captureSession.inputs.first as? AVCaptureDeviceInput, input.device.isFocusModeSupported(.continuousAutoFocus) else {return}
            try? input.device.lockForConfiguration()
            defer {
                input.device.unlockForConfiguration()
            }
            let devicePT = self.previewLayer.captureDevicePointConverted(fromLayerPoint: newValue)
            input.device.focusPointOfInterest = devicePT
            input.device.autoFocusRangeRestriction = .near
            input.device.focusMode = .continuousAutoFocus
            
        }
    }
    
    var zoomFactor: CGFloat{
        set{
            guard newValue > self.minZoomFactor,
                newValue < self.maxZoomFactor,
                let input =  self.captureSession.inputs.first as? AVCaptureDeviceInput else {return}
            try? input.device.lockForConfiguration()
            defer {
                input.device.unlockForConfiguration()
            }
            input.device.videoZoomFactor = newValue
        }
        get{
            return (self.captureSession.inputs.first as? AVCaptureDeviceInput)?.device.videoZoomFactor ?? 1
        }
    }
}

extension VideoManager: CapturingAVManager{
    func captureImage(context:CIContext, handler:@escaping (UIImage?)->Void){
        guard let photoOutput=self.captureSession.outputs.compactMap({return $0 as? AVCapturePhotoOutput}).first  else {return}
        let types=photoOutput.availablePhotoPixelFormatTypes
        let photoSettings=AVCapturePhotoSettings(format: [kCVPixelBufferPixelFormatTypeKey as String:types[0]])
//        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
//            photoSettings = AVCapturePhotoSettings(format:
//                [AVVideoCodecKey: AVVideoCodecType.hevc])
//        } else {
//            photoSettings = AVCapturePhotoSettings()
//        }
        
        photoSettings.isAutoStillImageStabilizationEnabled = photoOutput.isStillImageStabilizationSupported
        let d=PhotoCaptureDelegate(context: context, handler: {[weak self] image in
            self?.photoCaptureDelegate=nil
            handler(image)
        })
        photoOutput.capturePhoto(with: photoSettings, delegate: d)
        self.photoCaptureDelegate=d
        
    }
}


class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate{
    typealias PhotoCaptureDelegateHandler = (UIImage?)->Void
    let handler:PhotoCaptureDelegateHandler
    let context:CIContext
    
    init(context:CIContext, handler:@escaping PhotoCaptureDelegateHandler) {
        self.handler=handler
        self.context=context
        super.init()
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let pixelBuffer=photo.pixelBuffer else{
            handler(nil)
            return
        }
        
        let ciImage=CIImage(cvPixelBuffer: pixelBuffer, options: [CIImageOption.applyOrientationProperty:true])
        let transform=ciImage.orientationTransform(for: CGImagePropertyOrientation.right)
        let corrected=ciImage.transformed(by: transform)
        
        guard let cgCorr=context.createCGImage(corrected, from: corrected.extent) else{
            handler(nil)
            return
        }
        
        let uiCorr=UIImage(cgImage: cgCorr)
        handler(uiCorr)
    }
}
