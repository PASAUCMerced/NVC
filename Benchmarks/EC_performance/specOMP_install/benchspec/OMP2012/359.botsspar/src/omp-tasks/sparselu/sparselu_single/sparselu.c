/**********************************************************************************************/
/*  This program is part of the Barcelona OpenMP Tasks Suite                                  */
/*  Copyright (C) 2009 Barcelona Supercomputing Center - Centro Nacional de Supercomputacion  */
/*  Copyright (C) 2009 Universitat Politecnica de Catalunya                                   */
/*                                                                                            */
/*  This program is free software; you can redistribute it and/or modify                      */
/*  it under the terms of the GNU General Public License as published by                      */
/*  the Free Software Foundation; either version 2 of the License, or                         */
/*  (at your option) any later version.                                                       */
/*                                                                                            */
/*  This program is distributed in the hope that it will be useful,                           */
/*  but WITHOUT ANY WARRANTY; without even the implied warranty of                            */
/*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                             */
/*  GNU General Public License for more details.                                              */
/*                                                                                            */
/*  You should have received a copy of the GNU General Public License                         */
/*  along with this program; if not, write to the Free Software                               */
/*  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA            */
/**********************************************************************************************/

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <libgen.h>
#include "bots.h"
#include "sparselu.h"
#include "my_include.h"
/***********************************************************************
 * checkmat:
 **********************************************************************/


//double tmp[bots_arg_size][bots_arg_size][bots_arg_size_1*bots_arg_size_1];

int checkmat (double *M, double *N)
{
	//printf("11111\n");
   int i, j;
   double r_err;

   for (i = 0; i < bots_arg_size_1; i++)
   {
      for (j = 0; j < bots_arg_size_1; j++)
      {
         r_err = M[i*bots_arg_size_1+j] - N[i*bots_arg_size_1+j];
         if (r_err < 0.0 ) r_err = -r_err;
         r_err = r_err / M[i*bots_arg_size_1+j];
         if(r_err > EPSILON)
         {
           printf("Checking failure: A[%d][%d]=%20.12E  B[%d][%d]=%20.12E; Relative Error=%20.12E\n",
                   i,j, M[i*bots_arg_size_1+j], i,j, N[i*bots_arg_size_1+j], r_err);
            bots_message("Checking failure: A[%d][%d]=%lf  B[%d][%d]=%lf; Relative Error=%lf\n",
                    i,j, M[i*bots_arg_size_1+j], i,j, N[i*bots_arg_size_1+j], r_err);
            return FALSE;
         }
      }
   }
   return TRUE;
}
/***********************************************************************
 * genmat:
 **********************************************************************/
void genmat (double *M[])
{
   int null_entry, init_val, i, j, ii, jj;
   double *p;
   double *prow;
   double rowsum;

   init_val = 1325;

   /* generating the structure */
   for (ii=0; ii < bots_arg_size; ii++)
   {
      for (jj=0; jj < bots_arg_size; jj++)
      {
         /* computing null entries */
         null_entry=FALSE;
         if ((ii<jj) && (ii%3 !=0)) null_entry = TRUE;
         if ((ii>jj) && (jj%3 !=0)) null_entry = TRUE;
	 if (ii%2==1) null_entry = TRUE;
	 if (jj%2==1) null_entry = TRUE;
	 if (ii==jj) null_entry = FALSE;
	 if (ii==jj-1) null_entry = FALSE;
         if (ii-1 == jj) null_entry = FALSE;
         /* allocating matrix */
         if (null_entry == FALSE){
           // M[ii*bots_arg_size+jj] = (double *) malloc(bots_arg_size_1*bots_arg_size_1*sizeof(double));
	   M[ii*bots_arg_size+jj] = (double*)((void*)tmp + tmp_pos);
	   tmp_pos += bots_arg_size_1*bots_arg_size_1*sizeof(double);

 	    if ((M[ii*bots_arg_size+jj] == NULL))
            {
               bots_message("Error: Out of memory\n");
               exit(101);
            }
            /* initializing matrix */
            /* Modify diagonal element of each row in order */
            /* to ensure matrix is diagonally dominant and  */
            /* well conditioned. */
            prow = p = M[ii*bots_arg_size+jj];
            for (i = 0; i < bots_arg_size_1; i++)
            {
               rowsum = 0.0;
               for (j = 0; j < bots_arg_size_1; j++)
               {
	                  init_val = (3125 * init_val) % 65536;
      	            (*p) = (double)((init_val - 32768.0) / 16384.0);
                    rowsum += abs(*p);
                    p++;
               }
               if (ii == jj)
                 *(prow+i) = rowsum * (double) bots_arg_size + abs(*(prow+i));
               prow += bots_arg_size_1;
            }
         }
         else
         {
            M[ii*bots_arg_size+jj] = NULL;
         }
      }
   }
}
/***********************************************************************
 * print_structure:
 **********************************************************************/
