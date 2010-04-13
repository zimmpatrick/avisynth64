;%include "./convert/amd64inc.asm"

;=============================================================================
; Function declarations
;=============================================================================
%ASSIGN y 13
%REP 20

	global FRV_aligned_SSE2_FIR %+ y
	global FRV_unaligned_SSE2_FIR %+ y

%ASSIGN y y+1
%ENDREP

	global FRV_aligned_SSE2_FIR1
	global FRV_unaligned_SSE2_FIR1
	
;=============================================================================
; Read only data
;=============================================================================
SECTION .rodata align=16
FProundXMM:
	dq 00000200000002000h
	dq 00000200000002000h	
		
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
PROC_FRAME FRV_ %+ %1 %+ _SSE2_FIR %+ %2
	
	push		rbx
	[pushreg	rbx]
	push		rbp
	[pushreg	rbp]
	push		rsi
	[pushreg	rsi]

END_PROLOG

%DEFINE .int_yloop	[rsp+24+40] ;two xmm reg saves (+32) and 3 gpr saves (+24)
%DEFINE .int_xloop	[rsp+24+48]
%DEFINE .intp_yOfs	[rsp+24+56]
%DEFINE .intp_cur	[rsp+24+64]

%ASSIGN i 0
	
	mov			r11, .intp_cur					; load pointer cur, used in loop
	mov			ebx, DWORD .int_yloop			; load y loop counter
	mov			ebp, DWORD .int_xloop			; load x counter 
	movdqa		xmm8, [rel FProundXMM]

align 16
.yloop: 
	mov			r10, .intp_yOfs
	mov			eax, DWORD [r11]				; dereferenced current is this ever negative?
	mov			r10d, DWORD [r10+rax*4]			; yOfs[*cur]
	add			r11, 4							; cur++
	add			r10, rcx						; r10 = srcp + yOfs[*cur]
	xor			eax, eax						; eax = x = 0

