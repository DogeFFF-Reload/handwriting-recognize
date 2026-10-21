import InkCore
import SwiftUI

/// 总结笔记：离开草稿回到画廊时，底下问一句「总结内容」，点了才调 qwen3.8-max（不自动调用）。
/// 收成式子的部分按文字发，没收成式子的手写截成图发；没填百炼 Key 时按纸上的式子拼一份本地要点。
/// 结果存在草稿文件夹的 summary.json，画廊格子下面显示第一条，长按「查看要点」看全部。
@Observable
final class SummaryCenter {
    enum Phase: Equatable {
        case working
        case done
        case failed(String)
    }

    let library: BoardLibrary
    /// 正在总结、总结完、没总结成的草稿。
    private(set) var phases: [UUID: Phase] = [:]
    /// 刚离开的那份草稿：画廊底下出一条「已保存 · 总结内容」。
    var offered: UUID?
    /// 正在看要点的草稿。
    var showing: BoardMeta?

    init(library: BoardLibrary) {
        self.library = library
    }

    var hasKey: Bool { !Self.apiKey.isEmpty }

    private static var apiKey: String {
        (UserDefaults.standard.string(forKey: "dashscopeKey") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 离开草稿：纸上有东西、还没总结过（或者总结以后又改过），就问一句。
    func offer(_ id: UUID) {
        guard let meta = library.meta(id), library.summaryIsStale(meta), let digest = library.digest(id), !digest.isEmpty else {
            offered = nil
            return
        }
        phases[id] = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { offered = id }
    }

    func dismissOffer() {
        withAnimation(.easeOut(duration: 0.2)) { offered = nil }
    }

    /// 点了「总结内容」：有百炼 Key 就交给 qwen3.8-max，没有就拼本地要点。
    func summarize(_ id: UUID) {
        guard phases[id] != .working, let digest = page(id) else { return }
        let key = Self.apiKey
        guard !key.isEmpty else {
            library.saveSummary(id, NoteSummarizer.local(digest))
            phases[id] = .done
            return
        }
        phases[id] = .working
        let png = digest.hasLooseInk ? library.inkPNG(id) : nil
        Task { @MainActor [weak self] in
            do {
                let s = try await NoteSummarizer.summarize(digest, apiKey: key, inkPNG: png)
                self?.library.saveSummary(id, s)
                self?.phases[id] = .done
            } catch {
                self?.phases[id] = .failed(AppModel.describe(error))
            }
        }
    }

    /// 模型没连上时退一步：按纸上的式子拼一份本地要点。
    func useLocal(_ id: UUID) {
        guard let digest = page(id) else { return }
        library.saveSummary(id, NoteSummarizer.local(digest))
        phases[id] = .done
    }

    /// 上次存盘时纸上的东西，名字用草稿现在的名字。以前的草稿没有存过：只知道纸上有手写。
    private func page(_ id: UUID) -> NoteDigest? {
        guard let meta = library.meta(id) else { return nil }
        var d = library.digest(id) ?? NoteDigest(title: meta.title, lines: [], hasLooseInk: true)
        d.title = meta.title
        return d
    }
}

/// 画廊底下的一条：刚离开的草稿「已保存 · 总结内容」；点了以后是总结中、总结好了、没总结成。
struct SummaryBanner: View {
    var center: SummaryCenter
    var meta: BoardMeta

    var body: some View {
        HStack(spacing: 10) {
            switch center.phases[meta.id] {
            case .working?:
                ProgressView().controlSize(.small)
                Text(center.hasKey ? "qwen3.8-max 正在总结「\(meta.title)」…" : "正在整理「\(meta.title)」的要点…")
                    .font(.subheadline)
                    .lineLimit(1)
            case .done?:
                Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                Text(center.library.summaries[meta.id]?.points.first ?? "总结好了")
                    .font(.subheadline)
                    .lineLimit(1)
                BannerButton(title: "查看要点", systemImage: "list.bullet", prominent: true) { center.showing = meta }
            case .failed(let why)?:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                Text("没总结成：\(why)")
                    .font(.subheadline)
                    .lineLimit(1)
                BannerButton(title: "重试", systemImage: "arrow.clockwise", prominent: true) { center.summarize(meta.id) }
                BannerButton(title: "用本地要点", systemImage: "doc.plaintext", prominent: false) { center.useLocal(meta.id) }
            case nil:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok)
                Text("「\(meta.title)」已保存")
                    .font(.subheadline)
                    .lineLimit(1)
                BannerButton(title: "总结内容", systemImage: "sparkles", prominent: true) { center.summarize(meta.id) }
            }
            Button {
                center.dismissOffer()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("不用了")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 52)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .padding(.horizontal, 16)
        .task(id: meta.id) {
            // 没点就算了：十二秒后自己收起来（总结中、总结好了的留着）
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            if center.phases[meta.id] == nil, center.offered == meta.id { center.dismissOffer() }
        }
    }
}

private struct BannerButton: View {
    var title: String
    var systemImage: String
    var prominent: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(prominent ? Theme.accent : Theme.accent.opacity(0.12), in: Capsule())
                .foregroundStyle(prominent ? Color.white : Theme.accent)
                .fixedSize()
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }
}

/// 一份草稿的要点：标题、几条要点、是谁写的；可以重新总结，标题可以拿来当草稿名。
struct SummarySheet: View {
    var center: SummaryCenter
    var meta: BoardMeta
    @Environment(\.dismiss) private var dismiss

    private var working: Bool { center.phases[meta.id] == .working }

    var body: some View {
        NavigationStack {
            List {
                if let s = center.library.summaries[meta.id] {
                    Section {
                        ForEach(Array(s.points.enumerated()), id: \.offset) { i, point in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(i + 1)")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Theme.accent, in: Circle())
                                Text(point)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text(s.title.isEmpty ? meta.title : s.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    } footer: {
                        Text((s.isLocal ? "本地要点（按纸上的式子整理）" : s.engine) + " · " + Self.when(s.created))
                    }
                    if s.isLocal, !center.hasKey {
                        Section {
                            Text("在设置里填上百炼 Key，就能让 qwen3.8-max 连手写的字一起总结。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        Text("还没有总结过这份草稿。").foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button {
                        center.summarize(meta.id)
                    } label: {
                        Label(working ? "正在总结…" : "重新总结", systemImage: "sparkles")
                    }
                    .disabled(working)
                    if case .failed(let why)? = center.phases[meta.id] {
                        Text("没总结成：\(why)").font(.footnote).foregroundStyle(Theme.warn)
                    }
                    if let s = center.library.summaries[meta.id], !s.title.isEmpty, s.title != currentTitle {
                        Button {
                            center.library.rename(meta.id, to: s.title)
                        } label: {
                            Label("用「\(s.title)」作草稿名", systemImage: "pencil")
                        }
                    }
                }
            }
            .navigationTitle("笔记要点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { dismiss() } }
        }
    }

    private var currentTitle: String { center.library.meta(meta.id)?.title ?? meta.title }

    /// 10月21日 14:32
    static func when(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: d)
    }
}
