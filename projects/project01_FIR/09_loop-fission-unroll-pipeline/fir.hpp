#pragma once

#include <ap_int.h>

#define N 11 // Filter dimension

//* OPTIMIZATION(ap-int): using ap_int data types
// --- USER DEFINED DATA DIMENSIONS ---
#define COEF_BIT 10 // Number of bits for filter coefficients
#define IN_BIT 12   // Number of bits for input data
#define OUT_BIT 32  // Number of bits for output data

// --- CALCULATED DATA DIMENSIONS ---
// Calculated at compile time
constexpr int ceil_log2(unsigned n) {
    return (n <= 1) ? 0 : 1 + ceil_log2((n + 1) / 2);
}
constexpr int ACC_BIT = COEF_BIT + IN_BIT + ceil_log2(N);

typedef ap_int<COEF_BIT> coef_t;     // Filter coefficients
typedef ap_uint<IN_BIT>  in_data_t;  // Input data
typedef ap_int<ACC_BIT>  acc_t;      // Accumulator MAC
typedef ap_int<OUT_BIT>  out_data_t; // Output data

/**
 * Baseline FIR Filter implementation.
 *
 * @param y Pointer to the output data.
 * @param x The current input data sample.
 */
void fir(out_data_t *y, in_data_t x);
