;%include "./convert/amd64inc.asm"

;=============================================================================
; Function declarations
;=============================================================================
%ASSIGN y 2
%REP 11
	global FRV_aligned_SSSE3_FIR %+ y
	global FRV_unaligned_SSSE3_FIR %+ y
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
PROC_FRAME FRV_ %+ %1 %+ _SSSE3_FIR %+ %2
	
	push		rbx
	[pushreg	rbx]
	push		rbp
	[pushreg	rbp]
	push		rsi
	[pushreg	rsi]
	push		rdi
	[pushreg	rdi]
	push		r12
	[pushreg	r12]
END_PROLOG

%DEFINE .int_yloop	[rsp+40+40] ;two xmm reg saves (+32) and 3 gpr saves (+24)
%DEFINE .int_xloop	[rsp+40+48]
%DEFINE .intp_yOfs	[rsp+40+56]
%DEFINE .intp_cur	[rsp+40+64]

%ASSIGN i 0
	
	mov			r11, .intp_cur					; load pointer cur, used in loop
	mov			ebx, DWORD .int_yloop			; load y loop counter
	mov			ebp, DWORD .int_xloop			; load x counter 
	movdqa		xmm6, [rel FProundXMM]			; Rounder for final division. Not touched!
	movdqa		xmm0, [rel UnPackByteShuff]		; For unpacking the coefficient
	pxor		xmm5, xmm5						; zero xmm5
	

align 16
.yloop: 
	mov			rsi, .intp_yOfs
	mov			eax, DWORD [r11]				; dereferenced current is this ever negative? (movsxd?)
	mov			r10d, DWORD [rsi+rax*4]			; yOfs[*cur]
	add			r11, 4							; cur++
	
	mov			eax, DWORD [r11+(%2*4)]			; dereferenced curr->next
	mov			r12d, DWORD [rsi+rax*4]
	
	add			r10, rcx						; r10 = srcp + yOfs[*cur]
	add			r12, rcx
	xor			eax, eax						; eax = x = 0

align 16 
.xloop:
	lea			rsi, [r10+rax]					; rsi = srcp2 = srcp + x
	lea			rdi, [r12+rax]
		
%IFIDNI %1, aligned
	movdqa		xmm4, DQWORD [rsi]				; xmm4 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
	movdqa		xmm12, DQWORD [rdi]
%ELSE
	lddqu		xmm4, DQWORD [rsi]				; xmm4 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
	lddqu		xmm12, DQWORD [rdi]
%ENDIF

	movdqa		xmm7, xmm6						; Accumulator 1a
	movdqa		xmm1, xmm6						; Accumulator 2a
	movdqa		xmm15, xmm6						; Accumulator 1b
	movdqa		xmm9, xmm6						; Accumulator 1b
	
%REP %2
	prefetchnta	[rsi+r8]
	prefetchnta	[rdi+r8]
	
	movd		xmm3, DWORD [r11+(i*4)]			; current fir coefficient
	movd		xmm11,DWORD [r11+(i*4)+(%2*4)+4]
	
	movdqa		xmm2, xmm4						; xmm2 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
	movdqa		xmm10, xmm12

	punpckhbw	xmm4, xmm5						; xmm5=0, xmm4 = *srcp2 = 0p|0o|0n|0m|0l|0k|0j|0i
	punpcklbw	xmm2, xmm5						; xmm2=0, xmm2 = *srcp2 = 0h|0g|0f|0e|0d|0c|0b|0a
	
	punpckhbw	xmm12, xmm5						; xmm5=0, xmm4 = *srcp2 = 0p|0o|0n|0m|0l|0k|0j|0i
	punpcklbw	xmm10, xmm5						; xmm2=0, xmm2 = *srcp2 = 0h|0g|0f|0e|0d|0c|0b|0a
	
	pshufb		xmm3, xmm0						; unpack coefficient to all bytes
	pshufb		xmm11, xmm0
	
	psllw		xmm2, 7							; Extend to signed word
	psllw		xmm4, 7							; Extend to signed word
	
	psllw		xmm10, 7						; Extend to signed word
	psllw		xmm12, 7						; Extend to signed word
%IF (i < (%2 - 1))	
	add			rsi, r8							; src2p = srcp2+src_pitch
	add			rdi, r8
%ENDIF
	pmulhrsw	xmm2, xmm3						; Multiply 14bit(coeff) x 16bit (signed) -> 16bit signed and rounded result.  [h|g|f|e|d|c|b|a]
	pmulhrsw	xmm3, xmm4						; Multiply [p|o|n|m|l|k|j|i]

%IF (i < (%2 - 1))								; Load next set of pixels for FIR unrolled code
	%IFIDNI %1,aligned
		movdqa	xmm4, DQWORD [rsi]				; xmm4 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
	%ELSE
		lddqu	xmm4, DQWORD [rsi]				; xmm4 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
	%ENDIF
%ENDIF

	pmulhrsw	xmm10, xmm11
	pmulhrsw	xmm11, xmm12

%IF (i < (%2 - 1))								; Load next set of pixels for FIR unrolled code
	%IFIDNI %1,aligned
		movdqa	xmm12, DQWORD [rdi]				; xmm4 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
	%ELSE
		lddqu	xmm12, DQWORD [rdi]				; xmm4 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
	%ENDIF
%ENDIF

	paddsw		xmm1, xmm2						; Accumulate: h|g|f|e|d|c|b|a (signed words)
	paddsw		xmm7, xmm3						; Accumulate: p|o|n|m|l|k|j|i
	
	paddsw		xmm9, xmm10						; Accumulate: h|g|f|e|d|c|b|a (signed words)
	paddsw		xmm15, xmm11					; Accumulate: p|o|n|m|l|k|j|i

%ASSIGN i i+1
%ENDREP

    psraw		xmm1, 6							; Compensate fraction
    psraw		xmm7, 6							; Compensate fraction
    packuswb	xmm1, xmm7						; xmm1 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
    
    psraw		xmm9, 6							; Compensate fraction
    psraw		xmm15, 6						; Compensate fraction
    packuswb	xmm9, xmm15						; xmm1 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
    
    lea			rdi, [rdx+r9]
    movdqa		DQWORD [rdx+rax], xmm1			; store calculated pixels in dest[x]  
    movdqa		DQWORD [rdi+rax], xmm9
    
    add			eax,16							; x+=16
    cmp			eax, ebp						; xloop stored in ebp
    jl			.xloop
    			
    lea			rdx,[rdx+r9*2]					; pDst += pDstPitch
    add			r11,(%2*8)+4					; cur += fir_filter_size
    sub			ebx, 2							; y loop counter
    ja			.yloop

	pop			r12
	pop			rdi
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