import AppKit
import SwiftUI

struct AppInfo: Equatable {
    let path: String
    let name: String
}

struct Folder: Codable, Equatable {
    var id: String
    var name: String
    var apps: [String]
}

enum Item: Codable, Equatable, Identifiable {
    case app(String)
    case folder(Folder)

    var id: String {
        switch self {
        case .app(let p): return p
        case .folder(let f): return f.id
        }
    }
}

enum AppScanner {
    static func scan() -> [AppInfo] {
        let home = NSHomeDirectory()
        let roots = ["/Applications", home + "/Applications", "/System/Applications", "/System/Cryptexes/App/System/Applications"]
        let fm = FileManager.default
        var result: [AppInfo] = []
        var names = Set<String>()
        var paths = Set<String>()

        func walk(_ dir: String, depth: Int) {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for e in entries where !e.hasPrefix(".") {
                let path = dir + "/" + e
                if e.hasSuffix(".app") {
                    let real = (path as NSString).resolvingSymlinksInPath
                    guard paths.insert(real).inserted else { continue }
                    if let info = Bundle(path: path)?.infoDictionary, (info["LSBackgroundOnly"] as? Bool) == true { continue }
                    var name = fm.displayName(atPath: path)
                    if name.hasSuffix(".app") { name.removeLast(4) }
                    guard names.insert(name).inserted else { continue }
                    result.append(AppInfo(path: path, name: name))
                } else if depth > 0 {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue { walk(path, depth: depth - 1) }
                }
            }
        }
        roots.forEach { walk($0, depth: 2) }
        return result
    }
}

enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()
    static func icon(_ path: String) -> NSImage {
        if let i = cache.object(forKey: path as NSString) { return i }
        let i = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(i, forKey: path as NSString)
        return i
    }
}

final class PagerState: ObservableObject {
    @Published var dragOffset: CGFloat = 0
}

final class DragState: ObservableObject {
    @Published var point: CGPoint = .zero
    @Published var scale: CGFloat = 1
    @Published var opacity: Double = 1
}

struct GridLayout {
    var w: CGFloat = 1280
    var gridLeft: CGFloat = 0
    var gridTop: CGFloat = 100
    var cell = CGSize(width: 150, height: 120)
    var icon: CGFloat = 80
    var cols = 7
    var rows = 5

    func slotCenter(_ k: Int) -> CGPoint {
        let col = k % cols, row = k / cols
        let contentH = icon + 6 + 16
        return CGPoint(x: gridLeft + (CGFloat(col) + 0.5) * cell.width,
                       y: gridTop + CGFloat(row) * cell.height + (cell.height - contentH) / 2 + icon / 2)
    }

    func slotIndex(_ p: CGPoint) -> Int {
        let col = min(max(Int(floor((p.x - gridLeft) / cell.width)), 0), cols - 1)
        let row = min(max(Int(floor((p.y - gridTop) / cell.height)), 0), rows - 1)
        return row * cols + col
    }
}

