import AppKit
import Carbon.HIToolbox
import SwiftUI

struct CompositionSceneRequest {
    let compositionID: UUID

    static let primary = CompositionSceneRequest(
        compositionID: SessionPersistence.primaryCompositionID
    )
}

enum CompositionTabCloseAction: Equatable {
    case closeTab
    case replaceWithBlankTab

    static func resolve(tabCount: Int) -> Self {
        tabCount <= 1 ? .replaceWithBlankTab : .closeTab
    }
}

@MainActor
final class CompositionWindowCloseInterceptor: NSObject {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func install(on button: NSButton?) {
        button?.target = self
        button?.action = #selector(handleClose(_:))
    }

    @objc func handleClose(_ sender: Any?) {
        onClose()
    }
}

@MainActor
final class CompositionTab: Identifiable {
    let id: UUID
    let title: String
    let store: ProjectStore

    init(id: UUID, title: String, store: ProjectStore) {
        self.id = id
        self.title = title
        self.store = store
    }
}

@MainActor
final class CompositionWindowController: ObservableObject {
    @Published private(set) var tabs: [CompositionTab]
    @Published private(set) var activeTabID: UUID

    let request: CompositionSceneRequest
    private unowned let workspace: CompositionWorkspace

    init(
        request: CompositionSceneRequest,
        workspace: CompositionWorkspace
    ) {
        self.request = request
        self.workspace = workspace
        UserDefaults.standard.removeObject(
            forKey: Self.tabsDefaultsKey(for: request.compositionID)
        )
        UserDefaults.standard.removeObject(
            forKey: Self.activeTabDefaultsKey(for: request.compositionID)
        )
        let initialTab = workspace.makeTab(
            compositionID: request.compositionID,
            startEmpty: true
        )
        self.tabs = [initialTab]
        self.activeTabID = initialTab.id
    }

    var activeTab: CompositionTab {
        tabs.first(where: { $0.id == activeTabID }) ?? tabs[0]
    }

    func addTab() {
        let tab = workspace.makeTab(compositionID: UUID())
        tabs.append(tab)
        select(tab.id)
    }

    func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        persistTabState()
        workspace.activate(controller: self)
    }

    func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else {
            return
        }
        switch CompositionTabCloseAction.resolve(tabCount: tabs.count) {
        case .replaceWithBlankTab:
            replaceLastTab()
            return
        case .closeTab:
            break
        }

        let removed = tabs.remove(at: index)
        removed.store.monitor.stop()
        if activeTabID == id {
            let replacementIndex = min(index, tabs.count - 1)
            activeTabID = tabs[replacementIndex].id
        }
        persistTabState()
        workspace.activate(controller: self)
    }

    func closeActiveTab() {
        close(activeTabID)
    }

    private func replaceLastTab() {
        let removed = tabs.removeLast()
        removed.store.monitor.stop()
        let replacement = workspace.makeTab(compositionID: UUID())
        tabs = [replacement]
        activeTabID = replacement.id
        persistTabState()
        workspace.activate(controller: self)
    }

    private func persistTabState() {
        UserDefaults.standard.set(
            tabs.map { $0.id.uuidString },
            forKey: Self.tabsDefaultsKey(for: request.compositionID)
        )
        UserDefaults.standard.set(
            activeTabID.uuidString,
            forKey: Self.activeTabDefaultsKey(for: request.compositionID)
        )
    }

    private static func tabsDefaultsKey(for windowID: UUID) -> String {
        "abasComposicao.\(windowID.uuidString)"
    }

    private static func activeTabDefaultsKey(for windowID: UUID) -> String {
        "abaAtivaComposicao.\(windowID.uuidString)"
    }
}

@MainActor
final class CompositionWorkspace: ObservableObject {
    @Published private(set) var activeStore: ProjectStore?

    private final class WindowRecord {
        weak var window: NSWindow?
        let controller: CompositionWindowController
        let closeInterceptor: CompositionWindowCloseInterceptor

