; Full-chip softmax: TDM 32 Q4.12 logits (16 words) -> LDS, S_SOFTMAX, store.
s_mov_b32 s5, 0x1000   ; global source
s_mov_b32 s6, 0        ; LDS word 0
s_mov_b32 s7, 16       ; 16 words = 32 x 16-bit logits
s_tdm_copy s5
s_mov_b32 s5, 0        ; softmax base
s_mov_b32 s6, 32       ; 32 elements
s_softmax s5
s_mov_b32 s8, 0x3000   ; global destination
s_mov_b32 s5, 0
v_lds_ld v0, s5
v_mem_st s8, v0
s_endpgm
