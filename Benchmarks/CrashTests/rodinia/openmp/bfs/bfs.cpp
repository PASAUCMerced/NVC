#include <stdio.h>
#include <string.h>
#include <math.h>
#include <stdlib.h>
#include "my_include.h"

#define OPEN


FILE *fp;

// Structure to hold a node information
struct Node {
    int starting;
    int no_of_edges;
};

void BFSGraph(int argc, char **argv);

void Usage(int argc, char **argv) {

    fprintf(stderr, "Usage: %s <input_file>\n", argv[0]);
}


////////////////////////////////////////////////////////////////////////////////
// Main Program
////////////////////////////////////////////////////////////////////////////////
int main(int argc, char **argv) {
    BFSGraph(argc, argv);
}


////////////////////////////////////////////////////////////////////////////////
// Apply BFS on a Graph
////////////////////////////////////////////////////////////////////////////////
void BFSGraph(int argc, char **argv) {
    int no_of_nodes = 0;
    int edge_list_size = 0;
    char *input_f;

    if (argc != 2) {
        Usage(argc, argv);
        exit(0);
    }

    input_f = argv[1];

    printf("Reading File\n");
    // Read in Graph from a file
    fp = fopen(input_f, "r");
    if (!fp) {
        printf("Error Reading graph file\n");
        return;
    }

    int source = 0;

    fscanf(fp, "%d", &no_of_nodes);

    // allocate host memory
    Node *h_graph_nodes = (Node *)malloc(sizeof(Node) * no_of_nodes);
    int *h_graph_mask = (int *)malloc(sizeof(int) * no_of_nodes);
    int *h_updating_graph_mask = (int *)malloc(sizeof(int) * no_of_nodes);
    int *h_graph_visited = (int *)malloc(sizeof(int) * no_of_nodes);

    int start, edgeno;
    // initalize the memory
    for (unsigned int i = 0; i < no_of_nodes; i++) {
        fscanf(fp, "%d %d", &start, &edgeno);
        h_graph_nodes[i].starting = start;
        h_graph_nodes[i].no_of_edges = edgeno;
        h_graph_mask[i] = 0;
        h_updating_graph_mask[i] = 0;
        h_graph_visited[i] = 0;
    }

    // read the source node from the file
    fscanf(fp, "%d", &source);
    // source=0; //tesing code line

    // set the source node as 1 in the mask
    h_graph_mask[source] = 1;
    h_graph_visited[source] = 1;

    fscanf(fp, "%d", &edge_list_size);

    int id, cost;
    int *h_graph_edges = (int *)malloc(sizeof(int) * edge_list_size);
    for (int i = 0; i < edge_list_size; i++) {
        fscanf(fp, "%d", &id);
        fscanf(fp, "%d", &cost);
        h_graph_edges[i] = id;
    }

    if (fp)
        fclose(fp);


    // allocate mem for the result on host side
    int *h_cost = (int *)malloc(sizeof(int) * no_of_nodes);
    for (int i = 0; i < no_of_nodes; i++)
        h_cost[i] = -1;
    h_cost[source] = 0;


//kai
	int flag1 = 0, flag2 = 0, flag3= 0, flag4 = 0;
	crucial_data(h_graph_mask, "int", no_of_nodes);
	crucial_data(h_updating_graph_mask, "int", no_of_nodes);
	crucial_data(h_graph_visited, "int", no_of_nodes); 
	crucial_data(h_cost, "int", no_of_nodes);
	consistent_data(&flag1, "int", 1);
	consistent_data(&flag2, "int", 1);
	consistent_data(&flag3, "int", 1);
	consistent_data(&flag4, "int", 1);

    flush_whole_cache();
    start_crash();
    printf("Start traversing the tree\n");

    int k = 0;
#ifdef OPEN
#ifdef OMP_OFFLOAD
#pragma omp target data map(                                                   \
    to : no_of_nodes,                                                          \
    h_graph_mask[0 : no_of_nodes],                                             \
                 h_graph_nodes[0 : no_of_nodes], h_graph_edges                 \
                               [0 : edge_list_size], h_graph_visited           \
                                [0 : no_of_nodes],                             \
                                 h_updating_graph_mask[0 : no_of_nodes])       \
                                    map(h_cost[0 : no_of_nodes])
    {
#endif
#endif
        int stop;
        do {
            // if no thread changes this value then the loop stops
            stop = 0;

#ifdef OPEN
// omp_set_num_threads(num_omp_threads);
#ifdef OMP_OFFLOAD
#pragma omp target
#endif
#pragma omp parallel for
#endif
            for (int tid = 0; tid < no_of_nodes; tid++) {
                if (h_graph_mask[tid] == 1) {
                    h_graph_mask[tid] = 0;
                    for (int i = h_graph_nodes[tid].starting;
                         i < (h_graph_nodes[tid].no_of_edges +
                              h_graph_nodes[tid].starting);
                         i++) {
                        int id = h_graph_edges[i];
                        if (!h_graph_visited[id]) {
                            h_cost[id] = h_cost[tid] + 1;
                            h_updating_graph_mask[id] = 1;
                        }
			//kai
			flag3 = i;
                    }
                }
		//kai
		flag2 = tid;
            }

#ifdef OPEN
#ifdef OMP_OFFLOAD
#pragma omp target map(stop)
#endif
#pragma omp parallel for
#endif
            for (int tid = 0; tid < no_of_nodes; tid++) {
                if (h_updating_graph_mask[tid] == 1) {
                    h_graph_mask[tid] = 1;
                    h_graph_visited[tid] = 1;
                    stop = 1;
                    h_updating_graph_mask[tid] = 0;
                }
		//kai
		flag4 = tid;
            }

		//kai
		flag1 = k;
            k++;
		printf("k=%d\n", k);
        } while (stop);
#ifdef OPEN
#ifdef OMP_OFFLOAD
    }
#endif
#endif
  //kai
	end_crash();

    // Store the result into a file
//    if (getenv("OUTPUT")) {
        FILE *fpo = fopen("output.txt", "w");
        for (int i = 0; i < no_of_nodes; i++)
            fprintf(fpo, "%d) cost:%d\n", i, h_cost[i]);
        fclose(fpo);
  //  }

    // cleanup memory
    free(h_graph_nodes);
    free(h_graph_edges);
    free(h_graph_mask);
    free(h_updating_graph_mask);
    free(h_graph_visited);
    free(h_cost);
}
