#include "spmv.hpp"

#define F 2 // Unroll factor

void spmv(
    const mtx_data_t values[NNZ], const vec_data_t x[NCOLS],
    const int col_idx[NNZ], const int row_ptr[NROWS + 1],
    out_data_t y[NROWS]
) {
    //* OPTIMIZATION(Cyclic-2): cyclic partitioning and complete partitioning
    #pragma HLS array_partition variable=values type=cyclic factor=F
    #pragma HLS array_partition variable=col_idx type=cyclic factor=F
    #pragma HLS array_partition variable=x type=complete // Need to be complete because we can't predict witch location will be used

    // Iterate over rows
    L1: for (int row = 0; row < NROWS; row++) {
        out_data_t sum = 0.0f;

        // Iterate over non-zero elements
        L2: for (int idx = row_ptr[row]; idx < row_ptr[row + 1]; idx++) {
            //* MIN: at lest 1 non-zero element
            //* MAX: 128 non-zero elements (entire row)
            //* AVG: 4 non-zero elements (typically 512 non-zero elements i total, 512/128 = 4 per row)
            #pragma HLS loop_tripcount min=1 max=128 avg=4
            //* OPTIMIZATION(Pipeline): running MAC in pipeline
            #pragma HLS pipeline II=1
            //* OPTIMIZATION(Unroll-2): partial unroll of MAC operation
            #pragma HLS unroll factor=F*2

            // --- MAC ---
            sum += values[idx] * x[col_idx[idx]];
        }

        y[row] = sum;
    }
}
