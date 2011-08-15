// avlib.h

#pragma once


/* Define all types necessary for interfacing with avisynth.dll
   Moved from internal.h */

// Win32 API macros, notably the types BYTE, DWORD, ULONG, etc.
#include <windef.h>

#if (_MSC_VER >= 1400)
extern "C" LONG __cdecl _InterlockedIncrement(LONG volatile * pn);
extern "C" LONG __cdecl _InterlockedDecrement(LONG volatile * pn);
#pragma intrinsic(_InterlockedIncrement)
#pragma intrinsic(_InterlockedDecrement)
#define InterlockedIncrement _InterlockedIncrement
#define InterlockedDecrement _InterlockedDecrement
#endif

// COM interface macros
#include <objbase.h>

void BitBlt(BYTE* dstp, int dst_pitch, const BYTE* srcp, int src_pitch, int row_size, int height);

void asm_BitBlt_ISSE(BYTE* dstp, int dst_pitch, const BYTE* srcp, int src_pitch, int row_size, int height);
void asm_BitBlt_MMX(BYTE* dstp, int dst_pitch, const BYTE* srcp, int src_pitch, int row_size, int height);
