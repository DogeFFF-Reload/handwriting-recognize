import SwiftUI

/// 草稿画廊（参考无边记）：所有手写草稿按修改时间排成一格一格的缩略图。
/// 点一下打开；长按：重命名、复制一份、删除；右上角新建、排序；可以搜索名字。
struct GalleryView: View {
    @Bindable var library: BoardLibrary
    var onOpen: (BoardMeta) -> Void

    @State private var query = ""
    @State private var sort: Sort = .recent
    @State private var renaming: BoardMeta?
    @State private var newName = ""
    @State private var deleting: BoardMeta?

    enum Sort: String, CaseIterable {
        case recent, created, name

        var title: String {
            switch self {
            case .recent: return "最近修改"
            case .created: return "建立时间"
            case .name: return "名字"
            }
        }
    }

    private var shown: [BoardMeta] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let list = q.isEmpty ? library.boards : library.boards.filter { $0.title.localizedCaseInsensitiveContains(q) }
        switch sort {
        case .recent: return list.sorted { $0.modified > $1.modified }
        case .created: return list.sorted { $0.created > $1.created }
        case .name: return list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 330), spacing: 28)], alignment: .leading, spacing: 30) {
                if query.isEmpty {
                    NewBoardTile { onOpen(library.create()) }
                }
                ForEach(shown) { meta in
                    BoardTile(meta: meta, thumbnail: library.thumbnail(meta.id), version: library.thumbnailVersion)
                        .onTapGesture { onOpen(meta) }
                        .contextMenu {
                            Button { onOpen(meta) } label: { Label("打开", systemImage: "arrow.up.forward.app") }
                            Button {
                                newName = meta.title
                                renaming = meta
                            } label: { Label("重命名", systemImage: "pencil") }
                            Button { library.duplicate(meta) } label: { Label("复制一份", systemImage: "plus.square.on.square") }
                            Divider()
                            Button(role: .destructive) { deleting = meta } label: { Label("删除", systemImage: "trash") }
                        }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("草稿")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索草稿")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("排序", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("排序")
                Button {
                    onOpen(library.create())
                } label: {
                    Label("新建草稿", systemImage: "square.and.pencil")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .buttonBorderShape(.capsule)
            }
        }
        .overlay {
            if library.boards.isEmpty {
                EmptyGallery { onOpen(library.create()) }
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .alert("重命名", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("草稿名字", text: $newName)
            Button("好") {
                if let r = renaming { library.rename(r.id, to: newName) }
                renaming = nil
            }
            Button("取消", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("删除「\(deleting?.title ?? "")」？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let d = deleting { library.delete(d) }
                deleting = nil
            }
        } message: {
            Text("笔迹、式子、图像和图形都会一起删掉，不能恢复。")
        }
    }
}

/// 一份草稿：缩略图 + 名字 + 什么时候改的。
private struct BoardTile: View {
    var meta: BoardMeta
    var thumbnail: UIImage?
    /// 缩略图换了就重画。
    var version: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Theme.paper
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipped()
                } else {
                    RuledPaper()
                    Image(systemName: "scribble")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
            .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(meta.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(Self.when(meta.modified))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .contentShape(Rectangle())
        .hoverEffect(.lift)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// 今天 14:32、昨天 09:10、10月18日、2025年3月2日。
    static func when(_ d: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        if cal.isDateInToday(d) {
            f.dateFormat = "HH:mm"
            return "今天 " + f.string(from: d)
        }
        if cal.isDateInYesterday(d) {
            f.dateFormat = "HH:mm"
            return "昨天 " + f.string(from: d)
        }
        f.dateFormat = cal.isDate(d, equalTo: Date(), toGranularity: .year) ? "M月d日" : "yyyy年M月d日"
        return f.string(from: d)
    }
}

/// 第一格：虚线框的「新建草稿」。
private struct NewBoardTile: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                    .background(Theme.accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 26, weight: .semibold))
                                .frame(width: 56, height: 56)
                                .background(Theme.accent.opacity(0.12), in: Circle())
                            Text("新建草稿").font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(Theme.accent)
                    }
                    .aspectRatio(4 / 3, contentMode: .fit)
                Text(" ").font(.headline)
                Text(" ").font(.caption)
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityLabel("新建草稿")
    }
}

/// 还一份草稿都没有。
private struct EmptyGallery: View {
    var action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.and.pencil.and.ellipsis")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("还没有草稿").font(.title2.weight(.semibold))
            Text("每份草稿是一张可以上下滚动的纸：写函数、求解、画几何都在上面。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(action: action) {
                Label("新建草稿", systemImage: "square.and.pencil").font(.headline).padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .buttonBorderShape(.capsule)
            .padding(.top, 6)
        }
        .padding(40)
    }
}

/// 没有缩略图时的横线纸。
private struct RuledPaper: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 26
            var p = Path()
            while y < size.height {
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
                y += 20
            }
            ctx.stroke(p, with: .color(Theme.rule), lineWidth: 1)
        }
    }
}
