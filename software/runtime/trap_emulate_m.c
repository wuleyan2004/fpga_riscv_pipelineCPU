/* RV32M 的八条寄存器指令由 RV32I 软件模拟。regs[n] 是异常入口保存的 xn。 */
typedef unsigned int u32;

static void product(u32 a, u32 b, u32 *low, u32 *high)
{
    u32 lo = 0, hi = 0, b_hi = 0;
    for (unsigned i = 0; i < 32; ++i) {
        if (a & 1) {
            u32 old = lo;
            lo += b;
            hi += b_hi + (lo < old);
        }
        b_hi = (b_hi << 1) | (b >> 31);
        b <<= 1;
        a >>= 1;
    }
    *low = lo;
    *high = hi;
}

static void quotient(u32 dividend, u32 divisor, u32 *q, u32 *r)
{
    u32 result = 0, rem = 0;
    if (divisor == 0) {
        *q = ~0u;
        *r = dividend;
        return;
    }
    for (unsigned i = 0; i < 32; ++i) {
        u32 carry = rem >> 31;
        rem = (rem << 1) | (dividend >> 31);
        dividend <<= 1;
        result <<= 1;
        if (carry || rem >= divisor) {
            rem -= divisor;
            result |= 1;
        }
    }
    *q = result;
    *r = rem;
}

__attribute__((used)) int trap_emulate_m(u32 instruction, u32 *regs)
{
    if ((instruction & 0xfe00007fu) != 0x02000033u)
        return 0;

    u32 funct3 = (instruction >> 12) & 7u;
    u32 rd = (instruction >> 7) & 31u;
    u32 a = regs[(instruction >> 15) & 31u];
    u32 b = regs[(instruction >> 20) & 31u];
    u32 lo, hi, q, r, value;

    if (funct3 < 4) {
        product(a, b, &lo, &hi);
        if (funct3 == 1 || funct3 == 2)
            hi -= (a >> 31) ? b : 0;
        if (funct3 == 1)
            hi -= (b >> 31) ? a : 0;
        value = funct3 == 0 ? lo : hi;
    } else {
        u32 a_negative = (funct3 == 4 || funct3 == 6) && (a >> 31);
        u32 b_negative = (funct3 == 4 || funct3 == 6) && (b >> 31);
        quotient(a_negative ? -a : a, b_negative ? -b : b, &q, &r);
        if (a_negative != b_negative && b != 0)
            q = -q;
        if (a_negative)
            r = -r;
        value = (funct3 == 4 || funct3 == 5) ? q : r;
    }
    if (rd != 0)
        regs[rd] = value;
    return 1;
}
