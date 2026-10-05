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
            let _ = model.layout = GridLayout(w: w, gridLeft: (w - cell.width * CGFloat(cols)) / 2, gridTop: 100,
                                              cell: cell, icon: metrics.icon, cols: cols, rows: rows)

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
                .blur(radius: model.folderOpen ? 7 : 0)
                .scaleEffect(model.folderOpen ? 0.96 : 1)

                if let p = model.pendingDelete, let info = model.catalog[p] {
                    DeleteDialog(model: model, path: p, name: info.name)
                        .transition(.opacity)
                }

                if let f = model.openFolder {
                    FolderOverlay(model: model, folder: f, screen: geo.size)
                }
                }
                .scaleEffect(model.visible ? 1 : (model.launching == nil ? 1.12 : 1.4))
                .opacity(model.visible ? 1 : 0)

                FloatingIcon(drag: model.drag, item: model.draggingItem, size: metrics.icon)
            }
            .coordinateSpace(name: "root")
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

struct FloatingIcon: View {
    @ObservedObject var drag: DragState
    let item: Item?
    let size: CGFloat

    var body: some View {
        if let item {
            ItemIcon(item: item, size: size)
                .scaleEffect(drag.scale)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                .opacity(drag.opacity)
                .position(drag.point)
                .allowsHitTesting(false)
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
    @GestureState private var pressed = false

    var body: some View {
        let isLaunching = model.launching == item.id
        VStack(spacing: 6) {
            // кликабельна ТОЛЬКО сама иконка
            ItemIcon(item: item, size: metrics.icon)
                .scaleEffect(model.mergeTarget == item.id ? 1.18 : (pressed ? 0.9 : 1))
                .animation(.easeOut(duration: 0.12), value: pressed)
                .contentShape(RoundedRectangle(cornerRadius: metrics.icon * 0.22, style: .continuous))
                .onTapGesture { model.activate(item) }
                .simultaneousGesture(DragGesture(minimumDistance: 0).updating($pressed) { _, s, _ in s = true })
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.8).onEnded { _ in
                    if model.draggingID == nil { model.editMode = true }
                })
                .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { _ in
                    model.beginDrag(item.id, container: containerFolder)
                })
                .contextMenu {
                    switch item {
                    case .app(let p):
                        Button("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
                        if model.isDeletable(p) { Button("Удалить…") { model.requestDelete(p) } }
                    case .folder(let f):
                        Button("Разобрать папку") { model.dissolve(f.id) }
                    }
                }
                // крестик — отдельный слой поверх иконки, со своей зоной нажатия
                .overlay(alignment: .topLeading) { deleteBadge }
            Text(model.title(item))
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                .lineLimit(1)
                .frame(maxWidth: metrics.cell.width - 12)
                .allowsHitTesting(false)
        }
        .scaleEffect(isLaunching ? 1.6 : 1)
        .opacity(isLaunching ? 0 : (model.draggingID == item.id ? 0 : ((model.openFolderID == item.id && model.folderOpen) ? 0 : 1)))
        .modifier(Jiggle(active: model.editMode, seed: Double(abs(item.id.hashValue) % 100)))
        // ячейка целиком нужна только для перетаскивания; клик мимо иконки закрывает Launchpad
        .frame(width: metrics.cell.width, height: metrics.cell.height)
        .contentShape(Rectangle())
        .onTapGesture { model.backgroundTap() }
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
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: -8, y: -8)
        }
    }
}

struct FolderOverlay: View {
    @ObservedObject var model: LaunchModel
    let folder: Folder
    let screen: CGSize

    private func report(_ f: CGRect, _ columns: Int) {
        model.folderGrid = f
        model.folderCols = columns
        model.folderPanel = CGRect(x: f.minX - 40, y: f.minY - 40 - 54, width: f.width + 80, height: f.height + 80 + 54)
    }

