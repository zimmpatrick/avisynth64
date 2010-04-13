;=============================================================================
; Function declarations
;=============================================================================
	
	global accumulate_line_mode2_mmx
	
	global accumulate_line_mode2_axmm
	global accumulate_line_mode2_uaxmm
	
	global scenechange_isse_asm
	global scenechange_sse3_asm
	
	global AFH_YV12_ASM
	
	
;=============================================================================
; Read only data
;=============================================================================
SECTION .rodata align=16
full:
	dq 0ffffffffffffffffh
	dq 0ffffffffffffffffh
add64:
	dq 00000400000004000h
	dq 00000400000004000h
i64_r7:
	dq 00040004000400040h
	dq 00040004000400040h
leftmask:
	dq 000000000000000FFh
	dq 000000000000000FFh
rightmask:
	dq 0FF00000000000000h
	dq 0FF00000000000000h

	
%MACRO scale 7 
; scale(mmAA,mmBB,mmCC,mmA,mmB,mmC,zeros)
	movdqa		%6,%3			;  Right 8 pixels      
	movdqa		%4,%1			;  Left     "          
	movdqa		%5,%2			;  Centre   "          
	punpcklbw	%6,%7			;  Low 4 right         
	punpcklbw	%4,%7			;  Low 4 left          
	punpcklbw	%5,%7			;  Low 4 centre        
	paddsw		%4,%6			;  Low 4 left + right  
	pmullw		%5,xmm14		;  *= centre weight    
	pmullw		%4,xmm13		;  *= outer weight     
	punpckhbw	%3,%7			;  High 4 Right        
	punpckhbw	%1,%7			;  High 4 Left         
	punpckhbw	%2,%7			;  High 4 Centre       
	paddsw		%1,%3			;  High 4 left + right 
	pmullw		%2,xmm14		;  *= centre weight    
	pmullw		%1,xmm13		;  *= outer weight     
	paddsw		%4,%5			;  += weighed low 4    
	paddsw		%1,%2			;  += weighed high 4   
	paddsw		%4,%5			;  += weighed low 4    
	paddsw		%1,%2			;  += weighed high 4   
	paddsw		%4, xmm7		;  += 0.5              
	paddsw		%1,	xmm7		;  += 0.5              
	psraw		%4,7			;  /= 128              
	psraw		%1,7			;  /= 128              
	add			rcx,16			;  p += 16             
	packuswb	%4,%1			;  Packed new 8 pixels 
%ENDMACRO

;=============================================================================
; void accumulate_line_mode2_mmx(const BYTE* c_plane, const BYTE** planeP, int planes, int rowsize, __int64 t, int div) 
;=============================================================================
; parameter 1(cplane):		rcx
; parameter 2(planeP):		rdx
; parameter 3(planes):		r8d
; parameter 4(row_size):	r9d 
; parameter 5(t):			rsp+40
; parameter 6(div):			rsp+48

section .text
align 16
PROC_FRAME accumulate_line_mode2_mmx
	push		rbx		; rbx = __int64 t
	[pushreg	rbx]
	push		rsi		; rsi = __int64 div, derived from param int div
	[pushreg	rsi]
	push		rdi		; rdi copies total planes to be used as a loop counter
	[pushreg	rdi]
END_PROLOG

%DEFINE .i64_t	[rsp+24+40]
%DEFINE .i_div	[rsp+24+48] 
	
	mov			rbx, .i64_t
	
	mov			esi, DWORD .i_div	
	mov			eax, esi
	shl			eax, 16
	or			esi, eax
	mov			rax, rsi
	shl			rax, 32
	or			rsi, rax		; div64 = (__int64)(div) | ((__int64)(div)<<16) | ((__int64)(div)<<32) | ((__int64)(div)<<48)
	xor			eax,eax			; eax will be plane offset (all planes).

