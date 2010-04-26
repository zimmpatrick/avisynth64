;=============================================================================
; Function declarations
;=============================================================================
%ASSIGN y 1
%REP 24

	global FRH_yv12_aligned_FIR %+ y
	global FRH_yv12_unaligned_FIR %+ y

%ASSIGN y y+1
%ENDREP
	
	
;=============================================================================
; Read only data
;=============================================================================
SECTION .rodata align=16
FPRoundMMX:
	dq 00000200000002000h
	dq 00000000000000000h
MaskWLow:
	dq 00000000000FF00FFh
MaskDW:
	dq 0FFFF0000FFFF0000h
MaskA:
	dq 000000000FF000000h

;=============================================================================
; void FRH_yv12_<memtype>_<firsize>(BYTE* srcp, BYTE* dstp, int src_pitch, int dst_pitch, int dst_height, int dst_width, int orig_width, int* pattern_array)
;=============================================================================
%MACRO FRH_yv12_memtpye_firsize 2
align 16
PROC_FRAME FRH_yv12_ %+ %1 %+ _FIR %+ %2
	push rdi
	[pushreg rdi]
	push rsi
	[pushreg rsi]	
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
END_PROLOG

%DEFINE .src_pitch	[rsp+56+24]
%DEFINE .dst_pitch	[rsp+56+32]
%DEFINE .dst_height [rsp+56+40]
%DEFINE .dst_width [rsp+56+48]
%DEFINE .orig_width [rsp+56+56]
%DEFINE .pattern_array [rsp+56+64]

	;load constants
	pxor			xmm5, xmm5		
	movq			mm6, [rel FPRoundMMX]
	mov				.src_pitch, r8
	mov				.dst_pitch, r9

	;load the y counter
	mov				esi, DWORD .dst_height
	mov				r14, QWORD .pattern_array		; curr_luma=array+2
	mov				ebp, .dst_width					; set the x counter 
	add				r14, 8
	mov				QWORD .pattern_array, r14
	shr				ebp, 3							; x = dst_width / 8
	mov				.dst_width, ebp

align 16	
.yv_yloop:
	mov				ebp, .dst_width					; set the x counter 
	mov				r14, QWORD .pattern_array		; curr_luma=array+2
	mov				r10d, DWORD [r14]				; Temporary pointer to Y plane filter-->DWORD @ mem[curr_luma[0]]
	mov				r12, rcx						; Save a copy of the srcp for destruction
	mov				r11d, DWORD .orig_width			; Source width is used to copy pixels to a workspace
	xor				eax, eax
	mov				r13d, r11d
	and				r13d, 0FFFFFFC0h
	jz				.yv_deintloop16

