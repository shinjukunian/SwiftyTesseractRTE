//
//  SceneStability.swift
//  KanjiLookup
//
//  Created by Morten Bertz on 2020/05/10.
//  Copyright © 2020 telethon k.k. All rights reserved.
//

import Foundation
import Vision
import AVFoundation


enum SceneStabilityState: Equatable, CustomStringConvertible{
    
    case steady
    case notSteady
    
    var description: String{
        switch self {
        case .notSteady:
            return "Not Steady"
        case .steady:
            return "Steady"
        }
    }
}


protocol SceneStability:class {
    var transpositionHistoryPoints: [CGPoint] {set get}
    var maximumHistoryLength : Int {get}
    var previousPixelBuffer: CVPixelBuffer? {get set}
       
    var currentlyAnalyzedPixelBuffer: CVPixelBuffer? {get set}
    var currentFrame : Int {get set}
    var sequenceRequestHandler : VNSequenceRequestHandler {get}
    var ciContext:CIContext {get}
    
    func assessStability(sampleBuffer: CMSampleBuffer)->SceneStabilityState
}


extension SceneStability{
    
    @inlinable
    var maximumHistoryLength:Int{
        return 15
    }
    
    internal func sceneStabilityAchieved() -> Bool {
        // Determine if we have enough evidence of stability.
        if transpositionHistoryPoints.count == maximumHistoryLength {
            // Calculate the moving average.
            var movingAverage: CGPoint = CGPoint.zero
            for currentPoint in transpositionHistoryPoints {
                movingAverage.x += currentPoint.x
                movingAverage.y += currentPoint.y
            }
            let distance = abs(movingAverage.x) + abs(movingAverage.y)
            if distance < 100 {
                return true
            }
          
        }
        return false
    }
    
    internal func resetTranspositionHistory() {
        transpositionHistoryPoints.removeAll()
    }
    
    internal func recordTransposition(_ point: CGPoint) {
        transpositionHistoryPoints.append(point)
        
        if transpositionHistoryPoints.count > maximumHistoryLength {
            transpositionHistoryPoints.removeFirst()
        }
    }
    
    func assessStability(sampleBuffer: CMSampleBuffer)->SceneStabilityState{
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return .notSteady
        }
        self.currentFrame+=1
        var requestHandlerOptions: [VNImageOption: AnyObject] = [VNImageOption.ciContext:self.ciContext]
        let cameraIntrinsicData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil)
        if cameraIntrinsicData != nil {
            requestHandlerOptions[VNImageOption.cameraIntrinsics] = cameraIntrinsicData
        }
            
        guard previousPixelBuffer != nil else {
            previousPixelBuffer = pixelBuffer
            self.resetTranspositionHistory()
            return .notSteady
        }
            
            
        let registrationRequest = VNTranslationalImageRegistrationRequest(targetedCVPixelBuffer: pixelBuffer)
        do {
            try self.sequenceRequestHandler.perform([registrationRequest], on: previousPixelBuffer!)
        } catch let error as NSError {
            print("Failed to process request: \(error.localizedDescription).")
            return .notSteady
        }
            
        previousPixelBuffer = pixelBuffer
            
        if let results = registrationRequest.results {
            if let alignmentObservation = results.first as? VNImageTranslationAlignmentObservation {
                let alignmentTransform = alignmentObservation.alignmentTransform
                self.recordTransposition(CGPoint(x: alignmentTransform.tx, y: alignmentTransform.ty))
            }
        }
            
        if self.sceneStabilityAchieved() {
            return .steady
        }
        else{
            return .notSteady
        }
    }
    
}


