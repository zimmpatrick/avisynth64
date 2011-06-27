
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

#include <boost/interprocess/ipc/message_queue.hpp>
#include <iostream>
#include <vector>

using namespace boost::interprocess;

#include "IPCMessages.h"

class IPCScriptEnvironment : public IScriptEnvironment
{
public:
	IPCScriptEnvironment()
	{
		// Erase previous message queue
		message_queue::remove("IPCScriptEnvironment");

		//Create a message_queue.
		mq = new message_queue(create_only  //only create
			,"IPCScriptEnvironment"			//name
			,100							//max message number
			,32								//max message size
			);
	}

	~IPCScriptEnvironment()
	{
		delete mq;
	}

	void __stdcall CheckVersion(int version)
	{
		CheckVersionMessage msg(version);
		SendMessage(&msg, sizeof(msg));
	}

	long __stdcall GetCPUFlags()
	{
		return 0;
	}

	char* __stdcall SaveString(const char* s, int length = -1)
	{
		return 0;
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
		return AVSValue();
	}

	AVSValue __stdcall GetVar(const char* name)
	{
		GetVarMessage msg(name);
		SendMessage(&msg, sizeof(msg));

		return AVSValue();
	}

	bool __stdcall SetVar(const char* name, const AVSValue& val)
	{
		return false;
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
		return 0;
	}

	PVideoFrame NewVideoFrame(int row_size, int height, int align)
	{
		return 0;
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
		return 0;
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

private:
	void SendMessage(Message * msg, size_t size)
	{
		mq->send(msg, size, 0);
	}

private:
	message_queue * mq;
};

IScriptEnvironment* __stdcall CreateScriptEnvironment(int version) {

	/*try{

	//Send 100 numbers
	for(int i = 0; i < 100; ++i){

	}
	}
	catch(interprocess_exception &ex){
	std::cout << ex.what() << std::endl;
	return 0;
	}
	*/

	return new IPCScriptEnvironment();

	return 0;
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