// @COPYRIGHT@
// Licensed under MIT license.
// See LMEMENSE.TXT file in the project root for more information.
// ==============================================================

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <iostream>
#include <unistd.h>
#include <assert.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <sstream>
#include <time.h>
#include "pin.H"
#include "cctlib.H"
#include "random.H"
typedef UINT64 CACHE_STATS; // type of cache hit/miss counters

#include "private_cache.H"
using namespace std;
using namespace PinCCTLib;

#include <unordered_set>
#include <vector>
#include <unordered_map>
#include <algorithm>
#include <boost/tuple/tuple.hpp>

#if defined(TARGET_MAC)
#define FLUSH_WHOLE_CACHE "_flush_whole_cache"
#define FLUSH "_clflush"
#define CONSISTENT_DATA "_consistent_data"
#define CRUCIAL_DATA "_crucial_data"
#define READONLY_DATA "_readonly_data"
#define CRUSH_START "_start_crash"
#define CRUSH_END "_end_crash"
#else
#define FLUSH_WHOLE_CACHE "flush_whole_cache"
#define FLUSH "clflush"
#define CONSISTENT_DATA "consistent_data"
#define CRUCIAL_DATA "crucial_data"
#define READONLY_DATA "readonly_data"
#define CRUSH_START "start_crash"
#define CRUSH_END "end_crash"
#endif
// if seperate CG into 5 phases
// CG class = S 3 iteration 48743061 all 235489608
// CG class = A 3 iteration 1081210628
// CG class = B 15 iteration 36820077353 all 193008895984
// CG class = C 15 iteration 96185361500 all 504839046451
// CG class = D/E
//453981865
//#define INS_MAX 91913574283;
const UINT64 INS_MAX = 54197099359;
//#define MAX_FILE_PATH 128
#define DOUBLE "double"
#define INT "int"
#define Long2 "long long"
#define MAX_THREAD_NUM 8

typedef UINT8 Byte;
typedef boost::tuple<ADDRINT, ADDRINT, CHAR *> ADDRRANGE;
typedef vector<ADDRRANGE> ADDRCARE;
typedef vector<ADDRINT> CONSISTENT_VARIABLE;
typedef std::pair<UINT32,UINT32> DIS;

ADDRCARE readonlydata;
ADDRCARE crucialdata;
CONSISTENT_VARIABLE consistent_variable;

static UINT64 icount = 0;
static UINT64 rand_crush = 0;
static bool crush_flag = false;
UINT8 threadnum;
UINT8 pcachenum;

//for output result
UINT32 crash_line = 0;

//General info for simulator, debug propose
FILE *gInfoFile;

ContextHandle_t Ctxthndl;

/* Other footprint_client settings */
#define MAX_FOOTPRINT_CONTEXTS_TO_LOG (10000)


struct node_metric_t {
  unordered_set<uint64_t> addressSet;
  unordered_set<uint64_t> addressSetDecoded;
  //uint64_t accessNum;
  //uint64_t dependentNum;
};

struct sort_format_t {
  ContextHandle_t handle;
  uint64_t footprint;
  uint64_t fpNum;
  //uint64_t accessNum;
  //uint64_t dependentNum;
};


#define THREAD_MAX (1024)
unordered_map<uint32_t, struct node_metric_t> hmap_vector[THREAD_MAX];

INT32 Usage2() {
    PIN_ERROR("Pin tool to gather calling context on each load and store.\n" + KNOB_BASE::StringKnobSummary() + "\n");
    return -1;
}

// Main for DeadSpy, initialize the tool, register instrumentation functions and call the target program.
FILE* gTraceFile;

struct timeval tv1;
__thread struct timeval tv2;
__thread struct timeval tv3;
struct timeval tv4;

std::ofstream TraceFile;

KNOB<string> KnobOutputFile(KNOB_MODE_WRITEONCE, "pintool",
    "o", "malloctrace.out", "specify trace file name");

KNOB<UINT32>   KnobThreadNum(KNOB_MODE_WRITEONCE, "pintool",
    "-t", "1", "how many thread using in application");

KNOB<UINT32>   KnobPrivateCacheNum(KNOB_MODE_WRITEONCE, "pintool",
    "-p", "1", "private cache num, atmost two thread have one private cache");

KNOB<UINT32>   KnobCacheL1Size(KNOB_MODE_WRITEONCE, "pintool",
    "-s1", "256", "l1 cache size in kilobytes");

KNOB<UINT32>   KnobCacheL1Associativity(KNOB_MODE_WRITEONCE, "pintool",
    "-a1", "8", "l1 cache associativity (1 for direct mapped)");

KNOB<UINT32>   KnobCacheL1LineSize(KNOB_MODE_WRITEONCE, "pintool",
    "-l1", "64", "l1 cacheline size in bytes");

KNOB<UINT32>   KnobCacheL2Size(KNOB_MODE_WRITEONCE, "pintool",
    "-s2", "20", "l2 cache size in bytes in megabytes");

KNOB<UINT32>   KnobCacheL2Associativity(KNOB_MODE_WRITEONCE, "pintool",
    "-a2", "20", "l2 cache associativity (1 for direct mapped)");

KNOB<UINT32>   KnobCacheL2LineSize(KNOB_MODE_WRITEONCE, "pintool",
    "-l2", "64", "l2 cacheline size in bytes");
/*
KNOB<UINT32>   KnobCacheL3Size(KNOB_MODE_WRITEONCE, "pintool",
    "-s3", "4", "l3 cache size in bytes in megabytes");

KNOB<UINT32>   KnobCacheL3Associativity(KNOB_MODE_WRITEONCE, "pintool",
    "-a3", "64", "l3 cache associativity (1 for direct mapped)");

KNOB<UINT32>   KnobCacheL3LineSize(KNOB_MODE_WRITEONCE, "pintool",
    "-l3", "64", "l3 cache size in bytes");
*/

namespace DL1
{
    //1st lavel data cache: configurable cache size, cache line size and associativity
    const CACHE_ALLOC::STORE_ALLOCATION allocation = CACHE_ALLOC::STORE_NO_ALLOCATE;

    const UINT32 max_sets = KILO;

    const UINT32 max_associativity = 256;

    //typedef CACHE_ROUND_ROBIN(max_sets, max_associativity, allocation) CACHE;
    typedef CACHE_LRU(max_sets, max_associativity, allocation) CACHE;
}
//That's for private cache
// DL1::CACHE **dl1;
namespace DL2
{
    // 2nd level data cache: configurable cache size, cache line size and associativity
    const CACHE_ALLOC::STORE_ALLOCATION allocation = CACHE_ALLOC::STORE_ALLOCATE;

    const UINT32 max_sets = 32*KILO; // cacheSize / (lineSize * associativity);

    const UINT32 max_associativity = 256; // associativity;

    //typedef CACHE_DIRECT_MAPPED(max_sets, allocation) CACHE;
    //typedef CACHE_ROUND_ROBIN(max_sets, max_associativity, allocation) CACHE;
    typedef CACHE_LRU(max_sets, max_associativity, allocation) CACHE;
}
LOCALVAR DL2::CACHE *dl2;


class PRIVATE_CACHE
{
  private:
    //Cache controler info, the index of array tells recently which cache has the lastest data, the value of array tells the status of that cache line
    typedef boost::array<UINT8, MAX_THREAD_NUM> CC_INFO; // Important! initialize as 0
    typedef std::unordered_map<ADDRINT, CC_INFO> CC_MAP;
    UINT8 _num;
    DL1::CACHE **dl1;
    //DL2::CACHE **dl2;
    CC_MAP dl1_map;
    //CC_MAP dl2_map;

  public:
    // constructors/destructors
    PRIVATE_CACHE(UINT8 num, UINT32 size, UINT32 linesize, UINT32 associativity)
    {
        _num = num;
        dl1 = new DL1::CACHE*[_num];
        for(UINT8 i = 0; i < _num; i++)
        {
            dl1[i] = new DL1::CACHE("L1 Data Cache", size, linesize, associativity);
        }
    }

    // modifiers
    /// Cache access from addr to addr+size-1
    void Access(THREADID threadid, ADDRINT addr, UINT32 size, CACHE_BASE::ACCESS_TYPE accessType, Byte* data_buf);
    // Cache coherence using MESI Protocal
    //void MESI();
    //void Load();
    void EvictTodl2(CACHE_LINE cache_line); //return if it is necessary to really do the evict op
    void LoadFromdl2(ADDRINT addr, CACHE_LINE &cache_line);
    void WriteAtdl2(ADDRINT addr, UINT32 size);
    void FlushPCache();
    void Output();
    void CountDirtyCacheLine();
    BOOL ReadL1Cache(ADDRINT addr, UINT8 size, ADDRINT &data);
    UINT8 CountCD(ADDRINT addr);
    /*
    bool AccessSingleLine(ADDRINT addr,UINT32 size, ACCESS_TYPE accessType,UINT8 (&value)[BLOCK_SIZE], CACHE_DIRTY &isdirty);
    bool ReadFromCache(ADDRINT addr, ADDRINT &data, UINT8 size);
    void LoadWholeCacheLine(ADDRINT addr, UINT8 value[BLOCK_SIZE], CACHE_DIRTY isdirty, ADDRINT &replace_addr);
    void FLushFromLastLevel(ADDRINT addr, ADDRINT &replace_addr, UINT8 value[BLOCK_SIZE]);
    void Flush();
    void ResetStats();
    */
};

