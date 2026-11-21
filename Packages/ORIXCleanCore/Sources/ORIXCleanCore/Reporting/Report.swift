// ORIX Clean — Packages/ORIXCleanCore/Sources/ORIXCleanCore/Reporting/Report.swift
// Description: Report model and renderers (Markdown, CSV, JSON, PDF). Every figure comes from a measurement or a deletion record.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import CoreGraphics
import CoreText
import Foundation

public struct ReportSection: Codable, Sendable, Hashable {
    public var title: String
    public var facts: [[String]]
    public var headers: [String]
    public var rows: [[String]]
    public var note: String?
    public init(title: String, facts: [(String, String)] = [], headers: [String] = [], rows: [[String]] = [], note: String? = nil) {
        self.title = title
        self.facts = facts.map { [$0.0, $0.1] }
        self.headers = headers
        self.rows = rows
        self.note = note
    }
}

public enum ReportFormat: String, Sendable, CaseIterable, Codable {
    case pdf, csv, json, markdown
    public var fileExtension: String { self == .markdown ? "md" : rawValue }
    public var title: String { self == .markdown ? "Markdown" : rawValue.uppercased() }
}

public struct Report: Codable, Sendable, Hashable {
    public var title: String
    public var generated: Date
    public var scope: String
    /// What the scan could not see (permission limits, unreadable folders).
    public var limitations: [String]
    public var sections: [ReportSection]
    public var appVersion: String

    public init(title: String, scope: String, limitations: [String] = [], sections: [ReportSection], generated: Date = Date(), appVersion: String = "") {
        self.title = title
        self.generated = generated
        self.scope = scope
        self.limitations = limitations
        self.sections = sections
        self.appVersion = appVersion
    }

    public func render(_ format: ReportFormat) -> Data {
        switch format {
        case .markdown: return Data(markdown().utf8)
        case .csv: return Data(csv().utf8)
        case .json:
            let e = JSONEncoder()
            e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            e.dateEncodingStrategy = .iso8601
            return (try? e.encode(self)) ?? Data()
        case .pdf: return pdf()
        }
    }

