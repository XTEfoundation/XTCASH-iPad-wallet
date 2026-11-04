// Copyright (c) 2026, TRRXITTE Int., incorporate. Licensed under AGPL-3.0.

import SwiftUI
import XTEWalletCore

struct OnboardingView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case create = "Create", seed = "Restore from seed", keys = "Restore from keys"
        var id: String { rawValue }
    }

    @EnvironmentObject var model: AppModel
    @State private var mode: Mode = .create
    @State private var generated = WalletKeys.generate()
    @State private var confirmedBackup = false
    @State private var seedText = ""
    @State private var spendKey = ""
    @State private var viewKey = ""
    @State private var scanHeight = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                switch mode {
                case .create: createSection
                case .seed: seedSection
                case .keys: keysSection
                }
                if mode != .create {
                    Section("Scan from block height") {
                        TextField("0 (scan whole chain)", text: $scanHeight).keyboardType(.numberPad)
                        Text("Enter the height at which this wallet was created to sync faster.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button(action: submit) {
                        Text(mode == .create ? "Create wallet" : "Restore wallet").frame(maxWidth: .infinity)
                    }
                    .disabled(mode == .create && !confirmedBackup)
                }
            }
            .navigationTitle("XTCASH Wallet")
        }
    }

    private var createSection: some View {
        Section {
            let words = (try? generated.mnemonic()) ?? []
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), alignment: .leading) {
                ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                    Text("\(i + 1). \(w)").font(.body.monospaced())
                }
            }
            .padding(.vertical, 4)
            .privacySensitive()
            Text(generated.address.encoded()).font(.caption.monospaced()).textSelection(.enabled)
            Toggle("I wrote down these 25 words. Anyone with them can spend my XTCASH.", isOn: $confirmedBackup)
            Button("Generate another") { generated = WalletKeys.generate(); confirmedBackup = false }
        } header: {
            Text("Your mnemonic seed")
        }
    }

    private var seedSection: some View {
        Section("25-word mnemonic seed") {
            TextEditor(text: $seedText)
                .frame(minHeight: 120)
                .font(.body.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private var keysSection: some View {
        Section("Private keys") {
            SecureField("Private spend key (64 hex)", text: $spendKey)
                .font(.body.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("Private view key (64 hex)", text: $viewKey)
                .font(.body.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }

    private func submit() {
        error = nil
        do {
            let height = UInt64(scanHeight.trimmingCharacters(in: .whitespaces)) ?? 0
            switch mode {
            case .create:
                try model.createWallet(generated, scanHeight: nil)
            case .seed:
                try model.createWallet(try WalletKeys.fromMnemonic(seedText), scanHeight: height)
            case .keys:
                try model.createWallet(try WalletKeys.fromKeys(privateSpendKeyHex: spendKey.trimmingCharacters(in: .whitespaces),
                                                               privateViewKeyHex: viewKey.trimmingCharacters(in: .whitespaces)),
                                       scanHeight: height)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
