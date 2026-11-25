import AppKit
import Vision
import JavaScriptCore

// A rendered French offer exercises Apple's OCR and the shipped calculation engine together.
let canvas = CGSize(width: 640, height: 460)
let graphic = NSImage(size: canvas)
graphic.lockFocus()
NSColor.white.setFill()
NSBezierPath(rect: CGRect(origin: .zero, size: canvas)).fill()
let words = ["Livraison", "6,40 €", "20 min (4 km)", "Accepter"]
for (index, word) in words.enumerated() {
    (word as NSString).draw(at: CGPoint(x: 46, y: 340 - 80 * index),
                            withAttributes: [.font: NSFont.systemFont(ofSize: 34),
                                             .foregroundColor: NSColor.black])
}
graphic.unlockFocus()
guard let sample = graphic.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Imagem de teste indisponível")
}
let request = VNRecognizeTextRequest()
// Hosted Macs may not expose a GPU to Vision. Exercise the OCR model on the CPU.
request.usesCPUOnly = true
request.recognitionLevel = .accurate
request.recognitionLanguages = ["fr-FR", "en-US"]
request.usesLanguageCorrection = false
try VNImageRequestHandler(cgImage: sample, options: [:]).perform([request])
let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
let js = JSContext()!
js.evaluateScript(try String(contentsOfFile: "App/offer.js", encoding: .utf8))
let args: [Any] = [text, 21.3, 0.14, 15]
guard let result = js.objectForKeyedSubscript("analyse")?.call(withArguments: args)?.toDictionary(),
      let rate = result["rate"] as? Double, abs(rate - 13.4304) < 0.001 else {
    fatalError("O cartão de teste não produziu a taxa esperada. OCR: " + text)
}
print("Vision + JavaScriptCore: cartão em francês e euros reconhecido, 13,43 €/h após custos.")
