// server.cpp : Defines the entry point for the console application.
//

#include "stdafx.h"

#include <boost/interprocess/ipc/message_queue.hpp>
#include <iostream>
#include <vector>

#include "core/avisynth.h"
#include "core/avisynth_c.h"
#include "core/IPCMessages.h"

using namespace boost::interprocess;

typedef IScriptEnvironment* (__stdcall *CreateScriptEnvironmentFunction)(int version);

int main ()
{
	HMODULE aviSynth = LoadLibrary(TEXT("C:\\Program Files\\AviSynth 2.5\\avisynth.dll"));

	CreateScriptEnvironmentFunction CreateScriptEnvironment = (CreateScriptEnvironmentFunction)GetProcAddress(aviSynth, "CreateScriptEnvironment");

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

      unsigned int priority;
      std::size_t recvd_size;


      
	  while(true) {
         char buffer[128];
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

					int64 clientEnv = (int64)env;
					mqOut.send(&clientEnv, sizeof(clientEnv), 0);
			 }
			 break;

			 case MSG_GETVAR:
				{
					GetVarMessage * msg = static_cast<GetVarMessage*>(inMsg);
					IScriptEnvironment * env = reinterpret_cast<IScriptEnvironment*>(msg->getScriptEnvironment());

					printf("GetVar('%s');\n", msg->getName());

					AVSValue val = env->GetVar(msg->getName());

					printf("%s;\n", val.AsString());
					mqOut.send(val.AsString(), strlen(val.AsString()) + 1, 0);

				}
				break;

			case MSG_CHECKVERSION:
				{
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

