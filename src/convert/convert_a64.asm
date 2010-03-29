; Avisynth v2.5.  Copyright 2002 Ben Rudiak-Gould et al.
; http://www.avisynth.org
;
; This program is free software; you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation; either version 2 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program; if not, write to the Free Software
; Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA, or visit
; http://www.gnu.org/copyleft/gpl.html .
;
; Linking Avisynth statically or dynamically with other modules is making a
; combined work based on Avisynth.  Thus, the terms and conditions of the GNU
; General Public License cover the whole combination.
;
; As a special exception, the copyright holders of Avisynth give you
; permission to link Avisynth with independent modules that communicate with
; Avisynth solely through the interfaces defined in avisynth.h, regardless of the license
; terms of these independent modules, and to copy and distribute the
; resulting combined work under terms of your choice, provided that
; every copy of the combined work is accompanied by a complete copy of
; the source code of Avisynth (the version of Avisynth used to produce the
; combined work), being distributed under the terms of the GNU General
; Public License plus this exception.  An independent module is a module
; which is not derived from or based on Avisynth, such as 3rd-party filters,
; import and export plugins, or graphical user interfaces.

;=============================================================================
; Constants
;=============================================================================
%define ofs_x0000_0000_0010_0010  0
%define ofs_x0080_0080_0080_0080  8
%define ofs_x00FF_00FF_00FF_00FF  16
%define ofs_x00002000_00002000 24
%define ofs_xFF000000_FF000000 32
%define ofs_cy 40
%define ofs_crv 48
%define ofs_cgu_cgv 56
%define ofs_cbu 64

;=============================================================================
; Read only data
;=============================================================================
SECTION .rodata align=16

yuv2rgb_constants_rec601:
						dq	00000000000100010h		;    16
						dq	00080008000800080h		;   128
						dq	000FF00FF00FF00FFh
						dq	00000200000002000h		;  8192        = (0.5)<<14
						dq	0FF000000FF000000h
						dq	000004A8500004A85h		; 19077        = (255./219.)<<14+0.5
						dq	03313000033130000h		; 13075        = ((1-0.299)*255./112.)<<13+0.5
						dq	0E5FCF377E5FCF377h		; -6660, -3209 = ((K-1)*K/0.587*255./112.)<<13-0.5, K=(0.299, 0.114)
						dq	00000408D0000408Dh		;        16525 = ((1-0.114)*255./112.)<<13+0.5

yuv2rgb_constants_PC_601:
						dq	00000000000000000h		;     0       
						dq	00080008000800080h		;   128       
						dq	000FF00FF00FF00FFh                    
						dq	00000200000002000h		;  8192        = (0.5)<<14
						dq	0FF000000FF000000h                    
						dq	00000400000004000h		; 16384        = (1.)<<14+0.5                                
						dq	02D0B00002D0B0000h		; 11531        = ((1-0.299)*255./127.)<<13+0.5                      
						dq	0E90FF4F2E90FF4F2h		; -5873, -2830 = (((K-1)*K/0.587)*255./127.)<<13-0.5, K=(0.299, 0.114)
						dq	0000038ED000038EDh		;        14573 = ((1-0.114)*255./127.)<<13+0.5                      

yuv2rgb_constants_rec709:
						dq	00000000000100010h		;    16       
						dq	00080008000800080h		;   128       
						dq	000FF00FF00FF00FFh                    
						dq	00000200000002000h		;  8192        = (0.5)<<14
						dq	0FF000000FF000000h                    
						dq	000004A8500004A85h		; 19077        = (255./219.)<<14+0.5
						dq	0395E0000395E0000h		; 14686        = ((1-0.2126)*255./112.)<<13+0.5
						dq	0EEF2F92DEEF2F92Dh		; -4366, -1747 = ((K-1)*K/0.7152*255./112.)<<13-0.5, K=(0.2126, 0.0722)
						dq	00000439900004399h		;        17305        = ((1-0.0722)*255./112.)<<13+0.5       

