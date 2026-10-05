import SwiftUI
import UniformTypeIdentifiers

struct GridMetrics {
    var cell: CGSize
    var icon: CGFloat
}

private let cols = 7
private let rows = 5

struct RootView: View {
    @ObservedObject var model: LaunchModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let gridW = w * 0.86
            let gridH = max(300, h - 40 - 36 - 24 - 60)
            let cell = CGSize(width: gridW / CGFloat(cols), height: gridH / CGFloat(rows))
            let metrics = GridMetrics(cell: cell, icon: min(cell.width * 0.62, cell.height - 40, 150))

            ZStack {
                background(size: geo.size)
                    .opacity(model.visible ? 1 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { model.backgroundTap() }

                Group {
                VStack(spacing: 0) {
                    searchBar.padding(.top, 40).padding(.bottom, 24)
                    pager(w: w, gridH: gridH, metrics: metrics)
                    dots.frame(height: 60)
                }

                if model.draggingID != nil && (model.openFolderID == nil || model.folderHidden) {
                    HStack {
                        Color.clear.frame(width: 60).contentShape(Rectangle())
                            .onDrop(of: [.plainText], delegate: EdgeDrop(model: model, dir: -1))
                        Spacer()
                        Color.clear.frame(width: 60).contentShape(Rectangle())
                            .onDrop(of: [.plainText], delegate: EdgeDrop(model: model, dir: 1))
                    }
                }

                if let p = model.pendingDelete, let info = model.catalog[p] {
                    DeleteDialog(model: model, path: p, name: info.name)
                        .transition(.opacity)
                }

                if let f = model.openFolder {
                    FolderOverlay(model: model, folder: f)
                        .opacity(model.folderHidden ? 0 : 1)
                        .allowsHitTesting(!model.folderHidden)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
                }
                .scaleEffect(model.visible ? 1 : 1.12)
                .opacity(model.visible ? 1 : 0)
            }
            .animation(.easeOut(duration: 0.2), value: model.openFolderID)
            .animation(.easeOut(duration: 0.28), value: model.visible)
            .onAppear { model.pageWidth = w; model.pageSize = cols * rows; searchFocused = true }
            .onChange(of: w) { _, v in model.pageWidth = v }
            .onChange(of: model.focusTick) { _, _ in searchFocused = true }
            .onChange(of: model.openFolderID) { _, v in searchFocused = (v == nil) }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private func background(size: CGSize) -> some View {
        ZStack {
            if let img = model.wallpaper {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .scaleEffect(1.05)
                    .blur(radius: 16)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
            Color.black.opacity(model.wallpaper == nil ? 0.3 : 0.2)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.6))
            TextField("", text: $model.query, prompt: Text("Поиск").foregroundStyle(.white.opacity(0.5)))
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .focused($searchFocused)
                .onSubmit { model.launchFirstResult() }
            if !model.query.isEmpty {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5))
                    .onTapGesture { model.query = "" }
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 260, height: 36)
        .background(Capsule().fill(.white.opacity(0.14)))
        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.5))
    }

    private func pager(w: CGFloat, gridH: CGFloat, metrics: GridMetrics) -> some View {
        let items = model.visibleItems
        let size = model.pageSize
        let pages: [[Item]] = stride(from: 0, to: max(items.count, 1), by: size).map {
            Array(items[$0..<min($0 + size, items.count)])
        }
        let content = HStack(spacing: 0) {
            ForEach(pages.indices, id: \.self) { i in
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(metrics.cell.width), spacing: 0), count: cols), spacing: 0) {
                    ForEach(pages[i]) { item in
                        TileView(model: model, item: item, metrics: metrics)
                    }
                }
                .animation(LaunchModel.spring, value: model.items)
                .frame(width: w, height: gridH, alignment: .top)
            }
        }
        .frame(width: w, alignment: .leading)

        return OffsetContainer(pager: model.pager, page: model.page, width: w, content: content)
            .frame(width: w, height: gridH, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { model.backgroundTap() }
            .onDrop(of: [.plainText], delegate: PageDrop(model: model))
    }

    private var dots: some View {
        HStack(spacing: 6) {
            if model.pageCount > 1 {
                ForEach(0..<model.pageCount, id: \.self) { i in
                    Circle()
                        .fill(.white.opacity(i == model.page ? 0.95 : 0.3))
                        .frame(width: 8, height: 8)
                        .padding(4)
                        .contentShape(Rectangle())
                        .onTapGesture { model.goTo(i) }
                }
            }
        }
    }
}