    func markdown() -> String {
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }
        var out = "# \(title)\n\n"
        out += "- **\(L("Generated"))**: \(ByteFormat.dateTime(generated))\n- **\(L("Scope"))**: \(scope)\n"
        if !appVersion.isEmpty { out += "- **ORIX Clean**: \(appVersion)\n" }
        if !limitations.isEmpty {
            out += "\n## \(L("Limitations"))\n\n"
            for l in limitations { out += "- \(l)\n" }
        }
        for s in sections {
            out += "\n## \(s.title)\n\n"
            for f in s.facts where f.count == 2 { out += "- **\(f[0])**: \(f[1])\n" }
            if !s.headers.isEmpty {
                if !s.facts.isEmpty { out += "\n" }
                out += "| " + s.headers.map(esc).joined(separator: " | ") + " |\n"
                out += "|" + s.headers.map { _ in "---" }.joined(separator: "|") + "|\n"
                for r in s.rows { out += "| " + r.map(esc).joined(separator: " | ") + " |\n" }
            }
            if let n = s.note { out += "\n> \(n)\n" }
        }
        return out
    }

    func csv() -> String {
        func q(_ s: String) -> String {
            // Neutralise spreadsheet formulas, then quote.
            var v = s
            if let c = v.first, "=+-@\t\r".contains(c) { v = "'" + v }
            return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var lines: [String] = []
        lines.append([q("section"), q("kind"), q("values")].joined(separator: ","))
        lines.append([q(title), q("generated"), q(ISO8601DateFormatter().string(from: generated))].joined(separator: ","))
        lines.append([q(title), q("scope"), q(scope)].joined(separator: ","))
        for l in limitations { lines.append([q(title), q("limitation"), q(l)].joined(separator: ",")) }
        for s in sections {
            for f in s.facts where f.count == 2 { lines.append(([q(s.title), q("fact")] + f.map(q)).joined(separator: ",")) }
            if !s.headers.isEmpty { lines.append(([q(s.title), q("header")] + s.headers.map(q)).joined(separator: ",")) }
            for r in s.rows { lines.append(([q(s.title), q("row")] + r.map(q)).joined(separator: ",")) }
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    func pdf() -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data), let ctx = CGContext(consumer: consumer, mediaBox: &box,
                                                                             [kCGPDFContextTitle: title, kCGPDFContextCreator: "ORIX Clean"] as CFDictionary) else { return Data() }
        let margin: CGFloat = 48
        let width = box.width - 2 * margin
        var y: CGFloat = 0
        var page = 0
        func font(_ size: CGFloat, bold: Bool = false, mono: Bool = false) -> CTFont {
            let base = CTFontCreateUIFontForLanguage(mono ? .userFixedPitch : (bold ? .emphasizedSystem : .system), size, nil)
            return base ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        }
        func footer() {
            let text = "ORIX Clean · \(title) · \(page)"
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font(8),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.45, alpha: 1)]))
            ctx.textPosition = CGPoint(x: margin, y: 26)
            CTLineDraw(line, ctx)
        }
        func newPage() {
            if page > 0 { footer(); ctx.endPDFPage() }
            ctx.beginPDFPage(nil)
            page += 1
            y = box.height - margin
        }
        func draw(_ text: String, size: CGFloat, bold: Bool = false, mono: Bool = false, gray: CGFloat = 0.1, indent: CGFloat = 0, spacing: CGFloat = 4) {
            let attr = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font(size, bold: bold, mono: mono),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: gray, alpha: 1)])
            let setter = CTFramesetterCreateWithAttributedString(attr)
            var start = 0
            while start < attr.length {
                if y < margin + 30 { newPage() }
                let rect = CGRect(x: margin + indent, y: margin + 14, width: width - indent, height: y - margin - 14)
                let frame = CTFramesetterCreateFrame(setter, CFRange(location: start, length: 0), CGPath(rect: rect, transform: nil), nil)
                let visible = CTFrameGetVisibleStringRange(frame)
                if visible.length == 0 { newPage(); continue }
                CTFrameDraw(frame, ctx)
                let used = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: start, length: visible.length), nil,
                                                                        CGSize(width: rect.width, height: .greatestFiniteMagnitude), nil)
                y -= used.height + spacing
                start += visible.length
                if start < attr.length { newPage() }
            }
        }
        newPage()
        draw(title, size: 22, bold: true, spacing: 8)
        draw("\(L("Generated")): \(ByteFormat.dateTime(generated))    \(L("Scope")): \(scope)", size: 9.5, gray: 0.35, spacing: 2)
        if !appVersion.isEmpty { draw("ORIX Clean \(appVersion)", size: 9.5, gray: 0.35, spacing: 10) }
        if !limitations.isEmpty {
            draw(L("Limitations"), size: 13, bold: true, spacing: 4)
            for l in limitations { draw("• " + l, size: 9.5, gray: 0.25, indent: 8, spacing: 2) }
            y -= 8
        }
        for s in sections {
            y -= 6
            draw(s.title, size: 13, bold: true, spacing: 5)
            for f in s.facts where f.count == 2 { draw("\(f[0]): \(f[1])", size: 10, indent: 8, spacing: 2) }
            if !s.headers.isEmpty {
                y -= 4
                draw(s.headers.joined(separator: "   ·   "), size: 8.5, bold: true, gray: 0.3, indent: 8, spacing: 3)
                for r in s.rows { draw(r.joined(separator: "   ·   "), size: 8.5, indent: 8, spacing: 2) }
            }
            if let n = s.note { y -= 2; draw(n, size: 9, gray: 0.4, indent: 8, spacing: 4) }
        }
        footer()
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }
}

