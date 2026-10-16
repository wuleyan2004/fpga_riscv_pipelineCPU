/* SPDX-License-Identifier: Apache-2.0 */
#include "coremark.h"

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
#else
volatile ee_s32 seed1_volatile = 0;
volatile ee_s32 seed2_volatile = 0;
#endif
volatile ee_s32 seed3_volatile = 0x66;
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;
ee_u32 default_num_contexts = 1;

#define MMIO32(addr) (*(volatile uint32_t *)(addr))
#define CYCLE_LO 0x10000020u
#define CYCLE_HI 0x10000024u
#define CLOCK_HZ 27000000u
#if COREMARK_PROFILE
#define PERF_CTRL        0x10000030u
#define PERF_CYCLES      0x10000034u
#define PERF_RETIRED     0x10000038u
#define PERF_MEM_WAIT    0x1000003cu
#define PERF_RAW_WAIT    0x10000040u
#define PERF_BRANCHES    0x10000044u
#define PERF_TAKEN       0x10000048u
#define PERF_BRANCH_COST 0x1000004cu
#define PERF_JUMP_COST   0x10000050u
#endif

volatile uint64_t measured_start_cycles;
volatile uint64_t measured_stop_cycles;
static CORE_TICKS start_ticks, stop_ticks;

static uint64_t read_cycles(void)
{
    uint32_t hi_before, lo, hi_after;
    /* 两次高位相同才接受低位，避免低 32 位回绕时读到混合值。 */
    do {
        hi_before = MMIO32(CYCLE_HI);
        lo = MMIO32(CYCLE_LO);
        hi_after = MMIO32(CYCLE_HI);
    } while (hi_before != hi_after);
    return ((uint64_t)hi_after << 32) | lo;
}

void start_time(void)
{
    uint64_t cycles = read_cycles();
    measured_start_cycles = cycles;
    start_ticks = (CORE_TICKS)(cycles >> 10);
#if COREMARK_PROFILE
    MMIO32(PERF_CTRL) = 1; /* 每次标定/正式迭代都清零，最终保留正式迭代结果。 */
#endif
}

void stop_time(void)
{
#if COREMARK_PROFILE
    MMIO32(PERF_CTRL) = 0;
#endif
    uint64_t cycles = read_cycles();
    measured_stop_cycles = cycles;
    stop_ticks = (CORE_TICKS)(cycles >> 10);
}

CORE_TICKS get_time(void) { return stop_ticks - start_ticks; }
secs_ret time_in_secs(CORE_TICKS ticks)
{
    return (secs_ret)ticks * 1024.0 / (secs_ret)CLOCK_HZ;
}

void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc;
    (void)argv;
    MMIO32(0x10000000u) = 1; /* 运行中 GPIO=01。 */
    ee_printf("CoreMark RV32I start; clock=27000000 Hz\n");
    if (sizeof(ee_ptr_int) != sizeof(void *) || sizeof(ee_u32) != 4)
        ee_printf("ERROR! CoreMark port data types\n");
    p->portable_id = 1;
}

void portable_fini(core_portable *p)
{
#if COREMARK_PROFILE
    ee_printf("PROFILE diagnostic counters (not an official score):\n");
    ee_printf("Profile cycles       : %lu\n", (unsigned long)MMIO32(PERF_CYCLES));
    ee_printf("Retired instructions : %lu\n", (unsigned long)MMIO32(PERF_RETIRED));
    ee_printf("Memory wait cycles   : %lu\n", (unsigned long)MMIO32(PERF_MEM_WAIT));
    ee_printf("RAW wait cycles      : %lu\n", (unsigned long)MMIO32(PERF_RAW_WAIT));
    ee_printf("Branch instructions  : %lu\n", (unsigned long)MMIO32(PERF_BRANCHES));
    ee_printf("Taken branches       : %lu\n", (unsigned long)MMIO32(PERF_TAKEN));
    ee_printf("Branch bubble cycles : %lu\n", (unsigned long)MMIO32(PERF_BRANCH_COST));
    ee_printf("Jump bubble cycles   : %lu\n", (unsigned long)MMIO32(PERF_JUMP_COST));
#endif
    p->portable_id = 0;
    /* GPIO=02 仅表示程序结束；是否有效须检查串口 CRC/时间输出。 */
    MMIO32(0x10000000u) = 2;
    /* 等待最后一个 UART 帧完整发送后，main 才返回。 */
    while (MMIO32(0x10000014u) & 1u) { }
}
