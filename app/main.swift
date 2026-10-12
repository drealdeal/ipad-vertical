// iPad Vertical - tiny menu bar app with two buttons:
//   Vertical   = portrait virtual display, shown rotated on the Sidecar iPad
//   Horizontal = plain landscape Sidecar
// Everything lives in the menu bar icon's menu.
// Toggle hotkey: Ctrl+Option+V

import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

// Portrait resolutions (points, all HiDPI). 820x1180 is the iPad 10th gen's native Sidecar size turned sideways.
let resolutions: [(name: String, size: CGSize)] = [
    ("Larger Text - 656 x 944", CGSize(width: 656, height: 944)),
    ("Default - 820 x 1180", CGSize(width: 820, height: 1180)),
    ("More Space - 1024 x 1474", CGSize(width: 1024, height: 1474)),
    ("Most Space - 1230 x 1770", CGSize(width: 1230, height: 1770)),
]
var resolutionIndex: Int {
    get { let i = UserDefaults.standard.object(forKey: "resolution") as? Int ?? 1; return resolutions.indices.contains(i) ? i : 1 }
    set { UserDefaults.standard.set(newValue, forKey: "resolution") }
}
var portraitPoints: CGSize { resolutions[resolutionIndex].size }
let capturePixels = CGSize(width: 1640, height: 2360)     // iPad panel pixels, turned sideways

func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

// MARK: - Sidecar (private SidecarCore framework)

enum Sidecar {
    static let manager: NSObject? = {
        dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_NOW)
        guard let cls = NSClassFromString("SidecarDisplayManager") as? NSObject.Type else { return nil }
        return cls.perform(Selector(("sharedManager")))?.takeUnretainedValue() as? NSObject
    }()

    static func devices() -> [NSObject] {
        (manager?.perform(Selector(("devices")))?.takeUnretainedValue() as? [NSObject]) ?? []
    }

    static func call(_ selector: String, done: @escaping (Bool) -> Void) {
        guard let manager, let device = devices().first else { done(false); return }
        let block: @convention(block) (NSError?) -> Void = { err in
            if let err { log("Sidecar \(selector) error: \(err.localizedDescription)") }
            DispatchQueue.main.async { done(err == nil) }
        }
        _ = manager.perform(Selector((selector)), with: device, with: block)
    }

    static func connect(done: @escaping (Bool) -> Void) { call("connectToDevice:completion:", done: done) }
    static func disconnect(done: @escaping (Bool) -> Void) { call("disconnectFromDevice:completion:", done: done) }
}

// MARK: - Displays

func displayID(of screen: NSScreen) -> CGDirectDisplayID {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
}

func place(_ moves: [(CGDirectDisplayID, Int, Int)]) {
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success else { return }
    for (id, x, y) in moves { CGConfigureDisplayOrigin(cfg, id, Int32(x), Int32(y)) }
    CGCompleteDisplayConfiguration(cfg, .forSession)
}

// MARK: - Controller

final class Controller: NSObject, SCStreamOutput, SCStreamDelegate {
    private var virtual: CGVirtualDisplay?
    private var stream: SCStream?
    private var window: NSWindow?
    private let content = CALayer()
    private let queue = DispatchQueue(label: "ipad-vertical.frames")
    var onStatus: (String) -> Void = { _ in }
    var isVertical: Bool { virtual != nil }
    var hasSidecar: Bool { sidecarScreen() != nil }

    private var rotation: Int {
        get { let r = UserDefaults.standard.integer(forKey: "rotation"); return r == 90 ? 90 : 270 }
        set { UserDefaults.standard.set(newValue, forKey: "rotation") }
    }
    private var sideLeft: Bool { UserDefaults.standard.bool(forKey: "sideLeft") }

    private func sidecarScreen() -> NSScreen? {
        let vid = virtual?.displayID ?? 0
        let others = NSScreen.screens.filter {
            let id = displayID(of: $0)
            return id != vid && CGDisplayIsBuiltin(id) == 0 && $0.localizedName != "iPad Vertical"
        }
        return others.first { n in ["sidecar", "ipad", "airplay"].contains { n.localizedName.lowercased().contains($0) } }
            ?? others.first
    }