        init(
            window: NSWindow,
            controller: CompositionWindowController,
            closeInterceptor: CompositionWindowCloseInterceptor
        ) {
            self.window = window
            self.controller = controller
            self.closeInterceptor = closeInterceptor
        }
    }

    private weak var videoStore: VideoRecorderStore?
    private weak var activeController: CompositionWindowController?
    private var records: [ObjectIdentifier: WindowRecord] = [:]
    private var nextSequence = 1
    private var observers: [NSObjectProtocol] = []
    private var isGlobalHotKeyRegistered = false
    private lazy var newWindowHotKey = GlobalHotKeyController(
        id: 3,
        keyCode: UInt32(kVK_F13),
        modifiers: GlobalHotKeyController.commandModifiers
    ) { [weak self] in
        self?.requestNewTabFromGlobalShortcut()
    }

    init(videoStore: VideoRecorderStore) {
        self.videoStore = videoStore
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let window = notification.object as? NSWindow else {
                    return
                }
                MainActor.assumeIsolated {
                    self?.activate(window: window)
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let window = notification.object as? NSWindow else {
                    return
                }
                MainActor.assumeIsolated {
                    self?.remove(window: window)
                }
            }
        )
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func makeStore(
        compositionID: UUID,
        startEmpty: Bool = false
    ) -> ProjectStore {
        ProjectStore(
            persistence: .live(compositionID: compositionID),
            restoreMonitorPreference: false,
            startEmpty: startEmpty
        )
    }

    func makeTab(
        compositionID: UUID,
        startEmpty: Bool = false
    ) -> CompositionTab {
        let tab = CompositionTab(
            id: compositionID,
            title: "Montagem \(nextSequence)",
            store: makeStore(
                compositionID: compositionID,
                startEmpty: startEmpty
            )
        )
        nextSequence += 1
        return tab
    }

    func register(
        window: NSWindow,
        controller: CompositionWindowController
    ) {
        let key = ObjectIdentifier(window)
        if let record = records[key] {
            record.closeInterceptor.install(
                on: window.standardWindowButton(.closeButton)
            )
            if window.isVisible && window.isKeyWindow {
                activate(controller: controller)
            }
            return
        }
        let closeInterceptor = CompositionWindowCloseInterceptor {
            [weak controller] in
            guard let controller else { return }
            controller.close(controller.activeTabID)
        }
        closeInterceptor.install(
            on: window.standardWindowButton(.closeButton)
        )
        records[key] = WindowRecord(
            window: window,
            controller: controller,
            closeInterceptor: closeInterceptor
        )
        window.identifier = NSUserInterfaceItemIdentifier(
            "io.skjaldr.composer.\(controller.request.compositionID.uuidString)"
        )
        window.tabbingMode = .disallowed
        window.title = "Skjaldr"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        activate(controller: controller)
        startGlobalHotKeyMonitoring()
    }

    func addTabToActiveWindow() {
        activeController?.addTab()
    }

    func activate(controller: CompositionWindowController) {
        activeController = controller
        let store = controller.activeTab.store
        if activeStore !== store {
            activeStore?.monitor.stop()
            activeStore = store
        }
        resumePreferredMonitoring(on: store)
    }

    func startGlobalHotKeyMonitoring() {
        guard !isGlobalHotKeyRegistered else { return }
        isGlobalHotKeyRegistered = newWindowHotKey.register()
        if !isGlobalHotKeyRegistered {
            activeStore?.toastMessage =
                "⌘F13 indisponível; use Arquivo > Nova aba"
        }
    }

    func suspendForVideoRecording() {
        for record in records.values {
            for tab in record.controller.tabs {
                tab.store.suspendForVideoRecording()
            }
        }
    }

    func resumeAfterVideoRecording() {
        for record in records.values {
            for tab in record.controller.tabs {
                tab.store.resumeAfterVideoRecording()
            }
        }
        if let activeStore {
            resumePreferredMonitoring(on: activeStore)
        }
    }