align 16
.testplane:
	movq		mm0,[rcx+rax]	; Load current frame pixels cplane[offset]
	pxor		mm2,mm2			; Clear mm2
	movq		mm6,mm0			; copy current pixels	
	movq		mm7,mm0			; copy current pixels
	punpcklbw	mm6,mm2			; mm0 = lower 4 pixels  (exhanging h/l in these two give funny results)
	punpckhbw	mm7,mm2			; mm1 = upper 4 pixels

	mov			edi, r8d		; load modifiable copy of planes
	lea			r10,[rdx+rdi*8-8] ;rdx=planeP, rdi=planes

align 16
.kernel_loop:
	mov			r11, QWORD [r10]
	movq		mm1, [r11+rax]	; Load 8 pixels from test plane
	movq		mm2, mm0
	movq		mm5, mm1		; Save test plane pixels (twice for unpack)
	pxor		mm4, mm4
	pmaxub		mm2, mm1		; Calc abs difference
	pminub		mm1, mm0
	psubusb		mm2, mm1		; mm2 = abs difference (packed bytes)
	movq		mm3, rbx		; Using t also gives funny results
	psubusb		mm2,mm3			; Subtrack threshold (unsigned, so all below threshold will give 0)
	movq		mm1,mm5
	pcmpeqb		mm2,mm4			; Compare values to 0
	prefetchnta	[r11+rax+64]	; it might just help - and we have an idle CPU here anyway ;)
	movq		mm3,mm2
	pxor		mm2,[rel full]	; mm2 inverse mask
	movq		mm4, mm0
	pand		mm5, mm3
	pand		mm4,mm2
	pxor		mm1,mm1
	por			mm4,mm5
	movq		mm5,mm4			;stall (this & below)
	punpcklbw	mm4,mm1			; mm4 = lower pixels
	punpckhbw	mm5,mm1			; mm5 = upper pixels
	paddusw		mm6,mm4
	paddusw		mm7,mm5

	sub			r10, 8			; changed from 4 to 8 because [rdi]=byte*'s = 8 bytes each
	sub			edi, 1			; planes--
	ja			.kernel_loop
	
	; Multiply (or in reality divides) added values, repack and store.
	movq		mm4, [rel add64]
	pxor		mm5, mm5
	movq		mm0, mm6
	movq		mm1, mm6
	punpcklwd	mm0, mm5			; low,low
	movq		mm6, rsi			; mov in div64
	punpckhwd	mm1, mm5			; low,high
	movq		mm2, mm7
	pmaddwd		mm0, mm6			; pmaddwd is used due to it's better rounding.
	punpcklwd	mm2, mm5			; high,low
	movq		mm3, mm7
	paddd		mm0, mm4
	pmaddwd		mm1, mm6
	punpckhwd	mm3, mm5			; high,high
	psrld		mm0, 15
	paddd		mm1, mm4
	pmaddwd		mm2, mm6
	packssdw	mm0, mm0
	psrld		mm1, 15
	paddd		mm2, mm4
	pmaddwd		mm3, mm6
	packssdw	mm1, mm1
	psrld		mm2, 15
	paddd		mm3, mm4
	psrld		mm3, 15
	packssdw	mm2, mm2
	packssdw	mm3, mm3
	packuswb	mm0, mm5
	packuswb	mm1, mm5
	packuswb	mm2, mm5
	packuswb	mm3, mm5
	pshufw		mm0, mm0,11111100b
	pshufw		mm1, mm1,11110011b
	pshufw		mm2, mm2,11001111b
	pshufw		mm3, mm3,00111111b
	por			mm0, mm1
	por			mm2, mm3
	por			mm0, mm2
	movq		[rcx+rax], mm0	; cplane[offset]=mm0
	add			eax, 8			; Next 8 pixels
	cmp			eax, r9d		; cmp row_size with count
	jle			.testplane
	
align 16
.outloop:
	emms
	pop rdi
	pop rsi
	pop rbx
	ret
	
ENDPROC_FRAME