void print_structure(char *name, double *M[])
{
   int ii, jj;
   bots_message("Structure for matrix %s @ 0x%p\n",name, M);
   for (ii = 0; ii < bots_arg_size; ii++) {
     for (jj = 0; jj < bots_arg_size; jj++) {
        if (M[ii*bots_arg_size+jj]!=NULL) {bots_message("x");}
        else bots_message(" ");
     }
     bots_message("\n");
   }
   bots_message("\n");
}
/***********************************************************************
 * allocate_clean_block:
 **********************************************************************/
double * allocate_clean_block()
{
  int i,j;
  double *p, *q;
//printf("1\n");
 // p = (double *) malloc(bots_arg_size_1*bots_arg_size_1*sizeof(double));
  p = (double*)((void*)tmp + tmp_pos);
  tmp_pos += bots_arg_size_1*bots_arg_size_1*sizeof(double);
  q=p;
  if (p!=NULL){
     for (i = 0; i < bots_arg_size_1; i++)
        for (j = 0; j < bots_arg_size_1; j++){(*p)=0.0; p++;}

  }
  else
  {
      bots_message("Error: Out of memory\n");
      exit (101);
  }
  return (q);
}

/***********************************************************************
 * lu0:
 **********************************************************************/
void lu0(double *diag)
{
   int i, j, k;

   for (k=0; k<bots_arg_size_1; k++) {
      for (i=k+1; i<bots_arg_size_1; i++)
      {
         diag[i*bots_arg_size_1+k] = diag[i*bots_arg_size_1+k] / diag[k*bots_arg_size_1+k];
         for (j=k+1; j<bots_arg_size_1; j++)
            diag[i*bots_arg_size_1+j] = diag[i*bots_arg_size_1+j] - diag[i*bots_arg_size_1+k] * diag[k*bots_arg_size_1+j];
      }
	//kai
	flag1 = k;
    }
}

/***********************************************************************
 * bdiv:
 **********************************************************************/
void bdiv(double *diag, double *row)
{
   int i, j, k;
   for (i=0; i<bots_arg_size_1; i++) {
      for (k=0; k<bots_arg_size_1; k++)
      {
         row[i*bots_arg_size_1+k] = row[i*bots_arg_size_1+k] / diag[k*bots_arg_size_1+k];
         for (j=k+1; j<bots_arg_size_1; j++)
            row[i*bots_arg_size_1+j] = row[i*bots_arg_size_1+j] - row[i*bots_arg_size_1+k]*diag[k*bots_arg_size_1+j];
      }

    }
}
/***********************************************************************
 * bmod:
 **********************************************************************/
