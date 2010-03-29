// Avisynth v1.0 beta.  Copyright 2000 Ben Rudiak-Gould.
// http://www.math.berkeley.edu/~benrg/avisynth.html

//	VirtualDub - Video processing and capture application
//	Copyright (C) 1998-2000 Avery Lee
//
//	This program is free software; you can redistribute it and/or modify
//	it under the terms of the GNU General Public License as published by
//	the Free Software Foundation; either version 2 of the License, or
//	(at your option) any later version.
//
//	This program is distributed in the hope that it will be useful,
//	but WITHOUT ANY WARRANTY; without even the implied warranty of
//	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//	GNU General Public License for more details.
//
//	You should have received a copy of the GNU General Public License
//	along with this program; if not, write to the Free Software
//	Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

#include "../../stdafx.h"

#include <excpt.h>

static long g_lCPUExtensionsEnabled;
static long g_lCPUExtensionsAvailable;

#define CPUF_SUPPORTS_CPUID			(0x00000001L)
#define CPUF_SUPPORTS_FPU			(0x00000002L)
#define CPUF_SUPPORTS_MMX			(0x00000004L)
#define CPUF_SUPPORTS_INTEGER_SSE	(0x00000008L)
#define CPUF_SUPPORTS_SSE			(0x00000010L)
#define CPUF_SUPPORTS_SSE2			(0x00000020L)
#define CPUF_SUPPORTS_3DNOW			(0x00000040L)
#define CPUF_SUPPORTS_3DNOW_EXT		(0x00000080L)
#define CPUF_SUPPORTS_SSE3			(0x00000100L)
#define CPUF_SUPPORTS_SSSE3			(0x00000200L)
#define CPUF_SUPPORTS_SSE41			(0x00000400L)
#define CPUF_SUPPORTS_MASK			(0x000007FFL)

#ifdef _AMD64_

	//Fucntion is straight from MSDN example, also used in VDub64
	long CPUCheckForExtensions() {
		long flags = CPUF_SUPPORTS_FPU;

		// check for SSE3, SSSE3, SSE4.1
		int cpuInfo[4];
		__cpuid(cpuInfo, 1);

		//we know off the bat what min features we have
		flags |= CPUF_SUPPORTS_MMX | CPUF_SUPPORTS_SSE | CPUF_SUPPORTS_INTEGER_SSE | CPUF_SUPPORTS_SSE2; 

		if (cpuInfo[2] & 0x00000001)
			flags |= CPUF_SUPPORTS_SSE3;

		if (cpuInfo[2] & 0x00000200)
			flags |= CPUF_SUPPORTS_SSSE3;

		if (cpuInfo[2] & 0x00080000)
			flags |= CPUF_SUPPORTS_SSE41;

		// check for 3DNow!, 3DNow! extensions
		__cpuid(cpuInfo, 0x80000000);
		if (cpuInfo[0] >= 0x80000001) {
			__cpuid(cpuInfo, 0x80000001);

			if (cpuInfo[3] & (1 << 31))
				flags |= CPUF_SUPPORTS_3DNOW;

			if (cpuInfo[3] & (1 << 30))
				flags |= CPUF_SUPPORTS_3DNOW_EXT;

			if (cpuInfo[3] & (1 << 22))
				flags |= CPUF_SUPPORTS_INTEGER_SSE;
		}

		return flags;
	}

#else

// This is ridiculous.

static long CPUCheckForSSESupport() {
	__try {
//		__asm andps xmm0,xmm0

		__asm _emit 0x0f
		__asm _emit 0x54
		__asm _emit 0xc0

	} __except(EXCEPTION_EXECUTE_HANDLER) {
		if (GetExceptionCode() == 0xC000001Du) // illegal instruction
			g_lCPUExtensionsAvailable &= ~(CPUF_SUPPORTS_SSE|CPUF_SUPPORTS_SSE2);
	}

	return g_lCPUExtensionsAvailable;
}

long __declspec(naked) CPUCheckForExtensions() {
	__asm {
		push	ebp
		push	edi
		push	esi
		push	ebx

		xor		ebp,ebp			//cpu flags - if we don't have CPUID, we probably
								//won't want to try FPU optimizations.

		//check for CPUID.

		pushfd					//flags -> EAX
		pop		eax
		or		eax,00200000h	//set the ID bit
		push	eax				//EAX -> flags
		popfd
		pushfd					//flags -> EAX
		pop		eax
		and		eax,00200000h	//ID bit set?
		jz		done			//nope...

		//CPUID exists, check for features register.

		mov		ebp,00000003h
		xor		eax,eax
		cpuid
		or		eax,eax
		jz		done			//no features register?!?

		//features register exists, look for MMX, SSE, SSE2.

		mov		eax,1
		cpuid
		mov		ebx,edx
		and		ebx,00800000h	//MMX is bit 23
		shr		ebx,21
		or		ebp,ebx			//set bit 2 if MMX exists

		mov		ebx,edx
		and		ebx,02000000h	//SSE is bit 25
		shr		ebx,25
		neg		ebx
		and		ebx,00000018h	//set bits 3 and 4 if SSE exists
		or		ebp,ebx

		mov		ebx,edx
		and		ebx,04000000h	//SSE2 is bit 26
		shr		ebx,21
		or		ebp,ebx			//set bit 5

		//look for SSE3, SSSE3, SSE4.1 , SSE4.2

		mov		ebx,ecx
		and		ebx,00000001h	//SSE3 is bit 0
		shl		ebx,8
		or		ebp,ebx			//set bit 8

		mov		ebx,ecx
		and		ebx,00000200h	//SSSE3 is bit 9
//		sh?		ebx,0
		or		ebp,ebx			//set bit 9

		mov		ebx,ecx
		and		ebx,00080000h	//SSE4.1 is bit 19
		shr		ebx,9
		or		ebp,ebx			//set bit 10

		mov		ebx,ecx
		and		ebx,00100000h	//SSE4.2 is bit 20
		shr		ebx,9
		or		ebp,ebx			//set bit 11

		//check for vendor feature register (K6/Athlon).

		mov		eax,80000000h
		cpuid
		mov		ecx,80000001h
		cmp		eax,ecx
		jb		done

		//vendor feature register exists, look for 3DNow! and Athlon extensions

		mov		eax,ecx
		cpuid

		mov		eax,edx
		and		edx,80000000h	//3DNow! is bit 31
		shr		edx,25
		or		ebp,edx			//set bit 6

		mov		edx,eax
		and		eax,40000000h	//3DNow!2 is bit 30
		shr		eax,23
		or		ebp,eax			//set bit 7

		and		edx,00400000h	//AMD MMX extensions (integer SSE) is bit 22
		shr		edx,19
		or		ebp,edx			//set bit 3

done:
		mov		eax,ebp
		mov		g_lCPUExtensionsAvailable, ebp

		//Full SSE and SSE-2 require OS support for the xmm* registers.

		test	eax,00000030h
		jz		nocheck
		call	CPUCheckForSSESupport
nocheck:
		pop		ebx
		pop		esi
		pop		edi
		pop		ebp
		ret
	}
}

#endif
