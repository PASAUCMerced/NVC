#include <stdio.h>
#include <math.h>
#include <iostream>

using namespace std;
int main()
{
	int chk=1500;
	double recomp=0.4;
	int MTBF=12;
	
	for(int i=0;i<3;i++)
	{
	double total = 10*365*24*60*60;
	//int MTBF = 12;
	//int chk=32*10;
	if(i!=0)
		MTBF /=2;
	cout<<"MTBF = "<<MTBF<<endl;
	double T = sqrt(2*MTBF*60*60*chk);
	int M = 10*365*24/MTBF;
	cout<<"T = "<<T<<endl;
	double T_w = (3*(chk + T))/2*M;
	//cout<<"T_w = "<<T_w<<endl;
	int N1 = (total - T_w)/T +1;
	int N2 = (total - T_w)/(T + 0.5*chk) +1;
	int N3 = (total - T_w)/(T + chk) +1;
	
	double e1 = T*N1/total;
	double e2 = T*N2/total;
	double e3 = T*N3/total;

	cout<<e1<<endl;
	cout<<e2<<endl;
	cout<<e3<<endl;
	}
	
	cout<<"EC"<<endl;
	MTBF=12;
	for(int i=0;i<3;i++)
        {
       	double total = 10*365*24*60*60;
        //int MTBF = 12;
        	
        if(i!=0)
                MTBF = MTBF/2;
        cout<<"MTBF = "<<MTBF<<endl;
        double T = sqrt(2*(MTBF/(1-recomp))*60*60*chk);
        int M = 10*365*24/MTBF;
	double M1 = M*recomp;
	double M2 = M*(1-recomp);

        cout<<"T = "<<T<<endl;
        double T_w = (3*(chk + T))/2*M2 + chk*0.5*M1;
        int N1 = (total - T_w)/T +1;
        int N2 = (total - T_w)/(T + 0.5*chk) +1;
        int N3 = (total - T_w)/(T + chk) +1;

        double e1 = T*N1/total;
        double e2 = T*N2/total;
        double e3 = T*N3/total;

        cout<<e1<<endl;
        cout<<e2<<endl;
        cout<<e3<<endl;
	}
	return 0;
}