UINT8 PRIVATE_CACHE::CountCD(ADDRINT addr){
  UINT8 dis = 0;
  for(UINT i = 0; i<_num; i++)
  {
      dis = dl1[i]->CountCrashDistance(addr);
      if(dis>0)
      {
        break;
      }
  }
  return dis;
}

VOID PRIVATE_CACHE::CountDirtyCacheLine(){
  for(UINT8 i=0; i<_num; i++)
     dl1[i]->CountDirtyCacheLine();
}

BOOL PRIVATE_CACHE::ReadL1Cache(ADDRINT addr, UINT8 size, ADDRINT &data){
  /*
    ADDRINT begin_addr;
    dl1[0]->FindBiginingAddressofCacheline(addr, begin_addr);
    CC_MAP::iterator it = dl1_map.find(begin_addr);
    BOOL result;
    if(it != dl1_map.end())
    {
        return false;
    }
    else{
      UINT8 i;
      for(i=0; i<_num; i++)
      {
        if(it->second[i] != INVALID)
        {
          break;
        }
      }
      if(i == _num)
      {
        return false;
      }
      else{
        result = dl1[i]->ReadFromCache(addr, data, size);
      }
    }
    */
    BOOL result = false;
    for(UINT i = 0; i<_num; i++)
    {
        result = dl1[i]->ReadFromCache(addr, data, size);
        if(result)
          break;
    }
    return result;
}

void PRIVATE_CACHE::Output()
{
  for(UINT8 i=0; i<_num; i++)
  {
    std::cerr << *dl1[i];
  }
}

void PRIVATE_CACHE::FlushPCache()
{
   for(UINT8 i=0; i<_num; i++)
      dl1[i]->Flush();
}

void PRIVATE_CACHE::WriteAtdl2(ADDRINT addr, UINT32 size){
    CACHE_LINE cache_line; //should be useless since inside the AccessSingleLine they already done eviction

    const BOOL dl2Hit = dl2->AccessSingleLine(addr,size,CACHE_BASE::ACCESS_TYPE_STORE,cache_line);
}

void PRIVATE_CACHE::LoadFromdl2(ADDRINT addr, CACHE_LINE &cache_line)
{
    const BOOL dl2Hit = dl2->AccessSingleLine(addr,BLOCK_SIZE,CACHE_BASE::ACCESS_TYPE_LOAD,cache_line);

    CACHE_LINE evict;
    if(!dl2Hit){
        UINT8 value[BLOCK_SIZE];
        memory.ReadAsBlock(addr, value);
        (cache_line._data).SetWholeCacheLine(value);
        cache_line._dirty = CACHE_DIRTY(0);
        dl2->LoadWholeCacheLine(addr,cache_line,evict);
        if(evict.if_evict)
        {// evict to main memory
          (evict._data).GetWholeCacheLine(value);
          memory.WriteAsBlock(evict._addr, value);
        }
    }
}

void PRIVATE_CACHE::EvictTodl2( CACHE_LINE cache_line)
{// can be outside of the class, also can hide the interface
    CC_MAP::iterator it = dl1_map.find(cache_line._addr);

    CACHE_LINE evict;
    dl2->GetEvictData(cache_line._addr, cache_line, evict);
    if(evict.if_evict && evict._dirty.ifdirty())
    {
      UINT8 value[BLOCK_SIZE];
      (evict._data).GetWholeCacheLine(value);
      memory.WriteAsBlock(evict._addr, value);
    }
}

void PRIVATE_CACHE::Access(THREADID threadid, ADDRINT addr, UINT32 size, CACHE_BASE::ACCESS_TYPE accessType, Byte* data_buf)
{

    const UINT8 pindex = threadid % _num;
    const ADDRINT highAddr = addr + size;
    bool allHit = true;
    const ADDRINT lineSize = dl1[pindex]->LineSize();
    const ADDRINT notLineMask = ~(lineSize - 1);
    UINT8 nothitindex = 0;

    do {
      BOOL test_hit = dl1[pindex]->CalculateCacheMissRatio(addr,accessType);
      /* code */
      CACHE_TAG tag;
      UINT32 setIndex;
      UINT32 lineIndex;

      dl1[pindex]->SplitAddress(addr, tag, setIndex, lineIndex);
      UINT32 distence = lineSize - lineIndex;
      UINT32 step = (distence >= size ? size : distence);
      ADDRINT begin_addr;
      dl1[pindex]->FindBiginingAddressofCacheline(addr, begin_addr);
      //EVMEMT_INFO evict_info;
      CACHE_LINE cache_line;
      CACHE_LINE evict;
      CC_MAP::iterator it = dl1_map.find(begin_addr);
      if(it == dl1_map.end())
      {//NOT in dl1 yet, creat the cache line info for the begin_addr

          CC_INFO cc;
          //initialize as INVALID
          std::fill_n(cc.begin(), MAX_THREAD_NUM, INVALID);
          dl1_map.emplace(std::make_pair(begin_addr, cc));
          it = dl1_map.find(begin_addr); //search the dl1 cache line info map again
      }

      ASSERTX(it != dl1_map.end());


      if (it->second[pindex] == INVALID) {
        //ASSERTX(!dl1[pindex]->AccessSingleLine(addr,step,accessType,cache_line));
        //For invalid state
        //PrRd --- For Read(C) : INVALID ---> SHARED | For Read(!C) : INVALID ---> EXCLUSIVE | FOR Write : INVALID ---> MODIFIED
        ASSERTX(!test_hit);
        bool C = false;
        UINT8 i; //i contains which private l1 cache has the newest data
        for(i = 0; i<_num; i++)
        {
          if(i != pindex && it->second[i] != INVALID)
          {
              C = true;
              break;
          }
        }

        if(accessType == CACHE_BASE::ACCESS_TYPE_LOAD)
        {//op == 'r'
            if(C)
            {//INVALID -> SHARED!
               //get cache line from dl1[i]
               const BOOL dl1Hit = dl1[i]->AccessSingleLine(addr,step,CACHE_BASE::ACCESS_TYPE_LOAD,cache_line);
               if(!dl1Hit)
               {
                 cout<<hex<<addr<<" : "<<accessType<<endl;
                 cout<<"The status is "<<+it->second[i]<<endl;
               }
               ASSERTX(dl1Hit);
               //load that cache line
               dl1[pindex]->LoadWholeCacheLine(addr,cache_line,evict);
               if(evict.if_evict){
                 //change the evicted cache line first, the state need to be changed as INVALID
                 CC_MAP::iterator temp_it = dl1_map.find(evict._addr);
                 ASSERTX(temp_it != dl1_map.end());
                 ASSERTX(temp_it->second[pindex] != INVALID);
                 //if(temp_it != dl1_map.end())
                 //{
                    //if(temp_it->second[pindex] != INVALID )
                    //{
                      if(temp_it->second[pindex] != EXCLUSIVE)
                      {
                          EvictTodl2(evict);
                      }
                      temp_it->second[pindex] = INVALID;
                      // Don't need to change the valid bit in cache since it already evict into L2
                    //}
                 //}
                 //evict to dl2 //evict to memory //all in EvictTodl2

              }

               //change dl1_map status, pindex has status SHARED
               it->second[pindex] = SHARED;

               //Generate BusRD to turn modified and exclusive to shared
               //no write back to main memory
               for(i=0; i<_num; i++)
               {
                  if(i != pindex && it->second[i] != INVALID)
                  {
                    //if(it->second[i] == MODIFIED || it->second[i] == EXCLUSIVE)
                      it->second[i] = SHARED;
                  }
                }
            }
            else{//read from dl2 and main memory
                 // INVALID -> EXCLUSIVE
                 LoadFromdl2(begin_addr, cache_line);
                 dl1[pindex]->LoadWholeCacheLine(addr,cache_line,evict);
                 if(evict.if_evict){
                   //change the evicted cache line first, the state need to be chaged as INVALID
                   CC_MAP::iterator temp_it = dl1_map.find(evict._addr);
                   ASSERTX(temp_it != dl1_map.end());
                   ASSERTX(temp_it->second[pindex] != INVALID);
                   //if(temp_it != dl1_map.end())
                   //{
                      //if(temp_it->second[pindex] != INVALID)
                      //{
                        if(temp_it->second[pindex] != EXCLUSIVE)
                        {
                            EvictTodl2(evict);
                        }
                        temp_it->second[pindex] = INVALID;
                      //}
                   //}
                   //evict to dl2 //evict to memory //all in EvictTodl2

                }
                it->second[pindex] = EXCLUSIVE;
            }
        }
        else{
          // op = 'w'

          if(C)// INVALID -> MODIFIED
          {// Copy from dl1[i]
              BOOL dl1Hit = dl1[i]->AccessSingleLine(addr,step,CACHE_BASE::ACCESS_TYPE_LOAD,cache_line);
              //debug infor
              ASSERTX(dl1Hit);
              //load that cache line
              dl1[pindex]->LoadWholeCacheLine(addr,cache_line,evict);
              if(evict.if_evict){
                //change the evicted cache line first, the state need to be chaged as INVALID
                CC_MAP::iterator temp_it = dl1_map.find(evict._addr);
                ASSERTX(temp_it != dl1_map.end());
                ASSERTX(temp_it->second[pindex] != INVALID);
                if(temp_it->second[pindex] != EXCLUSIVE)
                {
                   EvictTodl2(evict);
                }
                temp_it->second[pindex] = INVALID;
              }
              dl1Hit = dl1[pindex]->AccessSingleLine(addr, step, accessType, cache_line); //cache_line at this time should be useless
              ASSERTX(dl1Hit);
              it->second[pindex] = MODIFIED;
              for(i=0; i<_num; i++)
              {
                  if(i != pindex && it->second[i] != INVALID)
                  {
                      //cout<<"The orig status is "<<+it->second[i]<<" and needed to be set as invalid"<<endl;
                      it->second[i] = INVALID;
                      dl1[i]->SetInvalid(addr);
                  }
              }
          }
          else{
              //since L1 is write_no_allocate, when write miss happens in L1, just pass by l1 and write L2
              // The status won't change until read the l2, At that time the status become EXCLUSIVE
              WriteAtdl2(addr,step);
          }
        }
      }
      else if (it->second[pindex] == EXCLUSIVE) {
          //PrRd --- For Read : EXCLUSIVE ---> EXCLUSIVE | FOR Write : EXCLUSIVE ---> MODIFIED
          ASSERTX(test_hit);
          CACHE_LINE cache_line;
          const BOOL dl1Hit = dl1[pindex]->AccessSingleLine(addr,step, accessType, cache_line);
          //ASSERTX(dl1Hit); //It should hit since the status right now is exclusive
          /*
          if(!dl1Hit)
          {
              cout<<"Exclusive"<<endl;
              cout<<hex<<addr<<" : size is "<<+step<<". AccessType is "<<accessType<<endl;
              cout<<hex<<begin_addr<<endl;
              cout<<it->first<<endl;
          }*/
          if(accessType == CACHE_BASE::ACCESS_TYPE_STORE){
              it->second[pindex] = MODIFIED;
          }
      }
      else if(it->second[pindex] == SHARED)
      {// read SHARED->SHARED write //Shared  ----> Modified, other will become invalid
          ASSERTX(test_hit);
          CACHE_LINE cache_line;
          const BOOL dl1Hit = dl1[pindex]->AccessSingleLine(addr,step, accessType, cache_line);
          //ASSERTX(dl1Hit); //It should hit since the status right now is shared
          if(accessType == CACHE_BASE::ACCESS_TYPE_STORE){
              it->second[pindex] = MODIFIED;
              for(UINT8 i = 0; i<_num; i++)
              {
                if(i != pindex && it->second[i] != INVALID){
                  it->second[i] = INVALID;
                  dl1[i]->SetInvalid(addr);
                }
              }
          }
      }

      else if(it->second[pindex] == MODIFIED)
      {//MODIFIED -> MODIFIED
          ASSERTX(test_hit);
          CACHE_LINE cache_line;
          const BOOL dl1Hit = dl1[pindex]->AccessSingleLine(addr,step, accessType, cache_line);
          if(!dl1Hit)
          cout<<"Statue is "<<+pindex<<" : "<<+it->second[pindex]<<endl;
          //ASSERTX(dl1Hit); //It should hit since the status right now is modified
          /*
          if(!dl1Hit)
          {
              cout<<"Modified"<<endl;
              cout<<hex<<addr<<" : size is "<<+step<<". AccessType is "<<accessType<<endl;
              cout<<hex<<begin_addr<<endl;
              cout<<it->first<<endl;
          }*/
      }

      size = size - step;
      addr = (addr & notLineMask) + lineSize; //start of next cache line
    } while(addr < highAddr);

}

