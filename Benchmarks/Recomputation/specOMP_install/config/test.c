#include <stdio.h>

int main()
{
   void *a;
   a = malloc(5*sizeof(float)); 
   float *aa = (float*)a;
   int i;
   for(i=0; i<5;i++)
   {
	*(aa+i) = 12345;
}
  for(i=0; i<5;i++)
   {
        printf("%f\n",*(aa+i));
}
  float *b = malloc(5*sizeof(float));  
  for(i=0; i<5;i++)
   {
        *(b+i) = 11111;
}
   memcpy(a,b,5*sizeof(float));
for(i=0; i<5;i++)
   {
        printf("%f\n",*(aa+i));
}
return 0;
}
