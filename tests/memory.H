/*!
 *  For memory simulation
 *  store value as cache block/line 64 byte
 *  provide interface
 */

#ifndef MEMORY_H
#define MEMORY_H

#include <unordered_map>
#include <string>
#include <boost/array.hpp>
#include "globals.H"

using namespace std;


/*
 * Memory store as block, each block contains 64 bytes data
 * Memory provide read, read as a block(for reload cahce)
 * write as a block (for flush the whole cache line)
 * still need write several byte(for write allocate)
 * Memory's type is unorder map, block's beginning address as key
 * Block's type is array, the index of array used to calculate address
 */

 class MEMORY
 {
   private:
       MEM main_memory;             //main memory
       ADDRINT _capacity;           // main memory capacity
       ADDRINT _lineShift;          // for get block start address
       ADDRINT _mask;               // for get block start address

       ADDRINT GetBlockAddress(ADDRINT addr)
       {
           return addr & _mask;
       }


  public:
      MEMORY(int capacity) : _capacity(capacity),
                          _lineShift(FloorLog2(BLOCK_SIZE)),
                          _mask(UINT64_MAX<<_lineShift)
                          {}

      BOOL ReadMemory(ADDRINT addr, UINT8 size, ADDRINT &value);
      BOOL ReadAsBlock(ADDRINT addr, UINT8 (&value)[BLOCK_SIZE]);
      BOOL ReadAsBlock(ADDRINT addr, BLOCK &block);
      VOID WriteMemory(ADDRINT addr, UINT8 size, UINT8 value[BLOCK_SIZE]);
      VOID WriteAsBlock(ADDRINT addr, UINT8 value[BLOCK_SIZE]);
      UINT64 GetMemorySize();

};

/*
 *  Read main memory for a const size, size as input and no more than 8 bytes(smaller than or equal to DOUBLE/ADDRINT)
 *  Return whether the address is already in memory
 */
BOOL MEMORY::ReadMemory(ADDRINT addr, UINT8 size, ADDRINT &value)
{
    ASSERTX(size <= 8);
    UINT8 v[8] = {0,0,0,0,0,0,0,0};
    UINT8 i = 0;

    do{
        ADDRINT begin_addr = GetBlockAddress(addr);

        MEM::iterator it = main_memory.find(begin_addr);
        if (it != main_memory.end()) {
            UINT8 begin = addr - begin_addr;
            UINT8 dist = BLOCK_SIZE - begin;
            UINT8 step = dist>=size ? size : dist;

            ASSERTX(step + begin <= BLOCK_SIZE);
            for(UINT8 index = 0; index<step; index++)
            {
                v[i++] = it->second[index+begin];
            }
            size = size - step;
            addr = addr + step;
        }
        else{
            return false;
        }
    }while(size>0);

    ADDRINT *temp_data = reinterpret_cast<ADDRINT*>(v);
    value = *temp_data;
    return true;
}

/*
 * Read main memory as a block, using array for a reference
 * The input address stands as any address in this block, which means we do convert to the beginning address in memory
 * return if found the block with the specific address
 */
BOOL MEMORY::ReadAsBlock(ADDRINT addr, UINT8 (&value)[BLOCK_SIZE])
{
    ADDRINT begin_addr = GetBlockAddress(addr);
    MEM::iterator it = main_memory.find(begin_addr);
    if (it != main_memory.end()) {
        std::copy(it->second.begin(), it->second.end(), value);
        return true;
    }
    else{
        BLOCK block;
        std::fill_n(block.begin(), BLOCK_SIZE, 0);  //initialize the block!
        main_memory.insert(std::make_pair(begin_addr, block));
        return false;
    }
}

/*
 * Read main memory as a block, using array for a reference
 * The input address stands as any address in this block, which means we do convert to the beginning address in memory
 * return if found the block with the specific address
 */
BOOL MEMORY::ReadAsBlock(ADDRINT addr, BLOCK &block)
{
  MEM::iterator it = main_memory.find(addr);
  if (it != main_memory.end()) {
      block = it->second;
      return true;
  }
  else{
      return false;
  }
}

/*
 *  write main memory for a const size, size as input and no more than 8 bytes(smaller than or equal to DOUBLE/ADDRINT)
 *
 */
VOID MEMORY::WriteMemory(ADDRINT addr, UINT8 size, UINT8 value[BLOCK_SIZE])
{
       ADDRINT begin_addr = GetBlockAddress(addr);
       UINT8 begin = addr - begin_addr;
       MEM::iterator it = main_memory.find(begin_addr);

       //if(begin + size > BLOCK_SIZE)
       //{
        //  cout<<"addr is "<<hex<<addr<<". begin_addr is"<<hex<<begin_addr<<". size is "<<dec<<+size<<endl;
       //}

       if (it != main_memory.end()) {
           ASSERTX(begin + size <= BLOCK_SIZE);
           for(UINT8 index = 0; index<size; index++)
           {
               it->second[begin+index] = value[index];
           }
       }
       else{
           BLOCK block;  //create a new block
           std::fill_n(block.begin(), BLOCK_SIZE, 0);  //initialize the block!
           ASSERTX(begin + size <= BLOCK_SIZE);
           for(UINT8 index = 0; index<size; index++)
           {
               block[begin+index] = value[index];
           }
           main_memory.insert(std::make_pair(begin_addr, block));
       }
}

/*
 *  write main memory as a block
 *
 */
VOID MEMORY::WriteAsBlock(ADDRINT addr, UINT8 value[BLOCK_SIZE])
{
    ADDRINT begin_addr = GetBlockAddress(addr);

    MEM::iterator it = main_memory.find(begin_addr);
    if (it != main_memory.end()) {
        std::copy(value, value + BLOCK_SIZE, it->second.begin());
    }
    else{
        BLOCK block;
        std::fill_n(block.begin(), BLOCK_SIZE, 0);  //initialize the block!
        std::copy(value,value + BLOCK_SIZE, block.begin());
        main_memory.insert(std::make_pair(begin_addr, block));
    }
}

/*
 *  get main memory footprint as MB
 */
UINT64 MEMORY::GetMemorySize()
{
    return main_memory.size();
}



/*
VOID WriteMemory(ADDRINT addr, UINT8 size, UINT8 value[BLOCK_SIZE])
 {
    UINT8 i = 0;
    do{
         ADDRINT begin_addr = GetBlockAddress(addr);
         UINT8 begin = addr - begin_addr;
         UINT8 dist = BLOCK_SIZE - begin;
         UINT8 step = (dist>=size ? size : dist);
         HIPII::iterator it = main_memory.find(begin_addr);

         if (it != main_memory.end()) {
             ASSERTX(begin + step <= BLOCK_SIZE);
             for(UINT8 index = 0; index<step; index++)
             {
                 it->second[begin+index] = value[i++];
             }
         }
         else{
             BLOCK block;
             std::fill_n(block.begin(), BLOCK_SIZE, 0);  //initialize the block!
             for(UINT8 index = 0; index<step; index++)
             {
                 block[begin+index] = value[i++];
             }
             main_memory.insert(std::make_pair(begin_addr, block));
         }
         size = size - step;
         addr = addr + step;
     }while(size>0);
 }
*/

#endif // MEMORY_H

