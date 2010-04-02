BITS 64

%macro cglobal 1
	%ifdef PREFIX
		global _%1
		%define %1 _%1
	%else
		global %1
	%endif
%endmacro


%define TINY_BLOCK_COPY 64
%define IN_CACHE_COPY 64*1024
%define UNCACHED_COPY 197*1024
%define BLOCK_PREFETCH_COPY infinity
%define CACHEBLOCK 80h

;=============================================================================
; Read only data
;=============================================================================

SECTION .rodata align=16

mask:
	dq 0x00FF00FF00FF00FF, 0x00FF00FF00FF00FF
	
SECTION .text
;cglobal memcpy_amd
;cglobal memoptS
;cglobal memoptU
;cglobal memoptA
;cglobal conv422toYUY2_SSE2
;cglobal convYUY2to422_SSE2

global asm_BitBlt_u
global asm_BitBlt_a
global asm_BitBlt_SSE2
global asm_BitBlt_SSE4


;=======================================================================
;void memcpy_amd(void *dest, const void *src, size_t n)
;=======================================================================
align 16 
memcpy_amd:
	
	push	rdi
	push	rsi
	
	mov		rdi, rcx		; destination
	mov		rsi, rdx		; source
	mov		rcx, r8			; number of bytes to copy, r8 is our "copy" of the count now

	cld
	cmp		rcx, TINY_BLOCK_COPY
	jb		memcpy_ic_3			; tiny? skip mmx copy

	cmp		rcx, 32*1024		; don't align between 32k-64k because
	jbe		memcpy_do_align		;  it appears to be slower
	cmp		rcx, 64*1024
	jbe		memcpy_align_done

memcpy_do_align:
	mov		rcx, 8			; a trick that's faster than rep movsb...
	sub		rcx, rdi		; align destination to qword
	and		rcx, 111b		; get the low bits
	sub		r8, rcx			; update copy count
	neg		rcx				; set up to jump into the array
	lea		rdx, [rel memcpy_align_done]
	add		rcx, rdx
	jmp		rcx				; jump to array of movsb's

align 4
	movsb
	movsb
	movsb
	movsb
	movsb
	movsb
	movsb
	movsb

memcpy_align_done:			; destination is dword aligned
	mov		rcx, r8			; number of bytes left to copy
	shr		rcx, 6			; get 64-byte block count
	jz		memcpy_ic_2		; finish the last few bytes

	cmp		rcx, IN_CACHE_COPY/64	; too big 4 cache? use uncached copy
	jae		memcpy_uc_test

; This is small block copy that uses the MMX registers to copy 8 bytes
; at a time.  It uses the "unrolled loop" optimization, and also uses
; the software prefetch instruction to get the data into the cache.
align 16
memcpy_ic_1:			; 64-byte block copies, in-cache copy

	prefetchnta [rsi + (200*64/34+192)]		; start reading ahead

	movq	mm0, [rsi+0]	; read 64 bits
	movq	mm1, [rsi+8]
	movq	[rdi+0], mm0	; write 64 bits
	movq	[rdi+8], mm1	;    note:  the normal movq writes the
	movq	mm2, [rsi+16]	;    data to cache; a cache line will be
	movq	mm3, [rsi+24]	;    allocated as needed, to store the data
	movq	[rdi+16], mm2
	movq	[rdi+24], mm3
	movq	mm0, [rsi+32]
	movq	mm1, [rsi+40]
	movq	[rdi+32], mm0
	movq	[rdi+40], mm1
	movq	mm2, [rsi+48]
	movq	mm3, [rsi+56]
	movq	[rdi+48], mm2
	movq	[rdi+56], mm3

	add		rsi, 64			; update source pointer
	add		rdi, 64			; update destination pointer
	dec		rcx				; count down
	jnz		memcpy_ic_1		; last 64-byte block?

memcpy_ic_2:
	mov		rcx, r8			; has valid low 6 bits of the byte count
memcpy_ic_3:
	shr		rcx, 2			; dword count
	and		rcx, 1111b		; only look at the "remainder" bits
	neg		rcx				; set up to jump into the array
	lea		rdx, [rel memcpy_last_few]
	add		rcx, rdx
	jmp		rcx				; jump to array of movsd's

memcpy_uc_test:
	cmp		rcx, UNCACHED_COPY/64	; big enough? use block prefetch copy
	jae		memcpy_bp_1

