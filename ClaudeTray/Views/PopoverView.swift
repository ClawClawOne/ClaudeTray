import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    @State private var manualToken = ""
    @State private var showTokenField = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let snapshot = store.snapshot, !snapshot.windows.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(snapshot.windows) { window in
                        UsageRowView(window: window,
                                     now: store.now,
                                     showRemaining: store.showRemaining,
                                     baseColor: store.percentColor)
                    }
                }
            } else {
                Text("Aucune donnée d'usage pour l'instant.")
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
            .help("Rafraîchir maintenant")
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Rafraîchissement", selection: $store.refreshInterval) {
                ForEach(RefreshInterval.allCases) { interval in
                    Text(interval.label).tag(interval)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)

            Toggle("Barre de menu : afficher 5 h et hebdo", isOn: $store.showBothWindows)

            Picker("Métrique unique", selection: $store.metric) {
                ForEach(MenuBarMetric.allCases) { metric in
                    Text(metric.label).tag(metric)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .disabled(store.showBothWindows)

            HStack {
                Text("Espacement")
                Slider(value: $store.itemSpacing,
                       in: MenuBarLayout.minimumSpacing...MenuBarLayout.maximumSpacing,
                       step: 1)
                Text("\(Int(store.itemSpacing)) pt")
                    .monospacedDigit()
                    .frame(width: 32, alignment: .trailing)
            }
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 4) {
                Text("Couleur des pourcentages")
                HStack(spacing: 6) {
                    ForEach(ColorStorage.palette, id: \.name) { entry in
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
                        .help(entry.name)
                    }
                }
            }

            Toggle("Afficher le restant plutôt que le consommé", isOn: $store.showRemaining)
            Toggle("Notifications à 80 % et 95 %", isOn: $store.notificationsEnabled)
            Toggle("Lancer au démarrage", isOn: $store.launchAtLogin)
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

            if let staleFor = store.staleFor {
                Text("Données obsolètes depuis \(UsageFormatting.shortDuration(staleFor)).")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Text("Token :")
                Text(store.tokenSource?.rawValue ?? "non résolu")
                    .foregroundStyle(store.tokenSource == nil ? .secondary : .primary)
            }
            .font(.system(size: 10))

            Text(store.lastSuccess.map { "Dernier rafraîchissement réussi : \(UsageFormatting.clock.string(from: $0))" }
                 ?? "Aucun rafraîchissement réussi.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if store.isPaused {
                Text("Polling suspendu (veille ou session verrouillée).")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            manualTokenSection

            HStack {
                Spacer()
                Button("Quitter") { NSApplication.shared.terminate(nil) }
                    .controlSize(.small)
            }
        }
    }

    /// Échappatoire quand le trousseau refuse l'accès après un rebuild : un champ visible,
    /// pas un réglage caché. Le token vient de `claude setup-token` (validité un an).
    private var manualTokenSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(showTokenField ? "Masquer le token manuel" : "Coller un token manuel") {
                    showTokenField.toggle()
                }
                .controlSize(.small)

                if store.hasManualToken {
                    Button("Effacer") { store.clearManualToken() }
                        .controlSize(.small)
                }
            }

            if showTokenField {
                SecureField("sk-ant-oat…", text: $manualToken)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .onSubmit(save)

                HStack {
                    Text("Issu de « claude setup-token ». Stocké en 0600 dans Application Support.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Enregistrer", action: save)
                        .controlSize(.small)
                        .disabled(manualToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        store.saveManualToken(manualToken)
        manualToken = ""
        showTokenField = false
    }
}