LOCALVAR PRIVATE_CACHE *pdl1;



//disable dl3 for now
/*
namespace DL3
{
    // 3rd level data cache: configurable cache size, cache line size and associativity
    const CACHE_ALLOC::STORE_ALLOCATION allocation = CACHE_ALLOC::STORE_ALLOCATE;

    const UINT32 max_sets = 5*KILO; // cacheSize / (lineSize * associativity);

    const UINT32 max_associativity = 512; // associativity;

    //typedef CACHE_DIRECT_MAPPED(max_sets, allocation) CACHE;
    //typedef CACHE_ROUND_ROBIN(max_sets, max_associativity, allocation) CACHE;
    typedef CACHE_LRU(max_sets , max_associativity, allocation) CACHE;
}
LOCALVAR DL3::CACHE *dl3;
*/

VOID SimulatorInit(int argc, char* argv[]){
    // Create output file
    char name[MAX_FILE_PATH] = "generalinfo.out.";
    gethostname(name + strlen(name), MAX_FILE_PATH - strlen(name));
    pid_t pid = getpid();
    sprintf(name + strlen(name), "%d", pid);
    cerr << "\n Creating log file at:" << name << "\n";
    gInfoFile = fopen(name, "w");
    // print the arguments passed
    char cmr_name[MAX_FILE_PATH] = "cmr.out.";
    gethostname(cmr_name + strlen(cmr_name), MAX_FILE_PATH - strlen(cmr_name));
    sprintf(cmr_name + strlen(cmr_name), "%d", pid);
    CMRFile.open(cmr_name);
    //TraceFile << hex;
    CMRFile.setf(ios::showbase);
    fprintf(gInfoFile, "\n");

    for(int i = 0 ; i < argc; i++) {
        fprintf(gInfoFile, "%s ", argv[i]);
    }
    fprintf(gInfoFile, "\n");

}


LOCALFUN VOID Fini(int code, VOID * v)
{
    UINT64 memory_footprint = memory.GetMemorySize() * 64;

    cout<<"Memory footprint size is "<<memory_footprint<<" , which is "<<memory_footprint/KILO<<" K "<<memory_footprint/MEGA<<" M."<<endl;
    fprintf(gInfoFile,"\nMemory footprint size is  %lu, which is %lu K, %lu M.\n",memory_footprint, memory_footprint/KILO, memory_footprint/MEGA);
    cout<<"Count "<<dec<<icount<<endl;
    cout<<"The num of consistent variable is "<<consistent_variable.size()<<endl;
    cout<<"The num of array we care is "<<crucialdata.size()<<endl;
    TraceFile<<"Count "<<dec<<icount<<endl;
    TraceFile<<"The num of consistent variable is "<<consistent_variable.size()<<endl;
    TraceFile<<"The num of array we care is "<<crucialdata.size()<<endl;

    pdl1->Output();

    std::cerr << *dl2;
    //std::cerr << *dl3;
    TraceFile.close();
    CMRFile.close();
    fclose(gInfoFile);
}


BOOL ReadCache(ADDRINT addr, UINT8 size, ADDRINT &data)
{
    //cout<<"Hi I'm read cache!"<<endl;
    BOOL result = pdl1->ReadL1Cache(addr, size, data);
    if(! result)
    {
        result = dl2->ReadFromCache(addr, data, size);
    }
    return result;
}


VOID GetWhatWeCare(CHAR * name, ADDRINT addr, CHAR * type, ADDRINT size)
{
  if(strcmp(name, CONSISTENT_DATA)==0)
  {
        bool find = false;
        for(UINT8 i=0; i<consistent_variable.size();i++)
        {
            if(consistent_variable[i] == addr)
            {
               find = true;
               break;
            }
        }
        if(!find)
        {
          consistent_variable.push_back(addr);
          TraceFile <<hex<< addr << " " <<dec<< size <<" "<<type<< endl;
        }
  }
  else if(strcmp(name,CRUCIAL_DATA)==0)
  {
      bool find = false;
      for(UINT8 i=0; i<crucialdata.size();i++)
      {
          if( boost::get<0>(crucialdata[i]) == addr)
          {
             find = true;
             break;
          }
      }
      if(!find)
      {
        crucialdata.push_back(boost::make_tuple(addr,size,type));
        TraceFile <<hex<< addr << " " <<dec<< size <<" "<<type<< endl;
      }
  }

  else
  {
      readonlydata.push_back(boost::make_tuple(addr,size,type));
      TraceFile <<hex<< addr << " " <<dec<< size <<" "<<type<< endl;
  }
}

