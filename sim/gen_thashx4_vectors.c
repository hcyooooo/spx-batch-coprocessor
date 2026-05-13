#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "keccakx4.h"

#define SPX_N 16u
#define SPX_ADDR_BYTES 32u
#define SHAKE256_RATE 136u
#define KECCAK_WORDS 25u
#define KECCAK_LANES 4u
#define KECCAK_VECTOR_CASES 128u
#define THASH_CASES_PER_INBLOCKS 100u

static uint64_t prng_next(uint64_t *state)
{
    uint64_t x = *state;

    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *state = x;
    return x;
}

static void fill_bytes(uint8_t *out, size_t outlen, uint64_t *seed)
{
    for (size_t i = 0; i < outlen; i++) {
        out[i] = (uint8_t)(prng_next(seed) & 0xffu);
    }
}

static uint64_t load64_le(const uint8_t *x)
{
    uint64_t r = 0;

    for (size_t i = 0; i < 8; i++) {
        r |= (uint64_t)x[i] << (8 * i);
    }

    return r;
}

static void print_bytes_hex(FILE *fp, const uint8_t *bytes, size_t len)
{
    for (size_t i = 0; i < len; i++) {
        const size_t idx = len - 1u - i;
        fprintf(fp, "%02x", bytes[idx]);
    }
}

static void print_state_hex(FILE *fp, const uint64_t state[KECCAK_WORDS])
{
    for (size_t i = 0; i < KECCAK_WORDS; i++) {
        const size_t idx = KECCAK_WORDS - 1u - i;
        fprintf(fp, "%016" PRIx64, state[idx]);
    }
}

static void squeeze_spx_n(uint8_t out[SPX_N], const uint64_t state[KECCAK_WORDS])
{
    for (size_t i = 0; i < SPX_N; i++) {
        out[i] = (uint8_t)(state[i >> 3] >> (8 * (i & 0x07u)));
    }
}

static void build_thash_block(uint8_t block[SHAKE256_RATE],
                              const uint8_t pub_seed[SPX_N],
                              const uint8_t addr[SPX_ADDR_BYTES],
                              const uint8_t input[2u * SPX_N],
                              unsigned int inblocks)
{
    const size_t inbytes = (size_t)inblocks * SPX_N;
    size_t offset = 0;

    memset(block, 0, SHAKE256_RATE);

    memcpy(block + offset, pub_seed, SPX_N);
    offset += SPX_N;
    memcpy(block + offset, addr, SPX_ADDR_BYTES);
    offset += SPX_ADDR_BYTES;
    memcpy(block + offset, input, inbytes);
    offset += inbytes;

    block[offset] = 0x1fu;
    block[SHAKE256_RATE - 1u] |= 0x80u;
}

static void make_path(char *path, size_t path_len,
                      const char *outdir, const char *filename)
{
    const int written = snprintf(path, path_len, "%s/%s", outdir, filename);

    if (written < 0 || (size_t)written >= path_len) {
        fprintf(stderr, "Output path is too long: %s/%s\n", outdir, filename);
        exit(1);
    }
}

static FILE *open_output(const char *outdir, const char *filename)
{
    char path[4096];
    FILE *fp;

    make_path(path, sizeof(path), outdir, filename);
    fp = fopen(path, "w");
    if (fp == NULL) {
        fprintf(stderr, "Failed to open %s: %s\n", path, strerror(errno));
        exit(1);
    }

    return fp;
}

static void write_keccak_vectors(const char *outdir)
{
    FILE *fp = open_output(outdir, "keccakx4_vectors.hex");
    uint64_t seed = 0x123456789abcdef0ULL;

    fprintf(fp, "%u\n", KECCAK_VECTOR_CASES);

    for (size_t case_id = 0; case_id < KECCAK_VECTOR_CASES; case_id++) {
        uint64_t input[KECCAK_LANES][KECCAK_WORDS];
        uint64_t expected[KECCAK_LANES][KECCAK_WORDS];

        for (size_t lane = 0; lane < KECCAK_LANES; lane++) {
            for (size_t word = 0; word < KECCAK_WORDS; word++) {
                if (case_id == 0) {
                    input[lane][word] = 0;
                } else if (case_id == 1) {
                    input[lane][word] = UINT64_MAX;
                } else {
                    input[lane][word] = prng_next(&seed);
                }
                expected[lane][word] = input[lane][word];
            }
        }

        keccak_f1600x4(expected);

        for (size_t lane = 0; lane < KECCAK_LANES; lane++) {
            print_state_hex(fp, input[lane]);
            fputc(' ', fp);
        }
        for (size_t lane = 0; lane < KECCAK_LANES; lane++) {
            print_state_hex(fp, expected[lane]);
            fputc(lane + 1u == KECCAK_LANES ? '\n' : ' ', fp);
        }
    }

    fclose(fp);
}

