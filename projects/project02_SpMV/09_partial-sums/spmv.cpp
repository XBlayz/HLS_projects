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
        out_data_t partial_sums[F*2] = {0};
        #pragma HLS array_partition variable=partial_sums type=complete

        int start = row_ptr[row];
        int end = row_ptr[row + 1];

        // Iterate over non-zero elements
        L2_1: for (int k = start; k < end; k += F*2) {
            //* MIN: at lest 1 non-zero element
            //* MAX: 128 non-zero elements (entire row)
            //* AVG: 4 non-zero elements (typically 512 non-zero elements i total, 512/128 = 4 per row)
            #pragma HLS loop_tripcount min=1 max=128 avg=4
            //* OPTIMIZATION(Pipeline): running MAC in pipeline
            #pragma HLS pipeline II=1

            L2_2: for (int i = 0; i < F*2; i++) {
                //* OPTIMIZATION(Unroll): partial unroll of MAC operation with partial sum
                #pragma HLS unroll

                int idx = k + i;

                // --- MAC ---
                //! Check if idx is within bounds (row not always multiple of F)
                if (idx < end) {
                    partial_sums[i] += values[idx] * x[col_idx[idx]];
                }
            }
        }

        // --- Add ---
        partial_sum: for (int i=0; i < F*2; i++) {
            #pragma HLS unroll
            sum += partial_sums[i];
        }

        y[row] = sum;
    }
}
