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

#include "../../stdafx.h"

#include "resample.h"

#ifndef _AMD64_
#define USE_DYNAMIC_COMPILER true
#else
#define USE_DYNAMIC_COMPILER false
#endif

/********************************************************************
***** Declare index of new filters for Avisynth's filter engine *****
********************************************************************/

AVSFunction Resample_filters[] = {
  { "PointResize", "cii[src_left]f[src_top]f[src_width]f[src_height]f", FilteredResize::Create_PointResize },
  { "BilinearResize", "cii[src_left]f[src_top]f[src_width]f[src_height]f", FilteredResize::Create_BilinearResize },
  { "BicubicResize", "cii[b]f[c]f[src_left]f[src_top]f[src_width]f[src_height]f", FilteredResize::Create_BicubicResize },
  { "LanczosResize", "cii[src_left]f[src_top]f[src_width]f[src_height]f[taps]i", FilteredResize::Create_LanczosResize},
  { "Lanczos4Resize", "cii[src_left]f[src_top]f[src_width]f[src_height]f", FilteredResize::Create_Lanczos4Resize},
  { "BlackmanResize", "cii[src_left]f[src_top]f[src_width]f[src_height]f[taps]i", FilteredResize::Create_BlackmanResize},
  { "Spline16Resize", "cii[src_left]f[src_top]f[src_width]f[src_height]f", FilteredResize::Create_Spline16Resize},
  { "Spline36Resize", "cii[src_left]f[src_top]f[src_width]f[src_height]f", FilteredResize::Create_Spline36Resize},
  { "Spline64Resize", "cii[src_left]f[src_top]f[src_width]f[src_height]f", FilteredResize::Create_Spline64Resize},
  { "GaussResize", "cii[src_left]f[src_top]f[src_width]f[src_height]f[p]f", FilteredResize::Create_GaussianResize},
  /**
    * Resize(PClip clip, dst_width, dst_height [src_left, src_top, src_width, int src_height,] )
    *
    * src_left et al.   =  when these optional arguments are given, the filter acts just like
    *                      a Crop was performed with those parameters before resizing, only faster
   **/

  { 0 }
};

//arrays for easy assignment of function pointers
FRV_asm *FRV_aligned_SSE2_array[12] = {	&FRV_aligned_SSE2_FIR13, &FRV_aligned_SSE2_FIR14, &FRV_aligned_SSE2_FIR15, 
										&FRV_aligned_SSE2_FIR16, &FRV_aligned_SSE2_FIR17, &FRV_aligned_SSE2_FIR18, 
										&FRV_aligned_SSE2_FIR19, &FRV_aligned_SSE2_FIR20, &FRV_aligned_SSE2_FIR21, 
										&FRV_aligned_SSE2_FIR22, &FRV_aligned_SSE2_FIR23, &FRV_aligned_SSE2_FIR24,
										};

FRV_asm *FRV_unaligned_SSE2_array[12] = {&FRV_unaligned_SSE2_FIR13, &FRV_unaligned_SSE2_FIR14, &FRV_unaligned_SSE2_FIR15, 
										&FRV_unaligned_SSE2_FIR16, &FRV_unaligned_SSE2_FIR17, &FRV_unaligned_SSE2_FIR18, 
										&FRV_unaligned_SSE2_FIR19, &FRV_unaligned_SSE2_FIR20, &FRV_unaligned_SSE2_FIR21, 
										&FRV_unaligned_SSE2_FIR22, &FRV_unaligned_SSE2_FIR23, &FRV_unaligned_SSE2_FIR24
										};


FRV_asm *FRV_aligned_SSSE3_array[11] = {&FRV_aligned_SSSE3_FIR2, &FRV_aligned_SSSE3_FIR3, 
										&FRV_aligned_SSSE3_FIR4, &FRV_aligned_SSSE3_FIR5, &FRV_aligned_SSSE3_FIR6, 
										&FRV_aligned_SSSE3_FIR7, &FRV_aligned_SSSE3_FIR8, &FRV_aligned_SSSE3_FIR9 , 
										&FRV_aligned_SSSE3_FIR10, &FRV_aligned_SSSE3_FIR11, &FRV_aligned_SSSE3_FIR12};

FRV_asm *FRV_unaligned_SSSE3_array[11] = {&FRV_unaligned_SSSE3_FIR2, &FRV_unaligned_SSSE3_FIR3, 
										&FRV_unaligned_SSSE3_FIR4, &FRV_unaligned_SSSE3_FIR5, &FRV_unaligned_SSSE3_FIR6, 
										&FRV_unaligned_SSSE3_FIR7, &FRV_unaligned_SSSE3_FIR8, &FRV_unaligned_SSSE3_FIR9 , 
										&FRV_unaligned_SSSE3_FIR10, &FRV_unaligned_SSSE3_FIR11, &FRV_unaligned_SSSE3_FIR12};

FRV_asm *FRV_aligned_SSE3_array[11] = {&FRV_aligned_SSE3_FIR2, &FRV_aligned_SSE3_FIR3, 
										&FRV_aligned_SSE3_FIR4, &FRV_aligned_SSE3_FIR5, &FRV_aligned_SSE3_FIR6, 
										&FRV_aligned_SSE3_FIR7, &FRV_aligned_SSE3_FIR8, &FRV_aligned_SSE3_FIR9 , 
										&FRV_aligned_SSE3_FIR10, &FRV_aligned_SSE3_FIR11, &FRV_aligned_SSE3_FIR12};

FRV_asm *FRV_unaligned_SSE3_array[11] = {&FRV_unaligned_SSE3_FIR2, &FRV_unaligned_SSE3_FIR3, 
										&FRV_unaligned_SSE3_FIR4, &FRV_unaligned_SSE3_FIR5, &FRV_unaligned_SSE3_FIR6, 
										&FRV_unaligned_SSE3_FIR7, &FRV_unaligned_SSE3_FIR8, &FRV_unaligned_SSE3_FIR9 , 
										&FRV_unaligned_SSE3_FIR10, &FRV_unaligned_SSE3_FIR11, &FRV_unaligned_SSE3_FIR12};

FRV_asm *FRV_aligned_SSE4_array[12] = {	&FRV_aligned_SSE4_FIR13, &FRV_aligned_SSE4_FIR14, &FRV_aligned_SSE4_FIR15, 
										&FRV_aligned_SSE4_FIR16, &FRV_aligned_SSE4_FIR17, &FRV_aligned_SSE4_FIR18, 
										&FRV_aligned_SSE4_FIR19, &FRV_aligned_SSE4_FIR20, &FRV_aligned_SSE4_FIR21, 
										&FRV_aligned_SSE4_FIR22, &FRV_aligned_SSE4_FIR23, &FRV_aligned_SSE4_FIR24,
										};