memcpy_64_test:
	or		rcx, rcx		; tail end of block prefetch will jump here
	jz		memcpy_ic_2		; no more 64-byte blocks left

; For larger blocks, which will spill beyond the cache, it's faster to
; use the Streaming Store instruction MOVNTQ.   This write instruction
; bypasses the cache and writes straight to main memory.  This code also
; uses the software prefetch instruction to pre-read the data.

align 16
memcpy_uc_1:				; 64-byte blocks, uncached copy

	prefetchnta [rsi + (200*64/34+192)]		; start reading ahead

	movq	mm0,[rsi+0]		; read 64 bits
	add		rdi,64			; update destination pointer
	movq	mm1,[rsi+8]
	add		rsi,64			; update source pointer
	movq	mm2,[rsi-48]
	movntq	[rdi-64], mm0	; write 64 bits, bypassing the cache
	movq	mm0,[rsi-40]	;    note: movntq also prevents the CPU
	movntq	[rdi-56], mm1	;    from READING the destination address
	movq	mm1,[rsi-32]	;    into the cache, only to be over-written
	movntq	[rdi-48], mm2	;    so that also helps performance
	movq	mm2,[rsi-24]
	movntq	[rdi-40], mm0
	movq	mm0,[rsi-16]
	movntq	[rdi-32], mm1
	movq	mm1,[rsi-8]
	movntq	[rdi-24], mm2
	movntq	[rdi-16], mm0
	dec		rcx
	movntq	[rdi-8], mm1
	jnz		memcpy_uc_1	; last 64-byte block?

	jmp		memcpy_ic_2		; almost done

; For the largest size blocks, a special technique called Block Prefetch
; can be used to accelerate the read operations.   Block Prefetch reads
; one address per cache line, for a series of cache lines, in a short loop.
; This is faster than using software prefetch, in this case.
; The technique is great for getting maximum read bandwidth,
; especially in DDR memory systems.

memcpy_bp_1:			; large blocks, block prefetch copy

	cmp		rcx, CACHEBLOCK			; big enough to run another prefetch loop?
	jl		memcpy_64_test			; no, back to regular uncached copy

	mov		rax, CACHEBLOCK / 2		; block prefetch loop, unrolled 2X
	add		rsi, CACHEBLOCK * 64	; move to the top of the block
align 16
memcpy_bp_2:
	mov		rdx, [esi-64]		; grab one address per cache line
	mov		rdx, [esi-128]		; grab one address per cache line
	sub		rsi, 128			; go reverse order
	dec		rax					; count down the cache lines
	jnz		memcpy_bp_2			; keep grabbing more lines into cache

	mov		rax, CACHEBLOCK		; now that it's in cache, do the copy
align 16
memcpy_bp_3:
	movq	mm0, [rsi   ]		; read 64 bits
	movq	mm1, [rsi+ 8]
	movq	mm2, [rsi+16]
	movq	mm3, [rsi+24]
	movq	mm4, [rsi+32]
	movq	mm5, [rsi+40]
	movq	mm6, [rsi+48]
	movq	mm7, [rsi+56]
	add		rsi, 64				; update source pointer
	movntq	[rdi   ], mm0		; write 64 bits, bypassing cache
	movntq	[rdi+ 8], mm1		;    note: movntq also prevents the CPU
	movntq	[rdi+16], mm2		;    from READING the destination address 
	movntq	[rdi+24], mm3		;    into the cache, only to be over-written,
	movntq	[rdi+32], mm4		;    so that also helps performance
	movntq	[rdi+40], mm5
	movntq	[rdi+48], mm6
	movntq	[rdi+56], mm7
	add		rdi, 64				; update dest pointer

	dec		rax					; count down

	jnz		memcpy_bp_3			; keep copying
	sub		rcx, CACHEBLOCK		; update the 64-byte block count
	jmp		memcpy_bp_1		; keep processing chunks

; The smallest copy uses the X86 "movsd" instruction, in an optimized
; form which is an "unrolled loop".   Then it handles the last few bytes.
align 4
	movsd
	movsd			; perform last 1-15 dword copies
	movsd
	movsd
	movsd
	movsd
	movsd
	movsd
	movsd
	movsd			; perform last 1-7 dword copies
	movsd
	movsd
	movsd
	movsd
	movsd
	movsd

memcpy_last_few:		; dword aligned from before movsd's
	mov		rcx, r8		; has valid low 2 bits of the byte count
	and		rcx, 11b	; the last few cows must come home
	jz		memcpy_final	; no more, let's leave
	rep		movsb		; the last 1, 2, or 3 bytes

