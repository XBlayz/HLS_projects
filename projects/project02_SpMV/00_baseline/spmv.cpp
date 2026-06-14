#include "spmv.hpp"

void spmv(
    const mtx_data_t values[NNZ], const vec_data_t x[NCOLS],
    const int col_idx[NNZ], const int row_ptr[NROWS + 1],
    out_data_t y[NROWS]
) {
    // Iterate over rows
    L1: for (int row = 0; row < NROWS; row++) {
        out_data_t sum = 0.0f;

        // Iterate over non-zero elements
        L2: for (int idx = row_ptr[row]; idx < row_ptr[row + 1]; idx++) {
            // --- MAC ---
            sum += values[idx] * x[col_idx[idx]];
        }

        y[row] = sum;
    }
}
