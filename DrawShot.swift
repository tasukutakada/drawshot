//
//  DrawShot.swift
//  macOS用 ZoomIt風 画面描画ツール
//
//  ⌘2          : 描画モードの ON / OFF(グローバルホットキー)
//  ドラッグ      : フリーハンドペン
//  ⌘ + ドラッグ  : 四角形
//  ⇧ + ドラッグ  : 直線
//  ⌥ + ドラッグ  : 楕円
//  R/G/B/Y/O/P/W/K : 色変更(赤/緑/青/黄/橙/ピンク/白/黒)
//  [ / ]        : 線を細く / 太く(↓ / ↑ でも可)
//  ⌘Z           : 取り消し
//  E            : 全消去
//  ⌘S (または S) : スクリーンショットをデスクトップに保存
//  Esc          : 描画モード終了
//
//  メニューバーの「ログイン時に起動」で、Mac 起動時に自動で常駐させられる
//

import Cocoa
import Carbon.HIToolbox
import ScreenCaptureKit
import ServiceManagement

// MARK: - 図形モデル

struct Shape {
    enum Kind { case pen, rect, line, ellipse }
    var kind: Kind
    var color: NSColor
    var lineWidth: CGFloat
    var points: [CGPoint]   // pen 用
    var start: CGPoint
    var end: CGPoint
}

// MARK: - 描画ビュー

final class DrawingView: NSView {
    var shapes: [Shape] = []
    var current: Shape?
    var color: NSColor = .systemRed
    var lineWidth: CGFloat = 4
    var captureMode = false      // スクショ撮影中は暗幕を消す

    var onExit: (() -> Void)?
    var onSave: (() -> Void)?
    var onStatusChange: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: マウス

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let kind: Shape.Kind
        if event.modifierFlags.contains(.command)      { kind = .rect }
        else if event.modifierFlags.contains(.shift)   { kind = .line }
        else if event.modifierFlags.contains(.option)  { kind = .ellipse }
        else                                           { kind = .pen }
        current = Shape(kind: kind, color: color, lineWidth: lineWidth,
                        points: [p], start: p, end: p)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard current != nil else { return }
        let p = convert(event.locationInWindow, from: nil)
        current?.end = p
        if current?.kind == .pen { current?.points.append(p) }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let c = current { shapes.append(c) }
        current = nil
        needsDisplay = true
    }

    // MARK: キーボード

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { onExit?(); return }

        // 矢印キーで線の太さ変更（[/] が IME に取られる環境向けの代替）
        switch event.keyCode {
        case UInt16(kVK_UpArrow):
            lineWidth = min(30, lineWidth + 1)
            onStatusChange?("線の太さ: \(Int(lineWidth))")
            return
        case UInt16(kVK_DownArrow):
            lineWidth = max(1, lineWidth - 1)
            onStatusChange?("線の太さ: \(Int(lineWidth))")
            return
        default:
            break
        }

        let flags = event.modifierFlags
        guard let chars = event.charactersIgnoringModifiers?.lowercased(),
              !chars.isEmpty else { return }

        if flags.contains(.command) {
            switch chars {
            case "z":
                if !shapes.isEmpty { shapes.removeLast(); needsDisplay = true }
            case "s":
                onSave?()
            default:
                break
            }
            return
        }

        switch chars {
        case "r": setColor(.systemRed,    name: "赤")
        case "g": setColor(.systemGreen,  name: "緑")
        case "b": setColor(.systemBlue,   name: "青")
        case "y": setColor(.systemYellow, name: "黄")
        case "o": setColor(.systemOrange, name: "橙")
        case "p": setColor(.systemPink,   name: "ピンク")
        case "w": setColor(.white,        name: "白")
        case "k": setColor(.black,        name: "黒")
        case "e":
            shapes.removeAll()
            needsDisplay = true
            onStatusChange?("全消去しました")
        case "s":
            onSave?()
        case "[":
            lineWidth = max(1, lineWidth - 1)
            onStatusChange?("線の太さ: \(Int(lineWidth))")
        case "]":
            lineWidth = min(30, lineWidth + 1)
            onStatusChange?("線の太さ: \(Int(lineWidth))")
        default:
            break
        }
    }

    private func setColor(_ c: NSColor, name: String) {
        color = c
        onStatusChange?("色: \(name)")
    }

    // MARK: 描画

    override func draw(_ dirtyRect: NSRect) {
        if !captureMode {
            // 描画モード中であることが分かる薄い暗幕
            NSColor.black.withAlphaComponent(0.06).setFill()
            bounds.fill()
        }
        for s in shapes { drawShape(s) }
        if let c = current { drawShape(c) }
    }

    private func drawShape(_ s: Shape) {
        s.color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = s.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        switch s.kind {
        case .pen:
            guard let first = s.points.first else { return }
            path.move(to: first)
            for p in s.points.dropFirst() { path.line(to: p) }
        case .line:
            path.move(to: s.start)
            path.line(to: s.end)
        case .rect:
            path.appendRect(normalizedRect(s.start, s.end))
        case .ellipse:
            path.appendOval(in: normalizedRect(s.start, s.end))
        }
        path.stroke()
    }

    private func normalizedRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

