import AppKit
import Carbon.HIToolbox
import SwiftUI

var hotKeyAction: (() -> Void)?


final class LaunchWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = LaunchModel()
    private var window: LaunchWindow!
    private var isShown = false
    private var optionEdit = false
    private var effectView: NSVisualEffectView!
    private var showGen = 0
    private var leftForSettings = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
        buildMenu()
        buildWindow()
        installHotKey()
        installMonitors()
        model.close = { [weak self] in self?.hide() }
        model.mousePoint = { [weak self] in
            guard let w = self?.window else { return .zero }
            let p = w.mouseLocationOutsideOfEventStream
            return CGPoint(x: p.x, y: w.frame.height - p.y)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.model.awaitingSettings { self.leftForSettings = true }
            self.hide()
        }
        // Разрешения macOS (Управление приложениями, Автоматизация) применяются только к заново запущенной программе:
        // когда пользователь вернулся из настроек — перезапускаемся сами.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.model.awaitingSettings, self.leftForSettings else { return }
            self.relaunch()
        }
        show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !isShown { show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Window

    private func buildWindow() {
        let w = LaunchWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        w.acceptsMouseMovedEvents = true
        w.appearance = NSAppearance(named: .darkAqua)
        w.isReleasedWhenClosed = false

        let effect = NSVisualEffectView()
        effect.material = .fullScreenUI
        effect.blendingMode = .behindWindow
        effect.state = .active
        effectView = effect
        effect.autoresizingMask = [.width, .height]
        let host = NSHostingView(rootView: RootView(model: model))
        host.autoresizingMask = [.width, .height]
        let container = NSView()
        effect.frame = container.bounds
        host.frame = container.bounds
        container.addSubview(effect)
        container.addSubview(host)
        w.contentView = container
        window = w
    }

    func show() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        window.setFrame(screen.frame, display: true)
        optionEdit = false
        model.resetForShow()
        model.reload()
        showGen += 1
        NSApp.unhide(nil)
        // Фон — системное стекло «насквозь»: всегда показывает актуальные обои
        // (в том числе динамические и аэро-заставки, у которых нет файла-картинки).
        model.wallpaper = nil
        effectView.isHidden = false
        model.visible = false
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            window.animator().alphaValue = 1
        }
        NSApp.activate(ignoringOtherApps: true)
        isShown = true
        model.focusTick += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { self.model.setVisible(true) }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        model.editMode = false
        let gen = showGen
        model.setVisible(false)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            window.animator().alphaValue = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard gen == self.showGen, !self.isShown else { return }
            self.window.orderOut(nil)
            NSApp.deactivate()
        }
    }

    /// Запускает новую копию и закрывает текущую (после паузы, чтобы старая успела выйти).
    func relaunch() {
        let path = Bundle.main.bundlePath.replacingOccurrences(of: "'", with: "'\\''")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.7; open '\(path)'"]
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc func toggle() { isShown ? hide() : show() }

    // MARK: Menu

    private func buildMenu() {
        // меню приложения не нужно: Launchpad управляется значком в Dock и ⌃⌥Space, выход — ⌘Q
        NSApp.mainMenu = NSMenu()
    }

    // MARK: Hot key  (⌃⌥Space)

    private func installHotKey() {
        hotKeyAction = { [weak self] in self?.toggle() }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in hotKeyAction?(); return noErr }, 1, &spec, nil, nil)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: OSType(0x4C50434B), id: 1), GetApplicationEventTarget(), 0, &ref)
    }

    // MARK: Events

    private func installMonitors() {
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel, .leftMouseUp, .leftMouseDragged, .flagsChanged]) { [weak self] e in
            guard let self, self.isShown else { return e }
            switch e.type {
            case .keyDown: return self.handleKey(e)
            case .scrollWheel: return self.model.handleScroll(e) ? nil : e
            case .flagsChanged:
                let f = e.modifierFlags
                let opt = f.contains(.option) && !f.contains(.control) && !f.contains(.command)
                if opt != self.optionEdit {
                    self.optionEdit = opt
                    if self.model.draggingID == nil, self.model.pendingDelete == nil { self.model.editMode = opt }
                }
                return e
            case .leftMouseDragged:
                self.model.dragMove()
                return e
            case .leftMouseUp:
                if self.model.draggingID != nil { self.model.endDrag() }
                return e
            default:
                return e
            }
        }
    }

    private func handleKey(_ e: NSEvent) -> NSEvent? {
        if e.modifierFlags.contains(.command), e.charactersIgnoringModifiers == "q" { NSApp.terminate(nil); return nil }
        switch Int(e.keyCode) {
        case kVK_Escape:
            if model.pendingDelete != nil { model.cancelDelete() }
            else if model.openFolderID != nil { model.closeFolder() }
            else if model.editMode { model.editMode = false }
            else if !model.query.isEmpty { model.query = "" }
            else { hide() }
            return nil
        case kVK_LeftArrow where model.query.isEmpty && model.openFolderID == nil:
            model.changePage(-1); return nil
        case kVK_RightArrow where model.query.isEmpty && model.openFolderID == nil:
            model.changePage(1); return nil
        default:
            return e
        }
    }
}
