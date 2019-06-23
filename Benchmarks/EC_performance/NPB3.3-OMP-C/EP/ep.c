//-------------------------------------------------------------------------//
//                                                                         //
//  This benchmark is an OpenMP C version of the NPB EP code. This OpenMP  //
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
//      program EMBAR
//---------------------------------------------------------------------
//   M is the Log_2 of the number of complex pairs of uniform (0, 1) random
//   numbers.  MK is the Log_2 of the size of each batch of uniform random
//   numbers.  MK can be set for convenience on a given system, since it does
//   not affect the results.
//---------------------------------------------------------------------

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#ifdef _OPENMP
#include <omp.h>
#endif

#include "type.h"
#include "npbparams.h"
#include "randdp.h"
#include "timers.h"
#include "print_results.h"
#include  "../my_include/my_include.h"
#define MAX(X,Y)  (((X) > (Y)) ? (X) : (Y))

#define MK        16
#define MM        (M - MK)
#define NN        (1 << MM)
#define NK        (1 << MK)
#define NQ        10
#define EPSILON   1.0e-8
#define A         1220703125.0
#define S         271828183.0

static double x[2*NK];
static double qq[NQ];
#pragma omp threadprivate(x,qq)
static double q[NQ];
int    i1=0, i2=0, i3=0, k_temp = 0;
double ssx,ssy;

void vranlc_temp( int n, double *x, double a, double y[] )
{
  //--------------------------------------------------------------------
  //
  //  This routine generates N uniform pseudorandom double precision numbers in
  //  the range (0, 1) by using the linear congruential generator
  //
  //  x_{k+1} = a x_k  (mod 2^46)
  //
  //  where 0 < x_k < 2^46 and 0 < a < 2^46.  This scheme generates 2^44 numbers
  //  before repeating.  The argument A is the same as 'a' in the above formula,
  //  and X is the same as x_0.  A and X must be odd double precision integers
  //  in the range (1, 2^46).  The N results are placed in Y and are normalized
  //  to be between 0 and 1.  X is updated to contain the new seed, so that
  //  subsequent calls to VRANLC using the same arguments will generate a
  //  continuous sequence.  If N is zero, only initialization is performed, and
  //  the variables X, A and Y are ignored.
  //
  //  This routine is the standard version designed for scalar or RISC systems.
  //  However, it should produce the same results on any single processor
  //  computer with at least 48 mantissa bits in double precision floating point
  //  data.  On 64 bit systems, double precision should be disabled.
  //
  //--------------------------------------------------------------------

  // r23 = pow(0.5, 23.0);
  ////  pow(0.5, 23.0) = 1.1920928955078125e-07
  // r46 = r23 * r23;
  // t23 = pow(2.0, 23.0);
  ////  pow(2.0, 23.0) = 8.388608e+06
  // t46 = t23 * t23;

  const double r23 = 1.1920928955078125e-07;
  const double r46 = r23 * r23;
  const double t23 = 8.388608e+06;
  const double t46 = t23 * t23;

  double t1, t2, t3, t4, a1, a2, x1, x2, z;

  int i;

  //--------------------------------------------------------------------
  //  Break A into two parts such that A = 2^23 * A1 + A2.
  //--------------------------------------------------------------------
  t1 = r23 * a;
  a1 = (int) t1;
  a2 = a - t23 * a1;

  //--------------------------------------------------------------------
  //  Generate N results.   This loop is not vectorizable.
  //--------------------------------------------------------------------
  for ( i = 0; i < n; i++ ) {
    //--------------------------------------------------------------------
    //  Break X into two parts such that X = 2^23 * X1 + X2, compute
    //  Z = A1 * X2 + A2 * X1  (mod 2^23), and then
    //  X = 2^23 * Z + A2 * X2  (mod 2^46).
    //--------------------------------------------------------------------
    t1 = r23 * (*x);
    x1 = (int) t1;
    x2 = *x - t23 * x1;
    t1 = a1 * x2 + a2 * x1;
    t2 = (int) (r23 * t1);
    z = t1 - t23 * t2;
    t3 = t23 * z + a2 * x2;
    t4 = (int) (r46 * t3) ;
    *x = t3 - t46 * t4;
    y[i] = r46 * (*x);
    i3 = i;
  }

  return;
}