/// Builders that turn engine results into report sections.
public enum ReportBuilder {
    public static func limitations(issues: [ScanIssue], fullDiskAccess: Bool, sharingMeasured: Bool) -> [String] {
        var out: [String] = []
        if !fullDiskAccess { out.append(L("Full Disk Access was not granted: folders protected by macOS privacy controls were not read and are missing from the totals.")) }
        let denied = issues.filter { $0.kind == .permissionDenied }.count
        if denied > 0 { out.append(L("%d folders could not be read (permission denied). Their content is not counted.", denied)) }
        let other = issues.count - denied
        if other > 0 { out.append(L("%d items changed or disappeared during the scan.", other)) }
        out.append(sharingMeasured
            ? L("Recoverable space is an estimate. APFS can share blocks between files (clones) and local snapshots can keep removed data on disk until they expire.")
            : L("This filesystem does not report shared blocks; recoverable space equals allocated size and may be overstated."))
        return out
    }

    public static func overview(result: ScanResult, volume: VolumeInfo?, top: Int = 25) -> [ReportSection] {
        let tree = result.tree
        let root = tree[0]
        var sections: [ReportSection] = []
        var facts: [(String, String)] = [
            (L("Files"), ByteFormat.count(result.files)), (L("Folders"), ByteFormat.count(result.directories)),
            (L("Content size"), ByteFormat.string(root.logicalSize)), (L("Size on disk"), ByteFormat.string(root.allocatedSize)),
            (L("Scan duration"), String(format: "%.1f s", result.duration)),
        ]
        if let v = volume {
            facts.append((L("Volume"), "\(v.name) (\(v.format.uppercased()))"))
            facts.append((L("Volume capacity"), ByteFormat.string(v.total)))
            facts.append((L("Volume free space"), ByteFormat.string(v.available)))
        }
        sections.append(ReportSection(title: L("Storage overview"), facts: facts))
        let cats = TreeQuery.categories(in: tree)
        sections.append(ReportSection(title: L("By type"), headers: [L("Type"), L("Files"), L("Size on disk")],
                                      rows: cats.map { [$0.category.title, ByteFormat.count($0.files), ByteFormat.string($0.allocated)] }))
        sections.append(ReportSection(title: L("Largest folders"), headers: [L("Folder"), L("Size on disk"), L("Files")],
                                      rows: tree.sortedChildren(of: 0).prefix(top).filter { tree[$0].flags.contains(.directory) }.map {
                                          [tree.path(of: $0), ByteFormat.string(tree[$0].allocatedSize), ByteFormat.count(Int(tree[$0].fileCount))]
                                      }))
        sections.append(largestFiles(tree: tree, hits: TreeQuery.largestFiles(in: tree, limit: top)))
        return sections
    }

    public static func largestFiles(tree: ScanTree, hits: [FileHit]) -> ReportSection {
        ReportSection(title: L("Largest files"), headers: [L("File"), L("Size on disk"), L("Content size"), L("Modified")],
                      rows: hits.map { h in
                          let n = tree[h.node]
                          return [tree.path(of: h.node), ByteFormat.string(n.allocatedSize), ByteFormat.string(n.logicalSize),
                                  ByteFormat.date(Date(timeIntervalSince1970: TimeInterval(n.modified)))]
                      })
    }

    public static func duplicates(_ r: DuplicateResult, top: Int = 200) -> [ReportSection] {
        var sections = [ReportSection(title: L("Duplicate analysis"), facts: [
            (L("Groups"), ByteFormat.count(r.groups.count)), (L("Files compared"), ByteFormat.count(r.candidates)),
            (L("Content in extra copies"), ByteFormat.string(r.redundantLogical)), (L("Data hashed"), ByteFormat.string(r.bytesHashed)),
            (L("Unreadable files"), ByteFormat.count(r.unreadable.count)),
        ], note: L("Groups are files with the same SHA-256 digest. Extra-copy size is content size; clones and hard links free less."))]
        var rows: [[String]] = []
        for g in r.groups.prefix(top) { for f in g.files { rows.append([String(g.digest.prefix(12)), ByteFormat.string(g.logicalSize), f.path,
                                                                        f.hardLinkPaths.isEmpty ? (f.mayShareBlocks ? L("may share blocks") : "") : L("hard-linked")]) } }
        sections.append(ReportSection(title: L("Duplicate groups"), headers: [L("Digest"), L("Size"), L("Path"), L("Storage")], rows: rows))
        return sections
    }