align 16 
.xloop:
	lea			rsi, [r10+rax]					; rsi = srcp2 = srcp + x
			
	prefetchnta	[rsi+256]
	%IFIDNI %1, aligned
		movdqa		xmm0, DQWORD [rsi]				; xmm0 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
	%ELSE
		movdqu		xmm0, DQWORD [rsi]				; xmm0 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
	%ENDIF
	
	movdqa		xmm7, xmm8						; Accumulator 1 = rounder
	movdqa		xmm4, xmm8						; Accumulator 2 = rounder
	movdqa		xmm5, xmm8						; Accumulator 3 = rounder 
	movdqa		xmm6, xmm8						; Accumulator 4 = rounder
	
	%REP (%2/2)
	movq		xmm3, QWORD [r11+(i*8)]			; 00|00|00|00|xx|[coefficient+1]|xx|[coefficient] 
	
	%IFIDNI %1, aligned
		movdqa		xmm2, DQWORD [rsi+r8]			; xmm2 = P|O|N|M|L|K|J|I|H|G|F|E|D|C|B|A
	%ELSE
		movdqu		xmm2, DQWORD [rsi+r8]			; xmm2 = P|O|N|M|L|K|J|I|H|G|F|E|D|C|B|A
	%ENDIF						
	
	%IF (i*2 < (%2 - 2))
	lea			rsi, [rsi+r8*2]					; src2p = srcp2+2*src_pitch
	%ENDIF
	
	movdqa		xmm1, xmm0						; xmm1 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
	packssdw	xmm3, xmm3						; 00|00|00|00|[coeff+1]|[coeff]|[coeff+1]|[coeff]
	punpcklbw	xmm0, xmm2						; xmm0 = Hh|Gg|Ff|Ee|Dd|Cc|Bb|Aa
    punpckhbw	xmm1, xmm2						; xmm1 = Pp|Oo|Nn|Mm|Ll|Kk|Jj|Ii
	pshufd		xmm3, xmm3, 0					; unpack coefficient
	punpckhbw	xmm2, xmm0						; xmm2 = HP|hO|GN|gM|FL|fK|EJ|eI
	punpcklbw	xmm0, xmm0						; xmm0 = DD|dd|CC|cc|BB|bb|AA|aa
	psrlw		xmm2, 8							; xmm2 = 0H|0h|0G|0g|0F|0f|0E|0e
	psrlw		xmm0, 8							; xmm0 = 0D|0d|0C|0c|0B|0b|0A|0a

	pmaddwd		xmm2, xmm3						; xmm2 =  H*CO+h*co|G*CO+g*co|F*CO+f*co|E*CO+e*co
	pmaddwd		xmm0, xmm3						; xmm0 =  D*CO+d*co|C*CO+c*co|B*CO+b*co|A*CO+a*co
	paddd		xmm5, xmm2						; accumulateHGFE
	paddd		xmm4, xmm0						; accumulateDCBA
	pxor		xmm0, xmm0						;
	movdqa		xmm2, xmm1						; xmm2 = Pp|Oo|Nn|Mm|Ll|Kk|Jj|Ii
	punpcklbw	xmm1, xmm0						; xmm1 = 0L|0l|0K|0k|0J|0j|0I|0i
	punpckhbw	xmm2, xmm0						; xmm2 = 0P|0p|0O|0o|0N|0n|0M|0m

	%IF (i*2 < (%2 - 2))							; Load next set of pixels for FIR unrolled code
		%IFIDNI %1,aligned
			movdqa		xmm0, DQWORD [rsi]				; xmm0 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
		%ELSE
			movdqu		xmm0, DQWORD [rsi]				; xmm0 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
		%ENDIF
	%ENDIF

	pmaddwd		xmm1, xmm3						; xmm1 =  L*CO+l*co|K*CO+k*co|J*CO+j*co|I*CO+i*co
	pmaddwd		xmm2, xmm3						; xmm4 =  P*CO+p*co|O*CO+o*co|N*CO+n*co|M*CO+m*co
	paddd		xmm6, xmm1						; accumulateLKJI
	paddd		xmm7, xmm2						; accumulatePONM

	%ASSIGN i i+1
	%ENDREP
	
	%IF (%2 % 2 == 1)							; process last odd row
	movd		xmm3, DWORD [r11+(i*8)]			; 00|00|00|00|xx|xx|xx|[coefficient]-->should move 64 bits, 32bit mem moves are actually slower
												; could cause memory access violation, test later
	pxor		xmm2, xmm2
	punpckhbw	xmm1, xmm0						; xmm1 = p.|o.|n.|m.|l.|k.|j.|i.
	pshufd		xmm3, xmm3, 0					; xmm3 = --co|--co|--co|--co
	punpcklbw	xmm0, xmm2						; xmm0 = 0h|0g|0f|0e|0d|0c|0b|0a 
	pslld		xmm3, 16						; xmm3 = co|00|co|00|co|00|co|00
	psrlw		xmm1, 8							; xmm1 = 0p|0o|0n|0m|0l|0k|0j|0i
	punpckhwd	xmm2, xmm0						; xmm2 = 0h|..|0g|..|0f|..|0e|..
	punpcklwd	xmm0, xmm0						; xmm0 = 0d|0d|0c|0c|0b|0b|0a|0a
	pmaddwd		xmm2, xmm3						; xmm2 =  h*co|g*co|f*co|e*co
	pmaddwd		xmm0, xmm3						; xmm0 =  d*co|c*co|b*co|a*co
	paddd		xmm5, xmm2						; accumulateHGFE
	paddd		xmm4, xmm0						; accumulateDCBA
	punpckhwd	xmm2, xmm1						; xmm2 = 0p|..|0o|..|0n|..|0m|..
	punpcklwd	xmm1, xmm1						; xmm1 = 0l|0l|0k|0k|0j|0j|0i|0i
	pmaddwd		xmm2, xmm3						; xmm4 =  p*co|o*co|n*co|m*co
	pmaddwd		xmm1, xmm3						; xmm1 =  l*co|k*co|j*co|i*co
	paddd		xmm7, xmm2						; accumulatePONM
	paddd		xmm6, xmm1						; accumulateLKJI											
    %ENDIF
	
	psrad		xmm4, 14						; 14 bits -> 16bit fraction [--FF....|--FF....]
	psrad		xmm5, 14						; compensate the fact that FPScale = 16384
	psrad		xmm6, 14						;
	psrad		xmm7, 14						;
	packssdw	xmm4, xmm5						; xmm4 = 0h|0g|0f|0e|0d|0c|0b|0a
	packssdw	xmm6, xmm7						; xmm6 = 0p|0o|0n|0m|0l|0k|0j|0i
	packuswb	xmm4, xmm6						; xmm4 = p|o|n|m|l|k|j|i|h|g|f|e|d|c|b|a
    movdqa		DQWORD [rdx+rax], xmm4			; store calculated pixels in dest[x]
	add			eax, 16							; x+=16
	cmp			eax, ebp						; xloop stored in ebp
    jl			.xloop
    			
    add			rdx,r9							; pDst += pDstPitch
    add			r11,(%2*4)						; cur += fir_filter_size
    sub			ebx, 1							; y loop counter
    ja			.yloop


    pop			rsi
    pop			rbp
    pop			rbx