VOID clflush(ADDRINT addr)
{
   //pdl1->CLFlush(ADDRINT addr);
   dl2->CLFlush(addr);
}
VOID FlushCareData()
{

    cout<<"Flush Data we care!"<<endl;
    //dl3->Flush();
    dl2->Flush();
    pdl1->FlushPCache();


/*
    ADDRINT temp_value = 0;
    ADDRINT temp_addr;
    UINT16 step = 0;
    ADDRINT addr_base;
    ADDRINT size_base;
    CHAR * type_base;
    ofstream out;
    out.open("memory_init.out", ios::binary);
    for(UINT16 i = 0; i<readonlydata.size(); i++)
    {
        cout<<"Writing the array "<<i<<" we care."<<endl;
        addr_base = boost::get<0>(readonlydata[i]);
        size_base = boost::get<1>(readonlydata[i]);
        type_base = boost::get<2>(readonlydata[i]);
        cout<<hex<<addr_base<<" : "<<dec<<size_base<<" : "<<type_base<<endl;
        if(strcmp(type_base,DOUBLE) == 0)
        {
            step = 8;
        }
        else if(strcmp(type_base,INT) == 0){
            step = 4;
        }
        for(UINT64 it = 0; it<size_base; it++)
        {

          temp_addr = addr_base + it*step;
          bool hit = memory.ReadMemory(temp_addr, step, temp_value);
          //bool hit = ReadCache(temp_addr, step, temp_value);
          if(!hit){
              //cout<<hex<<temp_addr<<" Not in Memory"<<endl;
          }
          ADDRINT *pvalue;
          pvalue  = &temp_value;
          if(step == 4)
          {
              int *v1 = reinterpret_cast<int*>(pvalue);
              out<<*v1<<endl;
          }
          else{
              double *v2 = reinterpret_cast<double*>(pvalue);
              out<<*v2<<endl;
          }
        }

    }
    for(UINT16 i = 0; i<crucialdata.size(); i++)
    {
        cout<<"Recording the array "<<i<<" we care."<<endl;
        addr_base = boost::get<0>(crucialdata[i]);
        size_base = boost::get<1>(crucialdata[i]);
        type_base = boost::get<2>(crucialdata[i]);
        cout<<hex<<addr_base<<" : "<<dec<<size_base<<" : "<<type_base<<endl;
        if(strcmp(type_base,DOUBLE) == 0)
        {
            step = 8;
        }
        else if(strcmp(type_base,INT) == 0){
            step = 4;
        }
        //all_data += step*size_base;
        for(UINT64 it = 0; it<size_base; it++)
        {
            temp_addr = addr_base + it*step;
            bool hit = memory.ReadMemory(temp_addr, step, temp_value);
            if(!hit){
                //cout<<hex<<temp_addr<<" Not in Memory"<<endl;
            }
            ADDRINT *pvalue;
            pvalue  = &temp_value;
            if(step == 4)
            {
                int *v1 = reinterpret_cast<int*>(pvalue);
                out<<*v1<<endl;
                //fprintf(memout,"%d\n",*v1);
            }
            else{
                double *v2 = reinterpret_cast<double*>(pvalue);
                out<<*v2<<endl;
                //fprintf(memout,"%20.12e\n",*v2);
            }


        }
    }
    out.close();

    //PIN_ExitThread(0);
  */
}

VOID StopThreadForFlushCache(THREADID threadid){
  if (PIN_StopApplicationThreads(threadid))
       {
           printf("Threads stopped by application thread %u\n", threadid);
           fflush(stdout);

           UINT32 nThreads = PIN_GetStoppedThreadCount();
           cout<<"The value of nThread is "<<dec<<nThreads<<endl;
           ASSERTX(nThreads <= threadnum);
           for (UINT32 i = 0; i < nThreads; i++)
           {
               THREADID tid = PIN_GetStoppedThreadId(i);
               const CONTEXT * ctxt = PIN_GetStoppedThreadContext(tid);
               printf("  Thread %u, IP = %llx\n", tid,
                      (long long unsigned int)PIN_GetContextReg(ctxt, REG_INST_PTR));
           }
           FlushCareData();
           PIN_ResumeApplicationThreads(threadid);
           printf("Threads resumed by application thread %u\n", threadid);
           fflush(stdout);
       }

}

VOID StartCrush(THREADID threadid)
{
    PIN_LockClient();
    crush_flag = true;
    PIN_UnlockClient();
    cout<<"flip the flag!"<<endl;
}

VOID EndCrush()
{
    PIN_LockClient();
    crush_flag = false;
    PIN_UnlockClient();
    cout<<"flip the flag!"<<endl;
    cout<<"icount = "<<icount<<endl;
}


LOCALFUN VOID MemRefMulti(THREADID threadid, CACHE_BASE::ACCESS_TYPE accessType, ADDRINT addr, Byte* data_buf, UINT32 size)
{
    pdl1->Access(threadid, addr, size, accessType, data_buf);

  /*
    ADDRINT nothit[BLOCK_SIZE]={0};
    UINT8 sizeincacheline[BLOCK_SIZE]={0};

    for(UINT8 index=0; index < BLOCK_SIZE; index ++)
    {
        nothit[index] = 0;
        sizeincacheline[index] = 0;
    }

    // first level D-cache: potentially multiple cache-line access
    const BOOL dl1Hit = dl1[pindex]->Access(addr, size, accessType, nothit, sizeincacheline);

    UINT8 value[BLOCK_SIZE]={0};
    UINT8 flush_value[BLOCK_SIZE] = {0};
    CACHE_DIRTY isdirty;
    if(!dl1Hit){
        for(UINT8 i = 0; i<64; i++)
        {
          if(nothit[i] == 0 || sizeincacheline[i] ==0)
          {
              break;
          }
          UINT32 temp_size = sizeincacheline[i];
          ADDRINT miss_addr = nothit[i];
          ADDRINT replace_addr, replace_addr_l2, replace_addr_l3;

          const BOOL dl2Hit = dl2[pindex]->AccessSingleLine(miss_addr,temp_size,accessType, value, isdirty);

          if(!dl2Hit)
          {
              const BOOL dl3Hit = dl3->AccessSingleLine(miss_addr,temp_size, accessType, value, isdirty);

              if(!dl3Hit)
              {
                if(accessType == CACHE_BASE::ACCESS_TYPE_STORE)
                {
                    UINT8 v[64] = {0};
                    PIN_SafeCopy(v,(void*)addr,temp_size);
                    memory.WriteMemory(miss_addr,temp_size,v);
                }

                if(!memory.ReadAsBlock(miss_addr,value) && accessType == CACHE_BASE::ACCESS_TYPE_STORE)
                {
                    cout<<"Do NOT read from mem. "<<endl;
                    cout<<"Miss addr is "<<hex<<miss_addr<<"original addr is "<<addr<<endl;
                    for(UINT8 index=0; index < BLOCK_SIZE; index ++)
                    {
                        value[index] = 0;
                    }
                }
                //get value from cache must be clean
                isdirty = CACHE_DIRTY(0);
                dl3->LoadWholeCacheLine(miss_addr,value,isdirty,replace_addr);
              }
              dl2[pindex]->LoadWholeCacheLine(miss_addr,value,isdirty,replace_addr);
              if(replace_addr != 0)
              {
                memory.ReadAsBlock(replace_addr,flush_value);
                dl3->EvictToLastLevel(replace_addr,replace_addr_l2,flush_value);
              }
          }
          dl1[pindex]->LoadWholeCacheLine(miss_addr,value,isdirty, replace_addr);
          if(replace_addr != 0)
          {
            //reload to dl2 tp simulate dl1 flush to dl2 and dl3
            memory.ReadAsBlock(replace_addr,flush_value);
            dl2[pindex]->FLushFromLastLevel(replace_addr,replace_addr_l2,flush_value);
            if(replace_addr_l2 != 0)
            {
              memory.ReadAsBlock(replace_addr_l2,flush_value);
              dl3->FLushFromLastLevel(replace_addr_l2,replace_addr_l3,flush_value);
            }
            memory.ReadAsBlock(replace_addr,flush_value);
            dl3->FLushFromLastLevel(replace_addr,replace_addr_l3,flush_value);
          }

        }

    }
*/
    // second level unified Cache
    /*
    if ( ! dl1Hit) Dl2Access(addr, size, accessType);
    else if(accessType == CACHE_BASE::ACCESS_TYPE_STORE)
    {//Need to think about it!
        Dl2Access(addr, size, accessType);
    }*/

}

UINT32 CountInconsistency()
{
    //cache_count = 0;
    //dl3->Flush();
    //dl2->Flush();
    //pdl1->FlushPCache();

    pdl1->CountDirtyCacheLine();
    dl2->CountDirtyCacheLine();
    bool in_mem;
    UINT64 dirty_data = 0;
    for(MEM::iterator it = dirty_count.begin(); it != dirty_count.end(); it++)
    {
        BLOCK mem;
        in_mem = memory.ReadAsBlock(it->first,mem);
        ASSERTX(in_mem);
        dirty_data += CompareDiff(mem,it->second);
    }
    cout << "The total dirty cache line num is "<<dirty_count.size()<<endl;
    cout << endl;
    //return dirty_count.size();
    return dirty_data;
}

std::pair<UINT32,UINT32> CountCrashDistance(ADDRINT begin_addr, ADDRINT size)
{
    UINT32 dis=0;
    UINT32 dirty_num = 0;
    UINT8 delta;
    for(ADDRINT addr = begin_addr; addr<begin_addr+size; addr+=64)
    {
      delta = 0;
      delta = pdl1->CountCD(addr);
      if(delta>0)
      {
        dis += delta;
        dirty_num++;
        continue;
      }
      delta = dl2->CountCrashDistance(addr);
      if(delta > 0)
      {
        dis += delta;
        dirty_num++;
      }
    }
    return std::make_pair(dis, dirty_num);
}


