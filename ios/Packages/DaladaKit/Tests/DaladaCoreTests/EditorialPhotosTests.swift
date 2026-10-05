import Foundation
import Testing
@testable import DaladaCore

@Suite("Фото редакции")
struct EditorialPhotosTests {
    @Test func decodesRPCRow() throws {
        let rows = try JSONDecoder().decode([EditorialPhoto].self, from: Data("""
        [{"id": "fffffff0-0000-0000-0000-000000000001", "path": "photos/places/fffffff0-0000-0000-0000-000000000001.jpg",
          "thumb_path": "photos/places/fffffff0-0000-0000-0000-000000000001_thumb.jpg", "width": 2000, "height": 1500,
          "author": "Автор", "license": "CC BY-SA 4.0", "license_url": "https://creativecommons.org/licenses/by-sa/4.0",
          "source_url": "https://commons.wikimedia.org/wiki/File:Lake.jpg"},
         {"id": "fffffff0-0000-0000-0000-000000000002", "path": "photos/places/2.jpg", "thumb_path": "photos/places/2_thumb.jpg",
          "width": null, "height": null, "author": "B", "license": "CC0", "license_url": null, "source_url": null}]
        """.utf8))
        #expect(rows.count == 2)
        #expect(rows[0].license == "CC BY-SA 4.0")
        #expect(rows[0].sourceURL?.absoluteString == "https://commons.wikimedia.org/wiki/File:Lake.jpg")
        #expect(rows[1].licenseURL == nil)
    }

    @Test func publicFilesAreNotInBucket() {
        #expect(MediaPath.isPublicFile("photos/places/x_thumb.jpg"))
        let owner = UUID()
        #expect(!MediaPath.isPublicFile(MediaPath.full(owner: owner, media: UUID())))
        #expect(!MediaPath.isPublicFile(MediaPath.thumbnail(owner: owner, media: UUID())))
    }

    @Test func galleryPutsEditorialFirst() {
        let editorial = EditorialPhoto(
            id: UUID(), path: "photos/places/e.jpg", thumbnailPath: "photos/places/e_thumb.jpg",
            author: "A", license: "CC0"
        )
        let visitor = PlacePhoto(
            id: UUID(), checkinID: UUID(), path: "u/v.jpg", thumbnailPath: "u/v_thumb.jpg", at: .now,
            author: FeedAuthor(id: UUID(), username: "u", displayName: nil)
        )
        let gallery = PlaceGalleryPhoto.gallery(editorial: [editorial], visitors: [visitor])
        #expect(gallery.map(\.id) == [editorial.id, visitor.id])
        #expect(gallery.map(\.thumbnailPath) == ["photos/places/e_thumb.jpg", "u/v_thumb.jpg"])
    }
}
