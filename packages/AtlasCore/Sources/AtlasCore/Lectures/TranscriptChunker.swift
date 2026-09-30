import Foundation

public struct TranscriptChunk: Hashable, Sendable {
    public let index: Int
    public let startSeconds: Double
    public let endSeconds: Double
    public let text: String

    public init(index: Int, startSeconds: Double, endSeconds: Double, text: String) {
        self.index = index
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
    }

    public var rangeLabel: String {
        "\(AtlasLectureSegment.timecode(for: startSeconds))–\(AtlasLectureSegment.timecode(for: endSeconds))"
    }
}

/// Splits a long transcript into model-sized pieces on segment boundaries.
///
/// An hour of lecture is far larger than any on-device context window, so the
/// structuring pass runs per chunk and merges. Chunks carry their time range
/// so the resulting notes can point back into the recording.
public enum TranscriptChunker {
    public static let defaultChunkCharacters = 6_000

    public static func chunks(
        from segments: [AtlasLectureSegment],
        maximumCharacters: Int = defaultChunkCharacters
    ) -> [TranscriptChunk] {
        let budget = max(500, maximumCharacters)
        let usable = segments.filter { !$0.text.trimmed.isEmpty }
        guard !usable.isEmpty else { return [] }

        var chunks: [TranscriptChunk] = []
        var buffer: [AtlasLectureSegment] = []
        var bufferLength = 0

        func flush() {
            guard let first = buffer.first, let last = buffer.last else { return }
            let text = buffer.map { $0.text.trimmed }.joined(separator: " ")
            chunks.append(
                TranscriptChunk(
                    index: chunks.count,
                    startSeconds: first.start,
                    endSeconds: last.end,
                    text: text
                )
            )
            buffer = []
            bufferLength = 0
        }

        for segment in usable {
            let length = segment.text.trimmed.count + 1
            if bufferLength + length > budget, !buffer.isEmpty {
                flush()
            }
            buffer.append(segment)
            bufferLength += length
            if bufferLength >= budget { flush() }
        }
        flush()
        return chunks
    }

    /// Fallback for a transcript that arrived without timing information.
    public static func chunks(
        fromPlainText text: String,
        totalDuration: Double,
        maximumCharacters: Int = defaultChunkCharacters
    ) -> [TranscriptChunk] {
        let budget = max(500, maximumCharacters)
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        guard !words.isEmpty else { return [] }

        var pieces: [String] = []
        var buffer: [Substring] = []
        var length = 0

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            pieces.append(buffer.joined(separator: " "))
            buffer = []
            length = 0
        }

        for word in words {
            // Extracted PDF text can arrive as one unbroken run with no spaces.
            // Without a hard split that becomes a single chunk far past the
            // model's context window.
            guard word.count <= budget else {
                flushBuffer()
                var remainder = Substring(word)
                while !remainder.isEmpty {
                    let slice = remainder.prefix(budget)
                    pieces.append(String(slice))
                    remainder = remainder.dropFirst(slice.count)
                }
                continue
            }
            if length + word.count + 1 > budget { flushBuffer() }
            buffer.append(word)
            length += word.count + 1
        }
        flushBuffer()

        let span = pieces.isEmpty ? 0 : totalDuration / Double(pieces.count)
        return pieces.enumerated().map { index, piece in
            TranscriptChunk(
                index: index,
                startSeconds: span * Double(index),
                endSeconds: span * Double(index + 1),
                text: piece
            )
        }
    }
}

/// Picking a readable sample from a transcript too long to send whole.
///
/// The review pass has to see the WHOLE lecture, not the start of it. A
/// 90-minute marketing transcript runs to nearly 60,000 characters and the
/// group activity — the thing the review exists to catch — begins three
/// quarters of the way in. Taking a prefix, which is the obvious thing to do,
/// guarantees the review never looks at the part most likely to be wrong.
///
/// So the sample is spread evenly across the whole recording, with the gaps
/// marked so nothing between two windows is mistaken for a join.
public enum TranscriptSampler {
    /// How many windows to spread across the transcript.
    ///
    /// What matters is the GAP between windows, not the count: a stretch of
    /// transcript longer than the gap cannot be missed entirely. Sixteen
    /// windows over a 60,000-character transcript at an 18,000-character budget
    /// leaves gaps of about 2,800 characters — under a minute of speech — while
    /// the thing this exists to catch, a group activity, runs for many minutes.
    public static let defaultWindows = 16

    public static func evenlySampled(
        _ text: String,
        budget: Int,
        windows: Int = defaultWindows
    ) -> String {
        let trimmed = text.trimmed
        guard budget > 0 else { return "" }
        guard trimmed.count > budget else { return trimmed }

        // Each window has to be long enough to read as prose rather than as a
        // handful of disconnected words.
        let windowCount = max(1, min(windows, budget / 400))
        guard windowCount > 1 else { return String(trimmed.prefix(budget)) }

        let windowSize = budget / windowCount
        let characters = Array(trimmed)
        // Windows start evenly across the text, and the last one ends at the
        // end: a lecture's closing minutes carry the summary and the homework.
        let span = max(1, characters.count - windowSize)
        var pieces: [String] = []

        for index in 0..<windowCount {
            let start = windowCount == 1
                ? 0
                : Int((Double(index) / Double(windowCount - 1)) * Double(span))
            let end = min(characters.count, start + windowSize)
            guard start < end else { continue }
            pieces.append(String(characters[start..<end]))
        }

        return pieces.joined(separator: "\n\n[…a stretch of the recording is not shown here…]\n\n")
    }

    /// The longest run of transcript that can fall entirely between two
    /// windows. Anything longer than this is guaranteed to be sampled.
    public static func largestGap(
        totalCharacters: Int,
        budget: Int,
        windows: Int = defaultWindows
    ) -> Int {
        guard totalCharacters > budget, budget > 0 else { return 0 }
        let windowCount = max(1, min(windows, budget / 400))
        guard windowCount > 1 else { return totalCharacters - budget }
        let windowSize = budget / windowCount
        let span = max(1, totalCharacters - windowSize)
        let stride = span / (windowCount - 1)
        return max(0, stride - windowSize)
    }
}
