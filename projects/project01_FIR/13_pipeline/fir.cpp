#include "fir.hpp"

#include <ap_shift_reg.h>

void fir(out_data_t *y, in_data_t x) {
    #pragma HLS pipeline II=1 //* OPTIMIZATION(pipeline): executing FIR in pipeline

    // Constant coefficients array for the impulse response
    const coef_t c[N] = {53, 0, -91, 0, 313, 500, 313, 0, -91, 0, 53};

    //* OPTIMIZATION(ap_shift_reg): use ap_shift_reg instead of static array
    static ap_shift_reg<in_data_t, N> shift_reg;

    acc_t acc = 0;

    // --- Shift REG ---
    shift_reg.shift(x);

    // Sequential MAC (Multiply-Accumulate) operations
    mac_loop: for (int i = 0; i < N; i++) {
        // --- MAC ---
        acc += shift_reg.read(i) * c[i]; // Perform MAC on the i-th element
    }

    //! ATTENTION: OPTIMIZATION(code-hoisting) no longer present

    *y = acc;
}