int main(int argc, char *argv[])
{
  crucial_data(x,"double",2*NK);
  crucial_data(qq,"double",NQ);
  crucial_data(q,"double",NQ);
  crucial_data(&ssx,"double",1);
  crucial_data(&ssy,"double",1);
  //printf("the addr of x at beginning is %p\n",x);
  double Mops, t1, t2, t3, t4, x1, x2;
  double sx, sy, tm, an, tt, gc;
  double sx_verify_value, sy_verify_value, sx_err, sy_err;
  int    np;
  int    i, ik, kk, l, k, nit;
  int    k_offset, j;

  logical verified, timers_enabled;
  consistent_data(&k_temp,"int",1);
  consistent_data(&i1,"int",1);
  consistent_data(&i2,"int",1);
  //consistent_data(&i3,"int",1);
  double dum[3] = {1.0, 1.0, 1.0};
  char   size[16];

  FILE *fp;

  if ((fp = fopen("timer.flag", "r")) == NULL) {
    timers_enabled = false;
  } else {
    timers_enabled = true;
    fclose(fp);
  }

  //--------------------------------------------------------------------
  //  Because the size of the problem is too large to store in a 32-bit
  //  integer for some classes, we put it into a string (for printing).
  //  Have to strip off the decimal point put in there by the floating
  //  point print statement (internal file)
  //--------------------------------------------------------------------

  sprintf(size, "%15.0lf", pow(2.0, M+1));
  j = 14;
  if (size[j] == '.') j--;
  size[j+1] = '\0';
  printf("\n\n NAS Parallel Benchmarks (NPB3.3-OMP-C) - EP Benchmark\n");
  printf("\n Number of random numbers generated: %15s\n", size);
  printf("\n Number of available threads:          %13d\n", omp_get_max_threads());

  verified = false;

  //--------------------------------------------------------------------
  //  Compute the number of "batches" of random number pairs generated
  //  per processor. Adjust if the number of processors does not evenly
  //  divide the total number
  //--------------------------------------------------------------------

  np = NN;

  //--------------------------------------------------------------------
  //  Call the random number generator functions and initialize
  //  the x-array to reduce the effects of paging on the timings.
  //  Also, call all mathematical functions that are used. Make
  //  sure these initializations cannot be eliminated as dead code.
  //--------------------------------------------------------------------

  vranlc(0, &dum[0], dum[1], &dum[2]);
  dum[0] = randlc(&dum[1], dum[2]);
  #pragma omp parallel default(shared) private(i)
  {
    for (i = 0; i < 2 * NK; i++) {
      x[i] = -1.0e99;
    }
  }
  Mops = log(sqrt(fabs(MAX(1.0, 1.0))));

  #pragma omp parallel
  {
    timer_clear(0);
    if (timers_enabled) timer_clear(1);
    if (timers_enabled) timer_clear(2);
  }
  timer_start(0);

  t1 = A;
  vranlc(0, &t1, A, x);

  //--------------------------------------------------------------------
  //  Compute AN = A ^ (2 * NK) (mod 2^46).
  //--------------------------------------------------------------------

  t1 = A;

  for (i = 0; i < MK + 1; i++) {
    t2 = randlc(&t1, t1);
  }

  an = t1;
  tt = S;
  gc = 0.0;
  sx = 0.0;
  sy = 0.0;

  for (i = 0; i < NQ; i++) {
    q[i] = 0.0;
  }

  //--------------------------------------------------------------------
  //  Each instance of this loop may be performed independently. We compute
  //  the k offsets separately to take into account the fact that some nodes
  //  have more numbers to generate than others
  //--------------------------------------------------------------------
  int calculate_counter = 0;
  int uncalculate_counter = 0;
  k_offset = -1;
  //FILE *testfile;
  //testfile = fopen("resultfile1443.out","w");
  //printf("the addr of x at middle is %p\n",x);
  //printf("np = %d\n", np);
  #pragma omp parallel default(shared) private(k,kk,t1,t2,t3,t4,i,ik,x1,x2,l)
  {
    for (i = 0; i < NQ; i++) {
      qq[i] = 0.0;
    }
    flush_whole_cache();
    //start_crash();
    printf("np = %d\n", np);
    #pragma omp for reduction(+:sx,sy) nowait
    for (k = 1; k <= np; k++) {//main conputation loop
      kk = k_offset + k;
      t1 = S;
      t2 = an;

      for (i = 1; i <= 100; i++) {
        ik = kk / 2;
        if ((2 * ik) != kk) t3 = randlc(&t1, t2);
        if (ik == 0) break;
        t3 = randlc(&t2, t2);
        kk = ik;
        i1 = i;
      }
      //printf("k=%d, i1 = %d\n",k,i1);
      //--------------------------------------------------------------------
      //  Compute uniform pseudorandom numbers.
      //--------------------------------------------------------------------
      if (timers_enabled) timer_start(2);
      //vranlc_temp(2 * NK, &t1, A, x);
      if (timers_enabled) timer_stop(2);
      /*if(k==2981){
      fprintf(testfile,"after vranlc, t1 = %lf, A = %lf\n",t1, A);
      for(ijk = 0; ijk<2*NK; ijk++)
      {
        fprintf(testfile,"%lf\n",x[ijk]);
      }}*/
      //--------------------------------------------------------------------
      //  Compute Gaussian deviates by acceptance-rejection method and
      //  tally counts in concentri//square annuli.  This loop is not
      //  vectorizable.
      //--------------------------------------------------------------------
      if (timers_enabled) timer_start(1);
      //printf("NK = %d\n", NK);
      for (i = 0; i < NK; i++) {
        x1 = 2.0 * x[2*i] - 1.0;
        x2 = 2.0 * x[2*i+1] - 1.0;
        t1 = x1 * x1 + x2 * x2;

        if (t1 <= 1.0) {
          t2    = sqrt(-2.0 * log(t1) / t1);
          t3    = (x1 * t2);
          t4    = (x2 * t2);
          l     = MAX(fabs(t3), fabs(t4));
          qq[l] = qq[l] + 1.0;
          sx    = sx + t3;
          sy    = sy + t4;
        }
        i2=i;
      }
      if (timers_enabled) timer_stop(1);
      k_temp=k;
      ssx = sx;
      ssy = sy;
      /*sx_err = fabs((sx - sx_verify_value) / sx_verify_value);
      sy_err = fabs((sy - sy_verify_value) / sy_verify_value);
      verified = ((sx_err <= EPSILON) && (sy_err <= EPSILON));
      printf("sx_err = %25.15lE, sy_err =%25.15lE\n",sx_err, sy_err);*/
    }
    end_crash();
    printf("%d %d\n",calculate_counter,uncalculate_counter);
    for (i = 0; i < NQ; i++) {
      #pragma omp atomic
      q[i] += qq[i];
    }
  }
  //fclose(testfile);
  for (i = 0; i < NQ; i++) {
    gc = gc + q[i];
  }

  timer_stop(0);
  tm = timer_read(0);

  nit = 0;
  verified = true;
  if (M == 24) {
    sx_verify_value = -3.247834652034740e+3;
    sy_verify_value = -6.958407078382297e+3;
  } else if (M == 25) {
    sx_verify_value = -2.863319731645753e+3;
    sy_verify_value = -6.320053679109499e+3;
  } else if (M == 28) {
    sx_verify_value = -4.295875165629892e+3;
    sy_verify_value = -1.580732573678431e+4;
  } else if (M == 30) {
    sx_verify_value =  4.033815542441498e+4;
    sy_verify_value = -2.660669192809235e+4;
  } else if (M == 32) {
    sx_verify_value =  4.764367927995374e+4;
    sy_verify_value = -8.084072988043731e+4;
  } else if (M == 36) {
    sx_verify_value =  1.982481200946593e+5;
    sy_verify_value = -1.020596636361769e+5;
  } else if (M == 40) {
    sx_verify_value = -5.319717441530e+05;
    sy_verify_value = -3.688834557731e+05;
  } else {
    verified = false;
  }

  if (verified) {
    sx_err = fabs((sx - sx_verify_value) / sx_verify_value);
    sy_err = fabs((sy - sy_verify_value) / sy_verify_value);
    verified = ((sx_err <= EPSILON) && (sy_err <= EPSILON));
  }

  Mops = pow(2.0, M+1) / tm / 1000000.0;

  printf("\nEP Benchmark Results:\n\n");
  printf("CPU Time =%10.4lf\n", tm);
  printf("N = 2^%5d\n", M);
  printf("No. Gaussian Pairs = %15.0lf\n", gc);
  printf("Sums = %25.15lE %25.15lE\n", sx, sy);
  printf("Counts: \n");
  for (i = 0; i < NQ; i++) {
    printf("%3d%15.0lf\n", i, q[i]);
  }

  print_results("EP", CLASS, M+1, 0, 0, nit,
      tm, Mops,
      "Random numbers generated",
      verified, NPBVERSION, COMPILETIME, CS1,
      CS2, CS3, CS4, CS5, CS6, CS7);

  if (timers_enabled) {
    if (tm <= 0.0) tm = 1.0;
    tt = timer_read(0);
    printf("\nTotal time:     %9.3lf (%6.2lf)\n", tt, tt*100.0/tm);
    tt = timer_read(1);
    printf("Gaussian pairs: %9.3lf (%6.2lf)\n", tt, tt*100.0/tm);
    tt = timer_read(2);
    printf("Random numbers: %9.3lf (%6.2lf)\n", tt, tt*100.0/tm);
  }

  return 0;
}
