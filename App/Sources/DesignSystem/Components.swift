// ORIX Clean — App/Sources/DesignSystem/Components.swift
// Description: Reusable ORIX components: cards, badges, size labels, bars, empty states, file rows.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import AppKit
import ORIXCleanCore
import QuickLookThumbnailing
import SwiftUI

struct Card<Content: View>: View {
    var padding: CGFloat = ORIX.Space.l
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ORIX.Palette.surface, in: RoundedRectangle(cornerRadius: ORIX.Radius.l, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ORIX.Radius.l, style: .continuous).strokeBorder(ORIX.Palette.hairline, lineWidth: 1))
    }
}

struct SectionTitle: View {
    var title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(ORIX.Palette.textSecondary).fixedSize(horizontal: false, vertical: true) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct RiskBadge: View {
    var risk: Risk
    var body: some View {
        Label(risk.title, systemImage: risk.symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(risk.color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(risk.color.opacity(0.13), in: Capsule())
            .accessibilityLabel(risk.title)
    }
}

struct SizeText: View {
    var bytes: Int64
    var weight: Font.Weight = .medium
    var body: some View {
        Text(ByteFormat.string(bytes)).font(.body.monospacedDigit().weight(weight))
    }
}

/// Proportional bar. The value is always also given as text next to it.
struct ProportionBar: View {
    var fraction: Double
    var color: Color = ORIX.Palette.accent
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(ORIX.Palette.hairline)
                Capsule().fill(color).frame(width: max(2, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        VStack(spacing: ORIX.Space.m) {
            Image(systemName: symbol).font(.system(size: 40, weight: .light)).foregroundStyle(ORIX.Palette.accent).accessibilityHidden(true)
            Text(title).font(.title3.weight(.semibold))
            Text(message).font(.callout).foregroundStyle(ORIX.Palette.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 460)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 4)
            }
        }
        .padding(ORIX.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A banner that states a fact and offers one action. Never styled as an alarm.
struct InfoBanner: View {
    var symbol: String = "info.circle"
    var text: String
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ORIX.Space.s) {
            Image(systemName: symbol).foregroundStyle(ORIX.Palette.accentSecondary).accessibilityHidden(true)
            Text(text).font(.callout).foregroundStyle(ORIX.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: ORIX.Space.s)
            if let actionTitle, let action { Button(actionTitle, action: action).controlSize(.small) }
        }
        .padding(ORIX.Space.m)
        .background(ORIX.Palette.accentSecondary.opacity(0.08), in: RoundedRectangle(cornerRadius: ORIX.Radius.m, style: .continuous))
    }
}

struct ProgressLine: View {
    var title: String
    var detail: String
    var fraction: Double?
    var onCancel: (() -> Void)?
    var body: some View {
        HStack(spacing: ORIX.Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.medium))
                if let fraction { ProgressView(value: min(1, max(0, fraction))).progressViewStyle(.linear) }
                else { ProgressView().progressViewStyle(.linear) }
                Text(detail).font(.caption.monospacedDigit()).foregroundStyle(ORIX.Palette.textSecondary).lineLimit(1).truncationMode(.middle)
            }
            if let onCancel { Button(L("Cancel"), action: onCancel) }
        }
        .padding(ORIX.Space.m)
        .background(ORIX.Palette.surface, in: RoundedRectangle(cornerRadius: ORIX.Radius.m, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ORIX.Radius.m, style: .continuous).strokeBorder(ORIX.Palette.hairline))
    }
}

/// Finder icon of a file, loaded lazily.
struct FileIcon: View {
    var path: String
    var size: CGFloat = 20
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable().interpolation(.high).frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// Quick Look thumbnail of a file (images, documents), with the Finder icon as fallback.
struct Thumbnail: View {
    var path: String
    var side: CGFloat
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                FileIcon(path: path, size: min(side, 64))
            }
        }
        .frame(width: side, height: side)
        .background(ORIX.Palette.canvas, in: RoundedRectangle(cornerRadius: ORIX.Radius.s))
        .clipShape(RoundedRectangle(cornerRadius: ORIX.Radius.s))
        .task(id: path) {
            let request = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path), size: CGSize(width: side, height: side),
                                                       scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
            image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        }
        .accessibilityHidden(true)
    }
}

struct PathText: View {
    var path: String
    var body: some View {
        Text(((path as NSString).deletingLastPathComponent).abbreviatingHome)
            .font(.caption).foregroundStyle(ORIX.Palette.textSecondary).lineLimit(1).truncationMode(.middle)
            .help(path)
    }
}

/// Standard context menu for anything that is a file on disk.
struct FileMenu: View {
    var path: String
    var body: some View {
        Button(L("Reveal in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        Button(L("Quick Look")) { QuickLook.show([path]) }
        Button(L("Copy Path")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }
    }
}

struct Checkbox: View {
    var isOn: Bool
    var label: String
    var toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                .font(.system(size: 15)).foregroundStyle(isOn ? ORIX.Palette.accent : ORIX.Palette.textTertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? L("Selected") : L("Not selected"))
        .accessibilityAddTraits(.isToggle)
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var detail: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(ORIX.Palette.textSecondary)
            Text(value).font(.title2.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            if let detail { Text(detail).font(.caption).foregroundStyle(ORIX.Palette.textTertiary).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
