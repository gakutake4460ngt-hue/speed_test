#pragma once
#include <stdint.h>

// phase: 0 idle, 1 ping, 2 down, 3 up
// mode:  0 down, 1 up, 2 alternate
typedef struct {
    uint32_t phase;
    uint32_t cycle;
    uint32_t running;
    uint32_t error;
    double mbps;
    double down_mbps;
    double up_mbps;
    double ping_ms;
    double progress;
} ScStatus;

void sc_start(uint32_t mode);
void sc_stop(void);
void sc_status(ScStatus *out);
