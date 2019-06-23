//-------------------------------------------------------------------------//
//                                                                         //
//  This benchmark is an OpenMP C version of the NPB LU code. This OpenMP  //
//  C version is developed by the Center for Manycore Programming at Seoul //
//  National University and derived from the OpenMP Fortran versions in    //
//  "NPB3.3-OMP" developed by NAS.                                         //
//                                                                         //
//  Permission to use, copy, distribute and modify this software for any   //
//  purpose with or without fee is hereby granted. This software is        //
//  provided "as is" without express or implied warranty.                  //
//                                                                         //
//  Information on NPB 3.3, including the technical report, the original   //
//  specifications, source code, results and information on how to submit  //
//  new results, is available at:                                          //
//                                                                         //
//           http://www.nas.nasa.gov/Software/NPB/                         //
//                                                                         //
//  Send comments or suggestions for this OpenMP C version to              //
//  cmp@aces.snu.ac.kr                                                     //
//                                                                         //
//          Center for Manycore Programming                                //
//          School of Computer Science and Engineering                     //
//          Seoul National University                                      //
//          Seoul 151-744, Korea                                           //
//                                                                         //
//          E-mail:  cmp@aces.snu.ac.kr                                    //
//                                                                         //
//-------------------------------------------------------------------------//

//-------------------------------------------------------------------------//
// Authors: Sangmin Seo, Jungwon Kim, Jun Lee, Jeongho Nah, Gangwon Jo,    //
//          and Jaejin Lee                                                 //
//-------------------------------------------------------------------------//

//---------------------------------------------------------------------
//   program applu
//---------------------------------------------------------------------

//---------------------------------------------------------------------
//
//   driver for the performance evaluation of the solver for
//   five coupled parabolic/elliptic partial differential equations.
//
//---------------------------------------------------------------------

#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include "applu.incl"
#include "timers.h"
#include "print_results.h"

//---------------------------------------------------------------------
// grid
//---------------------------------------------------------------------
/* common/cgcon/ */
double dxi, deta, dzeta;
double tx1, tx2, tx3;
double ty1, ty2, ty3;
double tz1, tz2, tz3;
int nx, ny, nz;
int nx0, ny0, nz0;
int ist, iend;
int jst, jend;
int ii1, ii2;
int ji1, ji2;
int ki1, ki2;

//---------------------------------------------------------------------
// dissipation
//---------------------------------------------------------------------
/* common/disp/ */
double dx1, dx2, dx3, dx4, dx5;
double dy1, dy2, dy3, dy4, dy5;
double dz1, dz2, dz3, dz4, dz5;
double dssp;

//---------------------------------------------------------------------
// field variables and residuals
// to improve cache performance, second two dimensions padded by 1
// for even number sizes only.
// Note: corresponding array (called "v") in routines blts, buts,
// and l2norm are similarly padded
//---------------------------------------------------------------------
/* common/cvar/ */
double u    [ISIZ3][ISIZ2/2*2+1][ISIZ1/2*2+1][5];
double rsd  [ISIZ3][ISIZ2/2*2+1][ISIZ1/2*2+1][5];
double frct [ISIZ3][ISIZ2/2*2+1][ISIZ1/2*2+1][5];
double flux [ISIZ1][5];
double qs   [ISIZ3][ISIZ2/2*2+1][ISIZ1/2*2+1];
double rho_i[ISIZ3][ISIZ2/2*2+1][ISIZ1/2*2+1];

//---------------------------------------------------------------------
// output control parameters
//---------------------------------------------------------------------
/* common/cprcon/ */
int ipr, inorm;

//---------------------------------------------------------------------
// newton-raphson iteration control parameters
//---------------------------------------------------------------------
/* common/ctscon/ */
double dt, omega, tolrsd[5], rsdnm[5], errnm[5], frc, ttotal;
int itmax, invert;

/* common/cjac/ */
double a[ISIZ2][ISIZ1/2*2+1][5][5];
double b[ISIZ2][ISIZ1/2*2+1][5][5];
double c[ISIZ2][ISIZ1/2*2+1][5][5];
double d[ISIZ2][ISIZ1/2*2+1][5][5];

/* common/cjacu/ */
double au[ISIZ2][ISIZ1/2*2+1][5][5];
double bu[ISIZ2][ISIZ1/2*2+1][5][5];
double cu[ISIZ2][ISIZ1/2*2+1][5][5];
double du[ISIZ2][ISIZ1/2*2+1][5][5];


//---------------------------------------------------------------------
// coefficients of the exact solution
//---------------------------------------------------------------------
/* common/cexact/ */
double ce[5][13];


//---------------------------------------------------------------------
// timers
//---------------------------------------------------------------------
/* common/timer/ */
double maxtime;
logical timeron;

//kai
int k1,k2,k3,k4;

