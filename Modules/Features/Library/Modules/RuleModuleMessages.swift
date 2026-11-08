import Foundation

// What the import sheet says when a module file is refused (Phase 6e): each reason names the
// field, so whoever wrote the module knows what to change.

extension RuleModuleRejection {
    var message: String {
        switch self {
        case .tooLarge: localized("模组档案超过 256 KB。")
        case .notJSON: localized("这不是模组档案：无法读成 JSON。")
        case .missingField(let field): String(format: localized("缺少栏位 %@。"), field)
        case .malformed(let field): String(format: localized("栏位 %@ 的格式不对。"), field)
        case .invalidID(let id): String(format: localized("代号「%@」只能用英文字母、数字、句点、底线和连字号。"), id)
        case .invalidVersion(let field, let value): String(format: localized("%1$@ 的「%2$@」不是数字版本。"), field, value)
        case .requiresNewerApp(let required, let running):
            String(format: localized("这个模组需要阅读 %1$@ 以上的版本，目前是 %2$@。"), required, running)
        case .noEntries: localized("模组没有任何清单。")
        case .tooManyEntries(let count): String(format: localized("模组有 %d 个清单，上限是 50 个。"), count)
        case .duplicateEntryID(let id): String(format: localized("清单代号「%@」重复。"), id)
        case .emptyRule(let field): String(format: localized("%@ 的规则是空的。"), field)
        case .javaScript(let field): String(format: localized("%@ 含有 JavaScript，模组不执行 JavaScript。"), field)
        case .variables(let field): String(format: localized("%@ 用到 @get 或 @put，模组不支援变数。"), field)
        case .undeclaredTemplate(let field, let name):
            String(format: localized("%1$@ 的 {{%2$@}} 不是宣告过的参数。"), field, name)
        case .unknownParamType(let field, let type): String(format: localized("%1$@ 的参数类型「%2$@」不支援。"), field, type)
        case .enumerationWithoutOptions(let field): String(format: localized("%@ 没有列出选项。"), field)
        case .unsupportedMethod(let field, let method):
            String(format: localized("%1$@ 的「%2$@」不支援，只能用 GET 或 POST。"), field, method)
        case .invalidURL(let field): String(format: localized("%@ 不是 http 或 https 网址。"), field)
        case .urlOptions(let field): String(format: localized("%@ 带有网址选项（,{…}）；方法、内容和标头请写在各自的栏位。"), field)
        case .hostNotAllowed(let field, let host): String(format: localized("%1$@ 连到 %2$@，但 hosts 没有列出它。"), field, host)
        case .unknownValue(let field, let value): String(format: localized("%1$@ 的「%2$@」不是可用的值。"), field, value)
        case .needsRequiredVersion(let field, let minimum):
            String(format: localized("用到 %1$@ 的模组，requiredVersion 至少要 %2$@。"), field, minimum)
        }
    }
}

extension RuleModuleStoreError {
    var message: String {
        switch self {
        case .rejected(let rejection): rejection.message
        case .alreadyInstalled(let id): String(format: localized("已经加入过这个模组（%@）。"), id)
        case .notInstalled: localized("找不到这个模组。")
        case .differentModule(_, let offered): String(format: localized("下载到的是另一个模组（%@）。"), offered)
        case .notNewer: localized("已是最新版本")
        case .reservedID(let id): String(format: localized("「%@」是官方模组的代号，请换一个。"), id)
        }
    }
}