memcpy_final: 
	emms				; clean up the MMX state
	sfence				; flush the write buffer
	
	pop rsi
	pop rdi
	ret
	
;=============================================================================
; void asm_BitBlt_u(BYTE* dstp, int dst_pitch, const BYTE* srcp, int src_pitch, int row_size, int height)
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
PROC_FRAME asm_BitBlt_u
	push		rbx
	[pushreg	rbx]
	push		rbp
	[pushreg	rbp]
END_PROLOG

%DEFINE .rowsize	[rsp+16+40] 
%DEFINE .height		[rsp+16+48]

	mov			ebx, DWORD .height				; load y loop counter
	mov			ebp, DWORD .rowsize				; load x counter 

align 16
.yloop:
	mov			r10d, ebp
	and			r10d, 0FFFFFFC0h
	mov			eax, r10d
	jz			.xloop16_a
	
align 16
.xloop64:
	prefetchnta	[r8+rax+256]
	movdqu		xmm0,DQWORD [r8 + r10 - 16]
	movdqu		xmm1,DQWORD [r8 + r10 - 32]
	movdqu		DQWORD[rcx + r10 - 16], xmm0
	movdqu		DQWORD[rcx + r10 - 32], xmm1
	
	sub			r10d, 64
	
	movdqu		xmm2,DQWORD [r8 + r10+64 -  48]
	movdqu		xmm3,DQWORD [r8 + r10+64 -  64]
	movdqu		DQWORD[rcx + r10+64 -  48], xmm2
	movdqu		DQWORD[rcx + r10+64 -  64], xmm3
	
	ja			.xloop64
	
	test		ebp, 63
	jz			.xdone

align 16
.xloop16_a:
	mov			r10d, ebp
	and			r10d, 000000030h
	jz			.xloop4_a
	
align 16
.xloop16:					
	movdqu		xmm0,DQWORD [r8 + rax]
	movdqu	 	DQWORD[rcx + rax], xmm0
	add			eax, 16
	sub			r10d,16
	ja			.xloop16
	
	test		ebp, 15
	je			.xdone

align 16
.xloop4_a:
	mov			r10d, ebp
	and			r10d, 00000000Ch
	jz			.xloop1
	
align 16
.xloop4:			
	mov			r11d, DWORD [r8 + rax]
	mov			DWORD [rcx + rax], r11d
	add			eax, 4
	sub			r10d, 4
	ja			.xloop4			
	
	test		ebp, 3
	jz			.xdone
	
align 16
.xloop1:
	mov			r11b, BYTE [r8 + rax]
	mov			BYTE [rcx+rax], r11b
	add			eax, 1
	cmp			eax, ebp
	jb			.xloop1

align 16
.xdone:
	add			rcx, rdx
	add			r8, r9
	sub			ebx, 1
	ja			.yloop
	
    pop			rbp
    pop			rbx
    ret
[ENDPROC_FRAME]

;=============================================================================
; void asm_BitBlt_a(BYTE* dstp, int dst_pitch, const BYTE* srcp, int src_pitch, int row_size, int height)
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
PROC_FRAME asm_BitBlt_a
	push		rbx
	[pushreg	rbx]
	push		rbp
	[pushreg	rbp]
END_PROLOG

%DEFINE .rowsize	[rsp+16+40] 
%DEFINE .height		[rsp+16+48]

	mov			ebx, DWORD .height				; load y loop counter
	mov			ebp, DWORD .rowsize				; load x counter 

align 16
.yloop:
	mov			r10d, ebp
	and			r10d, 0FFFFFFC0h
	mov			eax, r10d
	jz			.xloop16_a
	
align 16
.xloop64:
	prefetchnta	[r8+rax+256]
	movdqa		xmm0,DQWORD [r8 + r10 - 16]
	movdqa		xmm1,DQWORD [r8 + r10 - 32]
	movdqa		DQWORD[rcx + r10 - 16], xmm0
	movdqa		DQWORD[rcx + r10 - 32], xmm1
	
	sub			r10d, 64
	
	movdqa		xmm2,DQWORD [r8 + r10+64 -  48]
	movdqa		xmm3,DQWORD [r8 + r10+64 -  64]
	movdqa		DQWORD[rcx + r10+64 -  48], xmm2
	movdqa		DQWORD[rcx + r10+64 -  64], xmm3
	
	ja			.xloop64
	
	test		ebp, 63
	jz			.xdone

