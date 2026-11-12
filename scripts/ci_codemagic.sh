#!/bin/bash
# Codemagic 构建入口：平铺执行，不用 eval/run_step 包装。
# 步骤内容与 .github/workflows/build-ipa.yml 一致（由 scripts/ci_build_ipa.sh 逐块导出）。
# 为什么重写：旧版用 run_step + eval 跑步骤，在 macOS 自带 bash 3.2 上
# 会在 Build 成功之后抛 "name: unbound variable"，导致编译成功却拿不到包。
set -eo pipefail

echo "===== 0 环境 ====="
xcodebuild -version || true

echo ""
echo "===== Verify source is the fixed version ====="
MISSING=0
check() {
  if grep -q "$2" "$1" 2>/dev/null; then
    echo "  OK   $3"
  else
    echo "  MISS $3   (文件: $1)"
    MISSING=$((MISSING+1))
  fi
}
check_absent() {
  if grep -q "$2" "$1" 2>/dev/null; then
    echo "  BAD  $3   (文件: $1 仍含该写法)"
    MISSING=$((MISSING+1))
  else
    echo "  OK   $3"
  fi
}
echo "=== 校验修复是否包含在源码中 ==="
check Modules/Core/MOBI/KF8Converter.swift 'let insertion: \[UInt8\]' "KF8Converter 类型检查拆分"
check Modules/Core/ReaderCore/CoreText/HTMLAttributedStringBuilder.swift '@unchecked Sendable' "ElementNode Sendable"
check Modules/Features/AI/AIRelationshipMapView.swift 'let step: Double' "AIRelationshipMapView 拆分"
check Modules/Features/Explore/PublicLibrary/PublicLibraryBookSheet.swift 'let opacity: Double' "PublicLibrary 运算符拆分"
check Modules/Features/Reader/ReaderViewportReporting.swift 'YUEDU_HAS_RESERVED_REGIONS' "ReservedRegion 隔离"
check Modules/Services/Works/WorkIndexService.swift 'let seriesValue' "WorkIndex 类型标注"
check Modules/Core/BookSource/SourcePerfTrace.swift 'thresholdMilliseconds: Int = 1' "spanAsync 阈值改 Int"
check Modules/Features/Reader/ChapterTitleInspectorView.swift 'Binding<Double>(' "ChapterTitleInspectorView 内联 Binding"
check_absent Modules/Features/Reader/ChapterTitleInspectorView.swift 'doubleBinding' "doubleBinding 已展开（消除 IRGen thunk）"
check Yuedu-Reader.xcodeproj/project.pbxproj 'Crashlytics run tool not found' "Crashlytics 脚本已加固（缺工具时跳过，避免 PhaseScriptExecution 127）"
echo "缺失修复项: $MISSING"
if [ "$MISSING" -gt 0 ]; then
  echo "!! 源码缺少必要补丁（可能上传了旧 zip）!!"
  exit 1
fi
echo "源码版本校验通过"

echo ""
echo "===== Pick Xcode ====="
# 优先 26.2（Swift 6.2.3）：iOS 17.0 真机 swift_task_dealloc LIFO 崩溃
# （swiftlang/swift#84793）实测 26.2 干净、26.5/26.6 崩，6.2.4+ 产物在旧运行时崩
# （#88036）。没有 26.2 时退回「选最新」。
BEST=""
if [ -d "/Applications/Xcode_26.2.0.app" ]; then
  BEST="/Applications/Xcode_26.2.0.app"
