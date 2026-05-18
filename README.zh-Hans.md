# 阅读

[English](README.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md)

<p align="center">
  <img src="iOS/Assets.xcassets/AppIcon.appiconset/ios_app_icon_novel_reader_1024_no_alpha.png" width="120">
</p>

<p align="center">
  <strong>一个用 CoreText 打造的 iOS 原生阅读引擎，不是 WebView。</strong><br>
  开源里你能找到最好的原生 iOS 阅读引擎。CoreText 渲染，零 WebView。
</p>

## 展示

<table width="100%">
  <tr style="border: none;">
    <td width="33.3%" align="center" style="border: none; vertical-align: top;">
      <br>
      <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="#6d28d9" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-label="Book icon"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"></path><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"></path></svg>
      <h3>CJK 竖排阅读</h3>
      <img src="docs/screenshots/cjk-vertical.png" width="220" style="border-radius: 8px; box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1);" alt="CJK 竖排阅读截图">
      <p style="font-size: 0.9em; color: #666; margin-top: 10px;">《红楼梦》(脂评本): 竖排文本、行间注释和紧凑标注。</p>
    </td>
    <td width="33.3%" align="center" style="border: none; vertical-align: top;">
      <br>
      <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="#15803d" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-label="Text icon"><path d="M3 5v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2z"></path><path d="M7 15l3-6 3 6"></path><path d="M8 13h4"></path></svg>
      <h3>英文 EPUB</h3>
      <img src="docs/screenshots/english-epub.png" width="220" style="border-radius: 8px; box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1);" alt="英文 EPUB 渲染截图">
      <p style="font-size: 0.9em; color: #666; margin-top: 10px;">出版商 CSS 支持: 首字母下沉、嵌套边距和字体层叠。</p>
    </td>
    <td width="33.3%" align="center" style="border: none; vertical-align: top;">
      <br>
      <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="#1d4ed8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-label="List icon"><line x1="8" y1="6" x2="21" y2="6"></line><line x1="8" y1="12" x2="21" y2="12"></line><line x1="8" y1="18" x2="21" y2="18"></line><line x1="3" y1="6" x2="3.01" y2="6"></line><line x1="3" y1="12" x2="3.01" y2="12"></line><line x1="3" y1="18" x2="3.01" y2="18"></line></svg>
      <h3>目录导航</h3>
      <img src="docs/screenshots/toc.png" width="220" style="border-radius: 8px; box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1);" alt="目录导航截图">
      <p style="font-size: 0.9em; color: #666; margin-top: 10px;">优先使用 toc.ncx 和 nav.xhtml, 而非基于骨架的章节猜测。</p>
    </td>
  </tr>
</table>

## 为什么 CoreText 渲染如此不同

