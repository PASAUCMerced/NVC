/*BEGIN_LEGAL
Intel Open Source License

Copyright (c) 2002-2017 Intel Corporation. All rights reserved.

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
A PARTMEMULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE INTEL OR
ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVMEMES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRMEMT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
END_LEGAL */
/*! @file
 *  This file contains a configurable cache class
 */

#ifndef PIN_CACHE_H
#define PIN_CACHE_H

#include "globals.H"
#include "memory.H"
#include "pin_util.H"
#include <deque>
using namespace std;

//defind the memory, how many blocks the memroy has, define as unlimited memory
MEMORY memory(1*1024);



/*!
 *  @brief Cache tag - self clearing on creation
 */
class CACHE_TAG
{
  private:
    ADDRINT _tag;

  public:
    CACHE_TAG(ADDRINT tag = 0) { _tag = tag; }
    bool operator==(const CACHE_TAG &right) const { return _tag == right._tag; }
    operator ADDRINT() const { return _tag; }
};

/*!
 *  @brief Cache data - self clearing on creation
 */
class CACHE_DATA
{
  private:
    UINT8 _data[BLOCK_SIZE]={0}; //Store data as byte
    UINT8 _lineSize;

  public:
    CACHE_DATA(UINT8 lineSize = 64) {
        _lineSize = lineSize;
        //for(UINT8 i = 0; i<_lineSize; i++)
        //    _data[i] = 0;
     }

    VOID SetData(UINT32 index, UINT8 size, ADDRINT data){
      //using ADDRINT(UINT64) as input, seperate it into UINT8
        const UINT8 MASK = 0xff;
        ASSERTX(index + size <= _lineSize);
        //_data[index] = data;
        for(UINT8 i=0; i<size; i++)
        {
            _data[index+i] = (data >> (8*i)) & MASK;
        }
    }

    VOID Set(UINT32 index, UINT8 data){
      //Set one byte, Using UINT8 as input and set the data derectly
        ASSERTX(index < _lineSize);
        ASSERTX(index >= 0);
        _data[index] = data;
    }

    VOID SetWholeCacheLine(UINT8 v[BLOCK_SIZE])
    {
        std::copy(v, v + _lineSize, _data);
    }

    UINT8 GetData(UINT32 index){ //for test
      //Get data's value, read it byte by byte
        ASSERTX(index < _lineSize);
        return _data[index];
    }

    UINT8* Get(UINT32 index = 0){
      //Get the data we want's address
        ASSERTX(index < _lineSize);
        return &_data[index];
    }

    VOID GetWholeCacheLine(UINT8 (&v)[BLOCK_SIZE])
    {
        std::copy(_data, _data + _lineSize, v);
    }

    CACHE_DATA& operator=(const CACHE_DATA& other)
    {
        if(this != &other)
        {
          std::copy(other._data, other._data + other._lineSize, _data);
        }
        return *this;
    }
};


 /*!
  *  @brief Valid Bit  -  0 stands for the cache line is invalid (Multiply processor using)
  */
/*  class CACHE_FLAG
  {
    private:
      UINT8 _flag;

    public:
      CACHE_FLAG(UINT8 flag = 0) { _flag = flag; }
      bool operator==(const CACHE_FLAG &right) const { return _flag == right._flag; }
      operator UINT8() const { return _flag; }
  };*/

  /*!
   *  @brief Dirty Bit  -  1 stands for the cache line is dirty(has different value from memory)
   */
   class CACHE_DIRTY
   {
     private:
       UINT8 _dirty;

     public:
       CACHE_DIRTY(UINT8 dirty = 0) { _dirty = dirty; } //initialize as not dirty
       bool operator==(const CACHE_DIRTY &right) const { return _dirty == right._dirty; }
       bool ifdirty(){
         if(_dirty>0)
            return true;
          else
            return false;
          }
       operator UINT8() const { return _dirty; }
       //void get() {cout<<+_dirty<<endl;}
       void selfincrease(){_dirty++;}
   };

   /*!
    *  @brief valid Bit  -  1 stands for the cache line has been occupied
    */
    class CACHE_VALID
    {
      private:
        UINT8 _valid;

      public:
        CACHE_VALID(UINT8 valid = 0) { _valid = valid; } //initialize as not dirty
        bool operator==(const CACHE_VALID &right) const { return _valid == right._valid; }
        operator UINT8() const { return _valid; }
    };

   /*!
    * @bried bitmap - array of bitset and easy to set(not in good shape because difficult to detect 0) //still can improve
    */
    class CACHE_MAP
    {
        private:
            typedef std::bitset<BLOCK_SIZE> REFERENCE;
            typedef boost::array<REFERENCE, BLOCK_SIZE> MAP;
            MAP map;
            UINT32 _size;
        public:
            CACHE_MAP(UINT32 size = BLOCK_SIZE) {
              _size = size;
              for(UINT32 i = 0; i < _size; i++)
              {
                map[i].reset();
              }
            } //initialize the size of the bit map

            VOID setsize(UINT32 size) //must call this function before using the map!!!
            {
                _size = size;
            }

            UINT32 getsize()
            {
              return _size;
            }

            VOID rowset(UINT8 index){
                //ASSERTX(index<_size);
                map[index].set();
            }
            VOID columnreset(UINT8 index){
                //ASSERTX(index<_size);
                for(UINT32 i = 0; i<_size; i++)
                {
                   map[i].reset(index);
                }
            }
            BOOL linenone(UINT8 index){
                ASSERTX(index<_size);
                return map[index].none();
            }

            UINT32 findemptyline(){
              UINT8 setnum = BLOCK_SIZE - _size;
              for(UINT32 i = 0; i<_size; i++)
              {
                  if(map[i].none())
                    return i;
                  else if(map[i].count() == setnum)
                    return i;
              }
              return -1;
            }
    };


    /*!
     * @BIP cache replacement algo ISCA 07'
     * LRU Insertion Policy (LIP) which places all incoming lines in the LRU position
     * These lines are promoted from the LRU position to the MRU position only if they get referenced while in the LRU position
     * LIP prevents thrashing for workloads whose working set is greater than the cache size and obtains near-optimal hit rates for workloads that have a cyclic access pattern
     * LIP can easily be implemented by avoiding the recency update at insertion.
     *
     *   Bimodal Insertion Policy (BIP)
     *   similar as LIP, except that BIP infrequently (with a low probability) places the incoming line in the MRU position
     */
     class BIP_REPLACE{
        private:
            std::deque<UINT32> d;
            UINT32 _size;
            double t;
        public:
            BIP_REPLACE(UINT32 size = BLOCK_SIZE)
            {
              _size = size;
              t = 1/32;
            }

            VOID setsize(UINT32 size) //must call this function before using the map!!!
            {
                _size = size;
            }

            UINT32 findemptyline(){
              ASSERTX(d.size()<=_size);
              //cout<<"d size is "<<d.size()<<endl;
              double r = ((double) rand() / (RAND_MAX));
              //cout<<"r = "<<r<<endl;
              if(r < t){
                //insert at MRU position
                if(d.size() == _size)
                {
                  UINT32 index = d.back();
                  d.pop_back();
                  return index;
                }
                else{
                  return d.size();
                }
              }
              else{
                //insert at LRU position
                if(d.size() == _size)
                {
                  UINT8 index = d.back();
                  d.pop_back();
                  d.push_front(index);
                  return index;
                }
                else{
                  //cout<<"I should be here!"<<endl;
                  return d.size();
                }
              }

            }

            VOID update(UINT32 index){
              if( d.size()!=0 && d.back() == index)
              {
                  d.pop_back();
                  d.push_front(index);
              }
              else if(d.size() == 0){
                d.push_front(index);
              }
            }
     };


    /*!
     * @bried CACHE_LINE - record all the info that a cache line should contain.
     * for evict propose and same level data trans
     * evict should never consisder if it is dirty or not, which can make sure it is a inclusive cache, but will have extra expensive like load(Still need to be considered!)
     * inclusive cache need l1 cache use Wirte-non-allocate to make sure
     * use for evaction
     */
     class CACHE_LINE{
     public:
          BOOL if_evict;
          ADDRINT _addr;
          CACHE_DIRTY _dirty;
          CACHE_DATA _data;
     };

