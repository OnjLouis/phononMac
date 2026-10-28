import Foundation

public struct SpeechRequest {
    public var text = ""
    public var rate: Float = 1
    public var pitch: Float = 1
    public var volume: Float = 1

    public init(text: String = "") { self.text = text }

    public static func parse(_ ssml: String) throws -> SpeechRequest {
        let delegate = RequestParser()
        let parser = XMLParser(data: Data(ssml.utf8))
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? RequestError.invalidMarkup }
        delegate.request.text = delegate.request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return delegate.request
    }
}

public enum RequestError: Error { case invalidMarkup, modelUnavailable }

private final class RequestParser: NSObject, XMLParserDelegate {
    var request = SpeechRequest()
    private let boundaries = Set(["voice", "lang", "p", "s", "paragraph", "sentence", "break"])
    private func boundary() {
        if !request.text.isEmpty, request.text.last?.isWhitespace == false { request.text += " " }
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        if boundaries.contains(element.lowercased()) { boundary() }
        guard element.lowercased() == "prosody" else { return }
        if let value = attributes["rate"], let n = number(value) {
            request.rate = max(0.5, min(3, n / (value.contains("%") ? 200 : 1)))
        }
        if let value = attributes["pitch"], let n = number(value) {
            request.pitch = max(0.5, min(2, value.contains("st") ? pow(2, n / 12) :
                (value.hasPrefix("+") || value.hasPrefix("-") ? 1 + n / 100 : n / 50)))
        }
        if let value = attributes["volume"] {
            if value == "silent" { request.volume = 0 }
            else if let n = number(value) {
                request.volume = max(0, min(1, value.lowercased().contains("db") ? pow(10, n / 20) : n / 100))
            }
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { request.text += string }
    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if boundaries.contains(element.lowercased()) { boundary() }
    }
    private func number(_ value: String) -> Float? {
        Float(value.filter { $0.isNumber || ".+-".contains($0) })
    }
}
