import Foundation

struct HTTPRequest {
    let method: String
    let path: String
    let jsonBody: [String: Any]?
}

enum HTTPRequestParser {
    /// Returns nil if the request hasn't fully arrived yet (headers or body still incomplete).
    static func parse(_ buffer: Data) -> HTTPRequest? {
        guard let headerEndRange = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let headerData = buffer[..<headerEndRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])

        var contentLength = 0
        for line in lines.dropFirst() {
            if line.lowercased().hasPrefix("content-length:") {
                let value = line.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)
                contentLength = Int(value) ?? 0
            }
        }

        let bodyStart = headerEndRange.upperBound
        guard buffer.count - bodyStart >= contentLength else {
            return nil
        }

        var jsonBody: [String: Any]?
        if contentLength > 0 {
            let bodyData = buffer[bodyStart..<(bodyStart + contentLength)]
            jsonBody = try? JSONSerialization.jsonObject(with: Data(bodyData)) as? [String: Any]
        }

        return HTTPRequest(method: method, path: path, jsonBody: jsonBody)
    }
}

enum HTTPResponseData {
    case html(String)
    case json(Data)
    case notFound

    func rawHTTPResponse() -> Data {
        switch self {
        case .html(let string):
            return Self.build(status: "200 OK", contentType: "text/html; charset=utf-8", body: Data(string.utf8))
        case .json(let data):
            return Self.build(status: "200 OK", contentType: "application/json", body: data)
        case .notFound:
            return Self.build(status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8))
        }
    }

    private static func build(status: String, contentType: String, body: Data) -> Data {
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Connection: close",
            "Cache-Control: no-store",
        ].joined(separator: "\r\n") + "\r\n\r\n"

        var response = Data(headers.utf8)
        response.append(body)
        return response
    }
}
