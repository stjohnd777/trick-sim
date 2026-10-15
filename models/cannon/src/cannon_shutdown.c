/************************************************************************
PURPOSE: (Print the final cannon ball state.)
*************************************************************************/
#include "../include/cannon.h"
#include "trick/exec_proto.h"
#include <stdio.h>

int cannon_shutdown(CANNON* C)
{
    const double t = exec_get_sim_time(); // s

    printf("========================================\n");
    printf("      Cannon Ball State at Shutdown     \n");
    printf("t = %g\n", t);
    printf("pos = [%.9f, %.9f]\n", C->pos[0], C->pos[1]);
    printf("vel = [%.9f, %.9f]\n", C->vel[0], C->vel[1]);
    printf("========================================\n");

    return 0;
}