align 16
.yv_deintloop64:
	prefetchnta		[r12+64]
	prefetchnta		[r10+rax+128]
	%IFIDNI %1,aligned
	movdqa			xmm0, DQWORD [r12+ 0]				; xmm0 = 16xYY
	movdqa			xmm2, DQWORD [r12+16]				; xmm0 = 16xYY
	movdqa			xmm4, DQWORD [r12+32]				; xmm0 = 16xYY
	movdqa			xmm6, DQWORD [r12+48]				; xmm0 = 16xYY
	%ELSE
	lddqu			xmm0, DQWORD [r12+ 0]				; xmm0 = 16xYY
	lddqu			xmm2, DQWORD [r12+16]				; xmm0 = 16xYY
	lddqu			xmm4, DQWORD [r12+32]				; xmm0 = 16xYY
	lddqu			xmm6, DQWORD [r12+48]				; xmm0 = 16xYY
	%ENDIF
	
	punpckhbw		xmm1, xmm0						; xmm1 = (Y0 Y0 Y0 Y0) x4
	punpcklbw		xmm0, xmm5						; xmm0 = (0Y 0Y 0Y 0Y) x4
	psrlw			xmm1, 8							; xmm1 = (0Y 0Y 0Y 0Y) x4
	movdqa			[r10+rax], xmm0					; store base words
	movdqa			[r10+rax+16], xmm1				; store +16 words
	
	punpckhbw		xmm3, xmm2						; xmm1 = (Y0 Y0 Y0 Y0) x4
	punpcklbw		xmm2, xmm5						; xmm0 = (0Y 0Y 0Y 0Y) x4
	psrlw			xmm3, 8							; xmm1 = (0Y 0Y 0Y 0Y) x4
	movdqa			[r10+rax+32], xmm2				; store +32 words
	movdqa			[r10+rax+48], xmm3				; store +64 words
	
	punpckhbw		xmm8, xmm4						; xmm1 = (Y0 Y0 Y0 Y0) x4
	punpcklbw		xmm4, xmm5						; xmm0 = (0Y 0Y 0Y 0Y) x4
	psrlw			xmm8, 8							; xmm1 = (0Y 0Y 0Y 0Y) x4
	movdqa			[r10+rax+64], xmm4				; store base words
	movdqa			[r10+rax+80], xmm8				; store +16 words
	
	punpckhbw		xmm7, xmm6						; xmm1 = (Y0 Y0 Y0 Y0) x4
	punpcklbw		xmm6, xmm5						; xmm0 = (0Y 0Y 0Y 0Y) x4
	psrlw			xmm7, 8							; xmm1 = (0Y 0Y 0Y 0Y) x4
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
	%IFIDNI %1,aligned
	movdqa			xmm0, DQWORD [r12+ 0]				; xmm0 = 16xYY
	%ELSE
	lddqu			xmm0, DQWORD [r12+ 0]				; xmm0 = 16xYY
	%ENDIF	
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
	mov				rax, rdx						; copy the dstp for inner loop
	add				rcx, .src_pitch					; srcp+=src_pitch
	add				rdx, .dst_pitch					; dstp+=dst_pitch			  

align 16
.yv_xloop:
	mov				r10d, DWORD [r14]				; r10 = &tempY[ofs0]
	mov				r12d, DWORD [r14+(%2*8+8)]		; r12 = next &tempY[ofs1]
	movq			mm1, mm6						; start with rounder 
	movq			mm3, mm6						; start with rounder
	mov				r11d, DWORD [r14+4]				; r11 = &tempY[ofs1]
	mov				r13d, DWORD [r14+(%2*8+8)+4]	; r13 = next &tempY[ofs1]
	
	mov				ebx, DWORD [r14+(%2*8+8)*2]
	mov				edi, DWORD [r14+(%2*8+8)*2+4]
	movq			mm5, mm6
	movq			mm7, mm6
	mov				r8d, DWORD [r14+(%2*8+8)*3]
	mov				r9d, DWORD [r14+(%2*8+8)*3+4]
	
	add				r14, 8							; cur_luma++

	%ASSIGN i 0
	%REP %2
	movd			mm2, [r10+i*4]					; mm2 =  0| 0|Yb|Ya
	movd			mm4, [r12+i*4]
	punpckldq		mm2, [r11+i*4]					; mm2 = Yn|Ym|Yb|Ya

	pmaddwd			mm2, [r14+i*8]					; mm2 = Y1|Y0 (DWORDs)
	punpckldq		mm4, [r13+i*4]					; [r14] = COn|COm|COb|COa

	pmaddwd			mm4, [r14+(%2*8+8)+i*8]			; mm4 = Y1|Y0 (DWORDs)

	paddd			mm1, mm2						; accumulate
	paddd			mm3, mm4						; accumulate
	
	;second pair
	movd			mm2, [rbx+i*4]					; mm2 =  0| 0|Yb|Ya
	movd			mm4, [r8+i*4]
	punpckldq		mm2, [rdi+i*4]					; mm2 = Yn|Ym|Yb|Ya

	pmaddwd			mm2, [r14+(%2*8+8)*2+i*8]		; mm2 = Y1|Y0 (DWORDs)
	punpckldq		mm4, [r9+i*4]					; [r14] = COn|COm|COb|COa

	pmaddwd			mm4, [r14+(%2*8+8)*3+i*8]		; mm4 = Y1|Y0 (DWORDs)

	paddd			mm5, mm2						; accumulate
	paddd			mm7, mm4						; accumulate
	%ASSIGN i i+1
	%ENDREP
	
	add				r14, (%2*8+8)*3+(%2*8)			; curr_luma += filter_offset
	psrad			mm1, 14							; mm1 = --y1|--y0
	psrad			mm3, 14							; mm3 = --y3|--y2
	packssdw		mm1, mm3						; mm1 = -3|-2|-1|-0
	packuswb		mm1, mm1						; mm1 = 3|2|1|0 3|2|1|0
	psrlq			mm1, 32			
	;movd			[rax], mm1
	psrad			mm5, 14							; mm1 = --y1|--y0
	psrad			mm7, 14							; mm3 = --y3|--y2
	packssdw		mm5, mm7						; mm1 = -3|-2|-1|-0
	packuswb		mm5, mm5						; mm1 = 3|2|1|0 3|2|1|0
	psllq			mm5, 32
	por				mm1, mm5
	movq			[rax], mm1
	;movd			[rax+4],mm5
	
	add				eax, 8
	sub				ebp, 1
	ja				.yv_xloop

