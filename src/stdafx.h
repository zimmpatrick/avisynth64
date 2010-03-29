#pragma once

// Modify the following definitions if you need to target a platform prior to the ones specified below.
// Refer to MSDN for the latest info on corresponding values for different platforms.
#ifndef WINVER              // Allow use of features specific to Windows 7 or later.
#define WINVER 0x0601       // Change this to the appropriate value to target other versions of Windows.
#endif

#ifndef _WIN32_WINNT        // Allow use of features specific to Windows 7 or later.
#define _WIN32_WINNT 0x0601 // Change this to the appropriate value to target other versions of Windows.
#endif

#ifndef __Stdafx_H__
#define __Stdafx_H__

//C
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <malloc.h>
#include <string.h>
#include <io.h>
#include <ctype.h>
#include <wtypes.h>

//windows
#define WIN32_LEAN_AND_MEAN
#include <objbase.h>
#include <BaseTsd.h>
#include <vfw.h>
#include <windows.h>
#include <mmsystem.h>
#include <msacm.h>

//STL
#include <vector>
#include <algorithm>

// fast synchronization
#if (_MSC_VER >= 1400)
#include <intrin.h>
#define InterlockedIncrement _InterlockedIncrement
#define InterlockedDecrement _InterlockedDecrement
#define InterlockedExchange _InterlockedExchange
#undef InterlockedExchangePointer
#define InterlockedExchangePointer(a,b) (void*)_InterlockedExchange((volatile long*)(a), (long)(b))
#define InterlockedExchangeAdd _InterlockedExchangeAdd
#define InterlockedCompareExchange _InterlockedCompareExchange
#endif

#endif // __Stdafx_H__
