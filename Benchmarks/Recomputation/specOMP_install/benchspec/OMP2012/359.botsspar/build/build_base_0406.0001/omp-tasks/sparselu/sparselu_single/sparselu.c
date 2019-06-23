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
#include "read_memory.h"
/***********************************************************************
 * checkmat:
 **********************************************************************/


//float tmp[bots_arg_size][bots_arg_size][bots_arg_size_1*bots_arg_size_1];

int checkmat (float *M, float *N)
{
	//printf("11111\n");
   int i, j;
   float r_err;

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
            bots_message("Checking failure: A[%d][%d]=%f  B[%d][%d]=%f; Relative Error=%f\n",
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
void genmat (float *M[])
{
   int null_entry, init_val, i, j, ii, jj;
   float *p;
   float *prow;
   float rowsum;

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
           // M[ii*bots_arg_size+jj] = (float *) malloc(bots_arg_size_1*bots_arg_size_1*sizeof(float));
	   M[ii*bots_arg_size+jj] = (float*)((void*)tmp + tmp_pos);
	   tmp_pos += bots_arg_size_1*bots_arg_size_1*sizeof(float);

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
      	            (*p) = (float)((init_val - 32768.0) / 16384.0);
                    rowsum += abs(*p);
                    p++;
               }
               if (ii == jj)
                 *(prow+i) = rowsum * (float) bots_arg_size + abs(*(prow+i));
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
void print_structure(char *name, float *M[])
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
float * allocate_clean_block()
{
  int i,j;
  float *p, *q;
//printf("1\n");
 // p = (float *) malloc(bots_arg_size_1*bots_arg_size_1*sizeof(float));
  p = (float*)((void*)tmp + tmp_pos);
  tmp_pos += bots_arg_size_1*bots_arg_size_1*sizeof(float);
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
void lu0(float *diag)
{
   int i, j, k;
   //if(recompute == 0)
   flag1 = -1;//if(recompute == 0)
   for (k=flag1+1; k<bots_arg_size_1; k++) {
      for (i=k+1; i<bots_arg_size_1; i++)
      {
         diag[i*bots_arg_size_1+k] = diag[i*bots_arg_size_1+k] / diag[k*bots_arg_size_1+k];
         for (j=k+1; j<bots_arg_size_1; j++)
            diag[i*bots_arg_size_1+j] = diag[i*bots_arg_size_1+j] - diag[i*bots_arg_size_1+k] * diag[k*bots_arg_size_1+j];
      }
	   //kai
    }
}

/***********************************************************************
 * bdiv:
 **********************************************************************/
void bdiv(float *diag, float *row)
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
void bmod(float *row, float *col, float *inner)
{
   int i, j, k;
   for (i=0; i<bots_arg_size_1; i++)
      for (j=0; j<bots_arg_size_1; j++)
         for (k=0; k<bots_arg_size_1; k++)
            inner[i*bots_arg_size_1+j] = inner[i*bots_arg_size_1+j] - row[i*bots_arg_size_1+k]*col[k*bots_arg_size_1+j];
}
/***********************************************************************
 * bmod:
 **********************************************************************/
void vbmod(float *row, float *col, float *inner)
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
void fwd(float *diag, float *col)
{
   int i, j, k;
   for (j=0; j<bots_arg_size_1; j++)
      for (k=0; k<bots_arg_size_1; k++)
         for (i=k+1; i<bots_arg_size_1; i++)
            col[i*bots_arg_size_1+j] = col[i*bots_arg_size_1+j] - diag[i*bots_arg_size_1+k]*col[k*bots_arg_size_1+j];
}


void sparselu_init (float ***pBENCH, char *pass)
{
	tmp_pos  = 0;
   *pBENCH = (float **) malloc(bots_arg_size*bots_arg_size*sizeof(float *));
  // printf("%s\n", pass):
   tmp = malloc((bots_arg_size*bots_arg_size)*bots_arg_size_1*bots_arg_size_1*sizeof(float));
  //*pBENCH = (float **)tmp + tmp_pos;
   //tmp_pos += bots_arg_size*bots_arg_size*sizeof(float *);

   genmat(*pBENCH);

	//crucial_data(tmp, "float", (bots_arg_size*bots_arg_size*bots_arg_size_1*bots_arg_size_1));

//kai
   /*consistent_data(&flag1, "int", 1);
   consistent_data(&flag2, "int", 1);
   consistent_data(&flag3, "int", 1);
   consistent_data(&flag4, "int", 1);
   consistent_data(&flag5, "int", 1);*/

   /* spec  print_structure(pass, *pBENCH);  */
}

void sparselu_par_call(float **BENCH)
{

  //printf("1111\n");
   int ii, jj, kk;

   bots_message("Computing SparseLU Factorization (%dx%d matrix with %dx%d blocks) ",
           bots_arg_size,bots_arg_size,bots_arg_size_1,bots_arg_size_1);
//kai
	//flush_whole_cache();
   //start_crash();
   float *tmpt;
   tmpt = malloc((bots_arg_size*bots_arg_size)*bots_arg_size_1*bots_arg_size_1*sizeof(float));
   int t_flag1,t_flag2,t_flag3,t_flag4,t_flag5,t_flag6,t_flag7,t_flag8,t_flag9;
   ppid = pid;
   addr[count_addr++] = tmpt;
   addr[count_addr++] = &t_flag1;
   addr[count_addr++] = &t_flag2;
   addr[count_addr++] = &t_flag3;
   addr[count_addr++] = &t_flag4;
   addr[count_addr++] = &t_flag5;
   addr[count_addr++] = &t_flag6;
   addr[count_addr++] = &t_flag7;
   addr[count_addr++] = &t_flag8;
   addr[count_addr++] = &t_flag9;
   ReadVarriable(addr,count_addr);
   printf("flag1 = %d\n",t_flag1);
   printf("flag2 = %d\n",t_flag2);
   printf("flag3 = %d\n",t_flag3);
   printf("flag4 = %d\n",t_flag4);
   printf("flag5 = %d\n",t_flag5);
   printf("flag6 = %d\n",t_flag6);
   printf("flag7 = %d\n",t_flag7);
   printf("flag8 = %d\n",t_flag8);
   printf("flag9 = %d\n",t_flag9);
   //kk=0;flag1 = -1;flag2=kk; flag3 = kk; flag4 = kk;
   //memcpy(tmp,tmpt,(bots_arg_size*bots_arg_size)*bots_arg_size_1*bots_arg_size_1*sizeof(float));
   #pragma omp parallel
   #pragma omp single nowait
   //flag5=-1;
   for (kk=0; kk<bots_arg_size; kk++)
   {

    /* */
      lu0(BENCH[kk*bots_arg_size+kk]);
      //if(recompute == 0) flag2=kk;
      flag2=kk;
      for (jj=flag2+1; jj<bots_arg_size; jj++) {
         if (BENCH[kk*bots_arg_size+jj] != NULL)
            #pragma omp task untied firstprivate(kk, jj) shared(BENCH)
         {
            fwd(BENCH[kk*bots_arg_size+kk], BENCH[kk*bots_arg_size+jj]);
         }
	        //kai
	         //flag2 = kk+1;
      }
      //if(recompute == 0)  flag3=kk;
      flag3=kk;
      for (ii=flag3+1; ii<bots_arg_size; ii++) {
         if (BENCH[ii*bots_arg_size+kk] != NULL)
            #pragma omp task untied firstprivate(kk, ii) shared(BENCH)
         {
            bdiv (BENCH[kk*bots_arg_size+kk], BENCH[ii*bots_arg_size+kk]);
         }
	        //kai
	     //flag3 = kk+1;
      }
    /*  if(kk == flag5)
       {
         recompute = 1;
         float *ttmp = (float*) tmp;
         memcpy(tmp,tmpt,(bots_arg_size*bots_arg_size)*bots_arg_size_1*bots_arg_size_1*sizeof(float));
         flag1 = t_flag1;flag2=t_flag2; flag3 =t_flag3; flag4 = t_flag4;
       }
      else{
        recompute = 0;
      }*/
      if(recompute == 0) flag4=kk;
      #pragma omp taskwait
      for (ii=flag4+1; ii<bots_arg_size; ii++) {
          if(kk == flag5)
              printf("ii = %d\n",ii);

         if (BENCH[ii*bots_arg_size+kk] != NULL){
            for (jj=kk+1; jj<bots_arg_size; jj++)
               if (BENCH[kk*bots_arg_size+jj] != NULL)
               #pragma omp task untied firstprivate(kk, jj, ii) shared(BENCH)
               {
                     if (BENCH[ii*bots_arg_size+jj]==NULL) BENCH[ii*bots_arg_size+jj] = allocate_clean_block();
                     bmod(BENCH[ii*bots_arg_size+kk], BENCH[kk*bots_arg_size+jj], BENCH[ii*bots_arg_size+jj]);
               }
	        //kai
	       //flag4 = kk+1;
         if(kk == flag5 && ii ==flag4 &&jj==flag6)
          {    //memcpy(tmpt,tmp,(bots_arg_size*bots_arg_size)*bots_arg_size_1*bots_arg_size_1*sizeof(float));
              memcpy(tmp,tmpt,(bots_arg_size*bots_arg_size)*bots_arg_size_1*bots_arg_size_1*sizeof(float));
              if (strcmp(tmp,tmpt) == 0) {
                printf("Equal\n");
              }
              else{
                printf("Error!\n");
              }
          }
       }
      }
      #pragma omp taskwait
	    //flag5 = kk;
      recompute = 0;

   }
//kai
  // end_crash();
   bots_message(" completed!\n");
}


void sparselu_seq_call(float **BENCH)
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

void sparselu_fini (float **BENCH, char *pass)
{
   /* spec  print_structure(pass, BENCH); */
   return;
}

/*
 * changes for SPEC, original source
 *
int sparselu_check(float **SEQ, float **BENCH)
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
 void vgenmat (float *M[])
 {
    int null_entry, init_val, i, j, ii, jj;
    float *p;
    float *prow;
    float rowsum;

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
           M[ii*bots_arg_size+jj] = (float *) malloc(bots_arg_size_1*bots_arg_size_1*sizeof(float));
 	  // M[ii*bots_arg_size+jj] = (float*)((void*)tmp + tmp_pos);
 	 //  tmp_pos += bots_arg_size_1*bots_arg_size_1*sizeof(float);

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
       	            (*p) = (float)((init_val - 32768.0) / 16384.0);
                     rowsum += abs(*p);
                     p++;
                }
                if (ii == jj)
                  *(prow+i) = rowsum * (float) bots_arg_size + abs(*(prow+i));
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
void vlu0(float *diag)
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
void vsparselu_init (float ***pBENCH, char *pass)
{
   *pBENCH = (float **) malloc(bots_arg_size*bots_arg_size*sizeof(float *));
   vgenmat(*pBENCH);
   /* spec  print_structure(pass, *pBENCH);  */
}

void vsparselu_par_call(float **BENCH)
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

int sparselu_check(float **SEQ, float **BENCH)
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
   FILE *file;
   char result_file[128] = "/home/cc/nvc/tests/recompute_result.out.jie";
   sprintf(result_file + strlen(result_file), "%d", pid);
   file = fopen(result_file,"w");

   if(ok)
   {
     fprintf(file,"SUCCESS\n");
   }
   else{
     fprintf(file,"UNSUCCESS\n");
   }
   fclose(file);
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
int checkmat1 (float *N)
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