static void write_one_thash_phase(FILE *fp_inputs, FILE *fp_expected,
                                  unsigned int inblocks, uint64_t *seed)
{
    fprintf(fp_inputs, "%u\n", THASH_CASES_PER_INBLOCKS);

    for (size_t case_id = 0; case_id < THASH_CASES_PER_INBLOCKS; case_id++) {
        uint8_t pub_seed[SPX_N];
        uint8_t addr[KECCAK_LANES][SPX_ADDR_BYTES];
        uint8_t input[KECCAK_LANES][2u * SPX_N];
        uint8_t output[KECCAK_LANES][SPX_N];
        uint64_t state[KECCAK_LANES][KECCAK_WORDS] = {{0}};

        fill_bytes(pub_seed, sizeof(pub_seed), seed);
        for (size_t lane = 0; lane < KECCAK_LANES; lane++) {
            fill_bytes(addr[lane], sizeof(addr[lane]), seed);
            fill_bytes(input[lane], sizeof(input[lane]), seed);
            addr[lane][0] = (uint8_t)(0x40u + 0x11u * lane);
            input[lane][0] = (uint8_t)(0x10u + 0x22u * lane);
        }

        for (size_t lane = 0; lane < KECCAK_LANES; lane++) {
            uint8_t block[SHAKE256_RATE];

            build_thash_block(block, pub_seed, addr[lane],
                              input[lane], inblocks);

            for (size_t word = 0; word < SHAKE256_RATE / 8u; word++) {
                state[lane][word] = load64_le(block + 8u * word);
            }
        }

        keccak_f1600x4(state);

        for (size_t lane = 0; lane < KECCAK_LANES; lane++) {
            squeeze_spx_n(output[lane], state[lane]);
        }

        print_bytes_hex(fp_inputs, pub_seed, sizeof(pub_seed));
        fputc(' ', fp_inputs);
        for (size_t lane = 0; lane < KECCAK_LANES; lane++) {
            print_bytes_hex(fp_inputs, addr[lane], sizeof(addr[lane]));
            fputc(' ', fp_inputs);
        }
        for (size_t lane = 0; lane < KECCAK_LANES; lane++) {
            print_bytes_hex(fp_inputs, input[lane], sizeof(input[lane]));
            fputc(lane + 1u == KECCAK_LANES ? '\n' : ' ', fp_inputs);
        }

        fprintf(fp_expected, "%u ", inblocks);
        for (size_t lane = 0; lane < KECCAK_LANES; lane++) {
            print_bytes_hex(fp_expected, output[lane], sizeof(output[lane]));
            fputc(lane + 1u == KECCAK_LANES ? '\n' : ' ', fp_expected);
        }
    }
}

static void write_thash_vectors(const char *outdir)
{
    FILE *fp_ib1 = open_output(outdir, "thashx4_inblocks1.hex");
    FILE *fp_ib2 = open_output(outdir, "thashx4_inblocks2.hex");
    FILE *fp_expected = open_output(outdir, "thashx4_expected.hex");
    uint64_t seed = 0x0f1e2d3c4b5a6978ULL;

    fprintf(fp_expected, "%u\n", 2u * THASH_CASES_PER_INBLOCKS);
    write_one_thash_phase(fp_ib1, fp_expected, 1u, &seed);
    write_one_thash_phase(fp_ib2, fp_expected, 2u, &seed);

    fclose(fp_ib1);
    fclose(fp_ib2);
    fclose(fp_expected);
}

int main(int argc, char **argv)
{
    const char *outdir = (argc > 1) ? argv[1] : "sim/vectors";

    if (mkdir(outdir, 0777) != 0 && errno != EEXIST) {
        fprintf(stderr, "Failed to create %s: %s\n", outdir, strerror(errno));
        return 1;
    }

    write_keccak_vectors(outdir);
    write_thash_vectors(outdir);

    printf("Generated Keccak and thashx4 vectors in %s\n", outdir);
    return 0;
}