align 16
.xloop16_a:
	mov			r10d, ebp
	and			r10d, 000000030h
	jz			.xloop4_a
	
align 16
.xloop16:					
	movdqa		xmm0,DQWORD [r8 + rax]
	movdqa	 	DQWORD[rcx + rax], xmm0
	add			eax, 16
	sub			r10d,16
	ja			.xloop16
	
	test		ebp, 15
	je			.xdone

align 16
.xloop4_a:
	mov			r10d, ebp
	and			r10d, 00000000Ch
	jz			.xloop1
	
align 16
.xloop4:			
	mov			r11d, DWORD [r8 + rax]
	mov			DWORD [rcx + rax], r11d
	add			eax, 4
	sub			r10d, 4
	ja			.xloop4			
	
	test		ebp, 3
	jz			.xdone
	
align 16
.xloop1:
	mov			r11b, BYTE [r8 + rax]
	mov			BYTE [rcx+rax], r11b
	add			eax, 1
	cmp			eax, ebp
	jb			.xloop1

align 16
.xdone:
	add			rcx, rdx
	add			r8, r9
	sub			ebx, 1
	ja			.yloop
	
    pop			rbp
    pop			rbx
    ret
[ENDPROC_FRAME]



;=============================================================================
; void asm_BitBlt(BYTE* dstp, int dst_pitch, const BYTE* srcp, int src_pitch, int row_size, int height)
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
PROC_FRAME asm_BitBlt_SSE2
	push		rbx
	[pushreg	rbx]
	push		rbp
	[pushreg	rbp]
END_PROLOG

%DEFINE .rowsize	[rsp+16+40] 
%DEFINE .height		[rsp+16+48]

	mov			ebx, DWORD .height				; load y loop counter
	mov			ebp, DWORD .rowsize				; load x counter

	mov			eax, ecx
	mov			r10d,edx
	or			eax, r9d
	or			r10d, r8d
	or			eax, r10d
	
	test		ebx,ebx
	jz			.end
	test		ebp, ebp
	jz			.end	
	

	test		eax, 0Fh
	jnz			.yloop_U
	

align 16
.yloop_A:
	mov			r10d, ebp
	and			r10d, 0FFFFFFC0h
	mov			eax, r10d
	jz			.xloop16_A1
	
align 16
.xloop64_A:
	movdqa		xmm0,DQWORD [r8 + r10 -  16]
	movdqa		xmm1,DQWORD [r8 + r10 -  32]
	movdqa		DQWORD[rcx + r10 -  16], xmm0
	movdqa		DQWORD[rcx + r10 -  32], xmm1
	
	sub			r10d, 64

	movdqa		xmm2,DQWORD [r8 + r10+64 -  48]
	movdqa		xmm3,DQWORD [r8 + r10+64 -  64]
	movdqa		DQWORD[rcx + r10+64 -  48], xmm2
	movdqa		DQWORD[rcx + r10+64 -  64], xmm3

	ja			.xloop64_A
	
	test		ebp, 63
	jz			.xdone_A

align 16
.xloop16_A1:
	mov			r10d, ebp
	and			r10d, 000000030h
	jz			.xloop4_A1
	
align 16
.xloop16_A:					
	movdqa		xmm0,DQWORD [r8 + rax]
	movdqa	 	DQWORD[rcx + rax], xmm0
	add			eax, 16
	sub			r10d, 16
	ja			.xloop16_A
	
	test		ebp, 15
	jz			.xdone_A

align 16
.xloop4_A1:
	mov			r10d, ebp
	and			r10d, 00000000Ch
	jz			.xloop1_A
	

align 16
.xloop4_A:			
	mov			r11d, DWORD [r8 + rax]
	mov			DWORD [rcx + rax], r11d
	add			eax, 4
	sub			r10d, 4
	ja			.xloop4_A	
	
	test		ebp, 3
	jz			.xdone_A
	
align 16
.xloop1_A:
	mov			r11b, BYTE [r8 + rax]
	mov			BYTE [rcx+rax], r11b
	add			eax, 1
	cmp			eax, ebp
	jb			.xloop1_A

align 16
.xdone_A:
	add			rcx, rdx
	add			r8, r9
	sub			ebx, 1
	ja			.yloop_A
	
	pop			rbp
    pop			rbx
    ret


