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

final class LaunchModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var query = "" {
        didSet { if query != oldValue { page = 0; pager.dragOffset = 0 } }
    }
    @Published var page = 0
    @Published var openFolderID: String?
    @Published var folderHidden = false
    @Published var mergeTarget: String?
    @Published var editMode = false
    @Published var pendingDelete: String?
    @Published var deleteError: String?
    @Published var focusTick = 0
    @Published var draggingID: String? {
        didSet {
            if draggingID == nil {
                hoverTarget = nil
                mergeTarget = nil
                cancelEdgeTimer()
                if folderHidden { folderHidden = false; openFolderID = nil }
            }
        }
    }

    let pager = PagerState()
    var catalog: [String: AppInfo] = [:]
    var utilityPaths = Set<String>()
    var pageWidth: CGFloat = 1
    var pageSize = 35
    var hoverTarget: String?
    var close: () -> Void = {}

    private var hasSaved = false
    private var accum: CGFloat = 0
    private var lastWheel = Date.distantPast
    private var edgeTimer: Timer?

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
        folderHidden = false
        editMode = false
        pendingDelete = nil
        deleteError = nil
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
            if case .folder(let f) = item { openFolderID = f.id }
            return
        }
        switch item {
        case .app(let p): launch(p)
        case .folder(let f): openFolderID = f.id
        }
    }

    func launch(_ path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
        close()
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

    /// Put `dragged` at the position of `target` in the top-level grid.
    func place(_ dragged: String, onto target: String) {
        let dIdx = items.firstIndex { $0.id == dragged }
        let tIdx0 = items.firstIndex { $0.id == target }
        guard let moved = detach(dragged), let t0 = tIdx0 else { return }
        guard let tIdx = items.firstIndex(where: { $0.id == target }) else { return }
        let at = (dIdx != nil && dIdx! < t0) ? tIdx + 1 : tIdx
        withAnimation(Self.spring) {
            items.insert(moved, at: min(at, items.count))
            cleanup()
        }
    }

    func moveInFolder(_ folderID: String, _ dragged: String, onto target: String) {
        guard let fi = items.firstIndex(where: { $0.id == folderID }), case .folder(var f) = items[fi],
              let ti = f.apps.firstIndex(of: target), let di = f.apps.firstIndex(of: dragged) else { return }
        f.apps.remove(at: di)
        f.apps.insert(dragged, at: ti)
        withAnimation(Self.spring) { items[fi] = .folder(f); save() }
    }

    func moveToEnd(ofPage p: Int) {
        guard let d = draggingID, let moved = detach(d) else { return }
        withAnimation(Self.spring) {
            items.insert(moved, at: min((p + 1) * pageSize, items.count))
            cleanup()
        }
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

    func startEdgeTimer(_ dir: Int) {
        cancelEdgeTimer()
        edgeTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            self?.changePage(dir)
        }
    }

    func cancelEdgeTimer() { edgeTimer?.invalidate(); edgeTimer = nil }

    /// Returns true if the event was consumed.
    func handleScroll(_ e: NSEvent) -> Bool {
        guard openFolderID == nil, pageCount > 1 else { return false }
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
}
