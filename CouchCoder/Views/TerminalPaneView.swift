//
//  TerminalPaneView.swift
//  CouchCoder
//
//  Created by AI Assistant on 11/17/25.
//

import SwiftUI
import SwiftTerm
import UIKit

private enum TerminalAppearance {
    static let fontSize: CGFloat = 10.5
    static let targetColumns: CGFloat = 120
    static let minimumContentWidth: CGFloat = 680
    
    static func foregroundColor(for colorScheme: ColorScheme) -> UIColor {
        switch colorScheme {
        case .light:
            return UIColor.black
        case .dark:
            return UIColor.white
        @unknown default:
            return UIColor.white
        }
    }
    
    static func backgroundColor(for colorScheme: ColorScheme) -> UIColor {
        switch colorScheme {
        case .light:
            return UIColor.white
        case .dark:
            return UIColor.black
        @unknown default:
            return UIColor.black
        }
    }
    
    static func cursorColor(for colorScheme: ColorScheme) -> UIColor {
        switch colorScheme {
        case .light:
            return UIColor.systemBlue
        case .dark:
            return UIColor.systemMint
        @unknown default:
            return UIColor.systemMint
        }
    }
    
    static func selectionColor(for colorScheme: ColorScheme) -> UIColor {
        switch colorScheme {
        case .light:
            return UIColor.systemBlue.withAlphaComponent(0.2)
        case .dark:
            return UIColor.systemMint.withAlphaComponent(0.25)
        @unknown default:
            return UIColor.systemMint.withAlphaComponent(0.25)
        }
    }
}

/// Hosts `TerminalView` inside a horizontal scroll view so wide Codex output can be panned.
final class TerminalScrollContainerView: UIView {
    let terminalView = TerminalView()
    private let scrollView = UIScrollView()
    private var minimumWidthConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        terminalView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(terminalView)

        let flexibleWidth = terminalView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        flexibleWidth.priority = .defaultLow

        minimumWidthConstraint = terminalView.widthAnchor.constraint(greaterThanOrEqualToConstant: TerminalAppearance.minimumContentWidth)

        var constraints = [NSLayoutConstraint]()
        constraints.append(contentsOf: [
            terminalView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            terminalView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            flexibleWidth
        ])

        if let minimumWidthConstraint {
            constraints.append(minimumWidthConstraint)
        }

        NSLayoutConstraint.activate(constraints)
    }

    func updateMinimumContentWidth(for font: UIFont) {
        let glyphWidth = "W".size(withAttributes: [.font: font]).width
        let preferredWidth = max(
            TerminalAppearance.targetColumns * glyphWidth,
            TerminalAppearance.minimumContentWidth
        )
        minimumWidthConstraint?.constant = preferredWidth
    }
}

/// SwiftUI wrapper for SwiftTerm's TerminalView
struct TerminalPaneView: UIViewRepresentable {
    let bridge: TerminalBridge
    @Environment(\.colorScheme) var colorScheme
    
    func makeUIView(context: Context) -> TerminalScrollContainerView {
        let container = TerminalScrollContainerView()
        let term = container.terminalView
        term.terminalDelegate = bridge
        
        // Configure terminal appearance
        configureAppearance(term, container: container, colorScheme: colorScheme)
        configureAccessoryView(for: term)
        
        // Attach to bridge
        bridge.attach(terminalView: term)
        
        return container
    }
    
    func updateUIView(_ uiView: TerminalScrollContainerView, context: Context) {
        // Update appearance when color scheme changes
        configureAppearance(uiView.terminalView, container: uiView, colorScheme: colorScheme)
        uiView.updateMinimumContentWidth(for: uiView.terminalView.font)
    }
    
    private func configureAppearance(_ term: TerminalView, container: TerminalScrollContainerView, colorScheme: ColorScheme) {
        let foregroundColor = TerminalAppearance.foregroundColor(for: colorScheme)
        let backgroundColor = TerminalAppearance.backgroundColor(for: colorScheme)
        let cursorColor = TerminalAppearance.cursorColor(for: colorScheme)
        let selectionColor = TerminalAppearance.selectionColor(for: colorScheme)
        
        term.nativeForegroundColor = foregroundColor
        term.nativeBackgroundColor = backgroundColor
        term.caretColor = cursorColor
        term.selectedTextBackgroundColor = selectionColor
        term.backgroundColor = backgroundColor
        
        // Remove rounded corners
        term.layer.cornerRadius = 0
        term.layer.masksToBounds = false
        
        // Ensure opaque rendering for better text clarity
        term.isOpaque = true
        term.clearsContextBeforeDrawing = true
        
        // Improve text rendering quality
        term.contentMode = .left
        term.layer.shouldRasterize = false
        
        // Improve text rendering to reduce shimmering
        term.layer.allowsEdgeAntialiasing = true
        
        // Set font with slightly smaller size
        let font = UIFont.monospacedSystemFont(ofSize: TerminalAppearance.fontSize, weight: .regular)
        term.font = font
        container.updateMinimumContentWidth(for: font)
        
        // Force redraw to apply changes
        term.setNeedsDisplay()
    }
    