/*!
 * Everything related to cache sets
 */
namespace CACHE_SET
{

/*!
 *  @brief Cache set direct mapped
 */
class DIRECT_MAPPED
{
  private:
    CACHE_TAG _tag;

  public:
    DIRECT_MAPPED(UINT32 associativity = 1) { ASSERTX(associativity == 1); }

    VOID SetAssociativity(UINT32 associativity) { ASSERTX(associativity == 1); }
    UINT32 GetAssociativity(UINT32 associativity) { return 1; }

    UINT32 Find(CACHE_TAG tag) { return(_tag == tag); }
    //VOID Replace(CACHE_TAG tag,UINT32 lineindex, CACHE_VALID valid) { _tag = tag; _data = data; _valid = valid;}
    VOID Flush() { _tag = 0; }
};

/*!
 *  @brief Cache set with round robin replacement
 */
template <UINT32 MAX_ASSOCIATIVITY = 4>
class ROUND_ROBIN
{
  private:
    CACHE_TAG _tags[MAX_ASSOCIATIVITY];
    CACHE_DATA _data[MAX_ASSOCIATIVITY];
    CACHE_DIRTY _dirty[MAX_ASSOCIATIVITY];
    CACHE_MAP _map;
    UINT32 _tagsLastIndex;
    UINT32 _nextReplaceIndex;
    UINT32 _hitindex;
    UINT8 _lineShift;
    UINT8 _lineSize;

  public:
    ROUND_ROBIN(UINT32 associativity = MAX_ASSOCIATIVITY)
      : _tagsLastIndex(associativity - 1)
    {
        ASSERTX(associativity <= MAX_ASSOCIATIVITY);
        _nextReplaceIndex = _tagsLastIndex;
        for (INT32 index = _tagsLastIndex; index >= 0; index--)
        {
            _tags[index] = CACHE_TAG(0);
            _data[index] = CACHE_DATA();
            _dirty[index] = CACHE_DIRTY(0);
        }
    }

    VOID SetAssociativity(UINT32 associativity)
    {//must be called when initialize a cache set!
        ASSERTX(associativity <= MAX_ASSOCIATIVITY);
        _tagsLastIndex = associativity - 1;
        _nextReplaceIndex = _tagsLastIndex;
        _hitindex = -1;
        _map.setsize(associativity);
    }

    UINT32 GetAssociativity(UINT32 associativity) {
      return _tagsLastIndex + 1;
    }

    VOID SetLinesize(UINT8 lineSize)
    {//must be called when initialize a cache set!
        _lineSize = lineSize;
        _lineShift= FloorLog2(lineSize);
    }

    UINT32 Find(CACHE_TAG tag)
    {
        bool result = true;

        for (INT32 index = _tagsLastIndex; index >= 0; index--)
        {
            // this is an ugly micro-optimization, but it does cause a
            // tighter assembly loop for ARM that way ...
            if(_tags[index] == tag){
              _hitindex = index;
              goto end;
            }
        }
        _hitindex = -1;
        result = false;

        end: return result;
    }

    VOID Replace(CACHE_TAG tag)
    {
        // g++ -O3 too dumb to do CSE on following lines?!
        //_nextReplaceIndex = _map.findemptyline();
        const UINT32 index = _nextReplaceIndex;

        if(_dirty[index] == CACHE_DIRTY(1))
        {
            WriteBackCacheLine(index);
        }

        _tags[index] = tag;

        Load(index);
        // condition typically faster than modulo
        _nextReplaceIndex = (index == 0 ? _tagsLastIndex : index - 1);
    }

    VOID Load(UINT32 index)
    {
        ADDRINT addr = _tags[index] << _lineShift;
        UINT8 value[64];
        BOOL hit = memory.ReadAsBlock(addr, value);
        if(!hit){
            std::fill_n(value, BLOCK_SIZE, 0);  //initialize the block!
        }

        _data[index].SetWholeCacheLine(value);
        _dirty[index] = CACHE_DIRTY(0); //the cache line has been cleaned!
    }

    VOID Update(UINT32 lineindex, UINT8 size, UINT8 v[])
    {
        //Set data
        ASSERTX(_hitindex >= 0);
        UINT32 index = _hitindex;

        for(UINT8 i=0; i<size; i++)
        {
            _data[index].Set(lineindex+i,v[i]);
        }
        _dirty[index] = CACHE_DIRTY(1);  //set Dirty
        //WriteBackCacheLine(index);
        //flush the consistent data!
        /*
        for(UINT8 i = 0; i<consistent_variable.size();i++)
        {
            ADDRINT temp_tag = consistent_variable[i] >> _lineShift;
            if(temp_tag == _tags[index])
            {
              //  cout<<"Consistent value hit!"<<endl;
                WriteBackCacheLine(index);
            }
        }*/
    }

    UINT8 Read(UINT32 lineindex)
    { //Read data in Cache byte by byte! need to call fuction find first!
        ASSERTX(_hitindex >= 0);
        return _data[_hitindex].GetData(lineindex);
    }

