/******************************* TRICK HEADER ****************************
PURPOSE: (Set the initial data values)
*************************************************************************/

/* Model Include files */
#include "../include/cannon.h"
#include <math.h>

/* default data job */
int cannon_default_data(CANNON* C)
{
    C->acc[0] = 0.0;            // m/s^2
    C->acc[1] = -9.81;          // m/s^2

    C->init_angle = M_PI / 6.0; // rad
    C->init_speed = 50.0;       // m/s

    C->pos0[0] = 0.0;           // m
    C->pos0[1] = 0.0;           // m

    C->time = 0.0;              // s

    C->impact     = 0;          // no impact yet
    C->impactTime = 0.0;        // s

    return 0;
}

/* initialization job */
int cannon_init(CANNON* C)
{
    C->vel0[0] = C->init_speed * cos(C->init_angle);
    C->vel0[1] = C->init_speed * sin(C->init_angle);

    C->pos[0] = C->pos0[0];
    C->pos[1] = C->pos0[1];

    C->vel[0] = C->vel0[0];
    C->vel[1] = C->vel0[1];

    return 0;
}