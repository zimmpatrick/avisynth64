;=============================================================================
; Function declarations
;=============================================================================
	global FRH_yv12_aligned_mmx
	global FRH_yv12_unaligned_mmx
	
	global FRH_yuy2_aligned_mmx
	global FRH_yuy2_unaligned_mmx
	
	global FRH_rgb24_mmx
	global FRH_rgb32_mmx
	
;=============================================================================
; Read only data
;=============================================================================
SECTION .rodata align=8
FPRoundMMX:
	dq 00000200000002000h
MaskWLow:
	dq 00000000000FF00FFh
MaskDW:
	dq 0FFFF0000FFFF0000h
MaskA:
	dq 000000000FF000000h
MaskYXMM:
	dq 000FF00FF00FF00FFh
	dq 00000000000000000h
FPRoundXMM:
	dq 00020002000200020h
	dq 00020002000200020h
UnPackByteShuff:
	dq 00100010001000100h
	dq 00100010001000100h

;=============================================================================
; void FRH_yv12_aligned_mmx(BYTE* srcp, BYTE* dstp, int src_pitch, int dst_pitch, int dst_height, int dst_width, int orig_width, int* pattern_array)
;=============================================================================
section .text

PROC_FRAME FRH_yv12_aligned_mmx
	push rsi
	[pushreg rsi]
	push rdi
	[pushreg rdi]
	push rbx
	[pushreg rbx]
	push rbp
	[pushreg rbp]
	push r12
	[pushreg r12]
	push r13
	[pushreg r13]
	push r14
	[pushreg r14]
	push r15
	[pushreg r15]
		
	alloc_stack  0x30
	save_xmm128  xmm6,0x00
	save_xmm128  xmm7,0x10
	save_xmm128  xmm8,0x20
END_PROLOG

%DEFINE .dst_height [rsp+64+40]
%DEFINE .dst_width [rsp+64+48]
%DEFINE .orig_width [rsp+64+56]
%DEFINE .pattern_array [rsp+64+64]

	;load constants
	pxor			xmm5, xmm5		
	movq			mm6, [rel FPRoundMMX]
	mov				r15, QWORD .pattern_array		; pattern_luma, pattern_chroma

	;load the y counter
	mov				esi, DWORD .dst_height

align 16	
.yv_yloop:
	mov				ebp, .dst_width					; set the x counter 
	shr				ebp, 2							; x = dst_width / 4
	lea				r14, [r15+8]					; curr_luma=array+2
	mov				r10d, DWORD [r14]				; Temporary pointer to Y plane filter-->DWORD @ mem[curr_luma[0]]
	mov				r12, rcx						; Save a copy of the srcp for destruction
	mov				r11d, DWORD .orig_width			; Source width is used to copy pixels to a workspace
	xor				rax, rax	
	mov				r13d, r11d
	and				r13d, 0FFFFFFC0h
	jz				.yv_deintloop16

align 16
.yv_deintloop64:
	prefetchnta		[r12+128]
	prefetchnta		[r10+rax+256]
	movdqa			xmm0, DQWORD [r12+ 0]				; xmm0 = 16xYY
	movdqa			xmm2, DQWORD [r12+16]				; xmm0 = 16xYY
	movdqa			xmm4, DQWORD [r12+32]				; xmm0 = 16xYY
	movdqa			xmm6, DQWORD [r12+48]				; xmm0 = 16xYY
	
	punpckhbw		xmm1, xmm0						; xmm1 = (Y0 Y0 Y0 Y0) x4
	punpcklbw		xmm0, xmm5						; xmm0 = (0Y 0Y 0Y 0Y) x4
	psrlw			xmm1, 8							; xmm1 = (0Y 0Y 0Y 0Y) x4
	punpckhbw		xmm3, xmm2						; xmm1 = (Y0 Y0 Y0 Y0) x4
	punpcklbw		xmm2, xmm5						; xmm0 = (0Y 0Y 0Y 0Y) x4
	psrlw			xmm3, 8							; xmm1 = (0Y 0Y 0Y 0Y) x4
	punpckhbw		xmm8, xmm4						; xmm1 = (Y0 Y0 Y0 Y0) x4
	punpcklbw		xmm4, xmm5						; xmm0 = (0Y 0Y 0Y 0Y) x4
	psrlw			xmm8, 8							; xmm1 = (0Y 0Y 0Y 0Y) x4
	punpckhbw		xmm7, xmm6						; xmm1 = (Y0 Y0 Y0 Y0) x4
	punpcklbw		xmm6, xmm5						; xmm0 = (0Y 0Y 0Y 0Y) x4
	psrlw			xmm7, 8							; xmm1 = (0Y 0Y 0Y 0Y) x4
	movdqa			[r10+rax], xmm0					; store base words
	movdqa			[r10+rax+16], xmm1				; store +16 words
	movdqa			[r10+rax+32], xmm2				; store +32 words
	movdqa			[r10+rax+48], xmm3				; store +64 words
	movdqa			[r10+rax+64], xmm4				; store base words
	movdqa			[r10+rax+80], xmm8				; store +16 words
	movdqa			[r10+rax+96], xmm6				; store +32 words
	movdqa			[r10+rax+112], xmm7				; store +64 words 
	add				eax, 128						; offset+=32, we just stored 32 bytes of info
	add				r12d, 64						; srcp = next 16 bytes
	sub				r13d, 64						; width-=16 to account for bytes we just moved and unpacked
	ja				.yv_deintloop64					; if not mod 16, could give mem access errors?
													; further investigation is needed on above point
	
	
	and				r11d, 00000003Fh
	jz				.yv_xloop_pre

