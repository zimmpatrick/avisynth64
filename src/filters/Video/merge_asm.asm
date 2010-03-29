;=============================================================================
; Function declarations
;=============================================================================
	global mmx_merge_luma
	global mmx_weigh_luma
	global mmx_weigh_chroma
	global mmx_weigh_plane
	global isse_avg_plane
	
;=============================================================================
; Read only data
;=============================================================================
SECTION .rodata 
align 16
I1:
	dq 000ff00ff00ff00ffh
	dq 000ff00ff00ff00ffh
I2:
	dq 0ff00ff00ff00ff00h
	dq 0ff00ff00ff00ff00h
rounder:
	dq 00000400000004000h
	dq 00000400000004000h

section .text
;=============================================================================
;void mmx_merge_luma( unsigned int *src, unsigned int *luma, int pitch, int luma_pitch,int width, int height )
;=============================================================================
; parameter 1(src): rcx
; parameter 2(luma): rdx
; parameter 3(pitch): r8d
; parameter 4(luma_pitch): r9d 
; parameter 5(width): rsp + 40
; parameter 6(height): rsp + 48 -->terminates loop!
align 16
PROC_FRAME mmx_merge_luma
END_PROLOG

	;int row_size = width * 2;
	mov		r10d, [rsp+40]
	add		r10d, r10d
	mov		dword [rsp+40],r10d ;store it back where it came from, width unused after
		
	;int row_even = row_size & -8;
	mov		r11d, r10d
	and		r11d, -8
	mov		dword [rsp+8], r11d ;just use rcx's shadow space
	
	;int lwidth_bytes = row_size & -16;	// bytes handled by the MMX loop
	mov		r11d, r10d
	and		r11d, -16
	
	;load in constants and such
	movdqa	xmm3,[rel I1]     ; Luma mask
	movdqa	xmm4,[rel I2]     ; Chroma mask
	
	;r10d is for loop counter
	;eax is pixel counter
	xor		r10d, r10d

align 16	
.yloop
	cmp		r10d, dword [rsp+48] ;compare our counter with the height
	jge		.finish
	xor		eax, eax

align 16	
.goloop:
	;can we do 16 bytes?
	cmp		eax, r11d
	jge		.outloop
	
	; Processes 8 pixels at the time
	movdqa	xmm0,[rcx+rax]	; load chroma 8 pixels
	movdqa	xmm1,[rdx+rax]  ; load luma 8 pixels
	pand	xmm0,xmm3		; mask chroma
	pand	xmm1,xmm4		; mask luma
	por		xmm0,xmm2		; merge
	movdqa	[rcx+rax],xmm0	; store back to source
	add		eax,16
	jmp		.goloop

align 16	
.outloop:
	; processes remaining pixels pair
	cmp		eax, dword [rsp+8]	;see if there are 8 pixels left
	jge		.outeven
	
	movq	xmm0,[rcx+rax]	; load chroma 8 pixels
	movq	xmm1,[rdx+rax]  ; load luma 8 pixels
	pand	xmm0,xmm3		; mask chroma
	pand	xmm1,xmm4		; mask luma
	por		xmm0,xmm2		; merge
	movq	[rcx+rax-8], xmm0
	add		eax,8
align 16
.outeven:
	; processes remaining pixel
	cmp		eax,dword [rsp+40] ;see if any processing remains
	jge		.exitloop	
	movd	xmm0,[rcx+rax]	; load chroma
	movd	xmm1,[rdx+rax]  ; load luma
	pand	xmm0,xmm3		; mask chroma
	pand	xmm1,xmm4		; mask luma
	por		xmm0,xmm1		; merge
	movd	[rcx+rax],xmm0

align 16	
.exitloop
	; add pitch in, proceed to next set
	add		rcx,r8
	add		rdx,r9
	inc		r10d
	jmp		.yloop

align 16
.finish:
	ret
