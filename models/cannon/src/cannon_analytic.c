/*****************************************************************************
PURPOSE:    ( Analytical Cannon )
*****************************************************************************/
#include "../include/cannon_analytic.h"
#include <math.h>
#include <stdio.h>

int cannon_analytic(CANNON* C)
{
    const double time_step = 0.01; // must match this job's rate in the S_define

    C->vel[0] = C->vel0[0] + C->acc[0] * C->time;  
    C->vel[1] = C->vel0[1] + C->acc[1] * C->time;  

    C->pos[0] = C->pos0[0] + (C->vel0[0] + 0.5 * C->acc[0] * C->time) * C->time;
    C->pos[1] = C->pos0[1] + (C->vel0[1] + 0.5 * C->acc[1] * C->time) * C->time;

    if (C->pos[1] < 0.0) { 
        // check for impact
        C->impactTime = (-C->vel0[1] - sqrt(C->vel0[1] * C->vel0[1] - 2.0 * C->acc[1] * C->pos0[1])) / C->acc[1];

        C->pos[0] = C->pos0[0] + (C->vel0[0] + 0.5 * C->acc[0] * C->impactTime) * C->impactTime;
        C->pos[1] = 0.0;

        C->vel[0] = 0.0;
        C->vel[1] = 0.0;

        if (!C->impact) {
            C->impact = 1;
            fprintf(stderr, "\n\nIMPACT: t = %.9f, pos[0] = %.9f\n\n", C->impactTime, C->pos[0]);
        }
    }

    /*
     * Increment model time by the time delta associated with this job.
     * time_step must match the frequency of this job as specified in the S_define.
     */
    C->time += time_step;

    return 0;
}