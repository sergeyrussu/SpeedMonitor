//
//  MenuBarSpeedApp.swift
//  SpeedMonitor
//

import SwiftUI
import AppKit
import Combine
import ServiceManagement

private enum TextLayout: Int {
    case horizontal = 0
    case vertical = 1
}

private enum AppLanguage: String {
    case russian
    case english
    case hindi
    case chinese
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let fontStep: CGFloat = 0.5
    private static let horizontalLineSpacing: CGFloat = 1
    private static let verticalLineSpacing: CGFloat = -2
    private static let horizontalMetricsGapSpaces: Int = 1
    private static let horizontalMetricsKern: CGFloat = -5

    private let speedMonitor = SpeedMonitor()
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    private let layoutDefaultsKey = "menuTextLayout"
    private let languageDefaultsKey = "menuLanguage"
    private let horizontalFontDefaultsKey = "menuHorizontalFontSize"
    private let verticalFontDefaultsKey = "menuVerticalFontSize"

    private var isMenuOpen = false
    private var pendingRawText: String?
    private var latestRawText = "0K↓ 0K↑"
    private var needsMenuRebuild = false
    private var needsDisplayRefresh = false

    private var layoutMode: TextLayout = .horizontal
    private var appLanguage: AppLanguage = .english
    private var horizontalFontSize: CGFloat = 10.5
    private var verticalFontSize: CGFloat = 8.0

    private var layoutMenuItems: [NSMenuItem] = []
    private var languageItems: [NSMenuItem] = []
    private var launchAtLoginItem: NSMenuItem?

