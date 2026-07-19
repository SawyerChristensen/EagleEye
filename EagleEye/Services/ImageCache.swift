//
//  ImageCache.swift
//  EagleEye
//
//  A small memory + disk cache for remote images (member portraits).
//

import SwiftUI
import CoreImage
import ImageIO

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

/// Caches remote images in memory and on disk, keyed by their URL.
///
/// The default `AsyncImage` re-fetches a portrait every time its view appears
/// and relies solely on the URL cache's HTTP headers, so opening the
/// representatives page can flash placeholders and hit the network again on each
/// launch. Portrait URLs are stable, so we persist the downloaded image to the
/// caches directory: after the first fetch it loads instantly, even across app
/// launches, and only falls back to the network on a cache miss.
actor ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, PlatformImage>()
    private let directory: URL
    /// Tracks in-progress downloads so concurrent requests for the same URL
    /// share a single network fetch instead of each starting their own.
    private var inFlight: [URL: Task<PlatformImage?, Never>] = [:]

    /// Bounds how many disk/decode/network loads run concurrently. Each load does
    /// blocking disk I/O and a heavy Core Image pass inside a detached task on the
    /// cooperative thread pool; firing hundreds at once (e.g. every pin in the
    /// map's viewport) exhausts that pool, so even URLSession's completion
    /// continuations can't resume and every load appears to hang forever. Gating
    /// keeps a handful in flight and lets the rest drain in turn.
    private static let maxConcurrentLoads = 6
    private var availableSlots = ImageCache.maxConcurrentLoads
    private var slotWaiters: [CheckedContinuation<Void, Never>] = []

    /// Waits until a load slot is free, then claims it. Pair every successful
    /// return with a `releaseSlot()`.
    private func acquireSlot() async {
        if availableSlots > 0 {
            availableSlots -= 1
            return
        }
        await withCheckedContinuation { slotWaiters.append($0) }
    }

    /// Releases a load slot, handing it directly to the next waiter if any.
    private func releaseSlot() {
        if slotWaiters.isEmpty {
            availableSlots += 1
        } else {
            slotWaiters.removeFirst().resume()
        }
    }

    /// A dedicated queue for the blocking parts of a load (disk I/O, ImageIO
    /// decode, Core Image enhance), kept off Swift's cooperative thread pool so
    /// those steps can't starve it. Concurrent, so gated loads still parallelize.
    private static let processingQueue = DispatchQueue(
        label: "ImageCache.processing", qos: .userInitiated, attributes: .concurrent
    )

    /// Runs `work` on `processingQueue`, suspending the caller until it finishes
    /// without occupying a cooperative-pool thread while it blocks.
    private nonisolated static func offPool(_ work: @escaping () -> PlatformImage?) async -> PlatformImage? {
        await withCheckedContinuation { continuation in
            processingQueue.async {
                continuation.resume(returning: work())
            }
        }
    }

    /// Portraits never render larger than a profile header, so there's no reason
    /// to keep full-resolution bitmaps around. Decoding down to this max pixel
    /// dimension slashes the per-image memory footprint (a 1200×1500 source is
    /// ~7 MB decoded; at 600 px it's ~1.4 MB), which is what stops the district
    /// map's overlay memory from triggering a warning that purges this cache.
    private static let maxPixelDimension: CGFloat = 600

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("CachedImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Bound the in-memory cache by total decoded bytes so it can't itself
        // balloon while the map browses dozens of pins. NSCache still evicts
        // early under system memory pressure — but because every image is also
        // on disk, a purge just means a fast disk reload, not a lost photo.
        memory.totalCostLimit = 48 * 1024 * 1024 // ~48 MB of decoded pixels
    }

    /// Returns the image for `url`, reading from the memory cache, then disk,
    /// then the network — persisting each newly fetched image for next time.
    /// Returns `nil` if the image can't be loaded.
    ///
    /// `priority` sets the priority of the underlying work. On-screen portraits
    /// use the default; a bulk `prefetch` warms the cache at a lower priority so
    /// it never competes with a portrait the user is actually looking at.
    func image(for url: URL, priority: TaskPriority = .medium) async -> PlatformImage? {
        let key = Self.key(for: url)

        if let cached = memory.object(forKey: key) {
            return cached
        }

        // Coalesce concurrent requests for the same URL onto one task. This also
        // means a high-priority portrait awaiting an in-flight low-priority
        // prefetch escalates that task, so the visible pin isn't stuck behind it.
        if let existing = inFlight[url] {
            return await existing.value
        }

        // Wait for a load slot before doing any heavy work (see `maxConcurrentLoads`).
        await acquireSlot()

        // If the caller (e.g. a map pin panned off-screen) was cancelled while we
        // waited in line, give the slot back without doing the work.
        if Task.isCancelled {
            releaseSlot()
            return nil
        }

        // Another caller may have finished this URL while we waited for a slot.
        if let cached = memory.object(forKey: key) {
            releaseSlot()
            return cached
        }
        if let existing = inFlight[url] {
            releaseSlot()
            return await existing.value
        }

        // The blocking steps of a load — disk read, ImageIO decode, and the Core
        // Image "auto-enhance" — are dispatched to `processingQueue` (see `offPool`)
        // rather than run here on the cooperative thread pool. Those steps block
        // their thread; running them on the cooperative pool at any real
        // concurrency starves it, deadlocking the actor and MainActor
        // continuations that need a pool thread to resume — which made every map
        // portrait load hang forever right inside `autoEnhanced`. Only the truly
        // async network fetch stays on this task.
        let task = Task<PlatformImage?, Never>(priority: priority) { [directory] in
            let fileURL = directory.appendingPathComponent(key as String)

            if let diskImage = await Self.offPool({
                guard let data = try? Data(contentsOf: fileURL),
                      let image = Self.downsampledImage(from: data, maxDimension: Self.maxPixelDimension)
                else { return nil }
                return Self.autoEnhanced(image)
            }) {
                return diskImage
            }

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(from: url)
            } catch {
                print("🖼️ [Cache] network ERROR for \(url.lastPathComponent): \(error.localizedDescription)")
                return nil
            }

            if let http = response as? HTTPURLResponse {
                guard 200..<300 ~= http.statusCode else {
                    print("🖼️ [Cache] HTTP \(http.statusCode) for \(url.lastPathComponent)")
                    return nil
                }
            }

            return await Self.offPool({
                guard let image = Self.downsampledImage(from: data, maxDimension: Self.maxPixelDimension) else {
                    print("🖼️ [Cache] DECODE FAILED (\(data.count) bytes) for \(url.lastPathComponent)")
                    return nil
                }
                try? data.write(to: fileURL)
                return Self.autoEnhanced(image)
            })
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        releaseSlot()

        if let image {
            memory.setObject(image, forKey: key, cost: Self.decodedByteCost(of: image))
        }
        return image
    }

    /// Approximate decoded size in bytes (4 bytes per pixel), used as the
    /// `NSCache` cost so `totalCostLimit` reflects real memory use.
    private static func decodedByteCost(of image: PlatformImage) -> Int {
        #if canImport(UIKit)
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        #elseif canImport(AppKit)
        let pixels = image.size.width * image.size.height
        #endif
        return Int(pixels) * 4
    }

    /// Decodes `data` directly to a bitmap no larger than `maxDimension` on its
    /// longest edge, using ImageIO's thumbnail path so the full-resolution image
    /// is never materialized in memory. Returns `nil` only if the data isn't a
    /// decodable image.
    private static func downsampledImage(from data: Data, maxDimension: CGFloat) -> PlatformImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            // Fall back to a plain decode if thumbnail generation isn't available
            // for this format, so we still get an image rather than nothing.
            return PlatformImage(data: data)
        }
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cgImage, size: .zero)
        #endif
    }

    /// Warms the cache for `urls` in the given order, only a handful at a time,
    /// so the earliest (highest-priority) subjects are ready first without firing
    /// hundreds of downloads and Core Image renders simultaneously. Already-cached
    /// URLs return immediately, so re-running this is cheap. Runs at a low
    /// priority by default so it yields to portraits the user is looking at.
    func prefetch(_ urls: [URL], concurrency: Int = 6, priority: TaskPriority = .utility) async {
        var next = 0
        var loaded = 0
        var failed = 0
        await withTaskGroup(of: Bool.self) { group in
            // Keep at most `concurrency` loads running: seed that many workers,
            // then start one more each time an earlier one finishes.
            func addNext() -> Bool {
                guard next < urls.count else { return false }
                let url = urls[next]
                next += 1
                group.addTask(priority: priority) {
                    await self.image(for: url, priority: priority) != nil
                }
                return true
            }
            for _ in 0..<max(1, concurrency) where addNext() {}
            for await ok in group {
                if ok { loaded += 1 } else { failed += 1 }
                _ = addNext()
            }
        }
        print("🖼️ [Cache] prefetch tally — loaded=\(loaded) failed=\(failed) of \(urls.count)")
    }

    /// A filesystem-safe, deterministic filename for a URL, stable across launches.
    private static func key(for url: URL) -> NSString {
        let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        return (encoded ?? String(abs(url.absoluteString.hashValue))) as NSString
    }

    private static let ciContext = CIContext()

    /// Applies the same auto-enhance adjustments as Photos' "magic wand" (exposure,
    /// contrast, shadow, and highlight correction) so dim or poorly lit official
    /// portraits look consistently good without any manual editing.
    private static func autoEnhanced(_ image: PlatformImage) -> PlatformImage {
        #if canImport(UIKit)
        guard let cgSource = image.cgImage else { return image }
        #elseif canImport(AppKit)
        guard let cgSource = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        #endif

        var ciImage = CIImage(cgImage: cgSource)
        let filters = ciImage.autoAdjustmentFilters()
        guard !filters.isEmpty else { return image }

        for filter in filters {
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            if let output = filter.outputImage {
                ciImage = output
            }
        }

        guard let cgOutput = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return image
        }

        #if canImport(UIKit)
        return UIImage(cgImage: cgOutput, scale: image.scale, orientation: image.imageOrientation)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cgOutput, size: image.size)
        #endif
    }
}