    private func ensureSidecar(_ then: @escaping (Bool) -> Void) {
        if sidecarScreen() != nil { then(true); return }
        onStatus("Connecting to iPad...")
        Sidecar.connect { _ in
            self.waitFor({ self.sidecarScreen() != nil }, tries: 20) { then($0) }
        }
    }

    private func waitFor(_ cond: @escaping () -> Bool, tries: Int, _ then: @escaping (Bool) -> Void) {
        if cond() { then(true); return }
        if tries <= 0 { then(false); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.waitFor(cond, tries: tries - 1, then) }
    }

    // MARK: Vertical

    func vertical() {
        if isVertical { return }
        ensureSidecar { ok in
            guard ok else { self.onStatus("iPad not found. Plug it in and unlock it."); return }
            self.onStatus("Starting vertical...")

            let d = CGVirtualDisplayDescriptor()
            d.queue = DispatchQueue.main
            d.name = "iPad Vertical"
            d.maxPixelsWide = UInt(portraitPoints.width * 2)
            d.maxPixelsHigh = UInt(portraitPoints.height * 2)
            d.sizeInMillimeters = CGSize(width: 158, height: 227)
            d.vendorID = 0x1D0C; d.productID = 0x1AD0; d.serialNum = 1
            guard let v = CGVirtualDisplay(descriptor: d) else { self.onStatus("Could not create the portrait display."); return }
            let s = CGVirtualDisplaySettings()
            s.hiDPI = 1
            s.modes = [CGVirtualDisplayMode(width: UInt(portraitPoints.width), height: UInt(portraitPoints.height), refreshRate: 60)].compactMap { $0 }
            guard v.applySettings(s) else { self.onStatus("Could not create the portrait display."); return }
            self.virtual = v

            self.waitFor({ NSScreen.screens.contains { displayID(of: $0) == v.displayID } }, tries: 20) { found in
                guard found, let side = self.sidecarScreen() else { self.fail("Portrait display did not appear."); return }
                let mainW = Int(CGDisplayBounds(CGMainDisplayID()).width)
                let sid = displayID(of: side)
                let sw = Int(side.frame.width), sh = Int(side.frame.height)
                // Portrait display next to the MacBook; the hidden landscape Sidecar desktop is parked
                // corner-to-corner on the far side so the cursor cannot wander into it.
                if self.sideLeft {
                    place([(v.displayID, -Int(portraitPoints.width), 0), (sid, mainW, -sh)])
                } else {
                    place([(v.displayID, mainW, 0), (sid, -sw, -sh)])
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.startCapture(v.displayID) }
            }
        }
    }

