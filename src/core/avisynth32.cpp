
// Avisynth v2.5.  Copyright 2007 Ben Rudiak-Gould et al.
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

#pragma once

#include "../stdafx.h"

#include <stdarg.h>

#include <string>
using std::string;

#include "../internal.h"
//#include "convert/convert.h"
#include "filters/video/focus.h"

#include <boost/interprocess/ipc/message_queue.hpp>
#include <iostream>
#include <vector>
#include <set>

using namespace boost::interprocess;

#include "IPCMessages.h"


void* VideoFrame::operator new(size_t size) {
	VideoFrame * data = (VideoFrame*)new BYTE[size];
	data->refcount = 1;
	return data;
}


VideoFrame::VideoFrame(VideoFrameBuffer* _vfb, int _offset, int _pitch, int _row_size, int _height)
  : /*refcount(1),*/ vfb(_vfb), offset(_offset), pitch(_pitch), row_size(_row_size), height(_height),
    offsetU(_offset),offsetV(_offset),pitchUV(0)  // PitchUV=0 so this doesn't take up additional space
{
  InterlockedIncrement(&vfb->refcount);
}

VideoFrame::VideoFrame(VideoFrameBuffer* _vfb, int _offset, int _pitch, int _row_size, int _height,
                       int _offsetU, int _offsetV, int _pitchUV)
  : /*refcount(1),*/ vfb(_vfb), offset(_offset), pitch(_pitch), row_size(_row_size), height(_height),
    offsetU(_offsetU),offsetV(_offsetV),pitchUV(_pitchUV)
{
  InterlockedIncrement(&vfb->refcount);
}

VideoFrame* VideoFrame::Subframe(int rel_offset, int new_pitch, int new_row_size, int new_height) const {
    VideoFrame* Retval= new VideoFrame(vfb, offset+rel_offset, new_pitch, new_row_size, new_height);
	InterlockedDecrement(&Retval->refcount);//This is not threadsafe so filters should use IScriptEnviroment->Subframe instead
	return Retval;
}


VideoFrame* VideoFrame::Subframe(int rel_offset, int new_pitch, int new_row_size, int new_height,
                                 int rel_offsetU, int rel_offsetV, int new_pitchUV) const {
    VideoFrame* Retval= new VideoFrame(vfb, offset+rel_offset, new_pitch, new_row_size, new_height, rel_offsetU+offsetU, rel_offsetV+offsetV, new_pitchUV);
	InterlockedDecrement(&Retval->refcount);//This is not threadsafe so filters should use IScriptEnviroment->Subframe instead
	return Retval;
}


VideoFrameBuffer::VideoFrameBuffer() : refcount(1), data(0), data_size(0), sequence_number(0) {}


#ifdef _DEBUG  // Add 16 guard bytes front and back -- cache can check them after every GetFrame() call
VideoFrameBuffer::VideoFrameBuffer(int size) : 
  refcount(1), 
  data((new BYTE[size+32])+16), 
  data_size(data ? size : 0), 
  sequence_number(0) {
  InterlockedIncrement(&sequence_number); 
  int *p=(int *)data;
  p[-4] = 0xDEADBEAF;
  p[-3] = 0xDEADBEAF;
  p[-2] = 0xDEADBEAF;
  p[-1] = 0xDEADBEAF;
  p=(int *)(data+size);
  p[0] = 0xDEADBEAF;
  p[1] = 0xDEADBEAF;
  p[2] = 0xDEADBEAF;
  p[3] = 0xDEADBEAF;
}

VideoFrameBuffer::~VideoFrameBuffer() {
//  _ASSERTE(refcount == 0);
  InterlockedIncrement(&sequence_number); // HACK : Notify any children with a pointer, this buffer has changed!!!
  if (data) delete[] (BYTE*)(data-16);
  (BYTE*)data = 0; // and mark it invalid!!
  (int)data_size = 0;   // and don't forget to set the size to 0 as well!
}

#else

VideoFrameBuffer::VideoFrameBuffer(int size)
 : refcount(1), data(new BYTE[size]), data_size(data ? size : 0), sequence_number(0) { InterlockedIncrement(&sequence_number); }

VideoFrameBuffer::~VideoFrameBuffer() {
//  _ASSERTE(refcount == 0);
  InterlockedIncrement(&sequence_number); // HACK : Notify any children with a pointer, this buffer has changed!!!
  if (data) delete[] data;
  (BYTE*)data = 0; // and mark it invalid!!
  (int)data_size = 0;   // and don't forget to set the size to 0 as well!
}
#endif


enum {
    COLOR_MODE_RGB = 0,
    COLOR_MODE_YUV
};