ENDPROC_FRAME
	
	
;=============================================================================	
;void mmx_weigh_luma(unsigned int *src,unsigned int *luma, int pitch, int luma_pitch,int width, int height, int weight, int invweight)
;=============================================================================
; parameter 1(src): rcx
; parameter 2(luma): rdx
; parameter 3(pitch): r8d
; parameter 4(luma_pitch): r9d 
; parameter 5(width): rsp+48
; parameter 6(height): rsp+56 -->terminates loop!
; parameter 7(weight): rsp+64
; parameter 7(inv_weight): rsp+72
align 16
PROC_FRAME mmx_weigh_luma
END_PROLOG

	;int row_size = width * 2;
	mov			r10d, [rsp+40]
	add			r10d, r10d
	mov			dword [rsp+40],r10d ;store it back where it came from, width unused after
		
	;int lwidth_bytes = row_size & -8;	// bytes handled by the main loop
	mov			r11d, r10d
	and			r11d, -8
	
	;load in constants and such
	movq		mm7,[rel I1]		; Luma
	movq		mm6,[rel I2]		; Chroma
	movd		mm5,[rsp+64]		; invweight
	punpcklwd	mm5,[rsp+56]		; weight
	punpckldq	mm5,mm5				; Weight = invweight | (weight<<16) | (invweight<<32) | (weight<<48);
	movq		mm4,[rel rounder]

	;r10d is for loop counter
	;eax is pixel counter
	xor			r10d, r10d
	xor			rax, rax ; clear rax fully for good measure
	
.yloop:
	cmp			r10d, dword [rsp+48] ;compare our counter with the height
	jge			.finish
	xor			eax, eax
	
	cmp			eax,r11d		; Is eax(i) greater than endx
	jge			.outloop		; Jump out of loop if true
								; weird condition, but I geuss it could happen?
	
	movq		mm3,[rcx]		; original 4 pixels   (cc)
align 16
.goloop:
	; Processes 4 pixels at the time
	movq		mm2,[rdx+rax]	; load luma 4 pixels
	movq		mm1,mm3			; move original pixel into mm3
	punpckhwd	mm3,mm2			; Interleave upper pixels in mm3 | mm3= CCLL ccll CCLL ccll
	movq		mm0,mm1
	punpcklwd	mm1,mm2			; Interleave lower pixels in mm1 | mm1= CCLL ccll CCLL ccll
	pand		mm3,mm7			; mm3= 00LL 00ll 00LL 00ll
	pand		mm1,mm7
	pmaddwd		mm3,mm5			; Mult with weights and add. Latency 2 cycles - mult unit cannot be used
	pand		mm0,mm6			; mm0= cc00 cc00 cc00 cc00
	pmaddwd		mm1,mm5
	paddd		mm3,mm4			; round to nearest
	paddd		mm1,mm4			; round to nearest
	psrld		mm3,15			; Divide with total weight (=15bits) mm3 = 0000 00LL 0000 00LL
	psrld		mm1,15			; Divide with total weight (=15bits) mm1 = 0000 00LL 0000 00LL
	add			eax,8			; 8 bytes per pass = 4 pixels = 1 quadword
	packssdw	mm1, mm3		; mm1 = 00LL 00LL 00LL 00LL
	cmp			eax,r11d		; Is eax(i) greater than endx
	por			mm1,mm0
	movq		mm3,[rcx+rax]	; original 4 pixels   (cc)
	movq		[rcx+rax-8],mm1
	jnge		.goloop			; fall out of loop if true

align 16
.outloop:
	; processes remaining pixels here
	cmp			eax, dword [rsp+40]		; compare against row size
	jge			.exitloop
	movd		mm1,[rcx+rax]			; original 2 pixels
	movd		mm2,[rdx+rcx]			; luma 2 pixels
	movq		mm0,mm1
	punpcklwd	mm1,mm2					; mm1= CCLL ccll CCLL ccll
	pand		mm0,mm6					; mm0= 0000 0000 cc00 cc00
	pand		mm1,mm7					; mm1= 00LL 00ll 00LL 00ll
	pmaddwd		mm1,mm5
	paddd		mm1,mm4					; round to nearest
	psrld		mm1,15					; mm1= 0000 00LL 0000 00LL
	packssdw	mm1,mm1					; mm1= 00LL 00LL 00LL 00LL
	por			mm1,mm0					; mm0 finished
	movd		[rcx+rax],mm1
	; no loop since there is at most 2 remaining pixels