align 16
.yloop_U:
	mov			r10d, ebp
	and			r10d, 0FFFFFFC0h
	mov			eax, r10d
	jz			.xloop16_U1
	
align 16
.xloop64_U:
	movdqa		xmm0,DQWORD [r8 + r10 -  16]
	movdqa		xmm1,DQWORD [r8 + r10 -  32]
	movdqa		DQWORD[rcx + r10 -  16], xmm0
	movdqa		DQWORD[rcx + r10 -  32], xmm1
	
	sub			r10d, 64

	movdqa		xmm2,DQWORD [r8 + r10+64 -  48]
	movdqa		xmm3,DQWORD [r8 + r10+64 -  64]
	movdqa		DQWORD[rcx + r10+64 -  48], xmm2
	movdqa		DQWORD[rcx + r10+64 -  64], xmm3

	ja			.xloop64_U
	
	test		ebp, 63
	jz			.xdone_U


align 16
.xloop16_U1:
	mov			r10d, ebp
	and			r10d, 000000030h
	jz			.xloop4_U1
	
align 16
.xloop16_U:					
	movdqu		xmm0,DQWORD [r8 + rax]
	movdqu	 	DQWORD [rcx + rax], xmm0
	add			eax, 16
	sub			r10d, 16
	ja			.xloop16_U
	
	test		ebp, 15
	jz			.xdone_U
	
align 16
.xloop4_U1:
	mov			r10d, ebp
	and			r10d, 00000000Ch
	jz			.xloop1_U

align 16
.xloop4_U:			
	mov			r11d, DWORD [r8 + rax]
	mov			DWORD [rcx + rax], r11d
	add			eax, 4
	sub			r10d, 4
	ja			.xloop4_U
	
	test		ebp, 3
	jz			.xdone_U

align 16
.xloop1_U:
	mov			r11b, BYTE [r8 + rax]
	mov			BYTE [rcx+rax], r11b
	add			eax, 1
	cmp			eax, ebp
	jb			.xloop1_U

align 16
.xdone_U:
	add			rcx, rdx
	add			r8, r9
	sub			ebx, 1
	ja			.yloop_U

align 16
.end:
    pop			rbp
    pop			rbx
    ret
[ENDPROC_FRAME]

;=============================================================================
; void asm_BitBlt(BYTE* dstp, int dst_pitch, const BYTE* srcp, int src_pitch, int row_size, int height)
;=============================================================================	
; parameter 1(dstp):		rcx
; parameter 2(dst_pitch):	rdx
; parameter 3(srcp):		r8
; parameter 4(src_pitch):	r9 
; parameter 5(row_size):	rsp+40
; parameter 6(height):		rsp+48


;align 16
PROC_FRAME asm_BitBlt_SSE4
	push		rbx
	[pushreg	rbx]
	push		rbp
	[pushreg	rbp]
END_PROLOG

%DEFINE .rowsize	[rsp+16+40] 
%DEFINE .height		[rsp+16+48]

	mov			ebx, DWORD .height				; load y loop counter
	mov			ebp, DWORD .rowsize				; load x counter
	
	mov			eax, ecx
	mov			r10d,edx
	or			eax, r9d
	or			r10d, r8d
	or			eax, r10d
	
	
	;test		ebx,ebx
	;jz			.end
	;test		ebp, ebp
	;jz			.end	
	
	test		eax, 0Fh
	jnz			.yloop_U
	

align 16
.yloop_A:
	mov			r10d, ebp
	and			r10d, 0FFFFFFC0h
	mov			eax, r10d
	jz			.xloop16_A1
		
align 16
.xloop64_A:
	movntdqa	xmm0,DQWORD [r8 + r10 -  16]
	movntdqa	xmm1,DQWORD [r8 + r10 -  32]
	movntdq		DQWORD[rcx + r10 -  16], xmm0
	movntdq		DQWORD[rcx + r10 -  32], xmm1
	
	sub			r10d, 64

	movntdqa	xmm2,DQWORD [r8 + r10+64 -  48]
	movntdqa	xmm3,DQWORD [r8 + r10+64 -  64]
	movntdq		DQWORD[rcx + r10+64 -  48], xmm2
	movntdq		DQWORD[rcx + r10+64 -  64], xmm3

	ja			.xloop64_A
	
	test		ebp, 63
	jz			.xdone_A
		
align 16
.xloop16_A1:
	mov			r10d, ebp
	and			r10d, 000000030h
	jz			.xloop4_A1
	
	
