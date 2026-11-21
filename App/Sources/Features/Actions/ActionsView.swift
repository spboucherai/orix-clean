// ORIX Clean — App/Sources/Features/Actions/ActionsView.swift
// Description: ORIX Clean Actions: run, create and save cleanup workflows. Removal always passes through the preview.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import ORIXCleanCore
import SwiftUI

struct ActionsView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Workflow?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ORIX.Space.l) {
                HStack(alignment: .top) {
                    SectionTitle(title: L("ORIX Clean Actions"), subtitle: L("Reusable sequences of real operations. A step that removes files can only follow a review step, and the review always shows you the exact list."))
                    Spacer()
                    Button(L("New Action…")) { editing = Workflow(name: L("My action"), steps: [.collectCaches, .review, .moveToTrash, .report]) }
                        .accessibilityIdentifier("actions.new")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: ORIX.Space.l)], alignment: .leading, spacing: ORIX.Space.l) {
                    ForEach(model.workflows) { w in card(w) }
                }
                if !model.workflowEvents.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionTitle(title: L("Last run"), subtitle: nil)
                            ForEach(model.workflowEvents) { e in
                                HStack(alignment: .firstTextBaseline) {
                                    Text("\(e.step + 1)").font(.caption.monospacedDigit()).foregroundStyle(ORIX.Palette.textTertiary).frame(width: 18, alignment: .trailing)
                                    Text(e.message).font(.callout)
                                    Spacer()
                                    Text(e.date.formatted(date: .omitted, time: .standard)).font(.caption.monospacedDigit()).foregroundStyle(ORIX.Palette.textTertiary)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("actions.log")
                }
            }
            .padding(ORIX.Space.xl)
            .frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .sheet(item: $editing) { w in WorkflowEditor(workflow: w) { saved in if let saved { model.save(saved) }; editing = nil } }
    }

    private func card(_ w: Workflow) -> some View {
        Card {
            VStack(alignment: .leading, spacing: ORIX.Space.s) {
                HStack {
                    Image(systemName: "bolt.fill").foregroundStyle(ORIX.Palette.accent).accessibilityHidden(true)
                    Text(w.name).font(.headline)
                    Spacer()
                    if !w.builtIn {
                        Menu { Button(L("Edit…")) { editing = w }; Button(L("Delete"), role: .destructive) { model.delete(w) } } label: { Image(systemName: "ellipsis.circle") }
                            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel(L("More"))
                    }
                }
                ForEach(Array(w.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(i + 1).").font(.caption.monospacedDigit()).foregroundStyle(ORIX.Palette.textTertiary)
                        Text(step.title).font(.callout).foregroundStyle(step == .review ? ORIX.Palette.accentSecondary : .primary)
                    }
                }
                HStack {
                    Spacer()
                    if model.runningWorkflow == w.id { ProgressView().controlSize(.small) }
                    Button(L("Run")) { model.run(w) }.buttonStyle(.borderedProminent).disabled(model.runningWorkflow != nil)
                        .accessibilityIdentifier("actions.run." + w.id)
                }
            }
        }
    }
}

struct WorkflowEditor: View {
    @State var workflow: Workflow
    var done: (Workflow?) -> Void
    @State private var error: String?

    static let palette: [(String, WorkflowStep)] = [
        ("Scan Downloads", .scanFolder(path: NSHomeDirectory() + "/Downloads")), ("Scan Home Folder", .scanFolder(path: NSHomeDirectory())),
        ("Find duplicates (1 MB+)", .findDuplicates(minimumSizeMB: 1)), ("Analyze caches and logs", .collectCaches),
        ("Analyze developer data", .collectDeveloperData), ("Collect downloads older than 90 days", .collectDownloads(olderThanDays: 90)),
        ("Review and confirm", .review), ("Move to Trash", .moveToTrash), ("Create report", .report),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: ORIX.Space.m) {
            Text(L("Edit action")).font(.title2.weight(.semibold))
            TextField(L("Name"), text: $workflow.name).textFieldStyle(.roundedBorder)
            List {
                ForEach(Array(workflow.steps.enumerated()), id: \.offset) { i, step in
                    HStack {
                        Text("\(i + 1).").foregroundStyle(ORIX.Palette.textTertiary)
                        Text(step.title)
                        Spacer()
                        Button { workflow.steps.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel(L("Remove step"))
                    }
                }
                .onMove { workflow.steps.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: 220)
            Menu(L("Add Step")) { ForEach(Self.palette, id: \.0) { p in Button(L(p.0)) { workflow.steps.append(p.1) } } }.fixedSize()
            if let error { Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(ORIX.Palette.high) }
            HStack {
                Spacer()
                Button(L("Cancel")) { done(nil) }.keyboardShortcut(.cancelAction)
                Button(L("Save")) {
                    do { try workflow.validate(); done(workflow) } catch WorkflowError.removalWithoutReview {
                        error = L("“Move to Trash” must come right after “Review and confirm”. An action can never remove files you have not seen.")
                    } catch WorkflowError.duplicatesWithoutScan {
                        error = L("“Find duplicates” needs a scan step before it.")
                    } catch { self.error = L("The action has no step.") }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(workflow.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(ORIX.Space.xl)
        .frame(width: 520)
    }
}
