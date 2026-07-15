//
//  ImageCache.swift
//  EagleEye
//
//  A small memory + disk cache for remote images (member portraits).
//

import SwiftUI
import CoreImage

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

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("CachedImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Returns the image for `url`, reading from the memory cache, then disk,
    /// then the network — persisting each newly fetched image for next time.
    /// Returns `nil` if the image can't be loaded.
    func image(for url: URL) async -> PlatformImage? {
        let key = Self.key(for: url)

        if let cached = memory.object(forKey: key) {
            return cached
        }

        let fileURL = directory.appendingPathComponent(key as String)
        if let data = try? Data(contentsOf: fileURL), let image = PlatformImage(data: data) {
            let enhanced = Self.autoEnhanced(image)
            memory.setObject(enhanced, forKey: key)
            return enhanced
        }

        // Coalesce concurrent requests for the same URL onto one download.
        if let existing = inFlight[url] {
            return await existing.value
        }

        let task = Task<PlatformImage?, Never> { [directory] in
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) ?? true,
                  let image = PlatformImage(data: data) else {
                return nil
            }
            try? data.write(to: directory.appendingPathComponent(key as String))
            return Self.autoEnhanced(image)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil

        if let image {
            memory.setObject(image, forKey: key)
        }
        return image
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

        guard let cgOutput = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return image }

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

    var body: some View {
        Group {
            if let image {
                content(image)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let platformImage = await ImageCache.shared.image(for: url) {
                #if canImport(UIKit)
                image = Image(uiImage: platformImage)
                #elseif canImport(AppKit)
                image = Image(nsImage: platformImage)
                #endif
            }
        }
    }
}
