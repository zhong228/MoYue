# 阅读

[English](README.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md)

<p align="center">
  <img src="iOS/Assets.xcassets/AppIcon.appiconset/ios_app_icon_novel_reader_1024_no_alpha.png" alt="阅读 app icon" width="128">
</p>

阅读是一个使用 SwiftUI 和 CoreText 构建的 iOS 原生阅读器，专注于 CJK 长文本阅读、本地 EPUB/TXT 书库、网页内容转码、RSS 订阅、TTS 听书、WebDAV 同步，以及可细调的阅读排版。

> 状态说明：本项目是 CJK-first 阅读器。中文阅读、中英/数字混排、长篇小说场景是主要目标。英文 EPUB/TXT 基本可读，但目前还不是主要验证路径。

## 能做什么

- **原生 CoreText 阅读器**：支持分页阅读和连续滚动，不以 WebView 作为主要阅读界面。
- **CJK 中文排版**：处理段首缩进、标点、行距、页边距、中英混排和竖排阅读。
- **本地书库**：导入 EPUB、TXT 和类 Markdown 文本文件，支持解析、缓存、封面、书签、标注和阅读位置恢复。
- **大体积书籍处理**：已针对长篇 TXT 和 EPUB 阅读流程验证，包含数百万字级内容。
- **在线阅读流程**：将用户自行提供的网页和规则化书源转换成同一套阅读器格式。
- **Legado 兼容书源规则**：可导入并运行用户自行提供、兼容 [Legado](https://github.com/gedoor/legado) 规则格式的自定义书源规则。
- **RSS 阅读**：支持 RSS/Atom feed、规则化提取、OPML 类工作流和文章渲染。
- **TTS 听书**：支持本机 `AVSpeechSynthesizer` 和基于 HTTP 的自定义 TTS provider。
- **同步与备份**：以 WebDAV 为核心的备份、恢复、书库同步和进度同步流程。
- **阅读器定制**：字体、字号、行高、段落间距、页边距、主题、分页/滚动模式和竖排模式。

## 项目边界

阅读是阅读器引擎和应用外壳，不内置、不托管、不推荐、也不分发任何受版权保护的内容来源。

用户需要自行确保导入文件、RSS feed、网站、自定义规则、cookie、账号和生成内容符合当地法律、版权要求和网站服务条款。

本项目不接受内置盗版源、DRM 绕过、付费墙绕过、私有 token 分享、cookie 提取或反爬绕过逻辑等贡献。

Legado 兼容性只代表书源规则格式兼容；阅读不内置第三方书源规则，也不是 Legado 项目的官方关联产品。

## AI 协同开发声明

本仓库重度使用 AI 协同开发，包括代码生成、重构、文档撰写和审查辅助。项目仍会保留人工审阅与维护责任，但 AI 辅助产出的代码会明确存在于项目中。

如果你偏好完全由人手撰写的代码，或对 AI 辅助开发有疑虑或排斥，请在使用或贡献前自行评估，并请见谅。

## 环境要求

- iOS 18.0+
- Xcode 16+
- Xcode 项目目前使用 Swift 5 language mode

## 快速开始

```bash
git clone https://github.com/CHANG-JUI-LIN/Yuedu-reader.git
cd Yuedu-reader
open Yuedu-Reader.xcodeproj
```

选择 `Yuedu-Reader` scheme，然后在 iOS 模拟器或真机上构建运行。

也可以使用 app target 的构建脚本：

```bash
./scripts/build.sh
```

等价命令：

```bash
xcodebuild \
  -project "Yuedu-Reader.xcodeproj" \
  -scheme "Yuedu-Reader" \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  build
```

## 项目结构

```text
iOS/
├── Models/               # 数据模型、存储、服务、渲染器、解析器
│   ├── App/              # 全局设置、设计 token、依赖注入
│   ├── Book/             # 书籍模型、BookStore、书签、metadata
│   ├── BookSource/       # 用户自定义来源抓取
│   ├── LocalBook/        # EPUB/TXT/Markdown 导入
│   ├── Online/           # 在线阅读与网页内容转码流程
│   ├── RSS/              # RSS 模型、feed 抓取器、解析器、文章工具
│   ├── Reader/CoreText/  # CoreText 分页、滚动排版、绘制
│   ├── RuleEngine/       # CSS/XPath/Regex/JSON 提取
│   ├── Sync/             # WebDAV 与同步逻辑
│   └── TTS/              # 语音播放协调
├── Views/                # SwiftUI 页面和共用 UI
│   ├── Reader/           # 阅读器界面、控制栏、设置、覆盖层
│   ├── Bookshelf/        # 首页书架与书籍管理
│   ├── BookSource/       # 书源管理与诊断
│   ├── Online/           # 浏览器/导入流程
│   ├── RSS/              # RSS 订阅与文章页面
│   └── Settings/         # App 设置、个人资料、同步、TTS、迁移
├── ViewModels/           # ObservableObject ViewModel
├── Assets/               # Asset catalog 和规则引擎资源
└── *.lproj/              # 本地化：zh-Hant、zh-Hans、en

ShareExtension/           # iOS 分享扩展
Widget/                   # 主屏幕 widget
Tests/                    # Unit test 和 UI test targets
Technotes/                # 架构笔记
scripts/                  # 本地自动化脚本
xcconfig/                 # 共用 Xcode 设置
```

## 架构笔记

- **EPUB**：使用 Readium 组件处理 EPUB package 解析与资源访问。
- **渲染**：`EPUBPageRenderer` 按阅读模式分派到 `CoreTextPageEngine` 或 `CoreTextScrollEngine`。`CoreTextPageView` 和 chunk cell 负责绘制最终 CoreText frame。
- **阅读位置**：稳定位置使用 `(spineIndex, charOffset)`，不使用页码，因为章节加载或版面变更后 page index 可能位移。
- **在线内容**：`BookSourceFetcher`、`OnlineReadingPipeline`、`ModernRuleEngine` 和 web fetcher 会把用户提供的来源转成标准化章节内容。
- **RSS**：feed XML 解析和规则化文章提取，沿用和在线阅读一致的清理与阅读器渲染原则。
- **TTS**：播放状态独立于渲染层协调，让阅读器高亮和系统媒体控制能跟随当前朗读段落。
- **依赖注入**：通过 `AppDependencies` 和 SwiftUI environment 提供 app services；需要持久化或缓存所有权的 manager 会集中管理。

更多细节见 [Technotes/Architecture.md](Technotes/Architecture.md)。

## 开发规则

- 使用 `localized()` 处理用户可见文字，并同步更新三个本地化文件：
  - `iOS/zh-Hant.lproj/Localizable.strings`
  - `iOS/zh-Hans.lproj/Localizable.strings`
  - `iOS/en.lproj/Localizable.strings`
- 阅读位置要使用稳定内容坐标，不要使用会变动的 page index。
- UI 样式请使用 app 自定义 design-token API：`Models/App/DesignTokens.swift` 内的 `DSColor`、`DSFont`、`DSSpacing`。
- 新增或调整 SwiftUI View 时，尽量提供可编译的 preview（`#Preview` 或 `PreviewProvider`），方便在 Xcode 直接观察页面和组件状态。
- 书源和规则引擎相关工作必须限定在合法、用户自行提供内容的流程。

贡献规范见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

MIT。见 [LICENSE](LICENSE)。

本项目链接了 [Readium](https://github.com/readium) 组件，Readium 组件使用 BSD 许可证。Readium 名称和标志是 Readium Foundation 的商标。