;=============================================================================
; void accumulate_line_mode2_aligned_xmm(const BYTE* c_plane, const BYTE** planeP, int planes, int rowsize, __int64 t, int div) 
;=============================================================================
; parameter 1(cplane):		rcx
; parameter 2(planeP):		rdx
; parameter 3(planes):		r8d
; parameter 4(row_size):	r9d 
; parameter 5(t):			rsp+40
; parameter 6(div):			rsp+48
align 16
PROC_FRAME accumulate_line_mode2_axmm
	push		rdi		; rdi copies total planes to be used as a loop counter
	[pushreg	rdi]
END_PROLOG

%DEFINE .i64_t	[rsp+8+40]
%DEFINE .i_div	[rsp+8+48] 
		
	;movddup		xmm8, .i64_t	; copies a 64 bit value from mem and duplicates it int he upper half 
	movq		xmm8, .i64_t
	movlhps		xmm8, xmm8
	
	pxor		xmm15,xmm15		; our go to 0 register for unpacking
	xor			eax, eax
		
	movdqa		xmm9, [rel full]
	movdqa		xmm10, [rel add64]
	
	movd		xmm11, .i_div				; mov in div64
	pshufd		xmm11, xmm11,00000000b	; copy div64 to upper half

align 16
.testplane:
	movdqa		xmm0,[rcx+rax]	; Load current frame pixels cplane[offset]
	movdqa		xmm6,xmm0		; copy current pixels	
	movdqa		xmm7,xmm0		; copy current pixels
	punpcklbw	xmm6,xmm15		; mm0 = lower 4 pixels  (exchanging h/l in these two give funny results)
	punpckhbw	xmm7,xmm15		; mm1 = upper 4 pixels

	mov			edi, r8d		; load modifiable copy of planes
	lea			r10,[rdx+rdi*8-8] ;rdx=planeP, rdi=planes

align 16
.kernel_loop:
	mov			r11, QWORD [r10]
	movdqa		xmm1, [r11+rax]	; Load 16 pixels from test plane
	movdqa		xmm2, xmm0
	movdqa		xmm5, xmm1		; Save test plane pixels (twice for unpack)
	pmaxub		xmm2, xmm1		; Calc abs difference
	pminub		xmm1, xmm0
	psubusb		xmm2, xmm1		; mm2 = abs difference (packed bytes)
	psubusb		xmm2, xmm8		; Subtrack threshold (unsigned, so all below threshold will give 0)
	movdqa		xmm1, xmm5
	pcmpeqb		xmm2, xmm15		; Compare values to 0
	prefetchnta	[r11+rax+128]	; it might just help - and we have an idle CPU here anyway ;)
	movdqa		xmm3, xmm2
	pxor		xmm2, xmm9		; mm2 inverse mask
	movdqa		xmm4, xmm0
	pand		xmm5, xmm3
	pand		xmm4, xmm2
	por			xmm4, xmm5
	movdqa		xmm5, xmm4		;stall (this & below)
	
	sub			r10d, 8			; changed from 4 to 8 because [rdi]=byte*'s = 8 bytes each
	
	punpcklbw	xmm4, xmm15		; mm4 = lower pixels
	punpckhbw	xmm5, xmm15		; mm5 = upper pixels
	paddusw		xmm6, xmm4
	paddusw		xmm7, xmm5
	
	sub			edi, 1			; planes--
	ja			.kernel_loop
	
	; Multiply (or in reality divides) added values, repack and store.
	movdqa		xmm0, xmm6
	movdqa		xmm1, xmm6
	punpcklwd	xmm0, xmm15		; low,low
	punpckhwd	xmm1, xmm15		; low,high
	movdqa		xmm2, xmm7
	pmaddwd		xmm0, xmm11		; pmaddwd is used due to it's better rounding.
	punpcklwd	xmm2, xmm15		; high,low
	movdqa		xmm3, xmm7
	paddd		xmm0, xmm10		; add64
	pmaddwd		xmm1, xmm11		; div64
	punpckhwd	xmm3, xmm15		; high,high
	psrld		xmm0, 15
	paddd		xmm1, xmm10		; add64
	pmaddwd		xmm2, xmm11		; div64
	packssdw	xmm0, xmm0
	psrld		xmm1, 15
	paddd		xmm2, xmm10		; add64
	pmaddwd		xmm3, xmm11		; div64
	packssdw	xmm1, xmm1
	psrld		xmm2, 15
	paddd		xmm3, xmm10		; add64
	psrld		xmm3, 15
	packssdw	xmm2, xmm2
	packssdw	xmm3, xmm3
	packuswb	xmm0, xmm15
	packuswb	xmm1, xmm15
	packuswb	xmm2, xmm15
	packuswb	xmm3, xmm15
	pshufd		xmm0, xmm0, 11111100b 
	pshufd		xmm1, xmm1, 11110011b
	pshufd		xmm2, xmm2, 11001111b
	pshufd		xmm3, xmm3, 00111111b
	por			xmm0, xmm1
	por			xmm2, xmm3
	por			xmm0, xmm2
	movdqa		[rcx+rax], xmm0	; cplane[offset]=mm0
	add			eax, 16			; Next 16 pixels
	cmp			eax, r9d		; cmp row_size with count
	jle			.testplane
	