class StaticImage : public IClip {
  const VideoInfo vi;
  const PVideoFrame frame;
  bool parity;

public:
  StaticImage(const VideoInfo& _vi, const PVideoFrame& _frame, bool _parity)
    : vi(_vi), frame(_frame), parity(_parity) {}
  PVideoFrame __stdcall GetFrame(int n, IScriptEnvironment* env) { return frame; }
  void __stdcall GetAudio(void* buf, __int64 start, __int64 count, IScriptEnvironment* env) {
    memset(buf, 0, vi.BytesFromAudioSamples(count));
  }
  const VideoInfo& __stdcall GetVideoInfo() { return vi; }
  bool __stdcall GetParity(int n) { return (vi.IsFieldBased() ? (n&1) : false) ^ parity; }
  void __stdcall SetCacheHints(int cachehints,int frame_range) { };
};


static PVideoFrame CreateBlankFrame(const VideoInfo& vi, int color, int mode, IScriptEnvironment* env) {

  if (!vi.HasVideo()) return 0;

  PVideoFrame frame = env->NewVideoFrame(vi);
  BYTE* p = frame->GetWritePtr();
  int size = frame->GetPitch() * frame->GetHeight();

  if (vi.IsPlanar()) {
    int color_yuv =(mode == COLOR_MODE_YUV) ? color : RGB2YUV(color);
    int Cval = (color_yuv>>16)&0xff;
    Cval |= (Cval<<8)|(Cval<<16)|(Cval<<24);
    for (int i=0; i<size; i+=4)
      *(unsigned*)(p+i) = Cval;
    p = frame->GetWritePtr(PLANAR_U);
    size = frame->GetPitch(PLANAR_U) * frame->GetHeight(PLANAR_U);
    Cval = (color_yuv>>8)&0xff;
    Cval |= (Cval<<8)|(Cval<<16)|(Cval<<24);
    for (int i=0; i<size; i+=4)
      *(unsigned*)(p+i) = Cval;
    size = frame->GetPitch(PLANAR_V) * frame->GetHeight(PLANAR_V);
    p = frame->GetWritePtr(PLANAR_V);
    Cval = (color_yuv)&0xff;
    Cval |= (Cval<<8)|(Cval<<16)|(Cval<<24);
    for (int i=0; i<size; i+=4)
      *(unsigned*)(p+i) = Cval;
  } else if (vi.IsYUY2()) {
    int color_yuv =(mode == COLOR_MODE_YUV) ? color : RGB2YUV(color);
    unsigned d = ((color_yuv>>16)&255) * 0x010001 + ((color_yuv>>8)&255) * 0x0100 + (color_yuv&255) * 0x01000000;
    for (int i=0; i<size; i+=4)
      *(unsigned*)(p+i) = d;
  } else if (vi.IsRGB24()) {
    const unsigned char clr0 = (color & 0xFF);
    const unsigned short clr1 = (color >> 8);
    const int gr = frame->GetRowSize();
    const int gp = frame->GetPitch();
    for (int y=frame->GetHeight();y>0;y--) {
      for (int i=0; i<gr; i+=3) {
        p[i] = clr0; *(unsigned __int16*)(p+i+1) = clr1;
      }
      p+=gp;
    }
  } else if (vi.IsRGB32()) {
    for (int i=0; i<size; i+=4)
      *(unsigned*)(p+i) = color;
  }
  return frame;
}

static AVSValue __cdecl Create_BlankClip(IScriptEnvironment* env) {
  VideoInfo vi;
  memset(&vi, 0, sizeof(VideoInfo));
  vi.fps_denominator=1;
  vi.fps_numerator=24;
  vi.height=480;
  vi.pixel_type=VideoInfo::CS_BGR32;
  vi.num_frames=240;
  vi.width=640;
  vi.audio_samples_per_second=44100;
  vi.nchannels=1;
  vi.num_audio_samples=44100*10;
  vi.sample_type=SAMPLE_INT16;
  vi.SetFieldBased(false);
  bool parity=false;

  vi.width++; // cheat HasVideo() call for Audio Only clips
  vi.num_audio_samples = vi.AudioSamplesFromFrames(vi.num_frames);
  vi.width--;

  int color = 0;
  int mode = COLOR_MODE_RGB;

  return new StaticImage(vi, CreateBlankFrame(vi, color, mode, env), parity);
}

class ScriptEnvironment;

class ProxyClip : public IClip {
public:
	ProxyClip(int64 clip, ScriptEnvironment* env);
	virtual ~ProxyClip();

