import Foundation

/// 「孤岛 / Cay」内置的三套段评气泡轮廓，转成阅读器自订 SVG 认识的占位符：
/// Cay 用 `{{count}}` / `{{color}}`，阅读器用 `$displayText` / `${color}`。
/// 在「气泡设置 › 段评气泡」里一键汇入，之后可按现有编辑器改颜色与大小。
enum CayBubblePresets {
    struct Preset {
        let name: String
        let svg: String
    }

    static let items: [Preset] = [
        Preset(name: "孤岛 · 对话气泡", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" width="42" height="30" viewBox="0 0 42 30">
          <path d="M2 3 H40 A2 2 0 0 1 42 5 V21 A2 2 0 0 1 40 23 H14 L7 29 V23 H2 A2 2 0 0 1 0 21 V5 A2 2 0 0 1 2 3 Z"
                fill="none" stroke="${color}" stroke-width="2"/>
          <text x="21" y="17" text-anchor="middle" font-size="12" fill="${color}">$displayText</text>
        </svg>
        """),
        Preset(name: "孤岛 · 胶囊", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" width="42" height="26" viewBox="0 0 42 26">
          <rect x="1" y="1" width="40" height="24" rx="12" fill="none" stroke="${color}" stroke-width="2"/>
          <text x="21" y="17" text-anchor="middle" font-size="12" fill="${color}">$displayText</text>
        </svg>
        """),
        Preset(name: "孤岛 · 纯数字", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" width="34" height="24" viewBox="0 0 34 24">
          <text x="17" y="17" text-anchor="middle" font-size="13" font-weight="bold" fill="${color}">$displayText</text>
        </svg>
        """)
    ]
}