align 16
.outloop:
	pop rdi
	ret
	
ENDPROC_FRAME

;=============================================================================
; void accumulate_line_mode2_aligned_xmm(const BYTE* c_plane, const BYTE** planeP, int planes, int rowsize, __int64 t, int div) 
;=============================================================================
; parameter 1(cplane):		rcx
; parameter 2(planeP):		rdx
; parameter 3(planes):		r8d
; parameter 4(row_size):	r9d 
; parameter 5(t):			rsp+40
; parameter 6(div):			rsp+48
align 16
PROC_FRAME accumulate_line_mode2_uaxmm
	push		rdi		; rdi copies total planes to be used as a loop counter
	[pushreg	rdi]
END_PROLOG

%DEFINE .i64_t	[rsp+8+40]
%DEFINE .i_div	[rsp+8+48] 
		

	
	;movddup		xmm8, .i64_t	; copies a 64 bit value from mem and duplicates it int he upper half --> SSSE3 instruction :(
	movq		xmm8, .i64_t
	movlhps		xmm8, xmm8
	
	pxor		xmm15,xmm15		; our go to 0 register for unpacking
	xor			eax, eax
		
	movdqa		xmm9, [rel full]
	movdqa		xmm10, [rel add64]
	
	movd		xmm11, .i_div				; mov in div64
	pshufd		xmm11, xmm11,00000000b	; copy div64 to upper half

align 16
.testplane:
	movdqu		xmm0,[rcx+rax]	; Load current frame pixels cplane[offset]
	movdqa		xmm6,xmm0		; copy current pixels	
	movdqa		xmm7,xmm0		; copy current pixels
	punpcklbw	xmm6,xmm15		; mm0 = lower 4 pixels  (exchanging h/l in these two give funny results)
	punpckhbw	xmm7,xmm15		; mm1 = upper 4 pixels

	mov			edi, r8d		; load modifiable copy of planes
	lea			r10,[rdx+rdi*8-8] ;rdx=planeP, rdi=planes

align 16
.kernel_loop:
	mov			r11, QWORD [r10]
	movdqu		xmm1, [r11+rax]	; Load 16 pixels from test plane
	movdqa		xmm2, xmm0
	movdqa		xmm5, xmm1		; Save test plane pixels (twice for unpack)
	pmaxub		xmm2, xmm1		; Calc abs difference
	pminub		xmm1, xmm0
	psubusb		xmm2, xmm1		; mm2 = abs difference (packed bytes)
	psubusb		xmm2, xmm8		; Subtrack threshold (unsigned, so all below threshold will give 0)
	movdqa		xmm1, xmm5
	pcmpeqb		xmm2, xmm15		; Compare values to 0
	prefetchnta	[r11+rax+128]	; it might just help - and we have an idle CPU here anyway ;)
	movdqa		xmm3, xmm2
	pxor		xmm2, xmm9		; mm2 inverse mask
	movdqa		xmm4, xmm0
	pand		xmm5, xmm3
	pand		xmm4, xmm2
	por			xmm4, xmm5
	movdqa		xmm5, xmm4		;stall (this & below)
	punpcklbw	xmm4, xmm15		; mm4 = lower pixels
	punpckhbw	xmm5, xmm15		; mm5 = upper pixels
	paddusw		xmm6, xmm4
	paddusw		xmm7, xmm5

	sub			r10, 8			; changed from 4 to 8 because [rdi]=byte*'s = 8 bytes each
	sub			edi, 1			; planes--
	ja			.kernel_loop
	
	; Multiply (or in reality divides) added values, repack and store.
	movdqa		xmm0, xmm6
	movdqa		xmm1, xmm6
	punpcklwd	xmm0, xmm15		; low,low
	punpckhwd	xmm1, xmm15		; low,high
	movdqa		xmm2, xmm7
	pmaddwd		xmm0, xmm11		; pmaddwd is used due to it's better rounding.
	punpcklwd	xmm2, xmm15		; high,low
	movdqa		xmm3, xmm7
	paddd		xmm0, xmm10		; add64
	pmaddwd		xmm1, xmm11		; div64
	punpckhwd	xmm3, xmm15		; high,high
	psrld		xmm0, 15
	paddd		xmm1, xmm10		; add64
	pmaddwd		xmm2, xmm11		; div64
	packssdw	xmm0, xmm0
	psrld		xmm1, 15
	paddd		xmm2, xmm10		; add64
	pmaddwd		xmm3, xmm11		; div64
	packssdw	xmm1, xmm1
	psrld		xmm2, 15
	paddd		xmm3, xmm10		; add64
	psrld		xmm3, 15
	packssdw	xmm2, xmm2
	packssdw	xmm3, xmm3
	packuswb	xmm0, xmm15
	packuswb	xmm1, xmm15
	packuswb	xmm2, xmm15
	packuswb	xmm3, xmm15
	pshufd		xmm0, xmm0, 11111100b 
	pshufd		xmm1, xmm1, 11110011b
	pshufd		xmm2, xmm2, 11001111b
	pshufd		xmm3, xmm3, 00111111b
	por			xmm0, xmm1
	por			xmm2, xmm3
	por			xmm0, xmm2
	movdqu		[rcx+rax], xmm0	; cplane[offset]=mm0
	add			eax, 16			; Next 16 pixels
	cmp			eax, r9d		; cmp row_size with count
	jle			.testplane
	
