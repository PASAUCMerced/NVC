#include <stdio.h>
#include "my_include.h"

int main()
{
	char a[8] = {'a','b','c','1','1','1','0','0'};
        checkpoint(a, sizeof(a));
        printf("a = %lu\n", &a);
 	return 0;
}