yuv2rgb_constants_PC_709:
						dq	00000000000000000h		;     0       
						dq	00080008000800080h		;   128       
						dq	000FF00FF00FF00FFh                    
						dq	00000200000002000h		;  8192        = (0.5)<<14
						dq	0FF000000FF000000h                    
						dq	00000400000004000h		; 16384        = (1.)<<14+0.5                                
						dq	03298000032980000h		; 12952        = ((1-0.2126)*255./127.)<<13+0.5                      
						dq	0F0F6F9FBF0F6F9FBh		; -3850, -1541 = (((K-1)*K/0.7152)*255./127.)<<13-0.5, K=(0.2126, 0.0722)
						dq	000003B9D00003B9Dh		;        15261 = ((1-0.0722)*255./127.)<<13+0.5

mask2:
	dq	0xFF00FF00FF00FF00
	
add_ones:
	dq  0x0101010101010101
	
rgb_mask:
	dq	0x00FFFFFF00FFFFFF

fraction:
	dd	0x00084000 ; 0
	dd	0x00084000 ; 4
	dd  0x00004000 ; 8
	dd	0x00004000 ; 16
	
;y1y2_mult:
	dd	0x00004A85 ; 20
	dd	0x00004A85 ; 24
	dd	0x00004000 ; 28 
	dd	0x00004000 ; 32

;fpix_mul:
	dq	0x0000503300003F74 ; 40
	dq	0x0000476600003C6E ; 48
	dq	0x00005AF1000047F4 ; 56
	dq	0x000050F6000044B6 ; 64

;cybgr:
	dq	0x000020DE40870C88 ; 72
	dq	0x0000175F4E9F07F0 ; 80
	dq	0x000026464B230E97 ; 88
	dq	0x00001B365B8C093E ; 96
	
sub_32:
	dd	0x0000FFE0

rb_mask:
	dq	0x0000ffff0000ffff

fpix_add:
	dq	0x0080800000808000

chroma_mask2:
	dq	0xffff0000ffff0000                    



;=============================================================================
; Macros
;=============================================================================

%macro GET_Y 2  ; mma, uyvy
%if %2
	psrlw %1, 8
%else
	pand %1, [r11+ofs_x00FF_00FF_00FF_00FF]
%endif
%endmacro

%macro GET_UV 2  ; mma, uyvy
	GET_Y %1, (1-%2)
%endmacro

;=============================================================================

%macro YUV2RGB_INNER_LOOP 3  ; uyvy, rgb32, no_next_pixel

;; This YUV422->RGB conversion code uses only four MMX registers per
;; source dword, so I convert two dwords in parallel.  Lines corresponding
;; to the "second pipe" are indented an extra space.  There's almost no
;; overlap, except at the end and in the three lines marked ***.
;; revised 4july,2002 to properly set alpha in rgb32 to default "on" & other small memory optimizations

	movd		mm0, [r8] ; DWORD PTR for compatibility with masm8
	movd		mm5, [r8+4]
	movq		mm1,mm0
	GET_Y		mm0,%1		; mm0 = __________Y1__Y0
	movq		mm4,mm5
	GET_UV		mm1,%1		; mm1 = __________V0__U0
	GET_Y		mm4,%1		; mm4 = __________Y3__Y2
	movq		mm2,mm5		; *** avoid reload from [esi+4]
	GET_UV		mm5,%1		; mm5 = __________V2__U2
	psubw		mm0,[r11+ofs_x0000_0000_0010_0010]	; (Y-16)
	movd		mm6,[r8+8-4*%3]
	GET_UV		mm2,%1		; mm2 = __________V2__U2
	psubw		mm4,[r11+ofs_x0000_0000_0010_0010]	; (Y-16)
	paddw		mm2,mm1		; 2*UV1=UV0+UV2
	GET_UV		mm6,%1	; mm6 = __________V4__U4
	psubw		mm1,[r11+ofs_x0080_0080_0080_0080]	; (UV-128)
	paddw		mm6,mm5	; 2*UV3=UV2+UV4
	psllq		mm2,32
	psubw		mm5,[r11+ofs_x0080_0080_0080_0080]	; (UV-128)
	punpcklwd	mm0,mm2		; mm0 = ______Y1______Y0
	psllq		mm6,32
	pmaddwd		mm0,[r11+ofs_cy]	; (Y-16)*(255./219.)<<14
	punpcklwd	mm4,mm6
	paddw		mm1,mm1		; 2*UV0=UV0+UV0
	pmaddwd		mm4,[r11+ofs_cy]
	paddw		mm5,mm5	; 2*UV2=UV2+UV2
	paddw		mm1,mm2		; mm1 = __V1__U1__V0__U0 * 2
	paddd		mm0,[r11+ofs_x00002000_00002000]	; +=0.5<<14
	paddw		mm5,mm6	; mm5 = __V3__U3__V2__U2 * 2
	movq		mm2,mm1
	paddd		mm4,[r11+ofs_x00002000_00002000]	; +=0.5<<14
	movq		mm3,mm1
	movq		mm6,mm5
	pmaddwd		mm1,[r11+ofs_crv]
	movq		mm7,mm5
	paddd		mm1,mm0
	pmaddwd		mm5,[r11+ofs_crv]
	psrad		mm1,14		; mm1 = RRRRRRRRrrrrrrrr
	paddd		mm5,mm4
	pmaddwd		mm2,[r11+ofs_cgu_cgv]
	psrad		mm5,14
	paddd		mm2,mm0
	pmaddwd		mm6,[r11+ofs_cgu_cgv]
	psrad		mm2,14		; mm2 = GGGGGGGGgggggggg
	paddd		mm6,mm4
	pmaddwd		mm3,[r11+ofs_cbu]
	psrad		mm6,14
	paddd		mm3,mm0
	pmaddwd		mm7,[r11+ofs_cbu]
	add			r8,8
	add			rdx,12+4*%2
	