int main(int argc, char *argv[])
{
  int pid = atoi(argv[1]);
	printf("pid = %d\n",pid);
  /*
  //kai
//[ISIZ3][ISIZ2/2*2+1][ISIZ1/2*2+1][5];
   crucial_data(u, "double", ISIZ3*(ISIZ2/2*2+1)*(ISIZ1/2*2+1)*5);
   crucial_data(rsd, "double", ISIZ3*(ISIZ2/2*2+1)*(ISIZ1/2*2+1)*5);
   crucial_data(frct, "double", ISIZ3*(ISIZ2/2*2+1)*(ISIZ1/2*2+1)*5);
 //  crucial_data(flux, "double", 5);
   crucial_data(qs, "double", ISIZ3*(ISIZ2/2*2+1)*(ISIZ1/2*2+1));
   crucial_data(rho_i, "double", ISIZ3*(ISIZ2/2*2+1)*(ISIZ1/2*2+1));

 //  crucial_data(tolrsd, "double", 5);
   crucial_data(rsdnm, "double", 5);
 //  crucial_data(errnm, "double", 5);
   crucial_data(a, "double", ISIZ2*(ISIZ1/2*2+1)*5*5);
   crucial_data(b, "double", ISIZ2*(ISIZ1/2*2+1)*5*5);
   crucial_data(c, "double", ISIZ2*(ISIZ1/2*2+1)*5*5);
   crucial_data(d, "double", ISIZ2*(ISIZ1/2*2+1)*5*5);
   crucial_data(au, "double", ISIZ2*(ISIZ1/2*2+1)*5*5);
   crucial_data(bu, "double", ISIZ2*(ISIZ1/2*2+1)*5*5);
   crucial_data(cu, "double", ISIZ2*(ISIZ1/2*2+1)*5*5);
   crucial_data(du, "double", ISIZ2*(ISIZ1/2*2+1)*5*5);
   //crucial_data(ce, "double", 13*5);



  consistent_data(&k1, "int", 1);
  consistent_data(&k2, "int", 1);
  consistent_data(&k3, "int", 1);
  consistent_data(&k4, "int", 1);
*/

  char Class;
  logical verified;
  logical verified1;
  logical verified2;
  logical verified3;
  double mflops;

  double t, tmax, trecs[t_last+1];
  int i;
  char *t_names[t_last+1];

  //---------------------------------------------------------------------
  // Setup info for timers
  //---------------------------------------------------------------------
  FILE *fp;
  if ((fp = fopen("timer.flag", "r")) != NULL) {
    timeron = true;
    t_names[t_total] = "total";
    t_names[t_rhsx] = "rhsx";
    t_names[t_rhsy] = "rhsy";
    t_names[t_rhsz] = "rhsz";
    t_names[t_rhs] = "rhs";
    t_names[t_jacld] = "jacld";
    t_names[t_blts] = "blts";
    t_names[t_jacu] = "jacu";
    t_names[t_buts] = "buts";
    t_names[t_add] = "add";
    t_names[t_l2norm] = "l2norm";
    fclose(fp);
  } else {
    timeron = false;
  }

  //---------------------------------------------------------------------
  // read input data
  //---------------------------------------------------------------------
  read_input();

  //---------------------------------------------------------------------
  // set up domain sizes
  //---------------------------------------------------------------------
  domain();

  //---------------------------------------------------------------------
  // set up coefficients
  //---------------------------------------------------------------------
  setcoeff();

  //---------------------------------------------------------------------
  // set the boundary values for dependent variables
  //---------------------------------------------------------------------
  setbv();

  //---------------------------------------------------------------------
  // set the initial values for dependent variables
  //---------------------------------------------------------------------
  setiv();

  //---------------------------------------------------------------------
  // compute the forcing term based on prescribed exact solution
  //---------------------------------------------------------------------
  erhs();

  //---------------------------------------------------------------------
  // perform one SSOR iteration to touch all data pages
  //---------------------------------------------------------------------
  ssor(1,pid);

  //---------------------------------------------------------------------
  // reset the boundary and initial values
  //---------------------------------------------------------------------
  setbv();
  setiv();

  //---------------------------------------------------------------------
  // perform the SSOR iterations
  //---------------------------------------------------------------------
  ssor(itmax,pid);

  //---------------------------------------------------------------------
  // compute the solution error
  //---------------------------------------------------------------------
  error();

  //---------------------------------------------------------------------
  // compute the surface integral
  //---------------------------------------------------------------------
  pintgr();

  //---------------------------------------------------------------------
  // verification test
  //---------------------------------------------------------------------
  verify ( rsdnm, errnm, frc, &Class, &verified1, &verified2, &verified3, &verified );
  mflops = (double)itmax * (1984.77 * (double)nx0
      * (double)ny0
      * (double)nz0
      - 10923.3 * pow(((double)(nx0+ny0+nz0)/3.0), 2.0)
      + 27770.9 * (double)(nx0+ny0+nz0)/3.0
      - 144010.0)
    / (maxtime*1000000.0);

  FILE *file;
  char result_file[128] = "/home/cc/nvc/tests/recompute_result.out.jie";
  sprintf(result_file + strlen(result_file), "%d", pid);
  file = fopen(result_file,"w");

  if(verified)
  {
    fprintf(file,"%d,%d,%d,SUCCESS\n",verified1,verified2,verified3);
  }
  else{
    fprintf(file,"%d,%d,%d,UNSUCCESS\n",verified1,verified2,verified3);
  }
  fclose(file);

  print_results("LU", Class, nx0,
                ny0, nz0, itmax,
                maxtime, mflops, "          floating point", verified,
                NPBVERSION, COMPILETIME, CS1, CS2, CS3, CS4, CS5, CS6,
                "(none)");

  //---------------------------------------------------------------------
  // More timers
  //---------------------------------------------------------------------
  if (timeron) {
    for (i = 1; i <= t_last; i++) {
      trecs[i] = timer_read(i);
    }
    tmax = maxtime;
    if (tmax == 0.0) tmax = 1.0;

    printf("  SECTION     Time (secs)\n");
    for (i = 1; i <= t_last; i++) {
      printf("  %-8s:%9.3f  (%6.2f%%)\n",
          t_names[i], trecs[i], trecs[i]*100./tmax);
      if (i == t_rhs) {
        t = trecs[t_rhsx] + trecs[t_rhsy] + trecs[t_rhsz];
        printf("     --> %8s:%9.3f  (%6.2f%%)\n", "sub-rhs", t, t*100./tmax);
        t = trecs[i] - t;
        printf("     --> %8s:%9.3f  (%6.2f%%)\n", "rest-rhs", t, t*100./tmax);
      }
    }
  }

  return 0;
}
