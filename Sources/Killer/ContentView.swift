// Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4
// Workbench · utilitarian · native semantic colors · system typography.
import AppKit
import KillerCore
import SwiftUI

enum Palette {
    static let accent = Color.accentColor
    static let destructive = Color.red
    static let success = Color.green
    static let warning = Color.orange
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
}

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            VStack(spacing: 0) {
                if model.scope == .activity {
                    ActivityView(entries: model.visibleActivity, query: model.query)
                } else {
                    HSplitView {
                        processList.frame(minWidth: 280, idealWidth: 350, maxWidth: 400)
                        inspector.frame(minWidth: 340, idealWidth: 420, maxWidth: .infinity)
                    }
                }
                statusBar
            }
            .background(Palette.canvas)
            .navigationTitle(model.scope.rawValue)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    ProcessSearchField(text: $model.query).frame(width: 240)
                }
                ToolbarItem {
                    Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh processes (⌘R)").accessibilityLabel("Refresh processes")
                        .disabled(model.isRefreshing)
                }
            }
        }
        .sheet(isPresented: $model.showConfirmation) {
            if let target = model.pendingTarget { confirmation(target) }
        }
        .onChange(of: model.scope) { model.selection = nil }
        .onChange(of: model.query) {
            if let selected = model.selection, !model.visibleProcesses.contains(where: { $0.id == selected }) {
                model.selection = nil
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "stop.circle.fill").font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Palette.destructive)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Killer").font(.title3.weight(.semibold))
                    Text("Take back control.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 26)
            List(selection: $model.scope) {
                Section("On this Mac") {
                    ForEach([ProcessScope.applications, .background]) { scope in
                        Label {
                            HStack {
                                Text(scope == .background ? "Background" : scope.rawValue)
                                Spacer(minLength: 2)
                                Text("\(scope == .applications ? model.applicationCount : model.backgroundCount)")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: scope.symbol) }
                            .tag(scope)
                    }
                }
                Section {
                    Label(ProcessScope.activity.rawValue, systemImage: ProcessScope.activity.symbol)
                        .tag(ProcessScope.activity)
                }
            }.listStyle(.sidebar)
            VStack(alignment: .leading, spacing: 7) {
                Label("Only on your Mac", systemImage: "macbook")
                    .font(.caption.weight(.medium))
                Text("No account. No tracking.\nNo processes stopped automatically.")
                    .font(.caption).foregroundStyle(.secondary).lineSpacing(3)
            }.padding(16)
        }
    }

    private var processList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.scope == .applications ? "Running applications" : "Third-party processes")
                    .font(.headline)
                Spacer()
                Text("\(model.visibleProcesses.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(16)
            Divider()
            if model.visibleProcesses.isEmpty {
                ContentUnavailableView {
                    Label(model.isRefreshing && model.lastRefresh == nil ? "Finding processes…" : "No matches", systemImage: "magnifyingglass")
                } description: {
                    Text(model.query.isEmpty ? "Processes appear here while they’re running." : "Try a different name, PID, or executable path.")
                }
            } else {
                List(selection: $model.selection) {
                    ForEach(model.visibleProcesses) { process in
                        ProcessRow(process: process, isStopping: model.activeOperation == process.id)
                            .tag(process.id)
                            .contextMenu {
                                Button("Force Quit…", role: .destructive) { model.requestTermination(process) }
                                    .disabled(model.activeOperation != nil || process.protection != nil)
                                Button("Copy Process ID") { copy(String(process.id.pid)) }
                                Button("Show in Finder") { reveal(process) }
                            }
                    }
                }.listStyle(.inset).alternatingRowBackgrounds(.disabled)
            }
        }.background(Palette.surface)
    }

    @ViewBuilder private var inspector: some View {
        if let selected = model.selectedProcess {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        ProcessIcon(process: selected, size: 64)
                        Text(selected.displayName).font(.system(size: 26, weight: .semibold)).textSelection(.enabled)
                        Label(selected.isApplication ? "Running application" : "Background process", systemImage: "circle.fill")
                            .font(.caption).foregroundStyle(.secondary)
                            .labelStyle(StatusLabelStyle())
                    }
                    VStack(spacing: 12) {
                        metadata("Process ID", value: String(selected.id.pid), mono: true)
                        metadata("Owner", value: selected.owner)
                        metadata("Parent process", value: String(selected.record.parentPID), mono: true)
                        if let bundle = selected.bundleIdentifier { metadata("Bundle", value: bundle, mono: true) }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Executable").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Text(selected.record.executablePath).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        Button("Show in Finder") { reveal(selected) }.buttonStyle(.link).font(.caption)
                    }
                    Spacer(minLength: 0)
                    if let reason = selected.protection {
                        Label(reason, systemImage: "lock.shield").font(.callout).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Close it. Even when Quit won’t.").font(.headline)
                            Text("Force quitting stops this process immediately. Unsaved changes may be lost.")
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button(role: .destructive) { model.requestTermination(selected) } label: {
                                HStack(spacing: 8) {
                                    if model.activeOperation == selected.id { ProgressView().controlSize(.small) }
                                    else { Image(systemName: selected.needsAdministrator ? "lock.shield" : "stop.fill") }
                                    Text(model.activeOperation == selected.id ? "Stopping & checking…" : selected.needsAdministrator ? "Force Quit as Administrator…" : "Force Quit…")
                                }.frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent).tint(Palette.destructive).controlSize(.large)
                            .disabled(model.activeOperation != nil)
                            if !selected.needsAdministrator {
                                Button("Force Quit as Administrator…") { model.requestTermination(selected, administrator: true) }
                                    .buttonStyle(.link).font(.caption).disabled(model.activeOperation != nil)
                            }
                            if selected.needsAdministrator {
                                Text("macOS will request administrator authorization for this process.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let result = model.latestResult, result.pid == selected.id.pid { ResultCard(entry: result) }
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "cursorarrow.click.2").font(.system(size: 42, weight: .light)).foregroundStyle(.tertiary)
                VStack(spacing: 8) {
                    Text("Some apps need a firmer goodbye.").font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                    Text("Select a process to see what’s running\nand force it to quit.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Spacer()
                if let result = model.latestResult { ResultCard(entry: result) }
                Label("Core macOS processes are protected.", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth: .infinity)
        }
    }

    private var statusBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                if model.activeOperation != nil {
                    ProgressView().controlSize(.mini)
                    Text("Waiting for exit and checking for a restart…")
                } else {
                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Palette.success)
                    Text(model.lastRefresh == nil ? "Loading processes…" : "Live · refreshes every 2 seconds")
                }
                Spacer()
                Text("⌘F Search").padding(.trailing, 8)
                Text("⌘⌫ Force Quit")
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    private func confirmation(_ target: AppProcess) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                ProcessIcon(process: target, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Force quit \(target.displayName)?").font(.title3.weight(.semibold))
                    Text("Process \(target.id.pid) · \(target.owner)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("This process will stop immediately. Any unsaved changes may be lost. Separate helper processes will keep running.")
                .fixedSize(horizontal: false, vertical: true)
            if model.useAdministrator {
                Label("macOS will ask you to authorize this action as an administrator.", systemImage: "lock.shield")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.showConfirmation = false; model.pendingTarget = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Force Quit", role: .destructive) { model.confirmTermination() }
                    .buttonStyle(.borderedProminent).tint(Palette.destructive)
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 430)
    }

    private func metadata(_ label: String, value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).fontDesign(mono ? .monospaced : .default).textSelection(.enabled).multilineTextAlignment(.trailing)
        }.font(.callout)
    }
    private func copy(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }
    private func reveal(_ process: AppProcess) {
        NSWorkspace.shared.activateFileViewerSelecting([process.bundleURL ?? URL(fileURLWithPath: process.record.executablePath)])
    }
}

