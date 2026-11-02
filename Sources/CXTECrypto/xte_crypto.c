// Copyright (c) 2012-2017, The CryptoNote developers, The Bytecoin developers
// Copyright (c) 2014-2018, The Monero Project
// Copyright (c) 2016-2018, The Karbowanec developers
// Copyright (c) 2018-2019, The TurtleCoin Developers
// Copyright (c) 2020-2026, TRRXITTE Int., incorporate
//
// C port of traaitt/src/crypto/crypto.cpp. Logic is kept identical to the
// upstream C++; only the C++ type wrappers were replaced with byte arrays.
// Please see LICENSE-traaitt-GPL3.txt (upstream) and the repository LICENSE.

#if defined(__linux__) && !defined(_DEFAULT_SOURCE)
#define _DEFAULT_SOURCE
#endif

#include "include/xte_crypto.h"

#include "crypto-ops.h"
#include "keccak.h"

#include <stdlib.h>
#include <string.h>

void xte_random_bytes(uint8_t *out, size_t n)
{
    /* arc4random_buf is a CSPRNG on Apple platforms (and glibc >= 2.36). */
    arc4random_buf(out, n);
}

void xte_cn_fast_hash(const uint8_t *data, size_t length, uint8_t hash_out[32])
{
    uint8_t state[200];
    keccak1600(data, (int)length, state);
    memcpy(hash_out, state, 32);
    memset(state, 0, sizeof(state));
}

void xte_keccak(const uint8_t *data, size_t length, uint8_t *md, size_t mdlen)
{
    keccak(data, (int)length, md, (int)mdlen);
}

void xte_sc_reduce32(uint8_t scalar[32])
{
    sc_reduce32(scalar);
}

int xte_sc_check(const uint8_t scalar[32])
{
    return sc_check(scalar) == 0;
}

static void random_scalar(uint8_t res[32])
{
    unsigned char tmp[64];
    xte_random_bytes(tmp, 64);
    sc_reduce(tmp);
    memcpy(res, tmp, 32);
    memset(tmp, 0, sizeof(tmp));
}

void xte_hash_to_scalar(const uint8_t *data, size_t length, uint8_t res[32])
{
    xte_cn_fast_hash(data, length, res);
    sc_reduce32(res);
}

void xte_generate_keys(uint8_t pub[32], uint8_t sec[32])
{
    ge_p3 point;
    random_scalar(sec);
    ge_scalarmult_base(&point, sec);
    ge_p3_tobytes(pub, &point);
}

void xte_generate_deterministic_keys(const uint8_t seed[32], uint8_t pub[32], uint8_t sec[32])
{
    ge_p3 point;
    memcpy(sec, seed, 32);
    sc_reduce32(sec);
    ge_scalarmult_base(&point, sec);
    ge_p3_tobytes(pub, &point);
}

int xte_check_key(const uint8_t key[32])
{
    ge_p3 point;
    return ge_frombytes_vartime(&point, key) == 0;
}

int xte_secret_key_to_public_key(const uint8_t sec[32], uint8_t pub[32])
{
    ge_p3 point;
    if (sc_check(sec) != 0)
    {
        return 0;
    }
    ge_scalarmult_base(&point, sec);
    ge_p3_tobytes(pub, &point);
    return 1;
}

void xte_generate_view_from_spend(const uint8_t spend[32], uint8_t view_sec[32], uint8_t view_pub[32])
{
    uint8_t seed[32];
    keccak(spend, 32, seed, 32);
    xte_generate_deterministic_keys(seed, view_pub, view_sec);
    memset(seed, 0, sizeof(seed));
}

int xte_generate_key_derivation(const uint8_t key1[32], const uint8_t key2[32], uint8_t derivation[32])
{
    ge_p3 point;
    ge_p2 point2;
    ge_p1p1 point3;
    if (sc_check(key2) != 0)
    {
        return 0;
    }
    if (ge_frombytes_vartime(&point, key1) != 0)
    {
        return 0;
    }
    ge_scalarmult(&point2, key2, &point);
    ge_mul8(&point3, &point2);
    ge_p1p1_to_p2(&point2, &point3);
    ge_tobytes(derivation, &point2);
    return 1;
}

static size_t write_varint(uint8_t *dest, uint64_t i)
{
    size_t n = 0;
    while (i >= 0x80)
    {
        dest[n++] = (uint8_t)((i & 0x7f) | 0x80);
        i >>= 7;
    }
    dest[n++] = (uint8_t)i;
    return n;
}

static void derivation_to_scalar(const uint8_t derivation[32], uint64_t output_index, uint8_t res[32])
{
    uint8_t buf[32 + 10];
    memcpy(buf, derivation, 32);
    size_t n = write_varint(buf + 32, output_index);
    xte_hash_to_scalar(buf, 32 + n, res);
}

