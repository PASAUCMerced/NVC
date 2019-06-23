#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "my_include.h"

#define DOUBLE "double"
#define INT "int"
#define FLOAT "float"

void consistent_data(void* addr, char type[], int size)
{
    //printf("The address is %x, the type is %s, the size is %d\n", addr, type, size);
}

void crucial_data(void* addr, char type[], int size)
{
    printf("The address is %x, the type is %s, the size is %d\n", addr, type, size);
}

void readonly_data(void* addr, char type[], int size)
{
    //printf("The address is %x, the type is %s, the size is %d\n", addr, type, size);
}

void flush_whole_cache()
{
	printf("Flush the whole cache\n");
}

void start_crash()
{
	printf("crash could happen!\n");
}

void end_crash()
{
	printf("crash wouldn't happen anymore!\n");
}

void clflush(void* addr)
{

}

void clwb(void* addr)
{

}