struct ProcessRow: View {
    let process: AppProcess
    let isStopping: Bool
    var body: some View {
        HStack(spacing: 10) {
            ProcessIcon(process: process, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(process.displayName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text("PID \(process.id.pid) · \(process.needsAdministrator ? "Administrator" : "You")")
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
            if isStopping { ProgressView().controlSize(.small) }
            else if process.protection != nil { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
            else if process.needsAdministrator { Image(systemName: "lock.shield").font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 7)
            .accessibilityElement(children: .combine)
    }
}

struct ProcessIcon: View {
    let process: AppProcess
    let size: CGFloat
    var body: some View {
        if let icon = process.icon { Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size) }
        else {
            Image(systemName: process.isApplication ? "app.fill" : "terminal.fill")
                .font(.system(size: size * 0.56, weight: .regular)).foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: size * 0.22))
        }
    }
}

struct ResultCard: View {
    let entry: ActivityEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(entry.name) · \(entry.outcome.rawValue)", systemImage: entry.outcome.symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(entry.outcome.isSuccess ? Palette.success : Palette.warning)
            Text(entry.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
    }
}

struct ActivityView: View {
    let entries: [ActivityEntry]
    let query: String
    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView(query.isEmpty ? "Nothing stopped yet" : "No matching activity", systemImage: "clock.arrow.circlepath", description: Text("The outcome of each force quit appears here for this session."))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text("This session").font(.title2.weight(.semibold)).padding(.bottom, 4)
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("PID \(entry.pid)")
                                Spacer()
                                Text(entry.date, style: .time)
                            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            ResultCard(entry: entry)
                        }
                    }
                }.padding(28).frame(maxWidth: 720)
            }.frame(maxWidth: .infinity)
        }
    }
}

private struct StatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon.font(.system(size: 5)).foregroundStyle(Palette.success); configuration.title }
    }
}