void bmod(double *row, double *col, double *inner)
{
   int i, j, k;
   for (i=0; i<bots_arg_size_1; i++){
      for (j=0; j<bots_arg_size_1; j++){
         for (k=0; k<bots_arg_size_1; k++){
            inner[i*bots_arg_size_1+j] = inner[i*bots_arg_size_1+j] - row[i*bots_arg_size_1+k]*col[k*bots_arg_size_1+j];
            flag9 = k;
          }
             flag8 = j;
          }
      flag7 = i;
   }
}
/***********************************************************************
 * bmod:
 **********************************************************************/
void vbmod(double *row, double *col, double *inner)
{
   int i, j, k;
   for (i=0; i<bots_arg_size_1; i++)
      for (j=0; j<bots_arg_size_1; j++)
         for (k=0; k<bots_arg_size_1; k++)
            inner[i*bots_arg_size_1+j] = inner[i*bots_arg_size_1+j] - row[i*bots_arg_size_1+k]*col[k*bots_arg_size_1+j];
}
/***********************************************************************
 * fwd:
 **********************************************************************/
void fwd(double *diag, double *col)
{
   int i, j, k;
   for (j=0; j<bots_arg_size_1; j++)
      for (k=0; k<bots_arg_size_1; k++)
         for (i=k+1; i<bots_arg_size_1; i++)
            col[i*bots_arg_size_1+j] = col[i*bots_arg_size_1+j] - diag[i*bots_arg_size_1+k]*col[k*bots_arg_size_1+j];
}


void sparselu_init (double ***pBENCH, char *pass)
{
	tmp_pos  = 0;
   *pBENCH = (double **) malloc(bots_arg_size*bots_arg_size*sizeof(double *));
  // printf("%s\n", pass):
   tmp = malloc((bots_arg_size*bots_arg_size)*bots_arg_size_1*bots_arg_size_1*sizeof(double));
  //*pBENCH = (double **)tmp + tmp_pos;
   //tmp_pos += bots_arg_size*bots_arg_size*sizeof(double *);

   genmat(*pBENCH);

	crucial_data(tmp, "double", (bots_arg_size*bots_arg_size*bots_arg_size_1*bots_arg_size_1));

//kai
   consistent_data(&flag1, "int", 1);
   consistent_data(&flag2, "int", 1);
   consistent_data(&flag3, "int", 1);
   consistent_data(&flag4, "int", 1);
   consistent_data(&flag5, "int", 1);
   consistent_data(&flag6, "int", 1);
   consistent_data(&flag7, "int", 1);
   consistent_data(&flag8, "int", 1);
   consistent_data(&flag9, "int", 1);

   /* spec  print_structure(pass, *pBENCH);  */
}

void sparselu_par_call(double **BENCH)
{

  //printf("1111\n");
   int ii, jj, kk;

   bots_message("Computing SparseLU Factorization (%dx%d matrix with %dx%d blocks) ",
           bots_arg_size,bots_arg_size,bots_arg_size_1,bots_arg_size_1);
//kai
	flush_whole_cache();
   start_crash();
#pragma omp parallel
#pragma omp single nowait
   for (kk=0; kk<bots_arg_size; kk++)
   {
      lu0(BENCH[kk*bots_arg_size+kk]);
      for (jj=kk+1; jj<bots_arg_size; jj++) {
         if (BENCH[kk*bots_arg_size+jj] != NULL)
            #pragma omp task untied firstprivate(kk, jj) shared(BENCH)
         {
            fwd(BENCH[kk*bots_arg_size+kk], BENCH[kk*bots_arg_size+jj]);
         }
	        //kai
	         flag2 = jj;
      }

      for (ii=kk+1; ii<bots_arg_size; ii++) {
         if (BENCH[ii*bots_arg_size+kk] != NULL)
            #pragma omp task untied firstprivate(kk, ii) shared(BENCH)
         {
            bdiv (BENCH[kk*bots_arg_size+kk], BENCH[ii*bots_arg_size+kk]);
         }
        	//kai
        	flag3 = ii;
      }

      #pragma omp taskwait
      for (ii=kk+1; ii<bots_arg_size; ii++) {
         if (BENCH[ii*bots_arg_size+kk] != NULL)
            for (jj=kk+1; jj<bots_arg_size; jj++)
               if (BENCH[kk*bots_arg_size+jj] != NULL)
               #pragma omp task untied firstprivate(kk, jj, ii) shared(BENCH)
               {
                     if (BENCH[ii*bots_arg_size+jj]==NULL) BENCH[ii*bots_arg_size+jj] = allocate_clean_block();
                     bmod(BENCH[ii*bots_arg_size+kk], BENCH[kk*bots_arg_size+jj], BENCH[ii*bots_arg_size+jj]);
                     flag6 = jj;
               }
              	//kai
              	flag4 = ii;
          /*  if(kk==0 && ii==47)
            {
              FILE *file = fopen("checkpoint","w");
              int ijk = 0;
              double *temp_tmp = (double *)tmp;
              for(ijk= 0; ijk<bots_arg_size*bots_arg_size*bots_arg_size_1*bots_arg_size_1;ijk++)
              {
                fprintf(file, "%21.12E\n",*(temp_tmp+ijk));
              }
              fclose(file);
            }*/
      }
      #pragma omp taskwait
	flag5 = kk;
   }
//kai
   end_crash();
   bots_message(" completed!\n");
}