    var body: some View {
        let cell = CGSize(width: 140, height: 130)
        let metrics = GridMetrics(cell: cell, icon: 78)
        let columns = min(max(folder.apps.count, 1), 5)
        let rowCount = Int(ceil(Double(folder.apps.count) / Double(columns)))
        let open = model.folderOpen
        let s: CGFloat = open ? 1 : 0.16
        ZStack {
            // подложка не масштабируется — только плавно темнеет
            Color.black.opacity(open ? 0.38 : 0)
                .contentShape(Rectangle())
                .onTapGesture { model.closeFolder() }

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
                    .animation(LaunchModel.spring, value: folder.apps)
                }
                .frame(width: cell.width * CGFloat(columns), height: cell.height * CGFloat(min(rowCount, 3)))
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { report(g.frame(in: .named("root")), columns) }
                        .onChange(of: folder.apps.count) { _, _ in report(g.frame(in: .named("root")), columns) }
                })
            }
            .padding(40)
            // содержимое проявляется чуть позже стекла, при закрытии уходит вместе с ним
            .opacity(open ? 1 : 0)
            .animation(open ? .easeOut(duration: 0.26).delay(0.12) : .easeIn(duration: 0.2).delay(0.06), value: open)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 44, style: .continuous).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 44, style: .continuous).fill(Color.black.opacity(0.28))
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 44, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
            .opacity(open ? 1 : 0)
            .animation(open ? .easeOut(duration: 0.12) : .spring(response: 0.36, dampingFraction: 0.92), value: open)
            // панель вырастает из иконки папки
            .scaleEffect(s)
            .offset(x: (model.folderAnchor.x - screen.width / 2) * (1 - s),
                    y: (model.folderAnchor.y - screen.height / 2) * (1 - s))
        }
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

struct DialogButtonStyle: ButtonStyle {
    enum Kind { case cancel, destructive }
    let kind: Kind
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: kind == .destructive ? .semibold : .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(kind == .destructive
                          ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1.0, green: 0.35, blue: 0.30), Color(red: 0.88, green: 0.19, blue: 0.20)], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white.opacity(hover ? 0.2 : 0.13)))
            )
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 0.5))
            .brightness(kind == .destructive && hover ? 0.06 : 0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hover)
            .onHover { hover = $0 }
    }
}

struct DeleteDialog: View {
    @ObservedObject var model: LaunchModel
    let path: String
    let name: String

    var body: some View {
        let open = model.deleteOpen
        ZStack {
            Color.black.opacity(open ? 0.5 : 0)
                .contentShape(Rectangle())
                .onTapGesture { model.cancelDelete() }

            VStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: IconCache.icon(path))
                        .resizable()
                        .frame(width: 84, height: 84)
                        .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
                    Image(systemName: "trash.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(LinearGradient(colors: [Color(red: 1.0, green: 0.35, blue: 0.30), Color(red: 0.88, green: 0.19, blue: 0.20)], startPoint: .top, endPoint: .bottom)))
                        .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                        .offset(x: 8, y: 8)
                        .scaleEffect(open ? 1 : 0.2)
                        .animation(.spring(response: 0.4, dampingFraction: 0.55).delay(0.12), value: open)
                }
                .padding(.bottom, 18)

                Text("Удалить «\(name)»?")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.bottom, 6)
                Text(model.deleteError ?? "Приложение будет перемещено в Корзину.\nЕго можно будет вернуть оттуда.")
                    .font(.system(size: 13))
                    .foregroundStyle(model.deleteError == nil ? Color.white.opacity(0.62) : Color(red: 1.0, green: 0.45, blue: 0.4))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 22)

                HStack(spacing: 10) {
                    Button("Отмена") { model.cancelDelete() }
                        .buttonStyle(DialogButtonStyle(kind: .cancel))
                        .keyboardShortcut(.cancelAction)
                    Button("Удалить") { model.confirmDelete() }
                        .buttonStyle(DialogButtonStyle(kind: .destructive))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .frame(width: 290)
            .padding(.horizontal, 28)
            .padding(.top, 30)
            .padding(.bottom, 26)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 32, style: .continuous).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Color.black.opacity(0.34))
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.4), radius: 34, y: 14)
            .scaleEffect(open ? 1 : 0.86)
            .opacity(open ? 1 : 0)
        }
    }
}
