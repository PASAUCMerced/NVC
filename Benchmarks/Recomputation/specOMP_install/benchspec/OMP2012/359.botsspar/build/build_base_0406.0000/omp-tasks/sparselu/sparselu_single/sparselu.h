#ifndef SPARSELU_H
#define SPARSELU_H

#define EPSILON 1.0E-6

void *tmp;
int tmp_pos = 0;
int flag1 = 0, flag2 = 0, flag3 = 0, flag4 = 0, flag5 = 0;

int checkmat (double *M, double *N);
void genmat (double *M[]);
void print_structure(char *name, double *M[]);
double * allocate_clean_block();
void lu0(double *diag);
void bdiv(double *diag, double *row);
void bmod(double *row, double *col, double *inner);
void fwd(double *diag, double *col);

#endif
