import Combine
import SwiftUI
import UIKit

/// 没有自订头像时用的内建图：剑来主题包的 `assets/artwork/avatar.png`（圆形水墨剑，
/// 四角本来就是透明的），缩到 384px 放进 Assets。使用者一换头像就只用他自己的。
enum ReaderDefaultAvatar {
    static let imageName = "ReaderDefaultAvatar"

    static var image: UIImage? { UIImage(named: imageName) }
}

/// 本机阅读身份：头像、暱称、签名。
///
/// maintainer, 2026-11-06：这张卡放在设置首页「尊享会员」之上，而且「名字和头像要可以
/// 更改的。并且只在本地保存」。所以它刻意不进 `GlobalSettings` —— 那边的帐号栏位会写进
/// Firestore，换一台装置就同步出去了；这里只有两个 UserDefaults 字串和 Library 下的一个
/// JPEG，不联网、不上传、不参与任何同步。
@MainActor
final class ReaderIdentityStore: ObservableObject {
    static let shared = ReaderIdentityStore()

    /// 第一次打开时显示的文字，取自维护者的参考图。
    static let sampleName = "林间读者"
    static let sampleSignature = "让阅读回到你喜欢的样子"

    /// 暱称与签名的长度上限：再长就不是一行名字、一句话了。
    static let nameLimit = 16
    static let signatureLimit = 24

    /// 使用者自己填的暱称；空白代表没设过，显示时退回 `sampleName`。
    @Published private(set) var name: String
    @Published private(set) var signature: String
    @Published private(set) var avatar: UIImage?

    private enum Key {
        static let name = "yd_reader_identity_name"
        static let signature = "yd_reader_identity_signature"
    }

    /// 512px 的 JPEG，和阅读统计放在同一个地方（Library 根下）。
    private let avatarURL: URL

    private init() {
        let defaults = UserDefaults.standard
        name = defaults.string(forKey: Key.name) ?? ""
        signature = defaults.string(forKey: Key.signature) ?? ""
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        avatarURL = library.appendingPathComponent("reader_identity_avatar.jpg")
        avatar = UIImage(contentsOfFile: avatarURL.path)
    }

    // MARK: - 显示用

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? localized(Self.sampleName) : trimmed
    }

    var displaySignature: String {
        let trimmed = signature.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? localized(Self.sampleSignature) : trimmed
    }

    // MARK: - 写入

    /// 一次提交编辑页的三样东西。`avatar` 给 `nil` 就是「没有头像」，档案一并删掉。
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

    // MARK: - 图片

    /// 缩到 512px 再压 JPEG：头像最大只画 76pt，原图存下来没有意义，还会让备份变大。
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
