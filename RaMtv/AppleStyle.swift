import SwiftUI
import Combine

// MARK: - Rotating hero (Apple TV style)

struct FeaturedCarousel: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    let items: [Item]
    @State private var index = 0
    private let timer = Timer.publish(every: 7, on: .main, in: .common).autoconnect()

    private var height: CGFloat { sizeClass == .regular ? 620 : 500 }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    FeaturedPage(item: item).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            if items.count > 1 {
                HStack(spacing: 7) {
                    ForEach(items.indices, id: \.self) { i in
                        Capsule()
                            .fill(Color.white.opacity(i == index ? 0.95 : 0.4))
                            .frame(width: i == index ? 22 : 7, height: 7)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: index)
                .padding(.bottom, 14)
            }
        }
        .frame(height: height)
        .onReceive(timer) { _ in
            guard items.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.6)) { index = (index + 1) % items.count }
        }
    }
}

private struct FeaturedPage: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    let item: Item

    private var meta: String {
        var parts: [String] = []
        switch item.kind {
        case .live: parts.append(t("Live"))
        case .movie: parts.append(t("Movies"))
        case .series: parts.append(t("Series"))
        }
        if !item.group.isEmpty { parts.append(item.group) }
        if let y = item.year { parts.append(y) }
        return parts.joined(separator: " · ")
    }

    private var playLabel: some View {
        Label(t("Play"), systemImage: "play.fill")
            .font(.headline)
            .foregroundStyle(.black)
            .padding(.horizontal, 34)
            .padding(.vertical, 14)
            .background(.white, in: Capsule())
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            ArtThumb(item: item, fit: item.kind == .live)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            LinearGradient(colors: [.black.opacity(0.55), .clear, .clear],
                           startPoint: .top, endPoint: .center)
            LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.95)],
                           startPoint: .center, endPoint: .bottom)
            LinearGradient(colors: [.black.opacity(0.6), .clear],
                           startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 12) {
                if store.recents.contains(where: { $0.id == item.id }) {
                    Text(t("Continue Watching"))
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Text(item.displayTitle)
                    .font(.system(size: sizeClass == .regular ? 54 : 38, weight: .heavy))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text(meta).font(.title3.weight(.semibold)).lineLimit(1)
                BadgeRow(item: item)
                HStack(spacing: 14) {
                    if item.seriesId != nil {
                        NavigationLink(value: item) { playLabel }
                    } else {
                        Button { store.play(item) } label: { playLabel }
                    }
                    Button { store.toggleFavorite(item) } label: {
                        Image(systemName: store.isFavorite(item) ? "checkmark" : "plus")
                            .font(.title3.weight(.bold))
                            .frame(width: 52, height: 52)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel(t("Favorites"))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, sizeClass == .regular ? 40 : 20)
            .padding(.bottom, 44)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
        }
        .clipped()
    }
}

// MARK: - Continue Watching (wide cards with progress)

enum RemainingTime {
    static func text(seconds: Double, duration: Double) -> String? {
        let left = max(0, duration - seconds)
        guard duration > 0, left >= 60 else { return nil }
        let f = DateComponentsFormatter()
        f.allowedUnits = left >= 3600 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .abbreviated
        var cal = Calendar.current
        cal.locale = AppLanguage.selected.locale
        f.calendar = cal
        return f.string(from: left)
    }
}

struct ContinueCard: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    let item: Item

    private var width: CGFloat { sizeClass == .regular ? 330 : 250 }

    private var card: some View {
        let resume = ResumeStore.get(item.id)
        return ZStack(alignment: .bottomLeading) {
            ArtThumb(item: item, fit: item.kind == .live)
                .frame(width: width, height: width * 9 / 16)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            HStack(spacing: 8) {
                Image(systemName: "play.fill").font(.caption.weight(.bold))
                if let r = resume, r.duration > 0 {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.35))
                        Capsule().fill(Color.white).frame(width: 44 * min(1, r.seconds / r.duration))
                    }
                    .frame(width: 44, height: 4)
                    if let left = RemainingTime.text(seconds: r.seconds, duration: r.duration) {
                        Text(left).font(.caption.weight(.semibold))
                    }
                }
                Spacer(minLength: 0)
                Text(item.displayTitle).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(10)
        }
        .frame(width: width, height: width * 9 / 16)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    var body: some View {
        Group {
            if item.seriesId != nil {
                NavigationLink(value: item) { card }
            } else {
                Button { store.play(item) } label: { card }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { store.play(item) } label: { Label(t("Play"), systemImage: "play.fill") }
                .disabled(item.seriesId != nil)
            Button {
                ResumeStore.clear(item.id)
                store.removeFromRecents(item)
            } label: { Label(t("Mark as watched"), systemImage: "checkmark.circle") }
            Button(role: .destructive) { store.removeFromRecents(item) } label: {
                Label(t("Remove from Continue Watching"), systemImage: "xmark.circle")
            }
        }
    }
}

struct ContinueShelf: View {
    let items: [Item]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ShelfHeader(title: t("Continue Watching"), items: items)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(items) { ContinueCard(item: $0) }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

// MARK: - Shelf header with "see all"

struct ShelfHeader: View {
    let title: String
    let items: [Item]

    var body: some View {
        Group {
            if items.count > 6 {
                NavigationLink { SeeAllView(title: title, items: items) } label: {
                    HStack(spacing: 4) {
                        Text(title)
                        Image(systemName: "chevron.forward").font(.headline.weight(.bold)).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(title)
            }
        }
        .font(.title2.weight(.bold))
        .padding(.horizontal, 16)
    }
}

struct SeeAllView: View {
    let title: String
    let items: [Item]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 14)], spacing: 18) {
                ForEach(items) { PosterCard(item: $0, width: 130) }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
