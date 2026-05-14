# Yuedu Reader

[English](README.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md)

<p align="center">
  <img src="iOS/Assets.xcassets/AppIcon.appiconset/ios_app_icon_novel_reader_1024_no_alpha.png" alt="Yuedu Reader app icon" width="128">
</p>

Yuedu Reader, named `閱讀` in Traditional Chinese and `阅读` in Simplified Chinese, is a native iOS reading app built with SwiftUI and CoreText. It is designed for CJK long-form reading, local EPUB/TXT libraries, online article normalization, RSS subscriptions, TTS playback, WebDAV sync, and highly configurable typography.

> Status: CJK-first. Chinese reading, mixed CJK/Latin text, and long novel scenarios are the primary targets. English EPUB/TXT rendering is supported, but it is not the main validation path yet.

## What It Does

- **Native CoreText reader**: paged reading and continuous scroll rendering without using WebView as the main reading surface.
- **CJK typography**: paragraph indentation, punctuation handling, line spacing, margins, mixed CJK/Latin text, and vertical writing support.
- **Local library**: import EPUB, TXT, and Markdown-like text files with parsing, caching, covers, bookmarks, annotations, and reading-position restore.
- **Large-book handling**: validated with long TXT and EPUB books, including multi-million-character reading flows.
- **Online reading pipeline**: normalize user-provided web pages and rule-based book sources into the same reader format.
- **Legado-compatible source rules**: import and run user-provided custom source rules compatible with the [Legado](https://github.com/gedoor/legado) rule format.
- **RSS reader**: RSS/Atom feeds, rule-based extraction, OPML-style workflows, and article rendering.
- **TTS**: local `AVSpeechSynthesizer` playback and HTTP-based custom TTS providers.
- **Sync and backup**: WebDAV-oriented backup, restore, library sync, and progress sync flows.
- **Reader customization**: fonts, font size, line height, paragraph spacing, margins, themes, page/scroll mode, and vertical writing mode.

## Project Boundary

Yuedu Reader is a reader engine and app shell. It does not include, host, recommend, or distribute copyrighted content sources.

Users are responsible for making sure imported files, RSS feeds, websites, custom rules, cookies, accounts, and generated content comply with applicable laws, copyright requirements, and website terms.

The project will not accept contributions for built-in piracy sources, DRM circumvention, paywall bypassing, private-token sharing, cookie harvesting, or anti-bot bypass logic.

Legado compatibility is a source-rule format compatibility target only. Yuedu Reader does not bundle third-party source rules and is not affiliated with the Legado project.

## AI-Assisted Development

This repository is developed with heavy AI-assisted collaboration, including code generation, refactoring, documentation, and review support. Human review and project ownership remain part of the workflow, but AI-assisted code is intentionally present throughout the project.

If you strongly prefer strictly human-authored code or are uncomfortable with AI-assisted development, please review the project with that expectation in mind. Your understanding is appreciated.

## Requirements

- iOS 18.0+
- Xcode 16+
- Swift 5 language mode in the Xcode project

## Getting Started

```bash
git clone https://github.com/CHANG-JUI-LIN/Yuedu-reader.git
cd Yuedu-reader
open Yuedu-Reader.xcodeproj
```

Select the `Yuedu-Reader` scheme and build for an iOS simulator or device.

You can also run the app-target build script:

```bash
./scripts/build.sh
```

Equivalent command:

```bash
xcodebuild \
  -project "Yuedu-Reader.xcodeproj" \
  -scheme "Yuedu-Reader" \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  build
```

## Repository Layout

```text
iOS/
├── Models/               # Data models, stores, services, renderers, parsers
│   ├── App/              # Global settings, design tokens, dependency injection
│   ├── Book/             # Book model, BookStore, bookmarks, metadata
│   ├── BookSource/       # User-defined source fetching
│   ├── LocalBook/        # EPUB/TXT/Markdown ingestion
│   ├── Online/           # Online reading and web normalization pipeline
│   ├── RSS/              # RSS models, feed fetcher, parser, article utilities
│   ├── Reader/CoreText/  # CoreText pagination, scroll layout, drawing
│   ├── RuleEngine/       # CSS/XPath/Regex/JSON extraction
│   ├── Sync/             # WebDAV and sync logic
│   └── TTS/              # Speech playback coordination
├── Views/                # SwiftUI screens and reusable UI
│   ├── Reader/           # Reader surface, controls, settings, overlays
│   ├── Bookshelf/        # Home bookshelf and book management
│   ├── BookSource/       # Book-source management and diagnostics
│   ├── Online/           # Browser/import flows
│   ├── RSS/              # RSS subscription and article views
│   └── Settings/         # App settings, profile, sync, TTS, migration
├── ViewModels/           # ObservableObject view models
├── Assets/               # Asset catalogs and rule-engine resources
└── *.lproj/              # Localization: zh-Hant, zh-Hans, en

ShareExtension/           # iOS share extension
Widget/                   # Home screen widget
Tests/                    # Unit and UI test targets
Technotes/                # Architecture notes
scripts/                  # Local automation scripts
xcconfig/                 # Shared Xcode configuration
```

## Architecture Notes

- **EPUB**: Readium components handle EPUB package parsing and resource access.
- **Rendering**: `EPUBPageRenderer` routes content to `CoreTextPageEngine` for paged reading or `CoreTextScrollEngine` for continuous scroll. `CoreTextPageView` and chunk cells draw the final CoreText frames.
- **Reading position**: durable positions are based on `(spineIndex, charOffset)` instead of page number, because page indexes can shift after chapter loading or layout changes.
- **Online content**: `BookSourceFetcher`, `OnlineReadingPipeline`, `ModernRuleEngine`, and web fetchers convert user-provided sources into normalized chapter content.
- **RSS**: feed XML parsing and rule-based article extraction share the same sanitization and reader-rendering principles as online reading.
- **TTS**: playback state is coordinated separately from rendering so reader highlighting and system media controls can follow the active text segment.
- **Dependency injection**: `AppDependencies` and SwiftUI environment values provide app services; shared managers are centralized where persistence or cache ownership is required.

More detail: [Technotes/Architecture.md](Technotes/Architecture.md).

## Development Rules

- Use `localized()` for user-facing strings and update all three localization files:
  - `iOS/zh-Hant.lproj/Localizable.strings`
  - `iOS/zh-Hans.lproj/Localizable.strings`
  - `iOS/en.lproj/Localizable.strings`
- Keep reader identity based on stable content coordinates, not transient page indexes.
- Use the app's design-token APIs for UI styling: `DSColor`, `DSFont`, and `DSSpacing` in `Models/App/DesignTokens.swift`.
- Add a compiling SwiftUI preview (`#Preview` or `PreviewProvider`) when creating or changing view code wherever practical, so screens and components can be inspected quickly in Xcode.
- Keep source/rule-engine work limited to legal, user-provided content workflows.

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution conventions.

## License

MIT. See [LICENSE](LICENSE).

This project links against [Readium](https://github.com/readium) components, which are BSD-licensed. The Readium name and logo are trademarks of the Readium Foundation.
