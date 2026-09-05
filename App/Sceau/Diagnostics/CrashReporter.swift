import Foundation
import MetricKit
import OSLog

/// Sammelt Absturz- und Hängerberichte des Systems.
///
/// Der Entwicklungsplan verlangt Absturzerfassung von Anfang an, statt erst
/// durch Nutzerbeschwerden von Problemen zu erfahren. `MetricKit` liefert
/// diese Berichte, ohne dass ein eigener Absturzfänger installiert werden
/// müsste — der käme dem System nur in die Quere.
///
/// **Stand:** Die Berichte werden lokal abgelegt und protokolliert. Einen
/// Server, an den sie gehen könnten, gibt es noch nicht; sobald der Vertrieb
/// entschieden ist (App Store oder eigenständig), kommt hier der Versand dazu.
/// Bis dahin sind die Dateien der Weg, um nach einem Absturz nachzusehen.
///
/// `@unchecked Sendable` ist hier belegbar und keine Beschwichtigung: Die
/// einzige gespeicherte Eigenschaft ist ein `Logger`, der selbst `Sendable`
/// ist; alles Übrige wird bei Bedarf berechnet. Nötig ist die Angabe, weil
/// MetricKit seine Berichte auf einem eigenen Thread zustellt.
final class CrashReporter: NSObject, @unchecked Sendable {

    static let shared = CrashReporter()

    private let log = Logger(subsystem: "ch.arunmeyer.Sceau", category: "Diagnose")

    private override init() {
        super.init()
    }

    func start() {
        MXMetricManager.shared.add(self)
        log.debug("Diagnose-Erfassung aktiv")
    }

    /// Ordner, in dem die Berichte liegen.
    ///
    /// Unterhalb der Programmunterstützung, damit die Dateien den
    /// Sandbox-Container nicht verlassen und beim Löschen der App mitgehen.
    private var reportDirectory: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }

        let directory = base.appendingPathComponent("Diagnose", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            log.error("Diagnoseordner nicht anlegbar: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Berichte, die älter sind, werden beim nächsten Eintreffen eines neuen
    /// Berichts aufgeräumt. MetricKit liefert höchstens ein-, zweimal täglich
    /// etwas, ohne diese Grenze wüchse der Ordner über die Lebensdauer der
    /// Installation trotzdem unbegrenzt weiter.
    private static let maxReportAge: TimeInterval = 30 * 24 * 60 * 60

    private func store(_ data: Data, prefix: String) {
        guard let directory = reportDirectory else { return }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("\(prefix)-\(stamp).json")

        do {
            try data.write(to: url, options: .atomic)
            log.notice("Diagnosebericht gesichert: \(url.lastPathComponent, privacy: .public)")
        } catch {
            log.error("Diagnosebericht nicht schreibbar: \(error.localizedDescription, privacy: .public)")
        }

        pruneOldReports(in: directory)
    }

    /// Löscht Berichte, die älter als ``maxReportAge`` sind.
    ///
    /// Beschränkt sich strikt auf den eigenen Diagnoseordner im
    /// Sandbox-Container — nichts, was ausserhalb davon liegt, wird auch nur
    /// betrachtet.
    private func pruneOldReports(in directory: URL) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-Self.maxReportAge)
        for url in entries {
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified < cutoff
            else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}

extension CrashReporter: MXMetricManagerSubscriber {

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            store(payload.jsonRepresentation(), prefix: "Messwerte")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            // Abstürze und Hänger sind der eigentliche Grund für diese
            // Anbindung, deshalb hier die deutlichere Protokollstufe.
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            if crashes > 0 || hangs > 0 {
                log.error("Diagnose eingetroffen: \(crashes) Abstürze, \(hangs) Hänger")
            }
            store(payload.jsonRepresentation(), prefix: "Diagnose")
        }
    }
}
