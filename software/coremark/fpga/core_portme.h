/* SPDX-License-Identifier: Apache-2.0
 * RV32I FPGA port of EEMBC CoreMark 1.0. Benchmark algorithms are unchanged.
 */
#ifndef CORE_PORTME_H
#define CORE_PORTME_H
#include <stddef.h>
#include <stdint.h>

/* 浮点运算由 libgcc 软件实现，不要求 CPU 有浮点指令。 */
#define HAS_FLOAT 1
#define HAS_TIME_H 0
#define USE_CLOCK 0
#define HAS_STDIO 0
#define HAS_PRINTF 0
#define COMPILER_VERSION "GCC " __VERSION__
#define COMPILER_FLAGS FLAGS_STR
#ifndef COREMARK_UART_GAP_CYCLES
#define COREMARK_UART_GAP_CYCLES 0
#endif
#define MEM_LOCATION "Static RAM; ROM:RAM:CPU clock 1:1:1"
typedef int16_t ee_s16;
typedef uint16_t ee_u16;
typedef int32_t ee_s32;
typedef double ee_f32;
typedef uint8_t ee_u8;
typedef uint32_t ee_u32;
typedef uintptr_t ee_ptr_int;
typedef size_t ee_size_t;
#define align_mem(x) (void *)(4 + (((ee_ptr_int)(x) - 1) & ~3u))

/* 64 位周期计数器除以 1024：tick 约 37.93 us，32 位 tick 约 45 小时回绕。 */
typedef ee_u32 CORE_TICKS;
#define SEED_METHOD SEED_VOLATILE
#define MEM_METHOD MEM_STATIC
#define MULTITHREAD 1
#define MAIN_HAS_NOARGC 1
#define MAIN_HAS_NORETURN 0
#define USE_PTHREAD 0
#define USE_FORK 0
#define USE_SOCKET 0
extern ee_u32 default_num_contexts;
typedef struct { ee_u8 portable_id; } core_portable;
void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);
int ee_printf(const char *fmt, ...);
#endif