// MARK: - オーバーレイウィンドウ

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - アプリ本体

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlay: OverlayWindow?
    private var drawingView: DrawingView?
    private var helpLabel: NSTextField?
    private var messageLabel: NSTextField?
    private var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        registerHotKey()

        // 画面収録の権限を事前に確認(スクショ保存に必要)
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    // MARK: メニューバー

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if #available(macOS 11.0, *),
               let img = NSImage(systemSymbolName: "pencil.tip.crop.circle",
                                 accessibilityDescription: "DrawShot") {
                button.image = img
            } else {
                button.title = "✏️"
            }
        }
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "描画モード (⌘2)", action: #selector(toggleFromMenu), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let login = NSMenuItem(title: "ログイン時に起動", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "DrawShot を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func toggleFromMenu() { toggleDrawing() }

    // MARK: ログイン時に起動

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("DrawShot: ログイン項目の変更に失敗: \(error)")
            let alert = NSAlert()
            alert.messageText = "ログイン項目の設定に失敗しました"
            alert.informativeText = "\(error.localizedDescription)\n\nシステム設定 → 一般 → ログイン項目 から手動で追加することもできます。"
            NSApp.activate()
            alert.runModal()
        }
        sender.state = service.status == .enabled ? .on : .off
    }

    // MARK: グローバルホットキー (⌘2)

    private func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, _) -> OSStatus in
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.toggleDrawing()
            }
            return noErr
        }, 1, &eventType, nil, nil)

        let hotKeyID = EventHotKeyID(signature: OSType(0x44535448), id: 1) // "DSTH"
        RegisterEventHotKey(UInt32(kVK_ANSI_2), UInt32(cmdKey), hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: 描画モード切り替え

    func toggleDrawing() {
        if overlay == nil { enterDrawingMode() } else { exitDrawingMode() }
    }

    private func screenWithMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func enterDrawingMode() {
        let screen = screenWithMouse()
        let window = OverlayWindow(contentRect: screen.frame,
                                   styleMask: .borderless,
                                   backing: .buffered,
                                   defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = DrawingView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onExit = { [weak self] in self?.exitDrawingMode() }
        view.onSave = { [weak self] in self?.saveScreenshot() }
        view.onStatusChange = { [weak self] msg in self?.showMessage(msg) }
        window.contentView = view

        // 操作ヘルプ(上部)
        let help = NSTextField(labelWithString:
            "ドラッグ:ペン  ⌘ドラッグ:四角  ⇧:直線  ⌥:楕円  |  R/G/B/Y/O/P/W/K:色  [/] ↓↑:太さ  ⌘Z:取消  E:全消去  ⌘S:スクショ保存  Esc:終了")
        help.font = .systemFont(ofSize: 13, weight: .medium)
        help.textColor = .white
        help.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        help.drawsBackground = true
        help.alignment = .center
        help.sizeToFit()
        let helpW = help.frame.width + 24
        let helpH = help.frame.height + 10
        help.frame = NSRect(x: (view.bounds.width - helpW) / 2,
                            y: view.bounds.height - helpH - 12,
                            width: helpW, height: helpH)
        help.wantsLayer = true
        help.layer?.cornerRadius = 6
        view.addSubview(help)

        // メッセージ表示用(下部)
        let message = NSTextField(labelWithString: "")
        message.font = .systemFont(ofSize: 14, weight: .semibold)
        message.textColor = .white
        message.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        message.drawsBackground = true
        message.alignment = .center
        message.isHidden = true
        view.addSubview(message)

        overlay = window
        drawingView = view
        helpLabel = help
        messageLabel = message

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate()
    }

    private func exitDrawingMode() {
        overlay?.orderOut(nil)
        overlay = nil
        drawingView = nil
        helpLabel = nil
        messageLabel = nil
    }

    // MARK: メッセージ表示

    private func showMessage(_ text: String) {
        guard let view = drawingView, let label = messageLabel else { return }
        label.stringValue = text
        label.sizeToFit()
        let w = label.frame.width + 24
        let h = label.frame.height + 10
        label.frame = NSRect(x: (view.bounds.width - w) / 2, y: 40, width: w, height: h)
        label.wantsLayer = true
        label.layer?.cornerRadius = 6
        label.isHidden = false
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideMessage), object: nil)
        perform(#selector(hideMessage), with: nil, afterDelay: 2.5)
    }

    @objc private func hideMessage() {
        messageLabel?.isHidden = true
    }

    // MARK: スクリーンショット

    private func saveScreenshot() {
        guard let window = overlay,
              let view = drawingView,
              let screen = window.screen ?? NSScreen.main,
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return }

        let displayID = CGDirectDisplayID(screenNumber.uint32Value)

        // 暗幕とHUDを一時的に消してから撮影する
        view.captureMode = true
        helpLabel?.isHidden = true
        messageLabel?.isHidden = true
        view.needsDisplay = true
        view.displayIfNeeded()

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                view.captureMode = false
                self.helpLabel?.isHidden = false
                view.needsDisplay = true
            }
            do {
                // コンポジット反映を待つ
                try await Task.sleep(nanoseconds: 150_000_000)

                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
                    showMessage("ディスプレイが見つかりませんでした")
                    return
                }
                let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width  = Int(screen.frame.width  * screen.backingScaleFactor)
                config.height = Int(screen.frame.height * screen.backingScaleFactor)
                config.showsCursor = false

                let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                         configuration: config)

                let rep = NSBitmapImageRep(cgImage: cgImage)
                guard let data = rep.representation(using: .png, properties: [:]) else {
                    showMessage("PNG変換に失敗しました")
                    return
                }

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd-HHmmss"
                let filename = "DrawShot-\(formatter.string(from: Date())).png"
                let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
                let url = desktop.appendingPathComponent(filename)

                try data.write(to: url)
                NSSound(named: "Glass")?.play()
                showMessage("保存しました: デスクトップ/\(filename)")
            } catch {
                showMessage("撮影に失敗しました: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - エントリポイント

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // Dockに出さないメニューバー常駐アプリ
app.run()
