@ ============================================================================
@ api_fpga.s - Final Version
@ ============================================================================
.syntax unified
.arch armv7-a
.text
.align 2

#include "constantes.h"

.extern open
.extern mmap
.extern munmap
.extern close
.extern perror

.global setup_memory_map
.global cleanup_memory_map
.global coproc_write_pixel
.global coproc_read_pixel
.global coproc_apply_zoom
.global coproc_reset_image
.global coproc_wait_done
.global coproc_apply_zoom_with_offset
.global coproc_update_mouse
.global coproc_set_window_start
.global coproc_set_window_end
.global coproc_set_window_active

.data
.align 4
g_fd_mem: .word -1
g_virtual_base: .word 0
g_pio_instruct_ptr: .word 0
g_pio_enable_ptr: .word 0
g_pio_dataout_ptr: .word 0
g_pio_flags_ptr: .word 0

str_dev_mem: .asciz "/dev/mem"

.text

.type pio_pulse_enable, %function
pio_pulse_enable:
    push {r0, r1, lr}
    ldr r0, =g_pio_enable_ptr
    ldr r0, [r0]
    mov r1, #1
    str r1, [r0]
    mov r1, #0
    str r1, [r0]
    pop {r0, r1, pc}
.size pio_pulse_enable, .-pio_pulse_enable

