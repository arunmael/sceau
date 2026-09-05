import Foundation
import Testing

@testable import SceauCore

/// `RGBAColor`/`GradientStop` sind über `Codable` auch aus Dateien erreichbar,
/// die von Hand verändert oder beschädigt wurden — nicht nur über die eigene,
/// bereits klemmende UI. Ohne Absicherung im Decoder würden nicht endliche
/// oder ausser Reichweite liegende Werte unbemerkt bis zu einer `Int(...)`-
/// Umwandlung (Hex-Anzeige, Prozentanzeige im Verlauf) durchrutschen und dort
/// abstürzen. Siehe agent-rules.md Abschnitt 4.
@Suite("RGBAColor/GradientStop — sicher gegen beschädigte Werte aus Dateien")
struct StyleValueSafetyTests {

    private func decode<T: Decodable>(_ type: T.Type, json: String) throws -> T {
        let decoder = JSONDecoder()
        // JSON selbst kennt kein NaN/Infinity — die Tokens hier simulieren nur,
        // dass ein Decoder sie akzeptieren könnte; JSONDecoder braucht dafür
        // diese Strategie, sonst würfe das Dekodieren selbst schon.
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan"
        )
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    @Test("Aus einer Datei dekodierte Farbkomponenten ausserhalb 0...1 werden geklemmt")
    func decodedColorComponentsAreClamped() throws {
        let color = try decode(
            RGBAColor.self,
            json: #"{"red": 5.0, "green": -3.0, "blue": 0.5, "alpha": 2.0}"#
        )
        #expect(color.red == 1)
        #expect(color.green == 0)
        #expect(color.blue == 0.5)
        #expect(color.alpha == 1)
    }

    @Test("Nicht endliche dekodierte Farbkomponenten stürzen nicht ab, sondern werden auf 0...1 abgebildet")
    func decodedNonFiniteColorComponentsDoNotCrash() throws {
        let color = try decode(
            RGBAColor.self,
            json: #"{"red": "nan", "green": "inf", "blue": "-inf", "alpha": 1.0}"#
        )
        #expect(color.red.isFinite)
        #expect(color.green == 1)
        #expect(color.blue == 0)
        // Die hexString-Berechnung darf mit diesen Werten nicht abstürzen —
        // das war der ursprüngliche Absturzpfad.
        _ = Int((color.red * 255).rounded())
    }

    @Test("Ein dekodierter Verlaufsstopp ausserhalb 0...1 wird auf den gültigen Bereich geklemmt")
    func decodedGradientStopLocationIsClamped() throws {
        let stop = try decode(
            GradientStop.self,
            json: #"{"color": {"red": 0, "green": 0, "blue": 0, "alpha": 1}, "location": 4.5}"#
        )
        #expect(stop.location == 1)
    }

    @Test("Ein nicht endlicher dekodierter Verlaufsstopp stürzt nicht ab")
    func decodedNonFiniteGradientStopLocationDoesNotCrash() throws {
        let stop = try decode(
            GradientStop.self,
            json: #"{"color": {"red": 0, "green": 0, "blue": 0, "alpha": 1}, "location": "nan"}"#
        )
        #expect(stop.location.isFinite)
        _ = Int((stop.location * 100))
    }

    @Test("Der normale Konstruktor klemmt weiterhin wie bisher (keine Verhaltensänderung)")
    func memberwiseInitializerStillClamps() {
        let color = RGBAColor(red: 10, green: -10, blue: 0.25, alpha: 10)
        #expect(color.red == 1)
        #expect(color.green == 0)
        #expect(color.blue == 0.25)
        #expect(color.alpha == 1)
    }
}