align 16
.xloop16_A:					
	movntdqa	xmm0,DQWORD [r8 + rax]
	movntdq	 	DQWORD[rcx + rax], xmm0
	add			eax, 16
	sub			r10d, 16
	ja			.xloop16_A
	
	test		ebp, 15
	jz			.xdone_A

align 16
.xloop4_A1:
	mov			r10d, ebp
	and			r10d, 00000000Ch
	jz			.xloop1_A
	

align 16
.xloop4_A:			
	mov			r11d, DWORD [r8 + rax]
	mov			DWORD [rcx + rax], r11d
	add			eax, 4
	sub			r10d, 4
	ja			.xloop4_A	
	
	test		ebp, 3
	jz			.xdone_A
	
align 16
.xloop1_A:
	mov			r11b, BYTE [r8 + rax]
	mov			BYTE [rcx+rax], r11b
	add			eax, 1
	cmp			eax, ebp
	jb			.xloop1_A

align 16
.xdone_A:
	add			rcx, rdx
	add			r8, r9
	sub			ebx, 1
	ja			.yloop_A
	
	mfence
	pop			rbp
    pop			rbx
    ret


align 16
.yloop_U:
	mov			r10d, ebp
	and			r10d, 0FFFFFFC0h
	mov			eax, r10d
	jz			.xloop16_U1
	
align 16
.xloop64_U:
	prefetchnta	[r8+rax+128]
	lddqu		xmm0,DQWORD [r8 + r10 - 16]
	lddqu		xmm1,DQWORD [r8 + r10 - 32]
	movdqu		DQWORD[rcx + r10 -  16], xmm0
	movdqu		DQWORD[rcx + r10 -  32], xmm1

	sub			r10d, 64
	
	lddqu		xmm2,DQWORD [r8 + r10+64 -  48]
	lddqu		xmm3,DQWORD [r8 + r10+64 -  64]
	movdqu		DQWORD[rcx + r10+64 -  48], xmm2
	movdqu		DQWORD[rcx + r10+64 -  64], xmm3
	
	ja			.xloop64_U
	
	test		ebp, 63
	jz			.xdone_U

align 16
.xloop16_U1:
	mov			r10d, ebp
	and			r10d, 000000030h
	jz			.xloop4_U1
	
align 16
.xloop16_U:					
	lddqu		xmm0,DQWORD [r8 + rax]
	movdqu	 	DQWORD [rcx + rax], xmm0
	add			eax, 16
	sub			r10d, 16
	ja			.xloop16_U
	
	test		ebp, 15
	jz			.xdone_U
	
align 16
.xloop4_U1:
	mov			r10d, ebp
	and			r10d, 00000000Ch
	jz			.xloop1_U


align 16
.xloop4_U:			
	mov			r11d, DWORD [r8 + rax]
	mov			DWORD [rcx + rax], r11d
	add			eax, 4
	sub			r10d,4
	ja			.xloop4_U
	
	test		ebp, 3
	jz			.xdone_U

align 16
.xloop1_U:
	mov			r11b, BYTE [r8 + rax]
	mov			BYTE [rcx+rax], r11b
	add			eax, 1
	cmp			eax, ebp
	jb			.xloop1_U

align 16
.xdone_U:
	add			rcx, rdx
	add			r8, r9
	sub			ebx, 1
	ja			.yloop_U

align 16
.end:
    pop			rbp
    pop			rbx
    ret
[ENDPROC_FRAME]




;==============================================================================================================================
;void memoptS(const unsigned char* srcStart, unsigned char* dstStart, int src_pitch, int dst_pitch, int row_size, int height)
;==============================================================================================================================
;rcx=srcStart
;rdx=dstStart
;r8=src_pitch
;r9=dst_pitch

memoptS:
		mov   r10d,[rsp+40] ;r10=row_size
		dec   r10d
		mov   r11d,[rsp+48] ;r11=height

align 16
memoptS_rowloop:
		mov   eax,r10d

memoptS_byteloop:
		mov   AL,[rcx+rax]
		mov   [rdx+rax],AL
		sub   eax,1
		jnc   memoptS_byteloop
		sub   rcx,r8
		sub   rdx,r9
		dec   r11d
		jne   memoptS_rowloop
		ret