FRV_asm *FRV_unaligned_SSE4_array[12] = {&FRV_unaligned_SSE4_FIR13, &FRV_unaligned_SSE4_FIR14, &FRV_unaligned_SSE4_FIR15, 
										&FRV_unaligned_SSE4_FIR16, &FRV_unaligned_SSE4_FIR17, &FRV_unaligned_SSE4_FIR18, 
										&FRV_unaligned_SSE4_FIR19, &FRV_unaligned_SSE4_FIR20, &FRV_unaligned_SSE4_FIR21, 
										&FRV_unaligned_SSE4_FIR22, &FRV_unaligned_SSE4_FIR23, &FRV_unaligned_SSE4_FIR24,
										};

FRH_yv12 *FRH_yv12_aligned_array[16] = {&FRH_yv12_aligned_FIR1, &FRH_yv12_aligned_FIR2, &FRH_yv12_aligned_FIR3, &FRH_yv12_aligned_FIR4,
										&FRH_yv12_aligned_FIR5, &FRH_yv12_aligned_FIR6, &FRH_yv12_aligned_FIR7, &FRH_yv12_aligned_FIR8,
										&FRH_yv12_aligned_FIR9, &FRH_yv12_aligned_FIR10, &FRH_yv12_aligned_FIR11, &FRH_yv12_aligned_FIR12,
										&FRH_yv12_aligned_FIR13, &FRH_yv12_aligned_FIR14, &FRH_yv12_aligned_FIR15, &FRH_yv12_aligned_FIR16};

FRH_yv12 *FRH_yv12_unaligned_array[16] = {&FRH_yv12_unaligned_FIR1, &FRH_yv12_unaligned_FIR2, &FRH_yv12_unaligned_FIR3, &FRH_yv12_unaligned_FIR4,
										&FRH_yv12_unaligned_FIR5, &FRH_yv12_unaligned_FIR6, &FRH_yv12_unaligned_FIR7, &FRH_yv12_unaligned_FIR8,
										&FRH_yv12_unaligned_FIR9, &FRH_yv12_unaligned_FIR10, &FRH_yv12_unaligned_FIR11, &FRH_yv12_unaligned_FIR12,
										&FRH_yv12_unaligned_FIR13, &FRH_yv12_unaligned_FIR14, &FRH_yv12_unaligned_FIR15, &FRH_yv12_unaligned_FIR16};



/****************************************
 ***** Filtered Resize - Horizontal *****
 ***************************************/
#ifndef _AMD64_
FilteredResizeH::FilteredResizeH( PClip _child, double subrange_left, double subrange_width,
                                  int target_width, ResamplingFunction* func, IScriptEnvironment* env )
  : GenericVideoFilter(_child), tempY(0), tempUV(0),pattern_luma(0),pattern_chroma(0),
  CodeGenerator(false) //Josh: Codegenerator construtor takes arg x64
{
	try {	// HIDE DAMN SEH COMPILER BUG!!!
  pattern_luma = pattern_chroma = (int *)0;
  tempUV = tempY = 0;

  original_width = _child->GetVideoInfo().width;

  if (target_width<=0)
    env->ThrowError("Resize: Width must be greater than 0.");

  if (vi.IsYUV())
  {
    if ((target_width&1) && (vi.IsYUY2()))
      env->ThrowError("Resize: YUY2 width must be even");
    if ((target_width&1) && (vi.IsYV12()))
      env->ThrowError("Resize: YV12 width must be even.");

    tempY = (BYTE*) _aligned_malloc(original_width*2+4+32, 64);   // aligned for Athlon cache line
    tempUV = (BYTE*) _aligned_malloc(original_width*4+8+32, 64);  // aligned for Athlon cache line

    if (vi.IsYV12()) {
      pattern_chroma = GetResamplingPatternYUV( vi.width>>1, subrange_left/2.0, subrange_width/2.0,
        target_width>>1, func, true, tempY, env );
    } else {
      pattern_chroma = GetResamplingPatternYUV( vi.width>>1, subrange_left/2.0, subrange_width/2.0,
        target_width>>1, func, false, tempUV, env );
    }
    pattern_luma = GetResamplingPatternYUV(vi.width, subrange_left, subrange_width, target_width, func, true, tempY, env);
  }
  else
    pattern_luma = GetResamplingPatternRGB(vi.width, subrange_left, subrange_width, target_width, func, env);

  vi.width = target_width;

  use_dynamic_code = USE_DYNAMIC_COMPILER;

  if (use_dynamic_code) {
    if (vi.IsPlanar()) {
      assemblerY = GenerateResizer(PLANAR_Y, env);
      assemblerUV = GenerateResizer(PLANAR_U, env);
    }
  }
	}
	catch (...) { throw; }
}
#else
FilteredResizeH::FilteredResizeH( PClip _child, double subrange_left, double subrange_width,
                                  int target_width, ResamplingFunction* func, IScriptEnvironment* env )
  : GenericVideoFilter(_child), tempY(0), tempUV(0),pattern_luma(0),pattern_chroma(0)
{
	pattern_luma = pattern_chroma = (int *)0;
	tempUV = tempY = 0;

	yv12_aligned = yv12_unaligned = 0;

	original_width = _child->GetVideoInfo().width;

	if (target_width<=0)
		env->ThrowError("Resize: Width must be greater than 0.");

	if (vi.IsYUV())
	{
		if ((target_width&1) && (vi.IsYUY2()))
			env->ThrowError("Resize: YUY2 width must be even");
		if ((target_width&1) && (vi.IsYV12()))
			env->ThrowError("Resize: YV12 width must be even.");

		tempY = (BYTE*) _aligned_malloc(original_width*2+4+32, 64);   // aligned for Athlon cache line
		tempUV = (BYTE*) _aligned_malloc(original_width*4+8+32, 64);  // aligned for Athlon cache line

		pattern_luma = GetResamplingPatternYUV(vi.width, subrange_left, subrange_width, target_width, func, true, tempY, env);
		
		if (vi.IsYV12()) 
		{
			pattern_chroma = GetResamplingPatternYUV( vi.width>>1, subrange_left/2.0, subrange_width/2.0,
			target_width>>1, func, true, tempY, env );
			if (*pattern_luma > 16)
			{
				yv12_aligned = &FRH_yv12_aligned_mmx;
				yv12_unaligned = &FRH_yv12_unaligned_mmx;
			}
			else
			{
				yv12_aligned = FRH_yv12_aligned_array[*pattern_luma-1];
				yv12_unaligned = FRH_yv12_unaligned_array[*pattern_luma-1];

			}
		} 
		else 
		{
			pattern_chroma = GetResamplingPatternYUV( vi.width>>1, subrange_left/2.0, subrange_width/2.0,
			target_width>>1, func, false, tempUV, env );
		}
		
	}
	else
		pattern_luma = GetResamplingPatternRGB(vi.width, subrange_left, subrange_width, target_width, func, env);

	vi.width = target_width;
}
#endif

