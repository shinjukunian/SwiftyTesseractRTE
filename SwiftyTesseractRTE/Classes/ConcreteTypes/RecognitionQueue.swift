//
//  RecognitionQueue.swift
//  SwiftyTesseractRTE
//
//  Created by Steven Sherry on 3/3/18.
//  Copyright © 2018 Steven Sherry. All rights reserved.
//

struct RecognitionQueue<T: Hashable> {
    private var values: [T:Int]
  
    let desiredConfidence: Int

    @inlinable
    func recognizedValue(confidence:Int)->T?{
        if let maxValue=self.values.max(by: {v1,v2 in
            return v1.value < v2.value
        }), maxValue.value >= self.desiredConfidence{
            return maxValue.key
        }
        return nil
    }
    
    var recognizedValue: T? {
        return self.recognizedValue(confidence: self.desiredConfidence)
    }
  
    init(desiredConfidence: Int) {
        self.desiredConfidence = desiredConfidence
        values = [T:Int]()
    }
  
    mutating func enqueue(_ value: T) {
        if let count=self.values[value]{
            self.values[value] = count+1
        }
        else{
            self.values[value]=1
        }
    }
  
  
    mutating func clear() {
        values.removeAll()
    }

}

extension RecognitionQueue {
    init(desiredReliability: RecognitionReliability) {
        self.init(desiredConfidence: desiredReliability.numberOfResults)
    }
}
