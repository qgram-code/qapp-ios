import SwiftUI
import UIKit

/// Small in-memory image cache shared by every avatar and post image.
/// `AsyncImage` alone re-downloads on every appearance inside a `List`, which
/// makes scrolling feel broken on a slow connection.
actor ImageCache {
    static let shared = ImageCache()

    private let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 240
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(memoryCapacity: 24 * 1024 * 1024,
                                          diskCapacity: 256 * 1024 * 1024,
                                          diskPath: "qgram-images")
        configuration.httpAdditionalHeaders = ["User-Agent": AppConfig.userAgent]
        return URLSession(configuration: configuration)
    }()

    func cached(_ url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        if let running = inFlight[url] { return await running.value }

        let task = Task<UIImage?, Never> { [session] in
            guard let (data, response) = try? await session.data(from: url) else { return nil }
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 { return nil }
            return UIImage(data: data)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            cache.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * 4))
        }
        return image
    }
}

/// Drop-in async image with a branded placeholder and cross-fade.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
                    .overlay {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(QColor.muted)
                        }
                    }
            }
        }
        .task(id: url) { await load() }
    }

    @MainActor
    private func load() async {
        guard let url else {
            image = nil
            return
        }
        if let hit = await ImageCache.shared.cached(url) {
            image = hit
            return
        }
        isLoading = true
        let loaded = await ImageCache.shared.image(for: url)
        isLoading = false
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            image = loaded
        }
    }
}

extension RemoteImage where Placeholder == AnyView {
    /// Neutral card-coloured placeholder used almost everywhere.
    init(url: URL?, contentMode: ContentMode = .fill) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = { AnyView(QColor.card2) }
    }
}