align 16
.yv_deintloop16:
	movdqa			xmm0, DQWORD [r12+ 0]				; xmm0 = 16xYY
	punpckhbw		xmm1, xmm0						; xmm1 = (Y0 Y0 Y0 Y0) x4
	punpcklbw		xmm0, xmm5						; xmm0 = (0Y 0Y 0Y 0Y) x4
	psrlw			xmm1, 8							; xmm1 = (0Y 0Y 0Y 0Y) x4
	movdqa			[r10+rax], xmm0					; store base words
	movdqa			[r10+rax+16], xmm1				; store base words
	add				eax, 32
	add				r12d, 16
	sub				r11d, 16
	ja				.yv_deintloop16

align 16
.yv_xloop_pre:
	mov				rdi, rdx						; copy the dstp for inner loop  
	mov				eax, DWORD [r15]				; Size of FIR filter
	shl				eax, 3							; filter_offset=fir_filter_size_luma*8+8
	add				eax, 8

align 16
.yv_xloop:
	mov				ebx, DWORD [r15]				; Size of FIR filter
	mov				r10d, DWORD [r14]				; r10 = &tempY[ofs0]
	mov				r12d, DWORD [r14+rax]			; r12 = next &tempY[ofs1]
	movq			mm1, mm6						; start with rounder
	movq			mm3, mm6						; start with rounder
	mov				r11d, DWORD [r14+4]				; r11 = &tempY[ofs1]
	mov				r13d, DWORD [r14+rax+4]			; r13 = next &tempY[ofs1]
	add				r14, 8							; cur_luma++

	%REP 16 
	movd			mm2, [r10]          ; mm2 =  0| 0|Yb|Ya
	movd			mm4, [r12]
	punpckldq		mm2, [r11]          ; mm2 = Yn|Ym|Yb|Ya
	add				r10, 4
	add				r12, 4
	pmaddwd			mm2, [r14]          ; mm2 = Y1|Y0 (DWORDs)
	punpckldq		mm4, [r13]			; [eax] = COn|COm|COb|COa
	add				r11, 4
	add				r13, 4
	pmaddwd			mm4, [r14+rax]      ; mm4 = Y1|Y0 (DWORDs)
	add				r14, 8              ; cur_luma++
	paddd			mm1, mm2            ; accumulate
	paddd			mm3, mm4            ; accumulate
	%ENDREP
	sub				ebx, 16				; known that we did at least 16 loops, other macros handle >=16

align 16
.yv_aloop:
	movd			mm2, [r10]						; mm2 =  0| 0|Yb|Ya
	movd			mm4, [r12]
	punpckldq		mm2, [r11]						; mm2 = Yn|Ym|Yb|Ya
	add				r10, 4
	add				r12, 4
	pmaddwd			mm2, [r14]						; mm2 = Y1|Y0 (DWORDs)
	punpckldq		mm4, [r13]						; [r13] = COn|COm|COb|COa
	add				r11, 4
	add				r13, 4
	pmaddwd			mm4, [r14+rax]					; mm4 = Y1|Y0 (DWORDs)
	add				r14, 8							; cur_luma++
	sub				ebx, 1							; known that we did at least 16 loops, other macros handle >=16
	paddd			mm1, mm2						; accumulate
	paddd			mm3, mm4						; accumulate
	ja				.yv_aloop		

;align 16 doesn't need aligned because now isn't branch target
.out_yv_aloop:
	add				r14, rax						; curr_luma += filter_offset
	psrad			mm1, 14							; mm1 = --y1|--y0
	psrad			mm3, 14							; mm3 = --y3|--y2
	packssdw		mm1, mm3						; mm1 = -3|-2|-1|-0
	packuswb		mm1, mm1						; mm1 = 3|2|1|0 3|2|1|0
	movd			[rdi], mm1
	add				rdi,4
	sub				ebp, 1
	ja				.yv_xloop

.endyloop:
	add				rcx, r8							; srcp+=src_pitch
	add				rdx, r9							; dstp+=dst_pitch
	sub				esi, 1
	ja				.yv_yloop

.endfunc:
	emms
	
	movdqa		xmm6,[rsp+16*0]
	movdqa		xmm7,[rsp+16*1]
	movdqa		xmm8,[rsp+16*2]
	add			rsp, 0x30
	
	pop r15
	pop r14
	pop r13
	pop r12
	pop rbp
	pop rbx
	pop rdi
	pop rsi
	ret
ENDPROC_FRAME

