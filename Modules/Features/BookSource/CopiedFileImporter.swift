import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - CopiedFileImporter

/// 书源（及本地）文件导入选择器。
///
/// 对齐修复版 Leaflow 的做法：用原生 `UIDocumentPickerViewController` 取代 SwiftUI 的
/// `.fileImporter`。在“部分签名 / 企业签 / 自签”环境下，`.fileImporter` 对沙盒外文件的
/// security-scoped 访问经常失败，表现为“选了没反应 / 读不到 / 点不动”。
///
/// 这里在 `documentPicker:didPickDocumentsAt:` 的回调里、趁安全域仍然有效，先把文件**复制进
/// App 沙盒**（`FileManager.temporaryDirectory`），再把本地副本的 URL 交给 `onCompletion`。
/// 后续读取发生在 App 自己的沙盒内，彻底绕开跨沙盒安全域访问的限制。
struct CopiedFileImporter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let allowedContentTypes: [UTType]
    let allowsMultipleSelection: Bool
    let onCompletion: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isHidden = true
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {
        if isPresented, uiViewController.presentedViewController == nil {
            let picker = UIDocumentPickerViewController(forOpening: allowedContentTypes)
            picker.allowsMultipleSelection = allowsMultipleSelection
            picker.delegate = context.coordinator
            uiViewController.present(picker, animated: true)
        } else if !isPresented, uiViewController.presentedViewController != nil {
            uiViewController.dismiss(animated: true)
        }
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: CopiedFileImporter

        init(_ parent: CopiedFileImporter) {
            self.parent = parent
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            parent.isPresented = false
            guard let url = urls.first else { return }
            parent.onCompletion(Self.copyToSandbox(url))
        }

        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
            parent.isPresented = false
        }

        /// 趁 security-scoped 访问有效，把选中的文件复制进 App 沙盒，返回本地副本 URL。
        private static func copyToSandbox(_ url: URL) -> Result<URL, Error> {
            let secured = url.startAccessingSecurityScopedResource()
            defer {
                if secured {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let data = try Data(contentsOf: url)
                let ext = url.pathExtension.isEmpty ? "json" : url.pathExtension
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(ext)
                try data.write(to: destination, options: .atomic)
                return .success(destination)
            } catch {
                return .failure(error)
            }
        }
    }
}
