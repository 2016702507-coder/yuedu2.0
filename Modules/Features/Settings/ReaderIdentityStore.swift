import Combine
import SwiftUI
import UIKit

/// 沒有自訂頭像時用的內建圖：劍來主題包的 `assets/artwork/avatar.png`（圓形水墨劍，
/// 四角本來就是透明的），縮到 384px 放進 Assets。使用者一換頭像就只用他自己的。
enum ReaderDefaultAvatar {
    static let imageName = "ReaderDefaultAvatar"

    static var image: UIImage? { UIImage(named: imageName) }
}

/// 本機閱讀身份：頭像、暱稱、簽名。
///
/// maintainer, 2026-11-06：這張卡放在設定首頁「尊享會員」之上，而且「名字和頭像要可以
/// 更改的。並且只在本地保存」。所以它刻意不進 `GlobalSettings` —— 那邊的帳號欄位會寫進
/// Firestore，換一台裝置就同步出去了；這裡只有兩個 UserDefaults 字串和 Library 下的一個
/// JPEG，不聯網、不上傳、不參與任何同步。
@MainActor
final class ReaderIdentityStore: ObservableObject {
    static let shared = ReaderIdentityStore()

    /// 第一次打開時顯示的文字，取自維護者的參考圖。
    static let sampleName = "林間讀者"
    static let sampleSignature = "讓閱讀回到你喜歡的樣子"

    /// 暱稱與簽名的長度上限：再長就不是一行名字、一句話了。
    static let nameLimit = 16
    static let signatureLimit = 24

    /// 使用者自己填的暱稱；空白代表沒設過，顯示時退回 `sampleName`。
    @Published private(set) var name: String
    @Published private(set) var signature: String
    @Published private(set) var avatar: UIImage?

    private enum Key {
        static let name = "yd_reader_identity_name"
        static let signature = "yd_reader_identity_signature"
    }

    /// 512px 的 JPEG，和閱讀統計放在同一個地方（Library 根下）。
    private let avatarURL: URL

    private init() {
        let defaults = UserDefaults.standard
        name = defaults.string(forKey: Key.name) ?? ""
        signature = defaults.string(forKey: Key.signature) ?? ""
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        avatarURL = library.appendingPathComponent("reader_identity_avatar.jpg")
        avatar = UIImage(contentsOfFile: avatarURL.path)
    }

    // MARK: - 顯示用

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? localized(Self.sampleName) : trimmed
    }

    var displaySignature: String {
        let trimmed = signature.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? localized(Self.sampleSignature) : trimmed
    }

    // MARK: - 寫入

    /// 一次提交編輯頁的三樣東西。`avatar` 給 `nil` 就是「沒有頭像」，檔案一併刪掉。
    func commit(name newName: String, signature newSignature: String, avatar newAvatar: UIImage?) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        name = String(trimmedName.prefix(Self.nameLimit))
        UserDefaults.standard.set(name, forKey: Key.name)

        let trimmedSignature = newSignature.trimmingCharacters(in: .whitespacesAndNewlines)
        signature = String(trimmedSignature.prefix(Self.signatureLimit))
        UserDefaults.standard.set(signature, forKey: Key.signature)

        guard let newAvatar else {
            try? FileManager.default.removeItem(at: avatarURL)
            avatar = nil
            return
        }
        guard let data = Self.normalizedJPEG(newAvatar) else { return }
        try? data.write(to: avatarURL, options: .atomic)
        avatar = UIImage(data: data)
    }

    // MARK: - 圖片

    /// 縮到 512px 再壓 JPEG：頭像最大只畫 76pt，原圖存下來沒有意義，還會讓備份變大。
    private static func normalizedJPEG(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 512
        let longestSide = max(image.size.width, image.size.height)
        let scale = min(1, maxSide / max(longestSide, 1))
        let size = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.88)
    }
}
