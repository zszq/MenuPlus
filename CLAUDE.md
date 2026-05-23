# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`rightMenu` is a SwiftUI macOS/iOS app built with Xcode. Currently at initial scaffolding stage — only the default Xcode template files exist.

## Build & Run

Build and run via Xcode (open `rightMenu.xcodeproj`) or via `xcodebuild`:

```bash
# Build
xcodebuild -project rightMenu.xcodeproj -scheme rightMenu -configuration Debug build

# Run tests (when tests are added)
xcodebuild -project rightMenu.xcodeproj -scheme rightMenu test
```

## Architecture

- **Entry point**: `rightMenu/rightMenuApp.swift` — `@main` SwiftUI `App` struct, launches `ContentView`
- **UI**: `rightMenu/ContentView.swift` — root SwiftUI view
- **Assets**: `rightMenu/Assets.xcassets` — app icon, accent color

The project uses SwiftUI's declarative lifecycle (`@main` + `App` protocol) rather than AppDelegate/SceneDelegate.