.endyloop:

	sub				esi, 1
	ja				.yv_yloop

.endfunc:
	pop r14
	pop r13
	pop r12
	pop rbp
	pop rbx
	pop rsi
	pop rdi
	emms
%ENDMACRO

;=============================================================================
; void FRH_yv12_<memtype>_<firsize>(BYTE* srcp, BYTE* dstp, int src_pitch, int dst_pitch, int dst_height, int dst_width, int orig_width, int* pattern_array)
;=============================================================================
%MACRO FRH_yv12_memtpye_firsize_new 2
align 16
PROC_FRAME FRH_yv12_ %+ %1 %+ _FIR %+ %2
	push rdi
	[pushreg rdi]
	push rsi
	[pushreg rsi]	
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
END_PROLOG

%DEFINE .src_pitch	[rsp+56+24]
%DEFINE .dst_pitch	[rsp+56+32]
%DEFINE .dst_height [rsp+56+40]
%DEFINE .dst_width [rsp+56+48]
%DEFINE .orig_width [rsp+56+56]
%DEFINE .pattern_array [rsp+56+64]

	;load constants
	pxor			xmm15, xmm15		; 0 register		
	movdqa			xmm14, [rel FPRoundMMX]
	mov				.src_pitch, r8
	mov				.dst_pitch, r9

	;load the y counter
	mov				esi, DWORD .dst_height
	mov				ebp, .dst_width					; set the x counter 
	shr				ebp, 3							; x = dst_width / 8
	mov				.dst_width, ebp
	mov				r14, QWORD .pattern_array		; curr_luma=array+2
	add				r14, 8
	mov				QWORD .pattern_array, r14

align 16	
.yv_yloop:
	mov				ebp, .dst_width					; set the x counter 
	mov				r14, QWORD .pattern_array		; curr_luma=array+2
	
	mov				r10d, DWORD [r14]				; Temporary pointer to Y plane filter-->DWORD @ mem[curr_luma[0]]
	mov				r12, rcx						; Save a copy of the srcp for destruction
	mov				r11d, DWORD .orig_width			; Source width is used to copy pixels to a workspace
	xor				eax, eax
	mov				r13d, r11d
	and				r13d, 0FFFFFFC0h
	jz				.yv_deintloop16