align 16
.outloop:
	pop rdi
	ret
	
ENDPROC_FRAME

;=============================================================================
; int scenechange_isse_asm(const BYTE* c_plane, const BYTE* tplane, int height, int width, int c_pitch, int t_pitch);
;=============================================================================
; parameter 1(c_plane):		rcx
; parameter 2(t_plane):		rdx
; parameter 3(height):		r8d
; parameter 4(width):		r9d 
; parameter 5(c_pitch):		rsp+40
; parameter 6(t_pitch):		rsp+48

align 16
PROC_FRAME scenechange_isse_asm

END_PROLOG
%DEFINE .c_pitch [rsp+40]
%DEFINE	.t_pitch [rsp+48]

	and		r9d, 0FFFFFFE0h				; adjust width to be mod 32
	mov		r10d, DWORD .c_pitch		; r10 = c_pitch
	mov		r11d, DWORD .t_pitch		; r11 = t_pitch
	pxor	mm5, mm5					; Maximum difference
	pxor	mm6, mm6					; We maintain two sums, for better pairablility
	pxor	mm7, mm7
	
align 16
.yloop:
	xor		eax, eax					; Clear (x) width counter

align 16
.xloop:
	movq	mm0, [rcx+rax]
	movq	mm2, [rcx+rax+8]
	movq	mm1, [rdx+rax]
	movq	mm3, [rdx+rax+8]
	psadbw	mm0, mm1    ; Sum of absolute difference
	psadbw	mm2, mm3
	paddd	mm6, mm0     ; Add...
	paddd	mm7, mm2
	movq	mm0, [rcx+rax+16]
	movq	mm2, [rcx+rax+24]
	movq	mm1, [rdx+rax+16]
	movq	mm3, [rdx+rax+24]
	psadbw	mm0, mm1
	psadbw	mm2, mm3
	paddd	mm6, mm0
	paddd	mm7, mm2

	add		eax, 32
	cmp		eax, r9d    
	jb		.xloop
	
	add		rcx,r10     ; add pitch to both planes
	add		rdx,r11
	sub		r8d, 1		
	ja		.yloop

