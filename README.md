# XTCASH iPad Wallet

Native iPadOS wallet for **traaittXTCASH [XTCASH]**, written in Swift/SwiftUI.
It is the XTCASH build of the [XTE iPad wallet](https://github.com/XTEfoundation/XTE-iPad-wallet)
(same CryptoNote core, retargeted network parameters) and matches the XTCASH React Native wallet
[XTEfoundation/XTCASH-wallet](https://github.com/XTEfoundation/XTCASH-wallet).
Private keys are generated and kept on the iPad (Keychain, guarded by Face ID / Touch ID / passcode);
transactions are built and ring-signed on the device and relayed to a public XTCASH node.

| | |
|---|---|
| Bundle ID | `io.traaitt.xtcash.ipad` |
| Display name | XTCASH |
| Version | 1.0.0 (build 1) |
| Minimum OS | iPadOS 16 |
| Device | iPad only (portrait + landscape, Split View / Slide Over) |
| Network | traaittXTCASH: address prefix 925524 (`cash…`, 98 chars), 2 decimals, minimum fee 1.00 XTCASH (100 atomic), 32 s blocks, RPC 14423 / P2P 14487 |
| License | AGPL-3.0, © TRRXITTE Int., incorporate (see `LICENSE`, `NOTICE`) |

## Features

* **Wallets** – create a new wallet (25-word CryptoNote mnemonic), restore from a mnemonic, or restore from
  private spend + view keys, with an optional scan height.
* **Keychain + biometrics** – the private keys are stored as a device-only Keychain item
  (`kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` + `.userPresence`), so every read requires
  Face ID / Touch ID or the passcode. Keys are dropped from memory when the app goes to the background.
  The non-secret sync cache (`wallet.json`: address, outputs, history) uses complete file protection
  and is excluded from backups.
* **Receive** – address, copy/share, QR code, and `xtcash://` payment requests with amount / payment ID.
* **Sync** – `/getwalletsyncdata` with block-hash checkpoints, output scanning via key derivation,
  global indexes via `/get_global_indexes_for_range`, spent detection via key images, unlock-time rules,
  fork/re-org rewind, unlocked/locked balance, transaction history.
* **Send** – input selection, denomination splitting, decoys from `/getrandom_outs`, ring signatures,
  payment IDs, integrated addresses, optional node fee from `/fee` (shown before confirming),
  local verification of every ring signature / amounts / fee / size, then `/sendrawtransaction`.
  Inputs are locked until the transaction is mined; dropped transactions are released via
  `/get_transactions_status`. Sending requires a fresh Face ID / passcode confirmation.
* **Node** – loads the public node list from
  [XTEfoundation/XTCASH-wallet `nodes.json`](https://github.com/XTEfoundation/XTCASH-wallet/blob/main/nodes.json) (same list as the RN app),
  shows node/network height, sync state and peers; custom nodes are supported. If the built-in default
  node (`https://main.trrxitte.com/xtcash`, the XTCASH daemon behind the TLS proxy; plain RPC is port 14423) is unreachable, the app switches once to the first responding node from that list.
* **Settings** – node selection, XTCASH-only display (no fiat prices / no third-party price APIs),
  backup screen (seed + keys) behind authentication, rescan, delete wallet.
* **URL scheme** – `xtcash://` links open the Send screen pre-filled.

## Layout

```
Package.swift                 Swift package: XTEWalletCore (+ CXTECrypto), testable on macOS, Linux and iOS
Sources/CXTECrypto/           CryptoNote ed25519 + Keccak (vendored from traaitt/src/crypto) and a C port of crypto.cpp
Sources/XTEWalletCore/        Addresses, base58, mnemonic, keys, daemon client, sync, transaction builder
Tests/XTEWalletCoreTests/     Unit tests + upstream vectors
App/XTCASHWallet/             SwiftUI iPad app (NavigationSplitView)
App/XTCASHWalletTests/        App unit tests (run in the iPad simulator)
project.yml                   XcodeGen spec for XTCASHWallet.xcodeproj
Tools/NodeCheck/              CLI that exercises every daemon endpoint against a live node
```

## Cryptography

No cryptography is re-invented or faked:

* `Sources/CXTECrypto/crypto-ops.c`, `crypto-ops-data.c`, `keccak.c` are copied unchanged from
  [TRRXITTE/traaitt](https://github.com/TRRXITTE/traaitt) `src/crypto` (CryptoNote/Monero/TurtleCoin ed25519 and Keccak).
* `xte_crypto.c` is a line-by-line C port of traaitt's `crypto.cpp` (key generation, key derivation,
  derive/underive public key, derive secret key, key images, signatures, ring signatures). It was ported to C
  only so that it builds as a plain C target without a C++ runtime.
* Address encoding (CryptoNote base58, prefix 925524 → `cash…`), the 1626-word mnemonic with CRC32 checksum,
  and the transaction format (v1, key inputs/outputs, tx extra) are implemented in Swift following traaitt
  `src/common/Base58.cpp`, `src/mnemonics`, `src/walletbackend/Transfer.cpp` and `WalletSynchronizer.cpp`.

Verification (`swift test`):

* 360 vectors from Monero's `tests/crypto/tests.txt` (check_key, secret→public, key derivation,
  derive public/secret key, key images, signatures, ring signatures, hash-to-scalar).
* XTCASH address / mnemonic vectors produced with the JavaScript crypto of the XTCASH React Native wallet
  (traaittcash-wallet-backend) for the same seeds, including the fixed-seed address the XTCASH daemon accepted;
  plus XTE (1334) and upstream wallet-backend address vectors to check the prefix handling.
* A transaction created and signed by turtlecoin-utils is parsed, re-serialized byte-for-byte, hashed and its ring
  signature verified; conversely, transactions built by this wallet were parsed by turtlecoin-utils with identical
  hash / prefix hash.
* End-to-end in-memory tests: receive → scan → build/sign → recipient detects funds → spend + change detection,
  re-orgs, locked outputs, dropped transactions.

## Build & run

Requirements: macOS with Xcode 15 or newer (CI uses Xcode 16 on `macos-15`), [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate          # creates XTCASHWallet.xcodeproj (not committed)
open XTCASHWallet.xcodeproj   # choose an iPad simulator and Run
```

Command line:

```sh
swift test                                     # core library tests (macOS or Linux)
xcodebuild build -project XTCASHWallet.xcodeproj -scheme XTCASHWallet \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' CODE_SIGNING_ALLOWED=NO
xcodebuild test  -project XTCASHWallet.xcodeproj -scheme XTCASHWallet \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' CODE_SIGNING_ALLOWED=NO
cd Tools/NodeCheck && swift run xte-node-check main.trrxitte.com 443 ssl /xtcash   # live node check
```

Note: the Keychain item requires a device passcode. In the simulator, enrol Face ID
(Features → Face ID → Enrolled) to test the unlock flow.

## Signing, TestFlight and App Store

Nothing secret is stored in this repository; signing happens on a Mac with the TRRXITTE Apple Developer account.

1. Apple Developer Program membership for the organisation; register the App ID `io.traaitt.xtcash.ipad`
   (no special capabilities are needed; Keychain access works with the default access group).
2. In App Store Connect create the app (platform iOS, iPad only), bundle ID `io.traaitt.xtcash.ipad`, SKU of your choice.
3. `xcodegen generate`, open the project, select the **XTCASHWallet** target → *Signing & Capabilities* →
   your Team (or set `DEVELOPMENT_TEAM` in `project.yml` locally, do not commit personal IDs if you prefer).
4. *Product → Archive* with destination *Any iOS Device*, then *Distribute App → App Store Connect → Upload*.
   Or from the command line:
   ```sh
   xcodebuild archive -project XTCASHWallet.xcodeproj -scheme XTCASHWallet -destination 'generic/platform=iOS' \
     -archivePath build/XTCASHWallet.xcarchive DEVELOPMENT_TEAM=<TEAMID>
   xcodebuild -exportArchive -archivePath build/XTCASHWallet.xcarchive -exportPath build/export \
     -exportOptionsPlist ExportOptions.plist   # method: app-store-connect, teamID: <TEAMID>
   ```
   CI: `.github/workflows/testflight.yml` archives, signs (profile "XTCASH AppStore io.traaitt.xtcash.ipad")
   and uploads with an App Store Connect API key, all from GitHub **secrets** (never in the repo). Without the
   secrets the TestFlight job is skipped.
5. In TestFlight add internal testers; external testing requires Beta App Review.
6. Before submission:
   * **Export compliance**: answer the encryption questions in App Store Connect (the app uses HTTPS and
     digital signatures for transactions). Add `ITSAppUsesNonExemptEncryption` to `project.yml` once decided.
   * **App Privacy** labels: the app collects no data; node operators see the IP address and the requests
     made to their node.
   * **Review notes**: explain that it is a non-custodial wallet for the XTCASH cryptocurrency
     (App Review Guideline 3.1.5(b) permits wallet apps; the developer must be an organisation).
   * Screenshots for 13" iPad (portrait and landscape), privacy policy URL, support URL.

## Status / known limitations

* Send has been verified offline (signatures, serialization, cross-checked with turtlecoin-utils) and the
  live-node workflow builds a transaction with real chain decoys, but **no transaction from this app has been
  broadcast and confirmed on mainnet yet** – do a small test send before relying on it.
* App Transport Security allows plain HTTP only for `*.trrxitte.com` (the public node list uses port 14423
  without TLS) and local network nodes; other custom nodes must use HTTPS.
* No QR-code camera scanner yet (paste and `xtcash://` links are supported); no fusion transactions; single wallet.
