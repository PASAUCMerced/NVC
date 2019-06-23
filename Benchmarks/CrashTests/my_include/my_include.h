#ifndef  MY_INCLUDE_H
#define MY_INCLUDE_H

extern void flush_whole_cache();
extern void clflush(void* addr);
extern void clwb(void* addr);
extern void start_crash();
extern void end_crash();
extern void crucial_data(void* addr, char type[], int size);
extern void readonly_data(void* addr, char type[], int size);
extern void consistent_data(void* addr, char type[], int size);

#endif