    // App bootstrapping: configure menu-bar mode, restore saved UI state, then start data flow.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        loadSavedSettings()
        setupStatusItem()
        bindMonitor()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Create the status-bar item once and attach the settings menu.
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.toolTip = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "SpeedMonitor"
        latestRawText = speedMonitor.menuBarText
        requestDisplayRefresh()
        item.menu = buildMenu()
    }

    // Listen for speed updates and avoid UI churn while the menu is open.
    private func bindMonitor() {
        speedMonitor.$menuBarText
            .receive(on: RunLoop.main)
            .sink { [weak self] rawText in
                guard let self else { return }
                self.latestRawText = rawText
                if self.isMenuOpen {
                    self.pendingRawText = rawText
                } else {
                    self.requestDisplayRefresh()
                }
            }
            .store(in: &cancellables)
    }

    // Restore persisted preferences for layout, language, and per-layout font sizes.
    private func loadSavedSettings() {
        let layoutRaw = UserDefaults.standard.integer(forKey: layoutDefaultsKey)
        layoutMode = TextLayout(rawValue: layoutRaw) ?? .horizontal

        if let rawLanguage = UserDefaults.standard.string(forKey: languageDefaultsKey),
           let language = AppLanguage(rawValue: rawLanguage) {
            appLanguage = language
        } else {
            appLanguage = .english
            UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: languageDefaultsKey)
        }

        horizontalFontSize = readFont(defaultsKey: horizontalFontDefaultsKey, fallback: 10.5)
        verticalFontSize = readFont(defaultsKey: verticalFontDefaultsKey, fallback: 8.0)
    }

    private func readFont(defaultsKey: String, fallback: CGFloat) -> CGFloat {
        guard UserDefaults.standard.object(forKey: defaultsKey) != nil else {
            UserDefaults.standard.set(Double(fallback), forKey: defaultsKey)
            return fallback
        }
        let value = CGFloat(UserDefaults.standard.double(forKey: defaultsKey))
        return max(1, value)
    }

    // Build the complete menu each time state changes (layout/language/login option).
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let createdItem = NSMenuItem(title: localizedCreatedByTitle(), action: nil, keyEquivalent: "")
        createdItem.isEnabled = false
        menu.addItem(createdItem)
        menu.addItem(.separator())

        menu.addItem(makeLayoutMenuItem())
        switch layoutMode {
        case .horizontal:
            menu.addItem(makeHorizontalSliderItem())
        case .vertical:
            menu.addItem(makeVerticalSliderItem())
        }

        menu.addItem(.separator())
        menu.addItem(makeLaunchAtLoginItem())
        menu.addItem(makeLanguageMenuItem())

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: localizedQuitTitle(), action: #selector(quitApp), keyEquivalent: "q"))

        return menu
    }

    // Submenu for layout mode.
    private func makeLayoutMenuItem() -> NSMenuItem {
        let root = NSMenuItem(title: localizedLayoutTitle(), action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: localizedLayoutTitle())

        let horizontal = NSMenuItem(title: localizedHorizontalTitle(), action: #selector(selectHorizontalLayout), keyEquivalent: "")
        horizontal.target = self
        submenu.addItem(horizontal)

        let vertical = NSMenuItem(title: localizedVerticalTitle(), action: #selector(selectVerticalLayout), keyEquivalent: "")
        vertical.target = self
        submenu.addItem(vertical)

        layoutMenuItems = [horizontal, vertical]
        refreshLayoutStates()

        root.submenu = submenu
        return root
    }

    // Only one font slider is shown at a time for the active layout.
    private func makeHorizontalSliderItem() -> NSMenuItem {
        makeFontSliderItem(
            title: localizedFontSizeTitle(),
            value: horizontalFontSize,
            min: 9.0,
            max: 13.0,
            action: #selector(horizontalSliderChanged(_:))
        )
    }

    private func makeVerticalSliderItem() -> NSMenuItem {
        makeFontSliderItem(
            title: localizedFontSizeTitle(),
            value: verticalFontSize,
            min: 7.0,
            max: 10.0,
            action: #selector(verticalSliderChanged(_:))
        )
    }

    // NSMenuItem custom view with label + slider.
    private func makeFontSliderItem(title: String, value: CGFloat, min: CGFloat, max: CGFloat, action: Selector) -> NSMenuItem {
        let item = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 48))

        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 12, y: 28, width: 226, height: 15)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        container.addSubview(label)

        let slider = NSSlider(value: Double(value), minValue: Double(min), maxValue: Double(max), target: self, action: action)
        slider.frame = NSRect(x: 12, y: 8, width: 226, height: 18)
        slider.numberOfTickMarks = Int((max - min) / Self.fontStep) + 1
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        
        container.addSubview(slider)

        item.view = container
        return item
    }

    // Toggle app registration in Login Items.
    private func makeLaunchAtLoginItem() -> NSMenuItem {
        let item = NSMenuItem(title: localizedLaunchAtLoginTitle(), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        item.target = self
        item.state = isLaunchAtLoginEnabled() ? .on : .off
        launchAtLoginItem = item
        return item
    }

    // Interface language submenu.
    private func makeLanguageMenuItem() -> NSMenuItem {
        let root = NSMenuItem(title: localizedLanguageTitle(), action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: localizedLanguageTitle())

        let entries: [(String, AppLanguage)] = [
            (localizedLanguageName(.russian), .russian),
            (localizedLanguageName(.english), .english),
            (localizedLanguageName(.hindi), .hindi),
            (localizedLanguageName(.chinese), .chinese)
        ]

        var items: [NSMenuItem] = []
        for (title, language) in entries {
            let item = NSMenuItem(title: title, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            submenu.addItem(item)
            items.append(item)
        }

        languageItems = items
        refreshLanguageStates()

        root.submenu = submenu
        return root
    }

    // Slider callbacks: quantize to 0.5 step, persist, then update title immediately.
    @objc private func horizontalSliderChanged(_ sender: NSSlider) {
        horizontalFontSize = quantized(sender.doubleValue)
        sender.doubleValue = Double(horizontalFontSize)
        UserDefaults.standard.set(Double(horizontalFontSize), forKey: horizontalFontDefaultsKey)
        requestDisplayRefresh(forceWhileMenuOpen: true)
    }

    @objc private func verticalSliderChanged(_ sender: NSSlider) {
        verticalFontSize = quantized(sender.doubleValue)
        sender.doubleValue = Double(verticalFontSize)
        UserDefaults.standard.set(Double(verticalFontSize), forKey: verticalFontDefaultsKey)
        requestDisplayRefresh(forceWhileMenuOpen: true)
    }

    // Keep values aligned with configured slider tick spacing.
    private func quantized(_ value: Double) -> CGFloat {
        let stepped = (value / Double(Self.fontStep)).rounded() * Double(Self.fontStep)
        return CGFloat(stepped)
    }

    @objc private func selectHorizontalLayout() { applyLayout(.horizontal) }
    @objc private func selectVerticalLayout() { applyLayout(.vertical) }

    // Persist layout and rebuild UI according to the selected orientation.
    private func applyLayout(_ layout: TextLayout) {
        layoutMode = layout
        UserDefaults.standard.set(layout.rawValue, forKey: layoutDefaultsKey)
        refreshLayoutStates()
        requestMenuRebuild()
        requestDisplayRefresh()
    }

    private func refreshLayoutStates() {
        for (index, item) in layoutMenuItems.enumerated() {
            item.state = index == layoutMode.rawValue ? .on : .off
        }
    }

    // Login item API state.
    private func isLaunchAtLoginEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if isLaunchAtLoginEnabled() {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
        launchAtLoginItem?.state = isLaunchAtLoginEnabled() ? .on : .off
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = AppLanguage(rawValue: rawValue) else { return }
        appLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: languageDefaultsKey)
        refreshLanguageStates()
        requestMenuRebuild()
    }

    private func refreshLanguageStates() {
        for item in languageItems {
            guard let raw = item.representedObject as? String else { continue }
            item.state = raw == appLanguage.rawValue ? .on : .off
        }
    }

    // Rebuild menu safely outside active menu layout pass.
    private func requestMenuRebuild() {
        if isMenuOpen {
            needsMenuRebuild = true
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statusItem?.menu = self.buildMenu()
        }
    }

    // Refresh status-bar image. When the menu is open, defer non-critical redraws.
    private func requestDisplayRefresh(forceWhileMenuOpen: Bool = false) {
        if forceWhileMenuOpen {
            updateDisplayTitle()
            return
        }

        if isMenuOpen {
            needsDisplayRefresh = true
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.updateDisplayTitle()
        }
    }

    // Render menu-bar title as image for precise coloring/positioning.
    private func updateDisplayTitle() {
        let text = displayText(from: latestRawText)
        guard let button = statusItem?.button else { return }

        let image = buildStatusImage(text: text, fontSize: effectiveFontSize())
        image.isTemplate = false

        button.title = ""
        button.image = image
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
    }

    private func effectiveFontSize() -> CGFloat {
        layoutMode == .horizontal ? horizontalFontSize : verticalFontSize
    }

    // Horizontal text is raw monitor output; vertical mode reorders lines (upload over download).
    private func displayText(from rawText: String) -> String {
        switch layoutMode {
        case .horizontal:
            let (down, up) = splitMetrics(from: rawText)
            let separator = String(repeating: " ", count: Self.horizontalMetricsGapSpaces)
            return "\(down)↓\(separator)\(up)↑"
        case .vertical:
            let (down, up) = splitMetrics(from: rawText)
            let downText = down + "↓"
            let upText = up + "↑"
            return "\(upText)\n\(downText)"
        }
    }

    // Parse monitor text into normalized numeric tokens.
    private func splitMetrics(from rawText: String) -> (down: String, up: String) {
        let parts = rawText.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let down = !parts.isEmpty ? sanitizeMetric(parts[0]) : "0K"
        let up = parts.count > 1 ? sanitizeMetric(parts[1]) : "0K"
        return (down, up)
    }

    private func sanitizeMetric(_ token: Substring) -> String {
        String(token).replacingOccurrences(of: "↓", with: "").replacingOccurrences(of: "↑", with: "")
    }

    // Draw text manually to keep center alignment stable for both single and two-line layouts.
    private func buildStatusImage(text: String, fontSize: CGFloat) -> NSImage {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
        let lines = text.components(separatedBy: "\n")
        let attributedLines = lines.map { attributedLine($0, font: font) }
        let lineSizes = attributedLines.map { $0.size() }

        let maxWidth = max(lineSizes.map(\ .width).max() ?? 0, 1)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let spacing = layoutMode == .vertical ? Self.verticalLineSpacing : Self.horizontalLineSpacing
        let height = max(CGFloat(lines.count) * lineHeight + CGFloat(max(0, lines.count - 1)) * spacing, 1)
        let width = ceil(maxWidth) + 2

        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()

            for (index, line) in attributedLines.enumerated() {
                let size = lineSizes[index]
                let x = (rect.width - size.width) / 2
                let y = rect.height - lineHeight - CGFloat(index) * (lineHeight + spacing)
                line.draw(at: NSPoint(x: x, y: y))
            }
            return true
        }
    }

    // Color arrows while preserving base color/spacing for metric values.
    private func attributedLine(_ line: String, font: NSFont) -> NSAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let attributed = NSMutableAttributedString(string: line, attributes: attrs)
        let nsLine = line as NSString

        if layoutMode == .horizontal {
            var searchRange = NSRange(location: 0, length: nsLine.length)
            while true {
                let spaceRange = nsLine.range(of: " ", options: [], range: searchRange)
                if spaceRange.location == NSNotFound { break }
                attributed.addAttribute(.kern, value: Self.horizontalMetricsKern, range: spaceRange)
                let nextLocation = spaceRange.location + spaceRange.length
                searchRange = NSRange(location: nextLocation, length: nsLine.length - nextLocation)
            }
        }

        let downRange = nsLine.range(of: "↓")
        if downRange.location != NSNotFound {
            attributed.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: downRange)
        }

        let upRange = nsLine.range(of: "↑")
        if upRange.location != NSNotFound {
            attributed.addAttribute(.foregroundColor, value: NSColor.systemRed, range: upRange)
        }

        return attributed
    }

    private func localizedLayoutTitle() -> String {
        switch appLanguage {
        case .russian: return "Расположение"
        case .english: return "Layout"
        case .hindi: return "लेआउट"
        case .chinese: return "布局"
        }
    }

    private func localizedHorizontalTitle() -> String {
        switch appLanguage {
        case .russian: return "Горизонтально"
        case .english: return "Horizontal"
        case .hindi: return "क्षैतिज"
        case .chinese: return "水平"
        }
    }

    private func localizedVerticalTitle() -> String {
        switch appLanguage {
        case .russian: return "Вертикально"
        case .english: return "Vertical"
        case .hindi: return "लंबवत"
        case .chinese: return "垂直"
        }
    }

    private func localizedFontSizeTitle() -> String {
        switch appLanguage {
        case .russian: return "Размер шрифта"
        case .english: return "Font Size"
        case .hindi: return "फ़ॉन्ट आकार"
        case .chinese: return "字体大小"
        }
    }

    private func localizedLaunchAtLoginTitle() -> String {
        switch appLanguage {
        case .russian: return "Запускать при входе"
        case .english: return "Launch at Login"
        case .hindi: return "लॉगिन पर चलाएँ"
        case .chinese: return "登录时启动"
        }
    }

    private func localizedLanguageTitle() -> String {
        switch appLanguage {
        case .russian: return "Язык интерфейса"
        case .english: return "Interface Language"
        case .hindi: return "इंटरफ़ेस भाषा"
        case .chinese: return "界面语言"
        }
    }

    private func localizedLanguageName(_ language: AppLanguage) -> String {
        switch language {
        case .russian: return "Русский"
        case .english: return "English"
        case .hindi: return "हिन्दी"
        case .chinese: return "中文"
        }
    }

    private func localizedQuitTitle() -> String {
        switch appLanguage {
        case .russian: return "Выход"
        case .english: return "Quit"
        case .hindi: return "बाहर निकलें"
        case .chinese: return "退出"
        }
    }

    private func localizedCreatedByTitle() -> String {
        switch appLanguage {
        case .russian: return "Создал Сергей Руссу, 2026"
        case .english: return "Created by Sergey Russu, 2026"
        case .hindi: return "निर्माता: Sergey Russu, 2026"
        case .chinese: return "由 Sergey Russu 创建，2026"
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        launchAtLoginItem?.state = isLaunchAtLoginEnabled() ? .on : .off
    }

    // Apply deferred menu/title updates once menu layout is finished.
    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        let hadPendingText = pendingRawText != nil
        if let pending = pendingRawText {
            latestRawText = pending
            self.pendingRawText = nil
        }

        if needsMenuRebuild {
            needsMenuRebuild = false
            statusItem?.menu = buildMenu()
        }

        if needsDisplayRefresh || hadPendingText {
            needsDisplayRefresh = false
            requestDisplayRefresh()
        }
    }
}

@main
struct MenuBarSpeedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