    VOID Flush()
    {
        for (INT32 index = _tagsLastIndex; index >= 0; index--)
        {
            if(_dirty[index] == CACHE_DIRTY(1))
            {//if data in this persition alreay dirty
                WriteBackCacheLine(index);
            }
         }
         _nextReplaceIndex=_tagsLastIndex;
    }

    VOID WriteBackCacheLine(INT32 index)
    {
        //flush the whole cacheline
        ADDRINT addr = _tags[index] << _lineShift;
        UINT8 data[64];
        _data[index].GetWholeCacheLine(data);

        //write into memory
        memory.WriteAsBlock(addr, data);

        _dirty[index] = CACHE_DIRTY(0);
        //no need to clean the cache
    }

};

/*!
 *  @brief Cache set with Last Recently Use replacement
 */
template <UINT32 MAX_ASSOCIATIVITY = 4>
class LRU
{
  private:
    CACHE_TAG _tags[MAX_ASSOCIATIVITY];
    CACHE_DATA _data[MAX_ASSOCIATIVITY];
    CACHE_DIRTY _dirty[MAX_ASSOCIATIVITY];
    CACHE_VALID _valid[MAX_ASSOCIATIVITY];
    CACHE_MAP _map;
    UINT32 _tagsLastIndex;
    UINT32 _nextReplaceIndex;
    UINT32 _hitindex;
    UINT8 _lineShift;
    UINT8 _lineSize;

  public:
    LRU(UINT32 associativity = MAX_ASSOCIATIVITY)
    :_tagsLastIndex(MAX_ASSOCIATIVITY-1)
    {
        ASSERTX(associativity <= MAX_ASSOCIATIVITY);
        for (INT32 index = _tagsLastIndex; index >= 0; index--)
        {
            _tags[index] = CACHE_TAG(0);
            _data[index] = CACHE_DATA();
            _dirty[index] = CACHE_DIRTY(0);
            _valid[index] = CACHE_VALID(0);
        }
    }

    VOID SetAssociativity(UINT32 associativity)
    {
        ASSERTX(associativity <= MAX_ASSOCIATIVITY);
        _tagsLastIndex = associativity - 1;
        _map.setsize(associativity);
        //_nextReplaceIndex = _map.findemptyline();
        //Alert inform
        //ASSERTX(_nextReplaceIndex >= 0);
        _hitindex = -1;

    }

    UINT32 GetAssociativity(UINT32 associativity)
    {
        return _tagsLastIndex + 1;
    }

    VOID SetLinesize(UINT8 lineSize)
    {//must be called when initialize a cache set!
        _lineSize = lineSize;
        _lineShift= FloorLog2(lineSize);
    }

    VOID UpdateBitMap(UINT32 index)
    {
        ASSERTX(index >= 0);
        ASSERTX(index<=_tagsLastIndex);
        _map.rowset(index);
        _map.columnreset(index);

    }

    UINT32 PreFind(CACHE_TAG tag)
    {
        bool result = true;
        for (INT32 index = 0 ; index <= _tagsLastIndex; index++)
        {
            // this is an ugly micro-optimization, but it does cause a
            // tighter assembly loop for ARM that way ...
            if(_tags[index] == tag &&  _valid[index] == CACHE_VALID(1))
            {
              //_valid[index] = CACHE_VALID(0);
              goto end;
            }
        }
        result = false;
        end: return result;
    }

    UINT32 SetInvalid(CACHE_TAG tag)
    {
        bool result = true;
        for (INT32 index = 0 ; index <= _tagsLastIndex; index++)
        {
            // this is an ugly micro-optimization, but it does cause a
            // tighter assembly loop for ARM that way ...
            if(_tags[index] == tag &&  _valid[index] == CACHE_VALID(1))
            {
              _valid[index] = CACHE_VALID(0);
              goto end;
            }
        }
        result = false;
        end: return result;
    }

    UINT32 Find(CACHE_TAG tag)
    {
        bool result = true;
        for (INT32 index = 0 ; index <= _tagsLastIndex; index++)
        {
            // this is an ugly micro-optimization, but it does cause a
            // tighter assembly loop for ARM that way ...
            if(_tags[index] == tag && _valid[index] == CACHE_VALID(1))
            {
              _hitindex = index;
              UpdateBitMap(index);
              goto end;
            }
        }
        _hitindex = -1;
        result = false;

        end: return result;
    }

    VOID Replace(CACHE_TAG tag, CACHE_LINE &evict_info)
    {
        // g++ -O3 too dumb to do CSE on following lines?!
        _nextReplaceIndex = _map.findemptyline();
        ASSERTX(_nextReplaceIndex >= 0);
        const UINT32 index = _nextReplaceIndex;
        /*
        if(_dirty[index] == CACHE_DIRTY(1))
        {//if data in this persition alreay dirty
            WriteBackCacheLine(index);
            replace_addr = _tags[index] << _lineShift;
        }*/
        ADDRINT tag_addr = tag << _lineShift;

        if(_valid[index] == CACHE_VALID(1))
        {//need to evict, record all the infomation from orig data in that cache line
            evict_info.if_evict = true;
            evict_info._addr = _tags[index] << _lineShift;
            evict_info._data = _data[index];
            evict_info._dirty = _dirty[index];
        }
        _tags[index] = tag;
        //set valid
        _valid[index] = CACHE_VALID(1);
        //Load(index);
        //UpdateBitMap Here!!!
        UpdateBitMap(index);
        _hitindex = index;
    }

    VOID Load(CACHE_LINE cache_line)
    {
        ASSERTX(_hitindex>=0);
        const UINT8 index = _hitindex;
        _data[index] = cache_line._data;
        _dirty[index] = cache_line._dirty;

        //_valid[index] = CACHE_VALID(1);
    }

    VOID Update(UINT32 lineindex, UINT8 size, UINT8 v[])
    {
        //Set data
        ASSERTX(_hitindex >= 0);
        UINT32 index = _hitindex;

        for(UINT8 i=0; i<size; i++)
        {
            _data[index].Set(lineindex+i,v[i]);
        }
        //_dirty[index] = CACHE_DIRTY(1);  //set Dirty
        _dirty[index].selfincrease();
        //WriteBackCacheLine(index);
        //flush the consistent data!
/*
        for(UINT8 i = 0; i<consistent_variable.size();i++)
        {
            ADDRINT temp_tag = consistent_variable[i] >> _lineShift;
            if(temp_tag == _tags[index])
            {
              //  cout<<"Consistent value hit!"<<endl;
                WriteBackCacheLine(index);
            }
        }
        */
    }

