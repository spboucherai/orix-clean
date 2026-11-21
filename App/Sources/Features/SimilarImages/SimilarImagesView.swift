// ORIX Clean — App/Sources/Features/SimilarImages/SimilarImagesView.swift
// Description: Groups of visually similar images for manual review. Nothing is preselected.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import ORIXCleanCore
import SwiftUI

struct SimilarImagesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if model.tree == nil {
            EmptyState(symbol: "photo.on.rectangle.angled", title: L("No scan yet"), message: L("Scan a folder that contains pictures first."),
                       actionTitle: L("Scan Home Folder")) { model.startScan(path: model.home) }
        } else {
            VStack(spacing: 0) {
                HStack(spacing: ORIX.Space.m) {
                    Picker(L("Method"), selection: $model.similarMode) {
                        Text(L("Fast")).tag(SimilarImageOptions.Mode.fast)
                        Text(L("Thorough (finds crops)")).tag(SimilarImageOptions.Mode.thorough)
                    }.frame(width: 300)
                    .help(L("Fast compares image structure, then confirms with Vision. Thorough compares every pair with Vision and is limited to 3,000 images."))
                    Button(model.similar == nil ? L("Find Similar Images") : L("Search Again")) { model.findSimilar() }
                        .buttonStyle(.borderedProminent).disabled(model.similarPhase == .running).accessibilityIdentifier("similar.find")
                    Spacer()
                    if let s = model.similar {
                        Text(L("%@ images examined · %@ groups", ByteFormat.count(s.imagesExamined), ByteFormat.count(s.groups.count)))
                            .font(.callout.monospacedDigit()).foregroundStyle(ORIX.Palette.textSecondary)
                    }
                }
                .padding(.horizontal, ORIX.Space.m).padding(.vertical, ORIX.Space.s).background(.bar)
                Divider()
                if model.similarPhase == .running {
                    let p = model.similarProgress
                    ProgressLine(title: p.stage == "fingerprint" ? L("Reading images…") : L("Comparing images…"),
                                 detail: L("%@ of %@", ByteFormat.count(p.done), ByteFormat.count(p.total)),
                                 fraction: p.total > 0 ? Double(p.done) / Double(p.total) : nil) { model.cancelSimilar() }
                        .padding(ORIX.Space.m)
                }
                if let s = model.similar {
                    if s.groups.isEmpty {
                        EmptyState(symbol: "checkmark.seal", title: L("No similar images found"), message: L("%@ images were examined on this Mac.", ByteFormat.count(s.imagesExamined)))
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: ORIX.Space.l) {
                                InfoBanner(text: L("These images look alike to a local model. That is not proof they are the same picture: compare them before removing any. Nothing is selected for you."))
                                if s.mode != model.similarMode, model.similarMode == .thorough {
                                    InfoBanner(text: L("More than 3,000 images: the fast method was used instead of the thorough one."))
                                }
                                ForEach(s.groups.prefix(200)) { g in group(g) }
                            }
                            .padding(ORIX.Space.l)
                        }
                        .accessibilityIdentifier("similar.list")
                    }
                } else if model.similarPhase != .running {
                    EmptyState(symbol: "photo.on.rectangle.angled", title: L("Find near-duplicate pictures"),
                               message: L("Resized, recompressed or lightly edited copies are grouped using image fingerprints computed on this Mac with Vision. Photo libraries are not opened."),
                               actionTitle: L("Find Similar Images")) { model.findSimilar() }
                }
            }
        }
    }

    private func group(_ g: SimilarGroup) -> some View {
        Card(padding: ORIX.Space.m) {
            VStack(alignment: .leading, spacing: ORIX.Space.s) {
                HStack {
                    Text(L("%d similar images", g.images.count)).font(.headline)
                    Text(L("confidence %d%%", Int(g.confidence * 100))).font(.caption.monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 1).background(ORIX.Palette.hairline, in: Capsule())
                        .help(L("Derived from the largest measured difference between linked images. 100% would be structurally identical."))
                    Spacer()
                    Button(L("Compare in Quick Look")) { QuickLook.show(g.images.map(\.path)) }.controlSize(.small)
                }
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: ORIX.Space.m) {
                        ForEach(g.images) { img in
                            let selected = model.isSelected(img.path)
                            VStack(alignment: .leading, spacing: 4) {
                                Thumbnail(path: img.path, side: 150)
                                    .overlay(RoundedRectangle(cornerRadius: ORIX.Radius.s).strokeBorder(selected ? ORIX.Palette.review : .clear, lineWidth: 3))
                                    .onTapGesture(count: 2) { QuickLook.show([img.path]) }
                                HStack(spacing: 5) {
                                    Checkbox(isOn: selected, label: L("Select %@ for cleanup", (img.path as NSString).lastPathComponent)) { model.toggleSimilar(img, in: g) }
                                    Text((img.path as NSString).lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                                }
                                Text("\(img.pixelWidth) × \(img.pixelHeight) · \(ByteFormat.string(img.logicalSize))").font(.caption2.monospacedDigit()).foregroundStyle(ORIX.Palette.textSecondary)
                                PathText(path: img.path)
                            }
                            .frame(width: 150)
                            .contextMenu { FileMenu(path: img.path) }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }
}