/// A drop-in replacement for `AsyncImage` that loads through `ImageCache`, so a
/// portrait fetched once is reused instantly on later appearances and future
/// launches. Mirrors `AsyncImage`'s content/placeholder API.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: Image?
    /// The URL the current `image` was loaded for, so we can tell a genuine
    /// subject change (recycled view) apart from a plain reappearance.
    @State private var loadedURL: URL?

    var body: some View {
        Group {
            if let image {
                content(image)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            // Only drop the shown image when this view is being reused for a
            // *different* subject — e.g. MapKit recycling an annotation view as
            // the camera pans, where `url` changes and this task restarts.
            // Clearing then prevents the previous subject's photo lingering on
            // the wrong pin. On a plain reappearance (same `url`, e.g. switching
            // back to this tab), we keep the current photo so it doesn't flash
            // to a placeholder — the bug where portraits looked like they
            // "vanished" after visiting the map.
            if loadedURL != url {
                image = nil
            }
            guard let url else {
                loadedURL = nil
                return
            }
            // Already showing this subject — nothing to reload.
            if loadedURL == url, image != nil { return }

            if let platformImage = await ImageCache.shared.image(for: url) {
                // The await above suspends; if `url` changed (view recycled)
                // while we were loading, this task was cancelled — bail so a
                // stale, slow load can't overwrite the correct image.
                guard !Task.isCancelled else {
                    print("🖼️ [Img] cancelled after load: \(url.lastPathComponent)")
                    return
                }
                print("🖼️ [Img] loaded: \(url.lastPathComponent)")
                #if canImport(UIKit)
                image = Image(uiImage: platformImage)
                #elseif canImport(AppKit)
                image = Image(nsImage: platformImage)
                #endif
                loadedURL = url
            } else {
                print("🖼️ [Img] FAILED (nil): \(url.absoluteString)")
            }
        }
    }
}
