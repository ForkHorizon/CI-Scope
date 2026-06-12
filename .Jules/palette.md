## 2024-03-24 - Missing tooltips in Sidebar Navigation
**Learning:** SwiftUI's `Label` component provides built-in accessibility labeling for VoiceOver based on the text string, but does not provide visual hover tooltips by default. Visual tooltips (`.help()`) are highly beneficial for macOS sidebars to improve discoverability.
**Action:** Add `.help()` modifiers systematically to macOS sidebar elements in SwiftUI, even when the label text is already visible or implies accessibility.