%ENDMACRO

;=============================================================================
; Instantiation of aligned macros (yasm doesn't like ret in a macro when using PROC_FRAME)
;=============================================================================
section .text

%ASSIGN y 13
%REP 20

FRV_memtpye_firsize aligned,y
ret
ENDPROC_FRAME

FRV_memtpye_firsize unaligned,y
ret
ENDPROC_FRAME

%ASSIGN y y+1
%ENDREP

;=============================================================================
; void FRV_SSE2_aligned_FIR1 (int *srcp, int *dstp, int src_pitch, int dst_pitch, int yloops, int xloops, int *yOfs, int *cur)
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

align 16
PROC_FRAME FRV_aligned_SSE2_FIR1
	push		rbx
	[pushreg	rbx]
	push		rbp
	[pushreg	rbp]
END_PROLOG

%DEFINE .int_yloop	[rsp+16+40] ;two xmm reg saves (+32) and 3 gpr saves (+24)
%DEFINE .int_xloop	[rsp+16+48]
%DEFINE .intp_yOfs	[rsp+16+56]
%DEFINE .intp_cur	[rsp+16+64]
	
	mov			r11, .intp_cur					; load pointer cur, used in loop
	mov			ebx, DWORD .int_yloop			; load y loop counter
	mov			ebp, DWORD .int_xloop			; load x counter 

align 16
.yloop: 
	mov			r10, .intp_yOfs
	mov			eax, DWORD [r11]				; dereferenced current is this ever negative?
	mov			r10d, DWORD [r10+rax*4]			; yOfs[*cur]
	add			r11, 8							; cur++
	add			r10, rcx						; r10 = srcp + yOfs[*cur]
	xor			eax, eax
	mov			r8d, ebp
	and			r8d, 0FFFFFF80h
	jz			.xloop64_a
	
align 16
.xloop128:
	prefetchnta	[r10+rax+256]
	movdqa		xmm0,DQWORD [r10 + rax +   0]
	movdqa		xmm1,DQWORD [r10 + rax +  16]
	movdqa		DQWORD[rdx + rax +   0], xmm0
	movdqa		DQWORD[rdx + rax +  16], xmm1
	
	movdqa		xmm2,DQWORD [r10 + rax +  32]
	movdqa		xmm3,DQWORD [r10 + rax +  48]
	movdqa		DQWORD[rdx + rax +  32], xmm2
	movdqa		DQWORD[rdx + rax +  48], xmm3
	
	add			eax, 128
	cmp			eax, r8d
	
	movdqa		xmm4,DQWORD [r10 + rax-128 +  64]
	movdqa		xmm5,DQWORD [r10 + rax-128 +  80]
	movdqa		DQWORD[rdx + rax-128 +  64], xmm4
	movdqa		DQWORD[rdx + rax-128 +  80], xmm5
	
	movdqa		xmm6,DQWORD [r10 + rax-128 +  96]
	movdqa		xmm7,DQWORD [r10 + rax-128 + 112]
	movdqa		DQWORD[rdx + rax-128 +  96], xmm6
	movdqa		DQWORD[rdx + rax-128 + 112], xmm7
	

	jb			.xloop128
	
	test		ebp, 127
	jz			.no_remain
				

align 16
.xloop64_a:
	test		ebp, 0FFFFFFC0h
	jz			.xloop_remain

align 16
.xloop64:
	prefetchnta	[r10+rax+256]
	movdqa		xmm0,DQWORD [r10 + rax +  0]
	movdqa		xmm1,DQWORD [r10 + rax + 16]
	movdqa		DQWORD[rdx + rax +  0], xmm0
	movdqa		DQWORD[rdx + rax + 16], xmm1
	
	movdqa		xmm2,DQWORD [r10 + rax + 32]
	movdqa		xmm3,DQWORD [r10 + rax + 48]
	movdqa		DQWORD[rdx + rax + 32], xmm2
	movdqa		DQWORD[rdx + rax + 48], xmm3
	add			eax, 64
	
	test		ebp, 63
	jz			.no_remain
	
align 16
.xloop_remain:
	movdqa		xmm0,DQWORD [r10 + rax]
	movdqa	 	DQWORD[rdx + rax], xmm0
	add			eax, 16
	cmp			eax, ebp
	jb			.xloop_remain
	
align 16
.no_remain:
	add			rdx, r9
	sub			ebx, 1
	ja			.yloop
	
    pop			rbp
    pop			rbx
    mfence
    ret
[ENDPROC_FRAME]


;=============================================================================
; void FRV_SSE2_unaligned_FIR1 (int *srcp, int *dstp, int src_pitch, int dst_pitch, int yloops, int xloops, int *yOfs, int *cur)
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

align 16
PROC_FRAME FRV_unaligned_SSE2_FIR1
	push		rbx
	[pushreg	rbx]
	push		rbp
	[pushreg	rbp]
END_PROLOG

%DEFINE .int_yloop	[rsp+16+40] ;two xmm reg saves (+32) and 3 gpr saves (+24)
%DEFINE .int_xloop	[rsp+16+48]
%DEFINE .intp_yOfs	[rsp+16+56]
%DEFINE .intp_cur	[rsp+16+64]
	
	mov			r11, .intp_cur					; load pointer cur, used in loop
	mov			ebx, DWORD .int_yloop			; load y loop counter
	mov			ebp, DWORD .int_xloop			; load x counter 

align 16
.yloop: 
	mov			r10, .intp_yOfs
	mov			eax, DWORD [r11]				; dereferenced current is this ever negative?
	mov			r10d, DWORD [r10+rax*4]			; yOfs[*cur]
	add			r11, 8							; cur++
	add			r10, rcx						; r10 = srcp + yOfs[*cur]
	xor			eax, eax
	mov			r8d, ebp
	and			r8d, 0FFFFFF80h
	jz			.xloop64_a
	
align 16
.xloop128:
	prefetchnta	[r10+rax+256]
	movdqu		xmm0,DQWORD [r10 + rax +   0]
	movdqu		xmm1,DQWORD [r10 + rax +  16]
	movdqu		DQWORD[rdx + rax +   0], xmm0
	movdqu		DQWORD[rdx + rax +  16], xmm1
	
	movdqu		xmm2,DQWORD [r10 + rax +  32]
	movdqu		xmm3,DQWORD [r10 + rax +  48]
	movdqu		DQWORD[rdx + rax +  32], xmm2
	movdqu		DQWORD[rdx + rax +  48], xmm3
	
	add			eax, 128
	cmp			eax, r8d	
	
	movdqu		xmm4,DQWORD [r10 + rax-128 +  64]
	movdqu		xmm5,DQWORD [r10 + rax-128 +  80]
	movdqu		DQWORD[rdx + rax-128 +  64], xmm4
	movdqu		DQWORD[rdx + rax-128 +  80], xmm5
	
	movdqu		xmm6,DQWORD [r10 + rax-128 +  96]
	movdqu		xmm7,DQWORD [r10 + rax-128 + 112]
	movdqu		DQWORD[rdx + rax-128 +  96], xmm6
	movdqu		DQWORD[rdx + rax-128 + 112], xmm7
	
	jb			.xloop128
	
	test		ebp, 127
	jz			.no_remain	

align 16
.xloop64_a:
	test		ebp, 0FFFFFFC0h
	jz			.xloop_remain

align 16
.xloop64:
	prefetchnta	[r10+rax+128]
	movdqu		xmm0,DQWORD [r10 + rax +  0]
	movdqu		xmm1,DQWORD [r10 + rax + 16]
	movdqu		DQWORD[rdx + rax +  0], xmm0
	movdqu		DQWORD[rdx + rax + 16], xmm1
	
	movdqu		xmm2,DQWORD [r10 + rax + 32]
	movdqu		xmm3,DQWORD [r10 + rax + 48]
	movdqu		DQWORD[rdx + rax + 32], xmm2
	movdqu		DQWORD[rdx + rax + 48], xmm3
	add			eax, 64
	
	test		ebp, 63
	jz			.no_remain
	
align 16
.xloop_remain:
	movdqu		xmm0,DQWORD [r10 + rax]
	movntdq		DQWORD[rdx + rax], xmm0
	add			eax, 16
	cmp			eax, ebp
	jb			.xloop_remain
	
align 16
.no_remain:
	add			rdx, r9
	sub			ebx, 1
	ja			.yloop
	
    pop			rbp
    pop			rbx
    sfence
    ret
[ENDPROC_FRAME]
	
	