%if (%3==0)
	cmp			r8,rax
%endif
	
	psrad		mm3,14		; mm3 = BBBBBBBBbbbbbbbb
	paddd		mm7,mm4
	pxor		mm0,mm0
	psrad		mm7,14
	packssdw	mm3,mm2	; mm3 = GGGGggggBBBBbbbb
	packssdw	mm7,mm6
	packssdw	mm1,mm0	; mm1 = ________RRRRrrrr
	packssdw	mm5,mm0	; *** avoid pxor mm4,mm4
	movq		mm2,mm3
	movq		mm6,mm7
	punpcklwd	mm2,mm1	; mm2 = RRRRBBBBrrrrbbbb
	punpcklwd	mm6,mm5
	punpckhwd	mm3,mm1	; mm3 = ____GGGG____gggg
	punpckhwd	mm7,mm5
	movq		mm0,mm2
	movq		mm4,mm6
	punpcklwd	mm0,mm3	; mm0 = ____rrrrggggbbbb
	punpcklwd	mm4,mm7

%if (%2==0)
	psllq		mm0,16
	psllq		mm4,16
%endif

	punpckhwd	mm2,mm3	; mm2 = ____RRRRGGGGBBBB
	punpckhwd	mm6,mm7
	packuswb	mm0,mm2	; mm0 = __RRGGBB__rrggbb <- ta dah!
	packuswb	mm4,mm6

%if (%2==1)
	por			mm0, [r11+ofs_xFF000000_FF000000]	 ; set alpha channels "on"
	por			mm4, [r11+ofs_xFF000000_FF000000]
	movq		[rdx-16],mm0	; store the quadwords independently
	movq		[rdx-8],mm4
%else
	psrlq		mm0,8			; pack the two quadwords into 12 bytes
	psllq		mm4,8			; (note: the two shifts above leave
	movd		[rdx-12],mm0	; mm0,4 = __RRGGBBrrggbb__)
	psrlq		mm0,32
	por			mm4,mm0
	movd		[rdx-8],mm4
	psrlq		mm4,32
	movd		[rdx-4],mm4
%endif

%endmacro

;=============================================================================
SECTION .text
%macro YUV2RGB_PROC 3  ; procname, uyvy, rgb32
global %1
PROC_FRAME %1
END_PROLOG
;;void __cdecl procname(
;;	rcx		 const BYTE* src,
;;	rdx		 BYTE* dst,
;;	r8		 const BYTE* src_end,
;;	r9d		 int src_pitch,
;;	[rsp+40] int row_size,
;;	[rsp+48] rec709 matrix);  0=rec601, 1=rec709, 3=PC_601, 7=PC_709

	
	movsxd r10, dword [rsp+40] ; row_size
	mov al, byte [rsp+48] ; temp storage for testing of matrix
	
	lea r11, [yuv2rgb_constants_rec601 wrt rip]
	test	al,1
	jz	.%1_loop0
	
	lea	r11, [yuv2rgb_constants_rec709 wrt rip]
	test	al,2
	jz	.%1_loop0
	
	lea	r11, [yuv2rgb_constants_PC_601 wrt rip]
	test	al,4
	jz	.%1_loop0
	
	lea	r11, [yuv2rgb_constants_PC_709 wrt rip]

