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

#pragma once

#define MSG_CHECKVERSION			1
#define MSG_GETVAR					2
#define MSG_CREATESCRIPTENVIRONMENT 3

typedef __int64 int64;

class Message
{
public:
	Message(int kind)
		: kind(kind)
	{
	}

	int getKind() const { return kind; }

private:
	int kind;
};

class CreateScriptEnvironmentMessage : public Message
{
public:
	CreateScriptEnvironmentMessage(int version)
		: Message(MSG_CREATESCRIPTENVIRONMENT), version(version)
	{
	}

	int getVersion() const { return version; }

private:
	int version;
};

class CheckVersionMessage : public Message
{
public:
	CheckVersionMessage(int64 env, int version)
		: Message(MSG_CHECKVERSION), env(env), version(version)
	{
	}

	int getVersion() const { return version; }
	int64 getScriptEnvironment() const { return env; }

private:
	int version;
	int64 env;
};

class GetVarMessage : public Message
{
public:
	GetVarMessage(int64 env, const char * name)
		: Message(MSG_GETVAR), env(env)
	{
		size_t size = strlen(name);
		if (size > 64) throw AvisynthError("Variables must be 64 characters or less");

		strcpy(this->name, name);
	}

	const char * getName() const { return name; }
	int64 getScriptEnvironment() const { return env; }

private:
	char name[65];
	int64 env;
};
