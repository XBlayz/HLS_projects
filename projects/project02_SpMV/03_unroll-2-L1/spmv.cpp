#include "spmv.hpp"

void spmv(
    const mtx_data_t values[NNZ], const vec_data_t x[NCOLS],
    const int col_idx[NNZ], const int row_ptr[NROWS + 1],
    out_data_t y[NROWS]
) {
    // Iterate over rows
    L1: for (int row = 0; row < NROWS; row++) {
        //* OPTIMIZATION(Unroll-2): partial unroll (factor 2) of SpMV operation
        #pragma HLS unroll factor=2

        out_data_t sum = 0.0f;

        // Iterate over non-zero elements
        L2: for (int idx = row_ptr[row]; idx < row_ptr[row + 1]; idx++) {
            //* MIN: at lest 1 non-zero element
            //* MAX: 128 non-zero elements (entire row)
            //* AVG: 4 non-zero elements (typically 512 non-zero elements i total, 512/128 = 4 per row)
            #pragma HLS loop_tripcount min=1 max=128 avg=4

            // --- MAC ---
            sum += values[idx] * x[col_idx[idx]];
        }

        y[row] = sum;
    }
}
