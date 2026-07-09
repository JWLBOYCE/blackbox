import SwiftUI
import OpenPilotLogbookCore

enum OpenPilotTheme {
    static let background = LinearGradient(
        colors: [
            Color(red: 0.050, green: 0.070, blue: 0.082),
            Color(red: 0.075, green: 0.105, blue: 0.120),
            Color(red: 0.035, green: 0.048, blue: 0.060)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let panel = Color.white.opacity(0.055)
    static let panelRaised = Color.white.opacity(0.080)
    static let border = Color.white.opacity(0.120)
    static let muted = Color.white.opacity(0.62)
    static let blue = Color(red: 0.270, green: 0.560, blue: 1.000)
    static let cyan = Color(red: 0.460, green: 0.760, blue: 1.000)
    static let green = Color(red: 0.420, green: 0.880, blue: 0.410)
    static let amber = Color(red: 1.000, green: 0.680, blue: 0.220)
    static let red = Color(red: 1.000, green: 0.330, blue: 0.230)
    static let corner: CGFloat = 8
}

struct AppBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(OpenPilotTheme.background)
            .foregroundStyle(.primary)
            .preferredColorScheme(.dark)
    }
}

extension View {
    func appBackground() -> some View { modifier(AppBackground()) }
}

struct Panel<Content: View>: View {
    var title: String?
    var systemImage: String?
    var content: Content

    init(_ title: String? = nil, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack(spacing: 8) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .foregroundStyle(OpenPilotTheme.cyan)
                    }
                    Text(title)
                        .font(.headline.weight(.semibold))
                }
            }
            content
        }
        .padding(16)
        .background(OpenPilotTheme.panel, in: RoundedRectangle(cornerRadius: OpenPilotTheme.corner))
        .overlay {
            RoundedRectangle(cornerRadius: OpenPilotTheme.corner)
                .stroke(OpenPilotTheme.border, lineWidth: 1)
        }
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color = OpenPilotTheme.cyan

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, alignment: .leading)
                Text(title.uppercased())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(OpenPilotTheme.muted)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                .minimumScaleFactor(0.72)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OpenPilotTheme.panelRaised, in: RoundedRectangle(cornerRadius: OpenPilotTheme.corner))
        .overlay {
            RoundedRectangle(cornerRadius: OpenPilotTheme.corner)
                .stroke(OpenPilotTheme.border, lineWidth: 1)
        }
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        MetricTile(title: title, value: value, systemImage: systemImage)
    }
}

struct ReadinessStrip: View {
    var isReady: Bool
    var issueCount: Int
    var action: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: isReady ? "checkmark.shield" : "exclamationmark.triangle")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(isReady ? OpenPilotTheme.green : OpenPilotTheme.amber)
            VStack(alignment: .leading, spacing: 4) {
                Text(isReady ? "CAA Ready" : "CAA Review Needed")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isReady ? OpenPilotTheme.green : OpenPilotTheme.amber)
                Text(isReady ? "Required fields are complete." : "\(issueCount) entries need attention before export.")
                    .font(.callout)
                    .foregroundStyle(OpenPilotTheme.muted)
            }
            Spacer()
            Button(action: action) {
                Label("View CAA Check", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: OpenPilotTheme.corner))
        .overlay {
            RoundedRectangle(cornerRadius: OpenPilotTheme.corner)
                .stroke(isReady ? OpenPilotTheme.green.opacity(0.35) : OpenPilotTheme.amber.opacity(0.45), lineWidth: 1)
        }
    }
}

struct ProgressLine: View {
    var title: String
    var value: String
    var progress: Double
    var tint: Color = OpenPilotTheme.green

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.callout.weight(.medium))
                Spacer()
                Text(value)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(0, min(1, progress)) * proxy.size.width)
                }
            }
            .frame(height: 7)
        }
    }
}

struct SplitRingChart: View {
    var dayMinutes: Int
    var nightMinutes: Int

    private var total: Int { max(1, dayMinutes + nightMinutes) }
    private var dayShare: Double { Double(dayMinutes) / Double(total) }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 28)
                Circle()
                    .trim(from: 0, to: dayShare)
                    .stroke(OpenPilotTheme.cyan, style: StrokeStyle(lineWidth: 28, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: dayShare, to: 1)
                    .stroke(OpenPilotTheme.blue.opacity(0.70), style: StrokeStyle(lineWidth: 28, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(LogbookFormatters.hours(dayMinutes + nightMinutes))
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    Text("Co-pilot")
                        .font(.caption)
                        .foregroundStyle(OpenPilotTheme.muted)
                }
            }
            .frame(width: 150, height: 150)

            HStack(spacing: 18) {
                ChartLegendRow(color: OpenPilotTheme.cyan, title: "Day", value: LogbookFormatters.hours(dayMinutes), percent: dayShare)
                ChartLegendRow(color: OpenPilotTheme.blue, title: "Night", value: LogbookFormatters.hours(nightMinutes), percent: 1 - dayShare)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ChartLegendRow: View {
    var color: Color
    var title: String
    var value: String
    var percent: Double

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(value)
                    .font(.callout.monospacedDigit())
                Text(percent.formatted(.percent.precision(.fractionLength(1))))
                    .font(.caption)
                    .foregroundStyle(OpenPilotTheme.muted)
            }
        }
    }
}

struct StatusGlyph: View {
    var ok: Bool

    var body: some View {
        Image(systemName: ok ? "checkmark.circle" : "exclamationmark.triangle")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(ok ? OpenPilotTheme.green : OpenPilotTheme.amber)
    }
}

struct EmptyStateBlock: View {
    var title: String
    var message: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(OpenPilotTheme.cyan)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(OpenPilotTheme.muted)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
