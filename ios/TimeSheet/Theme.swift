import SwiftUI

/// Same look as the web app.
enum Theme {
    static let bg = Color(hex: "#F4F5F8")
    static let card = Color.white
    static let ink = Color(hex: "#1C1C1E")
    static let muted = Color(hex: "#8E8E93")
    static let border = Color(hex: "#E7E8EC")
    static let line = Color(hex: "#EFF0F3")
    static let track = Color(hex: "#EEF0F3")
    static let danger = Color(hex: "#E5484D")
    static let go = Color(hex: "#2F9E6B")
    static let idleDigits = Color(hex: "#CDCFD5")
}

extension View {
    func card(radius: CGFloat = 26) -> some View {
        background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 12, y: 4)
    }

    /// White rounded input field
    func fieldStyle() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border))
    }
}

/// Big rounded button
struct PillButtonStyle: ButtonStyle {
    var fill: Color
    var ink: Color = .white
    var outlined = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 12)
            .background(fill, in: Capsule())
            .overlay(Capsule().stroke(outlined ? Theme.border : Color.clear))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// Small "+ New" style button
struct SmallPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().stroke(Theme.border))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

/// Colored dot in a soft circle, like the web app's badges
struct ProjectDot: View {
    let hex: String
    var size: CGFloat = 40

    var body: some View {
        Circle()
            .fill(Color(hex: hex).opacity(0.22))
            .frame(width: size, height: size)
            .overlay(Circle().fill(Color(hex: hex)).frame(width: size * 0.3, height: size * 0.3))
    }
}

/// Lays out chips left to right, wrapping onto new lines
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            let w = min(s.width, maxWidth)
            if x > 0 && x + w > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += w + spacing
            rowHeight = max(rowHeight, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            let w = min(s.width, bounds.width)
            if x > bounds.minX && x + w > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: w, height: s.height))
            x += w + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

struct ProjectChip: View {
    let project: Project
    let selected: Bool

    var body: some View {
        let color = Color(hex: project.color)
        let ink = selected ? Color.ink(on: project.color) : Theme.ink
        HStack(spacing: 8) {
            Circle()
                .fill(selected ? ink.opacity(0.32) : color.opacity(0.22))
                .frame(width: 24, height: 24)
                .overlay(Circle().fill(selected ? ink : color).frame(width: 8, height: 8))
            Text(project.name).lineLimit(1)
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(ink)
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(height: 40)
        .background(selected ? color : Theme.card, in: Capsule())
        .overlay(Capsule().stroke(selected ? color : Theme.border))
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(title).font(.system(size: 19, weight: .semibold))
            Spacer()
            trailing()
        }
        .padding(.horizontal, 4)
    }
}
