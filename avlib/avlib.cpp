// This is the main DLL file.

#include "stdafx.h"

#include "avlib.h"


#ifndef _AMD64_
void BitBlt(BYTE* dstp, int dst_pitch, const BYTE* srcp, int src_pitch, int row_size, int height) {
  if ( (!height)|| (!row_size)) return;
  if (GetCPUFlags() & CPUF_INTEGER_SSE) {
    if (height == 1 || (src_pitch == dst_pitch && dst_pitch == row_size)) {
      memcpy_amd(dstp, srcp, row_size*height);
    } else {
      asm_BitBlt_ISSE(dstp,dst_pitch,srcp,src_pitch,row_size,height);
    }
    return;
  }
  if (height == 1 || (dst_pitch == src_pitch && src_pitch == row_size)) {
    memcpy(dstp, srcp, row_size*height);
  } else {
    for (int y=height; y>0; --y) {
      memcpy(dstp, srcp, row_size);
      dstp += dst_pitch;
      srcp += src_pitch;
    }
  }
}
#else
//extern "C" void BitBlt(BYTE* dstp, int dst_pitch, const BYTE* srcp, int src_pitch, int row_size, int height);
extern "C" void asm_BitBlt_u(BYTE* dstp, int dst_pitch, const BYTE* srcp, int src_pitch, int row_size, int height);
extern "C" void asm_BitBlt_a(BYTE* dstp, int dst_pitch, const BYTE* srcp, int src_pitch, int row_size, int height);

void BitBlt(BYTE* dstp, int dst_pitch, const BYTE* srcp, int src_pitch, int row_size, int height) {
/*	
	if (GetCPUFlags() & CPUF_SSE4)
		asm_BitBlt_SSE4(dstp, dst_pitch, srcp, src_pitch, row_size, height);
	else
		asm_BitBlt_SSE2(dstp, dst_pitch, srcp, src_pitch, row_size, height);
*/
	if ( (!height)|| (!row_size)) return;
	
	if (height == 1 || (src_pitch == dst_pitch && dst_pitch == row_size))
		memcpy(dstp, srcp, row_size*height);
	else
	{
		
		for (int y=height; y>0; --y, dstp += dst_pitch, srcp += src_pitch)
		{
			memcpy(dstp, srcp, row_size);
		}
		/*
		bool source_ua = (((INT_PTR)srcp&15) || (src_pitch & 15));
		bool dest_ua = (((INT_PTR)dstp&15) || (dst_pitch & 15));
	
		if (source_ua || dest_ua) 
			asm_BitBlt_u(dstp, dst_pitch, srcp, src_pitch, row_size, height);
		else 
			asm_BitBlt_a(dstp, dst_pitch, srcp, src_pitch, row_size, height);
		*/
	}
}


#endif

  /*****************************
  * Assembler bitblit by Steady
   *****************************/

