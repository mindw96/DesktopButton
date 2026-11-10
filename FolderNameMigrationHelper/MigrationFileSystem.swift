import Darwin
import Foundation

enum MigrationFailure: String, Error {
    case invalidLocation = "invalid-location"
    case invalidBundle = "invalid-bundle"
    case invalidSignature = "invalid-signature"
    case invalidParent = "invalid-parent"
    case parentTimeout = "parent-timeout"
    case sourceChanged = "source-changed"
    case destinationExists = "destination-exists"
    case readOnly = "read-only"
    case permissionDenied = "permission-denied"
    case moveFailed = "move-failed"
    case launchFailed = "launch-failed"
}

/// A same-directory rename only. No caller-supplied destination or replacement is allowed.
struct MigrationFileSystem {
    static let oldName = "OneButton.app"
    static let newName = "Folder In Bar.app"
    let source: URL
    let destination: URL
    private let device: dev_t
    private let inode: ino_t

    init(source: URL) throws {
        let source = source.standardizedFileURL
        guard source.lastPathComponent == Self.oldName else { throw MigrationFailure.invalidLocation }
        let info = try Self.directoryIdentity(at: source)
        self.source = source
        destination = source.deletingLastPathComponent().appendingPathComponent(Self.newName, isDirectory: true)
        device = info.st_dev
        inode = info.st_ino
    }

    func preflight() throws {
        try verifySource()
        var destinationInfo = stat()
        if lstat(destination.path, &destinationInfo) == 0 {
            throw MigrationFailure.destinationExists
        }
        guard errno == ENOENT else { throw Self.failure(for: errno) }
        let parent = source.deletingLastPathComponent()
        if try parent.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly == true {
            throw MigrationFailure.readOnly
        }
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw MigrationFailure.permissionDenied
        }
    }

    func rename() throws {
        // Recheck after the parent exits; never move a directory substituted during the wait.
        try verifySource()
        let parent = source.deletingLastPathComponent()
        let directory = open(parent.path, O_SEARCH | O_CLOEXEC)
        guard directory >= 0 else { throw Self.failure(for: errno) }
        defer { close(directory) }

        var info = stat()
        guard fstatat(directory, Self.oldName, &info, AT_SYMLINK_NOFOLLOW) == 0,
              Self.isDirectory(info), info.st_dev == device, info.st_ino == inode else {
            throw MigrationFailure.sourceChanged
        }
        guard renameatx_np(directory, Self.oldName, directory, Self.newName, UInt32(RENAME_EXCL)) == 0 else {
            throw Self.failure(for: errno)
        }
    }

    func verifySource() throws {
        let info = try Self.directoryIdentity(at: source)
        guard info.st_dev == device, info.st_ino == inode else { throw MigrationFailure.sourceChanged }
    }

    private static func directoryIdentity(at url: URL) throws -> stat {
        var info = stat()
        guard lstat(url.path, &info) == 0, isDirectory(info) else {
            throw MigrationFailure.sourceChanged
        }
        return info
    }

    private static func isDirectory(_ info: stat) -> Bool {
        (info.st_mode & S_IFMT) == S_IFDIR
    }

    private static func failure(for code: Int32) -> MigrationFailure {
        switch code {
        case EEXIST, ENOTEMPTY: return .destinationExists
        case EACCES, EPERM: return .permissionDenied
        case EROFS: return .readOnly
        case ENOENT: return .sourceChanged
        default: return .moveFailed
        }
    }
}
