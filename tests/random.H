#ifndef RANDOM_H
#define RANDOM_H
//#include "pin_cache.H"
/*!
 *  @brief C++11 features
 *  creat random number
 *  @returns UINT64 random number
 *  for crash trigger
 */
#include <random>
using namespace std;

UINT64 Random(UINT64 max)
{
    std::mt19937 rng;
    rng.seed(std::random_device{}());
    // distribution in range [1, max]
    std::uniform_int_distribution<std::mt19937::result_type> dist(1,max);

    return dist(rng);
}

#endif // RANDOM_H