<table width="100%">
  <tr style="border: none;">
    <td width="50" style="border: none; vertical-align: top;">
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#7c3aed" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-label="Star icon"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"></polygon></svg>
    </td>
    <td style="border: none; vertical-align: top;">
      <strong>规范优先的保真度</strong><br>
      忠实实现 EPUB 和 CSS 规范，确保渲染结果一致且可预测。
      <ul>
        <li><strong>手动 CSS 解析</strong>: 自行解析出版商样式表并应用层叠逻辑，将 <code>text-indent</code>、<code>font-size</code> 和 <code>:first-letter</code> 等属性转换为 <code>NSAttributedString</code> 特性。</li>
        <li><strong>精确解析</strong>: 处理缩写属性、百分比值和继承属性，不依赖系统布局引擎。</li>
      </ul>
    </td>
  </tr>
  <tr style="border: none;">
    <td width="50" style="border: none; vertical-align: top;">
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#16a34a" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-label="Layout icon"><rect x="2" y="2" width="20" height="8" rx="2" ry="2"></rect><rect x="2" y="14" width="20" height="8" rx="2" ry="2"></rect><line x1="6" y1="6" x2="6.01" y2="6"></line><line x1="6" y1="18" x2="6.01" y2="18"></line></svg>
    </td>
    <td style="border: none; vertical-align: top;">
      <strong>高级布局</strong><br>
      支持竖排、旁注 (ruby)、脚注、批注、首字下沉和嵌套边距。
      <ul>
        <li><strong>CJK 竖排阅读</strong>: 轴向感知的渲染引擎，处理从栏顶开始的字符前进方向和块方向延伸。拉丁文字段会选择性解除竖排并重新居中。</li>
        <li><strong>行间批注</strong>: 支持密集的竖排批注（如脂评本），通过预留栏宽占位符并手动绘制批注，支持长批注跨页拆分。</li>
      </ul>
    </td>
  </tr>
  <tr style="border: none;">
    <td width="50" style="border: none; vertical-align: top;">
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#2563eb" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-label="Navigation icon"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path><polyline points="14 2 14 8 20 8"></polyline><line x1="16" y1="13" x2="8" y2="13"></line><line x1="16" y1="17" x2="8" y2="17"></line><polyline points="10 9 9 9 8 9"></polyline></svg>
    </td>
    <td style="border: none; vertical-align: top;">
      <strong>智能导航</strong><br>
      在可用时使用 <code>toc.ncx</code> 和 <code>nav.xhtml</code> 以获得准确的目录和位置。
      <ul>
        <li><strong>持久阅读位置</strong>: 进度以 <code>(spineIndex, charOffset)</code> 存储，确保在字号更改、设备旋转或章节加载后位置依然准确。</li>
        <li><strong>目录优先级</strong>: 优先使用显式导航清单而非基于骨架的猜测，自动对回退标题进行去重。</li>
      </ul>
    </td>
  </tr>
  <tr style="border: none;">
    <td width="50" style="border: none; vertical-align: top;">
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ea580c" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-label="Design icon"><circle cx="12" cy="12" r="10"></circle><path d="M12 16a4 4 0 0 0 0-8"></path><line x1="12" y1="2" x2="12" y2="4"></line><line x1="12" y1="20" x2="12" y2="22"></line><line x1="4.93" y1="4.93" x2="6.34" y2="6.34"></line><line x1="17.66" y1="17.66" x2="19.07" y2="19.07"></line><line x1="2" y1="12" x2="4" y2="12"></line><line x1="20" y1="12" x2="22" y2="12"></line><line x1="4.93" y1="19.07" x2="6.34" y2="17.66"></line><line x1="17.66" y1="4.93" x2="19.07" y2="6.34"></line></svg>
    </td>
    <td style="border: none; vertical-align: top;">
      <strong>默认优雅</strong><br>
      经过精心调优的排版、间距和主题，提供优雅的阅读体验。
      <ul>
        <li><strong>原生保真度</strong>: 主阅读器零 WebView 依赖，实现对行高、字间距和段落边距的绝对控制。</li>
      </ul>
    </td>
  </tr>
</table>

## 技术亮点

