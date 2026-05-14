#include <stdint.h>

#define DESC_WORDS 8u
#define DESC_STORAGE_WORDS (DESC_WORDS + 4u)
#define PUB_SEED_WORDS 4u
#define ADDR_WORDS_TOTAL 32u
#define INPUT_WORDS_TOTAL 16u
#define OUTPUT_WORDS_TOTAL 16u

#define DESC_FLAGS_STATUS_WORD 0u
#define DESC_CONFIG_WORD 1u
#define DESC_PUB_SEED_PTR_WORD 2u
#define DESC_ADDR_BASE_WORD 3u
#define DESC_INPUT_BASE_WORD 4u
#define DESC_OUTPUT_BASE_WORD 5u
#define DESC_LENGTH_WORD 6u
#define DESC_CHAIN_CTRL_WORD 7u

#define DESC_CONFIG_VARIANT_SHAKE_128F_SIMPLE 0x00000100u
#define DESC_CONFIG_LANES_X4 0x00000040u
#define DESC_CONFIG_OP_TYPE_WOTS_CHAINX4 0x00010000u
#define DESC_CONFIG_OP_TYPE_BAD 0x007f0000u

#define STATUS_BUSY_BIT 0u
#define STATUS_DONE_BIT 1u
#define STATUS_ERROR_BIT 2u
#define STATUS_ERROR_CODE_LSB 4u

#define ERR_BAD_ALIGN 0x2u
#define ERR_MEM_READ 0x3u
#define ERR_MEM_WRITE 0x4u
#define ERR_BAD_OP_TYPE 0x5u
#define ERR_BAD_CHAIN 0x6u

#define SMOKE_MAGIC_ADDR ((volatile uint32_t *)0x0000fffcu)
#define SMOKE_MAGIC_FAIL 0x0000deadu
#define SMOKE_MAGIC_WOTS_ERROR_PASS 0x0000e42eu

#define SMOKE_STATS_ADDR ((volatile uint32_t *)0x0000ffe0u)
#define SMOKE_STAT_CASES_PASSED 0u
#define SMOKE_STAT_CASES_FAILED 1u
#define SMOKE_STAT_STATUS_POLLS 2u
#define SMOKE_STAT_ERROR_CASES_PASSED 3u
#define SMOKE_STAT_WORDS 4u

#define SMOKE_CTRL_ADDR ((volatile uint32_t *)0x0000ffd0u)
#define SMOKE_CTRL_NONE 0u
#define SMOKE_CTRL_READ_ERROR_ONCE 1u
#define SMOKE_CTRL_WRITE_ERROR_ONCE 2u

extern uint32_t __stack_top;

__attribute__((naked, section(".init"))) void _start(void)
{
    __asm__ volatile(
        "la sp, __stack_top\n"
        "call main\n"
        "1: j 1b\n");
}

static volatile uint32_t desc[DESC_STORAGE_WORDS] __attribute__((aligned(16)));
static volatile uint32_t pub_seed[PUB_SEED_WORDS] __attribute__((aligned(16)));
static volatile uint32_t addr[ADDR_WORDS_TOTAL] __attribute__((aligned(16)));
static volatile uint32_t input[INPUT_WORDS_TOTAL] __attribute__((aligned(16)));
static volatile uint32_t output[OUTPUT_WORDS_TOTAL] __attribute__((aligned(16)));

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

static void reset_stats(void)
{
    volatile uint32_t *stats = SMOKE_STATS_ADDR;

    for (uint32_t i = 0; i < SMOKE_STAT_WORDS; i++) {
        stats[i] = 0u;
    }
}

static void inc_stat(uint32_t index)
{
    volatile uint32_t *stats = SMOKE_STATS_ADDR;

    stats[index] = stats[index] + 1u;
}

static void clear_words(volatile uint32_t *dst, uint32_t words)
{
    for (uint32_t i = 0; i < words; i++) {
        dst[i] = 0u;
    }
}

static void setup_valid_wots_descriptor(uint32_t start_step, uint32_t num_steps)
{
    clear_words(desc, DESC_STORAGE_WORDS);
    clear_words(output, OUTPUT_WORDS_TOTAL);

    for (uint32_t i = 0; i < PUB_SEED_WORDS; i++) {
        pub_seed[i] = 0x21354789u ^ (i * 0x01010101u);
    }
    for (uint32_t i = 0; i < ADDR_WORDS_TOTAL; i++) {
        addr[i] = 0x90000000u ^ (i * 0x0103070bu);
    }
    for (uint32_t i = 0; i < INPUT_WORDS_TOTAL; i++) {
        input[i] = 0x10203040u + (i * 0x11111111u);
    }

    desc[DESC_FLAGS_STATUS_WORD] = 0u;
    desc[DESC_CONFIG_WORD] = DESC_CONFIG_OP_TYPE_WOTS_CHAINX4 |
                             DESC_CONFIG_VARIANT_SHAKE_128F_SIMPLE |
                             DESC_CONFIG_LANES_X4;
    desc[DESC_PUB_SEED_PTR_WORD] = ptr32(pub_seed);
    desc[DESC_ADDR_BASE_WORD] = ptr32(addr);
    desc[DESC_INPUT_BASE_WORD] = ptr32(input);
    desc[DESC_OUTPUT_BASE_WORD] = ptr32(output);
    desc[DESC_LENGTH_WORD] = DESC_WORDS;
    desc[DESC_CHAIN_CTRL_WORD] = ((num_steps & 0xffu) << 8) |
                                 (start_step & 0xffu);
}

