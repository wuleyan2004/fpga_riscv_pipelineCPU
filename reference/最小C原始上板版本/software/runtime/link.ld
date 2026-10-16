/* 当前硬件：指令 ROM 1 KiB，数据 RAM 1 KiB，两个接口的地址都从 0 开始。 */
OUTPUT_ARCH(riscv)
OUTPUT_FORMAT("elf32-littleriscv")
ENTRY(_start)

MEMORY
{
    IROM (rx) : ORIGIN = 0x00000000, LENGTH = 1K
    RAM  (rw) : ORIGIN = 0x00000000, LENGTH = 1K
}

/* 最小 C 程序先预留 256 字节栈；CoreMark 的容量需编译后另外确定。 */
__stack_size = DEFINED(__stack_size) ? __stack_size : 256;
__stack_top = ORIGIN(RAM) + LENGTH(RAM);
__stack_bottom = __stack_top - __stack_size;

SECTIONS
{
    .text ORIGIN(IROM) :
    {
        KEEP(*(.text.startup.entry))
        *(.text .text.*)
        . = ALIGN(4);
        __text_end = .;
    } > IROM

    /*
     * .rodata 也放进 RAM：字符串、常量表经数据接口读取。
     * VMA 是运行地址；LMA 是初始副本在 RAM 中的预装地址。
     */
    .data ORIGIN(RAM) : AT(__data_load_start)
    {
        __data_start = .;
        *(.rodata .rodata.* .srodata .srodata.*)
        *(.data .data.* .sdata .sdata.*)
        *(.got .got.*)
        . = ALIGN(4);
        __data_end = .;
    } > RAM
    __global_pointer$ = __data_start + 0x800;

    .bss (NOLOAD) : AT(ADDR(.bss))
    {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss .bss.* .sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM

    /*
     * 副本必须在运行数据之后，且避开 ELF 中 .text 的装载地址范围。
     * 这样链接器可正常检查地址，生成 ROM/RAM 文件时分别提取各节。
     * 这个简单布局会在 RAM 中留出空隙，适合先验证小 C 程序。
     */
    __data_load_start = ALIGN(MAX(__text_end, __bss_end), 16);
    __data_load_end = __data_load_start + SIZEOF(.data);
    .ram_init __data_load_start (NOLOAD) : AT(__data_load_start)
    {
        . += SIZEOF(.data);
    } > RAM

    __heap_start = ALIGN(__data_load_end, 16);
    __heap_end = __stack_bottom;
    _end = __heap_start;
    end = _end;

    .stack __stack_bottom (NOLOAD) : AT(__stack_bottom)
    {
        . += __stack_size;
    } > RAM

    /* 该启动程序只支持普通单线程 C，不执行构造函数或初始化 TLS。 */
    .unsupported (NOLOAD) : AT(ADDR(.unsupported))
    {
        *(.preinit_array .preinit_array.* .init_array .init_array.*)
        *(.fini_array .fini_array.* .ctors .ctors.* .dtors .dtors.*)
        *(.tdata .tdata.* .tbss .tbss.*)
    } > RAM

    /DISCARD/ :
    {
        *(.comment .note .note.* .eh_frame .eh_frame.* .eh_frame_hdr)
    }

    ASSERT(_start == ORIGIN(IROM), "_start must be at reset address 0")
    ASSERT((__stack_size > 0) && ((__stack_size & 15) == 0),
           "stack size must be a positive multiple of 16")
    ASSERT((__stack_top & 15) == 0, "stack top must be 16-byte aligned")
    ASSERT(__stack_size <= LENGTH(RAM), "stack exceeds RAM capacity")
    ASSERT(__data_load_end <= __stack_bottom,
           "RAM too small: runtime data + initial copy + reserved stack")
    ASSERT(SIZEOF(.unsupported) == 0,
           "this startup does not support constructors or TLS")
}