;=============================================================================
; void FRH_yv12_unaligned_mmx(BYTE* srcp, BYTE* dstp, int src_pitch, int dst_pitch, int dst_height, int dst_width, int orig_width, int* pattern_array)
;=============================================================================
section .text

PROC_FRAME FRH_yv12_unaligned_mmx
	push rsi
	[pushreg rsi]
	push rdi
	[pushreg rdi]
	push rbx
	[pushreg rbx]
	push rbp
	[pushreg rbp]
	push r12
	[pushreg r12]
	push r13
	[pushreg r13]
	push r14
	[pushreg r14]
	push r15
	[pushreg r15]
	
	alloc_stack  0x30
	save_xmm128  xmm6,0x00
	save_xmm128  xmm7,0x10
	save_xmm128  xmm8,0x20
END_PROLOG

%DEFINE .dst_height [rsp+64+40]
%DEFINE .dst_width [rsp+64+48]
%DEFINE .orig_width [rsp+64+56]
%DEFINE .pattern_array [rsp+64+64]

	;load constants
	pxor			xmm5, xmm5		
	movq			mm6, [rel FPRoundMMX]
	mov				r15, QWORD .pattern_array		; pattern_luma, pattern_chroma

	;load the y counter
	mov				esi, DWORD .dst_height

align 16	
.yv_yloop:
	mov				ebp, .dst_width					; set the x counter 
	shr				ebp, 2							; x = dst_width / 4
	lea				r14, [r15+8]					; curr_luma=array+2
	mov				r10d, DWORD [r14]				; Temporary pointer to Y plane filter-->DWORD @ mem[curr_luma[0]]
	mov				r12, rcx						; Save a copy of the srcp for destruction
	mov				r11d, DWORD .orig_width			; Source width is used to copy pixels to a workspace
	mov				r13d, r11d
	and				r13d, 0FFFFFFC0h
	jz				.yv_deintloop16

align 16
.yv_deintloop64:
	prefetchnta		[r12+128]
	prefetchnta		[r10+rax+256]
	lddqu			xmm0, DQWORD [r12+ 0]				; xmm0 = 16xYY
	lddqu			xmm2, DQWORD [r12+16]				; xmm0 = 16xYY
	lddqu			xmm4, DQWORD [r12+32]				; xmm0 = 16xYY
	lddqu			xmm6, DQWORD [r12+48]				; xmm0 = 16xYY
	punpckhbw		xmm1, xmm0						; xmm1 = (Y0 Y0 Y0 Y0) x4
	punpcklbw		xmm0, xmm5						; xmm0 = (0Y 0Y 0Y 0Y) x4
	psrlw			xmm1, 8							; xmm1 = (0Y 0Y 0Y 0Y) x4
	punpckhbw		xmm3, xmm2						; xmm1 = (Y0 Y0 Y0 Y0) x4
	punpcklbw		xmm2, xmm5						; xmm0 = (0Y 0Y 0Y 0Y) x4
	psrlw			xmm3, 8							; xmm1 = (0Y 0Y 0Y 0Y) x4
	punpckhbw		xmm8, xmm4						; xmm1 = (Y0 Y0 Y0 Y0) x4
	punpcklbw		xmm4, xmm5						; xmm0 = (0Y 0Y 0Y 0Y) x4
	psrlw			xmm8, 8							; xmm1 = (0Y 0Y 0Y 0Y) x4
	punpckhbw		xmm7, xmm6						; xmm1 = (Y0 Y0 Y0 Y0) x4
	punpcklbw		xmm6, xmm5						; xmm0 = (0Y 0Y 0Y 0Y) x4
	psrlw			xmm7, 8							; xmm1 = (0Y 0Y 0Y 0Y) x4
	movdqa			[r10+rax], xmm0					; store base words
	movdqa			[r10+rax+16], xmm1				; store +16 words
	movdqa			[r10+rax+32], xmm2				; store +32 words
	movdqa			[r10+rax+48], xmm3				; store +64 words
	movdqa			[r10+rax+64], xmm4				; store base words
	movdqa			[r10+rax+80], xmm8				; store +16 words
	movdqa			[r10+rax+96], xmm6				; store +32 words
	movdqa			[r10+rax+112], xmm7				; store +64 words 
	add				eax, 128						; offset+=32, we just stored 32 bytes of info
	add				r12d, 64						; srcp = next 16 bytes
	sub				r13d, 64						; width-=16 to account for bytes we just moved and unpacked
	ja				.yv_deintloop64					; if not mod 16, could give mem access errors?
													; further investigation is needed on above point
	
	
	and				r11d, 00000003Fh
	jz				.yv_xloop_pre

align 16
.yv_deintloop16:
	lddqu			xmm0, DQWORD [r12+ 0]				; xmm0 = 16xYY	
	punpckhbw		xmm1, xmm0						; xmm1 = (Y0 Y0 Y0 Y0) x4
	punpcklbw		xmm0, xmm5						; xmm0 = (0Y 0Y 0Y 0Y) x4
	psrlw			xmm1, 8							; xmm1 = (0Y 0Y 0Y 0Y) x4
	movdqa			[r10+rax], xmm0					; store base words
	movdqa			[r10+rax+16], xmm1				; store base words
	add				eax, 32
	add				r12d, 16
	sub				r11d, 16
	ja				.yv_deintloop16

