#include "fir.hpp"

void fir(data_t *y, data_t x) {
    // Constant coefficients array for the impulse response
    const coef_t c[N] = {53, 0, -91, 0, 313, 500, 313, 0, -91, 0, 53};

    // Static shift register maintains data persistence across multiple function calls
    static data_t shift_reg[N] = {0}; // Initialize with zeros

    acc_t acc = 0;

    // Sequential shift and MAC (Multiply-Accumulate) operations
    fir_loop: for (int i = N-1; i > 0; i--) {
        // --- Shift REG ---
        shift_reg[i] = shift_reg[i - 1]; // Shift i-1 element to the right (drop the last element)

        // --- MAC ---
        acc += shift_reg[i] * c[i]; // Perform MAC on the i-th element
    }

    //* OPTIMIZATION(code-hoisting): removed conditional check in the loop
    // --- Shift REG ---
    shift_reg[0] = x; // Insert the new data sample at the beginning

    // --- MAC ---
    acc += shift_reg[0] * c[0]; // Perform MAC on the first element

    *y = acc;
}
