// Avisynth v2.5.  Copyright 2002 Ben Rudiak-Gould et al.
// http://www.avisynth.org

// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA, or visit
// http://www.gnu.org/copyleft/gpl.html .
//
// Linking Avisynth statically or dynamically with other modules is making a
// combined work based on Avisynth.  Thus, the terms and conditions of the GNU
// General Public License cover the whole combination.
//
// As a special exception, the copyright holders of Avisynth give you
// permission to link Avisynth with independent modules that communicate with
// Avisynth solely through the interfaces defined in avisynth.h, regardless of the license
// terms of these independent modules, and to copy and distribute the
// resulting combined work under terms of your choice, provided that
// every copy of the combined work is accompanied by a complete copy of
// the source code of Avisynth (the version of Avisynth used to produce the
// combined work), being distributed under the terms of the GNU General
// Public License plus this exception.  An independent module is a module
// which is not derived from or based on Avisynth, such as 3rd-party filters,
// import and export plugins, or graphical user interfaces.

#ifndef __Resample_H__
#define __Resample_H__

#include "../../internal.h"
#include "resample_functions.h"
#include "transform.h"

#ifndef _AMD64_
#include "../../core/softwire_helpers.h"
#endif 


#ifndef _AMD64_
class FilteredResizeH : public GenericVideoFilter, public  CodeGenerator
/**
  * Class to resize in the horizontal direction using a specified sampling filter
  * Helper for resample functions
 **/
{
public:
  FilteredResizeH( PClip _child, double subrange_left, double subrange_width, int target_width, 
                   ResamplingFunction* func, IScriptEnvironment* env );
  virtual ~FilteredResizeH(void);
  PVideoFrame __stdcall GetFrame(int n, IScriptEnvironment* env);
  DynamicAssembledCode GenerateResizer(int gen_plane, IScriptEnvironment* env);
private:

  DynamicAssembledCode assemblerY;
  DynamicAssembledCode assemblerUV;

  int* /*const*/ pattern_luma;
  int* /*const*/ pattern_chroma;
  int original_width;
  bool use_dynamic_code;

  BYTE *tempY, *tempUV;
// These must be properly set when running the filter:
  BYTE *gen_srcp;
  BYTE *gen_dstp;
  int gen_src_pitch, gen_dst_pitch;
// These are used by the filter:
  int gen_h, gen_x;
  BYTE* gen_temp_destp;
};
#else