	virtual PVideoFrame __stdcall GetFrame(int n, IScriptEnvironment* env);
	virtual bool __stdcall GetParity(int n);
	virtual void __stdcall GetAudio(void* buf, __int64 start, __int64 count, IScriptEnvironment* env);	
	virtual void __stdcall SetCacheHints(int cachehints,int frame_range);
	virtual const VideoInfo& __stdcall GetVideoInfo();

	int64 __stdcall ServerClip();

private:
	int64 clip;
	ScriptEnvironment * env;
	VideoInfo vi;
};

class ScriptEnvironment : public IScriptEnvironment
{
public:
	ScriptEnvironment(int version)
	{
		static int refcount = 0;
		if (refcount++ == 0) // TODO : ThreadSafe
		{

			// Erase previous message queue
			message_queue::remove("IPCScriptEnvironmentOut");
			message_queue::remove("IPCScriptEnvironmentIn");

			//Create a message_queue.
			mqOut = new message_queue(create_only  //only create
				,"IPCScriptEnvironmentOut"		//name
				,100							//max message number
				,280								//max message size
				);

			//Create a message_queue.
			mqIn = new message_queue(create_only  //only create
				,"IPCScriptEnvironmentIn"		//name
				,20							//max message number
				,4194368								//max message size
				);
		}
		else
		{
			mqOut = new message_queue(
				open_only        //only create
				,"IPCScriptEnvironmentOut"  //name
				);

			mqIn = new message_queue(
				open_only        //only create
				,"IPCScriptEnvironmentIn"  //name
				);
		}

		CreateScriptEnvironmentMessage msg(version);
		SendMessage(&msg, sizeof(msg));

		msg_buffer = malloc(4194368);
		env = ReadInt64Message();
	}

	~ScriptEnvironment()
	{
		delete mqIn;
		delete mqOut;

		free(msg_buffer);
		msg_buffer = 0;
	}

	void __stdcall CheckVersion(int version)
	{
		CheckVersionMessage msg(env, version);
		SendMessage(&msg, sizeof(msg));
	}

	long __stdcall GetCPUFlags()
	{
		return 0;
	}

	char* __stdcall SaveString(const char* s, int length = -1)
	{
		std::set<const char *, ltstr>::iterator it = mLocalStrings.find(s);
		if (it != mLocalStrings.end()) return const_cast<char*>(*it);

		char * result = strdup(s);
		mLocalStrings.insert(result);

		return result;
	}

	char* __stdcall Sprintf(const char* fmt, ...)
	{
		return 0;
	}

	char* __stdcall VSprintf(const char* fmt, void* val)
	{
		return 0;
	}

	void __stdcall ThrowError(const char* fmt, ...)
	{
	}

	void __stdcall AddFunction(const char* name, const char* params, ApplyFunc apply, void* user_data=0)
	{
	}

	bool __stdcall FunctionExists(const char* name)
	{
		return false;
	}

	AVSValue __stdcall Invoke(const char* name, const AVSValue args, const char** arg_names=0)
	{
		if (stricmp(name, "eval") == 0)
		{
			const char * buffer = args[0].AsString();
			int size = strlen(buffer);

			SendBufferMessage bmsg1(env, NULL, 0);
			SendMessage(&bmsg1, sizeof(bmsg1));

			while(size > 0)
			{
				int sent = min(size, 256);
				SendBufferMessage bmsg(env, buffer, sent);
				SendMessage(&bmsg, sizeof(bmsg));

				buffer += sent;
				size -= sent;
			}

			InvokeMessage msg(env, name);
			SendMessage(&msg, sizeof(msg));
			
			return ReadValue();
		}
		else if (stricmp(name, "converttorgb32") == 0)
		{
			ProxyClip * clip = static_cast<ProxyClip*>((void*)args.AsClip());

			InvokeMessage msg(env, name, clip->ServerClip());
			SendMessage(&msg, sizeof(msg));
			
			return ReadValue();
		}
	}

	AVSValue __stdcall GetVar(const char* name)
	{
		GetVarMessage msg(env, name);
		SendMessage(&msg, sizeof(msg));

		return ReadValue();
	}

	bool __stdcall SetVar(const char* name, const AVSValue& val)
	{
		ProxyClip * clip = static_cast<ProxyClip*>((void*)val.AsClip());

		SetVarMessage msg(env, name, clip->ServerClip());
		SendMessage(&msg, sizeof(msg));
		
		size_t read;
		char * buffer = ReadStringMessage(read);
		return (buffer[0] == 't');
	}

	bool __stdcall SetGlobalVar(const char* name, const AVSValue& val)
	{
		return false;
	}

