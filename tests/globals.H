#ifndef GLOBALS_H
#define GLOBALS_H

#include <string>
#include <unordered_map>
#include <boost/array.hpp>
#include <bitset>
#include <algorithm>
#include <fstream>

using namespace std;

const UINT8 BLOCK_SIZE = 64;


typedef boost::array<UINT8, BLOCK_SIZE> BLOCK;   //cache line organized as 64 byte, each byte store as a UINT8
typedef std::unordered_map<ADDRINT, BLOCK> MEM;  //main memory data structure,  store as block, 64 bytes and the key for hash is the first address of the cache line(block)


std::ofstream CMRFile;    //collect crash time info for analysis crash reason
                          //call by PIN_CACHE.h and dcache.cpp

MEM dirty_count;

/*!
 *  @brief Checks if n is a power of 2.
 *  @returns true if n is power of 2
 */
static inline bool IsPower2(UINT32 n)
{
    return ((n & (n - 1)) == 0);
}

/*!
 *  @brief Computes floor(log2(n))
 *  Works by finding position of MSB set.
 *  @returns -1 if n == 0.
 */
static inline INT32 FloorLog2(UINT32 n)
{
    INT32 p = 0;

    if (n == 0) return -1;

    if (n & 0xffff0000) { p += 16; n >>= 16; }
    if (n & 0x0000ff00)	{ p +=  8; n >>=  8; }
    if (n & 0x000000f0) { p +=  4; n >>=  4; }
    if (n & 0x0000000c) { p +=  2; n >>=  2; }
    if (n & 0x00000002) { p +=  1; }

    return p;
}

/*!
 *  @brief Computes floor(log2(n))
 *  Works by finding position of MSB set.
 *  @returns -1 if n == 0.
 */
static inline INT32 CeilLog2(UINT32 n)
{
    return FloorLog2(n - 1) + 1;
}

/*
 * compare block value difference in byte. return the number of different byte (0~64)
 * for inconsistent rate calculation
 */
UINT64 CompareDiff(BLOCK a, BLOCK b)
{
    UINT64 diff = 0;
    for(UINT8 i = 0; i<BLOCK_SIZE; i++)
    {
      if(a[i]!=b[i])
        diff++;
    }
    return diff;
}

#endif // GLOBALS_H

