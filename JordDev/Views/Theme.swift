// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The look of the app: colours, pastels with a meaning, card and list styling, button
// styles and the empty states.

import SwiftUI

enum Theme {
    static let paper = Color.white
    static let ink = Color(hex: 0x121217)
    static let quiet = Color(hex: 0x54565F)
    static let hairline = ink.opacity(0.12)
    static let cardRadius: CGFloat = 16
}

struct Pastel {
    let fill: Color
    let ink: Color

    static let rose = Pastel(fill: Color(hex: 0xFFE1E4), ink: Color(hex: 0x8F1D2C))
    static let lavender = Pastel(fill: Color(hex: 0xEAE4FF), ink: Color(hex: 0x4B2F9E))
    static let mint = Pastel(fill: Color(hex: 0xDCF3E4), ink: Color(hex: 0x1B6B3A))
    static let sky = Pastel(fill: Color(hex: 0xDDEEFF), ink: Color(hex: 0x1F5A99))
    static let peach = Pastel(fill: Color(hex: 0xFFE8D6), ink: Color(hex: 0x8A4A12))
    static let sand = Pastel(fill: Color(hex: 0xF3EDDD), ink: Color(hex: 0x6B5A1E))
    static let coral = Pastel(fill: Color(hex: 0xFFDFD6), ink: Color(hex: 0xA3301A))

    static let onTime = mint
    static let delayed = coral
}

extension TransitCategory {
    var pastel: Pastel {
        switch self {
        case .longDistance: .rose
        case .regional: .lavender
        case .suburban: .mint
        case .metro: .sky
        case .bus: .peach
        case .other: .sand
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Building blocks

private struct Card: ViewModifier {
    var isSelected: Bool
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        content
            .background(Theme.paper, in: shape)
            .overlay {
                shape.strokeBorder(
                    isSelected ? Theme.ink : Theme.hairline,
                    lineWidth: isSelected ? 1.5 : 1 / displayScale)
            }
            .contentShape(shape)
    }
}

extension View {
    func card(isSelected: Bool = false) -> some View {
        modifier(Card(isSelected: isSelected))
    }

    func paperList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
    }

    func paperRow() -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}

struct Hairline: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1 / displayScale)
            .padding(.leading, 16)
    }
}

struct InkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.paper)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.ink.opacity(isEnabled && !configuration.isPressed ? 1 : 0.8), in: .capsule)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.displayScale) private var displayScale

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.paper, in: .capsule)
            .overlay { Capsule().strokeBorder(Theme.hairline, lineWidth: 1 / displayScale) }
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct EmptyState: View {
    let title: LocalizedStringKey
    let systemImage: String
    var message: LocalizedStringKey?
    var pastel = Pastel.sand

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(pastel.ink)
                .frame(width: 64, height: 64)
                .background(pastel.fill, in: .circle)
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.quiet)
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct LogoEmptyState: View {
    let title: LocalizedStringKey
    var message: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 12) {
            Image(.logo)
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.quiet)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
        .accessibilityElement(children: .combine)
    }
}