void sparselu_seq_call(double **BENCH)
{
   int ii, jj, kk;

   for (kk=0; kk<bots_arg_size; kk++)
   {
      lu0(BENCH[kk*bots_arg_size+kk]);
      for (jj=kk+1; jj<bots_arg_size; jj++)
         if (BENCH[kk*bots_arg_size+jj] != NULL)
         {
            fwd(BENCH[kk*bots_arg_size+kk], BENCH[kk*bots_arg_size+jj]);
         }
      for (ii=kk+1; ii<bots_arg_size; ii++)
         if (BENCH[ii*bots_arg_size+kk] != NULL)
         {
            bdiv (BENCH[kk*bots_arg_size+kk], BENCH[ii*bots_arg_size+kk]);
         }
      for (ii=kk+1; ii<bots_arg_size; ii++)
         if (BENCH[ii*bots_arg_size+kk] != NULL)
            for (jj=kk+1; jj<bots_arg_size; jj++)
               if (BENCH[kk*bots_arg_size+jj] != NULL)
               {
                     if (BENCH[ii*bots_arg_size+jj]==NULL) BENCH[ii*bots_arg_size+jj] = allocate_clean_block();
                     bmod(BENCH[ii*bots_arg_size+kk], BENCH[kk*bots_arg_size+jj], BENCH[ii*bots_arg_size+jj]);
               }

   }
}

void sparselu_fini (double **BENCH, char *pass)
{
   /* spec  print_structure(pass, BENCH); */
   return;
}

/*
 * changes for SPEC, original source
 *
int sparselu_check(double **SEQ, double **BENCH)
{
   int ii,jj,ok=1;

   for (ii=0; ((ii<bots_arg_size) && ok); ii++)
   {
      for (jj=0; ((jj<bots_arg_size) && ok); jj++)
      {
         if ((SEQ[ii*bots_arg_size+jj] == NULL) && (BENCH[ii*bots_arg_size+jj] != NULL)) ok = FALSE;
         if ((SEQ[ii*bots_arg_size+jj] != NULL) && (BENCH[ii*bots_arg_size+jj] == NULL)) ok = FALSE;
         if ((SEQ[ii*bots_arg_size+jj] != NULL) && (BENCH[ii*bots_arg_size+jj] != NULL))
            ok = checkmat(SEQ[ii*bots_arg_size+jj], BENCH[ii*bots_arg_size+jj]);
      }
   }
   if (ok) return BOTS_RESULT_SUCCESSFUL;
   else return BOTS_RESULT_UNSUCCESSFUL;
}
*/

/*
 * SPEC modified check, print out values
 *
 */