VOID PrintResult()
{
    char output_file[MAX_FILE_PATH] = "result.out.";
    gethostname(output_file + strlen(output_file), MAX_FILE_PATH - strlen(output_file));
    pid_t pid = getpid();
    sprintf(output_file + strlen(output_file), "%d.txt", pid);
    FILE *resultout;
    resultout = fopen(output_file,"w");

    cerr << "\n Creating log file at:" << output_file << "\n";

    fprintf(resultout, "%d,%d\n", pid,crash_line);
    fclose(resultout);
    CMRFile<<pid<<","<<crash_line<<",";
}

VOID AfterCrush()
{
    cout<< "I'm after crush!"<< endl;
    //cout<< "addr_care's size is "<< crucialdata.size() + readonlydata.size()<<endl;
    cout<<"The total number of critical data is "<<dec<<crucialdata.size()<<endl;
    cout<<"The total number of consistent data is "<<dec<<consistent_variable.size()<<endl;
    FILE *memout;
    FILE *cacheout;
    FILE *consistentout;
    char memname[MAX_FILE_PATH] = "crush_mem.out.";
    char cachename[MAX_FILE_PATH] = "crush_cache.out.";
    char consistentname[MAX_FILE_PATH] = "consistent_variable.out.";
    gethostname(memname + strlen(memname), MAX_FILE_PATH - strlen(memname));
    gethostname(cachename + strlen(cachename), MAX_FILE_PATH - strlen(cachename));
    gethostname(consistentname + strlen(consistentname), MAX_FILE_PATH - strlen(consistentname));
    pid_t pid = getpid();
    sprintf(memname + strlen(memname), "%d", pid);
    sprintf(cachename + strlen(cachename), "%d", pid);
    sprintf(consistentname + strlen(consistentname), "%d", pid);
    cerr << "\n Creating log file at:" << memname << "\n";
    cerr << "\n Creating log file at:" << cachename << "\n";
    cerr << "\n Creating log file at:" << consistentname << "\n";
    memout = fopen(memname, "w");
    cacheout = fopen(cachename, "w");
    consistentout = fopen(consistentname,"w");
    ADDRINT temp_mem_value;
    ADDRINT temp_cache_value;
    ADDRINT temp_value;
    ADDRINT temp_addr;
    ADDRINT addr_base;
    ADDRINT size_base;
    CHAR * type_base;
    UINT8 step=0;
    //UINT64 variable_count = 0;
    UINT64 hit_count[128] = {0};
    UINT64 in_cache[128] = {0};
    UINT64 critical_data_count[128] = {0};
    ADDRINT *pvalue;
    UINT64 all_data = 0;
    DIS cd[16];

    //seperate consistent data
    for(UINT16 i = 0; i<consistent_variable.size(); i++)
    {
        bool hit = ReadCache(consistent_variable[i], 4, temp_value);
        if(!hit)
        {
          cout<<"The consistency data "<<i<<" is not in cache! Need to read from memory"<<endl;
          memory.ReadMemory(consistent_variable[i], 4, temp_value);
        }

        pvalue = &temp_value;
        int *v1 = reinterpret_cast<int*>(pvalue);
        cout<<"The consistent data value is "<< *v1<<endl;
        //out<<*v1<<endl;
        fprintf(consistentout,"%d\n",*v1);
        /*
        cout<<"In simulate memory "<<*v1<<endl;
        PIN_SafeCopy(&temp_value,(void *)consistent_variable[i], 4);
        pvalue = &temp_value;
        v1 = reinterpret_cast<int*>(pvalue);
        cout<<"In real memroy "<<*v1<<endl;
        */
    }

/*
    for(UINT16 i = 0; i<readonlydata.size(); i++)
    {
        cout<<"Recording the array "<<i<<" we care."<<endl;
        addr_base = boost::get<0>(readonlydata[i]);
        size_base = boost::get<1>(readonlydata[i]);
        type_base = boost::get<2>(readonlydata[i]);
        cout<<hex<<addr_base<<" : "<<dec<<size_base<<" : "<<type_base<<endl;
        if(strcmp(type_base,DOUBLE) == 0)
        {
            step = 8;
        }
        else if(strcmp(type_base,INT) == 0){
            step = 4;
        }
        //NOT the crucial data, we just flsuh it once and become read only
        //all_data += step*size_base;
        for(UINT64 it = 0; it<size_base; it++)
        {
          temp_addr = addr_base + it*step;
          bool hit = memory.ReadMemory(temp_addr, step, temp_value);
          if(!hit){
              //cout<<hex<<temp_addr<<" Not in Memory"<<endl;
          }
          ADDRINT *pvalue;
          pvalue  = &temp_value;
          if(step == 4)
          {
              int *v1 = reinterpret_cast<int*>(pvalue);
              fprintf(memout,"%d\n",*v1);
              //memout<<*v1<<endl;
          }
          else{
              double *v2 = reinterpret_cast<double*>(pvalue);
              //memout<<*v2<<endl;
              fprintf(memout,"%20.12e\n",*v2);
          }
        }
    }
*/

    for(UINT16 i = 0; i<crucialdata.size(); i++)
    {
        in_cache[i] = 0;
        hit_count[i] = 0;
        critical_data_count[i] = 0;
        cout<<"Recording the array "<<i<<" we care."<<endl;
        addr_base = boost::get<0>(crucialdata[i]);
        size_base = boost::get<1>(crucialdata[i]);
        type_base = boost::get<2>(crucialdata[i]);
        cout<<hex<<addr_base<<" : "<<dec<<size_base<<" : "<<type_base<<endl;
        if(strcmp(type_base,DOUBLE) == 0)
        {
            step = 8;
        }
        else if(strcmp(type_base,INT) == 0){
            step = 4;
        }
        all_data += size_base * step;
        critical_data_count[i] = size_base * step;
        for(UINT64 it = 0; it<size_base; it++)
        {
            temp_addr = addr_base + it*step;
            /*if(it == 0){
              if(ReadCache(temp_addr,step,temp_cache_value))
              {
                 in_cache[i]+=step;

                 UINT8 *p_mem = (UINT8 *)&temp_value;
                 UINT8 *p_cache = (UINT8 *)&temp_cache_value;

                 pvalue = &temp_cache_value;
                 if(step == 4)
                 {
                     int *v1 = reinterpret_cast<int*>(pvalue);
                     fprintf(memout,"%d\n",*v1);
                 }
                 else{
                     double *v2 = reinterpret_cast<double*>(pvalue);
                     fprintf(memout,"%20.12e\n",*v2);
                 }
              }
              else{
                bool hit = memory.ReadMemory(temp_addr, step, temp_value);
                if(!hit){
                    //cout<<hex<<temp_addr<<" Not in Memory"<<endl;
                    fprintf(memout,"0\n");
                }
                else{
                    ADDRINT *pvalue;
                    pvalue  = &temp_value;
                    if(step == 4)
                    {
                        int *v1 = reinterpret_cast<int*>(pvalue);
                        //memout<<*v1<<endl;
                        fprintf(memout,"%d\n",*v1);
                    }
                    else{
                        double *v2 = reinterpret_cast<double*>(pvalue);
                        //memout<<*v2<<endl;
                        fprintf(memout,"%20.12e\n",*v2);
                      }
                    }
                  }
              }
            else{*/
              bool hit = memory.ReadMemory(temp_addr, step, temp_value);
              if(!hit){
                  //cout<<hex<<temp_addr<<" Not in Memory"<<endl;
                  temp_value = 0;
              }
              ADDRINT *pvalue;
              pvalue  = &temp_value;
              if(step == 4)
              {
                  int *v1 = reinterpret_cast<int*>(pvalue);
                  //memout<<*v1<<endl;
                  fprintf(memout,"%d\n",*v1);
              }
              else{
                  double *v2 = reinterpret_cast<double*>(pvalue);
                  //memout<<*v2<<endl;
                  fprintf(memout,"%20.12e\n",*v2);
              }
              temp_mem_value = temp_value;
              if(ReadCache(temp_addr,step,temp_cache_value))
              {
                 in_cache[i]+=step;

                 UINT8 *p_mem = (UINT8 *)&temp_value;
                 UINT8 *p_cache = (UINT8 *)&temp_cache_value;

                 for(UINT8 ii=0; ii<step; ii++)
                 {
                   if(p_mem[ii] == p_cache[ii])
                   {
                      hit_count[i]++;
                   }
                 }

                 pvalue = &temp_cache_value;

              }
              else{
                pvalue = &temp_mem_value;
              }
              if(step == 4)
              {
                  int *v1 = reinterpret_cast<int*>(pvalue);
                  fprintf(cacheout,"%d\n",*v1);
              }
              else{
                  double *v2 = reinterpret_cast<double*>(pvalue);
                  fprintf(cacheout,"%20.12e\n",*v2);
              }
          //}
        }
        //cd[i] = CountCrashDistance(addr_base,size_base);
      }

      /*  for(UINT16 i = 0; i<crucialdata.size(); i++)
        {
          cout<<"Recording the array "<<i<<" we care."<<endl;
          addr_base = boost::get<0>(crucialdata[i]);
          size_base = boost::get<1>(crucialdata[i]);
          type_base = boost::get<2>(crucialdata[i]);
          step = 8;
          ADDRINT mvalue;
          for(UINT64 it=0; it<size_base; i++)
          {
                  temp_addr = addr_base + it*step;
                  if(ReadCache(temp_addr,step,temp_value))
                  {
                     //fprintf(cacheout,"%08llX ",temp_value);
                  }
                  else{
                     if(memory.ReadMemory(temp_addr, step, temp_value))
                          {}
                     else{
                          temp_value = 0;
                     }
                  }
                  if(memory.ReadMemory(temp_addr, step, mvalue))
                  {}
                  else{
                          mvalue = 0;
                     }
                  fprintf(cacheout,"%08lX ",temp_value);
                  fprintf(memout,"%08lX",mvalue);
          }
          fprintf(cacheout, "\n");
          fprintf(memout,"\n");
        }
      }
*/
    //For crucial data

    UINT64 total_in_cache = 0;
    UINT64 total_hit_count = 0;
    double rate;
    for(UINT16 i = 0; i<crucialdata.size(); i++)
    {
      total_in_cache += in_cache[i];
      total_hit_count += hit_count[i];
      cout<<"For critical data "<<i<<endl;
      cout<<"The number of critical data in cache is "<<dec<<in_cache[i]<<endl;
      cout<<"The number of critical data in cache and value in mem are the same is "<<hit_count[i]<<endl;
      rate = double(in_cache[i] - hit_count[i])/double(critical_data_count[i]);
      CMRFile<<rate<<",";
      cout<<"The inconsistency rate for critical data is "<<rate<<endl;
      cout<< "Crash distance is "<<dec<<cd[i].first<<endl;
    }
    cout<<endl;
    cout<<"The number of critical data is "<<dec<<all_data<<endl;
    rate = double(total_in_cache - total_hit_count)/double(all_data);
    CMRFile<<rate<<",";
    cout<<"Total inconsistency rate for critical data is "<<rate<<endl;
    cout<<endl;


    fprintf(gInfoFile,"\nFor critical data: \n");
    for(UINT16 i = 0; i<crucialdata.size(); i++)
    {
      fprintf(gInfoFile,"The number of critical data in cache is %lu.\n",in_cache[i]);
      fprintf(gInfoFile,"The number of critical data in cache and value in mem are the same is %lu.\n",hit_count[i]);
      rate = double(in_cache[i] - hit_count[i])/double(critical_data_count[i]);
      fprintf(gInfoFile,"The inconsistency rate for critical data is %lf.\n",rate);
      fprintf(gInfoFile,"Crash distance is %u\n", cd[i].first);
        CMRFile<<cd[i].first<<","<<cd[i].second<<",";
    }
    fprintf(gInfoFile,"\nThe number of critical data is %lu.\n",all_data);
    rate = double(total_in_cache - total_hit_count)/double(all_data);
    fprintf(gInfoFile, "\nTotal inconsistency rate for critical data is %lf\n",rate);


    //for all data
    all_data = memory.GetMemorySize() * 64;
    cout<<"The num of all data in application is "<<dec<<all_data<<" bytes."<<endl;
    UINT64 dirty_in_cache = CountInconsistency();
    cout<<"The num of dirty data in cache is "<<dec<<dirty_in_cache<<" bytes."<<endl;
    rate = double(dirty_in_cache)/double(all_data);
    CMRFile<<rate<<",";
    cout<<"The inconsistency rate for all data is "<<rate<<endl;
    fprintf(gInfoFile,"\nThe num of all data in application is %lu, which is %lu K, %lu M.\n",all_data, all_data/KILO, all_data/MEGA);
    fprintf(gInfoFile,"The num of dirty data in cache is %lu\n",dirty_in_cache);
    fprintf(gInfoFile,"The inconsistency rate for all data is %lf.",rate);


    fclose(memout);
    fclose(cacheout);
    fclose(consistentout);
}




