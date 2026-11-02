`crypto-tests.txt` is a subset of `tests/crypto/tests.txt` from the Monero
Project (Copyright (c) 2014-2024, The Monero Project, BSD-3-Clause), which
exercises the same CryptoNote primitives (ed25519 / Keccak / ring signatures)
used by traaitt. Lines are unmodified.

`turtlecoin-utils-tx.json` is a signed transaction produced by the independent
JavaScript implementation turtlecoin-utils 3.x (`createTransaction`) with the
XTE address prefix. It is used to check that this wallet's transaction
parser/serializer, hashing and ring-signature verification agree byte for byte.
