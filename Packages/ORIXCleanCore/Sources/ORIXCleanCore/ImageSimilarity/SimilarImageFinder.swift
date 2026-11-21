// ORIX Clean — Packages/ORIXCleanCore/Sources/ORIXCleanCore/ImageSimilarity/SimilarImageFinder.swift
// Description: Local near-duplicate image grouping: difference hash prefilter, Vision feature prints to confirm.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Accelerate
import CoreGraphics
import Foundation
import ImageIO
import Vision

public struct SimilarImageOptions: Sendable {
    public enum Mode: String, Sendable, CaseIterable {
        /// Difference-hash prefilter then Vision: finds resized, recompressed and lightly edited copies.
        case fast
        /// Vision feature prints for every pair: also finds crops. Limited to `thoroughLimit` images.
        case thorough
    }
    public var mode: Mode = .fast
    public var minimumSize: Int64 = 8 * 1024
    /// Hamming distance (of 64 bits) at or under which two images are called similar on structure alone.
    public var strongHashThreshold = 4
    /// Largest Hamming distance accepted when Vision also agrees.
    public var hashThreshold = 12
    /// Largest Vision distance accepted without structural agreement (thorough mode, finds crops).
    public var cropDistanceThreshold: Float = 0.25
    /// Largest Vision feature-print distance for two images to be called similar.
    public var distanceThreshold: Float = 0.36
    public var thoroughLimit = 3000
    public var under: Int32 = 0
    public init() {}
    public static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp"]
}

public struct SimilarImage: Sendable, Hashable, Identifiable {
    public var id: String { path }
    public var node: Int32
    public var path: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var logicalSize: Int64
    public var allocatedSize: Int64
    public var modified: Date
}

public struct SimilarGroup: Sendable, Hashable, Identifiable {
    public var id: String
    public var images: [SimilarImage]
    /// 0…1, from the largest measured distance between linked members. Perceptual similarity, never proof of equality.
    public var confidence: Double
    /// True when distances come from Vision; false when only the difference hash was available.
    public var visionConfirmed: Bool
}

public struct SimilarProgress: Sendable {
    public var done = 0
    public var total = 0
    public var stage = "fingerprint"
    public init() {}
    init(done: Int, total: Int, stage: String) { self.done = done; self.total = total; self.stage = stage }
}

public struct SimilarResult: Sendable {
    public var groups: [SimilarGroup]
    public var imagesExamined: Int
    public var unreadable: Int
    public var duration: TimeInterval
    public var mode: SimilarImageOptions.Mode
    public var cancelled: Bool
}