    VOID Flush()
    {
        for (INT32 index = _tagsLastIndex; index >= 0; index--)
        {
            //cout<<"dirty value"<<endl;
            if(_dirty[index].ifdirty()&& _valid[index] == CACHE_VALID(1))
            {//if data in this persition alreay dirty
                //_dirty[index].get();
                WriteBackCacheLine(index);
                //cache_count++;
            }
        }
    }

    VOID WriteBackCacheLine(INT32 index)
    {
        //flush the whole cacheline
        ADDRINT addr = _tags[index] << _lineShift;
        UINT8 data[64];
        _data[index].GetWholeCacheLine(data);
        /*
        if(checkFlush)
        {
          for(UINT8 ii=0; ii<64; ii++)
          {
            cout<<+data[ii]<<endl;
          }
        }*/

        //write into memory
        memory.WriteAsBlock(addr, data);

        _dirty[index] = CACHE_DIRTY(0);
        //_valid[index] = CACHE_VALID(0);
        //no need to clean the cache
    }

    void FlushCacheLine(INT32 index)
    {
        //flush the whole cacheline
        ADDRINT addr = _tags[index] << _lineShift;
        UINT8 data[64];
        _data[index].GetWholeCacheLine(data);
        /*
        if(checkFlush)
        {
          for(UINT8 ii=0; ii<64; ii++)
          {
            cout<<+data[ii]<<endl;
          }
        }*/

        //write into memory
        memory.WriteAsBlock(addr, data);

        _dirty[index] = CACHE_DIRTY(0);
        _valid[index] = CACHE_VALID(0);
        //no need to clean the cache
    }

    UINT8 Read(UINT32 lineindex)
    { //Read data in Cache byte by byte! need to call fuction find first!
        ASSERTX(_hitindex >= 0);
        return _data[_hitindex].GetData(lineindex);
    }

    VOID ReadCacheLine(CACHE_LINE &cache_line)
    {
        ASSERTX(_hitindex >= 0);
        const UINT8 index = _hitindex;
        cache_line._data = _data[index];
        cache_line._dirty = _dirty[index];
    }

    VOID CountDirty()
    {
      for (INT32 index = _tagsLastIndex; index >= 0; index--)
      {
          //cout<<"dirty value"<<endl;
          if(_dirty[index].ifdirty()&& _valid[index] == CACHE_VALID(1))
          {//if data in this persition alreay dirty
              ADDRINT dirty_addr =  _tags[index] << _lineShift;
              MEM::iterator it = dirty_count.find(dirty_addr);
              if(it == dirty_count.end())
              {
                UINT8 data[BLOCK_SIZE];
                _data[index].GetWholeCacheLine(data);
                BLOCK newline;
                std::copy(data,data + BLOCK_SIZE, newline.begin());
                dirty_count.emplace(std::make_pair(dirty_addr, newline));
              }
          }
      }
    }
};



/*!
 *  @brief Cache set with Bimodal Insertion Policy
 */
template <UINT32 MAX_ASSOCIATIVITY = 4>
class BIPLRU
{
  private:
    CACHE_TAG _tags[MAX_ASSOCIATIVITY];
    CACHE_DATA _data[MAX_ASSOCIATIVITY];
    CACHE_DIRTY _dirty[MAX_ASSOCIATIVITY];
    CACHE_VALID _valid[MAX_ASSOCIATIVITY];
    BIP_REPLACE _bip;
    UINT32 _tagsLastIndex;
    UINT32 _nextReplaceIndex;
    UINT32 _hitindex;
    UINT8 _lineShift;
    UINT8 _lineSize;

  public:
    BIPLRU(UINT32 associativity = MAX_ASSOCIATIVITY)
    :_tagsLastIndex(MAX_ASSOCIATIVITY-1)
    {
        ASSERTX(associativity <= MAX_ASSOCIATIVITY);
        for (INT32 index = _tagsLastIndex; index >= 0; index--)
        {
            _tags[index] = CACHE_TAG(0);
            _data[index] = CACHE_DATA();
            _dirty[index] = CACHE_DIRTY(0);
            _valid[index] = CACHE_VALID(0);
        }
    }

    VOID SetAssociativity(UINT32 associativity)
    {
        ASSERTX(associativity <= MAX_ASSOCIATIVITY);
        _tagsLastIndex = associativity - 1;
        _bip.setsize(associativity);
        //_nextReplaceIndex = _map.findemptyline();
        //Alert inform
        //ASSERTX(_nextReplaceIndex >= 0);
        _hitindex = -1;

    }

    UINT32 GetAssociativity(UINT32 associativity)
    {
        return _tagsLastIndex + 1;
    }

    VOID SetLinesize(UINT8 lineSize)
    {//must be called when initialize a cache set!
        _lineSize = lineSize;
        _lineShift= FloorLog2(lineSize);
    }


    UINT32 PreFind(CACHE_TAG tag)
    {
        bool result = true;
        for (INT32 index = 0 ; index <= _tagsLastIndex; index++)
        {
            // this is an ugly micro-optimization, but it does cause a
            // tighter assembly loop for ARM that way ...
            if(_tags[index] == tag &&  _valid[index] == CACHE_VALID(1))
            {
              //_valid[index] = CACHE_VALID(0);
              goto end;
            }
        }
        result = false;
        end: return result;
    }

    UINT32 SetInvalid(CACHE_TAG tag)
    {
        bool result = true;
        for (INT32 index = 0 ; index <= _tagsLastIndex; index++)
        {
            // this is an ugly micro-optimization, but it does cause a
            // tighter assembly loop for ARM that way ...
            if(_tags[index] == tag &&  _valid[index] == CACHE_VALID(1))
            {
              _valid[index] = CACHE_VALID(0);
              goto end;
            }
        }
        result = false;
        end: return result;
    }

    UINT32 Find(CACHE_TAG tag)
    {
        bool result = true;
        for (INT32 index = 0 ; index <= _tagsLastIndex; index++)
        {
            // this is an ugly micro-optimization, but it does cause a
            // tighter assembly loop for ARM that way ...
            if(_tags[index] == tag && _valid[index] == CACHE_VALID(1))
            {
              _hitindex = index;
              _bip.update(index);
              goto end;
            }
        }
        _hitindex = -1;
        result = false;

        end: return result;
    }

