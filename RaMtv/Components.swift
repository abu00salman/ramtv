import SwiftUI
import AVKit

struct PosterCard: View {
    @EnvironmentObject var store: AppStore
    let item: Item
    var width: CGFloat = 124

    private var height: CGFloat { item.kind == .live ? width * 0.62 : width * 1.5 }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtThumb(item: item, fit: item.kind == .live)
                .frame(width: width, height: height)
                .background(Color.white.opacity(0.08))
                .overlay(alignment: .bottom) {
                    if item.kind != .live, let f = ResumeStore.fraction(item.id) {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.black.opacity(0.5))
                                Rectangle().fill(Color.ram).frame(width: g.size.width * f)
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(item.displayTitle)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
    }

    var body: some View {
        if item.seriesId != nil {
            NavigationLink(value: item) { content }.buttonStyle(.plain)
        } else {
            Button { store.play(item) } label: { content }.buttonStyle(.plain)
        }
    }
}

struct ShelfView: View {
    let title: String
    let items: [Item]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title3.weight(.bold)).padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(items) { PosterCard(item: $0) }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

struct HeroView: View {
    @EnvironmentObject var store: AppStore
    let item: Item

    private var label: String {
        switch item.kind {
        case .live: return t("Live")
        case .movie: return t("Movies")
        case .series: return t("Series")
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color.ram.opacity(0.6), Color(white: 0.04)],
                           startPoint: .topTrailing, endPoint: .bottomLeading)
            Color.clear
                .overlay {
                    if item.kind == .live {
                        ArtThumb(item: item, fit: true)
                            .frame(width: 240, height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                            .offset(y: -30)
                    } else {
                        ArtThumb(item: item)
                    }
                }
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.92)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                Text(label).font(.caption.weight(.bold)).foregroundStyle(.secondary).textCase(.uppercase)
                Text(item.displayTitle).font(.largeTitle.weight(.heavy)).lineLimit(2)
                BadgeRow(item: item)
                HStack(spacing: 12) {
                    Button { store.play(item) } label: {
                        Label(t("Play"), systemImage: "play.fill")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .background(.white, in: Capsule())
                    }
                    Button { store.toggleFavorite(item) } label: {
                        Image(systemName: store.isFavorite(item) ? "checkmark" : "plus")
                            .font(.headline)
                            .frame(width: 46, height: 46)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .frame(height: 480)
        .clipped()
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var store: AppStore
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 56))
                .foregroundStyle(.white)
                .frame(width: 110, height: 110)
                .background(LinearGradient(colors: [Color.ram, Color(red: 0.03, green: 0.1, blue: 0.6)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            Text(t("Welcome to RaM tv")).font(.title.bold())
            Text(t("Add your own M3U playlist or server login to start watching. RaM tv is a player only and includes no channels or content."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button { showAdd = true } label: {
                Text(t("Add Source")).font(.headline).frame(maxWidth: 260).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            Button(t("Try Demo")) { store.addDemo() }
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 640)
        .sheet(isPresented: $showAdd) { AddSourceView() }
    }
}
