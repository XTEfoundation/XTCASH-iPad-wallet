// Copyright (c) 2012-2017, The CryptoNote developers, The Bytecoin developers
// Copyright (c) 2014-2018, The Monero Project
// Copyright (c) 2016-2018, The Karbowanec developers
// Copyright (c) 2018-2019, The TurtleCoin Developers
// Copyright (c) 2020-2026, TRRXITTE Int., incorporate
//
// C API over the CryptoNote ed25519 primitives used by traaitt [XTE].
// The implementation (xte_crypto.c) is a line-for-line C port of
// traaitt/src/crypto/crypto.cpp (namespace Crypto::crypto_ops) so it can be
// called from Swift without a C++ standard library. The curve arithmetic
// (crypto-ops.c / crypto-ops-data.c) and Keccak (keccak.c) are vendored
// unchanged from https://github.com/TRRXITTE/traaitt/tree/master/src/crypto.
//
// All keys, scalars, points, hashes and derivations are 32 bytes.
// Signatures are 64 bytes. Functions returning int return 1 on success, 0 on failure.

#ifndef XTE_CRYPTO_H
#define XTE_CRYPTO_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Keccak-256 as used by CryptoNote (cn_fast_hash). */
void xte_cn_fast_hash(const uint8_t *data, size_t length, uint8_t hash_out[32]);

/* Raw keccak with an arbitrary output size (used for view key from spend key). */
void xte_keccak(const uint8_t *data, size_t length, uint8_t *md, size_t mdlen);

/* sc_reduce32 in place. */
void xte_sc_reduce32(uint8_t scalar[32]);

/* Returns 1 if the 32-byte scalar is canonical (sc_check == 0). */
int xte_sc_check(const uint8_t scalar[32]);

/* Returns 1 if key is a valid curve point. */
int xte_check_key(const uint8_t pub[32]);

/* Random keypair from a CSPRNG (arc4random_buf). */
void xte_generate_keys(uint8_t pub_out[32], uint8_t sec_out[32]);

/* sec -> pub. Returns 0 if sec is not a reduced scalar. */
int xte_secret_key_to_public_key(const uint8_t sec[32], uint8_t pub_out[32]);

/* generate_deterministic_keys: sec = sc_reduce32(seed), pub = sec*G. */
void xte_generate_deterministic_keys(const uint8_t seed[32], uint8_t pub_out[32], uint8_t sec_out[32]);

/* View keys derived from the spend secret: keccak(spend) -> reduce -> pub. */
void xte_generate_view_from_spend(const uint8_t spend_sec[32], uint8_t view_sec_out[32], uint8_t view_pub_out[32]);

int xte_generate_key_derivation(const uint8_t pub[32], const uint8_t sec[32], uint8_t derivation_out[32]);

int xte_derive_public_key(const uint8_t derivation[32], uint64_t output_index, const uint8_t base[32], uint8_t derived_out[32]);

int xte_derive_secret_key(const uint8_t derivation[32], uint64_t output_index, const uint8_t base[32], uint8_t derived_out[32]);

int xte_underive_public_key(const uint8_t derivation[32], uint64_t output_index, const uint8_t derived_key[32], uint8_t base_out[32]);

int xte_generate_key_image(const uint8_t pub[32], const uint8_t sec[32], uint8_t image_out[32]);

/* hash_to_scalar(data) = sc_reduce32(keccak(data)) */
void xte_hash_to_scalar(const uint8_t *data, size_t length, uint8_t scalar_out[32]);

/* hash_to_point / hash_data_to_ec */
void xte_hash_to_point(const uint8_t *data, size_t length, uint8_t point_out[32]);

void xte_generate_signature(const uint8_t prefix_hash[32], const uint8_t pub[32], const uint8_t sec[32], uint8_t sig_out[64]);

int xte_check_signature(const uint8_t prefix_hash[32], const uint8_t pub[32], const uint8_t sig[64]);

/* Ring signatures (CryptoNote v1). pubs: count*32 bytes, sigs_out: count*64 bytes. */
int xte_generate_ring_signatures(
    const uint8_t prefix_hash[32],
    const uint8_t key_image[32],
    const uint8_t *pubs,
    size_t count,
    const uint8_t sec[32],
    size_t real_index,
    uint8_t *sigs_out);

int xte_check_ring_signature(
    const uint8_t prefix_hash[32],
    const uint8_t key_image[32],
    const uint8_t *pubs,
    size_t count,
    const uint8_t *sigs);

/* Fill buffer with cryptographically secure random bytes. */
void xte_random_bytes(uint8_t *out, size_t n);

#ifdef __cplusplus
}
#endif

#endif
