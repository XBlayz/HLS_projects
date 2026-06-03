#include "fir.hpp"

void fir(out_data_t *y, in_data_t x) {
    // Constant coefficients array for the impulse response
    const coef_t c[N] = {53, 0, -91, 0, 313, 500, 313, 0, -91, 0, 53};

    // Static shift register maintains data persistence across multiple function calls
    static in_data_t shift_reg[N] = {0}; // Initialize with zeros
    #pragma HLS array_partition variable=shift_reg //* OPTIMIZATION(array-partition): partitioning the shift register array completely

    acc_t acc = 0;

    //* OPTIMIZATION(loop-fission): loop separation for the shift and MAC operations
    // --- Shift REG ---
    shift_loop: for (int i = N-1; i > 0; i--) {
        #pragma HLS unroll //* OPTIMIZATION(unroll): unrolling the shift loop

        shift_reg[i] = shift_reg[i - 1]; // Shift i-1 element to the right (drop the last element)
    }
    //* OPTIMIZATION(code-hoisting): removed conditional check in the loop
    shift_reg[0] = x; // Insert the new data sample at the beginning

    // --- MAC ---
    mac_loop: for (int i = 0; i < N; i++) {
        acc += shift_reg[i] * c[i]; // Perform MAC on the i-th element
    }

    *y = acc;
}