public final class SimilarImageFinder: @unchecked Sendable {
    private let lock = NSLock()
    private var state = SimilarProgress()
    private var cancelledFlag = false
    public init() {}
    public func cancel() { lock.lock(); cancelledFlag = true; lock.unlock() }
    public var progress: SimilarProgress { lock.lock(); defer { lock.unlock() }; return state }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelledFlag }

    struct Print {
        var hash: UInt64
        var width: Int
        var height: Int
        var vector: [Float]?
    }

    /// Blocking. Run it off the main thread.
    public func run(tree: ScanTree, options: SimilarImageOptions = SimilarImageOptions()) -> SimilarResult {
        let started = Date()
        var candidates: [Int32] = []
        let inside = TreeQuery.packageMembership(tree)
        tree.forEachFile(under: options.under) { i, n in
            if n.logicalSize < options.minimumSize || n.flags.contains(.dataless) || n.flags.contains(.hardLinkDuplicate) || inside[Int(i)] { return }
            if SimilarImageOptions.extensions.contains(tree.fileExtension(of: i)) { candidates.append(i) }
        }
        let paths = candidates.map { tree.path(of: $0) }
        var mode = options.mode
        if mode == .thorough, candidates.count > options.thoroughLimit { mode = .fast }
        lock.lock(); state = SimilarProgress(done: 0, total: candidates.count, stage: "fingerprint"); lock.unlock()

        let count = candidates.count
        let prints = UnsafeMutablePointer<Print?>.allocate(capacity: max(1, count))
        prints.initialize(repeating: nil, count: max(1, count))
        defer { prints.deinitialize(count: max(1, count)); prints.deallocate() }
        nonisolated(unsafe) let slots = prints
        let wantVector = mode == .thorough
        DispatchQueue.concurrentPerform(iterations: count) { k in
            if self.isCancelled { return }
            slots[k] = Self.fingerprint(path: paths[k], withVector: wantVector)
            self.lock.lock(); self.state.done += 1; self.lock.unlock()
        }
        if isCancelled {
            return SimilarResult(groups: [], imagesExamined: count, unreadable: 0, duration: Date().timeIntervalSince(started), mode: mode, cancelled: true)
        }
        let valid = (0 ..< count).filter { prints[$0] != nil }
        var parent = Array(0 ..< count)
        func find(_ x: Int) -> Int { var x = x; while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }; return x }
        var weakest = [Float](repeating: 1, count: count)
        var vision = true
        func link(_ a: Int, _ b: Int, _ score: Float) {
            let ra = find(a), rb = find(b)
            let w = min(weakest[ra], weakest[rb], score)
            if ra != rb { parent[ra] = rb }
            weakest[find(a)] = w
        }
        func vector(_ i: Int) -> [Float] {
            if prints[i]!.vector == nil { prints[i]!.vector = Self.fingerprint(path: paths[i], withVector: true)?.vector ?? [] }
            return prints[i]!.vector ?? []
        }
        /// Decides one pair from both measurements. Returns the link score (0…1) or nil.
        func judge(_ a: Int, _ b: Int, bits: Int) -> Float? {
            let structural = 1 - Float(bits) / 32
            if bits <= options.strongHashThreshold {
                // Near-identical structure: resized or recompressed copy. Vision only refines the score.
                return structural
            }
            let va = vector(a), vb = vector(b)
            guard !va.isEmpty, va.count == vb.count else { vision = false; return nil }
            let d = Self.distance(va, vb)
            let perceptual = 1 - d / (options.distanceThreshold * 2)
            if bits <= options.hashThreshold, d <= options.distanceThreshold { return max(structural, perceptual) }
            if mode == .thorough, d <= options.cropDistanceThreshold { return perceptual }
            return nil
        }

        var pairs: [(Int, Int, Int)] = []
        for (x, a) in valid.enumerated() {
            let ha = prints[a]!.hash
            for b in valid[(x + 1)...] {
                let bits = (ha ^ prints[b]!.hash).nonzeroBitCount
                if mode == .thorough || bits <= options.hashThreshold { pairs.append((a, b, bits)) }
            }
        }
        lock.lock(); state = SimilarProgress(done: 0, total: pairs.count, stage: "compare"); lock.unlock()
        // Score every candidate pair, then build clusters around a representative, best pairs first.
        // An image joins a cluster only if it is similar to the representative itself: no chains of "A~B, B~C" linking A and C.
        var scored: [(Int, Int, Float)] = []
        var scoreOf: [UInt64: Float] = [:]
        for (k, pair) in pairs.enumerated() {
            if k % 64 == 0 {
                if isCancelled { break }
                lock.lock(); state.done = k; lock.unlock()
            }
            if let score = judge(pair.0, pair.1, bits: pair.2) {
                scored.append((pair.0, pair.1, score))
                scoreOf[UInt64(min(pair.0, pair.1)) << 32 | UInt64(max(pair.0, pair.1))] = score
            }
        }
        scored.sort { $0.2 > $1.2 }
        var representative = [Int](repeating: -1, count: count)
        func score(_ a: Int, _ b: Int) -> Float? { scoreOf[UInt64(min(a, b)) << 32 | UInt64(max(a, b))] }
        for (a, b, s) in scored {
            switch (representative[a], representative[b]) {
            case (-1, -1):
                representative[a] = a; representative[b] = a
                link(a, b, s)
            case (let r, -1):
                if r == a { representative[b] = r; link(a, b, s) } else if let rs = score(r, b) { representative[b] = r; link(r, b, rs) }
            case (-1, let r):
                if r == b { representative[a] = r; link(a, b, s) } else if let rs = score(r, a) { representative[a] = r; link(r, a, rs) }
            default:
                break
            }
        }

        var members: [Int: [Int]] = [:]
        for i in valid { members[find(i), default: []].append(i) }
        var groups: [SimilarGroup] = []
        for (rootIndex, list) in members where list.count > 1 {
            let images = list.map { i -> SimilarImage in
                let n = tree[candidates[i]]
                return SimilarImage(node: candidates[i], path: paths[i], pixelWidth: prints[i]!.width, pixelHeight: prints[i]!.height,
                                    logicalSize: n.logicalSize, allocatedSize: n.allocatedSize,
                                    modified: Date(timeIntervalSince1970: TimeInterval(n.modified)))
            }.sorted { (a: SimilarImage, b: SimilarImage) -> Bool in
                let pa = a.pixelWidth * a.pixelHeight, pb = b.pixelWidth * b.pixelHeight
                return pa != pb ? pa > pb : a.path < b.path
            }
            let confidence = Double(max(0, min(1, weakest[rootIndex])))
            groups.append(SimilarGroup(id: images.map { $0.path }.min() ?? "", images: images, confidence: confidence, visionConfirmed: vision))
        }
        groups.sort { $0.images.reduce(0) { $0 + $1.allocatedSize } > $1.images.reduce(0) { $0 + $1.allocatedSize } }
        return SimilarResult(groups: isCancelled ? [] : groups, imagesExamined: count, unreadable: count - valid.count,
                             duration: Date().timeIntervalSince(started), mode: mode, cancelled: isCancelled)
    }

    static func distance(_ a: [Float], _ b: [Float]) -> Float {
        var d: Float = 0
        vDSP_distancesq(a, 1, b, 1, &d, vDSP_Length(a.count))
        return d.squareRoot()
    }

    /// Difference hash (9×8 grey) and, on request, a Vision feature print of a thumbnail no larger than 448 px.
    static func fingerprint(path: String, withVector: Bool) -> Print? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        var width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        var height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        if let o = props?[kCGImagePropertyOrientation] as? Int, o >= 5 { swap(&width, &height) }
        let thumbOptions: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                             kCGImageSourceThumbnailMaxPixelSize: 448, kCGImageSourceShouldCacheImmediately: true]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else { return nil }
        var grey = [UInt8](repeating: 0, count: 72)
        guard let ctx = CGContext(data: &grey, width: 9, height: 8, bitsPerComponent: 8, bytesPerRow: 9, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 9, height: 8))
        ctx.draw(thumb, in: CGRect(x: 0, y: 0, width: 9, height: 8))
        var hash: UInt64 = 0
        for row in 0 ..< 8 { for col in 0 ..< 8 { hash = (hash << 1) | (grey[row * 9 + col] > grey[row * 9 + col + 1] ? 1 : 0) } }
        var vector: [Float]?
        if withVector {
            let request = VNGenerateImageFeaturePrintRequest()
            request.imageCropAndScaleOption = .scaleFill
            let handler = VNImageRequestHandler(cgImage: thumb, options: [:])
            if (try? handler.perform([request])) != nil, let obs = request.results?.first as? VNFeaturePrintObservation, obs.elementType == .float {
                vector = obs.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            } else {
                vector = []
            }
        }
        return Print(hash: hash, width: width, height: height, vector: vector)
    }
}