/***********************************
 * Dynamically Assembled Resampler
 *
 * (c) 2003, Klaus Post
 *
 * Dynamic version of the Horizontal resizer
 *
 * The Algorithm is the same, except this
 *  one is able to process 6 pixels in parallel.
 * The inner loop filter is unrolled based on the
 *  exact filter size.
 * Too much code to workaround for the 6 pixels, and
 *  still not quite perfect. Though still faster than
 *  the original code.
 **********************************/

#ifndef _AMD64_
DynamicAssembledCode FilteredResizeH::GenerateResizer(int gen_plane, IScriptEnvironment* env) {

  __declspec(align(8)) static const __int64 FPround   =  0x0000200000002000; // 16384/2
  __declspec(align(8)) static const __int64 Mask2_pix =  0x000000000000ffff;
  __declspec(align(8)) static const __int64 Mask1_pix_inv =  0xffffffffffffff00;
  __declspec(align(8)) static const __int64 Mask2_pix_inv =  0xffffffffffff0000;
  __declspec(align(8)) static const __int64 Mask3_pix_inv =  0xffffffffff000000;

  //Josh: Constructor for assembler takes bool argument x64
  Assembler x86(false);   // This is the class that assembles the code.

  // Set up variables for this plane.
  int vi_height = (gen_plane == PLANAR_Y) ? vi.height : (vi.height/2);
  int vi_dst_width = (gen_plane == PLANAR_Y) ? vi.width : (vi.width/2);
  int vi_src_width = (gen_plane == PLANAR_Y) ? original_width : (original_width/2);

  int mod16_w = ((3+vi_src_width)/16);  // Src size!
  int mod16_remain = (3+vi_src_width-(mod16_w*16))/4;  //Src size!


  bool isse = !!(env->GetCPUFlags() & CPUF_INTEGER_SSE);

  //  isse=false;   // Manually disable ISSE

  int prefetchevery = 2;
  if ((env->GetCPUFlags() & CPUF_3DNOW_EXT)||((env->GetCPUFlags() & CPUF_SSE2))) {
    // We have either an Athlon or a P4 with 64byte cacheline
    prefetchevery = 4;
  }

  bool unroll_fetch = false;
  // Unroll fetch loop on Athlon. P4 has a very small l1 cache, so unrolling will not give performance benefits here.
  if ((env->GetCPUFlags() & CPUF_3DNOW_EXT)) {
    unroll_fetch = true;
  }
  // We forcibly does not unroll fetch, if image width is more than 512
  if (vi_src_width > 512) {
    unroll_fetch = false;
  }

  bool avoid_stlf = false;
  if (env->GetCPUFlags() & CPUF_3DNOW_EXT) {
    // We have an Athlon.
    // Avoid Store->Load forward penalty (8 to 4 mismatch)
    // NOT faster on Athlon!
//    avoid_stlf = false;
    if (!isse) {
      avoid_stlf = false;
    }
  }

  if (!(vi_src_width && vi_dst_width && vi_height)) { // Skip
    x86.ret();
    return DynamicAssembledCode(x86, env, "ResizeH: ISSE code could not be compiled.");
  }

  int* array = (gen_plane == PLANAR_Y) ? pattern_luma : pattern_chroma;
  int fir_filter_size = array[0];
  int filter_offset=fir_filter_size*8+8;  // This is the length from one pixel pair to another
  int* cur_luma = array+2;

  int six_loops = (vi_dst_width-2)/6;  // How many loops can we do safely, with 6 pixels.


  if (true) {
    // Store registers
    x86.push(eax);
    x86.push(ebx);
    x86.push(ecx);
    x86.push(edx);
    x86.push(esi);
    x86.push(edi);
    x86.push(ebp);

    // Initialize registers.
    x86.mov(eax,(int)&FPround);
    x86.pxor(mm6,mm6);  // Cleared mmx register - Not touched!
    x86.movq(mm7, qword_ptr[eax]);  // Rounder for final division. Not touched!

    x86.mov(dword_ptr [&gen_h],vi_height);  // This is our y counter.

    x86.align(16);
    x86.label("yloop");

    x86.mov(eax,dword_ptr [&gen_dstp]);
    x86.mov(dword_ptr [&gen_temp_destp],eax);

    x86.mov(esi, dword_ptr[&gen_srcp]);
    x86.mov(edi, dword_ptr[&tempY]);

    // Unpack source bytes to words in tempY buffer

    for (int i=0;i<mod16_w;i++) {
      if ((!(i%prefetchevery)) && (i*16+256<vi_src_width) && isse && unroll_fetch) {
         //Prefetch only once per cache line
        x86.prefetchnta(dword_ptr [esi+256]);
      }
      if (!unroll_fetch) {  // Should we create a loop instead of unrolling?
        i = mod16_w;  // Jump out of loop
        x86.mov(ebx, mod16_w);
        x86.align(16);
        x86.label("fetch_loopback");
      }
      x86.movq(mm0, qword_ptr[esi]);        // Move pixels into mmx-registers
       x86.movq(mm1, qword_ptr[esi+8]);
      x86.movq(mm2,mm0);
       x86.punpcklbw(mm0,mm6);     // Unpack bytes -> words
      x86.movq(mm3,mm1);
       x86.punpcklbw(mm1,mm6);
      x86.add(esi,16);
       x86.punpckhbw(mm2,mm6);
      x86.add(edi,32);
       x86.punpckhbw(mm3,mm6);
      if (!unroll_fetch)   // Loop on if not unrolling
        x86.dec(ebx);
      if ((!avoid_stlf) || (!isse)) {
        x86.movq(qword_ptr[edi-32],mm0);        // Store unpacked pixels in temporary space.
        x86.movq(qword_ptr[edi+8-32],mm2);
        x86.movq(qword_ptr[edi+16-32],mm1);
        x86.movq(qword_ptr[edi+24-32],mm3);
      } else {  // Code to avoid store->load forward size mismatch.
        x86.movd(dword_ptr [edi-32],mm0);
        x86.movd(dword_ptr [edi+8-32],mm2);
        x86.movd(dword_ptr [edi+16-32],mm1);
        x86.movd(dword_ptr [edi+24-32],mm3);
        x86.pswapd(mm0,mm0);				// 3DNow instruction!!
        x86.pswapd(mm1,mm1);
        x86.pswapd(mm2,mm2);
        x86.pswapd(mm3,mm3);
        x86.movd(dword_ptr [edi+4-32],mm0);
        x86.movd(dword_ptr [edi+8+4-32],mm2);
        x86.movd(dword_ptr [edi+16+4-32],mm1);
        x86.movd(dword_ptr [edi+24+4-32],mm3);
      }
      if (!unroll_fetch)   // Loop on if not unrolling
        x86.jnz("fetch_loopback");
    }
    switch (mod16_remain) {
    case 3:
      x86.movq(mm0, qword_ptr[esi]);        // Move 12 pixels into mmx-registers
       x86.movd(mm1, dword_ptr[esi+8]);
      x86.movq(mm2,mm0);
       x86.punpcklbw(mm0,mm6);               // Unpack bytes -> words
      x86.punpckhbw(mm2,mm6);
       x86.punpcklbw(mm1,mm6);
      x86.movq(qword_ptr[edi],mm0);         // Store 12 unpacked pixels in temporary space.
       x86.movq(qword_ptr[edi+8],mm2);
      x86.movq(qword_ptr[edi+16],mm1);
      break;
    case 2:
      x86.movq(mm0, qword_ptr[esi]);        // Move 8 pixels into mmx-registers
      x86.movq(mm2,mm0);
       x86.punpcklbw(mm0,mm6);               // Unpack bytes -> words
      x86.punpckhbw(mm2,mm6);
       x86.movq(qword_ptr[edi],mm0);         // Store 8 unpacked pixels in temporary space.
      x86.movq(qword_ptr[edi+8],mm2);
      break;
    case 1:
      x86.movd(mm0,dword_ptr [esi]);        // Move 4 pixels into mmx-registers
      x86.punpcklbw(mm0,mm6);               // Unpack bytes -> words
      x86.movq(qword_ptr[edi],mm0);         // Store 4 unpacked pixels in temporary space.
      break;
    case 0:
      break;
    default:
      env->ThrowError("Resize: FilteredResizeH::GenerateResizer illegal state %d.", mod16_remain);  // Opps!
    }

    // Calculate destination pixels

    x86.mov(edi, (int)cur_luma);  // First there are offsets into the tempY planes, defining where the filter starts
                                  // After that there is (filter_size) constants for multiplying.
                                  // Next pixel pair is put after (filter_offset) bytes.

    if (six_loops) {       // Do we have at least 1 loops worth to do?
      if (six_loops > 1) { // Do we have more than 1 loop to do?
        x86.mov(dword_ptr [&gen_x],six_loops);
        x86.align(16);
        x86.label("xloop");
      }
      x86.mov(eax,dword_ptr [edi]);   // Move pointers of first pixel pair into registers
      x86.mov(ebx,dword_ptr [edi+4]);
      x86.mov(ecx,dword_ptr [edi+filter_offset]);     // Move pointers of next pixel pair into registers
      x86.mov(edx,dword_ptr [edi+filter_offset+4]);
      x86.movq(mm3,mm7);  // Start with rounder!
      x86.mov(esi,dword_ptr [edi+(filter_offset*2)]);   // Move pointers of next pixel pair into registers
      x86.movq(mm5,mm7);
      x86.mov(ebp,dword_ptr [edi+(filter_offset*2)+4]);
      x86.movq(mm4,mm7);
      x86.add(edi,8); // cur_luma++

      for (int i=0;i<fir_filter_size;i++) {       // Unroll filter inner loop based on the filter size.
          x86.movd(mm0, dword_ptr[eax+i*4]);
           x86.movd(mm1, dword_ptr[ecx+i*4]);
          x86.punpckldq(mm0, qword_ptr[ebx+i*4]);
           x86.punpckldq(mm1, qword_ptr[edx+i*4]);
          x86.pmaddwd(mm0, qword_ptr[edi+i*8]);
           x86.movd(mm2, dword_ptr[esi+i*4]);
          x86.pmaddwd(mm1,qword_ptr[edi+filter_offset+(i*8)]);
           x86.punpckldq(mm2, qword_ptr[ebp+i*4]);
          x86.paddd(mm3, mm0);
           x86.pmaddwd(mm2, qword_ptr[edi+(filter_offset*2)+(i*8)]);
          x86.paddd(mm4, mm1);
           x86.paddd(mm5, mm2);
      }
      x86.psrad(mm3,14);
       x86.mov(eax,dword_ptr[&gen_temp_destp]);
      x86.psrad(mm4,14);
       x86.add(dword_ptr [&gen_temp_destp],6);
      x86.psrad(mm5,14);
       x86.packssdw(mm3, mm4);       // [...3 ...2] [...1 ...0] => [.3 .2 .1 .0]
      x86.packssdw(mm5, mm6);        // [...z ...z] [...5 ...4] => [.z .z .5 .4]
       x86.add(edi,filter_offset*3-8);
      x86.packuswb(mm3, mm5);        // [.z .z .5 .4] [.3 .2 .1 .0] => [zz543210]
      if (six_loops > 1) {   // Do we have more than 1 loop to do?
         x86.dec(dword_ptr [&gen_x]);
        x86.movq(qword_ptr[eax],mm3);  // This was a potential 2 byte overwrite!
         x86.jnz("xloop");
      } else {
        x86.movq(qword_ptr[eax],mm3);  // This was a potential 2 byte overwrite!
      }
    }

    // Process any remaining pixels

//      vi_dst_width;                              1,2,3,4,5,6,7,8,9,A,B,C,D,E,F,10
//      vi_dst_width-2                            -1,0,1,2,3,4,5,6,7,8,9,A,B,C,D,E,F
//      six_loops = (vi_dst_width-2)/6;            0,0,0,0,0,0,0,1,1,1,1,1,1,2,2,2,2
    int remainx = vi_dst_width-(six_loops*6); //   1,2,3,4,5,6,7,2,3,4,5,6,7,2,3,4,5,6,7

    while (remainx>=4) {
      x86.mov(eax,dword_ptr [edi]);
      x86.mov(ebx,dword_ptr [edi+4]);
      x86.movq(mm3,mm7);  // Used for pix 1+2
      x86.mov(ecx,dword_ptr [edi+filter_offset]);
      x86.movq(mm4,mm7);  // Used for pix 3+4
      x86.mov(edx,dword_ptr [edi+filter_offset+4]);

      x86.add(edi,8); // cur_luma++
      for (int i=0;i<fir_filter_size;i++) {
        x86.movd(mm0, dword_ptr [eax+i*4]);
         x86.movd(mm1, dword_ptr [ecx+i*4]);
        x86.punpckldq(mm0, qword_ptr[ebx+i*4]);
         x86.punpckldq(mm1, qword_ptr[edx+i*4]);
        x86.pmaddwd(mm0, qword_ptr[edi+i*8]);
         x86.pmaddwd(mm1, qword_ptr[edi+filter_offset+(i*8)]);
        x86.paddd(mm3, mm0);
         x86.paddd(mm4, mm1);
      }
      x86.psrad(mm3,14);
      x86.psrad(mm4,14);
      x86.mov(eax,dword_ptr[&gen_temp_destp]);
      x86.packssdw(mm3, mm4);      // [...3 ...2] [...1 ...0] => [.3 .2 .1 .0]
      x86.packuswb(mm3, mm6);      // [.. .. .. ..] [.3 .2 .1 .0] => [....3210]

      x86.movd(dword_ptr[eax],mm3); 
      remainx -= 4;
      if (remainx) {
        x86.add(dword_ptr [&gen_temp_destp],4);
        x86.add(edi,filter_offset*2-8);
      }
    }
    if (remainx==3) {
      x86.mov(eax,dword_ptr [edi]);
      x86.movq(mm3,mm7);  // Used for pix 1+2
      x86.mov(ebx,dword_ptr [edi+4]);
      x86.movq(mm4,mm7);  // Used for pix 3
      x86.mov(ecx,dword_ptr [edi+filter_offset]);

      x86.add(edi,8); // cur_luma++
      for (int i=0;i<fir_filter_size;i++) {
        x86.movd(mm0, dword_ptr [eax+i*4]);
         x86.movd(mm1, dword_ptr [ecx+i*4]);
        x86.punpckldq(mm0, qword_ptr[ebx+i*4]);
         x86.pmaddwd(mm1, qword_ptr[edi+filter_offset+(i*8)]);
        x86.pmaddwd(mm0, qword_ptr[edi+i*8]);
         x86.paddd(mm4, mm1);
        x86.paddd(mm3, mm0);
      }
       x86.psrad(mm4,14);
      x86.psrad(mm3,14);
       x86.mov(eax,dword_ptr[&gen_temp_destp]);
      x86.packssdw(mm3, mm4);      // [...z ...2] [...1 ...0] => [.z .2 .1 .0]
       x86.movd(mm0,dword_ptr[eax]);
      x86.packuswb(mm3, mm6);      // [.. .. .. ..] [.z .2 .1 .0] => [....z210]
       x86.pand(mm0,qword_ptr[(int)&Mask3_pix_inv]);
      x86.por(mm3,mm0);
      
      x86.movd(dword_ptr[eax],mm3); 
      remainx = 0;
    }
    if (remainx==2) {
      x86.mov(eax,dword_ptr [edi]);
      x86.movq(mm3,mm7);  // Used for pix 1+2
      x86.mov(ebx,dword_ptr [edi+4]);

      x86.add(edi,8); // cur_luma++
      for (int i=0;i<fir_filter_size;i+=2) {
        const int j = i+1;
        if (j < fir_filter_size) {
          x86.movd(mm0, dword_ptr [eax+i*4]);
           x86.movd(mm1, dword_ptr [eax+j*4]);
          x86.punpckldq(mm0, qword_ptr[ebx+i*4]);
           x86.punpckldq(mm1, qword_ptr[ebx+j*4]);
          x86.pmaddwd(mm0, qword_ptr[edi+i*8]);
           x86.pmaddwd(mm1, qword_ptr[edi+j*8]);
          x86.paddd(mm3, mm0);
          x86.paddd(mm3, mm1);
        } else {
          x86.movd(mm0, dword_ptr [eax+i*4]);
          x86.punpckldq(mm0, qword_ptr[ebx+i*4]);
          x86.pmaddwd(mm0, qword_ptr[edi+i*8]);
          x86.paddd(mm3, mm0);
        }
      }
       x86.mov(eax,dword_ptr[&gen_temp_destp]);
      x86.psrad(mm3,14);
       x86.movd(mm0,dword_ptr[eax]);
      x86.packssdw(mm3, mm6);      // [...z ...z] [...1 ...0] => [.z .z .1 .0]
       x86.pand(mm0,qword_ptr[(int)&Mask2_pix_inv]);
      x86.packuswb(mm3, mm6);      // [.z .z .z .z] [.z .z .1 .0] => [zzzzzz10]
       x86.por(mm3,mm0);
       x86.movd(dword_ptr[eax],mm3); 
      remainx = 0;
    }
    if (remainx==1) {
      x86.mov(eax,dword_ptr [edi]);
      x86.movq(mm3,mm7);  // Used for pix 1

      x86.add(edi,8); // cur_luma++
      for (int i=0;i<fir_filter_size;i+=2) {
        const int j = i+1;
        if (j < fir_filter_size) {
          x86.movd(mm0, dword_ptr [eax+i*4]);
           x86.movd(mm1, dword_ptr [eax+j*4]);
          x86.pmaddwd(mm0, qword_ptr[edi+i*8]);
           x86.pmaddwd(mm1, qword_ptr[edi+j*8]);
          x86.paddd(mm3, mm0);
          x86.paddd(mm3, mm1);
        } else {
          x86.movd(mm0, dword_ptr [eax+i*4]);
          x86.pmaddwd(mm0, qword_ptr[edi+i*8]);
          x86.paddd(mm3, mm0);
        }
      }
       x86.mov(eax,dword_ptr[&gen_temp_destp]);
      x86.psrad(mm3,14);
       x86.movd(mm0,dword_ptr[eax]);
      x86.pand(mm3,qword_ptr[(int)&Mask2_pix]);
       x86.pand(mm0,qword_ptr[(int)&Mask1_pix_inv]);
      x86.packuswb(mm3, mm6);      // [.z .z .z .z] [.z .z .Z .0] => [zzzzzzZ0]
      x86.por(mm3,mm0);
      x86.movd(dword_ptr[eax],mm3); 
      remainx = 0;
    }

    // End remaining pixels

    x86.mov(eax,dword_ptr [&gen_src_pitch]);
    x86.mov(ebx,dword_ptr [&gen_dst_pitch]);
    x86.add(dword_ptr [&gen_srcp], eax);
    x86.add(dword_ptr [&gen_dstp], ebx);

    x86.dec(dword_ptr [&gen_h]);
    x86.jnz("yloop");
    // No more mmx for now
    x86.emms();
    // Restore registers
    x86.pop(ebp);
    x86.pop(edi);
    x86.pop(esi);
    x86.pop(edx);
    x86.pop(ecx);
    x86.pop(ebx);
    x86.pop(eax);
    x86.ret();
  }

  return DynamicAssembledCode(x86, env, "ResizeH: ISSE code could not be compiled.");
}
#endif