.type setup_memory_map, %function
setup_memory_map:
    push {r4-r8, lr}
    ldr r0, =str_dev_mem
    ldr r1, =(0x2 | 0x1000)
    bl open
    ldr r1, =g_fd_mem
    str r0, [r1]
    mov r4, r0
    
    mov r0, #0
    ldr r1, =LW_BRIDGE_SPAN
    mov r2, #3
    mov r3, #1
    str r4, [sp]
    ldr r5, =LW_BRIDGE_BASE
    str r5, [sp, #4]
    bl mmap
    
    ldr r1, =g_virtual_base
    str r0, [r1]
    mov r5, r0
    
    ldr r1, =PIO_INSTRUCT_OFFSET
    add r6, r5, r1
    ldr r7, =g_pio_instruct_ptr
    str r6, [r7]
    
    ldr r1, =PIO_ENABLE_OFFSET
    add r6, r5, r1
    ldr r7, =g_pio_enable_ptr
    str r6, [r7]

    ldr r1, =PIO_DATAOUT_OFFSET
    add r6, r5, r1
    ldr r7, =g_pio_dataout_ptr
    str r6, [r7]
    
    ldr r1, =PIO_FLAGS_OFFSET
    add r6, r5, r1
    ldr r7, =g_pio_flags_ptr
    str r6, [r7]

    mov r0, #0
    pop {r4-r8, pc}
.size setup_memory_map, .-setup_memory_map

.type cleanup_memory_map, %function
cleanup_memory_map:
    push {r4, lr}
    ldr r0, =g_virtual_base
    ldr r0, [r0]
    ldr r1, =LW_BRIDGE_SPAN
    bl munmap
    ldr r0, =g_fd_mem
    ldr r0, [r0]
    bl close
    pop {r4, pc}
.size cleanup_memory_map, .-cleanup_memory_map

.type coproc_wait_done, %function
coproc_wait_done:
    push {r0, r1, lr}
    ldr r0, =g_pio_flags_ptr
    ldr r0, [r0]
wait_loop$:
    ldr r1, [r0]
    ldr r2, =FLAG_DONE_MASK
    tst r1, r2
    beq wait_loop$
    pop {r0, r1, pc}
.size coproc_wait_done, .-coproc_wait_done

.type coproc_apply_zoom, %function
coproc_apply_zoom:
    push {r0, r1, lr}
    ldr r1, =g_pio_instruct_ptr
    ldr r1, [r1]
    str r0, [r1]
    bl pio_pulse_enable
    pop {r0, r1, pc}
.size coproc_apply_zoom, .-coproc_apply_zoom

.type coproc_reset_image, %function
coproc_reset_image:
    push {r0, lr}
    ldr r0, =g_pio_instruct_ptr
    ldr r0, [r0]
    ldr r1, =OP_RESET
    str r1, [r0]
    bl pio_pulse_enable
    pop {r0, pc}
.size coproc_reset_image, .-coproc_reset_image

.type coproc_write_pixel, %function
coproc_write_pixel:
    push {r0-r3, lr}
    ldr r3, =OP_STORE
    lsl r0, r0, #3
    orr r3, r3, r0
    lsl r1, r1, #21
    orr r3, r3, r1
    ldr r2, =g_pio_instruct_ptr
    ldr r2, [r2]
    str r3, [r2]
    bl pio_pulse_enable
    pop {r0-r3, pc}
.size coproc_write_pixel, .-coproc_write_pixel

.type coproc_read_pixel, %function
coproc_read_pixel:
    push {r1-r4, lr}
    ldr r3, =OP_LOAD
    lsl r0, r0, #3
    orr r3, r3, r0
    lsl r1, r1, #20
    orr r3, r3, r1
    ldr r2, =g_pio_instruct_ptr
    ldr r2, [r2]
    str r3, [r2]
    bl pio_pulse_enable
    bl coproc_wait_done
    ldr r4, =g_pio_dataout_ptr
    ldr r4, [r4]
    ldr r0, [r4]
    uxtb r0, r0
    pop {r1-r4, pc}
.size coproc_read_pixel, .-coproc_read_pixel

.type coproc_apply_zoom_with_offset, %function
coproc_apply_zoom_with_offset:
    push {r0-r4, lr}
    ldr r3, =g_pio_instruct_ptr
    ldr r3, [r3]
    mov r4, r0
    lsl r1, r1, #3
    orr r4, r4, r1
    lsl r2, r2, #21
    orr r4, r4, r2
    str r4, [r3]
    bl pio_pulse_enable
    pop {r0-r4, pc}
.size coproc_apply_zoom_with_offset, .-coproc_apply_zoom_with_offset

.type coproc_update_mouse, %function
coproc_update_mouse: 
    push {r0-r3, lr}
    mov r3, #0
    orr r3, r3, #(1 << 20)
    lsl r0, r0, #3
    orr r3, r3, r0
    lsl r1, r1, #21
    orr r3, r3, r1
    ldr r2, =g_pio_instruct_ptr
    ldr r2, [r2]
    str r3, [r2]
    bl pio_pulse_enable
    pop {r0-r3, pc}
.size coproc_update_mouse, .-coproc_update_mouse

.type coproc_set_window_start, %function
coproc_set_window_start:
    push {r0-r3, lr}
    mov r3, #0
    orr r3, r3, #(1 << 20)
    orr r3, r3, #(1 << 18)
    lsl r0, r0, #3
    orr r3, r3, r0
    lsl r1, r1, #21
    orr r3, r3, r1
    ldr r2, =g_pio_instruct_ptr
    ldr r2, [r2]
    str r3, [r2]
    bl pio_pulse_enable
    pop {r0-r3, pc}
.size coproc_set_window_start, .-coproc_set_window_start

.type coproc_set_window_end, %function
coproc_set_window_end:
    push {r0-r3, lr}
    mov r3, #0
    orr r3, r3, #(1 << 20)
    orr r3, r3, #(1 << 19)
    lsl r0, r0, #3
    orr r3, r3, r0
    lsl r1, r1, #21
    orr r3, r3, r1
    ldr r2, =g_pio_instruct_ptr
    ldr r2, [r2]
    str r3, [r2]
    bl pio_pulse_enable
    pop {r0-r3, pc}
.size coproc_set_window_end, .-coproc_set_window_end

.type coproc_set_window_active, %function
coproc_set_window_active:
    push {r0-r3, lr}
    mov r3, #0
    orr r3, r3, #(1 << 20)
    orr r3, r3, #(3 << 18)
    lsl r0, r0, #21
    orr r3, r3, r0
    ldr r2, =g_pio_instruct_ptr
    ldr r2, [r2]
    str r3, [r2]
    bl pio_pulse_enable
    pop {r0-r3, pc}
.size coproc_set_window_active, .-coproc_set_window_active