int xte_derive_public_key(const uint8_t derivation[32], uint64_t output_index, const uint8_t base[32], uint8_t derived_key[32])
{
    uint8_t scalar[32];
    ge_p3 point1;
    ge_p3 point2;
    ge_cached point3;
    ge_p1p1 point4;
    ge_p2 point5;
    if (ge_frombytes_vartime(&point1, base) != 0)
    {
        return 0;
    }
    derivation_to_scalar(derivation, output_index, scalar);
    ge_scalarmult_base(&point2, scalar);
    ge_p3_to_cached(&point3, &point2);
    ge_add(&point4, &point1, &point3);
    ge_p1p1_to_p2(&point5, &point4);
    ge_tobytes(derived_key, &point5);
    return 1;
}

int xte_underive_public_key(const uint8_t derivation[32], uint64_t output_index, const uint8_t derived_key[32], uint8_t base[32])
{
    uint8_t scalar[32];
    ge_p3 point1;
    ge_p3 point2;
    ge_cached point3;
    ge_p1p1 point4;
    ge_p2 point5;
    if (ge_frombytes_vartime(&point1, derived_key) != 0)
    {
        return 0;
    }
    derivation_to_scalar(derivation, output_index, scalar);
    ge_scalarmult_base(&point2, scalar);
    ge_p3_to_cached(&point3, &point2);
    ge_sub(&point4, &point1, &point3);
    ge_p1p1_to_p2(&point5, &point4);
    ge_tobytes(base, &point5);
    return 1;
}

int xte_derive_secret_key(const uint8_t derivation[32], uint64_t output_index, const uint8_t base[32], uint8_t derived_key[32])
{
    uint8_t scalar[32];
    if (sc_check(base) != 0)
    {
        return 0;
    }
    derivation_to_scalar(derivation, output_index, scalar);
    sc_add(derived_key, base, scalar);
    return 1;
}

/* s_comm { Hash h; EllipticCurvePoint key; EllipticCurvePoint comm; } -> 96 bytes */
void xte_generate_signature(const uint8_t prefix_hash[32], const uint8_t pub[32], const uint8_t sec[32], uint8_t sig[64])
{
    ge_p3 tmp3;
    uint8_t k[32];
    uint8_t buf[96];
    memcpy(buf, prefix_hash, 32);
    memcpy(buf + 32, pub, 32);
    random_scalar(k);
    ge_scalarmult_base(&tmp3, k);
    ge_p3_tobytes(buf + 64, &tmp3);
    xte_hash_to_scalar(buf, sizeof(buf), sig);
    sc_mulsub(sig + 32, sig, sec, k);
    memset(k, 0, sizeof(k));
}

int xte_check_signature(const uint8_t prefix_hash[32], const uint8_t pub[32], const uint8_t sig[64])
{
    ge_p2 tmp2;
    ge_p3 tmp3;
    uint8_t c[32];
    uint8_t buf[96];
    memcpy(buf, prefix_hash, 32);
    memcpy(buf + 32, pub, 32);
    if (ge_frombytes_vartime(&tmp3, pub) != 0)
    {
        return 0;
    }
    if (sc_check(sig) != 0 || sc_check(sig + 32) != 0)
    {
        return 0;
    }
    ge_double_scalarmult_base_vartime(&tmp2, sig, &tmp3, sig + 32);
    ge_tobytes(buf + 64, &tmp2);
    xte_hash_to_scalar(buf, sizeof(buf), c);
    sc_sub(c, c, sig);
    return sc_isnonzero(c) == 0;
}

static void hash_to_ec(const uint8_t key[32], ge_p3 *res)
{
    uint8_t h[32];
    ge_p2 point;
    ge_p1p1 point2;
    xte_cn_fast_hash(key, 32, h);
    ge_fromfe_frombytes_vartime(&point, h);
    ge_mul8(&point2, &point);
    ge_p1p1_to_p3(res, &point2);
}

void xte_hash_to_point(const uint8_t *data, size_t len, uint8_t key[32])
{
    uint8_t h[32];
    ge_p2 point;
    ge_p1p1 point2;
    xte_cn_fast_hash(data, len, h);
    ge_fromfe_frombytes_vartime(&point, h);
    ge_mul8(&point2, &point);
    ge_p1p1_to_p2(&point, &point2);
    ge_tobytes(key, &point);
}

int xte_generate_key_image(const uint8_t pub[32], const uint8_t sec[32], uint8_t image[32])
{
    ge_p3 point;
    ge_p2 point2;
    if (sc_check(sec) != 0)
    {
        return 0;
    }
    hash_to_ec(pub, &point);
    ge_scalarmult(&point2, sec, &point);
    ge_tobytes(image, &point2);
    return 1;
}

