#ifndef _COMPLIANCE_MODEL_H
#define _COMPLIANCE_MODEL_H

#define RVMODEL_DATA_SECTION \
        .pushsection .tohost,"aw",@progbits;                \
        .align 8; .global tohost; tohost: .dword 0;          \
        .align 8; .global fromhost; fromhost: .dword 0;      \
        .popsection;

#define RVMODEL_BOOT

#define RVMODEL_ACCESS_FAULT_ADDRESS 0x00000000

#define RVMODEL_HALT_PASS \
  li x1, 0                 ;\
  li t0, 0x10000000        ;\
  write_tohost_pass:       ;\
    sw x1, 0(t0)           ;\
    sw x0, 4(t0)           ;\
  self_loop_pass:          ;\
    j self_loop_pass       ;\

#define RVMODEL_HALT_FAIL \
  li x1, 1                 ;\
  li t0, 0x10000000        ;\
  write_tohost_fail:       ;\
    sw x1, 0(t0)           ;\
    sw x0, 4(t0)           ;\
  self_loop_fail:          ;\
    j self_loop_fail       ;\

#define RVMODEL_IO_INIT(_R1, _R2, _R3)

#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR) \
1:                           ;                        \
  lbu  _R1, 0(_STR_PTR)      ;                        \
  beqz _R1, 3f               ;                        \
2:                           ;                        \
  li   _R2, 0x10000004       ;                        \
  sw   _R1, 0(_R2)           ;                        \
  addi _STR_PTR, _STR_PTR, 1 ;                        \
  j 1b                       ;                        \
3:

#define RVMODEL_MTIME_ADDRESS
#define RVMODEL_MTIMECMP_ADDRESS

#define RVMODEL_SET_MEXT_INT
#define RVMODEL_CLR_MEXT_INT
#define RVMODEL_SET_MSW_INT
#define RVMODEL_CLR_MSW_INT

#define RVMODEL_SET_SEXT_INT
#define RVMODEL_CLR_SEXT_INT
#define RVMODEL_SET_SSW_INT
#define RVMODEL_CLR_SSW_INT

#endif
