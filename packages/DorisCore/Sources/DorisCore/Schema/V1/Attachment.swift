import Foundation
import DorisIPC
import SwiftData

@Model
public final class Attachment {
    public var id: UUID = UUID()
    public var filename: String = ""
    public var mimeType: String = ""
    public var byteCount: Int = 0
    public var relativePath: String = ""
    public var createdAt: Date = Date()

    /// Image bytes, for an image placed in a note's body (1.9.0). Kept out
    /// of the SQLite row and mirrored to CloudKit as an asset, so it syncs.
    /// `relativePath` predates this: a file in the local App Group that
    /// never left the device.
    @Attribute(.externalStorage) public var data: Data?

    /// Pixel size of `data`, so a body can reserve an image's height before
    /// its bytes are loaded — or before they have synced. Zero for
    /// attachments that aren't body images.
    public var pixelWidth: Int = 0
    public var pixelHeight: Int = 0

    public var note: Note?
    public var message: Message?

    public init(
        id: UUID = UUID(),
        filename: String,
        mimeType: String,
        byteCount: Int,
        relativePath: String,
        note: Note? = nil,
        message: Message? = nil
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.relativePath = relativePath
        self.note = note
        self.message = message
        self.createdAt = Date()
    }
}
