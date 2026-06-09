#include "Hector.h"
#include "softfloat.h"

void hector_wrapper()
{
    uint8_t  rounding_mode;
    uint8_t  exceptions;
    uint16_t multiplier;
    uint16_t multiplicand;
    uint16_t addend;
    uint16_t result;

    float16_t f_multiplicand;
    float16_t f_addend;
    float16_t f_result;

    Hector::registerInput("multiplier",    &multiplier,    16);
    Hector::registerInput("multiplicand",  &multiplicand,  16);
    Hector::registerInput("addend",        &addend,        16);
    Hector::registerInput("rounding_mode", &rounding_mode, 8 * sizeof(rounding_mode));
    Hector::registerOutput("result",       &result,        16);
    Hector::registerOutput("exceptions",   &exceptions,    8 * sizeof(exceptions));

    Hector::beginCapture();

    f_multiplicand.v = multiplicand;
    f_addend.v       = addend;

    softfloat_roundingMode   = rounding_mode;
    softfloat_exceptionFlags = 0;
    softfloat_detectTininess = softfloat_tininess_afterRounding;

    f_result = f16_add(f_multiplicand, f_addend);

    result = f_result.v;

    exceptions = 0;
    if (softfloat_exceptionFlags & softfloat_flag_invalid)   exceptions |= (1 << 4);
    if (softfloat_exceptionFlags & softfloat_flag_overflow)  exceptions |= (1 << 2);
    if (softfloat_exceptionFlags & softfloat_flag_underflow) exceptions |= (1 << 1);
    if (softfloat_exceptionFlags & softfloat_flag_inexact)   exceptions |= (1 << 0);

    Hector::endCapture();
}