align 16
.yv_deintloop64:
	prefetchnta		[r12+64]
	prefetchnta		[r10+rax+128]
	%IFIDNI %1,aligned
	movdqa			xmm0, DQWORD [r12+ 0]				; xmm0 = 16xYY
	movdqa			xmm2, DQWORD [r12+16]				; xmm0 = 16xYY
	movdqa			xmm4, DQWORD [r12+32]				; xmm0 = 16xYY
	movdqa			xmm6, DQWORD [r12+48]				; xmm0 = 16xYY
	%ELSE
	lddqu			xmm0, DQWORD [r12+ 0]				; xmm0 = 16xYY
	lddqu			xmm2, DQWORD [r12+16]				; xmm0 = 16xYY
	lddqu			xmm4, DQWORD [r12+32]				; xmm0 = 16xYY
	lddqu			xmm6, DQWORD [r12+48]				; xmm0 = 16xYY
	%ENDIF
	
	punpckhbw		xmm1, xmm0						; xmm1 = (Y0 Y0 Y0 Y0) x4
	punpcklbw		xmm0, xmm15						; xmm0 = (0Y 0Y 0Y 0Y) x4
	psrlw			xmm1, 8							; xmm1 = (0Y 0Y 0Y 0Y) x4
	movdqa			[r10+rax], xmm0					; store base words
	movdqa			[r10+rax+16], xmm1				; store +16 words
	
	punpckhbw		xmm3, xmm2						; xmm1 = (Y0 Y0 Y0 Y0) x4
	punpcklbw		xmm2, xmm15						; xmm0 = (0Y 0Y 0Y 0Y) x4
	psrlw			xmm3, 8							; xmm1 = (0Y 0Y 0Y 0Y) x4
	movdqa			[r10+rax+32], xmm2				; store +32 words
	movdqa			[r10+rax+48], xmm3				; store +64 words
	
	punpckhbw		xmm5, xmm4						; xmm1 = (Y0 Y0 Y0 Y0) x4
	punpcklbw		xmm4, xmm15						; xmm0 = (0Y 0Y 0Y 0Y) x4
	psrlw			xmm5, 8							; xmm1 = (0Y 0Y 0Y 0Y) x4
	movdqa			[r10+rax+64], xmm4				; store base words
	movdqa			[r10+rax+80], xmm5				; store +16 words
	
	punpckhbw		xmm7, xmm6						; xmm1 = (Y0 Y0 Y0 Y0) x4
	punpcklbw		xmm6, xmm15						; xmm0 = (0Y 0Y 0Y 0Y) x4
	psrlw			xmm7, 8							; xmm1 = (0Y 0Y 0Y 0Y) x4
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
	%IFIDNI %1,aligned
	movdqa			xmm0, DQWORD [r12+ 0]				; xmm0 = 16xYY
	%ELSE
	lddqu			xmm0, DQWORD [r12+ 0]				; xmm0 = 16xYY
	%ENDIF	
	punpckhbw		xmm1, xmm0						; xmm1 = (Y0 Y0 Y0 Y0) x4
	punpcklbw		xmm0, xmm15						; xmm0 = (0Y 0Y 0Y 0Y) x4
	psrlw			xmm1, 8							; xmm1 = (0Y 0Y 0Y 0Y) x4
	movdqa			[r10+rax], xmm0					; store base words
	movdqa			[r10+rax+16], xmm1				; store base words
	add				eax, 32
	add				r12d, 16
	sub				r11d, 16
	ja				.yv_deintloop16

align 16
.yv_xloop_pre:
	mov				rax, rdx						; copy the dstp for inner loop
	add				rcx, .src_pitch					; srcp+=src_pitch
	add				rdx, .dst_pitch					; dstp+=dst_pitch			  

