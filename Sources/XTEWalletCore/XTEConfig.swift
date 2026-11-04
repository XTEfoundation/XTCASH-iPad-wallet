// Copyright (c) 2026, TRRXITTE Int., incorporate. Licensed under AGPL-3.0.
//
// Network parameters for traaittXTCASH [XTCASH]. Values are taken from
// https://github.com/TRRXITTE/traaittXTCASH/blob/master/src/config/CryptoNoteConfig.h
// and src/config/WalletConfig.h, matching the XTCASH React Native wallet
// (XTEfoundation/XTCASH-wallet src/Config.js). The type keeps its historical
// name XTEConfig because the core library is shared with the XTE iPad wallet.

import Foundation

public enum XTEConfig {
    public static let ticker = "XTCASH"
    public static let coinName = "traaittXTCASH"

    /// CRYPTONOTE_PUBLIC_ADDRESS_BASE58_PREFIX
    public static let addressPrefix: UInt64 = 925524

    /// CRYPTONOTE_DISPLAY_DECIMAL_POINT
    public static let decimalPlaces = 2

    /// MINIMUM_FEE (atomic units)
    public static let minimumFee: UInt64 = 100

    /// DIFFICULTY_TARGET (seconds)
    public static let blockTargetSeconds: UInt64 = 32

    /// CRYPTONOTE_MINED_MONEY_UNLOCK_WINDOW
    public static let minedMoneyUnlockWindow: UInt64 = 40

    /// CRYPTONOTE_MAX_BLOCK_NUMBER - unlockTime below this is a block height, otherwise a unix timestamp.
    public static let maxBlockNumber: UInt64 = 500_000_000

    /// CRYPTONOTE_LOCKED_TX_ALLOWED_DELTA_BLOCKS / _SECONDS
    public static let lockedTxAllowedDeltaBlocks: UInt64 = 1
    public static let lockedTxAllowedDeltaSeconds: UInt64 = 32

    /// GENESIS_BLOCK_TIMESTAMP
    public static let genesisBlockTimestamp: UInt64 = 1_686_748_487

    /// MAX_OUTPUT_SIZE_CLIENT
    public static let maxOutputSizeClient: UInt64 = 100_000_000_000_00

    /// MAX_EXTRA_SIZE_V2 / MAX_EXTRA_SIZE_V2_HEIGHT
    public static let maxExtraSizeV2: Int = 1024
    public static let maxExtraSizeV2Height: UInt64 = 1_300_000

    /// Mixin limits by height (MIXIN_LIMITS_V1/V2/V3_HEIGHT).
    public static func mixinLimits(height: UInt64) -> (minimum: UInt64, maximum: UInt64, defaultMixin: UInt64) {
        if height >= 1_000_000 { return (0, 8, 8) }
        if height >= 800_000 { return (0, 5, 5) }
        if height >= 440_000 { return (0, 4, 4) }
        return (0, UInt64.max, 3)
    }

    /// WalletConfig.h standardAddressLength: varint(925524) (3 bytes) + 32 + 32 + 4-byte checksum
    /// -> 98 base58 chars, starting with "cash".
    public static let standardAddressLength = 98
    /// integratedAddressLength = standard + (64 * 11) / 8 = 186.
    public static let integratedAddressLength = 186

    public static let uriSchemes = ["xtcash"]

    /// RPC_DEFAULT_PORT / P2P_DEFAULT_PORT of the XTCASH daemon.
    public static let rpcDefaultPort = 14423
    public static let p2pDefaultPort = 14487

    /// Default node: the XTCASH daemon on main.trrxitte.com behind the TLS proxy at
    /// https://main.trrxitte.com/xtcash/ (plain RPC is main.trrxitte.com:14423).
    public static let defaultNode = NodeInfo(name: "XTCASH main (SSL)", host: "main.trrxitte.com", port: 443, ssl: true, path: "/xtcash")
    /// Public XTCASH node list (same file the XTCASH React Native wallet uses).
    public static let nodeListURL = URL(string: "https://raw.githubusercontent.com/XTEfoundation/XTCASH-wallet/main/nodes.json")!

    /// BLOCKS_SYNCHRONIZING_DEFAULT_COUNT used by the wallet backend.
    public static let blocksPerSyncRequest: UInt64 = 100
}
