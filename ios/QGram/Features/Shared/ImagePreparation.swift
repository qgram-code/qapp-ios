import SwiftUI
import PhotosUI
import UIKit

/// Turns picked photos into upload-ready JPEG payloads.
///
/// The backend checks that the file's magic bytes match its extension, so every
/// upload is re-encoded to JPEG and named `.jpg` — HEIC straight from the
/// camera roll would be rejected.
enum ImagePreparation {
    static func prepare(_ item: PhotosPickerItem, maxDimension: CGFloat = 2048, maxMB: Int) async -> UploadImage? {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return nil
        }
        return prepare(image, maxDimension: maxDimension, maxMB: maxMB)
    }

    static func prepare(_ image: UIImage, maxDimension: CGFloat = 2048, maxMB: Int) -> UploadImage? {
        let resized = downscale(image, maxDimension: maxDimension)
        var quality: CGFloat = 0.85
        var data = resized.jpegData(compressionQuality: quality)
        let limit = maxMB * 1024 * 1024
        while let current = data, current.count > limit, quality > 0.35 {
            quality -= 0.15
            data = resized.jpegData(compressionQuality: quality)
        }
        guard let payload = data, payload.count <= limit else { return nil }
        return UploadImage(data: payload,
                           filename: "qgram_\(UUID().uuidString.prefix(8)).jpg",
                           mimeType: "image/jpeg")
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension, longest > 0 else { return image.normalized() }
        let scale = maxDimension / longest
        let size = CGSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private extension UIImage {
    /// Bakes in EXIF orientation so the server (and everyone else) sees the
    /// picture the right way up.
    func normalized() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