;==============================================================================================================================
;void memoptU(const unsigned char* srcStart, unsigned char* dstStart, int src_pitch, int dst_pitch, int row_size, int height);
;==============================================================================================================================
;rcx=srcStart
;rdx=dstStart
;r8=src_pitch
;r9=dst_pitch
memoptU:
			push	rbx
						
			mov		AL,[rcx]
			mov		r10d,[rsp+48] ;r10=row_size
			mov		r11d,[rsp+56] ;r11=height
			
align 16			
memoptU_rowloop:
			xor		ebx,ebx
			mov		ebx,r10d
			dec		rbx
			add		rbx,rcx
			and		rbx,~63
			
memoptU_prefetchloop:
			mov		AX,[rbx]
			sub		rbx,64
			cmp		rbx,rcx
			jae		memoptU_prefetchloop
			movq	mm6,[rcx]
			movntq	[rcx],mm6
			mov		rax,rdx
			neg		rax
			mov		rbx,rax
			and		rbx,63
			and		rbx,7
			align 16
			
memoptU_prewrite8loop:
			cmp		rbx,rax
			jz		memoptU_pre8done
			movq	mm7,[rcx+rbx]
			movntq	[rdx+rbx],mm7
			add		rbx,8
			jmp		memoptU_prewrite8loop
			
align 16			
memoptU_write64loop:
			movntq  [rdx+rbx-64],mm0
			movntq  [rdx+rbx-56],mm1
			movntq  [rdx+rbx-48],mm2
			movntq  [rdx+rbx-40],mm3
			movntq  [rdx+rbx-32],mm4
			movntq  [rdx+rbx-24],mm5
			movntq  [rdx+rbx-16],mm6
			movntq  [rdx+rbx- 8],mm7
			
memoptU_pre8done:
			add		rbx,64
			cmp		ebx,r10d
			ja		memoptU_done64
			movq	mm0,[rcx+rbx-64]
			movq	mm1,[rcx+rbx-56]
			movq	mm2,[rcx+rbx-48]
			movq	mm3,[rcx+rbx-40]
			movq	mm4,[rcx+rbx-32]
			movq	mm5,[rcx+rbx-24]
			movq	mm6,[rcx+rbx-16]
			movq	mm7,[rcx+rbx- 8]
			jmp		memoptU_write64loop
			
memoptU_done64:
			sub		rbx,64
			align 16
			
memoptU_write8loop:
			add		rbx,8
			cmp		ebx,r10d
			ja		memoptU_done8
			movq	mm0,[rcx+rbx-8]
			movntq	[rdx+rbx-8],mm0
			jmp		memoptU_write8loop
			
memoptU_done8:
			movq	mm1,[rcx+r10-8]
			movntq	[rdx+r10-8],mm1
			sub		rcx,r8
			sub		rdx,r9
			dec		r11d
			jne		memoptU_rowloop
			sfence
			emms
			pop rbx
			ret

;==============================================================================================================================
;void memoptA(const unsigned char* srcStart, unsigned char* dstStart, int src_pitch, int dst_pitch, int row_size, int height);
;==============================================================================================================================
;rcx=srcStart
;rdx=dstStart
;r8=src_pitch
;r9=dst_pitch

memoptA:
			push	rbx
			mov		r10d, [rsp+48] ;r10=row size
			mov		r11d, [rsp+56] ;r11=height

align 16
memoptA_rowloop:
			xor		rbx,rbx
			mov		ebx,r10d
			dec		rbx
			add		rbx,rcx
			and		rbx,~63
			
align 16			
memoptA_prefetchloop:
			mov		AX,[rbx]
			sub		rbx,64
			cmp		rbx,rcx
			jae		memoptA_prefetchloop
			mov		rax,rdx
			xor		rbx,rbx
			neg		rax
			and		rax,63
			
align 16
memoptA_prewrite8loop:
			cmp		rbx,rax
			jz		memoptA_pre8done
			movq	mm7,[rcx+rbx]
			movntq	[rdx+rbx],mm7
			add		rbx,8
			jmp		memoptA_prewrite8loop
			
align 16
memoptA_write64loop:
			movntq	[rdx+rbx-64],mm0
			movntq	[rdx+rbx-56],mm1
			movntq	[rdx+rbx-48],mm2
			movntq	[rdx+rbx-40],mm3
			movntq	[rdx+rbx-32],mm4
			movntq	[rdx+rbx-24],mm5
			movntq	[rdx+rbx-16],mm6
			movntq	[rdx+rbx- 8],mm7
			