align 16
.yv_xloop_pre:
	mov				rdi, rdx						; copy the dstp for inner loop  
	mov				eax, DWORD [r15]				; Size of FIR filter
	shl				eax, 3							; filter_offset=fir_filter_size_luma*8+8
	add				eax, 8

align 16
.yv_xloop:
	mov				ebx, DWORD [r15]				; Size of FIR filter
	mov				r10d, DWORD [r14]				; r10 = &tempY[ofs0]
	mov				r12d, DWORD [r14+rax]			; r12 = next &tempY[ofs1]
	movq			mm1, mm6						; start with rounder
	movq			mm3, mm6						; start with rounder
	mov				r11d, DWORD [r14+4]				; r11 = &tempY[ofs1]
	mov				r13d, DWORD [r14+rax+4]			; r13 = next &tempY[ofs1]
	add				r14, 8							; cur_luma++

	%REP 16 
	movd			mm2, [r10]          ; mm2 =  0| 0|Yb|Ya
	movd			mm4, [r12]
	punpckldq		mm2, [r11]          ; mm2 = Yn|Ym|Yb|Ya
	add				r10, 4
	add				r12, 4
	pmaddwd			mm2, [r14]          ; mm2 = Y1|Y0 (DWORDs)
	punpckldq		mm4, [r13]			; [eax] = COn|COm|COb|COa
	add				r11, 4
	add				r13, 4
	pmaddwd			mm4, [r14+rax]      ; mm4 = Y1|Y0 (DWORDs)
	add				r14, 8              ; cur_luma++
	paddd			mm1, mm2            ; accumulate
	paddd			mm3, mm4            ; accumulate
	%ENDREP
	sub				ebx, 16				; known that we did at least 16 loops, other macros handle >=16

align 16
.yv_aloop:
	movd			mm2, [r10]			; mm2 =  0| 0|Yb|Ya
	movd			mm4, [r12]
	punpckldq		mm2, [r11]			; mm2 = Yn|Ym|Yb|Ya
	add				r10, 4
	add				r12, 4
	pmaddwd			mm2, [r14]			; mm2 = Y1|Y0 (DWORDs)
	punpckldq		mm4, [r13]			; [r13] = COn|COm|COb|COa
	add				r11, 4
	add				r13, 4
	pmaddwd			mm4, [r14+rax]		; mm4 = Y1|Y0 (DWORDs)
	add				r14, 8				; cur_luma++
	sub				ebx, 1				; known that we did at least 16 loops, other macros handle >=16
	paddd			mm1, mm2			; accumulate
	paddd			mm3, mm4			; accumulate
	ja				.yv_aloop		

;align 16 doesn't need aligned because now isn't branch target
.out_yv_aloop:
	add				r14, rax			; curr_luma += filter_offset
	psrad			mm1, 14				; mm1 = --y1|--y0
	psrad			mm3, 14				; mm3 = --y3|--y2
	packssdw		mm1, mm3			; mm1 = -3|-2|-1|-0
	packuswb		mm1, mm1			; mm1 = 3|2|1|0 3|2|1|0
	movd			[rdi], mm1
	add				rdi,4
	sub				ebp, 1
	ja				.yv_xloop

.endyloop:
	add				rcx, r8				; srcp+=src_pitch
	add				rdx, r9				; dstp+=dst_pitch
	sub				esi, 1
	ja				.yv_yloop

.endfunc:
	emms
	movdqa		xmm6,[rsp+16*0]
	movdqa		xmm7,[rsp+16*1]
	movdqa		xmm8,[rsp+16*2]
	add			rsp, 0x30
	
	pop r15
	pop r14
	pop r13
	pop r12
	pop rbp
	pop rbx
	pop rdi
	pop rsi
	ret
ENDPROC_FRAME	

;=============================================================================
; void FRH_yuy2_aligned_mmx(BYTE* srcp, BYTE* dstp, int src_pitch, int dst_pitch, int dst_height, int dst_width, int orig_width, int* luma, int* chroma)
;=============================================================================
PROC_FRAME FRH_yuy2_aligned_mmx
	push rsi
	[pushreg rsi]
	push rdi
	[pushreg rdi]
	push rbx
	[pushreg rbx]
	push rbp
	[pushreg rbp]
	push r12
	[pushreg r12]
	push r13
	[pushreg r13]
	push r14
	[pushreg r14]
	push r15
	[pushreg r15]
END_PROLOG

%DEFINE .dst_height [rsp+64+40]
%DEFINE .dst_width [rsp+64+48]
%DEFINE .orig_width [rsp+64+56]
%DEFINE .luma [rsp+64+64]
%DEFINE .chroma [rsp+64+72]

	;load constants	
	movq			mm7, [rel MaskWLow]
	pxor			xmm5, xmm5
	movq			xmm4, [rel MaskYXMM]
	movq			mm6, [rel FPRoundMMX]
	movq			mm5, [rel MaskDW]
	mov				r14, QWORD .luma				; pattern_luma
	mov				r15, QWORD .chroma				; pattern_chroma
	
	;load the y counter
	mov				esi, DWORD .dst_height
