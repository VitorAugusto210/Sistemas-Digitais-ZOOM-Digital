#ifndef FPGA_CONSTANTS_H
#define FPGA_CONSTANTS_H

/*
 * =================================================================
 * Constantes do Hardware da FPGA para o HPS
 * =================================================================
 */

// =================================================================
// Definições da Bridge HPS-para-FPGA
// =================================================================
#define LW_BRIDGE_BASE      0xFF200000
#define LW_BRIDGE_SPAN      0x1000

// Offsets dos PIOs
#define PIO_INSTRUCT_OFFSET 0x00000030
#define PIO_ENABLE_OFFSET   0x00000020
#define PIO_DATAOUT_OFFSET  0x00000010
#define PIO_FLAGS_OFFSET    0x00000000

// =================================================================
// Endereços Base (Para Assembly)
// =================================================================
#define PIO_INSTRUCT_BASE   (LW_BRIDGE_BASE + PIO_INSTRUCT_OFFSET)
#define PIO_ENABLE_BASE     (LW_BRIDGE_BASE + PIO_ENABLE_OFFSET)
#define PIO_DATAOUT_BASE    (LW_BRIDGE_BASE + PIO_DATAOUT_OFFSET)
#define PIO_FLAGS_BASE      (LW_BRIDGE_BASE + PIO_FLAGS_OFFSET)

// =================================================================
// Opcodes
// =================================================================
#define OP_REFRESH_SCREEN 0x0 
#define OP_LOAD           0x1 
#define OP_STORE          0x2 
#define OP_NHI_ALG        0x3 
#define OP_PR_ALG         0x4 
#define OP_BA_ALG         0x5 
#define OP_NH_ALG         0x6 
#define OP_RESET          0x7 

// =================================================================
// Sub-comandos de Janela (Bits 19:18 quando Opcode = 0)
// =================================================================
#define SUBCMD_UPDATE_MOUSE    0x0 
#define SUBCMD_SET_WIN_START   0x1 
#define SUBCMD_SET_WIN_END     0x2 
#define SUBCMD_SET_WIN_ACTIVE  0x3 

// =================================================================
// Flags
// =================================================================
#define FLAG_DONE_MASK    0x1 
#define FLAG_ERROR_MASK   0x2 
#define FLAG_ZMAX_MASK    0x4 
#define FLAG_ZMIN_MASK    0x8 

#endif // FPGA_CONSTANTS_H