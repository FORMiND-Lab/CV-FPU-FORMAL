//============================================================================
// softfloat_dpi.h — SoftFloat DPI-C 函数声明 (C++ 侧)
//============================================================================

#ifndef SOFLOAT_DPI_H
#define SOFLOAT_DPI_H

#include <cstdint>

extern "C" {

// FP32 fused multiply-add: result = a * b + c
void dpi_fmadd_s(
    int         enable,
    std::uint32_t a,
    std::uint32_t b,
    std::uint32_t c,
    std::uint32_t rm,
    std::uint32_t* result,
    std::uint32_t* fflags
);

// FP32 fused multiply-sub: result = a * b - c
void dpi_fmsub_s(
    int         enable,
    std::uint32_t a,
    std::uint32_t b,
    std::uint32_t c,
    std::uint32_t rm,
    std::uint32_t* result,
    std::uint32_t* fflags
);

// FP32 negated multiply-add: result = -(a * b) + c
void dpi_fnmadd_s(
    int         enable,
    std::uint32_t a,
    std::uint32_t b,
    std::uint32_t c,
    std::uint32_t rm,
    std::uint32_t* result,
    std::uint32_t* fflags
);

// FP32 negated multiply-sub: result = -(a * b) - c
void dpi_fnmsub_s(
    int         enable,
    std::uint32_t a,
    std::uint32_t b,
    std::uint32_t c,
    std::uint32_t rm,
    std::uint32_t* result,
    std::uint32_t* fflags
);

} // extern "C"

#endif // SOFLOAT_DPI_H
