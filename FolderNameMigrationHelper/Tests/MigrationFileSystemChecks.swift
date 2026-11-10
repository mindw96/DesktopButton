import Darwin
import Foundation

// Run separately from the helper target:
// swiftc -parse-as-library MigrationFileSystem.swift Tests/MigrationFileSystemChecks.swift -o /tmp/migration-checks
@main
enum MigrationFileSystemChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("folder-name-migration-checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try check("successful rename preserves inode and contents", root: root) { directory in
            let source = try app(in: directory, name: MigrationFileSystem.oldName, contents: "original")
            let plan = try MigrationFileSystem(source: source)
            var before = stat()
            precondition(lstat(source.path, &before) == 0)
            try plan.preflight()
            try plan.rename()
            var after = stat()
            precondition(lstat(plan.destination.path, &after) == 0)
            precondition(before.st_ino == after.st_ino && before.st_dev == after.st_dev)
            precondition(!FileManager.default.fileExists(atPath: source.path))
            try expectContents("original", at: plan.destination)
        }

        try check("destination created after preflight is never replaced", root: root) { directory in
            let source = try app(in: directory, name: MigrationFileSystem.oldName, contents: "original")
            let plan = try MigrationFileSystem(source: source)
            try plan.preflight()
            let destination = try app(in: directory, name: MigrationFileSystem.newName, contents: "existing")
            try expect(.destinationExists) { try plan.rename() }
            try expectContents("original", at: source)
            try expectContents("existing", at: destination)
        }

        try check("substituted source is not renamed", root: root) { directory in
            let source = try app(in: directory, name: MigrationFileSystem.oldName, contents: "original")
            let plan = try MigrationFileSystem(source: source)
            try plan.preflight()
            let retained = directory.appendingPathComponent("retained.app")
            try FileManager.default.moveItem(at: source, to: retained)
            _ = try app(in: directory, name: MigrationFileSystem.oldName, contents: "replacement")
            try expect(.sourceChanged) { try plan.verifySource() }
            try expect(.sourceChanged) { try plan.rename() }
            try expectContents("original", at: retained)
            try expectContents("replacement", at: source)
            precondition(!FileManager.default.fileExists(atPath: plan.destination.path))
        }

        try check("source symlink is rejected", root: root) { directory in
            let actual = try app(in: directory, name: "actual.app", contents: "original")
            let source = directory.appendingPathComponent(MigrationFileSystem.oldName)
            try FileManager.default.createSymbolicLink(at: source, withDestinationURL: actual)
            try expect(.sourceChanged) { _ = try MigrationFileSystem(source: source) }
            try expectContents("original", at: actual)
        }

        try check("dangling destination symlink is never replaced", root: root) { directory in
            let source = try app(in: directory, name: MigrationFileSystem.oldName, contents: "original")
            let plan = try MigrationFileSystem(source: source)
            try FileManager.default.createSymbolicLink(at: plan.destination, withDestinationURL: directory.appendingPathComponent("missing"))
            try expect(.destinationExists) { try plan.preflight() }
            try expect(.destinationExists) { try plan.rename() }
            try expectContents("original", at: source)
            let link = try FileManager.default.destinationOfSymbolicLink(atPath: plan.destination.path)
            precondition(link.hasSuffix("/missing"))
        }

        try check("custom app names are not migration targets", root: root) { directory in
            let source = try app(in: directory, name: "Custom.app", contents: "original")
            try expect(.invalidLocation) { _ = try MigrationFileSystem(source: source) }
            try expectContents("original", at: source)
        }
        try check("rename requires search and write access, not directory listing", root: root) { directory in
            let source = try app(in: directory, name: MigrationFileSystem.oldName, contents: "original")
            let plan = try MigrationFileSystem(source: source)
            precondition(chmod(directory.path, 0o333) == 0)
            defer { _ = chmod(directory.path, 0o700) }
            try plan.preflight()
            try plan.rename()
            try expectContents("original", at: plan.destination)
        }
        print("PASS: 7 migration filesystem checks")
    }

    private static func check(_ name: String, root: URL, body: (URL) throws -> Void) throws {
        let directory = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try body(directory)
        print("PASS: \(name)")
    }

    private static func app(in parent: URL, name: String, contents: String) throws -> URL {
        let url = parent.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        try contents.write(to: url.appendingPathComponent("sentinel"), atomically: true, encoding: .utf8)
        return url
    }

    private static func expectContents(_ expected: String, at app: URL) throws {
        let actual = try String(contentsOf: app.appendingPathComponent("sentinel"), encoding: .utf8)
        precondition(actual == expected)
    }

    private static func expect(_ failure: MigrationFailure, body: () throws -> Void) throws {
        do {
            try body()
            preconditionFailure("Expected \(failure)")
        } catch let actual as MigrationFailure {
            precondition(actual == failure, "Expected \(failure), got \(actual)")
        }
    }
}
