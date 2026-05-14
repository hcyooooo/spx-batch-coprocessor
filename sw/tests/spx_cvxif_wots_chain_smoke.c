#include <stdint.h>

#define DESC_WORDS 8u
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

#define STATUS_BUSY_BIT 0u
#define STATUS_DONE_BIT 1u
#define STATUS_ERROR_BIT 2u

#define SMOKE_MAGIC_ADDR ((volatile uint32_t *)0x0000fffcu)
#define SMOKE_MAGIC_PASS 0x00000001u
#define SMOKE_MAGIC_FAIL 0x0000deadu

#define SMOKE_STATS_ADDR ((volatile uint32_t *)0x0000ffe0u)
#define SMOKE_STAT_CASES_PASSED 0u
#define SMOKE_STAT_CASES_FAILED 1u
#define SMOKE_STAT_STATUS_POLLS 2u
#define SMOKE_STAT_ERROR_CASES_PASSED 3u
#define SMOKE_STAT_WORDS 4u

#define WOTS_VECTOR_TABLE_ADDR ((volatile const uint32_t *)0x00008000u)
#define WOTS_VECTOR_TABLE_MAGIC 0x53505857u
#define WOTS_VECTOR_HEADER_WORDS 4u
#define WOTS_VECTOR_CASE_WORDS 70u
#define WOTS_VECTOR_REQUIRED_CASES 5u

#define CASE_START_STEP_WORD 0u
#define CASE_NUM_STEPS_WORD 1u
#define CASE_PUB_SEED_WORD 2u
#define CASE_ADDR_WORD (CASE_PUB_SEED_WORD + PUB_SEED_WORDS)
#define CASE_INPUT_WORD (CASE_ADDR_WORD + ADDR_WORDS_TOTAL)
#define CASE_EXPECTED_WORD (CASE_INPUT_WORD + INPUT_WORDS_TOTAL)

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

static void copy_words(volatile uint32_t *dst, const volatile uint32_t *src,
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

static int compare_words(const volatile uint32_t *got,
                         const volatile uint32_t *expected, uint32_t words)
{
    for (uint32_t i = 0; i < words; i++) {
        if (got[i] != expected[i]) {
            return -1;
        }
    }
    return 0;
}

static int valid_chain_window(uint32_t start_step, uint32_t num_steps)
{
    if (num_steps == 0u || num_steps > 15u) {
        return 0;
    }
    if (start_step >= 16u) {
        return 0;
    }
    if ((start_step + num_steps) > 16u) {
        return 0;
    }
    return 1;
}

static int run_case(const volatile uint32_t *case_words)
{
    uint32_t status;
    const uint32_t start_step = case_words[CASE_START_STEP_WORD];
    const uint32_t num_steps = case_words[CASE_NUM_STEPS_WORD];

    if (!valid_chain_window(start_step, num_steps)) {
        return -1;
    }

    clear_words(desc, DESC_WORDS);
    clear_words(output, OUTPUT_WORDS_TOTAL);
    copy_words(pub_seed, case_words + CASE_PUB_SEED_WORD, PUB_SEED_WORDS);
    copy_words(addr, case_words + CASE_ADDR_WORD, ADDR_WORDS_TOTAL);
    copy_words(input, case_words + CASE_INPUT_WORD, INPUT_WORDS_TOTAL);

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

    (void)spx_clear();
    (void)spx_set_desc(ptr32(desc));
    status = spx_start();
    if (((status >> STATUS_BUSY_BIT) & 1u) == 0u) {
        return -2;
    }

    for (uint32_t poll = 0; poll < 100000u; poll++) {
        status = spx_status();
        inc_stat(SMOKE_STAT_STATUS_POLLS);
        if (((status >> STATUS_DONE_BIT) & 1u) != 0u) {
            if (((status >> STATUS_ERROR_BIT) & 1u) != 0u) {
                return -3;
            }
            if (compare_words(output, case_words + CASE_EXPECTED_WORD,
                              OUTPUT_WORDS_TOTAL) != 0) {
                return -4;
            }
            (void)spx_clear();
            return 0;
        }
    }

    return -5;
}

static void fail_and_stop(void)
{
    inc_stat(SMOKE_STAT_CASES_FAILED);
    write_magic(SMOKE_MAGIC_FAIL);
    stop_forever();
}

int main(void)
{
    const volatile uint32_t *table = WOTS_VECTOR_TABLE_ADDR;
    const volatile uint32_t *case_words;
    uint32_t cases;
    uint32_t case_stride;

    write_magic(0u);
    reset_stats();

    if (table[0] != WOTS_VECTOR_TABLE_MAGIC) {
        fail_and_stop();
    }

    cases = table[1];
    case_stride = table[2];

    if ((cases < WOTS_VECTOR_REQUIRED_CASES) ||
        (case_stride != WOTS_VECTOR_CASE_WORDS)) {
        fail_and_stop();
    }

    case_words = table + WOTS_VECTOR_HEADER_WORDS;
    for (uint32_t case_id = 0; case_id < cases; case_id++) {
        if (run_case(case_words) != 0) {
            fail_and_stop();
        }
        inc_stat(SMOKE_STAT_CASES_PASSED);
        case_words += case_stride;
    }

    write_magic(SMOKE_MAGIC_PASS);
    stop_forever();
}
