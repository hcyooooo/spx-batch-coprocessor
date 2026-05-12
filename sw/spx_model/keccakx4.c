#include <stddef.h>
#include <stdint.h>

#include "keccakx4.h"

#define NROUNDS 24

static const uint64_t KeccakF_RoundConstants[NROUNDS] = {
    0x0000000000000001ULL, 0x0000000000008082ULL,
    0x800000000000808aULL, 0x8000000080008000ULL,
    0x000000000000808bULL, 0x0000000080000001ULL,
    0x8000000080008081ULL, 0x8000000000008009ULL,
    0x000000000000008aULL, 0x0000000000000088ULL,
    0x0000000080008009ULL, 0x000000008000000aULL,
    0x000000008000808bULL, 0x800000000000008bULL,
    0x8000000000008089ULL, 0x8000000000008003ULL,
    0x8000000000008002ULL, 0x8000000000000080ULL,
    0x000000000000800aULL, 0x800000008000000aULL,
    0x8000000080008081ULL, 0x8000000000008080ULL,
    0x0000000080000001ULL, 0x8000000080008008ULL
};

static const unsigned int KeccakF_RotationConstants[5][5] = {
    { 0, 36,  3, 41, 18},
    { 1, 44, 10, 45,  2},
    {62,  6, 43, 15, 61},
    {28, 55, 25, 21, 56},
    {27, 20, 39,  8, 14}
};

static uint64_t rol64(uint64_t a, unsigned int offset)
{
    if (offset == 0) {
        return a;
    }
    return (a << offset) | (a >> (64 - offset));
}

void keccak_f1600x4(uint64_t state[4][25])
{
    for (size_t round = 0; round < NROUNDS; round++) {
        uint64_t c[4][5];
        uint64_t d[4][5];
        uint64_t b[4][25];

        for (size_t lane = 0; lane < 4; lane++) {
            for (size_t x = 0; x < 5; x++) {
                c[lane][x] = state[lane][x] ^
                             state[lane][x + 5] ^
                             state[lane][x + 10] ^
                             state[lane][x + 15] ^
                             state[lane][x + 20];
            }
        }

        for (size_t lane = 0; lane < 4; lane++) {
            for (size_t x = 0; x < 5; x++) {
                d[lane][x] = c[lane][(x + 4) % 5] ^
                             rol64(c[lane][(x + 1) % 5], 1);
            }
        }

        for (size_t lane = 0; lane < 4; lane++) {
            for (size_t y = 0; y < 5; y++) {
                for (size_t x = 0; x < 5; x++) {
                    state[lane][x + 5 * y] ^= d[lane][x];
                }
            }
        }

        for (size_t lane = 0; lane < 4; lane++) {
            for (size_t y = 0; y < 5; y++) {
                for (size_t x = 0; x < 5; x++) {
                    const size_t src = x + 5 * y;
                    const size_t dst = y + 5 * ((2 * x + 3 * y) % 5);
                    b[lane][dst] = rol64(state[lane][src],
                                         KeccakF_RotationConstants[x][y]);
                }
            }
        }

        for (size_t lane = 0; lane < 4; lane++) {
            for (size_t y = 0; y < 5; y++) {
                for (size_t x = 0; x < 5; x++) {
                    state[lane][x + 5 * y] =
                        b[lane][x + 5 * y] ^
                        ((~b[lane][((x + 1) % 5) + 5 * y]) &
                         b[lane][((x + 2) % 5) + 5 * y]);
                }
            }
            state[lane][0] ^= KeccakF_RoundConstants[round];
        }
    }
}