PVideoFrame __stdcall FilteredResizeH::GetFrame(int n, IScriptEnvironment* env)
{
	PVideoFrame src = child->GetFrame(n, env);
	PVideoFrame dst = env->NewVideoFrame(vi);
	const BYTE* srcp = src->GetReadPtr();
	BYTE* dstp = dst->GetWritePtr();
	int src_pitch = src->GetPitch();
	int dst_pitch = dst->GetPitch();
	if (vi.IsPlanar()) 
	{
		bool unaligned = (((INT_PTR)srcp&15) || (src_pitch&15));
		int org_width = src->GetRowSize(PLANAR_Y_ALIGNED);
		int dst_height = dst->GetHeight();
		int* array = pattern_luma;
		int dst_width = dst->GetRowSize(PLANAR_Y_ALIGNED);

		unaligned ? yv12_unaligned(srcp, dstp, src_pitch, dst_pitch, dst_height, dst_width, org_width, array) 
								: yv12_aligned(srcp, dstp, src_pitch, dst_pitch, dst_height, dst_width, org_width, array);

		srcp = src->GetReadPtr(PLANAR_U);
		dstp = dst->GetWritePtr(PLANAR_U);
		src_pitch = src->GetPitch(PLANAR_U);
		dst_pitch = dst->GetPitch(PLANAR_U);
		unaligned = (((INT_PTR)srcp&15) || (src_pitch&15));
		org_width = src->GetRowSize(PLANAR_U_ALIGNED);
		array = pattern_chroma;
		dst_height = dst->GetHeight(PLANAR_U);
		dst_width = dst->GetRowSize(PLANAR_U_ALIGNED);

		unaligned ? yv12_unaligned(srcp, dstp, src_pitch, dst_pitch, dst_height, dst_width, org_width, array) 
								: yv12_aligned(srcp, dstp, src_pitch, dst_pitch, dst_height, dst_width, org_width, array);

		srcp = src->GetReadPtr(PLANAR_V);
		dstp = dst->GetWritePtr(PLANAR_V);
		unaligned = (((INT_PTR)srcp&15) || (src_pitch &15));

		unaligned ? yv12_unaligned(srcp, dstp, src_pitch, dst_pitch, dst_height, dst_width, org_width, array) 
								: yv12_aligned(srcp, dstp, src_pitch, dst_pitch, dst_height, dst_width, org_width, array);



		/* don't really need a loop at the moment . . . yv12 is the only planar colorspace
		int plane = 0;
		//needs to based on case srcp or src pitch is not mod 16
		while (plane++<3) 
		{
			//int org_width = (plane==1) ? original_width : (original_width+1)>>1;
			int org_width = (plane==1) ? src->GetRowSize(PLANAR_Y_ALIGNED) : src->GetRowSize(PLANAR_V_ALIGNED);
			int dst_height= (plane==1) ? dst->GetHeight() : dst->GetHeight(PLANAR_U);
			int* array = (plane==1) ? pattern_luma : pattern_chroma;
			int dst_width = (plane==1) ? dst->GetRowSize(PLANAR_Y_ALIGNED) : dst->GetRowSize(PLANAR_U_ALIGNED);
			switch (plane) 
			{
				case 2:
				{
					srcp = src->GetReadPtr(PLANAR_U);
					dstp = dst->GetWritePtr(PLANAR_U);
					src_pitch = src->GetPitch(PLANAR_U);
					dst_pitch = dst->GetPitch(PLANAR_U);
					break;
				}
				
				case 3:
				{
					srcp = src->GetReadPtr(PLANAR_V);
					dstp = dst->GetWritePtr(PLANAR_V);
					src_pitch = src->GetPitch(PLANAR_U);
					dst_pitch = dst->GetPitch(PLANAR_U);
					break;
				}
				
				default: {break;}
			}
			
			(((INT_PTR)srcp&15) || (src_pitch &15)) ? yv12_unaligned(srcp, dstp, src_pitch, dst_pitch, dst_height, dst_width, org_width, array) 
														: yv12_aligned(srcp, dstp, src_pitch, dst_pitch, dst_height, dst_width, org_width, array);
		}*/
	}
	else if (vi.IsYUY2())
	{
		FRH_yuy2_aligned_mmx(srcp, dstp, src_pitch, dst_pitch, vi.height, vi.width, original_width, pattern_luma, pattern_chroma);
	}
	else if (vi.IsRGB24()) // RGB24 is not recommended. 75% of all pixels are not aligned.
		FRH_rgb24_mmx(srcp, dstp, src_pitch, dst_pitch, vi.height, vi.width, pattern_luma);
	else //last case is RGB32
		FRH_rgb32_mmx(srcp, dstp, src_pitch, dst_pitch, vi.height, vi.width, pattern_luma);
	return dst;
}