.exitloop:
	add			rcx, r8
	add			rdx, r9
	inc			r10d
	jmp			.yloop

align 16
.finish:
	emms
	ret
ENDPROC_FRAME

;=============================================================================
;void mmx_weigh_chroma( unsigned int *src,unsigned int *chroma, int pitch, int chroma_pitch,int width, int height, int weight, int invweight)
;=============================================================================
; parameter 1(src): rcx
; parameter 2(chroma): rdx
; parameter 3(pitch): r8d
; parameter 4(chroma_pitch): r9d 
; parameter 5(width): rsp+40
; parameter 6(height): rsp+48 -->terminates loop!
; parameter 7(weight): rsp+56
; parameter 7(inv_weight): rsp+64
align 16
PROC_FRAME mmx_weigh_chroma
END_PROLOG

	;int row_size = width * 2;
	mov			r10d, [rsp+40]
	add			r10d, r10d
	mov			dword [rsp+40],r10d ;store it back where it came from, width unused after
		
	;int lwidth_bytes = row_size & -8;	// bytes handled by the main loop
	mov			r11d, r10d
	and			r11d, -8

	;load in constants and such
	movq		mm7,[rel I1]		; Luma
	movd		mm5,[rsp+64]		; invweight
	punpcklwd	mm5,[rsp+56]		; weird
	punpckldq	mm5,mm5				; Weight = invweight | (weight<<16) | (invweight<<32) | (weight<<48);
	movq		mm4,[rel rounder]

align 16	
.yloop:
	cmp			r10d, dword [rsp+48] ;compare our counter with the height
	jge			.finish
	xor			eax, eax
	
	cmp			eax,r11d		; Is eax(i) greater than endx
	jge			.outloop		; Jump out of loop if true
								; weird condition, but I geuss it could happen
			
	movq		mm1,[rcx]		; original 4 pixels   (cc)
	movq		mm2,[rdx]		; load 4 pixels

align 16	
.goloop:
	movq		mm3,mm1
	punpcklwd	mm1,mm2			; Interleave lower pixels in mm1 | mm1= CCLL ccll CCLL ccll
	movq		mm0,mm3			; move original pixel into mm3
	psrlw		mm1,8
	punpckhwd	mm3,mm2			; Interleave upper pixels in mm3 | mm3= CCLL ccll CCLL ccll
	pmaddwd		mm1,mm5
	psrlw		mm3,8			; mm3= 00CC 00cc 00CC 00cc
	paddd		mm1,mm4			; round to nearest
	pmaddwd		mm3,mm5			; Mult with weights and add. Latency 2 cycles - mult unit cannot be used
	psrld		mm1,15			; Divide with total weight (=15bits) mm1 = 0000 00CC 0000 00CC
	paddd		mm3,mm4			; round to nearest
	pand		mm0,mm7			; mm0= 00ll 00ll 00ll 00ll
	psrld		mm3,15			; Divide with total weight (=15bits) mm3 = 0000 00CC 0000 00CC
	add			eax,8			; 8 bytes per pass = 4 pixels = 1 quadword
	packssdw	mm1, mm3		; mm1 = 00CC 00CC 00CC 00CC
	cmp			eax,r11d		; Is eax(i) greater than endx
	psllw		mm1,8
	movq		mm2,[rdx+rax]	; load 4 pixels
	por			mm0,mm1
	movq		mm1,[rcx+rax]	; original 4 pixels   (cc)
	movq		[rcx+rax-8],mm0
	jnge		.goloop			; fall out of loop if true