typedef void(FRH_yv12)(const BYTE* srcp, BYTE* dstp, int src_pitch, int dst_pitch, int dst_height, int dst_width, int orig_width, int* pattern_array);
extern "C"{

FRH_yv12 FRH_yv12_aligned_FIR1;
FRH_yv12 FRH_yv12_aligned_FIR2;
FRH_yv12 FRH_yv12_aligned_FIR3;
FRH_yv12 FRH_yv12_aligned_FIR4;
FRH_yv12 FRH_yv12_aligned_FIR5;
FRH_yv12 FRH_yv12_aligned_FIR6;
FRH_yv12 FRH_yv12_aligned_FIR7;
FRH_yv12 FRH_yv12_aligned_FIR8;
FRH_yv12 FRH_yv12_aligned_FIR9;
FRH_yv12 FRH_yv12_aligned_FIR10;
FRH_yv12 FRH_yv12_aligned_FIR11;
FRH_yv12 FRH_yv12_aligned_FIR12;
FRH_yv12 FRH_yv12_aligned_FIR13;
FRH_yv12 FRH_yv12_aligned_FIR14;
FRH_yv12 FRH_yv12_aligned_FIR15;
FRH_yv12 FRH_yv12_aligned_FIR16;

FRH_yv12 FRH_yv12_unaligned_FIR1;
FRH_yv12 FRH_yv12_unaligned_FIR2;
FRH_yv12 FRH_yv12_unaligned_FIR3;
FRH_yv12 FRH_yv12_unaligned_FIR4;
FRH_yv12 FRH_yv12_unaligned_FIR5;
FRH_yv12 FRH_yv12_unaligned_FIR6;
FRH_yv12 FRH_yv12_unaligned_FIR7;
FRH_yv12 FRH_yv12_unaligned_FIR8;
FRH_yv12 FRH_yv12_unaligned_FIR9;
FRH_yv12 FRH_yv12_unaligned_FIR10;
FRH_yv12 FRH_yv12_unaligned_FIR11;
FRH_yv12 FRH_yv12_unaligned_FIR12;
FRH_yv12 FRH_yv12_unaligned_FIR13;
FRH_yv12 FRH_yv12_unaligned_FIR14;
FRH_yv12 FRH_yv12_unaligned_FIR15;
FRH_yv12 FRH_yv12_unaligned_FIR16;

void FRH_yv12_aligned_mmx(const BYTE* srcp, BYTE* dstp, int src_pitch, int dst_pitch, int dst_height, int dst_width, int orig_width, int* pattern_array);
void FRH_yv12_unaligned_mmx(const BYTE* srcp, BYTE* dstp, int src_pitch, int dst_pitch, int dst_height, int dst_width, int orig_width, int* pattern_array);

void FRH_yuy2_aligned_mmx(const BYTE* srcp, BYTE* dstp, int src_pitch, int dst_pitch, int dst_height, int dst_width, int orig_width, int* pattern_luma, int* patter_chroma);
void FRH_yuy2_unaligned_mmx(const BYTE* srcp, BYTE* dstp, int src_pitch, int dst_pitch, int dst_height, int dst_width, int orig_width, int* pattern_luma, int* patter_chroma);

void FRH_rgb24_mmx(const BYTE* srcp, BYTE* dstp, int src_pitch, int dst_pitch, int dst_height, int dst_width, int* pattern_luma);
void FRH_rgb32_mmx(const BYTE* srcp, BYTE* dstp, int src_pitch, int dst_pitch, int dst_height, int dst_width, int* pattern_luma);}

class FilteredResizeH : public GenericVideoFilter
/**
  * Class to resize in the horizontal direction using a specified sampling filter
  * Helper for resample functions
 **/
{
public:
  FilteredResizeH( PClip _child, double subrange_left, double subrange_width, int target_width, 
                   ResamplingFunction* func, IScriptEnvironment* env );
  virtual ~FilteredResizeH(void);
  PVideoFrame __stdcall GetFrame(int n, IScriptEnvironment* env);
private:

  int* /*const*/ pattern_luma;
  int* /*const*/ pattern_chroma;
  int original_width;
  bool use_dynamic_code;

  //tailored resize functions
  FRH_yv12 *yv12_aligned;
  FRH_yv12 *yv12_unaligned;


  BYTE *tempY, *tempUV;
// These must be properly set when running the filter:
  BYTE *gen_srcp;
  BYTE *gen_dstp;
  int gen_src_pitch, gen_dst_pitch;
// These are used by the filter:
  int gen_h, gen_x;
  BYTE* gen_temp_destp;
};
#endif

