import SwiftUI

struct ChannelGridCard: View {
    @EnvironmentObject private var store: AppStore
    let item: Item
    let onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onPlay) {
                ArtThumb(item: item, fit: true)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.bold))
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(8)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("Play") + " " + item.displayTitle)
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(item.group).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { store.toggleFavorite(item) } label: {
                    Image(systemName: store.isFavorite(item) ? "heart.fill" : "heart")
                        .foregroundStyle(store.isFavorite(item) ? Color.ram : .secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("Favorites"))
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
