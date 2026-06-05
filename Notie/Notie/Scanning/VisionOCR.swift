//  VisionOCR.swift
//
//  On-device text recognition with Apple's Vision framework. Takes a photo
//  and returns the recognized text — free, fast, private (nothing leaves
//  the phone). This is step 1 of the capture pipeline; rule parsing + the
//  AI extraction (Week 5–6) run on this text.
//
//  Uses VNRecognizeTextRequest (iOS 17-compatible). Recognition runs off
//  the main thread; the result comes back via async/await.
//

import Foundation
import Vision
import UIKit

enum VisionOCR {
    /// Recognize printed text in an image. Returns lines joined by "\n",
    /// or "" if the image can't be read.
    static func recognizeText(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        let orientation = cgOrientation(from: image.imageOrientation)

        return await withCheckedContinuation { continuation in
            // Build the request + handler INSIDE the background closure so
            // the non-Sendable Vision objects aren't captured across the
            // concurrency boundary (keeps the build warning-free).
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, _ in
                    let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                        .compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: lines.joined(separator: "\n"))
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(
                    cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    // Vision wants a CGImagePropertyOrientation; map it from the UIImage's.
    private static func cgOrientation(from o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up:            return .up
        case .down:          return .down
        case .left:          return .left
        case .right:         return .right
        case .upMirrored:    return .upMirrored
        case .downMirrored:  return .downMirrored
        case .leftMirrored:  return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .up
        }
    }
}
