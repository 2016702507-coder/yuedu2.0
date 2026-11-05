#!/usr/bin/env python3
"""让工程内嵌的 SwiftSoup 与 readium/swift-toolkit 依赖的远程 SwiftSoup 不再冲突。

冲突成因：本地包路径 Packages/SwiftSoup 的包标识是 "swiftsoup"，
远程 https://github.com/scinfu/SwiftSoup.git 的标识也是 "swiftsoup"，
SwiftPM 视作同一包的两种来源而报错。

做法：把本地包目录改名为 YueduSwiftSoup（标识变为 yueduswiftsoup），
同时更新工程里的 relativePath。产品名仍是 SwiftSoup，代码 `import SwiftSoup`
与工程中的 productRef 都不受影响。
"""
import os
import re
import shutil
import sys

OLD_DIR = 'Packages/SwiftSoup'
NEW_DIR = 'Packages/YueduSwiftSoup'
PBX = 'Yuedu-Reader.xcodeproj/project.pbxproj'


def main() -> int:
    changed = False

    # 1. 目录改名
    if os.path.isdir(OLD_DIR):
        if os.path.isdir(NEW_DIR):
            shutil.rmtree(OLD_DIR)
        else:
            shutil.move(OLD_DIR, NEW_DIR)
        print(f'moved {OLD_DIR} -> {NEW_DIR}')
        changed = True
    elif os.path.isdir(NEW_DIR):
        print(f'{NEW_DIR} already in place')
    else:
        print('ERROR: local SwiftSoup package not found')
        return 1

    # 2. Package.swift 里的包名
    pkg = os.path.join(NEW_DIR, 'Package.swift')
    if os.path.isfile(pkg):
        text = open(pkg).read()
        if 'name: "SwiftSoup"' in text:
            text = text.replace('name: "SwiftSoup"', 'name: "YueduSwiftSoup"', 1)
            open(pkg, 'w').write(text)
            print('Package.swift name -> YueduSwiftSoup')
            changed = True

    # 3. 工程里的 relativePath
    if os.path.isfile(PBX):
        text = open(PBX).read()
        if 'relativePath = Packages/SwiftSoup;' in text:
            text = text.replace(
                'relativePath = Packages/SwiftSoup;',
                'relativePath = Packages/YueduSwiftSoup;'
            )
            open(PBX, 'w').write(text)
            print('pbxproj relativePath updated')
            changed = True
        balanced = text.count('{') == text.count('}')
        print('pbxproj braces balanced:', balanced)
        if not balanced:
            return 1

    print('done, changed:', changed)
    return 0


if __name__ == '__main__':
    sys.exit(main())