.end:
	paddd	mm7, mm6
	movd	eax, mm7
	emms
	ret
	
ENDPROC_FRAME

;=============================================================================
; int scenechange_sse3_asm(const BYTE* c_plane, const BYTE* tplane, int height, int width, int c_pitch, int t_pitch);
;=============================================================================
; parameter 1(c_plane):		rcx
; parameter 2(t_plane):		rdx
; parameter 3(height):		r8d
; parameter 4(width):		r9d 
; parameter 5(c_pitch):		rsp+40
; parameter 6(t_pitch):		rsp+48

align 16
PROC_FRAME scenechange_sse3_asm

END_PROLOG
%DEFINE .c_pitch [rsp+40]
%DEFINE	.t_pitch [rsp+48]

	
	mov		r10d, DWORD .c_pitch		; r10 = c_pitch
	mov		r11d, DWORD .t_pitch		; r11 = t_pitch

	test	r9d, 00000003Fh				; test if width is already divisible by 64
	jz		.noextra					; for precision, we do the first 32 bytes, then start the normal loop
	
	movdqa	xmm0, [rcx]
	movdqa	xmm1, [rdx]
	psadbw	xmm0, xmm1					; Sum of absolute difference
	
	movdqa	xmm2, [rcx+16]
	movdqa	xmm3, [rdx+16]
	psadbw	xmm2, xmm3					; Produces two 32bit results, one for top half, one for bottom
	
	movdqa	xmm6, xmm0					; Add...
	movdqa	xmm7, xmm2
	mov		eax, 32
	and		r9d, 0FFFFFFC0h				; adjust width to be mod 64
	jmp		.xloop

align 16
.noextra
	pxor	xmm6, xmm6					; We maintain two sums, for better pairablility
	pxor	xmm7, xmm7
	
align 16
.yloop:
	xor		eax, eax					; Clear (x) width counter

align 16
.xloop:
	prefetchnta[rcx+rax+64]
	prefetchnta[rdx+rax+64]
	
	movdqa	xmm0, [rcx+rax]
	movdqa	xmm1, [rdx+rax]
	psadbw	xmm0, xmm1					; Sum of absolute difference
	movdqa	xmm2, [rcx+rax+16]
	movdqa	xmm3, [rdx+rax+16]
	paddd	xmm6, xmm0
	

	psadbw	xmm2, xmm3
	movdqa	xmm8, [rcx+rax+32]
	movdqa	xmm9, [rdx+rax+32]					; Produces two 32bit results, one for top half, one for bottom
	paddd	xmm7, xmm2 ; Add...
	

	psadbw	xmm8, xmm9
	movdqa	xmm10, [rcx+rax+48]
	movdqa	xmm11, [rdx+rax+48]
	paddd	xmm6, xmm8
	
	psadbw	xmm10, xmm11
	paddd	xmm7, xmm10
	
	add		eax, 64
	cmp		eax, r9d 
	jb		.xloop
	
	add		rcx, r10					; add pitch to both planes
	add		rdx, r11
	sub		r8d, 1		
	ja		.yloop