#ifndef _AMD64_
FilteredResizeH::~FilteredResizeH(void)
{
  if (pattern_luma) _aligned_free(pattern_luma);
  if (pattern_chroma) _aligned_free(pattern_chroma);
  if (tempY)
  {
    if (tempUV) _aligned_free(tempUV);
    if (tempY) _aligned_free(tempY);
  }
  assemblerY.Free();
  assemblerUV.Free();
}
#else
FilteredResizeH::~FilteredResizeH(void)
{
  if (pattern_luma) _aligned_free(pattern_luma);
  if (pattern_chroma) _aligned_free(pattern_chroma);
  if (tempY)
  {
    if (tempUV) _aligned_free(tempUV);
    if (tempY) _aligned_free(tempY);
  }
}
#endif

/***************************************
 ***** Filtered Resize - Vertical ******
 ***************************************/

FilteredResizeV::FilteredResizeV( PClip _child, double subrange_top, double subrange_height,
                                  int target_height, ResamplingFunction* func, IScriptEnvironment* env )
  : GenericVideoFilter(_child)
{
	resampling_pattern = resampling_patternUV = yOfs = yOfsUV = 0;

	if (target_height<4)
		env->ThrowError("Resize: Height must be bigger than or equal to 4.");
	if (vi.IsYV12() && (target_height&1))
		env->ThrowError("Resize: YV12 destination height must be multiple of 2.");
	if (vi.IsRGB())
		subrange_top = vi.height - subrange_top - subrange_height;

	resampling_pattern = GetResamplingPatternRGB(vi.height, subrange_top, subrange_height, target_height, func, env);	
	resampling_patternUV = GetResamplingPatternRGB(vi.height>>1, subrange_top/2.0f, subrange_height/2.0f, target_height>>1, func, env);
	

	vi.height = target_height;

	pitch_gY = -1;
	yOfs = 0;

	pitch_gUV = -1;
	yOfsUV = 0;
	
	a_proc_yplane = 0;
	ua_proc_yplane = 0;
	a_proc_uvplane = 0;
	ua_proc_uvplane = 0;
	
	//We need new code for the new resizers using FUNCTION POINTERS!
	int fir_size_y = *resampling_pattern;
	int fir_size_uv = *resampling_patternUV;

	int flags = env->GetCPUFlags();

	if (fir_size_y < 13)
	{
		if(fir_size_y == 1)
		{
			if (flags & CPUF_SSE4)
			{
				a_proc_yplane = &FRV_aligned_SSE4_FIR1;
				ua_proc_yplane = &FRV_unaligned_SSE4_FIR1;
				a_proc_uvplane = &FRV_aligned_SSE4_FIR1;
				ua_proc_uvplane = &FRV_unaligned_SSE4_FIR1;
			}
			else
			{
				a_proc_yplane = &FRV_aligned_SSE2_FIR1;
				ua_proc_yplane = &FRV_unaligned_SSE2_FIR1;
				a_proc_uvplane = &FRV_aligned_SSE2_FIR1;
				ua_proc_uvplane = &FRV_unaligned_SSE2_FIR1;
			}
		}
		else if (flags & CPUF_SSSE3)
		{
			a_proc_yplane = FRV_aligned_SSSE3_array[fir_size_y - 2];
			ua_proc_yplane = FRV_unaligned_SSSE3_array[fir_size_y - 2];
			a_proc_uvplane = FRV_aligned_SSSE3_array[fir_size_uv - 2];
			ua_proc_uvplane = FRV_unaligned_SSSE3_array[fir_size_uv - 2];
		}
		else
		{	
			a_proc_yplane = FRV_aligned_SSE3_array[fir_size_y - 2];
			ua_proc_yplane = FRV_unaligned_SSE3_array[fir_size_y - 2];
			a_proc_uvplane = FRV_aligned_SSE3_array[fir_size_uv - 2];
			ua_proc_uvplane = FRV_unaligned_SSE3_array[fir_size_uv - 2];
		}
	}
	else
	{
		if (flags & CPUF_SSE4)
		{
			a_proc_yplane = FRV_aligned_SSE4_array[fir_size_y - 13];
			ua_proc_yplane = FRV_unaligned_SSE4_array[fir_size_y - 13];
			a_proc_uvplane = FRV_aligned_SSE4_array[fir_size_uv - 13];
			ua_proc_uvplane = FRV_unaligned_SSE4_array[fir_size_uv - 13];
		}
		else
		{
			a_proc_yplane = FRV_aligned_SSE2_array[fir_size_y - 13];
			ua_proc_yplane = FRV_unaligned_SSE2_array[fir_size_y - 13];
			a_proc_uvplane = FRV_aligned_SSE2_array[fir_size_uv - 13];
			ua_proc_uvplane = FRV_unaligned_SSE2_array[fir_size_uv - 13];
		}
	}
}


