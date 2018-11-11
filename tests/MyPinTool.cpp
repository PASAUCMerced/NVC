/*BEGIN_LEGAL
Intel Open Source License

Copyright (c) 2002-2015 Intel Corporation. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.  Redistributions
in binary form must reproduce the above copyright notice, this list of
conditions and the following disclaimer in the documentation and/or
other materials provided with the distribution.  Neither the name of
the Intel Corporation nor the names of its contributors may be used to
endorse or promote products derived from this software without
specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE INTEL OR
ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
END_LEGAL */

#include "pin.H"
#include <iostream>
#include <fstream>
#include <tuple>
#include <vector>
//#include <pair>
#include <unordered_map>
#include <string.h>
/* ===================================================================== */
/* Names of malloc and free */
/* ===================================================================== */
#if defined(TARGET_MAC)
#define START_CRASH "_start_crash"
#define RECORD "_record"
#define CRUCIAL_DATA "_crucial_data"
#define MALLOC "_malloc"
#define FREE "_free"
#define END_CRASH "_end_crash"
#else
#define START_CRASH "start_crash"
#define RECORD "record"
#define CRUCIAL_DATA "crucial_data"
#define MALLOC "malloc"
#define FREE "free"
#define END_CRASH "end_crash"
#endif

#define DOUBLE "double"
#define INT "int"
#define FLOAT "float"

typedef std::pair<ADDRINT, string> ADDRRANGE;
typedef std::unordered_map<ADDRINT,ADDRRANGE> ADDRCARE;
ADDRCARE address;
ADDRINT order_address[128];
UINT32 iteration=0;

BOOL computation = false;
UINT64 icount = 0;
/* ===================================================================== */
/* Global Variables */
/* ===================================================================== */

std::ofstream TraceFile;

/* ===================================================================== */
/* Commandline Switches */
/* ===================================================================== */

KNOB<string> KnobOutputFile(KNOB_MODE_WRITEONCE, "pintool",
    "o", "malloctrace.out", "specify trace file name");

/* ===================================================================== */


/* ===================================================================== */
/* Analysis routines                                                     */
/* ===================================================================== */

ADDRINT Arg1Before(ADDRINT size)
{
    //TraceFile << name << "(" << dec<<size << ")" << endl;
    return size;
}

VOID MallocAfter(ADDRINT size, ADDRINT ret)
{
  if(computation == false)
  {
    //TraceFile << "  returns " <<hex<<ret << endl;
    cout<<hex<<ret<<" "<<dec<<size<<endl;
    //char state[16] = "none";
    address.insert(std::make_pair(ret,std::make_pair(ret+size,"none")));
  }
}

VOID GetWhatWeCare(ADDRINT addr, CHAR * type, ADDRINT size)
{
  if(strcmp(type,DOUBLE) == 0)
  {
    size = size * 8;
  }
  else{
    size = size * 4;
  }
  address.insert(std::make_pair(addr,std::make_pair(addr+size,"none")));
  cout<<"insert "<<hex<<addr<<" : "<<dec<<size<<endl;
  order_address[iteration++] = addr;
}

VOID Arg2Before(CHAR * name, ADDRINT ret)
{
  if(computation == false)
  {
      cout << name<<" "<< hex<<ret << endl;
      address.erase(ret);
  }
}

VOID start()
{
    computation = true;
    cout<<"flip the flag!"<<endl;
    cout<<"When computation start, the data object num is "<<dec<<+address.size()<<endl;
}

VOID end()
{

    computation = false;
    //cout<<computation<<endl;
    cout<<"filp the flag"<<endl;
    cout<<"When computation end, the data object num is "<<dec<<+address.size()<<endl;
    int updated=0;
    for( auto& x: address)
    {
      cout<<hex<<x.first<<" "<<x.second.second<<endl;
      if(x.second.second == "updated")
      {
	   updated++;
      }
    }
    cout<<"Total updated object num is "<<dec<< updated<<endl;
   for(UINT32 i=0; i< iteration; i++)
   {
	auto search = address.find(order_address[i]);
        if (search != address.end()) {
	    cout<<hex<<search->first<<" "<<search->second.second<<endl;
	}
        else{
	  cout<<hex<<order_address[i]<<" error!"<<endl;
	}
   }

}

/*
VOID docount() {
  if(computation)
  {
     icount++;
	}
}*/

VOID write(ADDRINT addr)
{
    //cout<<"write in "<<hex<<addr<<end;
    if(computation)
    {
      for( auto& x: address)
      {
        if(addr >= x.first && addr <= x.second.first)
        {
          //cout<<"found one"<<endl;
          if(x.second.second != "updated")
          {
            x.second.second = "updated";
            cout<<hex<<x.first<<" has been updated!"<<endl;
          }
          break;
        }
      }
    }


    //for( auto& x: address)
    //{
      //if(x.second.second == "none")
        //return;
    //}
    //computation = false;
    //cout<<"All object is updated"<<endl;
    return;
}
/* ===================================================================== */
/* Instrumentation routines                                              */
/* ===================================================================== */

