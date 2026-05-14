#include <stdint.h>

#define DESC_WORDS 12u
#define PUB_SEED_WORDS 4u
#define ADDR_WORDS_TOTAL 32u
#define INPUT_WORDS_TOTAL_MAX 32u
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
#define STATUS_ERROR_CODE_LSB 4u

#define ERR_BAD_CONFIG 0x1u
#define ERR_BAD_ALIGN 0x2u
#define ERR_MEM_READ 0x3u
#define ERR_MEM_WRITE 0x4u

#define SMOKE_MAGIC_ADDR ((volatile uint32_t *)0x0000fffcu)
#define SMOKE_MAGIC_FAIL 0x0000deadu
#define SMOKE_MAGIC_ERROR_PASS 0x0000e55eu

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

static volatile uint32_t desc[DESC_WORDS] __attribute__((aligned(16)));
static volatile uint32_t pub_seed[PUB_SEED_WORDS] __attribute__((aligned(16)));
static volatile uint32_t addr[ADDR_WORDS_TOTAL] __attribute__((aligned(16)));
static volatile uint32_t input[INPUT_WORDS_TOTAL_MAX] __attribute__((aligned(16)));
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

static void setup_valid_descriptor(uint32_t inblocks)
{
    clear_words(desc, DESC_WORDS);
    clear_words(output, OUTPUT_WORDS_TOTAL);

    for (uint32_t i = 0; i < PUB_SEED_WORDS; i++) {
        pub_seed[i] = 0x11223344u + i * 0x01010101u;
    }
    for (uint32_t i = 0; i < ADDR_WORDS_TOTAL; i++) {
        addr[i] = 0x80000000u ^ (i * 0x0103070bu);
    }
    for (uint32_t i = 0; i < INPUT_WORDS_TOTAL_MAX; i++) {
        input[i] = 0x01020304u + i * 0x11111111u;
    }

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
}

static void fail_and_stop(void)
{
    inc_stat(SMOKE_STAT_CASES_FAILED);
    *SMOKE_CTRL_ADDR = SMOKE_CTRL_NONE;
    write_magic(SMOKE_MAGIC_FAIL);
    stop_forever();
}

static int expect_error_status(uint32_t start_addr, uint32_t expected_code)
{
    uint32_t status;

    (void)spx_clear();
    (void)spx_set_desc(start_addr);
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
            (void)spx_clear();
            return 0;
        }
    }

    return -4;
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

    setup_valid_descriptor(1u);
    desc[DESC_CONFIG_WORD] = DESC_CONFIG_VARIANT_SHAKE_128F_SIMPLE |
                             DESC_CONFIG_LANES_X4 | 3u;
    if (expect_error_status(ptr32(desc), ERR_BAD_CONFIG) != 0) {
        fail_and_stop();
    }
    pass_error_case();

    setup_valid_descriptor(1u);
    if (expect_error_status(ptr32(desc) + 4u, ERR_BAD_ALIGN) != 0) {
        fail_and_stop();
    }
    pass_error_case();

    setup_valid_descriptor(1u);
    *SMOKE_CTRL_ADDR = SMOKE_CTRL_READ_ERROR_ONCE;
    if (expect_error_status(ptr32(desc), ERR_MEM_READ) != 0) {
        fail_and_stop();
    }
    *SMOKE_CTRL_ADDR = SMOKE_CTRL_NONE;
    pass_error_case();

    setup_valid_descriptor(1u);
    *SMOKE_CTRL_ADDR = SMOKE_CTRL_WRITE_ERROR_ONCE;
    if (expect_error_status(ptr32(desc), ERR_MEM_WRITE) != 0) {
        fail_and_stop();
    }
    *SMOKE_CTRL_ADDR = SMOKE_CTRL_NONE;
    pass_error_case();

    write_magic(SMOKE_MAGIC_ERROR_PASS);
    stop_forever();
}
