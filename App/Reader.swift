import CoreMedia
import Foundation
import JavaScriptCore
import ScreenCaptureKit
import Vision

struct Limits {
    let reserve: Double
    let fuel: Double?
    let goal: Double
}

struct ResultLine {
    let title: String
    let body: String
}

final class Reader: NSObject, SCStreamOutput {
    let queue = DispatchQueue(label: "turno.offer-reader", qos: .userInitiated)
    private let limits: Limits
    private let found: (ResultLine) -> Void
    private let failed: (String) -> Void
    private let script: String
    private lazy var context: JSContext? = {
        guard let context = JSContext() else { return nil }
        context.evaluateScript(script)
        return context
    }()
    private var visibleOffer: String?
    private var absentSince: TimeInterval?
    private var lastFrame = -Double.infinity
    private var consecutiveErrors = 0

    init(limits: Limits, found: @escaping (ResultLine) -> Void,
         failed: @escaping (String) -> Void) throws {
        guard let url = Bundle.main.url(forResource: "offer", withExtension: "js") else {
            throw NSError(domain: "Turno", code: 1, userInfo: [NSLocalizedDescriptionKey: "Falta o leitor de ofertas no pacote."])
        }
        script = try String(contentsOf: url, encoding: .utf8)
        self.limits = limits
        self.found = found
        self.failed = failed
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        let now = ProcessInfo.processInfo.systemUptime
        guard outputType == .screen, now - lastFrame >= 0.24,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        autoreleasepool {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["fr-FR", "en-US"]
            request.usesLanguageCorrection = false
            // Vision coordinates start at the bottom. Leave system banners out of the read area.
            request.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 0.88)
            do {
                try VNImageRequestHandler(cvPixelBuffer: buffer, options: [:]).perform([request])
                consecutiveErrors = 0
            } catch {
                consecutiveErrors += 1
                if consecutiveErrors == 4 { failed("O iPhone deixou de conseguir ler o ecrã. Reinicia o turno.") }
                return
            }
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            let cost: Any = limits.fuel.map { NSNumber(value: $0) as Any } ?? NSNull()
            guard let fn = context?.objectForKeyedSubscript("analyse"),
                  let item = fn.call(withArguments: [text, limits.reserve, cost, limits.goal])?.toDictionary(),
                  let price = item["fare"] as? NSNumber,
                  let title = item["title"] as? String, let body = item["body"] as? String else {
                if absentSince == nil { absentSince = now }
                return
            }
            let cleared = absentSince.map { now - $0 > 1.25 } ?? false
            absentSince = nil
            let km = (item["km"] as? NSNumber)?.stringValue ?? "?"
            let minutes = (item["minutes"] as? NSNumber)?.stringValue ?? "?"
            let signature = [price.stringValue, km, minutes].joined(separator: "|")
            guard visibleOffer != signature || cleared else { return }
            visibleOffer = signature
            found(ResultLine(title: title, body: body))
        }
    }
}