align 16
.yv_xloop:
	mov				r10d, DWORD [r14]				; r10 = &tempY[ofs0]
	mov				r12d, DWORD [r14+(%2*8+8)]		; r12 = next &tempY[ofs1]
	movdqa			xmm1, xmm14						; start with rounder 
	movdqa			xmm3, xmm14						; start with rounder
	mov				r11d, DWORD [r14+4]				; r11 = &tempY[ofs1]
	mov				r13d, DWORD [r14+(%2*8+8)+4]	; r13 = next &tempY[ofs1]
	
	mov				ebx, DWORD [r14+(%2*8+8)*2]
	mov				edi, DWORD [r14+(%2*8+8)*2+4]
	movdqa			xmm5, xmm14
	movdqa			xmm7, xmm14
	mov				r8d, DWORD [r14+(%2*8+8)*3]
	mov				r9d, DWORD [r14+(%2*8+8)*3+4]
	
	add				r14, 8							; cur_luma++

	%ASSIGN i 0
	%REP (%2 / 2)
	%IF (i % 2 == 0)
	movdqu			xmm2, [r10+i*8]					; mm2 =  0| 0|Yb|Ya
	movdqu			xmm10, [r11+i*8]
	movdqa			xmm0, xmm2
		
	punpckldq		xmm2, xmm10						; mm2 = Yn|Ym|Yb|Ya
	punpckhdq		xmm0, xmm10						; mm2 = Yn|Ym|Yb|Ya
	
	movdqu			xmm4, [r12+i*8]
	movdqu			xmm11, [r13+i*8]
	movdqa			xmm6, xmm4
	
	punpckldq		xmm4, xmm11						; [r14] = COn|COm|COb|COa
	punpckhdq		xmm6, xmm11

	movdqu			xmm8, [r14+i*16]				;can grab 2 coefficients at once . . .
	movdqu			xmm9, [r14+(%2*8+8)+i*16]	
	
	pmaddwd			xmm2, xmm8						; mm2 = Y1|Y0 (DWORDs)
	pmaddwd			xmm4, xmm9						; mm4 = Y1|Y0 (DWORDs)

	paddd			xmm1, xmm2						; accumulate
	paddd			xmm3, xmm4						; accumulate
	%ELSE
	movdqu			xmm8, [r14+i*16]				;can grab 2 coefficients at once . . .
	movdqu			xmm9, [r14+(%2*8+8)+i*16]	
	
	pmaddwd			xmm0, xmm8						; mm2 = Y1|Y0 (DWORDs)
	pmaddwd			xmm6, xmm9						; mm4 = Y1|Y0 (DWORDs)

	paddd			xmm1, xmm0						; accumulate
	paddd			xmm3, xmm6						; accumulate
	%ENDIF
	
	%IF (i % 2 == 0)
	;second pair
	movdqu			xmm2, [rbx+i*8]					; mm2 =  0| 0|Yb|Ya
	movdqu			xmm10, [rdi+i*8]
	movdqa			xmm12, xmm2
	
	punpckldq		xmm2, xmm10					; mm2 = Yn|Ym|Yb|Ya
	punpckhdq		xmm12, xmm10
	
	movdqu			xmm4, [r8+i*8]
	movdqu			xmm11, [r9+i*8]	
	movdqa			xmm13, xmm4
	
	punpckldq		xmm4, xmm11					; [r14] = COn|COm|COb|COa
	punpckhdq		xmm13, xmm11

	movdqu			xmm8, [r14+(%2*8+8)*2+i*16]		;can grab 2 coefficients at once . . .
	movdqu			xmm9, [r14+(%2*8+8)*3+i*16]
	
	pmaddwd			xmm2, xmm8					; mm2 = Y1|Y0 (DWORDs)
	pmaddwd			xmm4, xmm9					; mm4 = Y1|Y0 (DWORDs)

	paddd			xmm5, xmm2					; accumulate
	paddd			xmm7, xmm4					; accumulate
	%ELSE
	movdqu			xmm8, [r14+(%2*8+8)*2+i*16]		;can grab 2 coefficients at once . . .
	movdqu			xmm9, [r14+(%2*8+8)*3+i*16]
	
	pmaddwd			xmm12, xmm8					; mm2 = Y1|Y0 (DWORDs)
	pmaddwd			xmm13, xmm9					; mm4 = Y1|Y0 (DWORDs)

	paddd			xmm5, xmm12					; accumulate
	paddd			xmm7, xmm13					; accumulate
	%ENDIF
	%ASSIGN i i+1
	%ENDREP
	
	
	%IF((%2 % 2) == 1)
	%ASSIGN i (%2 - 1)
	movd			xmm2, [r10+i*4]					; mm2 =  0| 0|Yb|Ya
	movd			xmm10, [r11+i*4]
	punpckldq		xmm2, xmm10						; mm2 = Yn|Ym|Yb|Ya
	
	movd			xmm4, [r12+i*4]
	movd			xmm11, [r13+i*4]
	punpckldq		xmm4, xmm11						; [r14] = COn|COm|COb|COa
	
	movq			xmm8, [r14+i*8]				;can grab 2 coefficients at once . . .
	movq			xmm9, [r14+(%2*8+8)+i*8]
	pmaddwd			xmm2, xmm8						; mm2 = Y1|Y0 (DWORDs)
	pmaddwd			xmm4, xmm9						; mm4 = Y1|Y0 (DWORDs)

	paddd			xmm1, xmm2						; accumulate
	paddd			xmm3, xmm4						; accumulate
	
	;second pair
	movd			xmm2, [rbx+i*4]					; mm2 =  0| 0|Yb|Ya
	movd			xmm10, [rdi+i*4]
	punpckldq		xmm2, xmm10					; mm2 = Yn|Ym|Yb|Ya
	
	movd			xmm4, [r8+i*4]
	movd			xmm11, [r9+i*4]	
	punpckldq		xmm4, xmm11				; [r14] = COn|COm|COb|COa
	
	movq			xmm8, [r14+(%2*8+8)*2+i*8]					;can grab 2 coefficients at once . . .
	movq			xmm9, [r14+(%2*8+8)*3+i*8]
	pmaddwd			xmm2, xmm8					; mm2 = Y1|Y0 (DWORDs)	
	pmaddwd			xmm4, xmm9					; mm4 = Y1|Y0 (DWORDs)

	paddd			xmm5, xmm2					; accumulate
	paddd			xmm7, xmm4					; accumulate
	%ENDIF
	
	movdqa			xmm2, xmm1
	movdqa			xmm4, xmm5
	unpckhpd		xmm2, xmm3
	unpcklpd		xmm1, xmm3
	paddd 			xmm1, xmm2
	
	unpckhpd		xmm4, xmm7
	unpcklpd		xmm5, xmm7
	paddd 			xmm5, xmm4
	

	add				r14, (%2*8+8)*3+(%2*8)			; curr_luma += filter_offset
	psrad			xmm1, 14							; mm1 = --y1|--y0
	psrad			xmm5, 14							; mm3 = --y3|--y2
		
	packssdw		xmm1, xmm5						; mm1 = -3|-2|-1|-0
	packuswb		xmm1, xmm1						; mm1 = 3|2|1|0 3|2|1|0		
	
	movq			[rax], xmm1
	add				eax, 8
	sub				ebp, 1
	ja				.yv_xloop

