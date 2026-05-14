#include <stdint.h>

#define DESC_WORDS 12u
#define PUB_SEED_WORDS 4u
#define ADDR_WORDS_PER_LANE 8u
#define ADDR_WORDS_TOTAL 32u
#define INPUT_WORDS_PER_LANE_MAX 8u
#define INPUT_WORDS_TOTAL_MAX 32u
#define OUTPUT_WORDS_PER_LANE 4u
#define OUTPUT_WORDS_TOTAL 16u

#define DESC_FLAGS_STATUS_WORD 0u
#define DESC_CONFIG_WORD 1u
#define DESC_PUB_SEED_PTR_WORD 2u
#define DESC_ADDR_BASE_WORD 3u
#define DESC_INPUT_BASE_WORD 4u
#define DESC_OUTPUT_BASE_WORD 5u
#define DESC_LENGTH_WORD 6u
#define DESC_INLINE_SEED_WORD 8u

#define DESC_CONFIG_VARIANT_SHAKE_128F_SIMPLE 0x00000100u
#define DESC_CONFIG_LANES_X4 0x00000040u

#define STATUS_BUSY_BIT 0u
#define STATUS_DONE_BIT 1u
#define STATUS_ERROR_BIT 2u

#define SMOKE_MAGIC_ADDR ((volatile uint32_t *)0x0000fffcu)
#define SMOKE_MAGIC_PASS 0x00000001u
#define SMOKE_MAGIC_FAIL 0x0000deadu

extern uint32_t __stack_top;

__attribute__((naked, section(".init"))) void _start(void)
{
    __asm__ volatile(
        "la sp, __stack_top\n"
        "call main\n"
        "1: j 1b\n");
}

static volatile uint32_t desc[DESC_WORDS] __attribute__((aligned(16)));
static volatile uint32_t pub_seed[PUB_SEED_WORDS] __attribute__((aligned(16)));
static volatile uint32_t addr[ADDR_WORDS_TOTAL] __attribute__((aligned(16)));
static volatile uint32_t input[INPUT_WORDS_TOTAL_MAX] __attribute__((aligned(16)));
static volatile uint32_t output[OUTPUT_WORDS_TOTAL] __attribute__((aligned(16)));

static const uint32_t case1_pub_seed[PUB_SEED_WORDS] = {
    0x8a892daa, 0x45796b59, 0xeef5a4af, 0x042c997b
};

static const uint32_t case1_addr[ADDR_WORDS_TOTAL] = {
    0xfe142240, 0x14ad8e9f, 0x8c2e123a, 0x3695aed1,
    0xd10ddc7c, 0x7e764a3e, 0xbbc29f96, 0x84c97b86,
    0xd5842051, 0x2887ac64, 0xf48d8014, 0xa7e670f1,
    0x2c4897de, 0x9adf679e, 0x73d49b17, 0x2ed9130f,
    0x20d73162, 0xdfaee7ac, 0x1e0c89de, 0x8f8aa3a4,
    0x3cf35be0, 0x9e8505c2, 0xec6c28cb, 0xab577d65,
    0x98fbae73, 0x526a66c1, 0xedbe1e54, 0x9e9fd040,
    0xf444b97f, 0xa2f30517, 0x4ad79efd, 0xa2e3d02e
};

static const uint32_t case1_input[INPUT_WORDS_TOTAL_MAX] = {
    0x4c812b10, 0x1be86218, 0x3cb990ad, 0x759a1a18,
    0x5b4dc632, 0x128de8cb, 0x38e79c7a, 0x11ec3e16,
    0x92ab0954, 0x3cb32779, 0xabda5410, 0xe9c8cdd6,
    0xa6047076, 0x6f774505, 0xdadda0ef, 0xd5d6f11d
};

static const uint32_t case1_expected[OUTPUT_WORDS_TOTAL] = {
    0xa2889d8e, 0xbe051045, 0x1d795d4d, 0xf4219c4e,
    0x5994492b, 0xce4673d7, 0xf480b229, 0xc520622a,
    0x0d00b777, 0x4ef9120e, 0xa3149280, 0x66d772cc,
    0x8858e994, 0x71c68862, 0xf73b0e8a, 0x3ef5cad1
};

static const uint32_t case2_pub_seed[PUB_SEED_WORDS] = {
    0x97eed975, 0x82e361b2, 0xf6303e85, 0xfc6cdd0b
};

static const uint32_t case2_addr[ADDR_WORDS_TOTAL] = {
    0xb98e6240, 0xe4d98a38, 0x3d8a1cbf, 0x88b9d0b7,
    0x5f292301, 0xcf73fe8f, 0xc81489fc, 0xfd61aab3,
    0x34484a51, 0xbfd0c3aa, 0x05bc4c54, 0x23b0bb05,
    0x6ae5ecaf, 0x7fd63848, 0x29ae20bb, 0xb10becd1,
    0x132f9662, 0x951de497, 0x84543656, 0xfeb1e0db,
    0x30e93d19, 0x528713ba, 0x432de40e, 0xd7f48d39,
    0x6ffc1e73, 0x86998ced, 0xd04ac90f, 0x657994dd,
    0x75c824e1, 0x603450d3, 0xebe297cc, 0xbcf3c652
};