// Initialized the needed data structures before launching the target program
void ClientInit(int argc, char* argv[]) {
    // Create output file
    char name[MAX_FILE_PATH] = "callpathinfo.out.";
    char* envPath = getenv("CCTLIB_CLIENT_OUTPUT_FILE");

    if(envPath) {
        // assumes max of MAX_FILE_PATH
        strcpy(name, envPath);
    }

    gethostname(name + strlen(name), MAX_FILE_PATH - strlen(name));
    pid_t pid = getpid();
    sprintf(name + strlen(name), "%d", pid);
    cerr << "\n Creating log file at:" << name << "\n";
    gTraceFile = fopen(name, "w");
    // print the arguments passed
    fprintf(gTraceFile, "\n");

    for(int i = 0 ; i < argc; i++) {
        fprintf(gTraceFile, "%s ", argv[i]);
    }

    fprintf(gTraceFile, "\n");
}

void DecodingFootPrint(const THREADID threadid,  ContextHandle_t myHandle, ContextHandle_t parentHandle, void **myMetric, void **parentMetric)
{
    if (*myMetric == NULL) return;
    struct node_metric_t *hset = static_cast<struct node_metric_t*>(*myMetric);
    unordered_set<uint64_t>::iterator it;
    for (it = hset->addressSet.begin(); it!= hset->addressSet.end(); ++it) {
        uint64_t refSize = (*it)>>48;
        uint64_t addr = (*it) & ((1ULL<<48)-1);
        assert(refSize != 0);
        for(uint i=0; i<refSize; i++) {
          hset->addressSetDecoded.insert(addr+i);
        }
    }
//    hset->addressSet.clear();
}

void MergeFootPrint(const THREADID threadid,  ContextHandle_t myHandle, ContextHandle_t parentHandle, void **myMetric, void **parentMetric)
{
    if (*myMetric == NULL) return;
    struct node_metric_t *hset = static_cast<struct node_metric_t*>(*myMetric);

    if (*parentMetric == NULL) {
      *parentMetric = &((hmap_vector[threadid])[parentHandle]);
      (hmap_vector[threadid])[parentHandle].addressSetDecoded.insert(hset->addressSetDecoded.begin(), hset->addressSetDecoded.end());
      (hmap_vector[threadid])[parentHandle].addressSet.insert(hset->addressSet.begin(), hset->addressSet.end());
    }
    else {
      (static_cast<struct node_metric_t*>(*parentMetric))->addressSetDecoded.insert(hset->addressSetDecoded.begin(), hset->addressSetDecoded.end());
      (static_cast<struct node_metric_t*>(*parentMetric))->addressSet.insert(hset->addressSet.begin(), hset->addressSet.end());
    }
}


inline bool FootPrintCompare(const struct sort_format_t &first, const struct sort_format_t &second)
{
  return first.footprint > second.footprint ? true : false;
}

void PrintTopFootPrintPath(THREADID threadid)
{
    uint64_t cntxtNum = 0;
    vector<struct sort_format_t> TmpList;

    fprintf(gTraceFile, "*************** Dump Data from Thread %d ****************\n", threadid);
    unordered_map<uint32_t, struct node_metric_t> &hmap = hmap_vector[threadid];
    unordered_map<uint32_t, struct node_metric_t>::iterator it;
    for (it = hmap.begin(); it != hmap.end(); ++it) {
        struct sort_format_t tmp;
        tmp.handle = (*it).first;
	tmp.footprint = (uint64_t)(*it).second.addressSetDecoded.size();
	tmp.fpNum = (uint64_t)(*it).second.addressSet.size();
        TmpList.emplace_back(tmp);
    }
    sort(TmpList.begin(), TmpList.end(), FootPrintCompare);
    PrintFullCallingContext(Ctxthndl);

}

VOID ThreadFiniFunc(THREADID threadid, const CONTEXT *ctxt, INT32 code, VOID *v)
{
    gettimeofday(&tv2, NULL);
    // traverse CCT bottom to up
    // decode first
    TraverseCCTBottomUp(threadid, DecodingFootPrint);
    // merge second
    TraverseCCTBottomUp(threadid, MergeFootPrint);
    gettimeofday(&tv3, NULL);
    // print the footprint for functions
    PIN_LockClient();
    PrintTopFootPrintPath(threadid);
    fprintf(gTraceFile, "online collection time %lf, offline analysis time %lf\n",tv2.tv_sec-tv1.tv_sec+(tv2.tv_usec-tv1.tv_usec)/1000000.0, tv3.tv_sec-tv2.tv_sec+(tv3.tv_usec-tv2.tv_usec)/1000000.0);
    PIN_UnlockClient();
}



