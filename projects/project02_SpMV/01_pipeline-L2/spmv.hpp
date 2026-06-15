#pragma once

#include <ap_int.h>

// --- CIRCUIT PARAMETERS ---
#define NROWS 128 // Number of rows of the matrix
#define NCOLS 128 // Number of columns of the matrix
#define NNZ   512 // Number of non-zero elements

// --- USER DEFINED DATA DIMENSIONS ---
#define VEC_BIT 10 // Number of bits for vector data
#define MTX_BIT 8  // Number of bits for matrix data
#define OUT_BIT 32 // Number of bits for output data

typedef ap_int<VEC_BIT>  vec_data_t; // Vector data
typedef ap_int<MTX_BIT>  mtx_data_t; // Matrix data
typedef ap_int<OUT_BIT>  out_data_t; // Output data

/**
 * SpMV implementation.
 *
 * @param values Array of matrix data.
 * @param x Array of vector data.
 * @param col_idx Array of column indices.
 * @param row_ptr Array of row pointers.
 * @param y Array of output data.
 */
void spmv(
    const mtx_data_t values[NNZ], const vec_data_t x[NCOLS],
    const int col_idx[NNZ], const int row_ptr[NROWS + 1],
    out_data_t y[NROWS]
);