    private func startCapture(_ vid: CGDirectDisplayID) {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { shareable, err in
            DispatchQueue.main.async {
                guard let display = shareable?.displays.first(where: { $0.displayID == vid }) else {
                    self.fail(err != nil
                        ? "Allow 'iPad Vertical' under Privacy & Security > Screen & System Audio Recording, then press Vertical again."
                        : "Portrait display not capturable.")
                    return
                }
                let cfg = SCStreamConfiguration()
                cfg.width = Int(capturePixels.width)
                cfg.height = Int(capturePixels.height)
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                cfg.showsCursor = true
                cfg.pixelFormat = kCVPixelFormatType_32BGRA
                cfg.queueDepth = 4
                let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg, delegate: self)
                do {
                    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue)
                } catch { self.fail("Capture setup failed: \(error.localizedDescription)"); return }
                stream.startCapture { err in
                    DispatchQueue.main.async {
                        if let err { self.fail("Capture failed: \(err.localizedDescription)"); return }
                        self.stream = stream
                        self.showWindow()
                        self.onStatus("Vertical is on")
                    }
                }
            }
        }
    }

    private func showWindow() {
        guard let screen = sidecarScreen() else { fail("iPad display disappeared."); return }
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        w.backgroundColor = .black
        w.isOpaque = true
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        content.contentsGravity = .resize
        view.layer?.addSublayer(content)
        w.contentView = view
        w.setFrame(screen.frame, display: true)
        w.orderFrontRegardless()
        window = w
        layoutContent()
    }

    private func layoutContent() {
        guard let size = window?.contentView?.bounds.size else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        // Portrait picture laid on its side to fill the landscape Sidecar surface.
        content.bounds = CGRect(x: 0, y: 0, width: size.height, height: size.width)
        content.position = CGPoint(x: size.width / 2, y: size.height / 2)
        content.setAffineTransform(CGAffineTransform(rotationAngle: rotation == 270 ? .pi / 2 : -.pi / 2))
        CATransaction.commit()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pb = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pb)?.takeUnretainedValue() else { return }
        DispatchQueue.main.async {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            self.content.contents = surface
            CATransaction.commit()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { if self.isVertical { self.fail("Capture stopped: \(error.localizedDescription)") } }
    }

    private func fail(_ message: String) {
        log(message)
        teardown()
        onStatus(message)
    }

    private func teardown() {
        stream?.stopCapture(completionHandler: nil)
        stream = nil
        window?.orderOut(nil)
        window = nil
        content.contents = nil
        content.removeFromSuperlayer()
        virtual = nil   // releasing the object removes the virtual display
    }

    // MARK: Horizontal

    func horizontal() {
        teardown()
        ensureSidecar { ok in
            guard ok, let side = self.sidecarScreen() else { self.onStatus("iPad not found. Plug it in and unlock it."); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let mainW = Int(CGDisplayBounds(CGMainDisplayID()).width)
                place([(displayID(of: side), self.sideLeft ? -Int(side.frame.width) : mainW, 0)])
                self.onStatus("Horizontal is on")
            }
        }
    }

    func toggle() { isVertical ? horizontal() : vertical() }

    func setResolution(_ index: Int) {
        resolutionIndex = index
        guard isVertical else { onStatus("Resolution saved for next Vertical"); return }
        teardown()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.vertical() }
    }

    func flip() {
        rotation = rotation == 270 ? 90 : 270
        layoutContent()
        onStatus(isVertical ? "Rotated" : "Rotation saved for next Vertical")
    }

    func disconnect() {
        teardown()
        Sidecar.disconnect { _ in self.onStatus("iPad disconnected") }
    }
}

// MARK: - App (menu bar only)

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static var shared: AppDelegate!
    let controller = Controller()
    var statusItem: NSStatusItem!
    var status = "Ctrl+Option+V switches Vertical / Horizontal"

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        controller.onStatus = { [weak self] text in
            self?.status = text
            self?.updateIcon()
            log(text)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
        registerHotKey()

        if CommandLine.arguments.contains("--vertical") { controller.vertical() }
        else if CommandLine.arguments.contains("--horizontal") { controller.horizontal() }
    }

    func updateIcon() {
        let name = controller.isVertical ? "ipad" : "ipad.landscape"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "iPad Vertical")
    }

    // Rebuilt every time the menu opens so checkmarks and status are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(.sectionHeader(title: "Orientation"))
        menu.addItem(item("Vertical", #selector(vertical), symbol: "ipad", on: controller.isVertical))
        menu.addItem(item("Horizontal", #selector(horizontal), symbol: "ipad.landscape", on: !controller.isVertical && controller.hasSidecar))
        menu.addItem(item("Rotate 180\u{00B0}", #selector(flip), symbol: "arrow.triangle.2.circlepath"))

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Vertical Resolution"))
        for (i, r) in resolutions.enumerated() {
            let it = item(r.name, #selector(resolutionPicked(_:)), on: i == resolutionIndex)
            it.tag = i
            menu.addItem(it)
        }

        menu.addItem(.separator())
        let info = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())
        menu.addItem(item("Disconnect iPad", #selector(disconnect), symbol: "cable.connector.slash"))
        menu.addItem(item("Quit iPad Vertical", #selector(quit), key: "q"))
    }

    func item(_ title: String, _ action: Selector, symbol: String? = nil, on: Bool = false, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        i.state = on ? .on : .off
        if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return i
    }

    func registerHotKey() {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x69505644), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { AppDelegate.shared.controller.toggle() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    @objc func vertical() { controller.vertical() }
    @objc func horizontal() { controller.horizontal() }
    @objc func flip() { controller.flip() }
    @objc func resolutionPicked(_ sender: NSMenuItem) { controller.setResolution(sender.tag) }
    @objc func disconnect() { controller.disconnect() }
    @objc func quit() { controller.horizontal(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) } }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
