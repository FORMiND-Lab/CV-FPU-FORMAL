#include <stdint.h>
#include "platform.h"
#ifndef softfloat_shiftRightJam32
uint32_t softfloat_shiftRightJam32( uint32_t a, uint_fast16_t dist )
{
    uint_fast16_t d = dist & 0x1F;
    uint_fast16_t inv = (32u - dist) & 0x1F;
    return (dist < 31) ? (a >> d) | (((uint32_t)(a << inv)) != 0) : (a != 0);
}
#endif
