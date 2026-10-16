    .section .text
    .globl _start
    .option norvc
    .option norelax
_start:
    addi x20, x0, 0x123
    sw x20, 0(x0)       # RAM sentinel for address isolation
    lui x1, 0x10000      # MMIO base 0x10000000
    lw x11, 20(x1)      # UART idle: busy=0

    addi x2, x0, 0x41
    sw x2, 16(x1)       # first frame: 'A'
    lw x12, 20(x1)      # busy=1
    addi x2, x0, 0xa5
    sb x2, 16(x1)       # wait until first frame finishes
    lw x13, 20(x1)      # second frame busy=1
    addi x2, x0, 0x5a
    sw x2, 16(x1)       # wait until second frame finishes
    lw x14, 20(x1)      # third frame busy=1

    addi x2, x0, 0x33
    sb x2, 17(x1)       # high byte must not start a frame
    sw x2, 20(x1)       # STATUS write is ignored
    lw x15, 16(x1)      # reading TX_DATA returns 0

wait_last_frame:
    lw x16, 20(x1)
    bne x16, x0, wait_last_frame
    lw x17, 20(x1)      # busy=0 after all 3 frames

    lw x18, 0(x0)       # RAM must still contain 0x123
    addi x19, x0, 123   # completion signature