    public static func similar(_ r: SimilarResult) -> [ReportSection] {
        var rows: [[String]] = []
        for (i, g) in r.groups.enumerated() { for img in g.images { rows.append(["\(i + 1)", "\(Int(g.confidence * 100)) %", "\(img.pixelWidth)×\(img.pixelHeight)",
                                                                                 ByteFormat.string(img.logicalSize), img.path]) } }
        return [ReportSection(title: L("Similar images"), facts: [(L("Images examined"), ByteFormat.count(r.imagesExamined)), (L("Groups"), ByteFormat.count(r.groups.count)),
                                                                  (L("Unreadable images"), ByteFormat.count(r.unreadable))],
                              headers: [L("Group"), L("Confidence"), L("Pixels"), L("Size"), L("Path")], rows: rows,
                              note: L("Perceptual similarity is not equality. Review every group before removing anything."))]
    }

    public static func candidates(title: String, items: [CleanupItem]) -> [ReportSection] {
        let plan = CleanupPlan(items: items)
        return [ReportSection(title: title, facts: [(L("Items"), ByteFormat.count(plan.items.count)), (L("Content size"), ByteFormat.string(plan.logicalSize)),
                                                    (L("Size on disk"), ByteFormat.string(plan.allocatedSize)), (L("Estimated recoverable"), plan.recoverable.text)],
                              headers: [L("Path"), L("Owner"), L("Risk"), L("Size on disk"), L("Reason")],
                              rows: plan.items.map { [$0.path, $0.owner ?? "", $0.risk.title, ByteFormat.string($0.measurement.allocated), $0.reason] })]
    }

    public static func cleanupResults(_ d: DeletionReport) -> [ReportSection] {
        var facts: [(String, String)] = [(L("Started"), ByteFormat.dateTime(d.started)), (L("Finished"), ByteFormat.dateTime(d.finished))]
        for s in DeletionStatus.allCases where d.count(s) > 0 { facts.append((s.title, "\(d.count(s)) · \(ByteFormat.string(d.allocated(s)))")) }
        if let a = d.freeBefore, let b = d.freeAfter {
            facts.append((L("Free space before"), ByteFormat.string(a)))
            facts.append((L("Free space after"), ByteFormat.string(b)))
        }
        let note = d.mode == .moveToTrash
            ? L("Items moved to the Trash still occupy disk space until the Trash is emptied.")
            : L("Permanently deleted items cannot be recovered without a backup.")
        return [ReportSection(title: L("Cleanup results"), facts: facts, headers: [L("Path"), L("Outcome"), L("Size on disk"), L("Detail")],
                              rows: d.records.map { [$0.path, $0.status.title, ByteFormat.string($0.allocatedSize), $0.detail] }, note: note)]
    }

    public static func trends(samples: [VolumeSample], volume: VolumeInfo) -> [ReportSection] {
        var facts: [(String, String)] = [(L("Volume"), volume.name), (L("Samples"), ByteFormat.count(samples.count))]
        if let first = samples.first { facts.append((L("Monitoring since"), ByteFormat.dateTime(first.date))) }
        if let slope = Trend.bytesPerDay(samples) { facts.append((L("Change in used space per day"), (slope < 0 ? "−" : "+") + ByteFormat.string(Int64(abs(slope))))) }
        return [ReportSection(title: L("Storage trends"), facts: facts, headers: [L("Date"), L("Used"), L("Free")],
                              rows: samples.suffix(400).map { [ByteFormat.dateTime($0.date), ByteFormat.string($0.used), ByteFormat.string($0.available)] },
                              note: L("History exists only from the first sample recorded by ORIX Clean, and only while the application was running."))]
    }
}