final class LaunchModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var query = "" {
        didSet { if query != oldValue { page = 0; pager.dragOffset = 0 } }
    }
    @Published var page = 0
    @Published var openFolderID: String?
    @Published var folderOpen = false
    @Published var mergeTarget: String?
    @Published var editMode = false
    @Published var pendingDelete: String?
    @Published var visible = false
    @Published var launching: String?
    @Published var wallpaper: NSImage?
    @Published var deleteError: String?
    @Published var focusTick = 0
    @Published var draggingID: String? {
        didSet {
            if draggingID == nil {
                mergeTarget = nil
                dragContainer = nil
                drag.opacity = 1
                drag.scale = 1
            }
        }
    }

    let pager = PagerState()
    var catalog: [String: AppInfo] = [:]
    var utilityPaths = Set<String>()
    var pageWidth: CGFloat = 1
    var pageSize = 35
    let drag = DragState()
    var layout = GridLayout()
    var folderGrid = CGRect.zero
    var folderPanel = CGRect.zero
    var folderCols = 1
    var folderAnchor = CGPoint.zero
    var dragContainer: String?
    var mousePoint: () -> CGPoint = { .zero }
    private var dragTimer: Timer?
    private var hoverKey: String?
    private var hoverSince = Date()
    private var edgeSince: Date?
    private var forceReorder = false
    var close: () -> Void = {}

    private var hasSaved = false
    private var accum: CGFloat = 0
    private var lastWheel = Date.distantPast

    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)

    private var saveURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LaunchpadClassic", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("layout.json")
    }

    init() {
        if let data = try? Data(contentsOf: saveURL), let saved = try? JSONDecoder().decode([Item].self, from: data) {
            items = saved
            hasSaved = true
        }
        apply(AppScanner.scan())
    }

    // MARK: Catalog

    func reload() {
        DispatchQueue.global(qos: .userInitiated).async {
            let r = AppScanner.scan()
            DispatchQueue.main.async { self.apply(r) }
        }
    }

    private func apply(_ scanned: [AppInfo]) {
        catalog = Dictionary(uniqueKeysWithValues: scanned.map { ($0.path, $0) })
        utilityPaths = Set(scanned.filter { $0.path.contains("/Utilities/") }.map { $0.path })
        var seen = Set<String>()
        var result: [Item] = []
        for it in items {
            switch it {
            case .app(let p):
                if catalog[p] != nil, seen.insert(p).inserted { result.append(it) }
            case .folder(var f):
                f.apps = f.apps.filter { catalog[$0] != nil && seen.insert($0).inserted }
                if !f.apps.isEmpty { result.append(.folder(f)) }
            }
        }
        let fresh = scanned.filter { !seen.contains($0.path) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if hasSaved {
            result += fresh.map { .app($0.path) }
        } else {
            result += fresh.filter { !utilityPaths.contains($0.path) }.map { .app($0.path) }
            let utils = fresh.filter { utilityPaths.contains($0.path) }.map { $0.path }
            if !utils.isEmpty { result.append(.folder(Folder(id: UUID().uuidString, name: "Утилиты", apps: utils))) }
        }
        if result != items { items = result }
        hasSaved = true
        save()
        if page >= pageCount { page = pageCount - 1 }
    }

    func save() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: saveURL, options: .atomic) }
    }

    func resetForShow() {
        query = ""
        page = 0
        pager.dragOffset = 0
        openFolderID = nil
        folderOpen = false
        editMode = false
        pendingDelete = nil
        deleteError = nil
        launching = nil
        dragTimer?.invalidate()
        dragTimer = nil
        draggingID = nil
    }

    // MARK: Queries

    var visibleItems: [Item] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return items }
        let all = catalog.values.filter { $0.name.localizedCaseInsensitiveContains(q) }
        let sorted = all.sorted { a, b in
            let ap = a.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
            let bp = b.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
            if ap != bp { return ap }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return sorted.map { .app($0.path) }
    }

    var pageCount: Int { max(1, Int(ceil(Double(visibleItems.count) / Double(pageSize)))) }

    var openFolder: Folder? {
        guard let id = openFolderID else { return nil }
        for it in items { if case .folder(let f) = it, f.id == id { return f } }
        return nil
    }

    func title(_ item: Item) -> String {
        switch item {
        case .app(let p): return catalog[p]?.name ?? ""
        case .folder(let f): return f.name
        }
    }

    func isApp(_ id: String) -> Bool { catalog[id] != nil }

    func isDeletable(_ path: String) -> Bool {
        let home = NSHomeDirectory() + "/Applications/"
        guard path.hasPrefix("/Applications/") || path.hasPrefix(home) else { return false }
        return !path.hasSuffix("/Launchpad Classic.app")
    }

    // MARK: Actions

    func activate(_ item: Item) {
        if editMode {
            if case .folder(let f) = item { openFolder(f.id) }
            return
        }
        switch item {
        case .app(let p): launch(p)
        case .folder(let f): openFolder(f.id)
        }
    }

    func setVisible(_ v: Bool) {
        withAnimation(.easeInOut(duration: 0.32)) { visible = v }
    }

    func openFolder(_ id: String) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            folderAnchor = layout.slotCenter(max(0, idx - page * pageSize))
        }
        folderOpen = false
        openFolderID = id
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { self.folderOpen = true }
        }
    }

    func closeFolder() {
        guard let id = openFolderID else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.92)) { folderOpen = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            if self.openFolderID == id && !self.folderOpen { self.openFolderID = nil }
        }
    }

    func launch(_ path: String) {
        withAnimation(.easeOut(duration: 0.3)) { launching = path }
        // даём анимации стартовать, затем открываем приложение и плавно закрываем Launchpad
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
        }
        close()
    }

    func backgroundTap() {
        if pendingDelete != nil { cancelDelete() }
        else if openFolderID != nil { closeFolder() }
        else if editMode { editMode = false }
        else { close() }
    }

    func launchFirstResult() {
        if case .app(let p)? = visibleItems.first { launch(p) }
    }

    func requestDelete(_ path: String) {
        deleteError = nil
        pendingDelete = path
    }

    func cancelDelete() {
        pendingDelete = nil
        deleteError = nil
    }

    func confirmDelete() {
        guard let path = pendingDelete else { return }
        NSWorkspace.shared.recycle([URL(fileURLWithPath: path)]) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.deleteError = "Не получилось: \(error.localizedDescription)"
                } else {
                    self.pendingDelete = nil
                    self.reload()
                }
            }
        }
    }

    func renameFolder(_ id: String, _ name: String) {
        guard let i = items.firstIndex(where: { $0.id == id }), case .folder(var f) = items[i] else { return }
        f.name = name
        items[i] = .folder(f)
        save()
    }

    func dissolve(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }), case .folder(let f) = items[i] else { return }
        items.replaceSubrange(i...i, with: f.apps.map { .app($0) })
        if openFolderID == id { openFolderID = nil }
        save()
    }

    // MARK: Moving

    private func detach(_ id: String) -> Item? {
        if let i = items.firstIndex(where: { $0.id == id }) { return items.remove(at: i) }
        for (i, it) in items.enumerated() {
            if case .folder(var f) = it, let j = f.apps.firstIndex(of: id) {
                f.apps.remove(at: j)
                items[i] = .folder(f)
                return .app(id)
            }
        }
        return nil
    }

    private func cleanup() {
        let before = items.count
        items.removeAll { if case .folder(let f) = $0 { return f.apps.isEmpty }; return false }
        if items.count != before, openFolder == nil { openFolderID = nil }
        save()
    }

    func merge(_ dragged: String, into target: String) {
        guard dragged != target, isApp(dragged), let moved = detach(dragged),
              let ti = items.firstIndex(where: { $0.id == target }) else { return }
        withAnimation(Self.spring) {
            switch items[ti] {
            case .app(let p):
                items[ti] = .folder(Folder(id: UUID().uuidString, name: "Папка", apps: [p, dragged]))
            case .folder(var f):
                f.apps.append(dragged)
                items[ti] = .folder(f)
            }
            _ = moved
            cleanup()
        }
    }

    // MARK: Paging

    func changePage(_ delta: Int) { goTo(page + delta) }

    func goTo(_ p: Int) {
        let t = min(max(p, 0), pageCount - 1)
        if t != page { withAnimation(Self.spring) { page = t } }
    }

    /// Returns true if the event was consumed.
    func handleScroll(_ e: NSEvent) -> Bool {
        guard openFolderID == nil, draggingID == nil, pageCount > 1 else { return false }
        let precise = e.hasPreciseScrollingDeltas
        if precise && (!e.phase.isEmpty || !e.momentumPhase.isEmpty) {
            if !e.momentumPhase.isEmpty { return true }
            if e.phase.contains(.ended) || e.phase.contains(.cancelled) {
                let thr = pageWidth * 0.15
                withAnimation(Self.spring) {
                    if accum < -thr { changePage(1) } else if accum > thr { changePage(-1) }
                    pager.dragOffset = 0
                }
                accum = 0
                return true
            }
            if e.phase.contains(.began) { accum = 0 }
            let dx = e.scrollingDeltaX
            if abs(dx) < abs(e.scrollingDeltaY) && accum == 0 { return false }
            accum += dx
            var off = accum
            if (page == 0 && accum > 0) || (page == pageCount - 1 && accum < 0) { off = accum * 0.25 }
            pager.dragOffset = off
            return true
        }
        let d = abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) ? e.scrollingDeltaX : e.scrollingDeltaY
        guard abs(d) > 0.1 else { return true }
        if Date().timeIntervalSince(lastWheel) > 0.3 {
            lastWheel = Date()
            changePage(d < 0 ? 1 : -1)
        }
        return true
    }

    // MARK: Перетаскивание (как на iPhone)

    var draggingItem: Item? {
        guard let id = draggingID else { return nil }
        if let it = items.first(where: { $0.id == id }) { return it }
        return catalog[id] != nil ? .app(id) : nil
    }

    func beginDrag(_ id: String, container: String?) {
        guard draggingID == nil, query.isEmpty, pendingDelete == nil else { return }
        dragContainer = container
        drag.point = mousePoint()
        drag.opacity = 1
        drag.scale = 1
        hoverKey = nil
        edgeSince = nil
        forceReorder = false
        draggingID = id
        withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) { drag.scale = 1.16 }
        dragTimer?.invalidate()
        dragTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.dragTick() }
    }

    func dragMove() {
        guard draggingID != nil else { return }
        drag.point = mousePoint()
    }

    private func dragTick() {
        guard let id = draggingID else { return }
        let p = drag.point
        if let fid = dragContainer {
            if folderPanel.insetBy(dx: -14, dy: -14).contains(p) { tickFolder(fid, id, p) } else { leaveFolder(id) }
            return
        }
        // у краёв экрана листаем страницы
        let dir = p.x < 56 ? -1 : (p.x > layout.w - 56 ? 1 : 0)
        if dir != 0 {
            if edgeSince == nil { edgeSince = Date() }
            if Date().timeIntervalSince(edgeSince!) > 0.55 {
                edgeSince = Date().addingTimeInterval(0.35)
                let before = page
                changePage(dir)
                if page != before { forceReorder = true }
            }
        } else {
            edgeSince = nil
        }

        let g = min(page * pageSize + layout.slotIndex(p), items.count - 1)
        guard g >= 0 else { return }
        let cur = items.firstIndex { $0.id == id }
        if g == cur {
            if mergeTarget != nil { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { mergeTarget = nil } }
            hoverKey = nil
            return
        }
        let target = items[g]
        let c = layout.slotCenter(g - page * pageSize)
        let inCenter = hypot(p.x - c.x, p.y - c.y) < layout.icon * 0.32
        let now = Date()
        if inCenter && isApp(id) && target.id != id {
            let key = "M" + target.id
            if hoverKey != key { hoverKey = key; hoverSince = now }
            if now.timeIntervalSince(hoverSince) > 0.4, mergeTarget != target.id {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { mergeTarget = target.id }
            }
        } else {
            if mergeTarget != nil { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { mergeTarget = nil } }
            let key = "R\(g)"
            if hoverKey != key { hoverKey = key; hoverSince = now }
            if forceReorder || now.timeIntervalSince(hoverSince) > 0.14 {
                forceReorder = false
                hoverKey = nil
                move(id, to: g)
            }
        }
    }

    private func move(_ id: String, to g: Int) {
        guard let from = items.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(Self.spring) {
            let it = items.remove(at: from)
            items.insert(it, at: min(g, items.count))
        }
    }

    private func leaveFolder(_ id: String) {
        guard let fid = dragContainer,
              let fi = items.firstIndex(where: { $0.id == fid }), case .folder(var f) = items[fi],
              let j = f.apps.firstIndex(of: id) else { dragContainer = nil; return }
        f.apps.remove(at: j)
        var new = items
        if f.apps.isEmpty { new.remove(at: fi) } else { new[fi] = .folder(f) }
        let g = min(page * pageSize + layout.slotIndex(drag.point), new.count)
        new.insert(.app(id), at: g)
        withAnimation(Self.spring) { items = new }
        dragContainer = nil
        hoverKey = nil
        closeFolder()
    }

    private func tickFolder(_ fid: String, _ id: String, _ p: CGPoint) {
        guard let fi = items.firstIndex(where: { $0.id == fid }), case .folder(var f) = items[fi],
              let cur = f.apps.firstIndex(of: id) else { return }
        let col = min(max(Int(floor((p.x - folderGrid.minX) / 140)), 0), folderCols - 1)
        let row = max(Int(floor((p.y - folderGrid.minY) / 130)), 0)
        let idx = min(max(row * folderCols + col, 0), f.apps.count - 1)
        if idx == cur { hoverKey = nil; return }
        let key = "F\(idx)"
        if hoverKey != key { hoverKey = key; hoverSince = Date() }
        if Date().timeIntervalSince(hoverSince) > 0.14 {
            hoverKey = nil
            f.apps.remove(at: cur)
            f.apps.insert(id, at: idx)
            withAnimation(Self.spring) { items[fi] = .folder(f) }
        }
    }

    func endDrag() {
        guard let id = draggingID else { return }
        dragTimer?.invalidate()
        dragTimer = nil
        edgeSince = nil
        hoverKey = nil
        var dest: CGPoint?
        var shrink = false
        if let fid = dragContainer {
            if let f = openFolder, f.id == fid, let idx = f.apps.firstIndex(of: id) {
                let col = idx % folderCols, row = idx / folderCols
                dest = CGPoint(x: folderGrid.minX + (CGFloat(col) + 0.5) * 140,
                               y: folderGrid.minY + CGFloat(row) * 130 + (130 - 100) / 2 + 39)
            }
        } else if let t = mergeTarget, let ti = items.firstIndex(where: { $0.id == t }) {
            dest = layout.slotCenter(ti - page * pageSize)
            shrink = true
            merge(id, into: t)
        } else if let idx = items.firstIndex(where: { $0.id == id }) {
            dest = layout.slotCenter(idx - page * pageSize)
        }
        mergeTarget = nil
        save()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            if let d = dest { drag.point = d }
            drag.scale = shrink ? 0.4 : 1
            if shrink { drag.opacity = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
            if self?.draggingID == id { self?.draggingID = nil }
        }
    }
}