VOID SimpleCCTQuery(THREADID id, void* addr, const uint32_t slot) {
// Only trigger crush at main thread !!!
    uint64_t Addr = (uint64_t)addr;
    if(crush_flag && id == 0)
    {
        PIN_LockClient();
        icount++;
        if(icount == rand_crush)
        {
          /*
          if (PIN_StopApplicationThreads(id))
             {
                 printf("Threads stopped by application thread %u\n", id);
                 fflush(stdout);

                 UINT32 nThreads = PIN_GetStoppedThreadCount();
                 cout<<"The value of nThread is "<<dec<<nThreads<<endl;
                 ASSERTX(nThreads <= threadnum);
                 for (UINT32 i = 0; i < nThreads; i++)
                 {
                     THREADID tid = PIN_GetStoppedThreadId(i);
                     const CONTEXT * ctxt = PIN_GetStoppedThreadContext(tid);
                     printf("  Thread %u, IP = %llx\n", tid,
                            (long long unsigned int)PIN_GetContextReg(ctxt, REG_INST_PTR));
                 }*/
                 cout << "Crush Happens"<<endl;
                 //
                 Ctxthndl = GetContextHandle(id, 0);
                 string filename;    // This will hold the source file name.
                 INT32 line = 0;     // This will hold the line number within the file.
                 PIN_LockClient();
                 PIN_GetSourceLocation(Addr, NULL, &line, &filename);
                 if(!filename.empty())
                 {
         	        char *cstr = new char[filename.length() + 1];
              	    strcpy(cstr, filename.c_str());
                   fprintf(gInfoFile,"\n\n Crush happens in 0x%lx #%s : line %d\n",Addr,cstr,line);
                   crash_line = line;
                   cout << "0x" << Addr  << " #" << filename << ":" << line << endl;
                 }
                 //void **Metric = GetContextHandle(id, 0);
                 PIN_AddThreadFiniFunction(ThreadFiniFunc, 0);

                 PIN_UnlockClient();
                 AfterCrush();
                 PrintResult();
                 //PIN_ExitThread(0);
                 /*
                 PIN_ResumeApplicationThreads(id);
                 printf("Threads resumed by application thread %u\n", id);
                 fflush(stdout);
             }*/

            PIN_ExitApplication(0);
        }
        PIN_UnlockClient();
    }


    if(icount <= INS_MAX)
    {
      void **metric = GetIPNodeMetric(id, 0);
      if (*metric == NULL) {
        // use ctxthndl as the key to associate footprint with the trace
        ContextHandle_t ctxthndl = GetContextHandle(id, 0);
        *metric = &(hmap_vector[id])[ctxthndl];
        (hmap_vector[id])[ctxthndl].addressSet.insert(Addr);
        //(hmap_vector[id])[ctxthndl].accessNum+=refSize;

        // check how many times write to a shared address
        // shared means that this address is read/write before this write
        //if (rwFlag && (*prevFlag))// && CheckDependence((uint64_t)addr, *prevAddr))
          //(hmap_vector[id])[ctxthndl].dependentNum+=refSize;
      }
      else {
        (static_cast<struct node_metric_t*>(*metric))->addressSet.insert(Addr);
        //(static_cast<struct node_metric_t*>(*metric))->accessNum+=refSize;
        //if (!rwFlag && (*prevFlag))// && CheckDependence((uint64_t)addr, *prevAddr))
          //(static_cast<struct node_metric_t*>(*metric))->dependentNum+=refSize;
      }
    }


}


ADDRINT captureWriteEa(ADDRINT tgt_ea)
{
   return tgt_ea;
}

VOID handleMemoryRead(THREADID threadid, ADDRINT read_address, UINT32 read_data_size)
{
    // lock in there???
    Byte read_data_buf[read_data_size];
    PIN_LockClient();
    MemRefMulti(threadid,
                CACHE_BASE::ACCESS_TYPE_LOAD,
                read_address,
                read_data_buf,
                read_data_size);
    PIN_UnlockClient();
}

VOID handleMemoryWrite(THREADID threadid, ADDRINT write_address, UINT32 write_data_size)
{
    PIN_LockClient();
    MemRefMulti(threadid,
                CACHE_BASE::ACCESS_TYPE_STORE,
                write_address,
                (Byte*) write_address,
                write_data_size);
    PIN_UnlockClient();
}

VOID InstrumentInsCallback(INS ins, VOID* v, const uint32_t slot) {
//VOID Instruction(INS ins, void * v){
    /*
    if (!INS_IsMemoryRead(ins) && !INS_IsMemoryWrite(ins)) return;
    if (INS_IsStackRead(ins) || INS_IsStackWrite(ins)) return;
    if (INS_IsBranchOrCall(ins) || INS_IsRet(ins)) return;
    UINT32 memOperands = INS_MemoryOperandCount(ins);
    for (UINT32 memOp = 0; memOp < memOperands; memOp++)
    {
        UINT32 refSize = INS_MemoryOperandSize(ins, memOp);
        if (INS_IsMemoryRead(ins))
          INS_InsertPredicatedCall(ins, IPOINT_BEFORE, (AFUNPTR)MemFunc, IARG_THREAD_ID, IARG_MEMORYOP_EA, memOp, IARG_BOOL, false, IARG_UINT32, refSize, IARG_END);
        else
          INS_InsertPredicatedCall(ins, IPOINT_BEFORE, (AFUNPTR)MemFunc, IARG_THREAD_ID, IARG_MEMORYOP_EA, memOp, IARG_BOOL, true, IARG_UINT32, refSize, IARG_END);
    }
    */
    //INS_InsertCall(ins, IPOINT_BEFORE, (AFUNPTR)docount,IARG_INST_PTR, IARG_END);

    INS_InsertPredicatedCall(ins, IPOINT_BEFORE, (AFUNPTR)SimpleCCTQuery, IARG_THREAD_ID, IARG_INST_PTR, IARG_UINT32, slot, IARG_END);

    if (INS_IsMemoryWrite(ins))
    {
        //const UINT32 size = INS_MemoryWriteSize(ins);
        //const AFUNPTR countFun = (size <= 4 ? (AFUNPTR) MemRefSingle : (AFUNPTR) MemRefMulti);

        // only predicated-on memory instructions access D-cache
        INS_InsertCall(
            ins, IPOINT_BEFORE,
            AFUNPTR(captureWriteEa),
            IARG_MEMORYWRITE_EA,
            IARG_RETURN_REGS, REG_INST_G0, //store IARG_MEMORYWRITE_EA in G0 ! IARG_MEMORY*_EA can only be used when it is IPONIT_BEFORE!
            IARG_END);

        IPOINT ipoint = INS_HasFallThrough(ins) ? IPOINT_AFTER : IPOINT_TAKEN_BRANCH;
        INS_InsertCall(ins, ipoint,
            AFUNPTR(handleMemoryWrite),
            IARG_THREAD_ID,
            //IARG_BOOL, INS_IsAtomicUpdate(ins),
            IARG_REG_VALUE, REG_INST_G0, // value of IARG_MEMORYWRITE_EA at IPOINT_BEFORE
            IARG_MEMORYWRITE_SIZE,
            IARG_END);
    }

    if (INS_IsMemoryRead(ins))
    {
        //const UINT32 size = INS_MemoryReadSize(ins);
        // we assume accesses <= 4 bytes stay in the same cache line
        // to speed up cache access lookups
        // const AFUNPTR countFun = (size <= 4 ? (AFUNPTR) MemRefSingle : (AFUNPTR) MemRefMulti);

        // only predicated-on memory instructions access D-cache
        INS_InsertCall(
            ins, IPOINT_BEFORE,
            AFUNPTR(handleMemoryRead),
            IARG_THREAD_ID,
            //IARG_BOOL, INS_IsAtomicUpdate(ins),
            IARG_MEMORYREAD_EA,
            IARG_MEMORYREAD_SIZE,
            IARG_END);
    }


    if(INS_HasMemoryRead2(ins))
    {
        INS_InsertCall(
            ins, IPOINT_BEFORE,
            AFUNPTR(handleMemoryRead),
            IARG_THREAD_ID,
            //IARG_BOOL, INS_IsAtomicUpdate(ins),
            IARG_MEMORYREAD2_EA,
            IARG_MEMORYREAD_SIZE,
            IARG_END
        );
    }
}
/* ===================================================================== */
/*
VOID Instruction(INS ins, void * v)
{
    UINT32 memOperands = INS_MemoryOperandCount(ins);

    // Instrument each memory operand. If the operand is both read and written
    // it will be processed twice.
    // Iterating over memory operands ensures that instructions on IA-32 with
    // two read operands (such as SCAS and CMPS) are correctly handled.
    for (UINT32 memOp = 0; memOp < memOperands; memOp++)
    {
        const UINT32 size = INS_MemoryOperandSize(ins, memOp);
        const BOOL   single = (size <= 4);

        if (INS_MemoryOperandIsWritten(ins, memOp))
        {
                if( single )
                {
                    INS_InsertPredicatedCall(
                        ins, IPOINT_BEFORE,  (AFUNPTR) MemRefSingle,
                        IARG_UINT32, CACHE_BASE::ACCESS_TYPE_STORE,
                        IARG_MEMORYWRITE_EA,
                        IARG_MEMORYREAD_SIZE,
                        IARG_END);

                }
                else
                {
                    INS_InsertPredicatedCall(
                        ins, IPOINT_BEFORE,  (AFUNPTR) MemRefMulti,
                        IARG_UINT32, CACHE_BASE::ACCESS_TYPE_STORE,
                        IARG_MEMORYWRITE_EA,
                        IARG_UINT32, size,
                        IARG_END);
                }
        }

        if (INS_MemoryOperandIsRead(ins, memOp))
        {
                if( single )
                {
                    INS_InsertPredicatedCall(
                        ins, IPOINT_BEFORE,  (AFUNPTR) MemRefSingle,
                        IARG_UINT32, CACHE_BASE::ACCESS_TYPE_LOAD,
                        IARG_MEMORYREAD_EA,
                        IARG_MEMORYREAD_SIZE,
                        IARG_END);

                }
                else
                {
                    INS_InsertPredicatedCall(
                        ins, IPOINT_BEFORE,  (AFUNPTR) MemRefMulti,
                        IARG_UINT32, CACHE_BASE::ACCESS_TYPE_LOAD,
                        IARG_MEMORYREAD_EA,
                        IARG_UINT32, size,
                        IARG_END);
                }
        }
    }
}
*/
/* ===================================================================== */