else
  BEST_V=0
  for x in /Applications/Xcode*.app; do
    v=$(defaults read "$x/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo 0)
    maj=${v%%.*}
    rest=${v#*.}
    min=${rest%%.*}
    n=$((maj * 100 + 10#${min:-0}))
    if [ "$n" -gt "$BEST_V" ]; then
      BEST_V=$n
      BEST="$x"
    fi
  done
fi
echo "选中: $BEST"
sudo xcode-select -s "$BEST"
xcodebuild -version
xcodebuild -showsdks | grep -i iphone || true

echo ""
echo "===== Ensure GoogleService-Info.plist has a valid API key ====="
# Firebase 的 FIRInstallations 在启动时校验 API_KEY 长度必须为 39，
# 不合规直接抛 NSException——Swift 捕获不到，进程当场终止（白屏闪退）。
KEY=$(/usr/libexec/PlistBuddy -c "Print :API_KEY" GoogleService-Info.plist 2>/dev/null || echo "")
echo "当前 API_KEY 长度: ${#KEY}"
if [ "${#KEY}" != "39" ]; then
  sed 's/^ *//' <<'EOF' > GoogleService-Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>BUNDLE_ID</key><string>com.yuedu.reader</string>
  <key>PROJECT_ID</key><string>yuedu-placeholder</string>
  <key>API_KEY</key><string>AIzaSyPLACEHOLDER-KEY-00000000000000000</string>
  <key>GCM_SENDER_ID</key><string>000000000000</string>
  <key>GOOGLE_APP_ID</key><string>1:000000000000:ios:0000000000000000000000</string>
  <key>STORAGE_BUCKET</key><string>yuedu-placeholder.appspot.com</string>
  <key>PLIST_VERSION</key><string>1</string>
</dict>
</plist>
EOF
  echo "已重写为 39 字符合规占位"
fi
FINAL=$(/usr/libexec/PlistBuddy -c "Print :API_KEY" GoogleService-Info.plist 2>/dev/null || echo "")
if [ "${#FINAL}" != "39" ]; then
  echo "::error::API_KEY 长度 ${#FINAL}，Firebase 要求 39 字符，构建中止"
  exit 1
fi

echo ""
echo "===== Resolve Swift packages (with retry) ====="
for i in 1 2 3; do
  echo "===== 依赖解析尝试 $i ====="
  if xcodebuild -resolvePackageDependencies \
       -project Yuedu-Reader.xcodeproj \
       -scheme Yuedu-Reader \
       -derivedDataPath build \
       -clonedSourcePackagesDirPath build/SourcePackages \
       -skipPackagePluginValidation \
       -skipMacroValidation > resolve.log 2>&1; then
    echo "依赖解析成功"
    RESOLVED=1
    break
  fi
  tail -20 resolve.log
  sleep 10
done
if [ "${RESOLVED:-0}" != "1" ]; then
  echo "===== 依赖解析失败 ====="
  grep -n 'error:' resolve.log 2>/dev/null | head -30 || true
  tail -60 resolve.log
  exit 1
fi

echo ""
echo "===== Detect ReservedRegion support ====="
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
if grep -rql 'ReservedRegion' "$SDK_PATH/System/Library/Frameworks/SwiftUI.framework" 2>/dev/null; then
  echo "SDK 支持 ReservedRegion"
  EXTRA_SWIFT_FLAGS=-DYUEDU_HAS_RESERVED_REGIONS
else
  echo "SDK 不含 ReservedRegion，对应功能降级"
  EXTRA_SWIFT_FLAGS=
fi

echo ""
echo "===== Inspect toolchain and Binding signature ====="
echo "=== Swift 版本 ==="
swift --version || true
echo "=== Xcode 与 iOS SDK ==="
xcodebuild -version || true
xcodebuild -showsdks 2>/dev/null | grep -i iphone || true
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
echo "SDK 路径: $SDK"
IFACE=$(find "$SDK/System/Library/Frameworks/SwiftUI.framework" -name "*.swiftinterface" 2>/dev/null | head -1)
echo "接口文件: $IFACE"
if [ -n "$IFACE" ]; then
  echo "=== Binding 的 init(get:set:) 声明 ==="
  grep -n -A5 'public init(get' "$IFACE" 2>/dev/null | head -60 || true
  echo "=== 是否出现 @isolated(any) ==="
  grep -c '@isolated(any)' "$IFACE" 2>/dev/null || echo 0
fi

echo ""
echo "===== Patch CloudKit guard (stop launch crash on re-signed builds) ====="
cat > /tmp/patch_icloud.py <<'PYEOF'
#!/usr/bin/env python3
"""Patch CloudKit initialisation so a re-signed build cannot die on launch.

`CKContainer(identifier:)` raises an Objective-C exception when the identifier is
not in the process's entitlements. A sideloaded build has
`com.apple.developer.icloud-container-identifiers` emptied by the signing tool, so
the exception is raised while `SubscriptionStore` (which holds the mirror as a
stored property) is being constructed at launch — the app dies on the splash.
Swift cannot catch it, so the only fix is not to create the container at all.
"""
import sys
import pathlib

ICLOUD = "Modules/Services/iCloud/ICloudSyncManager.swift"
MIRROR = "Modules/Services/Subscription/SubscriptionICloudMirror.swift"

PATCHES = {
    ICLOUD: [
        (
            "    private let container: CKContainer\n"
            "    private let database: CKDatabase\n"
            "\n"
            "    nonisolated private static var deviceId: String {",
            "    /// Nil when this build may not use the container: `CKContainer(identifier:)`\n"
            "    /// raises an Objective-C exception, which Swift cannot catch, when the\n"
            "    /// identifier is not in the process's entitlements — and that exception is fatal.\n"
            "    private let container: CKContainer?\n"
            "    private let database: CKDatabase?\n"
            "\n"
            "    /// Whether this build may touch CloudKit at all (see `container`).\n"
            "    ///\n"
            "    /// A re-signed / sideloaded build has `com.apple.developer.icloud-container-identifiers`\n"
            "    /// emptied by the signing tool, and CloudKit answers a container outside that\n"
            "    /// list by raising, before any Swift code can intervene. `SubscriptionStore`\n"
            "    /// holds this singleton as a stored property, so it is built during launch and\n"
            "    /// an exception there kills the app on the launch screen.\n"
            "    nonisolated static let isICloudSyncAvailable = false\n"
            "\n"
            "    nonisolated private static var deviceId: String {",
        ),
        (
            "    private init(container: CKContainer = CKContainer(identifier: ICloudSyncManager.containerIdentifier)) {\n"
            "        self.container = container\n"
            "        database = container.privateCloudDatabase\n"
            "        lastSyncDate = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date\n"
            "    }",
            "    private init() {\n"
            "        if Self.isICloudSyncAvailable {\n"
            "            let container = CKContainer(identifier: ICloudSyncManager.containerIdentifier)\n"
            "            self.container = container\n"
            "            database = container.privateCloudDatabase\n"
            "        } else {\n"
            "            container = nil\n"
            "            database = nil\n"
            "        }\n"
            "        lastSyncDate = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date\n"
            "    }",
        ),
        (
            "    nonisolated private func fetchAccountStatus() async -> CKAccountStatus {\n"
            "        await withCheckedContinuation { continuation in",
            "    nonisolated private func fetchAccountStatus() async -> CKAccountStatus {\n"
            "        guard let container else { return .couldNotDetermine }\n"
            "        return await withCheckedContinuation { continuation in",
        ),
        (
            "    nonisolated private func fetchRecord(_ recordID: CKRecord.ID) async throws -> CKRecord {\n"
            "        try await withCheckedThrowingContinuation { continuation in",
            "    nonisolated private func fetchRecord(_ recordID: CKRecord.ID) async throws -> CKRecord {\n"
            "        guard let database else { throw ICloudSyncError.accountUnavailable(.couldNotDetermine) }\n"
            "        return try await withCheckedThrowingContinuation { continuation in",
        ),
        (
            "    nonisolated private func fetchRecordWithoutFields(_ recordID: CKRecord.ID) async throws -> CKRecord? {\n"
            "        try await withCheckedThrowingContinuation { continuation in",
            "    nonisolated private func fetchRecordWithoutFields(_ recordID: CKRecord.ID) async throws -> CKRecord? {\n"
            "        guard let database else { throw ICloudSyncError.accountUnavailable(.couldNotDetermine) }\n"
            "        return try await withCheckedThrowingContinuation { continuation in",
        ),
        (
            "    nonisolated private func deleteRecord(_ recordID: CKRecord.ID) async throws {\n"
            "        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in",
            "    nonisolated private func deleteRecord(_ recordID: CKRecord.ID) async throws {\n"
            "        guard let database else { throw ICloudSyncError.accountUnavailable(.couldNotDetermine) }\n"
            "        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in",
        ),
        (
            "    nonisolated private func saveRecord(_ record: CKRecord) async throws {\n"
            "        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in",
            "    nonisolated private func saveRecord(_ record: CKRecord) async throws {\n"
            "        guard let database else { throw ICloudSyncError.accountUnavailable(.couldNotDetermine) }\n"
            "        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in",
        ),
    ],
    MIRROR: [
        (
            "    private let container: CKContainer\n"
            "    private let database: CKDatabase\n"
            "    /// Last value written, so repeated refreshes that re-read the same StoreKit",
            "    /// Nil when this build may not use the container; see\n"
            "    /// `ICloudSyncManager.isICloudSyncAvailable`.\n"
            "    private let container: CKContainer?\n"
            "    private let database: CKDatabase?\n"
            "    /// Last value written, so repeated refreshes that re-read the same StoreKit",
        ),
        (
            "    private init(\n"
            "        container: CKContainer = CKContainer(identifier: ICloudSyncManager.containerIdentifier)\n"
            "    ) {\n"
            "        self.container = container\n"
            "        database = container.privateCloudDatabase\n"
            "    }",
            "    private init() {\n"
            "        if ICloudSyncManager.isICloudSyncAvailable {\n"
            "            let container = CKContainer(identifier: ICloudSyncManager.containerIdentifier)\n"
            "            self.container = container\n"
            "            database = container.privateCloudDatabase\n"
            "        } else {\n"
            "            container = nil\n"
            "            database = nil\n"
            "        }\n"
            "    }",
        ),
        (
            "    func accountStatusDescription() async -> String {\n"
            "        await withCheckedContinuation { continuation in",
            "    func accountStatusDescription() async -> String {\n"
            "        guard let container else { return \"unavailable (no iCloud entitlement)\" }\n"
            "        return await withCheckedContinuation { continuation in",
        ),
        (
            "    private func isAvailable() async -> Bool {\n"
            "        await withCheckedContinuation { continuation in",
            "    private func isAvailable() async -> Bool {\n"
            "        guard let container else { return false }\n"
            "        return await withCheckedContinuation { continuation in",
        ),
        (
            "    private func fetchRecord(_ recordID: CKRecord.ID) async throws -> CKRecord {\n"
            "        try await withCheckedThrowingContinuation { continuation in",
            "    private func fetchRecord(_ recordID: CKRecord.ID) async throws -> CKRecord {\n"
            "        guard let database else { throw CKError(.notAuthenticated) }\n"
            "        return try await withCheckedThrowingContinuation { continuation in",
        ),
        (
            "    private func saveRecord(_ record: CKRecord) async throws {\n"
            "        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in",
            "    private func saveRecord(_ record: CKRecord) async throws {\n"
            "        guard let database else { throw CKError(.notAuthenticated) }\n"
            "        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in",
        ),
    ],
}


def apply(root, reverse=False):
    for rel, pairs in PATCHES.items():
        path = pathlib.Path(root) / rel
        if not path.exists():
            sys.exit("missing file: %s" % path)
        text = path.read_text(encoding="utf-8")
        if not reverse and "isICloudSyncAvailable" in text:
            print("already patched: %s" % rel)
            continue
        for old, new in pairs:
            if reverse:
                old, new = new, old
            if new in text and old not in text:
                continue
            if old not in text:
                sys.exit("anchor not found in %s:\n%s" % (rel, old[:160]))
            text = text.replace(old, new, 1)
        path.write_text(text, encoding="utf-8")
        print("patched: %s" % rel)


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--reverse", action="store_true")
    args = ap.parse_args()
    apply(args.root, args.reverse)
PYEOF
python3 /tmp/patch_icloud.py --root .

grep -q 'isICloudSyncAvailable' Modules/Services/iCloud/ICloudSyncManager.swift || { echo '!! CloudKit guard missing in ICloudSyncManager'; exit 1; }
grep -q 'guard let database else' Modules/Services/iCloud/ICloudSyncManager.swift || { echo '!! database guards missing in ICloudSyncManager'; exit 1; }
grep -q 'isICloudSyncAvailable' Modules/Services/Subscription/SubscriptionICloudMirror.swift || { echo '!! CloudKit guard missing in SubscriptionICloudMirror'; exit 1; }
echo 'CloudKit guard applied'

echo ""
echo "===== Build (unsigned, device) ====="
echo "EXTRA_SWIFT_FLAGS=$EXTRA_SWIFT_FLAGS"
echo "Xcode: $(xcodebuild -version | head -1)"

build_with() {
  local name="$1" mode="$2" opt="$3" batch="$4" disopt="$5"
  echo "----- 尝试配置: $name (mode=$mode opt=$opt batch=$batch disable-optzns=$disopt) -----"
  local extra_flags="\$(inherited)"
  # 默认 swiftc 一旦某个文件类型检查失败就停止调度后续文件，于是「一轮只暴露一个
  # 错误」，而每轮要 15 分钟。下面探测工具链是否支持继续构建，支持就加上：
  # 一次把所有源文件的错误都报出来。旧工具链不认识该开关时探测失败，自动跳过，
  # 行为退回原样。
  if [ "${CONTINUE_AFTER_ERRORS:-}" = "" ]; then
    printf 'let yueduProbe = 1\n' > /tmp/yuedu_flag_probe.swift
    if swiftc -typecheck -continue-building-after-errors /tmp/yuedu_flag_probe.swift >/dev/null 2>&1; then
      CONTINUE_AFTER_ERRORS="-continue-building-after-errors"
      echo "工具链支持 -continue-building-after-errors，本轮一次报全所有错误"
    else
      CONTINUE_AFTER_ERRORS="none"
      echo "工具链不支持 -continue-building-after-errors，退回遇错即停"
    fi
  fi
  if [ "$CONTINUE_AFTER_ERRORS" != "none" ]; then
    extra_flags="\$(inherited) $CONTINUE_AFTER_ERRORS"
  fi
  if [ "$disopt" = "yes" ]; then
    extra_flags="$extra_flags -Xfrontend -disable-llvm-optzns"
  fi
  # strip 只能在「已链接完成的产物」上做。上一版把
  #   STRIP_INSTALLED_PRODUCT=YES / COPY_PHASE_STRIP=YES / DEPLOYMENT_POSTPROCESSING=YES
  # 打进构建参数，Xcode 于是对编译中间产物 .o 也执行 Strip；而 .o 里仍带重定位项，
  # strip 必须失败：
  #   strip: error: symbols referenced by relocation entries that can't be stripped
  #   in .../third-party-IsAppEncrypted.o   (GoogleUtilities / Firebase)
  # 这四个开关现在全部显式置 NO。瘦身改到「打包」步骤，只对最终 Mach-O 做，
  # 而且失败不影响产物。
  xcodebuild \
    -project Yuedu-Reader.xcodeproj \
    -scheme Yuedu-Reader \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "build-$name" \
    -jobs 4 \
    -clonedSourcePackagesDirPath build/SourcePackages \
    -onlyUsePackageVersionsFromResolvedFile \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    ENABLE_DEBUG_DYLIB=NO \
    ENABLE_DEBUGGING_ATTACH=NO \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=NO \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS="\$(inherited) $EXTRA_SWIFT_FLAGS" \
    SWIFT_COMPILATION_MODE="$mode" \
    SWIFT_OPTIMIZATION_LEVEL="$opt" \
    SWIFT_ENABLE_BATCH_MODE="$batch" \
    OTHER_SWIFT_FLAGS="$extra_flags" \
    DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
    COPY_PHASE_STRIP=NO \
    STRIP_INSTALLED_PRODUCT=NO \
    STRIP_STYLE=non-global \
    DEPLOYMENT_POSTPROCESSING=NO \
    VALIDATE_PRODUCT=NO \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    build > "build-$name.log" 2>&1
}

# 崩溃诊断：把「崩溃文件 / 崩溃符号 / 堆栈」单独抽出来
# 同时写入 crash-context.log，失败时随 artifact 上传
report_crash() {
  local log="$1"
  echo "########## 崩溃诊断 ##########"
  echo "---- 崩溃所在源文件 ----"
  grep -o 'IR Generation for file "[^"]*"' "$log" 2>/dev/null | tail -3 | sed 's|.*/||; s|"$||' || true
  echo "---- 崩溃 SIL 符号 ----"
  grep 'While emitting IR SIL function' "$log" 2>/dev/null | tail -3 || true
  echo "---- 日志末尾 80 行 ----"
  tail -80 "$log" 2>/dev/null || true
  echo "##############################"
  {
    echo "=== IRGenRequest 崩溃文件（完整路径） ==="
    grep -o 'IR Generation for file "[^"]*"' "$log" 2>/dev/null || true
    echo ""
    echo "=== 崩溃 SIL 符号 ==="
    grep 'While emitting IR SIL function' "$log" 2>/dev/null || true
    echo ""
    echo "=== 崩溃堆栈（自 Stack dump 起 60 行） ==="
    awk '/Stack dump:/{f=1} f{print; n++} n>=60{exit}' "$log" 2>/dev/null || true
    echo ""
    echo "=== 日志末尾 150 行 ==="
    tail -150 "$log" 2>/dev/null || true
  } > crash-context.log || true
}

# 返回 0=成功 1=编译器崩溃（继续换档） 2=真实源码错误（立即停）
# 注意：本步骤运行在 bash -e 下，attempt 的非零返回必须用 `|| rc=$?` 接住，
# 否则第一档崩溃就会直接终止，后面的重试档根本不会执行。
attempt() {
  local name="$1" mode="$2" opt="$3" batch="$4" disopt="$5"
  if build_with "$name" "$mode" "$opt" "$batch" "$disopt"; then
    echo "编译成功（$name）"
    BUILD_DIR="build-$name"
    cp "build-$name.log" build.log
    tail -20 "build-$name.log" || true
    return 0
  fi
  echo "----- $name 失败 -----"
  # strip 打到了未链接的 .o 上（构建参数里开了 STRIP_INSTALLED_PRODUCT 之类）。
  # 这不是源码问题，但换优化级别重试同样会失败，所以立即停并说清楚。
  if grep -q 'strip: error: symbols referenced by relocation entries' "build-$name.log" 2>/dev/null; then
    echo "===== strip 阶段失败：Strip 作用到了编译中间产物 .o 上 ====="
    grep -n 'strip: error:' "build-$name.log" 2>/dev/null | head -10 || true
    echo "说明：.o 尚未链接、仍带重定位项，strip 必然报错。"
    echo "修复方向：构建参数里 STRIP_INSTALLED_PRODUCT / COPY_PHASE_STRIP /"
    echo "          DEPLOYMENT_POSTPROCESSING 必须为 NO，瘦身只对最终 Mach-O 做。"
    cp "build-$name.log" build.log
    return 2
  fi
  local errs
  errs=$(grep -c 'error:' "build-$name.log" 2>/dev/null || true)
  if [ "${errs:-0}" -gt 0 ]; then
    echo "===== 存在 ${errs} 条 error: 行，判定为真实源码错误，停止换档 ====="
    grep -n 'error:' "build-$name.log" 2>/dev/null | head -120 || true
    echo "===== 失败命令 ====="
    awk '/The following build commands failed:/,0' "build-$name.log" 2>/dev/null | head -25 || true
    cp "build-$name.log" build.log
    return 2
  fi
  # Run Script 阶段失败（如 Crashlytics / 自定义脚本）不是编译器崩溃，
  # 换优化级别重试毫无意义，必须立即停止并打印脚本诊断。
  if grep -q 'Command PhaseScriptExecution failed' "build-$name.log" 2>/dev/null; then
    echo "===== Run Script 阶段失败（非编译器崩溃，重试无用）====="
    grep -n -B1 -A8 'Command PhaseScriptExecution failed' "build-$name.log" 2>/dev/null | head -40 || true
    echo "---- 脚本自身的报错行 ----"
    grep -n '\.sh: line\|No such file or directory\|Permission denied\|command not found' "build-$name.log" 2>/dev/null | head -20 || true
    cp "build-$name.log" build.log
    return 2
  fi
  echo "===== 无 error: 行，判定为编译器崩溃 ====="
  report_crash "build-$name.log"
  cp "build-$name.log" build.log
  return 1
}

# 第 1 档用真正的 -O 优化（不带 -disable-llvm-optzns）：代码段从 97MB 降到
# 正常量级，产物约 40MB，第三方重签工具才签得动、系统才装得下。
# 若 -O 触发 IRGen 崩溃，自动降级到 -Onone 三档兜底。
# 一次报全：xcodebuild 一旦某个 SwiftCompile 失败就停下，所以正常的构建日志永远
# 只有一个 error:。而整模块编译（-wholemodule + -Onone）会把所有源文件塞进同一个
# frontend 进程，配上 -continue-building-after-errors 就能一次列出全部错误。
# 只在真的失败时才跑这一趟，成功路径不受影响。
diag_all_errors() {
  echo ""
  echo "===== 诊断：整模块类型检查，列出全部错误 ====="
  if [ "${CONTINUE_AFTER_ERRORS:-none}" = "none" ]; then
    echo "工具链不支持 -continue-building-after-errors，跳过诊断"
    return 0
  fi
  # 换一个 derivedDataPath，避免和刚失败的那次构建的中间产物互相干扰
  xcodebuild \
    -project Yuedu-Reader.xcodeproj \
    -scheme Yuedu-Reader \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "build-diag" \
    -jobs 8 \
    -clonedSourcePackagesDirPath build/SourcePackages \
    -onlyUsePackageVersionsFromResolvedFile \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    ENABLE_DEBUG_DYLIB=NO \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS="\$(inherited) $EXTRA_SWIFT_FLAGS" \
    SWIFT_COMPILATION_MODE=wholemodule \
    SWIFT_OPTIMIZATION_LEVEL=-Onone \
    SWIFT_ENABLE_BATCH_MODE=NO \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=NO \
    OTHER_SWIFT_FLAGS="\$(inherited) -continue-building-after-errors" \
    DEBUG_INFORMATION_FORMAT=dwarf \
    COPY_PHASE_STRIP=NO \
    VALIDATE_PRODUCT=NO \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    build > build-diag.log 2>&1 || true
  TOTAL=$(grep -c 'error:' build-diag.log 2>/dev/null || true)
  echo "诊断构建共 ${TOTAL:-0} 条 error:"
  echo "---- 全部错误（最多 120 行）----"
  grep -o '/Users/builder/clone/[^:]*:[0-9]*:[0-9]*: error: .*' build-diag.log 2>/dev/null | sort -u | head -120 || true
  echo "---- 结束 ----"
  cp build-diag.log build.log 2>/dev/null || true
}

for combo in \
  "opt|incremental|-O|NO|no" \
  "opt-size|incremental|-Osize|NO|no" \
  "nobatch-a|incremental|-Onone|NO|no" \
  "fallback|incremental|-Onone|NO|yes"; do
  IFS='|' read -r name mode opt batch disopt <<< "$combo"
  rc=0
  attempt "$name" "$mode" "$opt" "$batch" "$disopt" || rc=$?
  if [ "$rc" -eq 0 ]; then echo "构建完成：$name"; BUILD_OK=1; break; fi
  if [ "$rc" -eq 2 ]; then echo "真实源码错误，终止"; diag_all_errors; exit 1; fi
  echo "「$name」编译器崩溃，进入下一档"
done

if [ "${BUILD_OK:-0}" != "1" ]; then
  echo "===== 四种配置均失败 ====="
  echo "请下载 build-log 与 crash-context 两个 artifact"
  echo "crash-context.log 第 1 段「IRGenRequest 崩溃文件」就是元凶的完整路径"
  exit 1
fi

echo ""
echo "===== Package unsigned IPA ====="
if [ -z "${BUILD_DIR:-}" ]; then
  for d in build-opt build-opt-size build-nobatch-a build-nobatch-b build-batch build-fallback build-out; do
    if [ -d "$d/Build/Products" ]; then BUILD_DIR="$d"; break; fi
  done
fi
echo "使用构建目录: ${BUILD_DIR:-<空>}"
if [ -z "${BUILD_DIR:-}" ] || [ ! -d "$BUILD_DIR/Build/Products" ]; then
  echo "未找到构建产物目录，列出当前目录："
  ls -la || true
  find . -maxdepth 2 -name "Products" -type d 2>/dev/null | head -20 || true
  exit 1
fi
APP=$(find "$BUILD_DIR/Build/Products" -name "*.app" -type d -maxdepth 3 2>/dev/null | grep -v -E 'Tests|UITests|\.appex' | head -1 || true)
if [ -z "$APP" ]; then
  echo "未找到 .app 目录"
  find "$BUILD_DIR/Build/Products" -maxdepth 3 2>/dev/null | head -60 || true
  exit 1
fi
echo "找到 APP Bundle: $APP"

# —— 产物结构硬校验 ——
# Xcode 16+ 的 ENABLE_DEBUG_DYLIB 会把全部代码编进 App.debug.dylib，
# 主二进制只剩几十 KB 的壳，靠 @rpath/App.debug.dylib 加载真实代码。
# 未签名 IPA 交给第三方重签工具时，工具只签 .app 主二进制、Frameworks 和
# PlugIns，不会签 App 根目录下的 *.debug.dylib；iOS 加载未签名的 dylib 会
# 被内核拒绝，dyld 直接 abort —— 表现为「点开图标立刻回桌面」。
# 因此这里只要还看到 debug dylib 就终止，绝不产出这种包。
DEBUG_DYLIBS=$(find "$APP" -name "*.debug.dylib" 2>/dev/null || true)
if [ -n "$DEBUG_DYLIBS" ]; then
  echo "!! 产物里仍存在 debug dylib（ENABLE_DEBUG_DYLIB 未生效）："
  echo "$DEBUG_DYLIBS"
  find "$APP" -name "*.debug.dylib" -exec ls -lh {} \; 2>/dev/null || true
  exit 1
fi

MAIN_BIN="$APP/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist" 2>/dev/null || echo YueduReader)"
if [ ! -f "$MAIN_BIN" ]; then
  echo "!! 找不到主可执行文件 $MAIN_BIN"
  exit 1
fi
MAIN_SIZE=$(stat -f%z "$MAIN_BIN" 2>/dev/null || echo 0)
echo "主可执行文件: $(basename "$MAIN_BIN")  ${MAIN_SIZE} 字节"
if [ "${MAIN_SIZE:-0}" -lt 5242880 ]; then
  echo "!! 主二进制不足 5MB，仍是 debug dylib 空壳结构，终止打包"
  exit 1
fi
echo "产物结构校验通过（无 debug dylib，主二进制 ${MAIN_SIZE} 字节）"

# —— 对齐签名证书的 App ID ——
# iOS 启动时会拿描述文件里 application-identifier（格式 TEAMID.包名）的
# 包名部分，与 CFBundleIdentifier 逐字比对；不一致就由 amfid 直接终止进程，
# 表现正是「点开图标立刻回桌面」，而安装照样能成功。
# 所以先把包名改成证书对应的 App ID，签名工具读到的就是这个值。
if [ -n "${SIGN_BUNDLE_ID:-}" ]; then
  OLD_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null || true)
  if [ "$OLD_ID" != "$SIGN_BUNDLE_ID" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $SIGN_BUNDLE_ID" "$APP/Info.plist"
    # PlistBuddy 可能改写格式，强制回二进制（签名工具对大包更认二进制 plist）
    plutil -convert binary1 "$APP/Info.plist"
    echo "CFBundleIdentifier: $OLD_ID -> $SIGN_BUNDLE_ID"
  fi
  FINAL_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null || true)
  if [ "$FINAL_ID" != "$SIGN_BUNDLE_ID" ]; then
    echo "!! bundle id 改写失败（当前 $FINAL_ID，期望 $SIGN_BUNDLE_ID）"
    exit 1
  fi
  echo "bundle id 已对齐证书：$FINAL_ID"
else
  echo "SIGN_BUNDLE_ID 为空，保持原包名"
fi

# 精确 App ID 的证书签不了扩展（扩展 id 必须带主 App 前缀），
# 留着会在启动校验时被拒，因此按开关移除。
if [ "${DROP_EXTENSIONS:-0}" = "1" ] && [ -d "$APP/PlugIns" ]; then
  echo "移除扩展（精确 App ID 无法签名扩展）："
  ls "$APP/PlugIns" 2>/dev/null || true
  rm -rf "$APP/PlugIns"
fi

# —— 可选瘦身：只对「已链接完成的最终 Mach-O」做 ——
# -O 编译后本该落到 30MB 上下，正常不需要这一步。只有明显超标时
# 才 strip 一次（签名工具对超大二进制容易签残），且任何失败都不终止：
# 结构完整 > 体积。
if [ "${MAIN_SIZE:-0}" -gt 83886080 ]; then
  echo "主二进制偏大（${MAIN_SIZE} 字节），尝试剥离符号…"
  cp "$MAIN_BIN" "$MAIN_BIN.bak"
  OK=1
  xcrun strip -Sx "$MAIN_BIN" >/dev/null 2>&1 || OK=0
  NEW_SIZE=$(stat -f%z "$MAIN_BIN" 2>/dev/null || echo 0)
  if [ "${NEW_SIZE:-0}" -lt 1048576 ]; then OK=0; fi
  if [ "$OK" -eq 1 ]; then
    # 注意不要写 `otool -l | grep -q`：pipefail 下 grep 提前退出会让
    # otool 收到 SIGPIPE，管道整体返回非零，导致误判为「找不到 LC_MAIN」。
    LC_MAIN_HITS=$(xcrun otool -l "$MAIN_BIN" 2>/dev/null | grep -c LC_MAIN || true)
    if [ "${LC_MAIN_HITS:-0}" -eq 0 ]; then OK=0; fi
  fi
  if [ "$OK" -eq 0 ]; then
    echo "!! strip 失败或结果异常，回滚为原始二进制"
    cp "$MAIN_BIN.bak" "$MAIN_BIN"
    NEW_SIZE=$MAIN_SIZE
  fi
  rm -f "$MAIN_BIN.bak"
  echo "strip 后主二进制: ${NEW_SIZE} 字节"
else
  echo "主二进制体积正常（<80MB），跳过 strip"
fi

rm -rf Payload && mkdir -p Payload
cp -R "$APP" Payload/
zip -qry Yuedu-unsigned.ipa Payload
ls -lh Yuedu-unsigned.ipa
unzip -l Yuedu-unsigned.ipa | head -15 || true

