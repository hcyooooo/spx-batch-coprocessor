#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../fips202.h"
#include "../keccakx4.h"

#define TEST_ROUNDS 1024

static uint64_t prng_next(uint64_t *state)
{
    uint64_t x = *state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *state = x;
    return x;
}

static void fill_random_state(uint64_t state[4][25], uint64_t *seed)
{
    for (size_t lane = 0; lane < 4; lane++) {
        for (size_t i = 0; i < 25; i++) {
            state[lane][i] = prng_next(seed);
        }
    }
}

static int compare_case(uint64_t input[4][25], const char *label)
{
    uint64_t x4[4][25];
    uint64_t ref[4][25];

    memcpy(x4, input, sizeof(x4));
    memcpy(ref, input, sizeof(ref));

    keccak_f1600x4(x4);
    for (size_t lane = 0; lane < 4; lane++) {
        keccak_f1600(ref[lane]);
    }

    for (size_t lane = 0; lane < 4; lane++) {
        for (size_t i = 0; i < 25; i++) {
            if (x4[lane][i] != ref[lane][i]) {
                printf("FAIL keccak_f1600x4 %s: lane %zu word %zu\n",
                       label, lane, i);
                printf("  got      0x%016" PRIx64 "\n", x4[lane][i]);
                printf("  expected 0x%016" PRIx64 "\n", ref[lane][i]);
                return -1;
            }
        }
    }

    return 0;
}

int main(void)
{
    uint64_t seed = 0x123456789abcdef0ULL;
    uint64_t state[4][25];

    setbuf(stdout, NULL);

    memset(state, 0, sizeof(state));
    if (compare_case(state, "zero")) {
        return 1;
    }

    for (size_t lane = 0; lane < 4; lane++) {
        for (size_t i = 0; i < 25; i++) {
            state[lane][i] = UINT64_MAX;
        }
    }
    if (compare_case(state, "all-ones")) {
        return 1;
    }

    for (size_t round = 0; round < TEST_ROUNDS; round++) {
        fill_random_state(state, &seed);
        if (compare_case(state, "random")) {
            printf("  random round %zu failed\n", round);
            return 1;
        }
    }

    printf("PASS keccak_f1600x4 correctness (%u random rounds)\n",
           TEST_ROUNDS);
    return 0;
}