//Vertical resizers written in assembly
typedef void(FRV_asm)(const BYTE *srcp, BYTE *dstp, int src_pitch, int dst_pitch, int yloops, int xloops, int *yOfs, int *cur);
extern "C" {
//SSE2 FIR
FRV_asm FRV_aligned_SSE2_FIR1;
FRV_asm FRV_aligned_SSE2_FIR13;
FRV_asm FRV_aligned_SSE2_FIR14;
FRV_asm FRV_aligned_SSE2_FIR15;
FRV_asm FRV_aligned_SSE2_FIR16;
FRV_asm FRV_aligned_SSE2_FIR17;
FRV_asm FRV_aligned_SSE2_FIR18;
FRV_asm FRV_aligned_SSE2_FIR19;
FRV_asm FRV_aligned_SSE2_FIR20;
FRV_asm FRV_aligned_SSE2_FIR21;
FRV_asm FRV_aligned_SSE2_FIR22;
FRV_asm FRV_aligned_SSE2_FIR23;
FRV_asm FRV_aligned_SSE2_FIR24;


FRV_asm FRV_unaligned_SSE2_FIR1;
FRV_asm FRV_unaligned_SSE2_FIR13;
FRV_asm FRV_unaligned_SSE2_FIR14;
FRV_asm FRV_unaligned_SSE2_FIR15;
FRV_asm FRV_unaligned_SSE2_FIR16;
FRV_asm FRV_unaligned_SSE2_FIR17;
FRV_asm FRV_unaligned_SSE2_FIR18;
FRV_asm FRV_unaligned_SSE2_FIR19;
FRV_asm FRV_unaligned_SSE2_FIR20;
FRV_asm FRV_unaligned_SSE2_FIR21;
FRV_asm FRV_unaligned_SSE2_FIR22;
FRV_asm FRV_unaligned_SSE2_FIR23;
FRV_asm FRV_unaligned_SSE2_FIR24;

//SSE3 FIR
FRV_asm FRV_aligned_SSE3_FIR2;
FRV_asm FRV_aligned_SSE3_FIR3;
FRV_asm FRV_aligned_SSE3_FIR4;
FRV_asm FRV_aligned_SSE3_FIR5;
FRV_asm FRV_aligned_SSE3_FIR6;
FRV_asm FRV_aligned_SSE3_FIR7;
FRV_asm FRV_aligned_SSE3_FIR8;
FRV_asm FRV_aligned_SSE3_FIR9;
FRV_asm FRV_aligned_SSE3_FIR10;
FRV_asm FRV_aligned_SSE3_FIR11;
FRV_asm FRV_aligned_SSE3_FIR12;

FRV_asm FRV_unaligned_SSE3_FIR2;
FRV_asm FRV_unaligned_SSE3_FIR3;
FRV_asm FRV_unaligned_SSE3_FIR4;
FRV_asm FRV_unaligned_SSE3_FIR5;
FRV_asm FRV_unaligned_SSE3_FIR6;
FRV_asm FRV_unaligned_SSE3_FIR7;
FRV_asm FRV_unaligned_SSE3_FIR8;
FRV_asm FRV_unaligned_SSE3_FIR9;
FRV_asm FRV_unaligned_SSE3_FIR10;
FRV_asm FRV_unaligned_SSE3_FIR11;
FRV_asm FRV_unaligned_SSE3_FIR12;

//SSSE3 FIR
FRV_asm FRV_aligned_SSSE3_FIR2;
FRV_asm FRV_aligned_SSSE3_FIR3;
FRV_asm FRV_aligned_SSSE3_FIR4;
FRV_asm FRV_aligned_SSSE3_FIR5;
FRV_asm FRV_aligned_SSSE3_FIR6;
FRV_asm FRV_aligned_SSSE3_FIR7;
FRV_asm FRV_aligned_SSSE3_FIR8;
FRV_asm FRV_aligned_SSSE3_FIR9;
FRV_asm FRV_aligned_SSSE3_FIR10;
FRV_asm FRV_aligned_SSSE3_FIR11;
FRV_asm FRV_aligned_SSSE3_FIR12;

FRV_asm FRV_unaligned_SSSE3_FIR2;
FRV_asm FRV_unaligned_SSSE3_FIR3;
FRV_asm FRV_unaligned_SSSE3_FIR4;
FRV_asm FRV_unaligned_SSSE3_FIR5;
FRV_asm FRV_unaligned_SSSE3_FIR6;
FRV_asm FRV_unaligned_SSSE3_FIR7;
FRV_asm FRV_unaligned_SSSE3_FIR8;
FRV_asm FRV_unaligned_SSSE3_FIR9;
FRV_asm FRV_unaligned_SSSE3_FIR10;
FRV_asm FRV_unaligned_SSSE3_FIR11;
FRV_asm FRV_unaligned_SSSE3_FIR12;

//SSE4 FIR
FRV_asm FRV_aligned_SSE4_FIR1;
FRV_asm FRV_aligned_SSE4_FIR13;
FRV_asm FRV_aligned_SSE4_FIR14;
FRV_asm FRV_aligned_SSE4_FIR15;
FRV_asm FRV_aligned_SSE4_FIR16;
FRV_asm FRV_aligned_SSE4_FIR17;
FRV_asm FRV_aligned_SSE4_FIR18;
FRV_asm FRV_aligned_SSE4_FIR19;
FRV_asm FRV_aligned_SSE4_FIR20;
FRV_asm FRV_aligned_SSE4_FIR21;
FRV_asm FRV_aligned_SSE4_FIR22;
FRV_asm FRV_aligned_SSE4_FIR23;
FRV_asm FRV_aligned_SSE4_FIR24;


FRV_asm FRV_unaligned_SSE4_FIR1;
FRV_asm FRV_unaligned_SSE4_FIR13;
FRV_asm FRV_unaligned_SSE4_FIR14;
FRV_asm FRV_unaligned_SSE4_FIR15;
FRV_asm FRV_unaligned_SSE4_FIR16;
FRV_asm FRV_unaligned_SSE4_FIR17;
FRV_asm FRV_unaligned_SSE4_FIR18;
FRV_asm FRV_unaligned_SSE4_FIR19;
FRV_asm FRV_unaligned_SSE4_FIR20;
FRV_asm FRV_unaligned_SSE4_FIR21;
FRV_asm FRV_unaligned_SSE4_FIR22;
FRV_asm FRV_unaligned_SSE4_FIR23;
FRV_asm FRV_unaligned_SSE4_FIR24;


}