PVideoFrame __stdcall FilteredResizeV::GetFrame(int n, IScriptEnvironment* env)
{
	
	PVideoFrame src = child->GetFrame(n, env);
	PVideoFrame dst = env->NewVideoFrame(vi);
	int* cur = resampling_pattern;
	int fir_filter_size = *cur++;	
	int src_pitch = src->GetPitch();
	int dst_pitch = dst->GetPitch();

	int xloops = ((src->GetRowSize()+15)/16)*16; // Round to multiple of 16
	const BYTE* srcp = src->GetReadPtr();
	BYTE* dstp = dst->GetWritePtr();
	int y = vi.height;

	int plane = vi.IsPlanar() ? 4:1;

	if (pitch_gUV != src->GetPitch(PLANAR_U)) 
	{  // Pitch is not the same as last frame
		int shUV = src->GetHeight(PLANAR_U);
		pitch_gUV = src->GetPitch(PLANAR_U);

		if (!yOfsUV)
			yOfsUV = new int[shUV];

		for (int i = 0; i < shUV; i++)
			yOfsUV[i] = pitch_gUV * i;
	}

	if (pitch_gY != src->GetPitch(PLANAR_Y))  
	{ // Pitch is not the same as last frame
		int sh = src->GetHeight();
		pitch_gY = src->GetPitch(PLANAR_Y);

		if (!yOfs)
			yOfs = new int[sh];

		for (int i = 0; i < sh; i++)
			yOfs[i] = pitch_gY * i;
	}

	int *yOfs2 = yOfs;
	
	while (plane-->0)
	{
		switch (plane) 
		{
			case 2:  // take V plane
				cur = resampling_patternUV;
				fir_filter_size = *cur++;
				src_pitch = src->GetPitch(PLANAR_V);
				dst_pitch = dst->GetPitch(PLANAR_V);
				xloops = ((src->GetRowSize(PLANAR_V_ALIGNED)+15) / 16)*16;  // Round to multiple of 16
				dstp = dst->GetWritePtr(PLANAR_V);
				srcp = src->GetReadPtr(PLANAR_V);
				y = dst->GetHeight(PLANAR_V);
				yOfs2 = this->yOfsUV;
				(((INT_PTR)srcp&15) || (src_pitch &15)) ? ua_proc_uvplane(srcp, dstp, src_pitch, dst_pitch, y, xloops, yOfs2, cur)
															:a_proc_uvplane(srcp, dstp, src_pitch, dst_pitch, y, xloops, yOfs2, cur);
				
			break;

			case 1: // U Plane
				cur = resampling_patternUV;
				fir_filter_size = *cur++;
				dstp = dst->GetWritePtr(PLANAR_U);
				srcp = src->GetReadPtr(PLANAR_U);
				y = dst->GetHeight(PLANAR_U);
				src_pitch = src->GetPitch(PLANAR_U);
				dst_pitch = dst->GetPitch(PLANAR_U);
				xloops = ((src->GetRowSize(PLANAR_U_ALIGNED)+15) / 16)*16;  // Round to multiple of 16
				yOfs2 = this->yOfsUV;
				plane--; // skip case 0
				(((INT_PTR)srcp&15) || (src_pitch &15)) ? ua_proc_uvplane(srcp, dstp, src_pitch, dst_pitch, y, xloops, yOfs2, cur)
															:a_proc_uvplane(srcp, dstp, src_pitch, dst_pitch, y, xloops, yOfs2, cur);
			break;
			
			case 3: // Y plane for planar
				(((INT_PTR)srcp&15) || (src_pitch &15)) ? ua_proc_yplane(srcp, dstp, src_pitch, dst_pitch, y, xloops, yOfs2, cur)
															:a_proc_yplane(srcp, dstp, src_pitch, dst_pitch, y, xloops, yOfs2, cur);
			break;
			
			case 0: // Default for interleaved
				(((INT_PTR)srcp&15) || (src_pitch &15)) ? ua_proc_yplane(srcp, dstp, src_pitch, dst_pitch, y, xloops, yOfs2, cur)
															:a_proc_yplane(srcp, dstp, src_pitch, dst_pitch, y, xloops, yOfs2, cur);
			break;

			default:
				
			break;
		}
	}
	return dst;
}