    VOID Replace(CACHE_TAG tag, CACHE_LINE &evict_info)
    {
        // g++ -O3 too dumb to do CSE on following lines?!
        _nextReplaceIndex = _bip.findemptyline();
        ASSERTX(_nextReplaceIndex >= 0);
        const UINT32 index = _nextReplaceIndex;
        //cout<< "index here is "<<index<<endl;
        /*
        if(_dirty[index] == CACHE_DIRTY(1))
        {//if data in this persition alreay dirty
            WriteBackCacheLine(index);
            replace_addr = _tags[index] << _lineShift;
        }*/
        ADDRINT tag_addr = tag << _lineShift;

        if(_valid[index] == CACHE_VALID(1))
        {//need to evict, record all the infomation from orig data in that cache line
            evict_info.if_evict = true;
            evict_info._addr = _tags[index] << _lineShift;
            evict_info._data = _data[index];
            evict_info._dirty = _dirty[index];
        }
        _tags[index] = tag;
        //set valid
        _valid[index] = CACHE_VALID(1);
        //Load(index);
        //UpdateBitMap Here!!!
        _bip.update(index);
        _hitindex = index;
    }

    VOID Load(CACHE_LINE cache_line)
    {
        ASSERTX(_hitindex>=0);
        const UINT8 index = _hitindex;
        _data[index] = cache_line._data;
        _dirty[index] = cache_line._dirty;

        //_valid[index] = CACHE_VALID(1);
    }

    VOID Update(UINT32 lineindex, UINT8 size, UINT8 v[])
    {
        //Set data
        ASSERTX(_hitindex >= 0);
        UINT32 index = _hitindex;

        for(UINT8 i=0; i<size; i++)
        {
            _data[index].Set(lineindex+i,v[i]);
        }
        //_dirty[index] = CACHE_DIRTY(1);  //set Dirty
        _dirty[index].selfincrease();
        //WriteBackCacheLine(index);
        //flush the consistent data!
/*
        for(UINT8 i = 0; i<consistent_variable.size();i++)
        {
            ADDRINT temp_tag = consistent_variable[i] >> _lineShift;
            if(temp_tag == _tags[index])
            {
              //  cout<<"Consistent value hit!"<<endl;
                WriteBackCacheLine(index);
            }
        }
        */
    }

    VOID Flush()
    {
        for (INT32 index = _tagsLastIndex; index >= 0; index--)
        {
            //cout<<"dirty value"<<endl;
            if(_dirty[index].ifdirty()&& _valid[index] == CACHE_VALID(1))
            {//if data in this persition alreay dirty
                //_dirty[index].get();
                WriteBackCacheLine(index);
                //cache_count++;
            }
        }
    }

    VOID WriteBackCacheLine(INT32 index)
    {
        //flush the whole cacheline
        ADDRINT addr = _tags[index] << _lineShift;
        UINT8 data[64];
        _data[index].GetWholeCacheLine(data);
        /*
        if(checkFlush)
        {
          for(UINT8 ii=0; ii<64; ii++)
          {
            cout<<+data[ii]<<endl;
          }
        }*/

        //write into memory
        memory.WriteAsBlock(addr, data);

        _dirty[index] = CACHE_DIRTY(0);
        //_valid[index] = CACHE_VALID(0);
        //no need to clean the cache
    }

    void FlushCacheLine(INT32 index)
    {
        //flush the whole cacheline
        ADDRINT addr = _tags[index] << _lineShift;
        UINT8 data[64];
        _data[index].GetWholeCacheLine(data);
        /*
        if(checkFlush)
        {
          for(UINT8 ii=0; ii<64; ii++)
          {
            cout<<+data[ii]<<endl;
          }
        }*/

        //write into memory
        memory.WriteAsBlock(addr, data);

        _dirty[index] = CACHE_DIRTY(0);
        _valid[index] = CACHE_VALID(0);
        //no need to clean the cache
    }

    UINT8 Read(UINT32 lineindex)
    { //Read data in Cache byte by byte! need to call fuction find first!
        ASSERTX(_hitindex >= 0);
        return _data[_hitindex].GetData(lineindex);
    }

    VOID ReadCacheLine(CACHE_LINE &cache_line)
    {
        ASSERTX(_hitindex >= 0);
        const UINT8 index = _hitindex;
        cache_line._data = _data[index];
        cache_line._dirty = _dirty[index];
    }

    VOID CountDirty()
    {
      for (INT32 index = _tagsLastIndex; index >= 0; index--)
      {
          //cout<<"dirty value"<<endl;
          if(_dirty[index].ifdirty()&& _valid[index] == CACHE_VALID(1))
          {//if data in this persition alreay dirty
              ADDRINT dirty_addr =  _tags[index] << _lineShift;
              MEM::iterator it = dirty_count.find(dirty_addr);
              if(it == dirty_count.end())
              {
                UINT8 data[BLOCK_SIZE];
                _data[index].GetWholeCacheLine(data);
                BLOCK newline;
                std::copy(data,data + BLOCK_SIZE, newline.begin());
                dirty_count.emplace(std::make_pair(dirty_addr, newline));
              }
          }
      }
    }
};

}
// namespace CACHE_SET

namespace CACHE_ALLOC
{
    typedef enum
    {
        STORE_ALLOCATE,
        STORE_NO_ALLOCATE
    } STORE_ALLOCATION;
}

/*!
 *  @brief Generic cache base class; no allocate specialization, no cache set specialization
 */
class CACHE_BASE
{
  public:
    // types, constants
    typedef enum
    {
        ACCESS_TYPE_LOAD,
        ACCESS_TYPE_STORE,
        ACCESS_TYPE_NUM
    } ACCESS_TYPE;

  protected:
    static const UINT32 HIT_MISS_NUM = 2;
    CACHE_STATS _access[ACCESS_TYPE_NUM][HIT_MISS_NUM];

  private:
    // input params
    const std::string _name;
    const UINT32 _cacheSize;
    const UINT32 _lineSize;
    const UINT32 _associativity;
    UINT32 _numberOfFlushes;
    UINT32 _numberOfResets;

    // computed params
    const UINT32 _lineShift;
    const UINT32 _setIndexMask;

    CACHE_STATS SumAccess(bool hit) const
    {
        CACHE_STATS sum = 0;

        for (UINT32 accessType = 0; accessType < ACCESS_TYPE_NUM; accessType++)
        {
            sum += _access[accessType][hit];
        }

        return sum;
    }

  protected:
    UINT32 NumSets() const { return _setIndexMask + 1; }

  public:
    // constructors/destructors
    CACHE_BASE(std::string name, UINT32 cacheSize, UINT32 lineSize, UINT32 associativity);