align 16	
.yuy2_yloop:
	mov				ebp, .dst_width			; set the x counter 
	shr				ebp, 1					; x = dst_width / 2
	lea				r12, [r14+8]			; curr_luma=pattern_luma+2
	lea				r13, [r15+8]			; curr_chroma=patter_chroma+2
	mov				r10d, DWORD [r12]		; Temporary pointer to Y plane filter-->DWORD @ mem[curr_luma[0]]
	mov				r11d, DWORD [r13]		; Temporary pointer to UV plane filter-->DWORD @ mem[curr_chroma[0]]
	mov				rdi, rcx				; Save a copy of the srcp for destruction
	mov				ebx, DWORD .orig_width	; Source width is used to copy pixels to a workspace
	xor				rax, rax

align 16
.yuy2_deintloop:
	prefetchnta		[rdi+256]
	movq			xmm0, QWORD [rdi]		; xmm0 = (VY UY)*2
	movdqa			xmm1, xmm0				; xmm1 = (VY UY)*2
	pand			xmm0, xmm4				; xmm0 = (0Y 0Y)*2
	movq			[r10+rax],xmm0			; [tempY]=(0Y 0Y)*2
	punpcklbw		xmm1, xmm5				; xmm1 = (0V 0Y | 0U 0Y)*2
	psrld			xmm1, 16				; xmm1 = (00 0V | 00 0U)*2
	movdqa			[r11+rax*2],xmm1		; [tempUV] = (00 0V | 00 0U)*2 		
	add				edi, 8
	add				eax, 8
	sub				ebx, 4
	ja				.yuy2_deintloop
	
	lea				r12, [r14+8]			; load curr_luma
	lea				r13, [r15+8]			; load curr_chroma
	mov				rdi, rdx				; copy dstp for destruction

align 16	
.xloopYUV:
	mov				r10d, DWORD [r12]		; r10=&tempY[ofs0]
	movq			mm1, mm6				; start with rounder
	mov				r11d, DWORD [r12+4]		; r11=&tempY[ofs1]
	movq			mm3, mm6				; start with rounder
	mov				ebx, DWORD [r14]		; ebx=fir_size_luma
	add				r12d, 8					; cur_luma++
	
align 16
.aloopY:
	%REP 7
	movd			mm2, [r10]				; mm2 =  0| 0|Yb|Ya
	add				r10d, 4
	punpckldq		mm2, [r11]				; mm2 = Yn|Ym|Yb|Ya
											; [r12] = COn|COm|COb|COa
	add				r11d, 4
	pmaddwd			mm2, [r12]				; mm2 = Y1|Y0 (DWORDs)
	add				r12d, 8					; cur_luma++
	sub				ebx, 1					; fir_size_luma--
	paddd			mm1, mm2				; accumulate
	jz				.out_aloopY
	%ENDREP
	
	;after unrolling 7 times, see if we need to keep going
	movd			mm2, [r10]				; mm2 =  0| 0|Yb|Ya
	add				r10d, 4
	punpckldq		mm2, [r11]				; mm2 = Yn|Ym|Yb|Ya
											; [r12] = COn|COm|COb|COa
	add				r11d, 4
	pmaddwd			mm2, [r12]				; mm2 = Y1|Y0 (DWORDs)
	add				r12d, 8					; cur_luma++
	sub				ebx, 1					; fir_size_luma--
	paddd			mm1, mm2				; accumulate
	ja				.aloopY

align 16
.out_aloopY:
	mov				r10d, [r13]				; r10d=&tempUV[ofs]
	add				r13, 8					; cur_chroma++
	mov				ebx, [r15]				; ebx=fir_size_chroma

align 16	
.aloopUV:
	%REP 7
	movq			mm2, [r10]				;mm2 = 0|V|0|U
											;[r13] = 0|COv|0|COu
	add				r10d, 8
	pmaddwd			mm2, [r13]				;mm2 = V|U (DWORDs)
	add				r13d, 8					;cur_chroma++
	sub				ebx, 1					;fir_size_chroma--
	paddd			mm3, mm2				;accumulate
	jz				.out_aloopUV
	%ENDREP
	
	;after unrolling 7 times, see if we need to keep going
	movq			mm2, [r10]				; mm2 = 0|V|0|U
											; [r13] = 0|COv|0|COu
	add				r10d, 8
	pmaddwd			mm2, [r13]				; mm2 = V|U (DWORDs)
	add				r13, 8					; cur_chroma++
	sub				ebx, 1
	paddd			mm3, mm2				;accumulate
	ja				.aloopUV

