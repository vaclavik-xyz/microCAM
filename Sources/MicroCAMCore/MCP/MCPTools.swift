import Foundation

/// Tool definitions for `tools/list`. Names and argument names are an API:
/// agents and their prompts depend on them, so don't rename them.
public enum MCPTools {
    /// Longest side of images sent to agents unless they ask otherwise; the
    /// size vision models work with best, and a small, fast response.
    public static let defaultMaxSize = 1568
    public static let maxSizeRange = 64...8192
    public static let defaultListLimit = 20
    public static let listLimitRange = 1...100

    private static let maxSizeProperty: JSONValue = [
        "type": "integer", "minimum": .int(maxSizeRange.lowerBound), "maximum": .int(maxSizeRange.upperBound),
        "description": .string("Longest side of the returned image in pixels (default \(defaultMaxSize)). Smaller is faster."),
    ]

    private static func tool(_ name: String, _ title: String, _ description: String,
                             properties: [String: JSONValue] = [:], required: [String] = [],
                             readOnly: Bool, idempotent: Bool = false) -> JSONValue {
        var schema: [String: JSONValue] = ["type": "object", "properties": .object(properties),
                                           "additionalProperties": false]
        if !required.isEmpty { schema["required"] = .array(required.map { .string($0) }) }
        return ["name": .string(name), "title": .string(title), "description": .string(description),
                "inputSchema": .object(schema),
                "annotations": ["readOnlyHint": .bool(readOnly), "destructiveHint": false,
                                "idempotentHint": .bool(idempotent || readOnly), "openWorldHint": false]]
    }

    /// In a fixed order; `set_job` only while jobs are turned on.
    public static func definitions(jobsEnabled: Bool) -> [JSONValue] {
        var tools: [JSONValue] = [
            tool("get_status", "Camera status",
                 "The camera (as named in microCAM), its format, whether it is recording and for how long, a running timelapse, and the folder and job new captures go to.",
                 readOnly: true),
            tool("capture_frame", "Look at the camera",
                 "The current picture from the microscope camera as a JPEG, with the same image adjustments as photos. Nothing is saved. The person at the Mac sees that an agent is watching.",
                 properties: ["max_size": maxSizeProperty], readOnly: true),
            tool("take_photo", "Take a photo",
                 "Takes and saves a photo exactly like the photo button in microCAM (full resolution, into the current folder and job). Returns the photo and its file name.",
                 properties: ["max_size": maxSizeProperty], readOnly: false),
            tool("list_captures", "List captures",
                 "The newest photos and videos in the current folder, newest first, with name, kind, time and size.",
                 properties: ["limit": ["type": "integer", "minimum": .int(listLimitRange.lowerBound),
                                        "maximum": .int(listLimitRange.upperBound),
                                        "description": .string("How many files to list (default \(defaultListLimit)).")]],
                 readOnly: true),
            tool("get_capture", "Open a capture",
                 "A photo from the current folder as an image, or a video's details (videos are not sent).",
                 properties: ["name": ["type": "string", "description": "File name from list_captures."],
                              "max_size": maxSizeProperty],
                 required: ["name"], readOnly: true),
            tool("start_recording", "Start recording",
                 "Starts a video recording like the record button in microCAM.", readOnly: false),
            tool("stop_recording", "Stop recording",
                 "Stops the running recording and waits until the video is saved. Returns its file name.",
                 readOnly: false),
        ]
        if jobsEnabled {
            tools.append(tool("set_job", "Set the job",
                              "Sets the job (repair order) new captures are filed under, e.g. PR-260412. An empty string clears it.",
                              properties: ["job": ["type": "string",
                                                   "description": "Job code: letters, digits and '-', up to 32 characters. Empty clears the job."]],
                              required: ["job"], readOnly: false, idempotent: true))
        }
        return tools
    }
}

public enum MCPToolCall: Equatable, Sendable {
    case getStatus
    case captureFrame(maxSize: Int)
    case takePhoto(maxSize: Int)
    case listCaptures(limit: Int)
    case getCapture(name: String, maxSize: Int)
    case startRecording
    case stopRecording
    case setJob(JobCode?)

    public enum ParseError: Error, Equatable {
        /// A JSON-RPC error: the agent asked for something that doesn't exist.
        case unknownTool(String)
        /// A tool error the agent can fix by changing the arguments.
        case invalidArguments(String)
    }

    private static let allowed: [String: Set<String>] = [
        "get_status": [], "capture_frame": ["max_size"], "take_photo": ["max_size"], "list_captures": ["limit"],
        "get_capture": ["name", "max_size"], "start_recording": [], "stop_recording": [], "set_job": ["job"],
    ]

    public static func parse(name: String, arguments: JSONValue?) -> Result<MCPToolCall, ParseError> {
        guard let allowedKeys = allowed[name] else { return .failure(.unknownTool(name)) }
        let args: [String: JSONValue]
        switch arguments {
        case nil, .null?: args = [:]
        case .object(let o)?: args = o
        default: return .failure(.invalidArguments("The arguments must be an object."))
        }
        if let extra = args.keys.sorted().first(where: { !allowedKeys.contains($0) }) {
            return .failure(.invalidArguments("Unknown argument \"\(extra)\" for \(name)."))
        }
        do {
            switch name {
            case "get_status": return .success(.getStatus)
            case "capture_frame": return .success(.captureFrame(maxSize: try maxSize(args)))
            case "take_photo": return .success(.takePhoto(maxSize: try maxSize(args)))
            case "list_captures":
                return .success(.listCaptures(limit: try integer(args, "limit", MCPTools.defaultListLimit,
                                                                 MCPTools.listLimitRange)))
            case "get_capture":
                guard let file = args["name"]?.string, !file.isEmpty else {
                    throw ParseError.invalidArguments("\"name\" must be a file name from list_captures.")
                }
                return .success(.getCapture(name: file, maxSize: try maxSize(args)))
            case "start_recording": return .success(.startRecording)
            case "stop_recording": return .success(.stopRecording)
            default:   // set_job
                guard let raw = args["job"]?.string else {
                    throw ParseError.invalidArguments("\"job\" must be a job code, or an empty string to clear the job.")
                }
                if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .success(.setJob(nil)) }
                guard let code = JobCode(raw) else {
                    throw ParseError.invalidArguments("\"\(raw)\" isn't a valid job code. Use letters, digits and '-' (not first), up to \(JobCode.maxLength) characters.")
                }
                return .success(.setJob(code))
            }
        } catch let error as ParseError {
            return .failure(error)
        } catch {
            return .failure(.invalidArguments("\(error)"))
        }
    }

    private static func maxSize(_ args: [String: JSONValue]) throws -> Int {
        try integer(args, "max_size", MCPTools.defaultMaxSize, MCPTools.maxSizeRange)
    }

    private static func integer(_ args: [String: JSONValue], _ key: String, _ fallback: Int,
                                _ range: ClosedRange<Int>) throws -> Int {
        guard let value = args[key], value != .null else { return fallback }
        guard let number = value.integer, range.contains(number) else {
            throw ParseError.invalidArguments("\"\(key)\" must be a whole number from \(range.lowerBound) to \(range.upperBound).")
        }
        return number
    }
}
