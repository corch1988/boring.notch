//
//  NotchBarWindow.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Cocoa
import Combine
import Defaults

/// Full-width black bar on notched displays, drawn *behind* the menu bar so the
/// notch blends into one solid strip. It ignores mouse events, so hovering stays
/// exclusive to the notch window above it.
class NotchBarWindow: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isMovable = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .mainMenu - 1
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]

        reposition(on: screen)
        orderFrontRegardless()
    }

    /// AppKit pushes windows below `.mainMenu` level down so they can't cover the
    /// menu bar — which would park the bar right underneath the notch instead of on it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    func reposition(on screen: NSScreen) {
        let height = screen.safeAreaInsets.top
        setFrame(
            NSRect(
                x: screen.frame.minX,
                y: screen.frame.maxY - height,
                width: screen.frame.width,
                height: height
            ),
            display: true
        )
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

@MainActor
final class NotchBarWindowManager {
    static let shared = NotchBarWindowManager()

    private var windows: [String: NotchBarWindow] = [:] // UUID -> NotchBarWindow
    private var cancellables: Set<AnyCancellable> = []

    private init() {}

    func start() {
        Defaults.publisher(.hideNotch)
            .sink { [weak self] _ in
                Task { @MainActor in self?.update() }
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.update() }
            }
            .store(in: &cancellables)

        update()
    }

    func update() {
        guard Defaults[.hideNotch] else {
            close(Set(windows.keys))
            return
        }

        // ponytail: only real notches get a bar; a fake one on external displays is a separate feature
        let notchedScreens = NSScreen.screens.filter { $0.safeAreaInsets.top > 0 }
        let liveUUIDs = Set(notchedScreens.compactMap { $0.displayUUID })
        close(Set(windows.keys).subtracting(liveUUIDs))

        for screen in notchedScreens {
            guard let uuid = screen.displayUUID else { continue }

            if let window = windows[uuid] {
                window.reposition(on: screen)
            } else {
                windows[uuid] = NotchBarWindow(screen: screen)
            }
        }
    }

    private func close(_ uuids: Set<String>) {
        for uuid in uuids {
            windows[uuid]?.close()
            windows.removeValue(forKey: uuid)
        }
    }
}
