import Foundation
import Testing
@testable import DaladaCore

@Suite("Экспорт")
struct ExportTests {
    @Test func decodesTrackPoints() throws {
        let points = try JSONDecoder().decode([ExportedTrackPoint].self, from: Data("""
        [[77.001, 43.901, 481.0, 1790831100], [77.002, 43.902, null, 0]]
        """.utf8))
        #expect(points[0] == ExportedTrackPoint(longitude: 77.001, latitude: 43.901, altitude: 481, time: Date(timeIntervalSince1970: 1790831100)))
        #expect(points[1].altitude == nil)
        #expect(points[1].time == nil, "время 0 — неизвестно")
    }

    @Test func writesGPX() {
        let gpx = GPX.document(name: "Капшагай & <рыба>", points: [
            ExportedTrackPoint(longitude: 77.0, latitude: 43.9, altitude: 480, time: Date(timeIntervalSince1970: 1790830800)),
            ExportedTrackPoint(longitude: 77.001, latitude: 43.901),
        ])
        #expect(gpx.hasPrefix(#"<?xml version="1.0" encoding="UTF-8"?>"#))
        #expect(gpx.contains("<name>Капшагай &amp; &lt;рыба&gt;</name>"))
        #expect(gpx.contains(#"<trkpt lat="43.900000" lon="77.000000"><ele>480.0</ele><time>2026-10-01T05:00:00Z</time></trkpt>"#))
        #expect(gpx.contains(#"<trkpt lat="43.901000" lon="77.001000"></trkpt>"#))
        #expect(gpx.hasSuffix("</gpx>\n"))
    }

    @Test func fileNamesAreSafe() {
        #expect(ExportFileName.gpx(title: "Капшагай: утро/вечер", day: "2026-10-01T05:00:00+00:00") == "Капшагай утро вечер 2026-10-01.gpx")
        #expect(ExportFileName.gpx(title: "  ", day: "2026-10-01") == "Dalada 2026-10-01.gpx")
    }

    @Test func outlineNamesTripsWithoutClashes() throws {
        let outline = try ExportOutline.decode(Data("""
        {"format": "dalada-export", "trips": [
          {"id": "77777777-0000-0000-0000-000000000001", "title": "Залив", "started_at": "2026-10-01T05:00:00+00:00", "track": [[77, 43.9, 480, 1]]},
          {"id": "77777777-0000-0000-0000-000000000002", "title": "Залив", "started_at": "2026-10-01T09:00:00.5+00:00", "track": [[77, 43.9, 480, 1]]},
          {"id": "77777777-0000-0000-0000-000000000003", "title": null, "started_at": "2026-10-02T05:00:00+00:00", "track": []}
        ], "photos": [{"id": "eeeeeeee-0000-0000-0000-000000000001", "storage_path": "u/e.jpg", "width": 10}]}
        """.utf8))
        let names = outline.gpxFileNames()
        #expect(Set(names.values) == ["Залив 2026-10-01.gpx", "Залив 2026-10-01 (2).gpx"])
        #expect(names.count == 2, "поездка без трека — без файла")
        #expect(outline.photos.first?.storagePath == "u/e.jpg")
    }
}
