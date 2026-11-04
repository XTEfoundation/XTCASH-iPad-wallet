// Copyright (c) 2026, TRRXITTE Int., incorporate. Licensed under AGPL-3.0.

import SwiftUI
import XTEWalletCore

@main
struct XTCASHWalletApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onOpenURL { url in
                    if let uri = try? PaymentURI.parse(url.absoluteString) {
                        model.pendingURI = uri
                    }
                }
        }
        .onChange(of: scenePhase) { phase in
            // Drop keys from memory when the app leaves the foreground.
            if phase == .background { model.lock() }
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case wallet, send, receive, transactions, node, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .wallet: return "Wallet"
        case .send: return "Send"
        case .receive: return "Receive"
        case .transactions: return "Transactions"
        case .node: return "Node"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .wallet: return "creditcard"
        case .send: return "arrow.up.circle"
        case .receive: return "qrcode"
        case .transactions: return "list.bullet.rectangle"
        case .node: return "server.rack"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        switch model.phase {
        case .onboarding: OnboardingView()
        case .locked: LockedView()
        case .unlocked: MainSplitView()
        }
    }
}

struct MainSplitView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection: SidebarItem? = .wallet

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                NavigationLink(value: item) { Label(item.title, systemImage: item.icon) }
            }
            .navigationTitle(XTEConfig.ticker)
        } detail: {
            NavigationStack {
                switch selection ?? .wallet {
                case .wallet: WalletView(selection: $selection)
                case .send: SendView()
                case .receive: ReceiveView()
                case .transactions: TransactionsView()
                case .node: NodeView()
                case .settings: SettingsView()
                }
            }
        }
        .onChange(of: model.pendingURI) { uri in
            if uri != nil { selection = .send }
        }
    }
}

struct LockedView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield").font(.system(size: 72)).foregroundStyle(.tint)
            Text("XTCASH Wallet is locked").font(.title)
            Text(model.address).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 420)
            Button("Unlock") { model.unlock() }
                .buttonStyle(.borderedProminent).controlSize(.large)
            if let e = model.lastError { Text(e).foregroundStyle(.red) }
        }
        .padding()
        .onAppear { model.unlock() }
    }
}