/*int sparselu_check(double **SEQ, double **BENCH)
{
   int i, j, ok;

   bots_message("Output size: %d\n",bots_arg_size);
   for (i = 0; i < bots_arg_size; i+=50)
   {
      for (j = 0; j < bots_arg_size; j+=40)
      {
            ok = checkmat1(BENCH[i*bots_arg_size+j]);
      }
   }
   return BOTS_RESULT_SUCCESSFUL;
}
int checkmat1 (double *N)
{
   int i, j;

   for (i = 0; i < bots_arg_size_1; i+=20)
   {
      for (j = 0; j < bots_arg_size_1; j+=20)
      {
         bots_message("Output Matrix: A[%d][%d]=%8.12f \n",
                    i,j, N[i*bots_arg_size_1+j]);
      }
   }

	//printf("111111111\n");
   return TRUE;
}*/void vgenmat (double *M[])
{
   int null_entry, init_val, i, j, ii, jj;
   double *p;
   double *prow;
   double rowsum;

   init_val = 1325;

   /* generating the structure */
   for (ii=0; ii < bots_arg_size; ii++)
   {
      for (jj=0; jj < bots_arg_size; jj++)
      {
         /* computing null entries */
         null_entry=FALSE;
         if ((ii<jj) && (ii%3 !=0)) null_entry = TRUE;
         if ((ii>jj) && (jj%3 !=0)) null_entry = TRUE;
  if (ii%2==1) null_entry = TRUE;
  if (jj%2==1) null_entry = TRUE;
  if (ii==jj) null_entry = FALSE;
  if (ii==jj-1) null_entry = FALSE;
         if (ii-1 == jj) null_entry = FALSE;
         /* allocating matrix */
         if (null_entry == FALSE){
          M[ii*bots_arg_size+jj] = (double *) malloc(bots_arg_size_1*bots_arg_size_1*sizeof(double));
   // M[ii*bots_arg_size+jj] = (double*)((void*)tmp + tmp_pos);
  //  tmp_pos += bots_arg_size_1*bots_arg_size_1*sizeof(double);

       if ((M[ii*bots_arg_size+jj] == NULL))
            {
               bots_message("Error: Out of memory\n");
               exit(101);
            }
            /* initializing matrix */
            /* Modify diagonal element of each row in order */
            /* to ensure matrix is diagonally dominant and  */
            /* well conditioned. */
            prow = p = M[ii*bots_arg_size+jj];
            for (i = 0; i < bots_arg_size_1; i++)
            {
               rowsum = 0.0;
               for (j = 0; j < bots_arg_size_1; j++)
               {
             init_val = (3125 * init_val) % 65536;
                   (*p) = (double)((init_val - 32768.0) / 16384.0);
                    rowsum += abs(*p);
                    p++;
               }
               if (ii == jj)
                 *(prow+i) = rowsum * (double) bots_arg_size + abs(*(prow+i));
               prow += bots_arg_size_1;
            }
         }
         else
         {
            M[ii*bots_arg_size+jj] = NULL;
         }
      }
   }
}
void vlu0(double *diag)
{
  int i, j, k;

  for (k=0; k<bots_arg_size_1; k++)
     for (i=k+1; i<bots_arg_size_1; i++)
     {
        diag[i*bots_arg_size_1+k] = diag[i*bots_arg_size_1+k] / diag[k*bots_arg_size_1+k];
        for (j=k+1; j<bots_arg_size_1; j++)
           diag[i*bots_arg_size_1+j] = diag[i*bots_arg_size_1+j] - diag[i*bots_arg_size_1+k] * diag[k*bots_arg_size_1+j];
     }
}
void vsparselu_init (double ***pBENCH, char *pass)
{
  *pBENCH = (double **) malloc(bots_arg_size*bots_arg_size*sizeof(double *));
  vgenmat(*pBENCH);
  /* spec  print_structure(pass, *pBENCH);  */
}