align 16
.out_aloopUV:
	pslld			mm3, 2					; Shift up from 14 bits fraction to 16 bit fraction
	pxor			mm4, mm4				; Clear mm4 - utilize shifter stall
	psrad			mm1, 14					; mm1 = --y1|--y0
	pmaxsw			mm1, mm4				; Clamp at 0
	pand			mm3, mm5				; mm3 = v| 0|u| 0
	por				mm3, mm1
	packuswb		mm3, mm3				; mm3 = ...|v|y1|u|y0
	movd			[rdi], mm3
	add				rdi, 4
	sub				ebp, 1					; x--
	ja				.xloopYUV
	
.end_yuy2_yloop:
	add				rcx, r8
	add				rdx, r9
	sub				esi, 1
	ja				.yuy2_yloop
	
.endfunc:
	emms
	pop r15
	pop r14
	pop r13
	pop r12
	pop rbp
	pop rbx
	pop rdi
	pop rsi
	ret
ENDPROC_FRAME

;=============================================================================
; void FRH_yuy2_unaligned_mmx(BYTE* srcp, BYTE* dstp, int src_pitch, int dst_pitch, int dst_height, int dst_width, int orig_width, int* luma, int* chroma)
;=============================================================================
PROC_FRAME FRH_yuy2_unaligned_mmx
	push rsi
	[pushreg rsi]
	push rdi
	[pushreg rdi]
	push rbx
	[pushreg rbx]
	push rbp
	[pushreg rbp]
	push r12
	[pushreg r12]
	push r13
	[pushreg r13]
	push r14
	[pushreg r14]
	push r15
	[pushreg r15]
END_PROLOG

%DEFINE .dst_height [rsp+64+40]
%DEFINE .dst_width [rsp+64+48]
%DEFINE .orig_width [rsp+64+56]
%DEFINE .luma [rsp+64+64]
%DEFINE .chroma [rsp+64+72]

	;load constants	
	movq			mm7, [rel MaskWLow]
	pxor			xmm5, xmm5
	movq			xmm4, [rel MaskYXMM]
	movq			mm6, [rel FPRoundMMX]
	movq			mm5, [rel MaskDW]
	mov				r14, QWORD .luma				; pattern_luma
	mov				r15, QWORD .chroma				; pattern_chroma
	
	;load the y counter
	mov				esi, DWORD .dst_height
align 16	
.yuy2_yloop:
	mov				ebp, .dst_width			; set the x counter 
	shr				ebp, 1					; x = dst_width / 2
	lea				r12, [r14+8]			; curr_luma=pattern_luma+2
	lea				r13, [r15+8]			; curr_chroma=patter_chroma+2
	mov				r10d, DWORD [r12]		; Temporary pointer to Y plane filter-->DWORD @ mem[curr_luma[0]]
	mov				r11d, DWORD [r13]		; Temporary pointer to UV plane filter-->DWORD @ mem[curr_chroma[0]]
	mov				rdi, rcx				; Save a copy of the srcp for destruction
	mov				ebx, DWORD .orig_width	; Source width is used to copy pixels to a workspace
	xor				rax, rax

align 16
.yuy2_deintloop:
	prefetchnta		[rdi+256]
	movq			xmm0, QWORD [rdi]		; xmm0 = (VY UY)*2
	movdqa			xmm1, xmm0				; xmm1 = (VY UY)*2
	pand			xmm0, xmm4				; xmm0 = (0Y 0Y)*2
	movq			[r10+rax],xmm0			; [tempY]=(0Y 0Y)*2
	punpcklbw		xmm1, xmm5				; xmm1 = (0V 0Y | 0U 0Y)*2
	psrld			xmm1, 16				; xmm1 = (00 0V | 00 0U)*2
	movdqa			[r11+rax*2],xmm1		; [tempUV] = (00 0V | 00 0U)*2 		
	add				edi, 8
	add				eax, 8
	sub				ebx, 4
	ja				.yuy2_deintloop
	
	lea				r12, [r14+8]			; load curr_luma
	lea				r13, [r15+8]			; load curr_chroma
	mov				rdi, rdx				; copy dstp for destruction

align 16	
.xloopYUV:
	mov				r10d, DWORD [r12]		; r10=&tempY[ofs0]
	movq			mm1, mm6				; start with rounder
	mov				r11d, DWORD [r12+4]		; r11=&tempY[ofs1]
	movq			mm3, mm6				; start with rounder
	mov				ebx, DWORD [r14]		; ebx=fir_size_luma
	add				r12d, 8					; cur_luma++
	
align 16
.aloopY:
	%REP 7
	movd			mm2, [r10]				; mm2 =  0| 0|Yb|Ya
	add				r10d, 4
	punpckldq		mm2, [r11]				; mm2 = Yn|Ym|Yb|Ya
											; [r12] = COn|COm|COb|COa
	add				r11d, 4
	pmaddwd			mm2, [r12]				; mm2 = Y1|Y0 (DWORDs)
	add				r12d, 8					; cur_luma++
	sub				ebx, 1					; fir_size_luma--
	paddd			mm1, mm2				; accumulate
	jz				.out_aloopY
	%ENDREP
	
	;after unrolling 7 times, see if we need to keep going
	movd			mm2, [r10]				; mm2 =  0| 0|Yb|Ya
	add				r10d, 4
	punpckldq		mm2, [r11]				; mm2 = Yn|Ym|Yb|Ya
											; [r12] = COn|COm|COb|COa
	add				r11d, 4
	pmaddwd			mm2, [r12]				; mm2 = Y1|Y0 (DWORDs)
	add				r12d, 8					; cur_luma++
	sub				ebx, 1					; fir_size_luma--
	paddd			mm1, mm2				; accumulate
	ja				.aloopY

