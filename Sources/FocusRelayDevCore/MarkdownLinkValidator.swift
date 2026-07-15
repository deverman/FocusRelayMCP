import Foundation
import Markdown

public struct BrokenMarkdownLink: Equatable, Sendable {
    public let source: String
    public let destination: String

    public init(source: String, destination: String) {
        self.source = source
        self.destination = destination
    }
}

public enum MarkdownLinkValidator {
    public static func validate(root: URL, fileManager: FileManager = .default) throws -> [BrokenMarkdownLink] {
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let markdownFiles = try markdownFiles(below: resolvedRoot, fileManager: fileManager)
        return try markdownFiles.flatMap { file in
            let resolvedFile = file.standardizedFileURL.resolvingSymlinksInPath()
            let document = Document(parsing: try String(contentsOf: resolvedFile, encoding: .utf8))
            let broken: [BrokenMarkdownLink] = localDestinations(in: document).compactMap { destination in
                guard let relativePath = localPath(from: destination) else { return nil }
                let resolved = resolvedFile.deletingLastPathComponent()
                    .appendingPathComponent(relativePath)
                    .standardizedFileURL
                guard !fileManager.fileExists(atPath: resolved.path) else { return nil }
                let sourcePrefix = resolvedRoot.path + "/"
                let source = resolvedFile.path.hasPrefix(sourcePrefix)
                    ? String(resolvedFile.path.dropFirst(sourcePrefix.count))
                    : resolvedFile.lastPathComponent
                return BrokenMarkdownLink(
                    source: source,
                    destination: destination
                )
            }
            return broken
        }
    }

    private static func markdownFiles(below root: URL, fileManager: FileManager) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return enumerator.allObjects.compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "md" && !$0.pathComponents.contains(".build") }
            .sorted { $0.path < $1.path }
    }

    private static func localDestinations(in markup: Markup) -> [String] {
        var destinations: [String] = []
        if let link = markup as? Link, let destination = link.destination {
            destinations.append(destination)
        }
        if let image = markup as? Image, let source = image.source {
            destinations.append(source)
        }
        for child in markup.children {
            destinations.append(contentsOf: localDestinations(in: child))
        }
        return destinations
    }

    private static func localPath(from destination: String) -> String? {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("#"),
              !trimmed.hasPrefix("/"),
              URL(string: trimmed)?.scheme == nil else { return nil }

        let withoutFragment = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let withoutQuery = withoutFragment.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
        guard !withoutQuery.isEmpty else { return nil }
        return String(withoutQuery).removingPercentEncoding ?? String(withoutQuery)
    }
}
