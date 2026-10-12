import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct QuickAppearanceButton: View {
    @AppStorage("appAppearance") private var appearance = AppAppearance.dark.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            appearance = colorScheme == .dark ? AppAppearance.light.rawValue : AppAppearance.dark.rawValue
        } label: {
            Image(systemName: colorScheme == .dark ? "sun.max" : "moon")
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel(t(colorScheme == .dark ? "Day mode" : "Night mode"))
        .accessibilityIdentifier("appearance.quickToggle")
    }
}

extension View {
    func quickAppearanceToggle() -> some View {
        toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                QuickAppearanceButton()
            }
        }
    }
}