/* rs_comm { Hash h; struct { EllipticCurvePoint a, b; } ab[]; } */
static size_t rs_comm_size(size_t count)
{
    return 32 + count * 64;
}

int xte_generate_ring_signatures(
    const uint8_t prefix_hash[32],
    const uint8_t key_image[32],
    const uint8_t *pubs,
    size_t count,
    const uint8_t sec[32],
    size_t real_index,
    uint8_t *sigs)
{
    ge_p3 image_unp;
    ge_dsmp image_pre;
    uint8_t sum[32], k[32], h[32];
    size_t i;
    int ok = 0;

    if (count == 0 || real_index >= count)
    {
        return 0;
    }

    uint8_t *buf = (uint8_t *)malloc(rs_comm_size(count));
    if (buf == NULL)
    {
        return 0;
    }

    memset(sigs, 0, count * 64);

    if (ge_frombytes_vartime(&image_unp, key_image) != 0)
    {
        goto done;
    }

    ge_dsm_precomp(image_pre, &image_unp);
    sc_0(sum);
    memcpy(buf, prefix_hash, 32);

    for (i = 0; i < count; i++)
    {
        ge_p2 tmp2;
        ge_p3 tmp3;
        uint8_t *a = buf + 32 + i * 64;
        uint8_t *b = a + 32;
        uint8_t *sig = sigs + i * 64;
        const uint8_t *pub = pubs + i * 32;

        if (i == real_index)
        {
            random_scalar(k);
            ge_scalarmult_base(&tmp3, k);
            ge_p3_tobytes(a, &tmp3);
            hash_to_ec(pub, &tmp3);
            ge_scalarmult(&tmp2, k, &tmp3);
            ge_tobytes(b, &tmp2);
        }
        else
        {
            random_scalar(sig);
            random_scalar(sig + 32);
            if (ge_frombytes_vartime(&tmp3, pub) != 0)
            {
                goto done;
            }
            ge_double_scalarmult_base_vartime(&tmp2, sig, &tmp3, sig + 32);
            ge_tobytes(a, &tmp2);
            hash_to_ec(pub, &tmp3);
            ge_double_scalarmult_precomp_vartime(&tmp2, sig + 32, &tmp3, sig, image_pre);
            ge_tobytes(b, &tmp2);
            sc_add(sum, sum, sig);
        }
    }

    xte_hash_to_scalar(buf, rs_comm_size(count), h);
    sc_sub(sigs + real_index * 64, h, sum);
    sc_mulsub(sigs + real_index * 64 + 32, sigs + real_index * 64, sec, k);
    ok = 1;

done:
    memset(k, 0, sizeof(k));
    free(buf);
    return ok;
}

int xte_check_ring_signature(
    const uint8_t prefix_hash[32],
    const uint8_t key_image[32],
    const uint8_t *pubs,
    size_t count,
    const uint8_t *sigs)
{
    ge_p3 image_unp;
    ge_dsmp image_pre;
    uint8_t sum[32], h[32];
    size_t i;
    int ok = 0;

    if (count == 0)
    {
        return 0;
    }

    uint8_t *buf = (uint8_t *)malloc(rs_comm_size(count));
    if (buf == NULL)
    {
        return 0;
    }

    if (ge_frombytes_vartime(&image_unp, key_image) != 0)
    {
        goto done;
    }
    ge_dsm_precomp(image_pre, &image_unp);
    if (ge_check_subgroup_precomp_vartime(image_pre) != 0)
    {
        goto done;
    }
    sc_0(sum);
    memcpy(buf, prefix_hash, 32);

    for (i = 0; i < count; i++)
    {
        ge_p2 tmp2;
        ge_p3 tmp3;
        uint8_t *a = buf + 32 + i * 64;
        uint8_t *b = a + 32;
        const uint8_t *sig = sigs + i * 64;
        const uint8_t *pub = pubs + i * 32;

        if (sc_check(sig) != 0 || sc_check(sig + 32) != 0)
        {
            goto done;
        }
        if (ge_frombytes_vartime(&tmp3, pub) != 0)
        {
            goto done;
        }
        ge_double_scalarmult_base_vartime(&tmp2, sig, &tmp3, sig + 32);
        ge_tobytes(a, &tmp2);
        hash_to_ec(pub, &tmp3);
        ge_double_scalarmult_precomp_vartime(&tmp2, sig + 32, &tmp3, sig, image_pre);
        ge_tobytes(b, &tmp2);
        sc_add(sum, sum, sig);
    }

    xte_hash_to_scalar(buf, rs_comm_size(count), h);
    sc_sub(h, h, sum);
    ok = sc_isnonzero(h) == 0;

done:
    free(buf);
    return ok;
}