void vsparselu_par_call(double **BENCH)
{
  int ii, jj, kk;

  bots_message("Computing SparseLU Factorization (%dx%d matrix with %dx%d blocks) ",
          bots_arg_size,bots_arg_size,bots_arg_size_1,bots_arg_size_1);
#pragma omp parallel
#pragma omp single nowait
  for (kk=0; kk<bots_arg_size; kk++)
  {
     vlu0(BENCH[kk*bots_arg_size+kk]);
     for (jj=kk+1; jj<bots_arg_size; jj++)
        if (BENCH[kk*bots_arg_size+jj] != NULL)
           #pragma omp task untied firstprivate(kk, jj) shared(BENCH)
        {
           fwd(BENCH[kk*bots_arg_size+kk], BENCH[kk*bots_arg_size+jj]);
        }
     for (ii=kk+1; ii<bots_arg_size; ii++)
        if (BENCH[ii*bots_arg_size+kk] != NULL)
           #pragma omp task untied firstprivate(kk, ii) shared(BENCH)
        {
           bdiv (BENCH[kk*bots_arg_size+kk], BENCH[ii*bots_arg_size+kk]);
        }

     #pragma omp taskwait

     for (ii=kk+1; ii<bots_arg_size; ii++)
        if (BENCH[ii*bots_arg_size+kk] != NULL)
           for (jj=kk+1; jj<bots_arg_size; jj++)
              if (BENCH[kk*bots_arg_size+jj] != NULL)
              #pragma omp task untied firstprivate(kk, jj, ii) shared(BENCH)
              {
                    if (BENCH[ii*bots_arg_size+jj]==NULL) BENCH[ii*bots_arg_size+jj] = allocate_clean_block();
                    vbmod(BENCH[ii*bots_arg_size+kk], BENCH[kk*bots_arg_size+jj], BENCH[ii*bots_arg_size+jj]);
              }

     #pragma omp taskwait
  }
  bots_message("pre verify completed!\n");
}

int sparselu_check(double **SEQ, double **BENCH)
{

 vsparselu_init(&SEQ, NULL);
 vsparselu_par_call(SEQ);

int ii,jj,ok=1;

  for (ii=0; ((ii<bots_arg_size) && ok); ii++)
  {
     for (jj=0; ((jj<bots_arg_size) && ok); jj++)
     {
        if ((SEQ[ii*bots_arg_size+jj] == NULL) && (BENCH[ii*bots_arg_size+jj] != NULL)) ok = FALSE;
        if ((SEQ[ii*bots_arg_size+jj] != NULL) && (BENCH[ii*bots_arg_size+jj] == NULL)) ok = FALSE;
        if ((SEQ[ii*bots_arg_size+jj] != NULL) && (BENCH[ii*bots_arg_size+jj] != NULL))
           ok = checkmat(SEQ[ii*bots_arg_size+jj], BENCH[ii*bots_arg_size+jj]);
     }
  }
  if (ok) return BOTS_RESULT_SUCCESSFUL;
  else return BOTS_RESULT_UNSUCCESSFUL;
/*
  int i, j, ok;

  bots_message("Output size: %d\n",bots_arg_size);
  for (i = 0; i < bots_arg_size; i+=50)
  {
     for (j = 0; j < bots_arg_size; j+=40)
     {
           ok = checkmat1(BENCH[i*bots_arg_size+j]);
     }
  }
  return BOTS_RESULT_SUCCESSFUL;
*/

}
int checkmat1 (double *N)
{
  int i, j;

  for (i = 0; i < bots_arg_size_1; i+=20)
  {
     for (j = 0; j < bots_arg_size_1; j+=20)
     {
        bots_message("Output Matrix: A[%d][%d]=%8.12f \n",
                   i,j, N[i*bots_arg_size_1+j]);
     }
  }

 //printf("111111111\n");
  return TRUE;
}
