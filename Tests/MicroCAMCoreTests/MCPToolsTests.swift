import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MicroCAMCore

final class MCPToolsTests: XCTestCase {
    func names(_ jobs: Bool) -> [String] {
        MCPTools.definitions(jobsEnabled: jobs).compactMap { $0["name"]?.string }
    }

    func testListsToolsInAFixedOrderAndSetJobOnlyWithJobs() {
        let base = ["get_status", "capture_frame", "take_photo", "list_captures", "get_capture",
                    "start_recording", "stop_recording"]
        XCTAssertEqual(names(false), base)
        XCTAssertEqual(names(true), base + ["set_job"])
    }

    func testEveryToolHasADescriptionAndAClosedObjectSchema() {
        for tool in MCPTools.definitions(jobsEnabled: true) {
            let name = tool["name"]?.string ?? "?"
            XCTAssertFalse(tool["description"]?.string?.isEmpty ?? true, name)
            XCTAssertNotNil(tool["title"]?.string, name)
            XCTAssertEqual(tool["inputSchema"]?["type"], "object", name)
            XCTAssertEqual(tool["inputSchema"]?["additionalProperties"], .bool(false), name)
            XCTAssertNotNil(tool["annotations"]?["readOnlyHint"], name)
        }
        let getCapture = MCPTools.definitions(jobsEnabled: false).first { $0["name"] == "get_capture" }
        XCTAssertEqual(getCapture?["inputSchema"]?["required"], ["name"])
        XCTAssertEqual(getCapture?["inputSchema"]?["properties"]?["max_size"]?["type"], "integer")
    }

    func testParsesDefaults() {
        XCTAssertEqual(try MCPToolCall.parse(name: "get_status", arguments: nil).get(), .getStatus)
        XCTAssertEqual(try MCPToolCall.parse(name: "capture_frame", arguments: nil).get(),
                       .captureFrame(maxSize: MCPTools.defaultMaxSize))
        XCTAssertEqual(try MCPToolCall.parse(name: "list_captures", arguments: [:]).get(),
                       .listCaptures(limit: MCPTools.defaultListLimit))
        XCTAssertEqual(try MCPToolCall.parse(name: "take_photo", arguments: ["max_size": 800]).get(),
                       .takePhoto(maxSize: 800))
        XCTAssertEqual(try MCPToolCall.parse(name: "capture_frame", arguments: ["max_size": .double(640)]).get(),
                       .captureFrame(maxSize: 640))
        XCTAssertEqual(try MCPToolCall.parse(name: "get_capture", arguments: ["name": "a.jpg"]).get(),
                       .getCapture(name: "a.jpg", maxSize: MCPTools.defaultMaxSize))
        XCTAssertEqual(try MCPToolCall.parse(name: "set_job", arguments: ["job": " pr-12 "]).get(),
                       .setJob(JobCode("PR-12")))
        XCTAssertEqual(try MCPToolCall.parse(name: "set_job", arguments: ["job": ""]).get(), .setJob(nil))
    }

    func testRejectsBadArgumentsWithAReadableReason() {
        func reason(_ name: String, _ args: JSONValue?) -> String? {
            if case .failure(.invalidArguments(let text)) = MCPToolCall.parse(name: name, arguments: args) { return text }
            return nil
        }
        XCTAssertNotNil(reason("capture_frame", ["max_size": 10]))
        XCTAssertNotNil(reason("capture_frame", ["max_size": 100_000]))
        XCTAssertNotNil(reason("capture_frame", ["max_size": "big"]))
        XCTAssertNotNil(reason("capture_frame", ["max_size": .double(640.5)]))
        XCTAssertNotNil(reason("list_captures", ["limit": 0]))
        XCTAssertNotNil(reason("list_captures", ["limit": 101]))
        XCTAssertNotNil(reason("get_capture", [:]))
        XCTAssertNotNil(reason("get_capture", ["name": 5]))
        XCTAssertNotNil(reason("get_status", ["extra": true]))
        XCTAssertNotNil(reason("set_job", [:]))
        XCTAssertTrue(reason("set_job", ["job": "PR 1/.."])?.contains("PR 1/..") ?? false)
        XCTAssertNotNil(reason("get_status", .array([])))
    }

    func testUnknownTool() {
        XCTAssertEqual(MCPToolCall.parse(name: "format_disk", arguments: nil), .failure(.unknownTool("format_disk")))
    }
}

final class MCPCaptureCatalogTests: XCTestCase {
    func testListsNewestFirstWithKindTimeAndSize() throws {
        let tmp = TempDir()
        tmp.touch("PR-1/PR-1_2026-09-21_10-00-00.jpg")
        tmp.touch("PR-1/PR-1_2026-09-21_11-00-00.mov")
        tmp.touch("PR-1/Timelapse/PR-1_2026-09-21_12-00-00.jpg")
        tmp.touch("PR-1/notes.txt")
        let folders = [tmp.url.appendingPathComponent("PR-1"), tmp.url.appendingPathComponent("PR-1/Timelapse")]
        let files = MCPCaptureCatalog.list(in: folders, limit: 10)
        XCTAssertEqual(files.map(\.name), ["PR-1_2026-09-21_12-00-00.jpg", "PR-1_2026-09-21_11-00-00.mov",
                                           "PR-1_2026-09-21_10-00-00.jpg"])
        XCTAssertEqual(files.map(\.kind), [.timelapse, .video, .photo])
        XCTAssertEqual(files[0].sizeBytes, 1)
        XCTAssertNotNil(files[0].capturedAt)
        XCTAssertEqual(MCPCaptureCatalog.list(in: folders, limit: 1).count, 1)
    }

    func testResolvesPhotosAndVideosButNothingElse() {
        let tmp = TempDir()
        tmp.touch("PR-1/PR-1_2026-09-21_10-00-00.jpg")
        tmp.touch("PR-1/PR-1_2026-09-21_11-00-00.mov")
        tmp.touch("secret.txt")
        let folders = [tmp.url.appendingPathComponent("PR-1")]
        XCTAssertEqual(MCPCaptureCatalog.resolve("PR-1_2026-09-21_11-00-00.mov", in: folders)?.kind, .video)
        XCTAssertEqual(MCPCaptureCatalog.resolve("PR-1_2026-09-21_10-00-00.jpg", in: folders)?.kind, .photo)
        for name in ["../secret.txt", "secret.txt", "PR-1_2026-09-21_12-00-00.jpg", "/etc/passwd", ""] {
            XCTAssertNil(MCPCaptureCatalog.resolve(name, in: folders), name)
        }
    }
}

final class JPEGScalerTests: XCTestCase {
    func makeJPEG(width: Int, height: Int) -> Data {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    func testShrinksTheLongerSideAndKeepsSmallImages() throws {
        let big = try XCTUnwrap(JPEGScaler.scaled(makeJPEG(width: 400, height: 200), maxDimension: 100))
        XCTAssertEqual(big.width, 100)
        XCTAssertEqual(big.height, 50)
        XCTAssertNotNil(CGImageSourceCreateWithData(big.jpeg as CFData, nil))
        let small = try XCTUnwrap(JPEGScaler.scaled(makeJPEG(width: 80, height: 60), maxDimension: 100))
        XCTAssertEqual(small.width, 80)
        XCTAssertEqual(small.height, 60)
        XCTAssertNil(JPEGScaler.scaled(Data("not an image".utf8), maxDimension: 100))
    }
}