static const uint32_t case2_input[INPUT_WORDS_TOTAL_MAX] = {
    0x7e662a10, 0x53826010, 0xe3b2d36b, 0x60ed4190,
    0x3804c9e4, 0x32bbb45a, 0xf94fe444, 0x9b3f0da2,
    0x6d518432, 0xd40caf77, 0xaff2ff61, 0xe5c46066,
    0x6c38f39e, 0x51fc401a, 0xf84676e3, 0x77c69701,
    0x51150154, 0xd1292b1f, 0x168f7fec, 0xd731e220,
    0xf26289c4, 0x184e3cf9, 0x97d2e3da, 0x5d84380e,
    0xb7da7076, 0xaef5ae44, 0x53f46ed3, 0x7f8220f1,
    0xe2765c91, 0xec14ab5b, 0x78dd8ced, 0x5bccd5da
};

static const uint32_t case2_expected[OUTPUT_WORDS_TOTAL] = {
    0xc1073eba, 0x05a76adb, 0x8c1495d6, 0x859f101a,
    0xdc8aeb70, 0xb26b335f, 0xdc454c32, 0xf4d21104,
    0x4abe53ad, 0x5882eb3e, 0x94eb5fc8, 0x6ca199b2,
    0x9683b27e, 0xb36c4a7b, 0xfe149327, 0xe4f75ffe
};

static inline uint32_t spx_set_desc(uint32_t desc_addr)
{
    uint32_t rd;
    __asm__ volatile(
        ".insn r 0x0b, 0, 0x5a, %0, %1, x0"
        : "=r"(rd)
        : "r"(desc_addr)
        : "memory");
    return rd;
}

static inline uint32_t spx_start(void)
{
    uint32_t rd;
    __asm__ volatile(
        ".insn r 0x0b, 1, 0x5a, %0, x0, x0"
        : "=r"(rd)
        :
        : "memory");
    return rd;
}

static inline uint32_t spx_status(void)
{
    uint32_t rd;
    __asm__ volatile(
        ".insn r 0x0b, 2, 0x5a, %0, x0, x0"
        : "=r"(rd)
        :
        : "memory");
    return rd;
}

static inline uint32_t spx_clear(void)
{
    uint32_t rd;
    __asm__ volatile(
        ".insn r 0x0b, 3, 0x5a, %0, x0, x0"
        : "=r"(rd)
        :
        : "memory");
    return rd;
}

static void write_magic(uint32_t value)
{
    *SMOKE_MAGIC_ADDR = value;
}

static void stop_forever(void)
{
    for (;;) {
        __asm__ volatile("nop");
    }
}

static uint32_t ptr32(const volatile uint32_t *ptr)
{
    return (uint32_t)(uintptr_t)ptr;
}

static void copy_words(volatile uint32_t *dst, const uint32_t *src,
                       uint32_t words)
{
    for (uint32_t i = 0; i < words; i++) {
        dst[i] = src[i];
    }
}

static void clear_words(volatile uint32_t *dst, uint32_t words)
{
    for (uint32_t i = 0; i < words; i++) {
        dst[i] = 0u;
    }
}

static int compare_words(const volatile uint32_t *got, const uint32_t *expected,
                         uint32_t words)
{
    for (uint32_t i = 0; i < words; i++) {
        if (got[i] != expected[i]) {
            return -1;
        }
    }
    return 0;
}

static int run_case(uint32_t inblocks, const uint32_t *seed_words,
                    const uint32_t *addr_words, const uint32_t *input_words,
                    const uint32_t *expected_words)
{
    uint32_t status;
    const uint32_t input_words_per_lane = inblocks * 4u;
    const uint32_t input_words_total = input_words_per_lane * 4u;

    clear_words(desc, DESC_WORDS);
    clear_words(output, OUTPUT_WORDS_TOTAL);
    copy_words(pub_seed, seed_words, PUB_SEED_WORDS);
    copy_words(addr, addr_words, ADDR_WORDS_TOTAL);
    copy_words(input, input_words, input_words_total);

    desc[DESC_FLAGS_STATUS_WORD] = 0u;
    desc[DESC_CONFIG_WORD] = DESC_CONFIG_VARIANT_SHAKE_128F_SIMPLE |
                             DESC_CONFIG_LANES_X4 |
                             (inblocks & 0x3u);
    desc[DESC_PUB_SEED_PTR_WORD] = ptr32(pub_seed);
    desc[DESC_ADDR_BASE_WORD] = ptr32(addr);
    desc[DESC_INPUT_BASE_WORD] = ptr32(input);
    desc[DESC_OUTPUT_BASE_WORD] = ptr32(output);
    desc[DESC_LENGTH_WORD] = 8u;
    desc[DESC_INLINE_SEED_WORD] = 0u;

    (void)spx_clear();
    (void)spx_set_desc(ptr32(desc));
    status = spx_start();
    if (((status >> STATUS_BUSY_BIT) & 1u) == 0u) {
        return -1;
    }

    for (uint32_t poll = 0; poll < 50000u; poll++) {
        status = spx_status();
        if (((status >> STATUS_DONE_BIT) & 1u) != 0u) {
            if (((status >> STATUS_ERROR_BIT) & 1u) != 0u) {
                return -2;
            }
            if (compare_words(output, expected_words, OUTPUT_WORDS_TOTAL) != 0) {
                return -3;
            }
            (void)spx_clear();
            return 0;
        }
    }

    return -4;
}

int main(void)
{
    int rc;

    write_magic(0u);

    rc = run_case(1u, case1_pub_seed, case1_addr, case1_input, case1_expected);
    if (rc != 0) {
        write_magic(SMOKE_MAGIC_FAIL);
        stop_forever();
    }

    rc = run_case(2u, case2_pub_seed, case2_addr, case2_input, case2_expected);
    if (rc != 0) {
        write_magic(SMOKE_MAGIC_FAIL);
        stop_forever();
    }

    write_magic(SMOKE_MAGIC_PASS);
    stop_forever();
}