    // accessors
    UINT32 CacheSize() const { return _cacheSize; }
    UINT32 LineSize() const { return _lineSize; }
    UINT32 Associativity() const { return _associativity; }
    //
    CACHE_STATS Hits(ACCESS_TYPE accessType) const { return _access[accessType][true];}
    CACHE_STATS Misses(ACCESS_TYPE accessType) const { return _access[accessType][false];}
    CACHE_STATS Accesses(ACCESS_TYPE accessType) const { return Hits(accessType) + Misses(accessType);}
    CACHE_STATS Hits() const { return SumAccess(true);}
    CACHE_STATS Misses() const { return SumAccess(false);}
    CACHE_STATS Accesses() const { return Hits() + Misses();}

    CACHE_STATS Flushes() const { return _numberOfFlushes;}
    CACHE_STATS Resets() const { return _numberOfResets;}

    VOID SplitAddress(const ADDRINT addr, CACHE_TAG & tag, UINT32 & setIndex) const
    {
        tag = addr >> _lineShift;
        setIndex = tag & _setIndexMask;
        //cout<<"Address is "<<hex<<addr<<". Tag is "<<tag<<endl;
        //ADDRINT temp = tag << _lineShift;
        //cout<<"At the begining of a cacheline is "<<temp<<endl;
    }

    VOID SplitAddress(const ADDRINT addr, CACHE_TAG & tag, UINT32 & setIndex, UINT32 & lineIndex) const
    {
        const UINT32 lineMask = _lineSize - 1;
        lineIndex = addr & lineMask;
        SplitAddress(addr, tag, setIndex);
    }
    VOID FindBiginingAddressofCacheline(const ADDRINT addr, ADDRINT &begin_addr)
    {
        ADDRINT MASK = UINT64_MAX;
        MASK = MASK << _lineShift;
        begin_addr = addr & MASK;
        //cout<<"Address is "<<hex<<addr<<". Begin address is "<<begin_addr<<endl;
    }
    VOID IncFlushCounter()
    {
	     _numberOfFlushes += 1;
    }

    VOID IncResetCounter()
    {
	     _numberOfResets += 1;
    }

    std::ostream & StatsLong(std::ostream & out) const;
};

CACHE_BASE::CACHE_BASE(std::string name, UINT32 cacheSize, UINT32 lineSize, UINT32 associativity)
  : _name(name),
    _cacheSize(cacheSize),
    _lineSize(lineSize),
    _associativity(associativity),
    _lineShift(FloorLog2(lineSize)),
    _setIndexMask((cacheSize / (associativity * lineSize)) - 1)
{

    ASSERTX(IsPower2(_lineSize));
    ASSERTX(IsPower2(_setIndexMask + 1));

    for (UINT32 accessType = 0; accessType < ACCESS_TYPE_NUM; accessType++)
    {
        _access[accessType][false] = 0;
        _access[accessType][true] = 0;
    }
}

/*!
 *  @brief Stats output method
 */
std::ostream & CACHE_BASE::StatsLong(std::ostream & out) const
{
    const UINT32 headerWidth = 19;
    const UINT32 numberWidth = 10;

    out << _name << ":" << std::endl;

    for (UINT32 i = 0; i < ACCESS_TYPE_NUM; i++)
    {
        const ACCESS_TYPE accessType = ACCESS_TYPE(i);

        std::string type(accessType == ACCESS_TYPE_LOAD ? "Load" : "Store");

        out << StringString(type + " Hits:      ", headerWidth)
            << StringInt(Hits(accessType), numberWidth) << std::endl;
        out << StringString(type + " Misses:    ", headerWidth)
            << StringInt(Misses(accessType), numberWidth) << std::endl;
        out << StringString(type + " Accesses:  ", headerWidth)
            << StringInt(Accesses(accessType), numberWidth) << std::endl;
        out << StringString(type + " Miss Rate: ", headerWidth)
            << StringFlt(100.0 * Misses(accessType) / Accesses(accessType), 2, numberWidth-1) << "%" << std::endl;
        CMRFile<<(100.0 * Misses(accessType) / Accesses(accessType) )<< "%" <<",";
        out << std::endl;
    }

    out << StringString("Total Hits:      ", headerWidth, ' ')
        << StringInt(Hits(), numberWidth) << std::endl;
    out << StringString("Total Misses:    ", headerWidth, ' ')
        << StringInt(Misses(), numberWidth) << std::endl;
    out << StringString("Total Accesses:  ", headerWidth, ' ')
        << StringInt(Accesses(), numberWidth) << std::endl;
    out << StringString("Total Miss Rate: ", headerWidth, ' ')
        << StringFlt(100.0 * Misses() / Accesses(), 2, numberWidth-1) << "%" << std::endl;
    CMRFile<<(100.0 * Misses() / Accesses())<< "%" <<",";

    out << StringString("Flushes:         ", headerWidth, ' ')
        << StringInt(Flushes(), numberWidth) << std::endl;
    out << StringString("Stat Resets:     ", headerWidth, ' ')
        << StringInt(Resets(), numberWidth) << std::endl;

    out << std::endl;

    return out;
}

/// ostream operator for CACHE_BASE
std::ostream & operator<< (std::ostream & out, const CACHE_BASE & cacheBase)
{
    return cacheBase.StatsLong(out);
}

/*!
 *  @brief Templated cache class with specific cache set allocation policies
 *
 *  All that remains to be done here is allocate and deallocate the right
 *  type of cache sets.
 */
template <class SET, UINT32 MAX_SETS, UINT32 STORE_ALLOCATION>
class CACHE : public CACHE_BASE
{
  private:
    SET _sets[MAX_SETS];

  public:
    // constructors/destructors
    CACHE(std::string name, UINT32 cacheSize, UINT32 lineSize, UINT32 associativity)
      : CACHE_BASE(name, cacheSize, lineSize, associativity)
    {
        ASSERTX(NumSets() <= MAX_SETS);
        //cout<<"setnum in setassociativity is "<< dec<<NumSets()<<endl;
        for (UINT32 i = 0; i < NumSets(); i++)
        {
            _sets[i].SetAssociativity(associativity);
            _sets[i].SetLinesize(lineSize);
        }
    }