align 16	
.outloop:
	; processes remaining pixels here
	cmp			eax,[rsp+40]	;compare against width
	jge			.exitloop
	movd		mm0,[rcx+rax]	; original 2 pixels
	movd		mm2,[rdx+rax]	; luma 2 pixels
	movq		mm1,mm0
	punpcklwd	mm1,mm2			; mm1= CCLL ccll CCLL ccll
	psrlw		mm1,8			; mm1= 00CC 00cc 00CC 00cc
	pmaddwd		mm1,mm5
	pand		mm0,mm7			; mm0= 0000 0000 00ll 00ll
	paddd		mm1,mm4			; round to nearest
	psrld		mm1,15			; mm1= 0000 00CC 0000 00CC
	packssdw	mm1,mm1
	psllw		mm1,8			; mm1= CC00 CC00 CC00 CC00
	por			mm0,mm1			; mm0 finished
	movd		[rcx+rax],mm0

align 16
.exitloop:
	add			rcx, r8
	add			rdx, r9
	inc			r10d
	jmp			.yloop

align 16	
.finish:
	emms
	ret
ENDPROC_FRAME

;=============================================================================
;void mmx_weigh_plane(BYTE *p1, const BYTE *p2, int p1_pitch, int p2_pitch,int rowsize, int height, int weight, int invweight) 
;=============================================================================
; parameter 1(p1): rcx
; parameter 2(p2): rdx
; parameter 3(p1_pitch): r8d
; parameter 4(p2_pitch): r9d 
; parameter 5(rowsize): rsp+8+40
; parameter 6(height): rsp+8+48 -->terminates loop!
; parameter 7(weight): rsp+8+56
; parameter 7(inv_weight): rsp+8+64
align 16
PROC_FRAME mmx_weigh_plane
	push		rbx
	[pushreg	rbx]
END_PROLOG
	
	movdqa		xmm5,[rel rounder]
	pxor		xmm6,xmm6
	movd		xmm7,[rsp+8+56]	; weight
	movd		xmm8,[rsp+8+64]
	punpcklwd	xmm7,xmm8	; invweight
	punpckldq	xmm7,xmm7		; Weight = weight | (invweight<<16) | (weight<<32) | (invweight<<48);
	punpckldq	xmm7,xmm7	
	mov			r10d,[rsp+8+40]	; rowsize
	xor			rbx, rbx		; ebx = Height counter
	xor			rax, rax		; eax = inner loop counter
	mov			r11d,[rsp+8+48]	; height
	test		r10d, r10d
	jz			.finish

align 16
.yloop:
	xor			eax, eax
	cmp			ebx, r11d
	jge			.finish

align 16
.testloop:
	movdqa		xmm0,[rdx+rax]  ; y7y6 y5y4 y3y2 y1y0 img2
	movdqa		xmm1,[rcx+rax]  ; Y7Y6 Y5Y4 Y3Y2 Y1Y0 IMG1
	movdqa		xmm2,xmm0
	punpcklbw	xmm0,xmm1        ; Y3y3 Y2y2 Y1y1 Y0y0
	punpckhbw	xmm2,xmm1        ; Y7y7 Y6y6 Y5y5 Y4y4
	movdqa		xmm1,xmm0        ; Y3y3 Y2y2 Y1y1 Y0y0
	punpcklbw	xmm0,xmm6        ; 00Y1 00y1 00Y0 00y0
	movdqa		xmm3,xmm2        ; Y7y7 Y6y6 Y5y5 Y4y4
	pmaddwd		xmm0,xmm7        ; Multiply pixels by weights.  pixel = img1*weight + img2*invweight (twice)
	punpckhbw	xmm1,xmm6        ; 00Y3 00y3 00Y2 00y2
	paddd		xmm0,xmm5        ; Add rounder
	pmaddwd		xmm1,xmm7        ; Multiply pixels by weights.  pixel = img1*weight + img2*invweight (twice)
	punpcklbw	xmm2,xmm6        ; 00Y5 00y5 00Y4 00y4
	paddd		xmm1,xmm5        ; Add rounder                         
	psrld		xmm0,15         ; Shift down, so there is no fraction.
	pmaddwd		xmm2,xmm7        ; Multiply pixels by weights.  pixel = img1*weight + img2*invweight (twice)
	punpckhbw	xmm3,xmm6        ; 00Y7 00y7 00Y6 00y6
	paddd		xmm2,xmm5        ; Add rounder
	pmaddwd		xmm3,xmm7        ; Multiply pixels by weights.  pixel = img1*weight + img2*invweight (twice)
	psrld		xmm1,15         ; Shift down, so there is no fraction.
	paddd		xmm3,xmm5        ; Add rounder                         
	psrld		xmm2,15         ; Shift down, so there is no fraction.
	psrld		xmm3,15         ; Shift down, so there is no fraction.
	packssdw	xmm0,xmm1        ; 00Y3 00Y2 00Y1 00Y0
	packssdw	xmm2,xmm3        ; 00Y7 00Y6 00Y5 00Y4
	add			eax,16
	packuswb	xmm0,xmm2        ; Y7Y6 Y5Y4 Y3Y2 Y1Y0
	cmp			r10d, eax
	movdqa		[rcx+rax-16],xmm0
	jg			.testloop

	inc			ebx
	add			rcx,r8
	add			rdx,r9
	jmp			.yloop