align 16
.out_aloopY:
	mov				r10d, [r13]				; r10d=&tempUV[ofs]
	add				r13, 8					; cur_chroma++
	mov				ebx, [r15]				; ebx=fir_size_chroma

align 16	
.aloopUV:
	%REP 7
	movq			mm2, [r10]				; mm2 = 0|V|0|U
											; [r13] = 0|COv|0|COu
	add				r10d, 8
	pmaddwd			mm2, [r13]				; mm2 = V|U (DWORDs)
	add				r13d, 8					; cur_chroma++
	sub				ebx, 1					; fir_size_chroma--
	paddd			mm3, mm2				; accumulate
	jz				.out_aloopUV
	%ENDREP
	
	;after unrolling 7 times, see if we need to keep going
	movq			mm2, [r10]				; mm2 = 0|V|0|U
											; [r13] = 0|COv|0|COu
	add				r10d, 8
	pmaddwd			mm2, [r13]				; mm2 = V|U (DWORDs)
	add				r13, 8					; cur_chroma++
	sub				ebx, 1
	paddd			mm3, mm2				; accumulate
	ja				.aloopUV

align 16
.out_aloopUV:
	pslld			mm3, 2					; Shift up from 14 bits fraction to 16 bit fraction
	pxor			mm4, mm4				; Clear mm4 - utilize shifter stall
	psrad			mm1, 14					; mm1 = --y1|--y0
	pmaxsw			mm1, mm4				; Clamp at 0
	pand			mm3, mm5				; mm3 = v| 0|u| 0
	por				mm3, mm1
	packuswb		mm3, mm3				; mm3 = ...|v|y1|u|y0
	movd			[rdi], mm3
	add				rdi, 4
	sub				ebp, 1					; x--
	ja				.xloopYUV
	
.end_yuy2_yloop:
	add				rcx, r8
	add				rdx, r9
	sub				esi, 1
	ja				.yuy2_yloop
	
.endfunc:
	emms
	pop r15
	pop r14
	pop r13
	pop r12
	pop rbp
	pop rbx
	pop rdi
	pop rsi
	ret
ENDPROC_FRAME

;=============================================================================
; void FRH_rgb24_mmx(const BYTE* srcp, BYTE* dstp, int src_pitch, int dst_pitch, int dst_height, int dst_width, int* pattern_luma)
;=============================================================================
PROC_FRAME FRH_rgb24_mmx
	push rbx
	[pushreg rbx]
	push rbp
	[pushreg rbp]
	push r12
	[pushreg r12]
	push r15
	[pushreg r15]
END_PROLOG

%DEFINE .dst_height [rsp+32+40]
%DEFINE .dst_width [rsp+32+48]
%DEFINE .luma [rsp+32+56]

	;load constants
	pxor		mm2, mm2
	movq		mm4, [rel MaskA]
	mov			r15, QWORD .luma
	
	;load y counter
	mov			ebp, DWORD .dst_height		; ebp = y
	mov			ebx, DWORD .dst_width
	lea			ebx, [ebx+ebx*2]			; ebx = x = vi.width * 3;

align 16
.yloop24:
	xor         rax, rax					; eax = x			
	mov         r10d, DWORD [r15]			; need to know fir size to remove it from curr_luma
	lea         r11, [r15+4]				; curr_luma
	neg			r10
	lea			r11, [r11+r10*4]			; curr_luma-fir_size
		
align 16
.xloop24:
	mov         r10d, DWORD [r15]
	lea         r11, [r11+r10*4]			; cur += fir_filter_size
	mov         r12d, DWORD [r11]
	lea         r12d, [r12d+r12d*2]			; ebx = ofs = *cur * 3
	add         r11d, 4						; cur++
	movq        mm0, [rel FPRoundMMX]		; btotal, gtotal
	movq        mm1, [rel FPRoundMMX]		; atotal, rtotal
	lea         r11, [r11+r10*4]			; cur += fir_filter_size
	add         r12, rcx					; r12 = srcp + ofs*3
	lea         r10d, [r10d+r10d*2]			; rax = a = fir_filter_size*3