    // modifiers
    /// Cache access from addr to addr+size-1
    //bool Access(ADDRINT addr, UINT32 size, ACCESS_TYPE accessType, ADDRINT (&nothit)[BLOCK_SIZE], UINT8 (&sizeincacheline)[BLOCK_SIZE]);
    /// Cache access at addr that does not span cache lines
    bool AccessSingleLine(ADDRINT addr,UINT32 size, ACCESS_TYPE accessType, CACHE_LINE &cache_line);
    bool CalculateCacheMissRatio(ADDRINT addr,ACCESS_TYPE accessType);
    bool ReadFromCache(ADDRINT addr, ADDRINT &data, UINT8 size);
    void LoadWholeCacheLine(ADDRINT addr, CACHE_LINE orig, CACHE_LINE &evict);
    void GetEvictData(ADDRINT addr, CACHE_LINE orig, CACHE_LINE &evict);
    void SetInvalid(ADDRINT addr);
    void CLFlush(ADDRINT addr);
    void Flush();
    void ResetStats();
    void CountDirtyCacheLine();
    UINT8 CountCrashDistance(ADDRINT addr);
    BOOL ReadABlockFromCache(ADDRINT addr, BLOCK &block);
};
/*!
 *  @return true if all accessed cache lines hit
 */

template <class SET, UINT32 MAX_SETS, UINT32 STORE_ALLOCATION>
BOOL CACHE<SET,MAX_SETS,STORE_ALLOCATION>:: ReadABlockFromCache(ADDRINT addr, BLOCK &block)
{
      CACHE_TAG tag;
      UINT32 setIndex;
      SplitAddress(addr, tag, setIndex);
      CACHE_LINE cacheline;
      SET & set = _sets[setIndex];
      bool hit = set.PreFind(tag);
      if(hit)
      {
        set.ReadCacheLine(cacheline);
        block = cacheline._data;
      }
      return hit;
}
/*!
 *  @return true if all accessed cache lines hit
 */

template <class SET, UINT32 MAX_SETS, UINT32 STORE_ALLOCATION>
void CACHE<SET,MAX_SETS,STORE_ALLOCATION>::SetInvalid(ADDRINT addr)
{
    CACHE_TAG tag;
    UINT32 setIndex;
    SplitAddress(addr, tag, setIndex);

    SET & set = _sets[setIndex];

    //return set.Find(tag); //Thnink about update BitMap !!!!!!
    BOOL result = set.SetInvalid(tag);
    if(!result)
    {
      cout<<hex<<addr<<endl;
    }
    ASSERTX(result);
}

template <class SET, UINT32 MAX_SETS, UINT32 STORE_ALLOCATION>
void CACHE<SET,MAX_SETS,STORE_ALLOCATION>::CLFlush(ADDRINT addr)
{
    CACHE_TAG tag;
    UINT32 setIndex;
    SplitAddress(addr, tag, setIndex);

    SET & set = _sets[setIndex];

    //return set.Find(tag); //Thnink about update BitMap !!!!!!
    set.WriteBackCacheLine(tag);
    /*if(!result)
    {
      cout<<hex<<addr<<endl;
    }
    ASSERTX(result);*/
}

/*!
 *  @return the number of crash distance if accessed cache line hits
 */
template <class SET, UINT32 MAX_SETS, UINT32 STORE_ALLOCATION>
UINT8 CACHE<SET,MAX_SETS,STORE_ALLOCATION>::CountCrashDistance(ADDRINT addr)
{
    CACHE_TAG tag;
    UINT32 setIndex;
    SplitAddress(addr, tag, setIndex);
    CACHE_LINE cacheline;
    SET & set = _sets[setIndex];
    bool hit = set.PreFind(tag);
    if(hit)
    {
      set.ReadCacheLine(cacheline);
      return cacheline._dirty;
    }
    return 0;
}


/*!
 *  @return true if all accessed cache lines hit
 */
/*
template <class SET, UINT32 MAX_SETS, UINT32 STORE_ALLOCATION>
bool CACHE<SET,MAX_SETS,STORE_ALLOCATION>::Access(ADDRINT addr, UINT32 size, ACCESS_TYPE accessType, ADDRINT (&nothit)[BLOCK_SIZE], UINT8 (&sizeincacheline)[BLOCK_SIZE])
{
    //const ADDRINT orig_addr = addr;
    const ADDRINT highAddr = addr + size;
    bool allHit = true;
    const ADDRINT lineSize = LineSize();
    const ADDRINT notLineMask = ~(lineSize - 1);
    UINT8 nothitindex = 0;

    do
    {
        CACHE_TAG tag;
        UINT32 setIndex;
        UINT32 lineIndex;

        SplitAddress(addr, tag, setIndex, lineIndex);

        SET & set = _sets[setIndex];

        bool localHit = set.Find(tag);
        allHit &= localHit;
        UINT32 distence = lineSize - lineIndex;
        UINT32 step = (distence >= size ? size : distence);

        if(localHit)
        {

            if(accessType == ACCESS_TYPE_STORE)
            {
                UINT8 v[64] = {0};

                PIN_SafeCopy(v,(void*)addr,step);
                set.Update(lineIndex,step,v);
            }
        }
        else{
            // on miss, loads always allocate, stores optionally
            //if not hit, need to load data from memory to cacheline!, load is inside set.Replace();
            if(accessType == ACCESS_TYPE_STORE && STORE_ALLOCATION == CACHE_ALLOC::STORE_ALLOCATE)
            {
                UINT8 v[64]={0};
                UINT32 distence = lineSize - lineIndex;
                UINT32 step = (distence >= size ? size : distence);

                PIN_SafeCopy(v,(void*)addr,step);
                memory.WriteMemory(addr,step,v);
                size = size - step;

            }
            set.Replace(tag);
            nothit[nothitindex] = addr;
            sizeincacheline[nothitindex] = step;
            nothitindex++;
        }
        size = size - step;
        addr = (addr & notLineMask) + lineSize; //start of next cache line
        //cout<< "Next addr is "<< addr<<endl;
    }
    while (addr < highAddr);

    _access[accessType][allHit]++;

    return allHit;
}*/

/*!
 *  @return true if accessed cache line hits
 */
template <class SET, UINT32 MAX_SETS, UINT32 STORE_ALLOCATION>
bool CACHE<SET,MAX_SETS,STORE_ALLOCATION>::CalculateCacheMissRatio(ADDRINT addr, ACCESS_TYPE accessType)
{
    CACHE_TAG tag;
    UINT32 setIndex;
    SplitAddress(addr, tag, setIndex);
    SET & set = _sets[setIndex];

    bool hit = set.PreFind(tag);
    _access[accessType][hit]++;

    return hit;
}

/*!
 *  @return true if accessed cache line hits
 */