static void fail_and_stop(void)
{
    inc_stat(SMOKE_STAT_CASES_FAILED);
    *SMOKE_CTRL_ADDR = SMOKE_CTRL_NONE;
    write_magic(SMOKE_MAGIC_FAIL);
    stop_forever();
}

static int check_descriptor_status(uint32_t descriptor_addr,
                                   uint32_t expected_code)
{
    volatile uint32_t *status_ptr =
        (volatile uint32_t *)(uintptr_t)descriptor_addr;
    uint32_t descriptor_status = status_ptr[0];
    uint32_t descriptor_code =
        (descriptor_status >> STATUS_ERROR_CODE_LSB) & 0xfu;

    if (((descriptor_status >> STATUS_DONE_BIT) & 1u) == 0u) {
        return -1;
    }
    if (((descriptor_status >> STATUS_ERROR_BIT) & 1u) == 0u) {
        return -2;
    }
    if (descriptor_code != expected_code) {
        return -3;
    }
    return 0;
}

static int expect_error_status(uint32_t descriptor_addr, uint32_t expected_code)
{
    uint32_t status;

    (void)spx_clear();
    (void)spx_set_desc(descriptor_addr);
    status = spx_start();
    if (((status >> STATUS_BUSY_BIT) & 1u) == 0u) {
        return -1;
    }

    for (uint32_t poll = 0; poll < 50000u; poll++) {
        status = spx_status();
        inc_stat(SMOKE_STAT_STATUS_POLLS);
        if (((status >> STATUS_DONE_BIT) & 1u) != 0u) {
            uint32_t observed_code;

            if (((status >> STATUS_ERROR_BIT) & 1u) == 0u) {
                return -2;
            }
            observed_code = (status >> STATUS_ERROR_CODE_LSB) & 0xfu;
            if (observed_code != expected_code) {
                return -3;
            }
            if (check_descriptor_status(descriptor_addr, expected_code) != 0) {
                return -4;
            }
            (void)spx_clear();
            return 0;
        }
    }

    return -5;
}

static void pass_error_case(void)
{
    inc_stat(SMOKE_STAT_ERROR_CASES_PASSED);
}

int main(void)
{
    write_magic(0u);
    reset_stats();
    *SMOKE_CTRL_ADDR = SMOKE_CTRL_NONE;

    setup_valid_wots_descriptor(0u, 1u);
    desc[DESC_CONFIG_WORD] = DESC_CONFIG_OP_TYPE_BAD |
                             DESC_CONFIG_VARIANT_SHAKE_128F_SIMPLE |
                             DESC_CONFIG_LANES_X4;
    if (expect_error_status(ptr32(desc), ERR_BAD_OP_TYPE) != 0) {
        fail_and_stop();
    }
    pass_error_case();

    setup_valid_wots_descriptor(0u, 0u);
    if (expect_error_status(ptr32(desc), ERR_BAD_CHAIN) != 0) {
        fail_and_stop();
    }
    pass_error_case();

    setup_valid_wots_descriptor(0u, 16u);
    if (expect_error_status(ptr32(desc), ERR_BAD_CHAIN) != 0) {
        fail_and_stop();
    }
    pass_error_case();

    setup_valid_wots_descriptor(15u, 2u);
    if (expect_error_status(ptr32(desc), ERR_BAD_CHAIN) != 0) {
        fail_and_stop();
    }
    pass_error_case();

    setup_valid_wots_descriptor(0u, 1u);
    if (expect_error_status(ptr32(desc) + 4u, ERR_BAD_ALIGN) != 0) {
        fail_and_stop();
    }
    pass_error_case();

    setup_valid_wots_descriptor(0u, 1u);
    *SMOKE_CTRL_ADDR = SMOKE_CTRL_READ_ERROR_ONCE;
    if (expect_error_status(ptr32(desc), ERR_MEM_READ) != 0) {
        fail_and_stop();
    }
    *SMOKE_CTRL_ADDR = SMOKE_CTRL_NONE;
    pass_error_case();

    setup_valid_wots_descriptor(0u, 1u);
    *SMOKE_CTRL_ADDR = SMOKE_CTRL_WRITE_ERROR_ONCE;
    if (expect_error_status(ptr32(desc), ERR_MEM_WRITE) != 0) {
        fail_and_stop();
    }
    *SMOKE_CTRL_ADDR = SMOKE_CTRL_NONE;
    pass_error_case();

    write_magic(SMOKE_MAGIC_WOTS_ERROR_PASS);
    stop_forever();
}