align 16
.aloop24:
	sub         r11, 4						; cur--
	sub         r10d, 3						; a -= 3
	movd        mm7, [r12+r10]				; mm7 = srcp[ofs+a] = 0|0|0|0|x|r|g|b
	punpcklbw   mm7, mm2					; mm7 = 0x|0r|0g|0b
	movq        mm6, mm7
	punpcklwd   mm7, mm2					; mm7 = 00|0g|00|0b
	punpckhwd   mm6, mm2					; mm6 = 00|0x|00|0r
	movd        mm5, [r11]					; mm5 =    00|co (co = coefficient)
	pshufw		mm5, mm5, 11001100b
	;packssdw    mm5, mm2
	;punpckldq   mm5, mm5	
	pmaddwd     mm7, mm5					; mm7 =  g*co|b*co
	pmaddwd     mm6, mm5					; mm6 =  x*co|r*co
	paddd       mm0, mm7
	paddd       mm1, mm6
	ja			.aloop24
	
	pslld       mm0, 2
	pslld       mm1, 2						; compensate the fact that FPScale = 16384
	packuswb    mm0, mm1					; mm0 = x|_|r|_|g|_|b|_
	psrlw       mm0, 8						; mm0 = 0|x|0|r|0|g|0|b
	packuswb    mm0, mm2					; mm0 = 0|0|0|0|x|r|g|b
	pslld       mm0, 8
	psrld       mm0, 8						; mm0 = 0|0|0|0|0|r|g|b
	movd        mm3, [rdx+rax]				; mm3 = 0|0|0|0|x|r|g|b (dst)
	pand        mm3, mm4					; mm3 = 0|0|0|0|x|0|0|0 (dst)
	por         mm3, mm0
	movd        [rdx+rax], mm3

	add         eax, 3
	cmp			eax, ebx
	jb	        .xloop24

	add         rcx, r8						; srcp+=src_pitch
	add         rdx, r9						; dstp+=dst_pitch
	sub         ebp, 1
	ja			.yloop24

.endfunc:
	emms
	pop r15
	pop r12
	pop rbp
	pop rbx
	ret
ENDPROC_FRAME

;=============================================================================
; void FRH_rgb32_mmx(const BYTE* srcp, BYTE* dstp, int src_pitch, int dst_pitch, int dst_height, int dst_width, int* pattern_luma)
;=============================================================================
PROC_FRAME FRH_rgb32_mmx
	push rbx
	[pushreg rbx]
	push rbp
	[pushreg rbp]
	push r12
	[pushreg r12]
	push r15
	[pushreg r15]
END_PROLOG

%DEFINE .dst_height [rsp+32+40]
%DEFINE .dst_width [rsp+32+48]
%DEFINE .luma [rsp+32+56]


	;load constants
	pxor		mm2, mm2
	mov			r15, QWORD .luma
	
	;load y counter
	mov			ebp, DWORD .dst_height		; ebp = y
	mov			ebx, DWORD .dst_width		; ebx = x 

align 16
.yloop32:
	xor         rax, rax					; eax = count up to x			
	mov         r10d, DWORD [r15]			; need to know fir size to remove it from curr_luma
	lea         r11, [r15+4]				; curr_luma
	neg			r10
	lea			r11, [r11+r10*4]			; curr_luma-fir_size
		
align 16
.xloop32:
	mov         r10d, DWORD [r15]
	lea         r11, [r11+r10*4]			; cur += fir_filter_size
	mov         r12d, DWORD [r11]
	shl         r12d, 2						; r12d = ofs = *cur * 4
	add         r11d, 4						; cur++
	movq        mm0, [rel FPRoundMMX]		; btotal, gtotal
	movq        mm1, [rel FPRoundMMX]		; atotal, rtotal
	lea         r11, [r11+r10*4]			; cur += fir_filter_size
	add         r12, rcx					; r12 = srcp + ofs*3

align 16
.aloop32:
	sub         r11, 4						; cur--
	sub			r10d, 1						; a--
	movd        mm7, [r12+r10*4]			; mm7 = srcp[ofs+a] = 0|0|0|0|a|r|g|b
	punpcklbw   mm7, mm2					; mm7 = 0a|0r|0g|0b
	movq        mm6, mm7
	punpcklwd   mm7, mm2					; mm7 = 00|0g|00|0b
	punpckhwd   mm6, mm2					; mm6 = 00|0a|00|0r
	movd        mm5, [r11]					; mm5 =    00|co (co = coefficient)
	pshufw		mm5, mm5, 11001100b
	;packssdw    mm5, mm2
	;punpckldq   mm5, mm5					; mm5 =    co|co
	pmaddwd     mm7, mm5					; mm7 =  g*co|b*co
	pmaddwd     mm6, mm5					; mm6 =  a*co|r*co
	paddd       mm0, mm7
	paddd       mm1, mm6
	ja	        .aloop32
	
	pslld       mm0, 2
	pslld       mm1, 2						; compensate the fact that FPScale = 16384
	packuswb    mm0, mm1					; mm0 = a|_|r|_|g|_|b|_
	psrlw       mm0, 8						; mm0 = 0|a|0|r|0|g|0|b
	packuswb    mm0, mm2					; mm0 = 0|0|0|0|a|r|g|b
	movd        [rdx+rax*4], mm0

	add			eax, 1
	cmp			eax, ebx
	jb			.xloop32

	add         rcx, r8						; srcp+=src_pitch
	add         rdx, r9						; dstp+=dst_pitch
	sub         ebp, 1
	ja			.yloop32

.endfunc:
	emms
	pop r15
	pop r12
	pop rbp
	pop rbx
	ret
ENDPROC_FRAME