// server.cpp : Defines the entry point for the console application.
//

#include "stdafx.h"

#include <boost/interprocess/ipc/message_queue.hpp>
#include <iostream>
#include <vector>
#include <set>

#include "core/avisynth.h"
#include "core/avisynth_c.h"
#include "core/IPCMessages.h"

using namespace boost::interprocess;

typedef IScriptEnvironment* (__stdcall *CreateScriptEnvironmentFunction)(int version);

message_queue * pMqOut;

void SendValue(const AVSValue& val)
{
	if (val.IsString())
	{
		printf("%s;\n", val.AsString());
		char type = 's';
		pMqOut->send(&type, 1, 0);
		pMqOut->send(val.AsString(), strlen(val.AsString()) + 1, 0);
	}
	else if (val.IsClip())
	{
		char type = 'c';
		pMqOut->send(&type, 1, 0);

		PClip * save = new PClip(val.AsClip()); // save off a refcount
		int64 movie = (int64)save;
		pMqOut->send(&movie, sizeof(movie), 0);
	}
	else
	{
		char type = 'v';
		pMqOut->send(&type, 1, 0);
	}
}

int main ()
{
	SetCurrentDirectory(TEXT("C:\\Program Files\\AviSynth 2.5\\"));
	HMODULE aviSynth = LoadLibrary(TEXT("C:\\Program Files\\AviSynth 2.5\\avisynth.dll"));

	CreateScriptEnvironmentFunction CreateScriptEnvironment = (CreateScriptEnvironmentFunction)GetProcAddress(aviSynth, "CreateScriptEnvironment");
	std::set<IScriptEnvironment*> envs;

   try{
      //Open a message queue.
      message_queue mqIn
         (open_only        //only create
         ,"IPCScriptEnvironmentOut"  //name
         );
      message_queue mqOut
         (open_only        //only create
         ,"IPCScriptEnvironmentIn"  //name
         );

	  pMqOut = &mqOut;

      unsigned int priority;
      std::size_t recvd_size;

	  std::string dataBuffer;

      
	  while(true) {
         char buffer[280];
         mqIn.receive(&buffer, sizeof(buffer), recvd_size, priority);
		 Message * inMsg = reinterpret_cast<Message*>(buffer);

         if(recvd_size < sizeof(Message))
            return 1;

		 switch (inMsg->getKind())
		 {
			 case MSG_CREATESCRIPTENVIRONMENT:
			 {
					CreateScriptEnvironmentMessage * msg = static_cast<CreateScriptEnvironmentMessage*>(inMsg);

					IScriptEnvironment * env = 0;
					if (CreateScriptEnvironment)
					{
						env = (CreateScriptEnvironment)(msg->getVersion());
					}

					envs.insert(env);

					int64 clientEnv = (int64)env;
					mqOut.send(&clientEnv, sizeof(clientEnv), 0);
			 }
			 break;

			 case MSG_GETVAR:
				{
					GetVarMessage * msg = static_cast<GetVarMessage*>(inMsg);
					IScriptEnvironment * env = reinterpret_cast<IScriptEnvironment*>(msg->getScriptEnvironment());
					
					printf("GetVar('%s');\n", msg->getName());

					AVSValue val;
					try
					{
						if (envs.count(env))
						{
							val = env->GetVar(msg->getName());
						}
					} catch (IScriptEnvironment::NotFound) {
						// 
					}

					SendValue(val);
				}
				break;

				
			 case MSG_SETVAR:
				{
					SetVarMessage * msg = static_cast<SetVarMessage*>(inMsg);
					IScriptEnvironment * env = reinterpret_cast<IScriptEnvironment*>(msg->getScriptEnvironment());
					
					printf("SetVar('%s');\n", msg->getName());

					bool val = false;
					try
					{
						if (envs.count(env))
						{
							PClip * clip = reinterpret_cast<PClip*>(msg->getClip());
						
							val = env->SetVar(msg->getName(), *clip);
						}
					} catch (IScriptEnvironment::NotFound) {
						// 
					}

					char res = val ? 't' : 'f';
					mqOut.send(&res, 1, 0);
				}
				break;

			 case MSG_GETFRAME:
				{
					GetFrameMessage * msg = static_cast<GetFrameMessage*>(inMsg);
					IScriptEnvironment * env = reinterpret_cast<IScriptEnvironment*>(msg->getScriptEnvironment());
					
					printf("GetFrame(%d, %d);\n", msg->getClip(), msg->getFrame());

					try
					{
						if (envs.count(env))
						{
							PClip clip = * reinterpret_cast<PClip*>(msg->getClip());
							PVideoFrame pframe = clip->GetFrame(msg->getFrame(), env);
							VideoFrameBuffer * fb = pframe->GetFrameBuffer();

							  // sequence_number is incremented every time the buffer is changed, so
							  // that stale views can tell they're no longer valid.
							  long sequence_number = fb->GetSequenceNumber();
							  int data_size = fb->GetDataSize();

							  mqOut.send(&sequence_number, sizeof(sequence_number), 0);
							  mqOut.send(&data_size, sizeof(data_size), 0);
							  mqOut.send(fb->GetReadPtr(), fb->GetDataSize(), 0);
						}
					} catch (IScriptEnvironment::NotFound) {
						// 
					}
				}
				break;

			case MSG_CHECKVERSION:
				{
				}
				break;

			case MSG_SETWORKINGDIRECTORY:
				{
					SetWorkingDirectoryMessage * msg = static_cast<SetWorkingDirectoryMessage*>(inMsg);
					IScriptEnvironment * env = reinterpret_cast<IScriptEnvironment*>(msg->getScriptEnvironment());
		
					printf("SetWorkingDirectory('%s');\n", msg->getDirectory());

					if (envs.count(env))
					{
						int ret = env->SetWorkingDir(msg->getDirectory());
						mqOut.send(&ret, sizeof(ret), 0);
					}
				}
				break;

			case MSG_VIDEOINFO:
				{
					GetVideoInfoMessage * msg = static_cast<GetVideoInfoMessage*>(inMsg);
					IScriptEnvironment * env = reinterpret_cast<IScriptEnvironment*>(msg->getScriptEnvironment());
		
					printf("GetVideoInfo(%d);\n", msg->getClip());

					if (envs.count(env))
					{
						PClip clip = * reinterpret_cast<PClip*>(msg->getClip());
					
						VideoInfo vi = clip->GetVideoInfo();
						mqOut.send(&vi, sizeof(vi), 0);
					}
				}
				break;

			case MSG_SENDBUFFER:
				{
					SendBufferMessage * msg = static_cast<SendBufferMessage*>(inMsg);
					IScriptEnvironment * env = reinterpret_cast<IScriptEnvironment*>(msg->getScriptEnvironment());
		
					if (msg->getSize() == 0)
					{
						dataBuffer.clear();
					}

					dataBuffer.insert(dataBuffer.length(), 
						msg->getBuffer(), msg->getSize());
				}
				break;

			case MSG_INVOKE:
				{
					InvokeMessage * msg = static_cast<InvokeMessage*>(inMsg);
					IScriptEnvironment * env = reinterpret_cast<IScriptEnvironment*>(msg->getScriptEnvironment());
		
					printf("Invoke('%s');\n", msg->getName());

					if (stricmp(msg->getName(), "eval") == 0)
					{
						AVSValue v(dataBuffer.c_str());
						AVSValue args(&v, 1);
						AVSValue val;
						try
						{		
							if (envs.count(env))
							{
								val = env->Invoke(msg->getName(), args, 0);
							}
						} catch (AvisynthError err) {
							// 
							printf("\n");
						}

						dataBuffer.clear();
						SendValue(val);
					}
					else if (stricmp(msg->getName(), "converttorgb32") == 0)
					{
						AVSValue val;
						try
						{		
							if (envs.count(env))
							{
								PClip clip = * reinterpret_cast<PClip*>(msg->getClip());

								val = env->Invoke(msg->getName(), clip, 0);
							}
						} catch (AvisynthError err) {
							// 
							printf("\n");
						}

						SendValue(val);
					}
				}
				break;
		 }
      }
   }
   catch(interprocess_exception &ex){
      std::cout << ex.what() << std::endl;
      return 1;
   }
   return 0;
}

