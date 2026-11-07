; CDNA5-M1 softmax kernel: 32 Q4.12 logits at LDS word 0, normalized in place.
; s5 = base word, s6 = element count (the softmax_engine reads s[dst], s[dst+1])
s_mov_b32 s5, 0
s_mov_b32 s6, 32
s_softmax s5
s_endpgm
