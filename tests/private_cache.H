#ifndef PRIVATE_CACHE_H
#define PRIVATE_CACHE_H
#include "pin_cache.H"



/****add new states, based on the protocol****/
enum{
	 INVALID = 0,
   //VALID,
   //DIRTY,
   SHARED,
	 MODIFIED,
   EXCLUSIVE,
   //SHARED_CLEAN,
   //SHARED_MODIFIED,
   //EMPTY
};


#endif // PRIVATE_CACHE_H