struct OffsetContainer<Content: View>: View {
    @ObservedObject var pager: PagerState
    let page: Int
    let width: CGFloat
    let content: Content

    var body: some View {
        content.offset(x: -CGFloat(page) * width + pager.dragOffset)
    }
}

struct ItemIcon: View {
    let item: Item
    let size: CGFloat

    var body: some View {
        switch item {
        case .app(let p):
            Image(nsImage: IconCache.icon(p)).resizable().interpolation(.high).frame(width: size, height: size)
        case .folder(let f):
            FolderIcon(paths: Array(f.apps.prefix(9)), size: size)
        }
    }
}

struct FolderIcon: View {
    let paths: [String]
    let size: CGFloat

    var body: some View {
        let mini = size * 0.24
        let gap = size * 0.04
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous).fill(.white.opacity(0.26))
            VStack(spacing: gap) {
                ForEach(0..<3, id: \.self) { r in
                    HStack(spacing: gap) {
                        ForEach(0..<3, id: \.self) { c in
                            let i = r * 3 + c
                            if i < paths.count {
                                Image(nsImage: IconCache.icon(paths[i])).resizable().interpolation(.high).frame(width: mini, height: mini)
                            } else {
                                Color.clear.frame(width: mini, height: mini)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}

struct TileView: View {
    @ObservedObject var model: LaunchModel
    let item: Item
    let metrics: GridMetrics
    var containerFolder: String? = nil

    var body: some View {
        let isLaunching = model.launching == item.id
        VStack(spacing: 6) {
            ItemIcon(item: item, size: metrics.icon)
                .scaleEffect(model.mergeTarget == item.id ? 1.18 : 1)
                .overlay(alignment: .topLeading) { deleteBadge }
            Text(model.title(item))
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                .lineLimit(1)
                .frame(maxWidth: metrics.cell.width - 12)
        }
        .scaleEffect(isLaunching ? 1.4 : 1)
        .opacity(isLaunching ? 0 : (model.draggingID == item.id ? 0.35 : 1))
        .modifier(Jiggle(active: model.editMode, seed: Double(abs(item.id.hashValue) % 100)))
        .contentShape(Rectangle())
        .onTapGesture { model.activate(item) }
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.8).onEnded { _ in
            if model.draggingID == nil { model.editMode = true }
        })
        .onDrag {
            model.draggingID = item.id
            return NSItemProvider(object: item.id as NSString)
        } preview: {
            ItemIcon(item: item, size: metrics.icon)
        }
        .contextMenu {
            switch item {
            case .app(let p):
                Button("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
                if model.isDeletable(p) { Button("Удалить…") { model.requestDelete(p) } }
            case .folder(let f):
                Button("Разобрать папку") { model.dissolve(f.id) }
            }
        }
        // ячейка целиком нужна только для перетаскивания; клик по пустому месту закрывает Launchpad
        .frame(width: metrics.cell.width, height: metrics.cell.height)
        .contentShape(Rectangle())
        .onTapGesture { model.backgroundTap() }
        .onDrop(of: [.plainText], delegate: TileDrop(model: model, target: item.id, metrics: metrics, folder: containerFolder))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.mergeTarget)
    }

    @ViewBuilder private var deleteBadge: some View {
        if model.editMode, case .app(let p) = item, model.isDeletable(p) {
            Button { model.requestDelete(p) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color(white: 0.25)))
                    .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .offset(x: -8, y: -8)
        }
    }
}

struct FolderOverlay: View {
    @ObservedObject var model: LaunchModel
    let folder: Folder

    var body: some View {
        let cell = CGSize(width: 140, height: 130)
        let metrics = GridMetrics(cell: cell, icon: 78)
        let columns = min(max(folder.apps.count, 1), 5)
        let rowCount = Int(ceil(Double(folder.apps.count) / Double(columns)))
        ZStack {
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture { model.openFolderID = nil }
                .onDrop(of: [.plainText], delegate: BackdropDrop(model: model))

            VStack(spacing: 18) {
                TextField("", text: Binding(get: { folder.name }, set: { model.renameFolder(folder.id, $0) }))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white)
                    .frame(width: 320)
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell.width), spacing: 0), count: columns), spacing: 0) {
                        ForEach(folder.apps, id: \.self) { p in
                            TileView(model: model, item: .app(p), metrics: metrics, containerFolder: folder.id)
                        }
                    }
                }
                .frame(width: cell.width * CGFloat(columns), height: cell.height * CGFloat(min(rowCount, 3)))
            }
            .padding(40)
            .background(RoundedRectangle(cornerRadius: 44, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 44, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 0.5))
        }
    }
}