VOID Image(IMG img, VOID *v)
{
    // Instrument the malloc() and free() functions.  Print the input argument
    // of each malloc() or free(), and the return value of malloc().
    //
    //  Find the malloc() function.
    //cout<<"I found function call! "<<IMG_Name(img)<< endl;
    RTN mallocRtn = RTN_FindByName(img, MALLOC);
    if (RTN_Valid(mallocRtn))
    {
      //cout<<"I found start crash!"<<endl;
        RTN_Open(mallocRtn);

        // Instrument malloc() to print the input argument value and the return value.
        RTN_InsertCall(mallocRtn, IPOINT_BEFORE, (AFUNPTR)Arg1Before,
                       //IARG_ADDRINT, MALLOC,
                       IARG_FUNCARG_ENTRYPOINT_VALUE, 0,
                       IARG_RETURN_REGS, REG_INST_G0,
                       IARG_END);
        RTN_InsertCall(mallocRtn, IPOINT_AFTER, (AFUNPTR)MallocAfter,
                       IARG_REG_VALUE, REG_INST_G0,
                       IARG_FUNCRET_EXITPOINT_VALUE, IARG_END);

        RTN_Close(mallocRtn);

        // Instrument malloc() to print the input argument value and the return value.
        //RTN_InsertCall(mallocRtn, IPOINT_BEFORE, (AFUNPTR)Arg1Before,
        //               IARG_ADDRINT, MALLOC,
        //               IARG_FUNCARG_ENTRYPOINT_VALUE, 0,
        //               IARG_END);
        //cout<<"Open rtm!"<<endl;
        //  RTN_InsertCall(mallocRtn, IPOINT_BEFORE, (AFUNPTR)MallocAfter,
        //                IARG_END);
        //  RTN_Close(mallocRtn);
    }

    //RTN recordRtn = RTN_FindByName(img, RECORD);
    //if (RTN_Valid(recordRtn))
    //{
      //cout<<"I found start crash!"<<endl;
      //  RTN_Open(recordRtn);

        // Instrument malloc() to print the input argument value and the return value.
        //RTN_InsertCall(mallocRtn, IPOINT_BEFORE, (AFUNPTR)Arg1Before,
        //               IARG_ADDRINT, MALLOC,
        //               IARG_FUNCARG_ENTRYPOINT_VALUE, 0,
        //               IARG_END);
        //cout<<"Open rtm!"<<endl;
        //RTN_InsertCall(recordRtn, IPOINT_BEFORE, (AFUNPTR)GetWhatWeCare,
        //               IARG_FUNCARG_ENTRYPOINT_VALUE, 0,
        //               IARG_FUNCARG_ENTRYPOINT_VALUE, 1,
        //               IARG_FUNCARG_ENTRYPOINT_VALUE, 2,
        //               IARG_END);
        //RTN_Close(recordRtn);
    //}

    // Find the free() function.

    RTN freeRtn = RTN_FindByName(img, FREE);
    if (RTN_Valid(freeRtn))
    {
        RTN_Open(freeRtn);

        // Instrument free() to print the input argument value.
        RTN_InsertCall(freeRtn, IPOINT_BEFORE, (AFUNPTR)Arg2Before,
                       IARG_ADDRINT, FREE,
                       IARG_FUNCARG_ENTRYPOINT_VALUE, 0,
                       IARG_END);
        RTN_Close(freeRtn);
    }

    RTN startRtn = RTN_FindByName(img, START_CRASH);
    if (RTN_Valid(startRtn))
    {
        RTN_Open(startRtn);

        // Instrument free() to print the input argument value.
        RTN_InsertCall(startRtn, IPOINT_BEFORE, (AFUNPTR)start,
                       IARG_END);
        RTN_Close(startRtn);
    }

    RTN endRtn = RTN_FindByName(img, END_CRASH);
    if (RTN_Valid(endRtn))
    {
        RTN_Open(endRtn);

        // Instrument free() to print the input argument value.
        RTN_InsertCall(endRtn, IPOINT_BEFORE, (AFUNPTR)end,
                       IARG_END);
        RTN_Close(endRtn);
    }

    RTN criticalRtn = RTN_FindByName(img, CRUCIAL_DATA);
    if(RTN_Valid(criticalRtn)){
      RTN_Open(criticalRtn);

      // Instrument malloc() to print the input argument value and the return value.
      RTN_InsertCall(criticalRtn, IPOINT_BEFORE, (AFUNPTR)GetWhatWeCare,
                     IARG_FUNCARG_ENTRYPOINT_VALUE, 0,
                     IARG_FUNCARG_ENTRYPOINT_VALUE, 1,
                     IARG_FUNCARG_ENTRYPOINT_VALUE, 2,
                     IARG_END);

      RTN_Close(criticalRtn);
    }

}

VOID Instruction(INS ins, void * v){
  if (INS_IsMemoryWrite(ins))
  {
      INS_InsertCall(
        ins, IPOINT_BEFORE,
        AFUNPTR(write),
        IARG_MEMORYWRITE_EA,
        IARG_END);

  }
  //INS_InsertCall(ins, IPOINT_BEFORE, (AFUNPTR)docount, IARG_END);

}

/* ===================================================================== */

VOID Fini(INT32 code, VOID *v)
{
  TraceFile<<"Count "<<icount<<endl;
  TraceFile.close();
  cout<<"Count "<<icount<<endl;
}

/* ===================================================================== */
/* Print Help Message                                                    */
/* ===================================================================== */

INT32 Usage()
{
    cerr << "This tool produces a trace of calls to malloc." << endl;
    cerr << endl << KNOB_BASE::StringKnobSummary() << endl;
    return -1;
}

/* ===================================================================== */
/* Main                                                                  */
/* ===================================================================== */

int main(int argc, char *argv[])
{
    // Initialize pin & symbol manager
    PIN_InitSymbols();
    if( PIN_Init(argc,argv) )
    {
        return Usage();
    }

    // Write to a file since cout and cerr maybe closed by the application
    TraceFile.open(KnobOutputFile.Value().c_str());
    TraceFile << hex;
    TraceFile.setf(ios::showbase);

    // Register Image to be called to instrument functions.
    IMG_AddInstrumentFunction(Image, 0);
    INS_AddInstrumentFunction(Instruction, 0);
    PIN_AddFiniFunction(Fini, 0);

    // Never returns
    PIN_StartProgram();

    return 0;
}

/* ===================================================================== */
/* eof */
/* ===================================================================== */