align 16
.finish:
	emms
	pop rbx
	ret
ENDPROC_FRAME
	
;=============================================================================
;void isse_avg_plane(BYTE *p1, const BYTE *p2, int p1_pitch, int p2_pitch,int rowsize, int height) 
;=============================================================================
; parameter 1(p1): rcx
; parameter 2(p2): rdx
; parameter 3(p1_pitch): r8d
; parameter 4(p2_pitch): r9d 
; parameter 5(rowsize): rsp+40
; parameter 6(height): rsp+48 -->terminates loop!
align 16
PROC_FRAME isse_avg_plane
	push	rbx
	[pushreg rbx]
END_PROLOG 
	mov		r10d,[rsp+40]	;rowsize
	xor		rbx,rbx			;height counter
	mov		r11d,[rsp+48]	;height
	test	r11d, r11d
	jz		.finish
  
align 16
.yloopback:
	mov		eax,16
	cmp		ebx,r11d
	jge		.finish

	cmp		r10d, eax
	jl		.twelve

align 16
.testloop:
	movq	mm0,[rcx+rax-16]  ; y7y6 y5y4 y3y2 y1y0 img2
	movq	mm1,[rcx+rax- 8]  ; yFyE yDyC yByA y9y8 img2
	pavgb	mm0,[rdx+rax-16]  ; Y7Y6 Y5Y4 Y3Y2 Y1Y0 IMG1
	pavgb	mm1,[rdx+rax- 8]  ; YfYe YdYc YbYa Y9Y8 IMG1
	movq	[rcx+rax-16],mm0
	movq	[rcx+rax- 8],mm1
	add		eax,16
	cmp		r10d, eax
	jge		.testloop

align 16
.twelve:
	test	ebx, 8
	jz		.four
	movq	mm0,[rdx+rax-16]  ; y7y6 y5y4 y3y2 y1y0 img2
	pavgb	mm0,[rcx+rax-16]  ; Y7Y6 Y5Y4 Y3Y2 Y1Y0 IMG1
	movq	[rcx+rax-16],mm0
	add		eax,8

align 16
.four:
	test	ebx, 4
	jz		.zero
	movd	mm0,[rdx+rax-16]  ; ____ ____ y3y2 y1y0 img2
	movd	mm1,[rcx+rax-16]  ; ____ ____ Y3Y2 Y1Y0 IMG1
	pavgb	mm0,mm1
	movd	[rcx+rax-16],mm0

align 16
.zero:
	inc		rbx
	add		rcx,r8
	add		rdx,r9
	jmp		.yloopback

.finish:
	emms
	pop		rbx
	ret
ENDPROC_FRAME
