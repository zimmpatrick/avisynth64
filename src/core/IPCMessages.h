
#pragma once

#define MSG_CHECKVERSION 1
#define MSG_GETVAR 2

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

class CheckVersionMessage : public Message
{
public:
	CheckVersionMessage(int version)
		: Message(MSG_CHECKVERSION), version(version)
	{
	}

	int getVersion() const { return version; }

private:
	int version;
};

class GetVarMessage : public Message
{
public:
	GetVarMessage(const char * name)
		: Message(MSG_GETVAR)
	{
		size_t size = strlen(name);
		if (size > 24) throw AvisynthError("Variables must be 24 characters or less");

		strcpy(this->name, name);
	}

	const char * getName() const { return name; }

private:
	char name[25];
};