FilteredResizeV::~FilteredResizeV(void)
{
  if (resampling_pattern) { _aligned_free(resampling_pattern); resampling_pattern = 0; }
  if (resampling_patternUV) { _aligned_free(resampling_patternUV); resampling_patternUV = 0; }
  if (yOfs) { delete[] yOfs; yOfs = 0; }
  if (yOfsUV) { delete[] yOfsUV; yOfsUV = 0; }
  if (ua_proc_yplane) {ua_proc_yplane=0;}
  if (a_proc_yplane) {a_proc_yplane=0;}
  if (ua_proc_uvplane) {ua_proc_uvplane=0;}
  if (a_proc_uvplane) {a_proc_uvplane=0;}
}



/**********************************************
 *******   Resampling Factory Methods   *******
 **********************************************/

PClip FilteredResize::CreateResizeH(PClip clip, double subrange_left, double subrange_width, int target_width,
                    ResamplingFunction* func, IScriptEnvironment* env)
{
	const VideoInfo& vi = clip->GetVideoInfo();
	if (subrange_left == 0 && subrange_width == target_width && subrange_width == vi.width)
		return clip;

	if (subrange_left == int(subrange_left) && subrange_width == target_width && subrange_left >= 0 && subrange_left + subrange_width <= vi.width)
	{
		if (((int(subrange_left) | int(subrange_width)) & 1) == 0)
			return new Crop(int(subrange_left), 0, int(subrange_width), vi.height, 0, clip, env);
    
		else if (!vi.IsYUY2() && !vi.IsYV12()) 
			return new Crop(int(subrange_left), 0, int(subrange_width), vi.height, 0, clip, env);
    
	}
	return new FilteredResizeH(clip, subrange_left, subrange_width, target_width, func, env);
}