- **原生 CoreText 渲染**：左右翻页与连续滚动，不经过 WebView。
- **CJK 竖排**：繁简中文竖排、CJK 标点处理、CJK/拉丁混排，已用含行内批注与彩色注释的复杂竖排 EPUB 验证。
- **EPUB CSS 解析**：支持 `:first-letter` 首字放大、嵌套区块边距累加、`<hr>` 含 width/margin/alignment、`text-indent`（含负值 hanging indent）、字体层叠、百分比边距/内距/宽度解析。
- **稳定阅读位置**：以 `(spineIndex, charOffset)` 存储进度，而非会随排版变化漂移的页码。
- **大书处理**：数百万字 TXT 与 EPUB 验证通过。
- **Legado 兼容书源规则**：导入并执行兼容 [Legado](https://github.com/gedoor/legado) 格式的用户书源。
- **在线阅读管线**：将网页与规则型书源正规化为阅读格式。

## 渲染管线

<p align="center">
  <img src="docs/banner.svg" alt="渲染管线架构图" width="680">
</p>

两条平行路径产出 CoreText 属性字符串：

```
旧路径：    HTMLAttributedStringBuilder.build() → NSAttributedString
                   ↓                            ↓
RenderableNode：HTMLStyledASTRenderableNodeConverter → RenderableNode IR → NodeAttributedStringRenderer
                   ↓                            ↓
             共享层：CSSParser → ResolvedStyle → CoreTextPageView.drawLines()
```

任何 CSS 属性变更必须同时更新两条路径。共享层负责 CSS 解析、ResolvedStyle，以及 `CoreTextPageView` 的界面绘制。

**翻页 vs 滚动**：`EPUBPageRenderer` 将内容路由至 `CoreTextPageEngine`（翻页）或 `CoreTextScrollEngine`（滚动）。`CoreTextPageView` 及区块 Cell 绘制最终 CoreText 界面。

**EPUB 目录**：优先使用 `toc.ncx` / `nav.xhtml` 条目，优于 spine 章节列表。spine 非目录项目（续页、分割后记）会被排除。spine fallback 包含相同标题去重。

## 功能概览

- CoreText 翻页与滚动阅读器
- EPUB CSS 渲染（发布者样式表、字体层叠、首字放大、边距）
- CJK 排版：竖排、标点、段落缩进
- 本地书库：EPUB、TXT、Markdown 导入，含缓存、封面、书签、注释
- 在线阅读：网页正规化、规则型书源获取
- RSS 阅读器：RSS/Atom 订阅、规则型提取、OPML 导入
- TTS：AVSpeechSynthesizer 及 HTTP 自定义 TTS
- WebDAV 同步：备份、还原、书库与进度同步
- 阅读器自定义：字体、字号、行距、间距、边距、主题、翻页/滚动模式、竖排

## 系统需求

- iOS 18.0+、Xcode 16+、Swift 5

## 快速开始

```bash
git clone https://github.com/CHANG-JUI-LIN/Yuedu-reader.git
cd Yuedu-reader
open Yuedu-Reader.xcodeproj
```

选择 `Yuedu-Reader` scheme，构建至模拟器或实机。或直接运行：

```bash
./scripts/build.sh
```

## 目录结构

```text
iOS/
├── Models/
│   ├── App/              # 全局设定、DesignTokens、AppDependencies
│   ├── Book/             # ReadingBook、Bookmark、BookStore
│   ├── BookSource/       # 书源定义与获取管线
│   ├── LocalBook/        # EPUB/TXT/Markdown 解析器
│   ├── Online/           # 在线阅读与网页正规化
│   ├── RSS/              # RSS 模型、订阅解析
│   ├── Reader/CoreText/  # CoreText 翻页引擎、滚动引擎、CSS 解析、渲染
│   ├── RuleEngine/       # CSS/XPath/Regex/JSON 规则提取
│   ├── Sync/             # WebDAV 同步管理
│   └── TTS/              # 语音播放协调
├── Views/                # SwiftUI 界面
├── ViewModels/           # ObservableObject ViewModel
├── Assets/               # 资产目录与规则引擎资源
└── *.lproj/              # 本地化：zh-Hant、zh-Hans、en
```

## 开发规则

- 用户字符串使用 `localized()`，更新三个 `.lproj` 文件。
- 阅读位置以内容坐标为基准，不用页码。
- UI 样式使用设计 Token API：`DSColor`、`DSFont`、`DSSpacing`。
- 新增或修改 View 时，加入 `#Preview`。
- 新增 CSS 属性至 `ResolvedStyle` 时，同步 `RenderStyle` 字段、更新 `RenderStyle.from`，并处理两条渲染路径。
- 嵌套区块 CSS 边距通过 `inheritedBlockMarginLeft` 累加。

请见 [CONTRIBUTING.md](CONTRIBUTING.md)。架构笔记：[Technotes/Architecture.md](Technotes/Architecture.md)。

## 授权

MIT。详见 [LICENSE](LICENSE)。链接 [Readium](https://github.com/readium) 组件（BSD 授权）。
