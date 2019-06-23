#ifndef  MY_INCLUDE_H
#define MY_INCLUDE_H

extern void flush_dcache_range(unsigned long start, unsigned long end);
extern void flush_whole_cache();
extern void clflush(void* addr);
extern void clwb(void* addr);
extern void clflushopt(void* addr);
extern void mfence();
extern void start_crash();
extern void end_crash();
extern void crucial_data(void* addr, char type[], int size);
extern void readonly_data(void* addr, char type[], int size);
extern void consistent_data(void* addr, char type[], int size);
extern void checkpoint(void* addr, int size);                     //checkpoint: make data copy and flush them into stable storage
extern void EC(void* addr, int size);                             //EasyCrash: flush critical data objects

#endif
