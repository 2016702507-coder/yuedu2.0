import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - CopiedFileImporter

/// 全 App 统一的文件导入选择器。
///
/// 对齐修复版 Leaflow 的做法：用原生 `UIDocumentPickerViewController` 取代 SwiftUI 的
/// `.fileImporter`。在“部分签名 / 企业签 / 自签”环境下，`.fileImporter` 对沙盒外文件的
/// security-scoped 访问经常失败，表现为“选了没反应 / 读不到 / 点不动”。
///
/// 这里在 `documentPicker:didPickDocumentsAt:` 的回调里、趁安全域仍然有效，先把文件**复制进
/// App 沙盒**，再把本地副本的 URL 交给上层。后续读取全部发生在 App 自己的沙盒内，彻底绕开
/// 跨沙盒安全域访问的限制。
///
/// 副本放在 `tmp/CopiedImports/<随机目录>/<原文件名>`：目录名保证不重名，文件名保持原样，
/// 因为有些导入入口（本地书籍、主题、字体）会拿文件名当标题或判断类型。
struct CopiedFileImporter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let allowedContentTypes: [UTType]
    let allowsMultipleSelection: Bool
    let onCompletion: (Result<[URL], Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard isPresented, !context.coordinator.isPresenting else { return }
        guard let presenter = Self.topViewController() else {
            // 还没有可用的窗口（极早期调用）：把状态复位，让用户再点一次。
            DispatchQueue.main.async { isPresented = false }
            return
        }
        context.coordinator.isPresenting = true
        // `asCopy: true`：让系统直接把选中的文件复制成 App 可读的副本，
        // 与下面「再复制进沙盒」形成双保险，也避开部分签名环境的授权异常。
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: allowedContentTypes,
            asCopy: true
        )
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = context.coordinator
        presenter.present(picker, animated: true)
    }

    /// 取当前最顶层的控制器来弹出选择器。直接从背景控制器的 `present` 往往因为
    /// “不在窗口层级中”而静默失败，尤其在 SwiftUI sheet 之上。
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first,
              var top = window.rootViewController else { return nil }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: CopiedFileImporter
        var isPresenting = false

        init(_ parent: CopiedFileImporter) {
            self.parent = parent
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            isPresenting = false
            parent.isPresented = false
            guard !urls.isEmpty else { return }
            parent.onCompletion(Self.copyToSandbox(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            isPresenting = false
            parent.isPresented = false
        }

        /// 趁 security-scoped 访问有效，把选中的文件复制进 App 沙盒，返回本地副本 URL。
        private static func copyToSandbox(_ urls: [URL]) -> Result<[URL], Error> {
            var copies: [URL] = []
            let batch = FileManager.default.temporaryDirectory
                .appendingPathComponent("CopiedImports", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: batch, withIntermediateDirectories: true)
            } catch {
                return .failure(error)
            }
            for url in urls {
                let secured = url.startAccessingSecurityScopedResource()
                defer {
                    if secured {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                do {
                    let name = url.lastPathComponent.isEmpty ? UUID().uuidString : url.lastPathComponent
                    let destination = batch.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: url, to: destination)
                    copies.append(destination)
                } catch {
                    return .failure(error)
                }
            }
            return .success(copies)
        }
    }
}

// MARK: - View 扩展（与 `.fileImporter` 同名参数的两种重载）

extension View {
    /// 单选：回调一个已复制进沙盒的 URL。
    @ViewBuilder
    func copiedFileImporter(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) -> some View {
        background(
            CopiedFileImporter(
                isPresented: isPresented,
                allowedContentTypes: allowedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        onCompletion(.success(url))
                    } else {
                        onCompletion(.failure(CocoaError(.fileNoSuchFile)))
                    }
                case .failure(let error):
                    onCompletion(.failure(error))
                }
            }
        )
    }

    /// 多选（或显式指定 `allowsMultipleSelection`）：回调整批已复制进沙盒的 URL。
    @ViewBuilder
    func copiedFileImporter(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        allowsMultipleSelection: Bool,
        onCompletion: @escaping (Result<[URL], Error>) -> Void
    ) -> some View {
        background(
            CopiedFileImporter(
                isPresented: isPresented,
                allowedContentTypes: allowedContentTypes,
                allowsMultipleSelection: allowsMultipleSelection,
                onCompletion: onCompletion
            )
        )
    }
}