.end:
	paddd	xmm7, xmm6
	movhlps	xmm0, xmm7		; grab 3rd dw-->where 2nd sad value stored
	movd	eax, xmm7
	movd	ecx, xmm0
	add		eax, ecx
	ret
	
ENDPROC_FRAME

;=============================================================================
; void AFH_YV12_ASM(uc* p, int height, const int pitch, const int row_size, const int amount)
;=============================================================================
; parameter 1(p):			rcx
; parameter 2(height):		rdx
; parameter 3(pitch):		r8d
; parameter 4(row_size):	r9d 
; parameter 5(amount):		rsp+40
PROC_FRAME AFH_YV12_ASM

END_PROLOG
%DEFINE .amount [rsp+40]


; signed word center weight ((amount+0x100)>>9) x4
	mov			ax, .amount
	add			ax, 100h
	sar			ax, 9
	mov			r10d, eax
	shl			r10d, 16
	or			eax, r10d
	movd		xmm14, eax
	pshufd		xmm14, xmm14, 00000000b
	
	

; signed word outer weight 64-((amount+0x100)>>9) x4
	mov			r10w, 040h
	sub			r10w, ax
	;and			r10d, 0FFFFh
	mov			eax, r10d
	shl			eax, 16
	or			r10d, eax
	movd		xmm13, r10d
	pshufd		xmm13, xmm13, 00000000b
	
	pxor		xmm15, xmm15
	
	movdqa		xmm7, [rel i64_r7]
	movdqa		xmm8, [rel leftmask]
	movdqa		xmm9, [rel rightmask]
	
align 16
.xloop:	
	mov			eax, r9d
	;test		r9d, 15
	;jz			.nopad
	
	;mov			r10w, [rcx+r9-2]	; Pad edge pixel if needed
	;mov			[rcx+r9], r10w

align 16
.nopad:
	;add			eax, 15
	shr			eax, 4					; round to multiple of 16

										; first row
	movdqu		xmm2, [rcx]				; Centre 8 pixels
	movdqa		xmm1, xmm8				; 0x00000000000000ff
	movdqa		xmm3, xmm2				; Duplicate for left
	pand		xmm1, xmm2				; Left edge pixel
	psllq		xmm3, 8					; Left 7 other pixels
	sub			eax, 1
	por			xmm1, xmm3				; Left pixels, left most repeated
	jz			.out_row_loop_ex		; 8 or less pixels per line

	movdqu		xmm3,[rcx+2]			; Right 8 pixels

	scale xmm1,xmm2,xmm3,xmm4,xmm5,xmm6,xmm15

	sub			eax, 1
	jz			.out_row_loop			; 9 to 16 pixels per line

align 16
.row_loop:
	movdqu		xmm1, [rcx-2]		; Pickup left 8th before it's updated
	movdqu		[rcx-16], xmm4		; update current 8 pixels
	movdqu		xmm2, [rcx]			; Centre 8 pixels
	movdqu		xmm3, [rcx+2]		; Right 8 pixels

	scale xmm1,xmm2,xmm3,xmm4,xmm5,xmm6,xmm15

	sub			eax, 1
	ja			.row_loop			; more ?

.out_row_loop:
	movdqu		xmm1, [rcx-2]		; Pickup left 8th before it's updated
	movdqu		[rcx-16], xmm4		; update current 8 pixels
	movdqu		xmm2, [rcx]			; Centre 8 pixels

.out_row_loop_ex:
	movdqa		xmm3, xmm9			; 0xFF00000000000000
	movdqa		xmm4, xmm2			; Duplicate for right
	pand		xmm3, xmm2			; Right edge pixel
	psrlq		xmm4, 8				; Right 7 other pixels
	por			xmm3, xmm4			; Right pixles, right most repeated

	scale xmm1,xmm2,xmm3,xmm4,xmm5,xmm6,xmm15

	movdqu		[rcx-16], xmm4		; update current 8 pixels

	add			rcx, r8
	sub			edx, 1
	ja			.xloop
	
	ret
ENDPROC_FRAME