memoptA_pre8done:
			add		rbx,64
			cmp		ebx,r10d
			ja		memoptA_done64
			movq	mm0,[rcx+rbx-64]
			movq	mm1,[rcx+rbx-56]
			movq	mm2,[rcx+rbx-48]
			movq	mm3,[rcx+rbx-40]
			movq	mm4,[rcx+rbx-32]
			movq	mm5,[rcx+rbx-24]
			movq	mm6,[rcx+rbx-16]
			movq	mm7,[rcx+rbx- 8]
			jmp		memoptA_write64loop
			
memoptA_done64:
			sub		rbx,64
			
align 16
memoptA_write8loop:
			add		rbx,8
			cmp		ebx,r10d
			ja		memoptA_done8
			movq	mm7,[rcx+rbx-8]
			movntq	[rdx+rbx-8],mm7
			jmp		memoptA_write8loop
			
memoptA_done8:
			sub		rcx,r8
			sub		rdx,r9
			dec		r11d
			jne		memoptA_rowloop
			sfence
			emms
			pop rbx
			ret


;==============================================================================================================================
;void PlanarFrame::conv422toYUY2_SSE2(unsigned char *py, unsigned char *pu, unsigned char *pv, unsigned char *dst, int pitch1Y, int pitch1UV, int pitch2, int width, int height)
;==============================================================================================================================
;rcx=py
;rdx=pu
;r8=pv
;r9=dst

conv422toYUY2_SSE2:		
		mov r10d,[rsp+64] ;r10=width
		mov r11d,[rsp+72]
		shr r10d,1
conv422yloop:
		xor rax,rax
		align 16
conv422xloop:
		movlpd xmm0,[rcx+rax*2] ;????????YYYYYYYY
		movd xmm1,[rdx+rax]     ;000000000000UUUU
		movd xmm2,[r8+rax]		;000000000000VVVV
		punpcklbw xmm1,xmm2     ;00000000VUVUVUVU
		punpcklbw xmm0,xmm1     ;VYUYVYUYVYUYVYUY
		movdqa [r9+rax*4],xmm0 ;store
		add rax,4
		cmp eax,r10d
		jl conv422xloop
		add ecx,[rsp+40]
		add edx,[rsp+48]
		add r8d,[rsp+48]
		add r9d,[rsp+56]
		dec r11d
		jnz conv422yloop
		ret

;==============================================================================================================================
;void PlanarFrame::convYUY2to422_SSE2(const unsigned char *src, unsigned char *py, unsigned char *pu, unsigned char *pv, int pitch1, int pitch2Y, int pitch2UV, int width, int height)
;==============================================================================================================================
;rcx=src
;rdx=py
;r8=pu
;r9=pv

convYUY2to422_SSE2:
		mov r10d,[rsp+64] ;r10=width
		mov r11d,[rsp+72] ;r11=height
		shr r10d,1
		movdqa xmm3,[rel mask]
convYUY2yloop:
		xor rax,rax
		align 16
convYUY2xloop:
		movdqa xmm0,[rcx+rax*4] ;VYUYVYUYVYUYVYUY
		movdqa xmm1,xmm0        ;VYUYVYUYVYUYVYUY
		pand xmm0,xmm3          ;0Y0Y0Y0Y0Y0Y0Y0Y
		psrlw xmm1,8	        ;0V0U0V0U0V0U0V0U
		packuswb xmm0,xmm0      ;xxxxxxxxYYYYYYYY
		packuswb xmm1,xmm1      ;xxxxxxxxVUVUVUVU
		movdqa xmm2,xmm1        ;xxxxxxxxVUVUVUVU
		pand xmm1,xmm3          ;xxxxxxxx0U0U0U0U
		psrlw xmm2,8            ;xxxxxxxx0V0V0V0V
		packuswb xmm1,xmm1      ;xxxxxxxxxxxxUUUU
		packuswb xmm2,xmm2      ;xxxxxxxxxxxxVVVV
		movlpd [rdx+rax*2],xmm0 ;store y
		movd [r8+rax],xmm1     ;store u
		movd [r9+rax],xmm2     ;store v
		add eax,4
		cmp eax,r10d
		jl convYUY2xloop
		add ecx,[rsp+40] ;pitch1
		add edx,[rsp+48] ;pitch2Y
		add r8d,[rsp+56] ;pitch2UV
		add r9d,[rsp+56] ;pitch2UV
		dec r11d
		jnz convYUY2yloop
		ret