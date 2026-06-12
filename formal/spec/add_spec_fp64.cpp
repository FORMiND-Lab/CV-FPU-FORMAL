#include "Hector.h"
#include "softfloat.h"
void hector_wrapper()
{
    uint8_t  rounding_mode;
    uint8_t  exceptions;
    uint64_t multiplier;
    uint64_t multiplicand;
    uint64_t addend;
    uint64_t result;
    float64_t f_multiplicand;
    float64_t f_addend;
    float64_t f_result;
    Hector::registerInput("multiplier",    &multiplier,    64);
    Hector::registerInput("multiplicand",  &multiplicand,  64);
    Hector::registerInput("addend",        &addend,        64);
    Hector::registerInput("rounding_mode", &rounding_mode, 8 * sizeof(rounding_mode));
    Hector::registerOutput("result",       &result,        64);
    Hector::registerOutput("exceptions",   &exceptions,    8 * sizeof(exceptions));
    Hector::beginCapture();
    f_multiplicand.v = multiplicand;
    f_addend.v       = addend;
    softfloat_roundingMode   = rounding_mode;
    softfloat_exceptionFlags = 0;
    softfloat_detectTininess = softfloat_tininess_afterRounding;
    f_result = f64_add(f_multiplicand, f_addend);
    result     = f_result.v;
    exceptions = 0;
    if (softfloat_exceptionFlags & softfloat_flag_invalid)   exceptions |= (1 << 4);
    if (softfloat_exceptionFlags & softfloat_flag_overflow)  exceptions |= (1 << 2);
    if (softfloat_exceptionFlags & softfloat_flag_underflow) exceptions |= (1 << 1);
    if (softfloat_exceptionFlags & softfloat_flag_inexact)   exceptions |= (1 << 0);
    Hector::endCapture();
}
