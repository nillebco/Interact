# InteractApp

InteractApp is a macOS utility written in SwiftUI that lets you:

- Discover any visible window on your desktop.
- Capture a high-resolution screenshot of the selected window.
- Send arbitrary text or keyboard shortcuts (⌘, ⌥, ⌃, ⇧ modifiers) directly to that window.

The app is powered by Accessibility and Screen Recording APIs, so it runs locally with no external dependencies.

## Prerequisites

- macOS 13 Ventura or later.
- Xcode 16 (or Swift toolchain 6.2) for building.
- Accessibility and Screen Recording permissions (prompted on first launch).

## Building & Running

1. Open the project in Xcode:
   ```bash
   open Package.swift
   ```

   Xcode will generate an app scheme automatically. Alternatively you can build from the CLI:
   ```bash
   SWIFT_MODULECACHE_PATH=.build/module-cache \
   CLANG_MODULE_CACHE_PATH=.build/clang-module-cache \
   swift build
   ```
   > When running from a sandboxed environment you may need to override the module cache locations as shown above.

2. Run the “InteractApp” product. On first launch macOS will prompt for:
   - **Accessibility**: required to deliver keyboard events.
   - **Screen Recording**: required to capture screenshots of other apps.

3. Once permissions are granted:
   - Select a window from the list on the left.
   - Use the **Screenshot** panel to capture and save window images.
   - Use **Send Text** to type arbitrary strings.
   - Use **Send Shortcut** to trigger key combinations (letters, digits, arrows, function keys, return/tab/space/delete, etc.).

## Notes & Limitations

- macOS may take a moment to focus a target window before accepting keyboard events; a short delay is added automatically.
- For security reasons the system will only allow automation after you explicitly approve Accessibility access in **System Settings → Privacy & Security → Accessibility**.
- Screen captures require approval in **System Settings → Privacy & Security → Screen Recording**.
- Sending shortcuts relies on a predefined key map; if a key is not recognised the app will surface an error.

## Project Structure

- `Sources/InteractApp/InteractApp.swift` – SwiftUI entry point.
- `AppDelegate.swift` & `AuthorizationManager.swift` – Permission handling.
- `WindowService.swift` & `WindowAutomation.swift` – Window discovery, screenshots, keyboard automation.
- `WindowInteractionViewModel.swift` & `ContentView.swift` – View-model and UI.
- `Resources/Info.plist` – Bundle metadata and privacy descriptions.
