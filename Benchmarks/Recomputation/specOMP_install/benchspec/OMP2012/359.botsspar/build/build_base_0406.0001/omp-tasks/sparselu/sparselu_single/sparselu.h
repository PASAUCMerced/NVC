#ifndef SPARSELU_H
#define SPARSELU_H

#define EPSILON 1.0E-6
void *tmp;
int tmp_pos = 0;
int flag1 = 0, flag2 = 0, flag3 = 0, flag4 = 0, flag5 = 0, flag6 = 0, flag7 = 0,flag8 = 0,flag9=0;
int recompute = 0;
int checkmat (float *M, float *N);
void genmat (float *M[]);
void print_structure(char *name, float *M[]);
float * allocate_clean_block();
void lu0(float *diag);
void bdiv(float *diag, float *row);
void bmod(float *row, float *col, float *inner);
void fwd(float *diag, float *col);

#endif