template <class SET, UINT32 MAX_SETS, UINT32 STORE_ALLOCATION>
bool CACHE<SET,MAX_SETS,STORE_ALLOCATION>::AccessSingleLine(ADDRINT addr, UINT32 size, ACCESS_TYPE accessType, CACHE_LINE &cache_line)
{
    CACHE_TAG tag;
    UINT32 setIndex;
    UINT32 lineIndex;
    UINT8 v[BLOCK_SIZE]={0};

    PIN_SafeCopy(v,(void*)addr, size);


    SplitAddress(addr, tag, setIndex, lineIndex);

    SET & set = _sets[setIndex];

    bool hit = set.Find(tag);


    if(!hit)
    {
        if(accessType == ACCESS_TYPE_STORE && STORE_ALLOCATION == CACHE_ALLOC::STORE_ALLOCATE)
        {
            CACHE_LINE evict;
            CACHE_LINE line;
            UINT8 value[BLOCK_SIZE]={0};
            evict.if_evict = false;

            set.Replace(tag, evict);
            if(evict.if_evict && evict._dirty.ifdirty())
            {
                //evict._dirty.get();
                (evict._data).GetWholeCacheLine(value);
                memory.WriteAsBlock(evict._addr, value);
            }
            memory.WriteMemory(addr,size,v);
            memory.ReadAsBlock(addr, v);

            (line._data).SetWholeCacheLine(v);
            line._dirty = CACHE_DIRTY(0);
            set.Load(line);

        }
    }

    if(hit)
    {
      if(accessType == ACCESS_TYPE_STORE)
      {
            set.Update(lineIndex,size,v);
      }
      //if hit, update bit map happens in find function
      //else, gonna happen in replace function
      else{
        set.ReadCacheLine(cache_line);
      }

    }

    if(STORE_ALLOCATION == CACHE_ALLOC::STORE_ALLOCATE)
    {
      _access[accessType][hit]++;
    }
    return hit;
}

/*!
 *  Load whole cacheline from somewhere else, might the same level cache or next level cache
 */
template <class SET, UINT32 MAX_SETS, UINT32 STORE_ALLOCATION>
VOID CACHE<SET,MAX_SETS,STORE_ALLOCATION>::LoadWholeCacheLine(ADDRINT addr, CACHE_LINE orig, CACHE_LINE &evict)
{



    CACHE_TAG tag;
    UINT32 setIndex;
    SplitAddress(addr, tag, setIndex);

    SET & set = _sets[setIndex];
    evict.if_evict = false;

    set.Replace(tag,evict);
    set.Load(orig);
}

/*!
 *  @return if can the value we want is in cache
 */
template <class SET, UINT32 MAX_SETS, UINT32 STORE_ALLOCATION>
BOOL CACHE<SET,MAX_SETS,STORE_ALLOCATION>::ReadFromCache(ADDRINT addr, ADDRINT &data, UINT8 size)
{
    UINT8 v[8] = {0,0,0,0,0,0,0,0};
    UINT8 i = 0;
    data = -1;
    const ADDRINT highAddr = addr + size;
    bool allHit = true;
    const ADDRINT lineSize = LineSize();
    const ADDRINT notLineMask = ~(lineSize - 1);

    do
    {
        CACHE_TAG tag;
        UINT32 setIndex;
        UINT32 lineIndex;
        SplitAddress(addr, tag, setIndex, lineIndex);
        SET & set = _sets[setIndex];

        bool localHit = set.Find(tag);
        allHit &= localHit;
        if(!localHit){
          return false;
        }
        else{
            UINT32 distence = lineSize - lineIndex;
            UINT32 step = (distence >= size ? size : distence);
            for(UINT8 index = 0; index < step; index++)
            {
                v[i++] = set.Read(lineIndex+index);
            }
            size = size - step;
        }
        addr = (addr & notLineMask) + lineSize; //start of next cache line
    }while(addr < highAddr);

    ADDRINT *temp_data = reinterpret_cast<ADDRINT*>(v);
    data = *temp_data;
    return true;
}

/*!
 *  only dl2 can call this API
 *  bad shape and I don't like it, maybe cache to l2 and l3 as API rather than visiably for user
 */
template <class SET, UINT32 MAX_SETS, UINT32 STORE_ALLOCATION>
void CACHE<SET,MAX_SETS,STORE_ALLOCATION>::GetEvictData(ADDRINT addr, CACHE_LINE orig, CACHE_LINE &evict)
{
    CACHE_TAG tag;
    UINT32 setIndex;
    evict.if_evict = false;

    SplitAddress(addr, tag, setIndex);
    SET & set = _sets[setIndex];

    bool Hit = set.Find(tag);
    if(!Hit){
      set.Replace(tag,evict);
    }
    set.Load(orig);
    //_access[accessType][hit]++;
}

/*!
 *  @return true if accessed cache line hits
 */
template <class SET, UINT32 MAX_SETS, UINT32 STORE_ALLOCATION>
void CACHE<SET,MAX_SETS,STORE_ALLOCATION>::Flush()
{
    for (INT32 index = NumSets(); index >= 0; index--) {
      // << "Right now flushing "<<index<<" set"<<endl;
      SET & set = _sets[index];
      set.Flush();
    }
    IncFlushCounter();
}

template <class SET, UINT32 MAX_SETS, UINT32 STORE_ALLOCATION>
void CACHE<SET,MAX_SETS,STORE_ALLOCATION>::ResetStats()
{
    for (UINT32 accessType = 0; accessType < ACCESS_TYPE_NUM; accessType++)
    {
	     _access[accessType][false] = 0;
	     _access[accessType][true] = 0;
    }
    IncResetCounter();
}

template <class SET, UINT32 MAX_SETS, UINT32 STORE_ALLOCATION>
void CACHE<SET,MAX_SETS,STORE_ALLOCATION>::CountDirtyCacheLine()
{
  for (INT32 index = NumSets(); index >= 0; index--) {
    // << "Right now flushing "<<index<<" set"<<endl;
    SET & set = _sets[index];
    set.CountDirty();
  }
}

// define shortcuts
#define CACHE_DIRECT_MAPPED(MAX_SETS, ALLOCATION) CACHE<CACHE_SET::DIRECT_MAPPED, MAX_SETS, ALLOCATION>
#define CACHE_ROUND_ROBIN(MAX_SETS, MAX_ASSOCIATIVITY, ALLOCATION) CACHE<CACHE_SET::ROUND_ROBIN<MAX_ASSOCIATIVITY>, MAX_SETS, ALLOCATION>
#define CACHE_LRU(MAX_SETS,MAX_ASSOCIATIVITY,ALLOCATION) CACHE<CACHE_SET::LRU<MAX_ASSOCIATIVITY>,MAX_SETS,ALLOCATION>
#define CACHE_BIPLRU(MAX_SETS,MAX_ASSOCIATIVITY,ALLOCATION) CACHE<CACHE_SET::BIPLRU<MAX_ASSOCIATIVITY>,MAX_SETS,ALLOCATION>

#endif // PIN_CACHE_H
