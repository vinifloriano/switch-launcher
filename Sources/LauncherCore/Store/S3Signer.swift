import CryptoKit
import Foundation

/// AWS Signature Version 4 query signing (presigned URLs) for S3-compatible stores such as MinIO.
/// Presigned URLs let plain `URLSession` download tasks (with progress and resume) fetch private
/// objects without sending the secret anywhere.
public struct S3Signer: Sendable {
    public let accessKey: String
    public let secretKey: String
    public let region: String

    public init(accessKey: String, secretKey: String, region: String = "us-east-1") {
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.region = region
    }

    /// Path-style URL for `bucket/key` on `endpoint` (e.g. `http://192.168.1.10:30900`).
    /// `query` adds request parameters such as `uploads` or `partNumber` (multipart uploads).
    public func presignedURL(
        endpoint: URL,
        bucket: String,
        key: String,
        method: String = "GET",
        query: [(String, String)] = [],
        expires: Int = 3600,
        date: Date = Date()
    ) -> URL? {
        let path = "/" + ([bucket] + key.split(separator: "/").map(String.init)).joined(separator: "/")
        return presignedURL(endpoint: endpoint, path: path, method: method, query: query, expires: expires, date: date)
    }

    /// Signs an arbitrary `path` on `endpoint` (the path is used as given, then URI-encoded).
    public func presignedURL(
        endpoint: URL,
        path: String,
        method: String = "GET",
        query extraQuery: [(String, String)] = [],
        expires: Int,
        date: Date
    ) -> URL? {
        guard let scheme = endpoint.scheme, let hostName = endpoint.host() else { return nil }
        var host = hostName
        if let port = endpoint.port, !(scheme == "http" && port == 80), !(scheme == "https" && port == 443) {
            host += ":\(port)"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = formatter.string(from: date)
        let day = String(amzDate.prefix(8))
        let scope = "\(day)/\(region)/s3/aws4_request"

        let query: [(String, String)] = [
            ("X-Amz-Algorithm", "AWS4-HMAC-SHA256"),
            ("X-Amz-Credential", "\(accessKey)/\(scope)"),
            ("X-Amz-Date", amzDate),
            ("X-Amz-Expires", String(expires)),
            ("X-Amz-SignedHeaders", "host"),
        ] + extraQuery
        let canonicalQuery = query
            .map { (Self.encode($0.0), Self.encode($0.1)) }
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")
        let canonicalPath = path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { Self.encode(String($0)) }
            .joined(separator: "/")

        let canonicalRequest = [
            method,
            canonicalPath,
            canonicalQuery,
            "host:\(host)\n",
            "host",
            "UNSIGNED-PAYLOAD",
        ].joined(separator: "\n")

        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            Self.hex(SHA256.hash(data: Data(canonicalRequest.utf8))),
        ].joined(separator: "\n")

        var key = SymmetricKey(data: Data("AWS4\(secretKey)".utf8))
        for part in [day, region, "s3", "aws4_request"] {
            key = SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(part.utf8), using: key)))
        }
        let signature = Self.hex(HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key))

        let base = endpoint.absoluteString.hasSuffix("/") ? String(endpoint.absoluteString.dropLast()) : endpoint.absoluteString
        return URL(string: "\(base)\(canonicalPath)?\(canonicalQuery)&X-Amz-Signature=\(signature)")
    }

    /// RFC 3986 unreserved characters stay as they are; everything else is percent-encoded.
    static func encode(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    public static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