    func showExistingTabOrRequestNew() {
        if let window = records.values.compactMap(\.window).first {
            NSApp.unhide(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            requestNewTabFromGlobalShortcut()
        }
    }

    private func requestNewTabFromGlobalShortcut() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        guard let item = findMenuItem(
            titled: "Nova aba de composição",
            in: NSApp.mainMenu
        ), let action = item.action
        else {
            return
        }
        NSApp.sendAction(action, to: item.target, from: item)
    }

    private func findMenuItem(titled title: String, in menu: NSMenu?) -> NSMenuItem? {
        guard let menu else { return nil }
        for item in menu.items {
            if item.title == title {
                return item
            }
            if let match = findMenuItem(titled: title, in: item.submenu) {
                return match
            }
        }
        return nil
    }

    private func activate(window: NSWindow) {
        guard let record = records[ObjectIdentifier(window)] else { return }
        activate(controller: record.controller)
    }

    private func resumePreferredMonitoring(on store: ProjectStore) {
        guard videoStore?.phase == .idle,
              UserDefaults.standard.bool(forKey: "monitoramentoAtivo"),
              !store.monitor.isRunning,
              let path = UserDefaults.standard.string(forKey: "pastaMonitorada")
        else {
            return
        }
        store.startMonitoring(URL(fileURLWithPath: path))
    }

    private func remove(window: NSWindow) {
        let key = ObjectIdentifier(window)
        guard let removed = records.removeValue(forKey: key) else { return }
        for tab in removed.controller.tabs {
            tab.store.monitor.stop()
        }
        guard activeController === removed.controller else { return }
        activeController = nil
        activeStore = nil
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let keyWindow = NSApp.keyWindow,
                  let record = self.records[ObjectIdentifier(keyWindow)]
            else {
                return
            }
            self.activate(controller: record.controller)
        }
    }
}

struct CompositionWindowRoot: View {
    let request: CompositionSceneRequest
    @ObservedObject var workspace: CompositionWorkspace
    @ObservedObject var videoStore: VideoRecorderStore
    @ObservedObject var uploadStore: VideoUploadStore
    @StateObject private var controller: CompositionWindowController

    init(
        request: CompositionSceneRequest,
        workspace: CompositionWorkspace,
        videoStore: VideoRecorderStore,
        uploadStore: VideoUploadStore
    ) {
        self.request = request
        self.workspace = workspace
        self.videoStore = videoStore
        self.uploadStore = uploadStore
        _controller = StateObject(
            wrappedValue: CompositionWindowController(
                request: request,
                workspace: workspace
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            CompositionTabBar(controller: controller)
            CompositionTabContent(
                tab: controller.activeTab,
                windowID: request.compositionID,
                controller: controller
            )
            .id(controller.activeTabID)
        }
        .environmentObject(workspace)
        .environmentObject(videoStore)
        .environmentObject(uploadStore)
        .background {
            WindowAccessor { window in
                workspace.register(window: window, controller: controller)
            }
        }
    }
}

private struct CompositionTabContent: View {
    let tab: CompositionTab
    let windowID: UUID
    @ObservedObject var controller: CompositionWindowController

    var body: some View {
        ContentView(windowID: windowID)
            .environmentObject(tab.store)
            .environmentObject(controller)
    }
}

private struct CompositionTabBar: View {
    @ObservedObject var controller: CompositionWindowController

    var body: some View {
        HStack(spacing: 5) {
            ForEach(controller.tabs) { tab in
                HStack(spacing: 5) {
                    Button(tab.title) {
                        controller.select(tab.id)
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(
                        tab.id == controller.activeTabID
                            ? .semibold
                            : .regular
                    ))

                    Button {
                        controller.close(tab.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("Fechar aba")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    tab.id == controller.activeTabID
                        ? Color(nsColor: .windowBackgroundColor)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7)
                )
            }

            Button {
                controller.addTab()
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .help("Nova aba de composição")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
    }
}