.%1_loop0:
	sub	r8,r9 ;r8=dst_end-pitch
	lea rax, [r8+r10-8] ;load [address of end-pitch+rowsize-8] 

.%1_loop1:
	YUV2RGB_INNER_LOOP	%2,%3,0
	jb	.%1_loop1

	YUV2RGB_INNER_LOOP	%2,%3,1

	sub	r8,r10
	cmp	r8,rcx
	ja	.%1_loop0

	emms
	ret

%endmacro

;=============================================================================
; void convertxxxtoyuy2 (const BYTE* src, BYTE* dst, int src_pitch, int dst_pitch, int w, int h, int matrix);
;=============================================================================

%macro convertxxxtoyuy2 4	; procname, RGB24, DUPL, (matrix<2)	
global %1
PROC_FRAME %1
	push rbx
	[pushreg rbx]
	push rsi
	[pushreg rsi]
ENDPROLOG
	
	; load in constants for RGB processing
	mov			ebx, DWORD [rsp+16+56]				; matrix (0-3)
	lea			rax, [rel fraction]
	lea			rbx, [rax+rbx*4]					; fraction addr wrt to matrix index
	movd		mm0, DWORD [rbx]
	movq		mm7, QWORD [rbx+32]					; indexes into cygbr
	movd		mm5, DWORD [rbx+16]					; indexes into y1y2_mult

	
	mov			esi, DWORD [rsp+16+48]	; esi = height
	mov			r10,rdx					; save rdx for upcoming mult
	mov			eax, esi
	dec			eax
	mul			r8d						; eax = src_pitch*(height-1)
	mov			rdx, r10				; restore rdx
	add			rcx, rax				; Move source to bottom line (read top->bottom)
	
	mov			eax, DWORD [rsp+16+40]	; eax width
	%IF (%2==1) ;rgb24
	lea			eax,[eax+eax*2]			; eax = width*3 = rgb24 width in bytes
	%ELSE
	shr			eax, 2					; eax = width*4 = rgb32 width in bytes
	%ENDIF
	
	
.yloop:
	; zero offsets
	xor			r10, r10				; RGB Offset
	xor			r11, r11				; YUV offset
	
	movq		mm2, QWORD [rcx+r10]	; mm2= XXR2 G2B2 XXR1 G1B1
	cmp			r10d, eax
	punpcklbw	mm1, mm2				; mm1= XXxx R1xx G1xx B1xx
	
	%IF (%2==1) ;rgb24
    psllq		mm2,8					; Compensate for RGB24
	%ENDIF
	
