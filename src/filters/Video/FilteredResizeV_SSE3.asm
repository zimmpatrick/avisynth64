;=============================================================================
; Function declarations
;=============================================================================
%ASSIGN y 2
%REP 11
	global FRV_aligned_SSE3_FIR %+ y
	global FRV_unaligned_SSE3_FIR %+ y
%ASSIGN y y+1
%ENDREP
	
;=============================================================================
; Read only data
;=============================================================================
SECTION .rodata align=16
FProundXMM:
	dq 00020002000200020h
	dq 00020002000200020h
UnPackByteShuff:
	dq 00100010001000100h
	dq 00100010001000100h
		
;Macro to generate the functions based on FIR size-->allows loops unrolling
;=============================================================================
; void FRV_(aligment)_FIR(size) (int *srcp, int *dstp, int src_pitch, int dst_pitch, int yloops, int xloops, int *yOfs, int *cur)
;=============================================================================	
; parameter 1(srcp):		rcx
; parameter 2(dstp):		rdx
; parameter 3(src_pitch):	r8d
; parameter 4(dst_pitch):	r9d 
; parameter 5(yloops):		rsp+40
; parameter 6(xloops):		rsp+48
; parameter 6(yOfs):		rsp+56
; parameter 7(cur):			rsp+64

; eax=inner loop counter (x)
; ebx=outer loop counter (y)
; r10=yOfs
; r11=cur

;params [alignment,FIR filter size]
%MACRO FRV_memtpye_firsize 2
align 16
PROC_FRAME FRV_ %+ %1 %+ _SSE3_FIR %+ %2
	
	push		rbx
	[pushreg	rbx]
	push		rbp
	[pushreg	rbp]
	push		rsi
	[pushreg	rsi]
	alloc_stack  0x70
	save_xmm128  xmm6,0x00

END_PROLOG

%DEFINE .int_yloop	[rsp+24+40] ;two xmm reg saves (+32) and 3 gpr saves (+24)
%DEFINE .int_xloop	[rsp+24+48]
%DEFINE .intp_yOfs	[rsp+24+56]
%DEFINE .intp_cur	[rsp+24+64]
%ASSIGN i 0
	
	mov			r11, .intp_cur					; load pointer cur, used in loop
	mov			ebx, DWORD .int_yloop			; load y loop counter
	mov			ebp, DWORD .int_xloop			; load x counter 
	movdqa		xmm6, [rel FProundXMM]			; Rounder for final division. Not touched!
	pxor		xmm0, xmm0						; zero xmm0
	
	; initialize them once here, and then can move thier 
	; initilization to the end of every x loop to save setup time(hopefully)
	
	movdqa		xmm1, xmm6						; Accumulator 1
	movdqa		xmm2, xmm6						; Accumulator 2

align 16
.yloop: 
	mov			rsi, .intp_yOfs
	mov			eax, DWORD [r11]				; dereferenced current 
	mov			r10d, DWORD [rsi+rax*4]			; yOfs[*cur]
	add			r11, 4							; cur++	
	add			r10, rcx						; r10 = srcp + yOfs[*cur]
	xor			eax, eax						; eax = x = 0
	
align 16 
.xloop:
	lea			rsi, [r10+rax]					; rsi = srcp2 = srcp + x
		
%IFIDNI %1, aligned
	movdqa		xmm4, DQWORD [rsi]				; xmm4 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
%ELSE
	lddqu		xmm4, DQWORD [rsi]				; xmm4 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
%ENDIF

%REP %2
	
	movd		xmm3, DWORD [r11+(i*4)]			; current fir coefficient
	movdqa		xmm5, xmm4						; xmm2 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
	pshuflw		xmm3, xmm3, 0					; unpack coefficient to all low words
	
	punpckhbw	xmm4, xmm0						; xmm5=0, xmm4 = *srcp2 = 0p|0o|0n|0m|0l|0k|0j|0i
	punpcklbw	xmm5, xmm0						; xmm2=0, xmm2 = *srcp2 = 0h|0g|0f|0e|0d|0c|0b|0a
	
	movddup		xmm3, xmm3						; copy xmm3[63..0] to xmm3[127..64] 
	
	psllw		xmm4, 7							; Extend to signed word
	psllw		xmm5, 7							; Extend to signed word
	
%IF (i < (%2 - 1))	
	add			rsi, r8							; src2p = srcp2+src_pitch
%ENDIF
	pmulhw		xmm5, xmm3						; mimics pmulhrsw by doing a mult, and then shifting in 0
	pmulhw		xmm3, xmm4						; pmulhrsw would shift in a 0 or 1 based upon rounding (see left shifts below)
	
	prefetchnta	[rsi+r8]
	
	psllw		xmm5, 1							; which is done internally, so we have no "easy" clues as to which bit to change, fastest is to guess 0 shifts in
	psllw		xmm3, 1							; Works for AMD processors-->unfortunately lose nice internal rounding of pmulhrsw
												; Another unfortunate side effect is addition of two shift instructions

%IF (i < (%2 - 1))								; Load next set of pixels for FIR unrolled code
	%IFIDNI %1,aligned
		movdqa	xmm4, DQWORD [rsi]				; xmm4 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
	%ELSE
		lddqu	xmm4, DQWORD [rsi]				; xmm4 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
	%ENDIF
%ENDIF

	paddsw		xmm1, xmm5						; Accumulate: h|g|f|e|d|c|b|a (signed words)
	paddsw		xmm2, xmm3						; Accumulate: p|o|n|m|l|k|j|i

%ASSIGN i i+1
%ENDREP

    psraw		xmm1, 6							; Compensate fraction
    psraw		xmm2, 6							; Compensate fraction
    packuswb	xmm1, xmm2						; xmm1 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
    movdqa		DQWORD [rdx+rax], xmm1			; store calculated pixels in dest[x] 
    
    add			eax, 16							; x+=16
    cmp			eax, ebp						; xloop stored in ebp
    movdqa		xmm2, xmm6						; Accumulator 1
	movdqa		xmm1, xmm6						; Acc 2 = total = rounder
    jl			.xloop
    			
    add			rdx,r9							; pDst += pDstPitch
    add			r11,(%2*4)						; cur += fir_filter_size
    sub			ebx, 1							; y loop counter
    ja			.yloop

	movdqa		xmm6,[rsp+16*0]					;Restore volatile register
	add			rsp, 0x10
	
    pop			rsi
    pop			rbp
    pop			rbx
%ENDMACRO


;=============================================================================
; Instantiation of aligned macros (yasm doesn't like ret in a macro when using PROC_FRAME)
;=============================================================================
section .text
%ASSIGN y 2
%REP 11

FRV_memtpye_firsize aligned,y
ret
ENDPROC_FRAME

FRV_memtpye_firsize unaligned,y
ret
ENDPROC_FRAME

%ASSIGN y y+1
%ENDREP