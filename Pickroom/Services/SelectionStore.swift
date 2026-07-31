import Foundation

actor SelectionStore {
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let directory = support.appendingPathComponent("Pickroom", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("selections.json")
    }

    init(fileURL: URL, fileManager: FileManager = .default) {
        try? fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.fileURL = fileURL
    }

    func load() -> [String: StoredSelection] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let selections = try? JSONDecoder().decode([String: StoredSelection].self, from: data)
        else {
            return [:]
        }
        return selections
    }

    func save(_ selections: [String: StoredSelection]) {
        guard let data = try? JSONEncoder().encode(selections) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