align 16
.re_enter:
	punpckhbw	mm2, mm0	; mm2= 00XX 00R2 00G2 00B2
	psrlw		mm1, 8		; mm1= 00XX 00R1 00G1 00B1
	jge			.outloop	; Jump out of loop if true (width==0)

	movq		mm6, mm1	; mm6= 00XX 00R1 00G1 00B1
	pmaddwd		mm1, mm7	; mm1= v2v2 v2v2 v1v1 v1v1   y1 //(cyb*rgb[0] + cyg*rgb[1] + cyr*rgb[2] + 0x108000)
	
	%IF(%3==0) ; dupl==false 
	paddw		mm6, mm2	; mm6 = accumulated RGB values (for b_y and r_y) One factional bit more must be shifted.
	%ENDIF
	
	pmaddwd		mm2, mm7	; mm2= w2w2 w2w2 w1w1 w1w1   y2 //(cyb*rgbnext[0] + cyg*rgbnext[1] + cyr*rgbnext[2] + 0x108000)
	paddd		mm1, mm0	; Add rounding fraction (16.5)<<15 to lower dword only
	paddd		mm2, mm0	; Add rounding fraction (16.5)<<15 to lower dword only
	movq		mm3, mm1	
	movq		mm4, mm2
	psrlq		mm3, 32
	pand		mm6, QWORD [rel rb_mask]	; Clear out accumulated G-value mm6= 0000 RRRR 0000 BBBB
	psrlq		mm4, 32
	paddd		mm1, mm3		
	paddd		mm2, mm4
	psrld		mm1,15		; mm1= xxxx xxxx 0000 00y1 final value

	%IF (%4==1)	; matrix<2
	movd		mm3, DWORD[rel sub_32]	; mm3 = -32
	%ENDIF

	psrld		mm2, 15		; mm2= xxxx xxxx 0000 00y2 final value

	%IF (%4==1)	; matrix<2
	paddw		mm3,mm1		; mm3: y1 - 32
	%ELSE 
	movq		mm3,mm1		; mm3: y1
	%ENDIF

	%IF (%3==1)	; dupl==true
	pslld		mm6, 15		; Shift up accumulated R and B values (<<15 in C)
	%ELSE 
	pslld		mm6, 14		; Shift up accumulated R and B values (<<14 in C)
	%ENDIF

	%IF (%3==1)	; dupl==true
	paddw		mm3, mm1	; mm3 = y1+y1-32
	%ELSE 
	paddw		mm3, mm2	; mm3 = y1+y2-32
	%ENDIF

	psllq		mm2, 16		; mm2 Y2 shifted up(to clear fraction) mm2 ready
	pmaddwd		mm3, mm5	; mm3=scaled_y(latency 2 cycles)
	por			mm1, mm2	; mm1 = 0000 0000 00Y2 00Y1
	punpckldq	mm3, mm3	; Move scaled_y to upper dword mm3=SCAL ED_Y SCAL ED_Y
	movq		mm2, QWORD [rbx+32+32]	;indexes into fpix_mul
	psubd		mm6, mm3	; mm6 = b_y and r_y
	movq		mm4, QWORD [rel fpix_add]
	psrad		mm6, 14		; Shift down b_y and r_y(>>10 in C-code)
	movq		mm3,QWORD [rel chroma_mask2]
	pmaddwd		mm6, mm2	; Mult b_y and r_y
	add			r11d,4		; Two pixels(packed)
	paddd		mm6, mm4	; Add 0x808000 to r_y and b_y

	%IF (%2==1) ;rgb24
	add			r10d, 6
	%ELSE
	add			r10d, 8
	%ENDIF

	pand		mm6, mm3				; Clear out fractions
	movq		mm2, QWORD [rcx+r10]	; mm2= XXR2 G2B2 XXR1 G1B1
	packuswb	mm6, mm6				; mm6 = VV00 UU00 VV00 UU00
	cmp			r10d, eax				; cmp rgb to rgb in bytes
	por			mm6, mm1				; Or luma and chroma together
	punpcklbw	mm1,mm2					; mm1= XXxx R1xx G1xx B1xx
	movd		DWORD [rdx+r11-4], mm6	; Store final pixel
	
	%IF (%2==1) ;rgb24
	psllq		mm2,8					; Compensate for RGB24
	%ENDIF	
	jmp			.re_enter				; loop break condition at top


.outloop:
	sub			ecx, r8d
	add			edx, r9d
	dec			esi
	jnz			.yloop

	pop rsi
	pop rbx
		
	emms
	
%endmacro


;=============================================================================
; Macro instantiations
;=============================================================================
SECTION .text
YUV2RGB_PROC mmx_YUY2toRGB24,0,0
ret
ENDPROC_FRAME

YUV2RGB_PROC mmx_YUY2toRGB32,0,1
ret
ENDPROC_FRAME


;convertxxxtoyuy2 ConvertRGB24toYUY2_asm, 1, 0, 0
;convertxxxtoyuy2 ConvertRGB24toYUY2_dup_asm, 1, 1, 0
;convertxxxtoyuy2 ConvertRGB24toYUY2_sub_asm, 1, 0, 1
;convertxxxtoyuy2 ConvertRGB24toYUY2_dup_sub_asm, 1, 1, 1

;convertxxxtoyuy2 ConvertRGB32toYUY2_asm, 0, 0, 0
;convertxxxtoyuy2 ConvertRGB32toYUY2_dup_asm, 0, 1, 0
;convertxxxtoyuy2 ConvertRGB32toYUY2_sub_asm, 0, 0, 1
;convertxxxtoyuy2 ConvertRGB32toYUY2_dup_sub_asm, 0, 1, 1




