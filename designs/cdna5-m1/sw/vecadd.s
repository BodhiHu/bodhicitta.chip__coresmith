; vecadd: C[0..31] = A[0..31] + B[0..31]
; A at 0x1000, B at 0x2000, C at 0x3000
        s_mov_b32 s0, 0x1000
        s_mov_b32 s1, 0x2000
        s_mov_b32 s2, 0x3000
        v_mem_ld  v0, s0
        v_mem_ld  v1, s1
        v_add_i32 v2, v0, v1
        v_mem_st  s2, v2
        s_endpgm
