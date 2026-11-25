import Foundation
import CoreMedia
import Combine
import ScreenCaptureKit
import UIKit
import UserNotifications

final class Shift: NSObject, ObservableObject, SCContentSharingPickerObserver, SCStreamDelegate, UNUserNotificationCenterDelegate {
    enum Phase { case idle, picking, starting, active, stopping }
    @Published private(set) var phase = Phase.idle
    @Published private(set) var status = "Turno parado"
    @Published private(set) var latest: ResultLine?
    @Published private(set) var testTime: String?
    @Published private(set) var alertNote: String?
    private var testStart: TimeInterval?
    private var run = UUID()
    private var stream: SCStream?
    private var reader: Reader?
    private var limits: Limits?
    private let picker = SCContentSharingPicker.shared
    private let notices = UNUserNotificationCenter.current()

    override init() {
        super.init()
        notices.delegate = self
    }

    @MainActor func start(_ values: Limits) async {
        guard phase == .idle else { return }
        phase = .picking
        run = UUID()
        let token = run
        limits = values
        latest = nil
        testTime = nil
        alertNote = nil
        status = "A preparar a leitura"
        do {
            let allowed = try await notices.requestAuthorization(options: [.alert, .sound])
            if !allowed { alertNote = "Ativa as faixas em Definições → Notificações → Turno Euro para veres as avaliações na Uber." }
        } catch { alertNote = "O iPhone não autorizou os avisos." }
        guard run == token, phase == .picking else { return }
        picker.add(self)
        var config = SCContentSharingPickerConfiguration()
        config.showsMicrophoneControl = false
        picker.defaultConfiguration = config
        picker.isActive = true
        status = "Escolhe o ecrã completo ou a Uber Driver"
        picker.present()
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in
            guard phase == .picking, let limits else { return }
            phase = .starting
            let token = run
            do {
                let scan = try Reader(limits: limits, found: { [weak self] result in
                    Task { @MainActor in
                        guard let self, self.run == token, self.phase == .active else { return }
                        self.receive(result)
                    }
                }, failed: { [weak self] message in
                    Task { @MainActor in
                        guard let self, self.run == token else { return }
                        await self.stop(message)
                    }
                })
                let config = SCStreamConfiguration()
                let screen = UIScreen.main.nativeBounds
                config.width = min(1080, Int(screen.width))
                config.height = max(2, Int((screen.height / screen.width * CGFloat(config.width)) / 2) * 2)
                config.minimumFrameInterval = CMTime(value: 1, timescale: 4)
                let capture = SCStream(filter: filter, configuration: config, delegate: self)
                try capture.addStreamOutput(scan, type: .screen, sampleHandlerQueue: scan.queue)
                self.stream = capture
                reader = scan
                try await capture.startCapture()
                guard run == token, phase == .starting else {
                    try? await capture.stopCapture()
                    return
                }
                phase = .active
                status = "A ler ofertas"
            } catch {
                if run == token { await stop("Não foi possível iniciar a leitura. " + error.localizedDescription) }
            }
        }
    }

    @MainActor private func receive(_ result: ResultLine) {
        latest = result
        if let start = testStart {
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            testTime = String(format: "%.2f s até à leitura", elapsed)
            testStart = nil
        }
        let content = UNMutableNotificationContent()
        content.title = result.title
        content.body = result.body
        let notice = UNNotificationRequest(identifier: "ultima-oferta", content: content, trigger: nil)
        notices.add(notice) { [weak self] error in
            if error != nil { DispatchQueue.main.async { self?.alertNote = "A faixa não foi apresentada. Verifica as notificações." } }
        }
    }

    @MainActor func beginTest() { testStart = ProcessInfo.processInfo.systemUptime; testTime = nil }
    @MainActor func endTest() { testStart = nil }

    @MainActor func stop(_ message: String = "Turno parado") async {
        guard phase != .idle, phase != .stopping else { return }
        run = UUID()
        phase = .stopping
        let old = stream
        stream = nil
        picker.remove(self)
        picker.isActive = false
        testStart = nil
        if let old { try? await old.stopCapture() }
        reader = nil
        status = message
        phase = .idle
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in if phase == .picking { await stop("Partilha cancelada") } }
    }
    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in if phase == .picking { await stop(error.localizedDescription) } }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in if self.stream === stream { await stop("Leitura terminada pelo iPhone") } }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}
