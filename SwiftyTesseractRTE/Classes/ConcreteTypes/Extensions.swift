//
//  Extensions.swift
//  KanjiLookup
//
//  Created by Morten Bertz on 2020/05/13.
//  Copyright © 2020 telethon k.k. All rights reserved.
//

import Foundation
import AVFoundation

extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: return nil
        }
    }
}


extension CGImagePropertyOrientation{
    init(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .landscapeLeft:
            self = CGImagePropertyOrientation.left
        case .landscapeRight:
            self = CGImagePropertyOrientation.right
        case .portraitUpsideDown:
            self = CGImagePropertyOrientation.down
        default: // We default everything else to .portraitUp
            self = .up
        }
    }
}


