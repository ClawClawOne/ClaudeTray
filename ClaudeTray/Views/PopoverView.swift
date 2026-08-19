import SwiftUI

struct PopoverView: View {
    /// Lien de soutien, seule URL du popover qui ne serve pas au diagnostic.
    static let supportURL = URL(string: "https://buymeacoffee.com/theunnamedcompany")!

    @ObservedObject var store: UsageStore
    @State private var manualToken = ""
    @State private var showTokenField = false
    /// Révocation en deux temps : pas de panneau modal, qui ferait disparaître le popover.
    @State private var confirmRevoke = false

    /// Raccourci : toutes les chaînes viennent de la langue choisie dans les réglages.
    private var loc: Loc { store.loc }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let snapshot = store.snapshot, !snapshot.windows.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(snapshot.windows) { window in
                        UsageRowView(window: window,
                                     now: store.now,
                                     showRemaining: store.showRemaining,
                                     baseColor: store.percentColor,
                                     loc: loc)
                    }
                }
            } else {
                Text(loc.noData)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Divider()
            settings
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            ClaudeGlyph()
                .fill(Color.claudeOrange)
                .frame(width: 14, height: 14)
            Text("ClaudeTray")
                .font(.system(size: 13, weight: .bold))
            Spacer()
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            }
            Button {
                store.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(loc.refreshNow)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(loc.settingsLanguage, selection: $store.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.nativeName).tag(language)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)

            Picker(loc.settingsRefresh, selection: $store.refreshInterval) {
                ForEach(RefreshInterval.allCases) { interval in
                    Text(interval.label(loc)).tag(interval)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)

            Toggle(loc.showLogo, isOn: $store.showLogo)
            Toggle(loc.showAllWindows, isOn: $store.showBothWindows)

            Picker(loc.singleMetric, selection: $store.metric) {
                ForEach(MenuBarMetric.allCases) { metric in
                    Text(metric.label(loc)).tag(metric)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .disabled(store.showBothWindows)

            HStack {
                Text(loc.edgeMargin)
                Slider(value: $store.edgeMargin,
                       in: 0...MenuBarLayout.maximumEdgeMargin,
                       step: 1)
                Text("\(Int(store.edgeMargin)) pt")
                    .monospacedDigit()
                    .frame(width: 32, alignment: .trailing)
            }
            .controlSize(.small)

            HStack {
                Text(loc.spacing)
                Slider(value: $store.itemSpacing,
                       in: MenuBarLayout.minimumSpacing...MenuBarLayout.maximumSpacing,
                       step: 1)
                Text("\(Int(store.itemSpacing)) pt")
                    .monospacedDigit()
                    .frame(width: 32, alignment: .trailing)
            }
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 4) {
                Text(loc.percentColor)
                HStack(spacing: 6) {
                    ForEach(ColorStorage.palette, id: \.key) { entry in
                        Button {
                            store.percentColor = entry.color
                        } label: {
                            Circle()
                                .fill(entry.color)
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Circle().strokeBorder(.primary,
                                                          lineWidth: ColorStorage.hex(from: entry.color) == ColorStorage.hex(from: store.percentColor) ? 2 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(loc.colorName(entry.key))
                    }
                }
            }

            Toggle(loc.showRemaining, isOn: $store.showRemaining)
            Toggle(loc.notificationsSetting, isOn: $store.notificationsEnabled)
            Toggle(loc.launchAtLogin, isOn: $store.launchAtLogin)
            HStack(spacing: 6) {
                Toggle(loc.settingCheckUpdates, isOn: $store.updateCheckEnabled)
                Spacer()
                Button(store.isCheckingUpdate ? loc.checkingUpdate : loc.checkNow) {
                    store.checkForUpdates(force: true)
                }
                .controlSize(.small)
                .disabled(store.isCheckingUpdate)
            }
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 11))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let notice = store.noticeMessage {
                Label(notice, systemImage: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.checkedUpToDate {
                Text(loc.upToDate)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let staleFor = store.staleFor {
                Text(loc.staleSince(UsageFormatting.shortDuration(staleFor, loc: loc)))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Text(loc.tokenLabel)
                Text(store.tokenSource?.label(loc) ?? loc.tokenUnresolved)
                    .foregroundStyle(store.tokenSource == nil ? .secondary : .primary)
            }
            .font(.system(size: 10))

            Text(store.lastSuccess.map { loc.lastRefresh(UsageFormatting.clockString($0, loc: loc)) }
                 ?? loc.noRefreshYet)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if store.isPaused {
                Text(loc.pollingPaused)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let update = store.availableUpdate {
                Link(destination: update.url) {
                    Label(loc.updateAvailable(update.version), systemImage: "arrow.down.circle")
                        .font(.system(size: 10))
                }
            }

            manualTokenSection

            HStack {
                Link(loc.supportProject, destination: PopoverView.supportURL)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(loc.quit) { NSApplication.shared.terminate(nil) }
                    .controlSize(.small)
            }
        }
    }

    /// Échappatoire quand le trousseau refuse l'accès après un rebuild : un champ visible,
    /// pas un réglage caché. Le token vient de `claude setup-token` (validité un an).
    private var manualTokenSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(showTokenField ? loc.hideToken : loc.pasteToken) {
                    showTokenField.toggle()
                }
                .controlSize(.small)

                if store.hasManualToken {
                    Button(loc.clearManualToken) { store.clearManualToken() }
                        .controlSize(.small)
                }
            }

            if showTokenField {
                SecureField("sk-ant-oat…", text: $manualToken)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .onSubmit(save)

                HStack {
                    Text(loc.tokenHint)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(loc.save, action: save)
                        .controlSize(.small)
                        .disabled(manualToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Button(confirmRevoke ? loc.revokeConfirm : loc.revokeToken) {
                    if confirmRevoke {
                        confirmRevoke = false
                        store.revokeToken()
                    } else {
                        confirmRevoke = true
                    }
                }
                .controlSize(.small)
                .tint(confirmRevoke ? .red : nil)

                if confirmRevoke {
                    Text(loc.revokeHint)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // La confirmation retombe d'elle-même : sans cela, le bouton rouge resterait armé
        // pour un clic distrait la prochaine fois que le popover est ouvert.
        .task(id: confirmRevoke) {
            guard confirmRevoke else { return }
            try? await Task.sleep(for: .seconds(6))
            confirmRevoke = false
        }
    }

    private func save() {
        store.saveManualToken(manualToken)
        manualToken = ""
        showTokenField = false
    }
}
