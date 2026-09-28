import Foundation

/// One remembered person: a name and the average of the voiceprints it was given to.
public struct VoiceProfile: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    /// Unit length, so distances between profiles and new voices are comparable.
    public let embedding: [Float]
    /// How many recordings the average is made of.
    public let samples: Int
    public let updatedAt: Date

    public init(id: UUID, name: String, embedding: [Float], samples: Int, updatedAt: Date) {
        self.id = id
        self.name = name
        self.embedding = embedding
        self.samples = samples
        self.updatedAt = updatedAt
    }
}

/// The people whose voices the app has learned. When the person names a voice, its voiceprint is remembered under
/// that name; in later recordings a voice close enough to a remembered one is named automatically. Everything stays
/// in one file in the library folder and can be forgotten at any time.
public struct VoiceBook: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let empty = VoiceBook(profiles: [])

    /// Largest distance (Euclidean, unit-length vectors, range 0…2) at which a voice counts as a remembered person.
    /// FluidAudio merges voices within one recording at 0.6; across recordings the microphone, room and codec differ,
    /// so a little more slack is allowed. Equivalent to a cosine similarity of about 0.75.
    public static let maximumDistance: Float = 0.7

    public let version: Int
    public let profiles: [VoiceProfile]

    public init(profiles: [VoiceProfile], version: Int = currentVersion) {
        self.version = version
        self.profiles = profiles
    }

    /// A copy that knows `embedding` as `name`. The same name (ignoring case and surrounding spaces) refines the
    /// existing profile; a new name becomes a new profile. An empty name or an unusable embedding changes nothing.
    public func remembering(
        _ name: String, embedding: [Float], at date: Date = Date(), makeID: () -> UUID = UUID.init
    ) -> VoiceBook {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let voice = Self.normalized(embedding) else { return self }

        guard let index = profiles.firstIndex(where: { Self.sameName($0.name, trimmed) }) else {
            let added = VoiceProfile(id: makeID(), name: trimmed, embedding: voice, samples: 1, updatedAt: date)
            return VoiceBook(profiles: profiles + [added], version: version)
        }
        let known = profiles[index]
        guard known.embedding.count == voice.count else { return self }
        let weight = Float(known.samples)
        let mean = zip(known.embedding, voice).map { ($0 * weight + $1) / (weight + 1) }
        let refined = VoiceProfile(
            id: known.id, name: trimmed, embedding: Self.normalized(mean) ?? known.embedding,
            samples: known.samples + 1, updatedAt: date
        )
        var updated = profiles
        updated[index] = refined
        return VoiceBook(profiles: updated, version: version)
    }

    public func forgetting(_ profileID: VoiceProfile.ID) -> VoiceBook {
        VoiceBook(profiles: profiles.filter { $0.id != profileID }, version: version)
    }

    /// Names for the voices of a new recording, keyed by transcript label. The closest pairs are taken first and
    /// each person and each voice is used at most once, so two voices in one call never get the same name.
    public func names(for voices: [String: [Float]]) -> [String: String] {
        let pairs = voices.flatMap { label, embedding in
            profiles.compactMap { profile -> (label: String, profile: VoiceProfile, distance: Float)? in
                let distance = Self.distance(embedding, profile.embedding)
                return distance <= Self.maximumDistance ? (label, profile, distance) : nil
            }
        }
        var assigned: [String: String] = [:]
        var usedProfiles: Set<UUID> = []
        for pair in pairs.sorted(by: { ($0.distance, $0.label) < ($1.distance, $1.label) }) {
            guard assigned[pair.label] == nil, !usedProfiles.contains(pair.profile.id) else { continue }
            assigned[pair.label] = pair.profile.name
            usedProfiles.insert(pair.profile.id)
        }
        return assigned
    }

    /// Euclidean distance between the unit-length versions of two embeddings; unrelated sizes or an empty vector
    /// are infinitely far apart.
    static func distance(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, let left = normalized(lhs), let right = normalized(rhs) else { return .infinity }
        return zip(left, right).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }.squareRoot()
    }

    static func normalized(_ vector: [Float]) -> [Float]? {
        let length = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard !vector.isEmpty, length.isFinite, length > 0 else { return nil }
        return vector.map { $0 / length }
    }

    private static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

/// Reads and writes `voicebook.json` in the library folder (next to the recording folders, not inside one).
public enum VoiceBookStore {
    public static let fileName = "voicebook.json"

    public static func save(_ book: VoiceBook, in libraryDirectory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(book).write(to: libraryDirectory.appending(path: fileName), options: .atomic)
    }

    public static func load(from libraryDirectory: URL) throws -> VoiceBook {
        let file = libraryDirectory.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(VoiceBook.self, from: Data(contentsOf: file))
    }
}