.endyloop:
	sub				esi, 1
	ja				.yv_yloop

.endfunc:
	pop r14
	pop r13
	pop r12
	pop rbp
	pop rbx
	pop rsi
	pop rdi
%ENDMACRO
	
;=============================================================================
; Instantiation of macros (yasm doesn't like ret in a macro when using PROC_FRAME)
;=============================================================================
section .text
%ASSIGN y 1
%REP 3

FRH_yv12_memtpye_firsize_new aligned,y
ret
ENDPROC_FRAME

FRH_yv12_memtpye_firsize_new unaligned,y
ret
ENDPROC_FRAME

%ASSIGN y y+1
%ENDREP

%REP 21

FRH_yv12_memtpye_firsize_new aligned,y
ret
ENDPROC_FRAME

FRH_yv12_memtpye_firsize_new unaligned,y
ret
ENDPROC_FRAME

%ASSIGN y y+1
%ENDREP

;=============================================================================
; Just another idea for repacking the pixels at the end of the function, figured I'd hold onto it
;=============================================================================
;movhlps			xmm2, xmm1
;movhlps			xmm4, xmm5

;movlhps			xmm2, xmm3
;movlhps			xmm4, xmm7

;psrldq				xmm3, 8
;psrldq				xmm7, 8

;movlhps			xmm1, xmm3
;paddd				xmm1, xmm2

;movlhps			xmm5, xmm7
;paddd				xmm5, xmm4