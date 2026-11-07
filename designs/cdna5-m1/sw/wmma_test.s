; wmma_test: C[16][16] = A[16][32] x B[32][16], MXFP4
; A @ 0x4000, B @ 0x4100, C @ 0x5000
        s_mov_b32 s8, 0x4000
        s_mov_b32 s9, 0
        s_mov_b32 s10, 64
        s_tdm_copy s8
        s_mov_b32 s8, 0x4100
        s_mov_b32 s9, 64
        s_mov_b32 s10, 64
        s_tdm_copy s8
        s_mov_b32 s8, 0
        s_mov_b32 s9, 64
        s_mov_b32 s10, 128
        s_wmma s8
        s_mov_b32 s2, 0x5000
        s_mov_b32 s3, 512
        s_mov_b32 s6, 8
loop:
        v_lds_ld v0, s3
        v_mem_st s2, v0
        s_add_u32 s2, s2, 128
        s_add_u32 s3, s3, 128
        s_sub_u32 s6, s6, 1
        s_cmp_lt_u32 s6, 1
        s_cbranch_scc end
        s_branch loop
end:
        s_endpgm
