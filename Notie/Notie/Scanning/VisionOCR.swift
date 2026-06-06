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
                // Recognize English + Simplified Chinese + Spanish (Phase 1
                // languages) for mixed-language docs like NYC/TLC bilingual
                // forms. Intersect with what THIS OS build actually supports so
                // an unavailable tag can't make recognition fail into empty
                // text; always keep English as a fallback.
                let wanted = ["en-US", "zh-Hans", "es-ES"]
                let supported = Set((try? request.supportedRecognitionLanguages()) ?? [])
                let available = wanted.filter { supported.contains($0) }
                request.recognitionLanguages = available.isEmpty ? ["en-US"] : available

                // Downsample before Vision: OCR time scales with pixel count, so
                // a full ~12MP photo is the main reason a scan feels slow. This
                // is the biggest, safest speed win and doesn't change the text
                // for normal documents. Orientation still applies to the scaled
                // pixels, so we keep passing the original orientation.
                let scaled = downsampled(cgImage)
                let handler = VNImageRequestHandler(
                    cgImage: scaled, orientation: orientation, options: [:])
                let start = CFAbsoluteTimeGetCurrent()
                do {
                    try handler.perform([request])
                    #if DEBUG
                    // Answers "is OCR slow because of the Simulator or the code?"
                    // — logs the real time + the pixel size Vision processed.
                    let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
                    print("[VisionOCR] \(Int(ms)) ms · \(scaled.width)×\(scaled.height) px · langs \(request.recognitionLanguages)")
                    #endif
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    // Scale an image down so its longest edge is at most `maxEdge` px. Returns
    // the original if it's already small enough. Pure CoreGraphics (no UIKit),
    // so it's safe to run off the main thread.
    private static func downsampled(_ cgImage: CGImage, maxEdge: CGFloat = 2000) -> CGImage {
        let w = CGFloat(cgImage.width), h = CGFloat(cgImage.height)
        let longest = max(w, h)
        guard longest > maxEdge else { return cgImage }
        let scale = maxEdge / longest
        let newW = Int(w * scale), newH = Int(h * scale)
        guard let ctx = CGContext(
            data: nil, width: newW, height: newH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cgImage }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage() ?? cgImage
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
