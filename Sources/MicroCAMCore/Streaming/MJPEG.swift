import Foundation

/// Motion JPEG over `multipart/x-mixed-replace`, supported natively by
/// Safari/WebKit/Chrome `<img>`.
public enum MJPEG {
    public static let boundary = "microcamframe"

    public static func responseHead() -> Data {
        Data(("HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=\(boundary)\r\n"
              + "Cache-Control: no-store\r\nConnection: close\r\nPragma: no-cache\r\n\r\n").utf8)
    }

    public static func part(jpeg: Data) -> Data {
        Data("--\(boundary)\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpeg.count)\r\n\r\n".utf8)
            + jpeg + Data("\r\n".utf8)
    }
}
