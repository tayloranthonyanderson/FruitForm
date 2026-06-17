import Foundation

/// Structured shape read returned by the vision model for one fruit crop.
struct ShapeClassification {
    var category: String
    var confidence: Double
    var note: String?
}

/// Calls the Claude Messages API with a forced tool call so the response is
/// always structured. Vision-capable model classifies tomato fruit shape.
final class ClaudeClient {

    enum ClientError: LocalizedError {
        case notConfigured
        case http(Int, String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Cloud classification is not configured."
            case .http(let code, let body): return "Claude API error \(code): \(body)"
            case .badResponse: return "Unexpected response from Claude API."
            }
        }
    }

    private let apiKey: String
    private let model: String
    private let session = URLSession(configuration: .default)

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }

    /// The 7 preset shapes used in the Training tab — keep this in lock-step with
    /// `TrainingStore.defaultShapeLabels` so cloud labels match the trained taxonomy.
    private static let categories = [
        "round", "flat", "oval", "elongated", "heart", "pear", "fasciated"
    ]

    /// Plain-language definition of each category, handed to the model so it
    /// classifies into our taxonomy rather than its own.
    private static let categoryGuide = """
    - round: globe-shaped, about as wide as tall, smooth circular outline.
    - flat: oblate, distinctly wider than tall (a squat, flattened disc).
    - oval: egg / plum / roma — moderately longer than wide, smooth, blunt ends.
    - elongated: much longer than wide (long San Marzano / banana types).
    - heart: broad shoulders tapering to a point at the blossom end.
    - pear: pyriform — necked, narrow toward the stem, bulbous at the blossom end.
    - fasciated: ribbed AND irregular — lumpy, lobed or contorted outline from many locules.
    """

    func classify(jpeg: Data, shapeIndex: Double?, solidity: Double?, flatness: Double? = nil) async throws -> ShapeClassification {
        guard !apiKey.isEmpty else { throw ClientError.notConfigured }

        var hints = "On-device measurements: "
        hints += shapeIndex.map { "shape index (long/short axis) = \(String(format: "%.2f", $0)); " } ?? ""
        hints += solidity.map { "solidity = \(String(format: "%.2f", $0)) (1.0 = smooth, lower = ribbed/lobed → leans fasciated). " } ?? ""
        hints += flatness.map { "LiDAR flatness (height ÷ width) = \(String(format: "%.2f", $0)) (≈1 round; well below 1 → flat/oblate, even if the top looks round). " } ?? ""

        let tool: [String: Any] = [
            "name": "record_shape",
            "description": "Record the shape classification of the tomato fruit in the image.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "category": [
                        "type": "string",
                        "enum": Self.categories,
                        "description": "Best-fit fruit shape category."
                    ],
                    "confidence": [
                        "type": "number",
                        "description": "Confidence from 0 to 1."
                    ],
                    "note": [
                        "type": "string",
                        "description": "Short note on ribbing, blossom-end shape, or anything notable. May be empty."
                    ]
                ],
                "required": ["category", "confidence"]
            ]
        ]

        let prompt = """
        You are assisting a tomato breeder. Classify the shape of the single tomato fruit \
        that is the main subject of this image into exactly one of these 7 categories:
        \(Self.categoryGuide)
        Judge shape along the polar (stem-to-blossom) axis. \(hints)\
        Call the record_shape tool with your answer.
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 512,
            "tool_choice": ["type": "tool", "name": "record_shape"],
            "tools": [tool],
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": jpeg.base64EncodedString()
                        ]
                    ],
                    ["type": "text", "text": prompt]
                ]
            ]]
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.badResponse }
        guard http.statusCode == 200 else {
            throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]]
        else { throw ClientError.badResponse }

        for block in content where block["type"] as? String == "tool_use" {
            guard let input = block["input"] as? [String: Any],
                  let category = input["category"] as? String else { continue }
            let confidence = (input["confidence"] as? Double) ?? 0
            var note = input["note"] as? String
            if note?.isEmpty == true { note = nil }
            return ShapeClassification(category: category, confidence: confidence, note: note)
        }
        throw ClientError.badResponse
    }
}