	void __stdcall PushContext(int level=0)
	{
	}

	void __stdcall PopContext()
	{
	}

	void __stdcall PopContextGlobal()
	{
	}

	PVideoFrame __stdcall NewVideoFrame(const VideoInfo& vi, int align)
	{
		  // Check requested pixel_type:
  switch (vi.pixel_type) {
    case VideoInfo::CS_BGR24:
    case VideoInfo::CS_BGR32:
    case VideoInfo::CS_YUY2:
    case VideoInfo::CS_YV12:
    case VideoInfo::CS_I420:
      break;
    default:
      ThrowError("Filter Error: Filter attempted to create VideoFrame with invalid pixel_type.");
  }
  PVideoFrame retval;
  // If align is negative, it will be forced, if not it may be made bigger
  if (vi.IsPlanar()) { // Planar requires different math ;)
    if (align>=0) {
      align = max(align,FRAME_ALIGN);
    }
    if ((vi.height&1)||(vi.width&1))
      ThrowError("Filter Error: Attempted to request an YV12 frame that wasn't mod2 in width and height!");
    retval=NewPlanarVideoFrame(vi.width, vi.height, align, !vi.IsVPlaneFirst());  // If planar, maybe swap U&V
  } else {
    if ((vi.width&1)&&(vi.IsYUY2()))
      ThrowError("Filter Error: Attempted to request an YUY2 frame that wasn't mod2 in width.");
    if (align<0) {
      align *= -1;
    } else {
      align = max(align,FRAME_ALIGN);
    }
    retval=NewVideoFrame(vi.RowSize(), vi.height, align);
  }
  InterlockedDecrement(&retval->vfb->refcount);//After the VideoFrame has been assigned to a PVideoFrame it is safe to decrement the refcount (from 2 to 1)
  InterlockedDecrement(&retval->refcount);
  return retval;
	}


VideoFrameBuffer* ScriptEnvironment::GetFrameBuffer(int size) {
	return new VideoFrameBuffer(size);
}

	PVideoFrame NewVideoFrame(int row_size, int height, int align)
	{
	  const int pitch = (row_size+align-1) / align * align;
	  const int size = pitch * height;
	  const int _align = (align < FRAME_ALIGN) ? FRAME_ALIGN : align;
	  VideoFrameBuffer* vfb = GetFrameBuffer(size+(_align*4));
	  if (!vfb)
		ThrowError("NewVideoFrame: Returned 0 image pointer!");
	#ifdef _DEBUG
	  {
		static const BYTE filler[] = { 0x0A, 0x11, 0x0C, 0xA7, 0xED };
		BYTE* p = vfb->GetWritePtr();
		BYTE* q = p + vfb->GetDataSize()/5*5;
		for (; p<q; p+=5) {
		  p[0]=filler[0]; p[1]=filler[1]; p[2]=filler[2]; p[3]=filler[3]; p[4]=filler[4];
		}
	  }
	#endif
	  const int offset = (-(INT_PTR)(vfb->GetWritePtr())) & (FRAME_ALIGN-1);  // align first line offset  (alignment is free here!)
	  return new VideoFrame(vfb, offset, pitch, row_size, height);
	}

	PVideoFrame NewPlanarVideoFrame(int width, int height, int align, bool U_first)
	{
		return 0;
	}

	bool __stdcall MakeWritable(PVideoFrame* pvf)
	{
		return false;
	}

	void __stdcall BitBlt(BYTE* dstp, int dst_pitch, const BYTE* srcp, int src_pitch, int row_size, int height)
	{
		::BitBlt(dstp, dst_pitch, srcp, src_pitch, row_size, height);
	}

	void __stdcall AtExit(IScriptEnvironment::ShutdownFunc function, void* user_data)
	{
	}

	PVideoFrame __stdcall Subframe(PVideoFrame src, int rel_offset, int new_pitch, int new_row_size, int new_height)
	{
		return 0;
	}

	int __stdcall SetMemoryMax(int mem)
	{
		return 0;
	}

	int __stdcall SetWorkingDir(const char * newdir)
	{
		SetWorkingDirectoryMessage msg(env, newdir);
		SendMessage(&msg, sizeof(msg));

		int result = ReadIntMessage();
		return result;
	}

	void* __stdcall ManageCache(int key, void* data)
	{
		return 0;
	}

	bool __stdcall PlanarChromaAlignment(IScriptEnvironment::PlanarChromaAlignmentMode key)
	{
		return false;
	}

	PVideoFrame __stdcall SubframePlanar(PVideoFrame src, int rel_offset, int new_pitch, int new_row_size, int new_height, int rel_offsetU, int rel_offsetV, int new_pitchUV)
	{
		return 0;
	}