    private func configureAccessoryView(for term: TerminalView) {
        #if os(iOS)
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        let height: CGFloat = isPhone ? 36 : 48
        
        // Get width from the view's window scene instead of deprecated UIScreen.main
        // Use a reasonable default that will be adjusted when the view is laid out
        var width: CGFloat = 375 // Default fallback for iPhone
        if let windowScene = term.window?.windowScene {
            width = windowScene.screen.bounds.width
        } else if let screen = term.window?.screen {
            // Fallback to window's screen if windowScene isn't available
            width = screen.bounds.width
        } else {
            // Use device-based estimate as last resort
            width = isPhone ? 375 : 768
        }
        
        let accessory = CouchCoderTerminalAccessory(
            frame: CGRect(x: 0, y: 0, width: width, height: height),
            inputViewStyle: .keyboard,
            container: term
        )
        accessory.sizeToFit()
        term.inputAssistantItem.leadingBarButtonGroups = []
        term.inputAssistantItem.trailingBarButtonGroups = []
        term.inputAccessoryView = accessory
        #endif
    }
}

// MARK: - Terminal accessory customizations

/// Custom input accessory view for terminal keyboard
private final class CouchCoderTerminalAccessory: UIView {
    private weak var terminalView: TerminalView?
    private weak var pasteButton: UIButton?
    private weak var ctrlCButton: UIButton?
    
    init(frame: CGRect, inputViewStyle: UIInputView.Style, container: TerminalView) {
        super.init(frame: frame)
        self.terminalView = container
        setupAccessoryView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        configureShortcutButtons()
    }
    
    private func setupAccessoryView() {
        backgroundColor = .systemGray6
        
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 3
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        // Tab button
        stackView.addArrangedSubview(createButton(title: "Tab", image: nil, action: #selector(handleTab)))
        
        // Escape button
        stackView.addArrangedSubview(createButton(title: "Esc", image: nil, action: #selector(handleEscape)))
        
        // Arrow keys
        stackView.addArrangedSubview(createButton(title: "↑", image: nil, action: #selector(handleUpArrow)))
        stackView.addArrangedSubview(createButton(title: "↓", image: nil, action: #selector(handleDownArrow)))
        stackView.addArrangedSubview(createButton(title: "←", image: nil, action: #selector(handleLeftArrow)))
        stackView.addArrangedSubview(createButton(title: "→", image: nil, action: #selector(handleRightArrow)))
        
        // Paste button
        let pasteBtn = createButton(title: "Paste", image: UIImage(systemName: "doc.on.clipboard"), action: #selector(handlePaste))
        pasteButton = pasteBtn
        stackView.addArrangedSubview(pasteBtn)
        
        // Ctrl+C button
        let ctrlCBtn = createButton(title: "Ctrl+C", image: UIImage(systemName: "xmark.seal"), action: #selector(handleCtrlC))
        ctrlCButton = ctrlCBtn
        stackView.addArrangedSubview(ctrlCBtn)
        
        // Keyboard minimize button
        stackView.addArrangedSubview(createButton(title: "⌨", image: UIImage(systemName: "keyboard.chevron.compact.down"), action: #selector(handleMinimizeKeyboard)))
        
        scrollView.addSubview(stackView)
        addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -8),
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }
    
    private func createButton(title: String, image: UIImage?, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        if let image = image {
            button.setImage(image, for: .normal)
            button.setTitle("", for: .normal)
        } else {
            button.setTitle(title, for: .normal)
        }
        button.titleLabel?.font = UIFont.systemFont(ofSize: 10, weight: .semibold)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.backgroundColor = .systemBackground
        button.layer.cornerRadius = 6
        button.accessibilityLabel = title
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        return button
    }
    
    private func configureShortcutButtons() {
        // This method is kept for potential future customization
        // Currently buttons are created in setupAccessoryView
    }
    
    @objc private func handleTab() {
        terminalView?.send(txt: "\t")
    }
    
    @objc private func handleEscape() {
        terminalView?.send(txt: "\u{001B}")
    }
    
    @objc private func handleUpArrow() {
        terminalView?.send(txt: "\u{001B}[A")
    }
    
    @objc private func handleDownArrow() {
        terminalView?.send(txt: "\u{001B}[B")
    }
    
    @objc private func handleLeftArrow() {
        terminalView?.send(txt: "\u{001B}[D")
    }
    
    @objc private func handleRightArrow() {
        terminalView?.send(txt: "\u{001B}[C")
    }
    
    @objc private func handlePaste() {
        terminalView?.paste(nil)
    }
    
    @objc private func handleCtrlC() {
        // Send Ctrl+C directly through the delegate to bypass SwiftTerm's terminal emulation
        // which can cause cursor position issues. This goes straight to SSH.
        guard let terminalView = terminalView,
              let delegate = terminalView.terminalDelegate as? TerminalBridge else {
            // Fallback: send as raw bytes if delegate is not available
            let ctrlCByte: UInt8 = 0x03
            terminalView?.send(data: [ctrlCByte][...])
            return
        }
        // Use the delegate's send method which goes directly to SSH
        let ctrlCByte: UInt8 = 0x03
        delegate.send(source: terminalView, data: [ctrlCByte][...])
    }
    
    @objc private func handleMinimizeKeyboard() {
        _ = terminalView?.resignFirstResponder()
    }
}
