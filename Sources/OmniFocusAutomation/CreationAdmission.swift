import Darwin
import Foundation
import OmniFocusCore

/// Kernel-owned per-key lock, shared across CLI/MCP processes. Never unlink lock files:
/// replacing an inode while another process holds it would bypass admission.
enum CreationAdmission {
    static func withLock<T>(directory: URL, key: String, operation: (_ firstUse: Bool) throws -> T) throws -> T {
        let manager = FileManager.default
        let root = directory.deletingLastPathComponent()
        for url in [root, directory] {
            if manager.fileExists(atPath: url.path) {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else {
                    throw MutationValidationError("Creation state directory is not a private regular directory.")
                }
            } else {
                try manager.createDirectory(at: url, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
            }
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
        let path = directory.appendingPathComponent(key + ".admission").path
        var descriptor = open(path, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        let firstUse = descriptor >= 0
        if descriptor < 0 && errno == EEXIST {
            descriptor = open(path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else { throw MutationValidationError("Cannot open private creation admission lock.") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw MutationValidationError("This creationKey is already in flight. Reconcile with the same key after it finishes; do not generate a new key.")
        }
        defer { flock(descriptor, LOCK_UN) }
        return try operation(firstUse)
    }
}