	void __stdcall SetMTMode(int mode,int threads, bool temporary)
	{
	}

	int __stdcall  GetMTMode(bool return_nthreads)
	{
		return 0;
	}

	IClipLocalStorage*  __stdcall AllocClipLocalStorage()
	{
		return 0;
	}

	void __stdcall SaveClipLocalStorage()
	{
	}

	void __stdcall RestoreClipLocalStorage()
	{
	}

	VideoInfo GetVideoInfo(ProxyClip * clip)
	{
		GetVideoInfoMessage msg(env, clip->ServerClip());
		SendMessage(&msg, sizeof(msg));

		size_t read;
		VideoInfo vi = *(VideoInfo *)ReadMessage(read);
		assert(read == sizeof(vi));
		return vi;
	}

	PVideoFrame GetFrame(ProxyClip * clip, int n)
	{
		VideoInfo vi = clip->GetVideoInfo();

		GetFrameMessage msg(env, clip->ServerClip(), n);
		SendMessage(&msg, sizeof(msg));
		
		size_t read;
		unsigned int priotity;

		int seq = ReadIntMessage();
		int size = ReadIntMessage();

		PVideoFrame frame = NewVideoFrame(vi, 0);
		mqIn->receive(frame->GetWritePtr(), 4194368, read, priotity);
		assert(read == size);
		frame->vfb->sequence_number = seq;

		return frame;
	}

	bool GetParity(ProxyClip * clip, int n)
	{
		// TODO
		return false;
	}

private:
	void * ReadMessage(size_t & read)
	{
		unsigned int priotity;
		mqIn->receive(msg_buffer, 4194368, read, priotity);
		return msg_buffer;
	}

	char * ReadStringMessage(size_t & read)
	{
		return (char *)ReadMessage(read);
	}
	
	int64 ReadInt64Message()
	{
		struct Int64Message
		{
			int64 data;
		};

		size_t read;
		Int64Message * message = (Int64Message *)ReadMessage(read);
		assert(read == 8);
		return message->data;
	}

	int ReadIntMessage()
	{
		struct IntMessage
		{
			int data;
		};

		size_t read;
		IntMessage * message = (IntMessage *)ReadMessage(read);
		assert(read == 4);
		return message->data;
	}

	void SendMessage(Message * msg, size_t size)
	{
		char buffer[2048];
		sprintf(buffer, "Sending message: %s\n", typeid(msg).name());
		OutputDebugStr(buffer);

		mqOut->send(msg, size, 0);
	}


	AVSValue ReadValue()
	{
		size_t read;
		char * buffer = ReadStringMessage(read);
		if (buffer[0] == 's')
		{
			buffer = ReadStringMessage(read);
			return AVSValue(buffer);
		}
		else if (buffer[0] == 'c')
		{
			int64 movie = ReadInt64Message();
			return AVSValue(new ProxyClip(movie, this));
		}

		return AVSValue();
	}

private:
	struct ltstr
	{
	  bool operator()(const char* s1, const char* s2) const
	  {
		return strcmp(s1, s2) < 0;
	  }
	};

	message_queue * mqOut;
	message_queue * mqIn;
	std::map<const char *, int64> mqStringMap;
	std::set<const char *, ltstr> mLocalStrings;
	int64 env;
	void * msg_buffer;
};

IScriptEnvironment* __stdcall CreateScriptEnvironment(int version) {
	return new ScriptEnvironment(version);
}

void BitBlt(BYTE* dstp, int dst_pitch, const BYTE* srcp, int src_pitch, int row_size, int height) {
	if ( (!height)|| (!row_size)) return;
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





ProxyClip::ProxyClip(int64 clip, ScriptEnvironment* env)
{
	this->clip = clip;
	this->env = env;
}

ProxyClip::~ProxyClip()
{
	// release from server
}

PVideoFrame __stdcall ProxyClip::GetFrame(int n, IScriptEnvironment* env)
{
	assert(env == this->env);

	return this->env->GetFrame(this, n);
}

bool __stdcall ProxyClip::GetParity(int n)
{
	return env->GetParity(this, n);
}

void __stdcall ProxyClip::GetAudio(void* buf, __int64 start, __int64 count, IScriptEnvironment* env)
{
}
	
void __stdcall ProxyClip::SetCacheHints(int cachehints, int frame_range)
{
}

const VideoInfo& __stdcall ProxyClip::GetVideoInfo()
{
	vi = env->GetVideoInfo(this);
	return vi;
}

int64 __stdcall ProxyClip::ServerClip()
{
	return clip;
}