// MARK: Drop delegates

struct TileDrop: DropDelegate {
    let model: LaunchModel
    let target: String
    let metrics: GridMetrics
    let folder: String?

    func validateDrop(info: DropInfo) -> Bool { model.draggingID != nil && model.query.isEmpty }

    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if model.mergeTarget == target { model.mergeTarget = nil }
        if model.hoverTarget == target { model.hoverTarget = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        if let d = model.draggingID, model.mergeTarget == target { model.merge(d, into: target) }
        model.mergeTarget = nil
        model.draggingID = nil
        return true
    }

    private func update(_ info: DropInfo) {
        guard let d = model.draggingID, d != target else { return }
        let p = info.location
        let contentH = metrics.icon + 6 + 16
        let iconCenterY = (metrics.cell.height - contentH) / 2 + metrics.icon / 2
        let inCenter = abs(p.x - metrics.cell.width / 2) < metrics.icon * 0.3 && abs(p.y - iconCenterY) < metrics.icon * 0.32

        if inCenter && folder == nil && model.isApp(d) {
            if model.mergeTarget != target { model.mergeTarget = target }
            return
        }
        if model.mergeTarget != nil { model.mergeTarget = nil }
        guard model.hoverTarget != target else { return }
        model.hoverTarget = target
        let m = model, t = target, f = folder
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard m.hoverTarget == t, m.mergeTarget == nil, let dragged = m.draggingID else { return }
            m.hoverTarget = nil
            if let f { m.moveInFolder(f, dragged, onto: t) } else { m.place(dragged, onto: t) }
        }
    }
}

struct PageDrop: DropDelegate {
    let model: LaunchModel
    func validateDrop(info: DropInfo) -> Bool { model.draggingID != nil && model.query.isEmpty }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        model.moveToEnd(ofPage: model.page)
        model.draggingID = nil
        return true
    }
}

struct EdgeDrop: DropDelegate {
    let model: LaunchModel
    let dir: Int
    func validateDrop(info: DropInfo) -> Bool { true }
    func dropEntered(info: DropInfo) { model.startEdgeTimer(dir) }
    func dropExited(info: DropInfo) { model.cancelEdgeTimer() }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        model.cancelEdgeTimer()
        model.draggingID = nil
        return true
    }
}

struct BackdropDrop: DropDelegate {
    let model: LaunchModel
    func validateDrop(info: DropInfo) -> Bool { true }
    func dropEntered(info: DropInfo) { if model.draggingID != nil { model.folderHidden = true } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        model.draggingID = nil
        return true
    }
}


struct Jiggle: ViewModifier {
    let active: Bool
    let seed: Double

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !active)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            content.rotationEffect(.degrees(active ? sin(t * 28 + seed) * 1.8 : 0))
        }
    }
}

struct DeleteDialog: View {
    @ObservedObject var model: LaunchModel
    let path: String
    let name: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture { model.cancelDelete() }
            VStack(spacing: 14) {
                Image(nsImage: IconCache.icon(path)).resizable().frame(width: 64, height: 64)
                Text("Удалить «\(name)»?").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                Text(model.deleteError ?? "Приложение будет перемещено в Корзину.")
                    .font(.system(size: 13))
                    .foregroundStyle(model.deleteError == nil ? .white.opacity(0.7) : Color.red)
                    .multilineTextAlignment(.center)
                    .frame(width: 280)
                HStack(spacing: 12) {
                    Button("Отмена") { model.cancelDelete() }
                        .keyboardShortcut(.cancelAction)
                    Button("Удалить") { model.confirmDelete() }
                        .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThickMaterial))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 0.5))
        }
    }
}