VOID Image(IMG img, VOID *v)
{
    // Instrument the malloc() and free() functions.  Print the input argument
    // of each malloc() or free(), and the return value of malloc().
    //
    //  Find and only need to find the malloc() function. //NOT j_malloc
    for (SEC sec = IMG_SecHead(img); SEC_Valid(sec); sec = SEC_Next(sec) )
    {
        for (RTN rtn = SEC_RtnHead(sec); RTN_Valid(rtn); rtn = RTN_Next(rtn) )
        {
            string rtnName = RTN_Name(rtn);
            if (rtnName.find(CRUSH_START) != string::npos){
              if(RTN_Valid(rtn)){
                RTN_Open(rtn);
                // Instrument start_crush() to print the input argument value and the return value.
        	      RTN_InsertCall(rtn, IPOINT_BEFORE,
                              AFUNPTR(StartCrush),
                              IARG_THREAD_ID,
                             IARG_END);
        	      RTN_Close(rtn);
              }
            }
            else if(rtnName.find(CRUSH_END) != string::npos)
            {
              if(RTN_Valid(rtn)){
                RTN_Open(rtn);
                // Instrument end_crush() to print the input argument value and the return value.
        	      RTN_InsertCall(rtn, IPOINT_BEFORE, (AFUNPTR)EndCrush,
                               IARG_END);
                RTN_Close(rtn);
              }
            }
            else if(rtnName.find(FLUSH_WHOLE_CACHE) != string::npos)
            {
              if(RTN_Valid(rtn)){
                RTN_Open(rtn);
                // Instrument start_crush() to print the input argument value and the return value.
        	      RTN_InsertCall(rtn, IPOINT_BEFORE,
                              AFUNPTR(StopThreadForFlushCache),
                              IARG_THREAD_ID,
                             IARG_END);
        	      RTN_Close(rtn);
              }
            }
            else if(rtnName.find(FLUSH) != string::npos)
            {
              if(RTN_Valid(rtn)){
                RTN_Open(rtn);
                // Instrument start_crush() to print the input argument value and the return value.
                RTN_InsertCall(rtn, IPOINT_BEFORE,
                              AFUNPTR(clflush),
                              IARG_FUNCARG_ENTRYPOINT_VALUE, 0,
                             IARG_END);
                RTN_Close(rtn);
              }
            }
            else if(rtnName.find(READONLY_DATA) != string::npos){
              if(RTN_Valid(rtn)){
                RTN_Open(rtn);

                // Instrument malloc() to print the input argument value and the return value.
                RTN_InsertCall(rtn, IPOINT_BEFORE, (AFUNPTR)GetWhatWeCare,
                               IARG_ADDRINT, READONLY_DATA,
                               IARG_FUNCARG_ENTRYPOINT_VALUE, 0,
                               IARG_FUNCARG_ENTRYPOINT_VALUE, 1,
                               IARG_FUNCARG_ENTRYPOINT_VALUE, 2,
                               IARG_END);

                RTN_Close(rtn);
              }
            }
            else if(rtnName.find(CRUCIAL_DATA) != string::npos){
              if(RTN_Valid(rtn)){
                RTN_Open(rtn);

                // Instrument malloc() to print the input argument value and the return value.
                RTN_InsertCall(rtn, IPOINT_BEFORE, (AFUNPTR)GetWhatWeCare,
                               IARG_ADDRINT, CRUCIAL_DATA,
                               IARG_FUNCARG_ENTRYPOINT_VALUE, 0,
                               IARG_FUNCARG_ENTRYPOINT_VALUE, 1,
                               IARG_FUNCARG_ENTRYPOINT_VALUE, 2,
                               IARG_END);

                RTN_Close(rtn);
              }
            }
            //  Find and only need to find the variable_wecare() function.
            else if(rtnName.find(CONSISTENT_DATA) != string::npos){
              if(RTN_Valid(rtn)){
                RTN_Open(rtn);

                // Instrument malloc() to print the input argument value and the return value.
                RTN_InsertCall(rtn, IPOINT_BEFORE, (AFUNPTR)GetWhatWeCare,
                               IARG_ADDRINT, CONSISTENT_DATA,
                               IARG_FUNCARG_ENTRYPOINT_VALUE, 0,
                               IARG_FUNCARG_ENTRYPOINT_VALUE, 1,
                               IARG_FUNCARG_ENTRYPOINT_VALUE, 2,
                               IARG_END);

                RTN_Close(rtn);
              }
            }
        }
     }
}

INT32 Usage()
{
    cerr << "This tool simulate mutilayler cache." << endl;
    cerr << endl << KNOB_BASE::StringKnobSummary() << endl;
    return -1;
}

int main(int argc, char* argv[]) {

    //srand((unsigned)time(NULL));
    //rand_crush = rand()%INS_MAX + 1;
    rand_crush = Random(INS_MAX);
    cout<<"The rand_crush num is "<<rand_crush<<endl;

    gettimeofday(&tv1, NULL);
    // Initialize PIN
    if(PIN_Init(argc, argv))
    {
        return Usage();
        return Usage2();
    }

    //Init cache simulator, to write general info
    SimulatorInit(argc, argv);

    // Initialize Symbols, we need them to report functions and lines
    PIN_InitSymbols();

    // Init Client
    ClientInit(argc, argv);
    // Intialize CCTLib
    PinCCTLibInit(INTERESTING_INS_ALL, gTraceFile, InstrumentInsCallback, 0);
    TraceFile.open(KnobOutputFile.Value().c_str());
    //TraceFile << hex;
    TraceFile.setf(ios::showbase);


    IMG_AddInstrumentFunction(Image, 0);

    //function inside Instruction moved to CCTLib InstrumentInsCallback
    //INS_AddInstrumentFunction(Instruction, 0);

    // fini function for post-mortem analysis
    //PIN_AddThreadFiniFunction(ThreadFiniFunc, 0);
    //PIN_AddFiniFunction(FiniFunc, 0);
    PIN_AddFiniFunction(Fini, 0);

    threadnum = KnobThreadNum.Value();
    pcachenum = KnobPrivateCacheNum.Value();
    //at most 2 thread share one private cache
    ASSERTX(threadnum == pcachenum);
    ASSERTX(threadnum <= MAX_THREAD_NUM);

    const UINT32 size = KnobCacheL1Size.Value() * KILO;
    const UINT32 linesize = KnobCacheL1LineSize.Value();
    const UINT32 associativity = KnobCacheL1Associativity.Value();

    ASSERTX(  associativity <= DL1::max_associativity );
    ASSERTX( size /(associativity*linesize )<= DL1::max_sets );

    // create the l1 cache object
    // dl1 = new DL1::CACHE("L1 Data Cache", size, linesize, associativity);
    /*
    dl1 = new CACHE*[pcachenum];
    for(UINT8 i = 0; i < pcachenum; i++)
    {
        dl1[i] = new DL1::CACHE("L1 Data Cache", size, linesize, associativity);
    }
    */
    pdl1 = new PRIVATE_CACHE(pcachenum, size, linesize, associativity);

    const UINT32 sizel2 = KnobCacheL2Size.Value() * MEGA;
    const UINT32 linesizel2 = KnobCacheL2LineSize.Value();
    const UINT32 associativityl2 = KnobCacheL2Associativity.Value();

    ASSERTX(  associativityl2 <= DL2::max_associativity );
    ASSERTX( sizel2 /(associativityl2*linesizel2 )<= DL2::max_sets );

    // create the l2 cache object
    dl2 = new DL2::CACHE("L2 Data Cache", sizel2, linesizel2, associativityl2);

    /*
    //disable dl3 for now
    const UINT32 sizel3 = KnobCacheL3Size.Value() * MEGA;
    const UINT32 linesizel3 = KnobCacheL3LineSize.Value();
    const UINT32 associativityl3 = KnobCacheL3Associativity.Value();

    ASSERTX(  associativityl3 <= DL3::max_associativity );
    ASSERTX( sizel3 /(associativityl3*linesizel3 )<= DL3::max_sets );

    // create the l3 cache object
    dl3 = new DL3::CACHE("L3 Data Cache", sizel3, linesizel3, associativityl3);
    */

    // Launch program now
    PIN_StartProgram();
    gettimeofday(&tv4, NULL);
    printf("runtime is %lf\n",tv4.tv_sec-tv1.tv_sec+(tv4.tv_usec-tv1.tv_usec)/1000000.0);
    return 0;
}