#ifndef _AMD64_
void asm_BitBlt_ISSE(BYTE* dstp, int dst_pitch, const BYTE* srcp, int src_pitch, int row_size, int height) 
{

	// Warning! : If you modify this routine, check the generated assembler to make sure
	//            the stupid compiler is saving the ebx register in the entry prologue.
	//            And don't just add an extra push/pop ebx pair around the code, try to
	//            convince the compiler to do the right thing, it's not hard, usually a
	//            slight shuffle or a well placed "__asm mov ebx,ebx" does the trick.

	if(row_size==0 || height==0) return; //abort on goofs
	//move backwards for easier looping and to disable hardware prefetch
	const BYTE* srcStart=srcp+src_pitch*(height-1);
	BYTE* dstStart=dstp+dst_pitch*(height-1);

	if(row_size < 64) 
	{
		_asm 
		{
			mov		esi,srcStart  //move rows from bottom up
			mov		edi,dstStart
			mov		edx,row_size
			dec		edx
			mov		ebx,height
			align 16
		memoptS_rowloop:
			mov		ecx,edx
			//rep	movsb
		memoptS_byteloop:
			mov		AL,[esi+ecx]
			mov		[edi+ecx],AL
			sub		ecx,1
			jnc		memoptS_byteloop
			sub		esi,src_pitch
			sub		edi,dst_pitch
			dec		ebx
			jne		memoptS_rowloop
		};
		return;
	}//end small version

	else if( (int(dstp) | row_size | src_pitch | dst_pitch) & 7) 
	{
		//not QW aligned
		//unaligned version makes no assumptions on alignment

		_asm 
		{
			//****** initialize
			mov		esi,srcStart  //bottom row
			mov		AL,[esi]
			mov		edi,dstStart
			mov		edx,row_size
			mov		ebx,height

			//********** loop starts here ***********

			align 16
		memoptU_rowloop:
			mov		ecx,edx     //row_size
			dec		ecx         //offset to last byte in row
			add		ecx,esi     //ecx= ptr last byte in row
			and		ecx,~63     //align to first byte in cache line
		memoptU_prefetchloop:
			mov		AX,[ecx]    //tried AL,AX,EAX, AX a tiny bit faster
			sub		ecx,64
			cmp		ecx,esi
			jae		memoptU_prefetchloop

			//************ write *************

			movq    mm6,[esi]     //move the first unaligned bytes
			movntq  [edi],mm6

			//************************
			mov		eax,edi
			neg		eax
			mov		ecx,eax
			and		eax,63      //eax=bytes from [edi] to start of next 64 byte cache line
			and		ecx,7       //ecx=bytes from [edi] to next QW
			align 16
		memoptU_prewrite8loop:        //write out odd QW's so 64 bit write is cache line aligned
			cmp		ecx,eax           //start of cache line ?
			jz		memoptU_pre8done  //if not, write single QW
			movq    mm7,[esi+ecx]
			movntq  [edi+ecx],mm7
			add		ecx,8
			jmp		memoptU_prewrite8loop

			align 16
		memoptU_write64loop:
			movntq	[edi+ecx-64],mm0
			movntq  [edi+ecx-56],mm1
			movntq  [edi+ecx-48],mm2
			movntq  [edi+ecx-40],mm3
			movntq  [edi+ecx-32],mm4
			movntq  [edi+ecx-24],mm5
			movntq  [edi+ecx-16],mm6
			movntq  [edi+ecx- 8],mm7
		memoptU_pre8done:
			add		ecx,64
			cmp		ecx,edx         //while(offset <= row_size) do {...
			ja		memoptU_done64
			movq    mm0,[esi+ecx-64]
			movq    mm1,[esi+ecx-56]
			movq    mm2,[esi+ecx-48]
			movq    mm3,[esi+ecx-40]
			movq    mm4,[esi+ecx-32]
			movq    mm5,[esi+ecx-24]
			movq    mm6,[esi+ecx-16]
			movq    mm7,[esi+ecx- 8]
			jmp		memoptU_write64loop
		memoptU_done64:

			sub     ecx,64    //went to far
			align 16
		memoptU_write8loop:
			add     ecx,8           //next QW
			cmp     ecx,edx         //any QW's left in row ?
			ja      memoptU_done8
			movq    mm0,[esi+ecx-8]
			movntq  [edi+ecx-8],mm0
			jmp		memoptU_write8loop
		memoptU_done8:

			movq	mm1,[esi+edx-8] //write the last unaligned bytes
			movntq  [edi+edx-8],mm1
			sub		esi,src_pitch
			sub		edi,dst_pitch
			dec		ebx               //row counter (=height at start)
			jne		memoptU_rowloop

			sfence
			emms
		};
		return;
	}//end unaligned version

	else 
	{
		//QW aligned version (fastest)
		//else dstp and row_size QW aligned - hope for the best from srcp
		//QW aligned version should generally be true when copying full rows
		_asm 
		{
			mov		esi,srcStart  //start of bottom row
			mov		edi,dstStart
			mov		ebx,height
			mov		edx,row_size
			align 16
		memoptA_rowloop:
			mov		ecx,edx //row_size
			dec		ecx     //offset to last byte in row

			//********forward routine
			add		ecx,esi
			and		ecx,~63   //align prefetch to first byte in cache line(~3-4% faster)
			align 16
		memoptA_prefetchloop:
			mov		AX,[ecx]
			sub		ecx,64
			cmp		ecx,esi
			jae		memoptA_prefetchloop

			mov		eax,edi
			xor		ecx,ecx
			neg		eax
			and		eax,63            //eax=bytes from edi to start of cache line
			align 16
		memoptA_prewrite8loop:        //write out odd QW's so 64bit write is cache line aligned
			cmp		ecx,eax           //start of cache line ?
			jz		memoptA_pre8done  //if not, write single QW
			movq	mm7,[esi+ecx]
			movntq  [edi+ecx],mm7
			add		ecx,8
			jmp		memoptA_prewrite8loop

			align 16
		memoptA_write64loop:
			movntq  [edi+ecx-64],mm0
			movntq  [edi+ecx-56],mm1
			movntq  [edi+ecx-48],mm2
			movntq  [edi+ecx-40],mm3
			movntq  [edi+ecx-32],mm4
			movntq  [edi+ecx-24],mm5
			movntq  [edi+ecx-16],mm6
			movntq  [edi+ecx- 8],mm7
		memoptA_pre8done:
			add		ecx,64
			cmp		ecx,edx
			ja		memoptA_done64    //less than 64 bytes left
			movq    mm0,[esi+ecx-64]
			movq    mm1,[esi+ecx-56]
			movq    mm2,[esi+ecx-48]
			movq    mm3,[esi+ecx-40]
			movq    mm4,[esi+ecx-32]
			movq    mm5,[esi+ecx-24]
			movq    mm6,[esi+ecx-16]
			movq    mm7,[esi+ecx- 8]
			jmp		memoptA_write64loop

		memoptA_done64:
			sub		ecx,64

			align 16
		memoptA_write8loop:           //less than 8 QW's left
			add		ecx,8
			cmp		ecx,edx
			ja		memoptA_done8     //no QW's left
			movq    mm7,[esi+ecx-8]
			movntq  [edi+ecx-8],mm7
			jmp		memoptA_write8loop

		memoptA_done8:
			sub		esi,src_pitch
			sub		edi,dst_pitch
			dec		ebx               //row counter (height)
			jne		memoptA_rowloop

			sfence
			emms
		};
		return;
	}//end aligned version
}//end BitBlt_memopt()
#else
void asm_BitBlt_ISSE(BYTE* dstp, int dst_pitch, const BYTE* srcp, int src_pitch, int row_size, int height) 
{

	// Warning! : If you modify this routine, check the generated assembler to make sure
	//            the stupid compiler is saving the ebx register in the entry prologue.
	//            And don't just add an extra push/pop ebx pair around the code, try to
	//            convince the compiler to do the right thing, it's not hard, usually a
	//            slight shuffle or a well placed "__asm mov ebx,ebx" does the trick.

	//move backwards for easier looping and to disable hardware prefetch
	const BYTE* srcStart=srcp+src_pitch*(height-1);
	BYTE* dstStart=dstp+dst_pitch*(height-1);

	if(row_size < 64) 
	{
		_asm 
		{
			mov		rsi,srcStart  //move rows from bottom up
			mov		rdi,dstStart
			mov		edx,row_size
			dec		edx
			mov		ebx,height
		align 16
		memoptS_rowloop:
			mov		ecx,edx
			//rep	movsb
		memoptS_byteloop:
			mov		AL,[rsi+rcx]
			mov		[rdi+rcx],AL
			sub		ecx,1
			jnc		memoptS_byteloop
			sub		esi,src_pitch
			sub		edi,dst_pitch
			dec		ebx
			jne		memoptS_rowloop
		};
		return;
	}//end small version

	else if( ((INT_PTR)dstp | (INT_PTR)srcp | row_size | src_pitch | dst_pitch) & 15) 
	{
		//not QW aligned
		//unaligned version makes no assumptions on alignment

		_asm 
		{
			//****** initialize
			mov		rsi,srcStart  //bottom row
			mov		AL,[rsi]
			mov		rdi,dstStart
			mov		edx,row_size
			mov		ebx,height

			//********** loop starts here ***********

			align 16
		memoptU_rowloop:
			mov		ecx,edx     //row_size
			dec		ecx         //offset to last byte in row
			add		ecx,esi     //ecx= ptr last byte in row
			and		ecx,~64     //align to first byte in cache line
		memoptU_prefetchloop:
			mov		AX,[rcx]    //tried AL,AX,EAX, AX a tiny bit faster
			sub		ecx,64
			cmp		ecx,esi
			jae		memoptU_prefetchloop

			//************ write *************

			movdqu    xmm6,[rsi]     //move the first unaligned bytes
			movntdq  [rdi], xmm6

			//************************
			mov		eax,edi
			neg		eax
			mov		ecx,eax
			and		eax,127      //eax=bytes from [edi] to start of next 64 byte cache line
			and		ecx,15       //ecx=bytes from [edi] to next DQW
			align 16
		memoptU_prewrite16loop:        //write out odd QW's so 64 bit write is cache line aligned
			cmp		ecx,eax           //start of cache line ?
			jz		memoptU_pre16done  //if not, write single QW
			movdqu   xmm7,[rsi+rcx]
			movntdq [rdi+rcx],xmm7
			add		ecx,16
			jmp		memoptU_prewrite16loop

			align 16
		memoptU_write128loop:
			movntdq	 [rdi+rcx-128],xmm0
			movntdq  [rdi+rcx-112],xmm1
			movntdq  [rdi+rcx- 96],xmm2
			movntdq  [rdi+rcx- 80],xmm3
			movntdq  [rdi+rcx- 64],xmm4
			movntdq  [rdi+rcx- 48],xmm5
			movntdq  [rdi+rcx- 32],xmm6
			movntdq  [rdi+rcx- 16],xmm7
		memoptU_pre16done:
			add		ecx,128
			cmp		ecx,edx         //while(offset <= row_size) do {...
			ja		memoptU_done128
			movdqu    xmm0,[rsi+rcx-128]
			movdqu    xmm1,[rsi+rcx-112]
			movdqu    xmm2,[rsi+rcx- 96]
			movdqu    xmm3,[rsi+rcx- 80]
			movdqu    xmm4,[rsi+rcx- 64]
			movdqu    xmm5,[rsi+rcx- 48]
			movdqu    xmm6,[rsi+rcx- 32]
			movdqu    xmm7,[rsi+rcx- 16]
			jmp		memoptU_write128loop
		memoptU_done128:

			sub     ecx,128    //went too far
			align 16
		memoptU_write16loop:
			add     ecx,16           //next QW
			cmp     ecx,edx         //any QW's left in row ?
			ja      memoptU_done16
			movdqu    xmm0,[rsi+rcx-16]
			movntdq  [rdi+rcx-16],xmm0
			jmp		memoptU_write16loop
		memoptU_done16:

			movdqu	xmm1,[rsi+rdx-16] //write the last unaligned bytes
			movntdq [rdi+rdx-16],xmm1
			sub		esi,src_pitch
			sub		edi,dst_pitch
			dec		ebx               //row counter (=height at start)
			jne		memoptU_rowloop

			sfence
			emms
		};
		return;
	}//end unaligned version

	else 
	{
		//QW aligned version (fastest)
		//else dstp and row_size QW aligned - hope for the best from srcp
		//QW aligned version should generally be true when copying full rows
		_asm 
		{
			mov		rsi,srcStart  //start of bottom row
			mov		rdi,dstStart
			mov		ebx,height
			mov		edx,row_size
			align 16
		memoptA_rowloop:
			mov		ecx,edx //row_size
			dec		ecx     //offset to last byte in row

			//********forward routine
			add		ecx,esi
			and		ecx,~127   //align prefetch to first byte in cache line(~3-4% faster)
			align 16
		memoptA_prefetchloop:
			mov		AX,[rcx]
			sub		ecx,128
			cmp		ecx,esi
			jae		memoptA_prefetchloop

			mov		eax,edi
			xor		ecx,ecx
			neg		eax
			and		eax,127            //eax=bytes from edi to start of cache line
			align 16
		memoptA_prewrite16loop:        //write out odd QW's so 64bit write is cache line aligned
			cmp		ecx,eax           //start of cache line ?
			jz		memoptA_pre16done  //if not, write single QW
			movdqa	xmm7,[rsi+rcx]
			movntdq  [rdi+rcx],xmm7
			add		ecx,16
			jmp		memoptA_prewrite16loop

			align 16
		memoptA_write128loop:
			movntdq	 [rdi+rcx-128],xmm0
			movntdq  [rdi+rcx-112],xmm1
			movntdq  [rdi+rcx- 96],xmm2
			movntdq  [rdi+rcx- 80],xmm3
			movntdq  [rdi+rcx- 64],xmm4
			movntdq  [rdi+rcx- 48],xmm5
			movntdq  [rdi+rcx- 32],xmm6
			movntdq  [rdi+rcx- 16],xmm7
		memoptA_pre16done:
			add		ecx,128
			cmp		ecx,edx
			ja		memoptA_done128    //less than 64 bytes left
			movdqa    xmm0,[rsi+rcx-128]
			movdqa    xmm1,[rsi+rcx-112]
			movdqa    xmm2,[rsi+rcx- 96]
			movdqa    xmm3,[rsi+rcx- 80]
			movdqa    xmm4,[rsi+rcx- 64]
			movdqa    xmm5,[rsi+rcx- 48]
			movdqa    xmm6,[rsi+rcx- 32]
			movdqa    xmm7,[rsi+rcx- 16]
			jmp		memoptA_write128loop

		memoptA_done128:
			sub		ecx,128

			align 16
		memoptA_write16loop:           //less than 8 QW's left
			add		ecx,16
			cmp		ecx,edx
			ja		memoptA_done16     //no QW's left
			movdqa    xmm7,[rsi+rcx-16]
			movntdq  [rdi+rcx-16],xmm7
			jmp		memoptA_write16loop

		memoptA_done16:
			sub		esi,src_pitch
			sub		edi,dst_pitch
			dec		ebx               //row counter (height)
			jne		memoptA_rowloop

			sfence
			emms
		};
		return;
	}//end aligned version
}//end BitBlt_memopt()
#endif
