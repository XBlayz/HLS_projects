#pragma once

#define N 11 // Filter dimension

typedef int coef_t; // Filter coefficients
typedef int data_t; // Input and output data
typedef int acc_t;  // Accumulator MAC

/**
 * Baseline FIR Filter implementation.
 *
 * @param y Pointer to the output data.
 * @param x The current input data sample.
 */
void fir(data_t *y, data_t x);