class FilteredResizeV : public GenericVideoFilter 
/**
  * Class to resize in the vertical direction using a specified sampling filter
  * Helper for resample functions
 **/
{
public:
  FilteredResizeV( PClip _child, double subrange_top, double subrange_height, int target_height,
                   ResamplingFunction* func, IScriptEnvironment* env );
  virtual ~FilteredResizeV(void);
  PVideoFrame __stdcall GetFrame(int n, IScriptEnvironment* env);


private:
  int* /*const*/ resampling_pattern;
  int* /*const*/ resampling_patternUV;
  int *yOfs;
  int *yOfsUV;
  int pitch_gY;
  int pitch_gUV;
  
  
  FRV_asm *ua_proc_yplane;
  FRV_asm *a_proc_yplane;
  FRV_asm *ua_proc_uvplane;
  FRV_asm *a_proc_uvplane;
};


/*** Resample factory methods ***/

class FilteredResize
/**
  * Helper for resample functions
 **/
{
public:
static PClip CreateResizeH( PClip clip, double subrange_left, double subrange_width, int target_width, 
                            ResamplingFunction* func, IScriptEnvironment* env );

static PClip CreateResizeV( PClip clip, double subrange_top, double subrange_height, int target_height, 
                            ResamplingFunction* func, IScriptEnvironment* env );

static PClip CreateResize( PClip clip, int target_width, int target_height, const AVSValue* args, 
                           ResamplingFunction* f, IScriptEnvironment* env );

static AVSValue __cdecl Create_PointResize(AVSValue args, void*, IScriptEnvironment* env);

static AVSValue __cdecl Create_BilinearResize(AVSValue args, void*, IScriptEnvironment* env);

static AVSValue __cdecl Create_BicubicResize(AVSValue args, void*, IScriptEnvironment* env);

// 09-14-2002 - Vlad59 - Lanczos3Resize - 
static AVSValue __cdecl Create_LanczosResize(AVSValue args, void*, IScriptEnvironment* env);

static AVSValue __cdecl Create_Lanczos4Resize(AVSValue args, void*, IScriptEnvironment* env);

static AVSValue __cdecl Create_BlackmanResize(AVSValue args, void*, IScriptEnvironment* env);

static AVSValue __cdecl Create_Spline16Resize(AVSValue args, void*, IScriptEnvironment* env);

static AVSValue __cdecl Create_Spline36Resize(AVSValue args, void*, IScriptEnvironment* env);

static AVSValue __cdecl Create_Spline64Resize(AVSValue args, void*, IScriptEnvironment* env);

static AVSValue __cdecl Create_GaussianResize(AVSValue args, void*, IScriptEnvironment* env);
};



#endif // __Resample_H__