PClip FilteredResize::CreateResizeV(PClip clip, double subrange_top, double subrange_height, int target_height,
                    ResamplingFunction* func, IScriptEnvironment* env)
{
	const VideoInfo& vi = clip->GetVideoInfo();
	if (subrange_top == 0 && subrange_height == target_height && subrange_height == vi.height)
		return clip;

	if ((subrange_top == int(subrange_top)) && (subrange_height == target_height) && (subrange_top >= 0) && ((subrange_top + subrange_height) <= vi.height)) 
	{
		if (((int(subrange_top) | int(subrange_height)) & 1) == 0) 
			return new Crop(0, int(subrange_top), vi.width, int(subrange_height), 0, clip, env);
    
		if (!vi.IsYV12())
			return new Crop(0, int(subrange_top), vi.width, int(subrange_height), 0, clip, env);
	}

	return new FilteredResizeV(clip, subrange_top, subrange_height, target_height, func, env);
}


PClip FilteredResize::CreateResize(PClip clip, int target_width, int target_height, const AVSValue* args,
                   ResamplingFunction* f, IScriptEnvironment* env)
{
	clip->SetCacheHints(CACHE_NOTHING, 0);
	try 
	{	// HIDE DAMN SEH COMPILER BUG!!!
		const VideoInfo& vi = clip->GetVideoInfo();
		const double subrange_left = args[0].AsFloat(0), subrange_top = args[1].AsFloat(0);

		double subrange_width = args[2].AsFloat(vi.width), subrange_height = args[3].AsFloat(vi.height);
		
		// Crop style syntax
		if (subrange_width  <= 0.0) subrange_width  = vi.width  - subrange_left + subrange_width;
		if (subrange_height <= 0.0) subrange_height = vi.height - subrange_top  + subrange_height;

		PClip result;
		// ensure that the intermediate area is maximal
		const double area_FirstH = subrange_height * target_width;
		const double area_FirstV = subrange_width * target_height;
		if (area_FirstH < area_FirstV)
		{
			result = CreateResizeV(clip, subrange_top, subrange_height, target_height, f, env);
			result = CreateResizeH(result, subrange_left, subrange_width, target_width, f, env);
		}
		else
		{
			result = CreateResizeH(clip, subrange_left, subrange_width, target_width, f, env);
			result = CreateResizeV(result, subrange_top, subrange_height, target_height, f, env);
		}
		return result;
	}
	catch (...) { throw; }
}

AVSValue __cdecl FilteredResize::Create_PointResize(AVSValue args, void*, IScriptEnvironment* env)
{
	return CreateResize( args[0].AsClip(), args[1].AsInt(), args[2].AsInt(), &args[3],
                       &PointFilter(), env );
}


AVSValue __cdecl FilteredResize::Create_BilinearResize(AVSValue args, void*, IScriptEnvironment* env)
{
	return CreateResize( args[0].AsClip(), args[1].AsInt(), args[2].AsInt(), &args[3],
                       &TriangleFilter(), env );
}


AVSValue __cdecl FilteredResize::Create_BicubicResize(AVSValue args, void*, IScriptEnvironment* env)
{
	return CreateResize( args[0].AsClip(), args[1].AsInt(), args[2].AsInt(), &args[5],
                       &MitchellNetravaliFilter(args[3].AsFloat(1./3.), args[4].AsFloat(1./3.)), env );
}

AVSValue __cdecl FilteredResize::Create_LanczosResize(AVSValue args, void*, IScriptEnvironment* env)
{
	try {	// HIDE DAMN SEH COMPILER BUG!!!
		return CreateResize( args[0].AsClip(), args[1].AsInt(), args[2].AsInt(), &args[3],
                       &LanczosFilter(args[7].AsInt(3)), env );
	}
	catch (...) { throw; }
}

AVSValue __cdecl FilteredResize::Create_Lanczos4Resize(AVSValue args, void*, IScriptEnvironment* env)
{
	try {	// HIDE DAMN SEH COMPILER BUG!!!
		return CreateResize( args[0].AsClip(), args[1].AsInt(), args[2].AsInt(), &args[3],
                       &LanczosFilter(4), env );
	}
	catch (...) { throw; }
}

AVSValue __cdecl FilteredResize::Create_BlackmanResize(AVSValue args, void*, IScriptEnvironment* env)
{
	try {	// HIDE DAMN SEH COMPILER BUG!!!
		return CreateResize( args[0].AsClip(), args[1].AsInt(), args[2].AsInt(), &args[3],
                       &BlackmanFilter(args[7].AsInt(4)), env );
	}
	catch (...) { throw; }
}

AVSValue __cdecl FilteredResize::Create_Spline16Resize(AVSValue args, void*, IScriptEnvironment* env)
{
	return CreateResize( args[0].AsClip(), args[1].AsInt(), args[2].AsInt(), &args[3],
                       &Spline16Filter(), env );
}

AVSValue __cdecl FilteredResize::Create_Spline36Resize(AVSValue args, void*, IScriptEnvironment* env)
{
	return CreateResize( args[0].AsClip(), args[1].AsInt(), args[2].AsInt(), &args[3],
                       &Spline36Filter(), env );
}

AVSValue __cdecl FilteredResize::Create_Spline64Resize(AVSValue args, void*, IScriptEnvironment* env)
{
	return CreateResize( args[0].AsClip(), args[1].AsInt(), args[2].AsInt(), &args[3],
                       &Spline64Filter(), env );
}

AVSValue __cdecl FilteredResize::Create_GaussianResize(AVSValue args, void*, IScriptEnvironment* env)
{
	try {	// HIDE DAMN SEH COMPILER BUG!!!
		return CreateResize( args[0].AsClip(), args[1].AsInt(), args[2].AsInt(), &args[3],
                       &GaussianFilter(args[7].AsFloat(30.0f)), env );
	}
	catch (...) { throw; }
}
