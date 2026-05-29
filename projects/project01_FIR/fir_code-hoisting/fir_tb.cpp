#include <iostream>
#include <iomanip>
#include <string>

#include "fir.hpp"

#define N_SAMPLES 30 // Number of simulation cycles

/**
 * Software reference model (Golden Model) for the FIR filter.
 * Used to compute the expected results and verify the hardware implementation.
 */
void golden_fir(data_t *y, data_t x) {
    // Constant coefficients array for the impulse response
    const coef_t c[N] = {53, 0, -91, 0, 313, 500, 313, 0, -91, 0, 53};

    // Static shift register maintains data persistence across multiple function calls
    static data_t shift_reg[N] = {0}; // Initialize with zeros

    acc_t acc = 0;

    // Sequential shift and MAC (Multiply-Accumulate) operations
    for (int i = N-1; i >= 0; i--) {
        // --- Shift REG ---
        if (i == 0) {
            shift_reg[0] = x; // Insert the new data sample at the beginning
        } else {
            shift_reg[i] = shift_reg[i - 1]; // Shift i-1 element to the right (drop the last element)
        }

        // --- MAC ---
        acc += shift_reg[i] * c[i]; // Perform MAC on the i-th element
    }

    *y = acc;
}

int main() {
    data_t hw_result = 0;
    data_t sw_result = 0;
    data_t stimulus  = 0;
    
    int error_cnt = 0;

    std::cout << "==============================================================\n";
    std::cout << "                 FIR FILTER HLS TESTBENCH                     \n";
    std::cout << "==============================================================\n";
    std::cout << std::left 
              << std::setw(10) << "CYCLE" 
              << std::setw(15) << "INPUT (x)" 
              << std::setw(15) << "DUT OUT (y)" 
              << std::setw(15) << "GOLDEN OUT" 
              << std::setw(10) << "STATUS" << "\n";
    std::cout << "--------------------------------------------------------------\n";

    // Simulation loop
    for (int i = 0; i < N_SAMPLES; i++) {
        
        // Stimulus generation: Impulse at t=0, followed by a second pulse at t=15
        if (i == 0) {
            stimulus = 1;
        } else if (i == 15) {
            stimulus = 2;
        } else {
            stimulus = 0;
        }

        // Execute Device Under Test (Hardware IP)
        fir(&hw_result, stimulus);

        // Execute Golden Model (Software Reference)
        golden_fir(&sw_result, stimulus);

        // Result verification
        bool is_match = (hw_result == sw_result);
        if (!is_match) {
            error_cnt++;
        }

        // Terminal logging
        std::cout << std::left 
                  << std::setw(10) << i 
                  << std::setw(15) << stimulus 
                  << std::setw(15) << hw_result 
                  << std::setw(15) << sw_result 
                  << std::setw(10) << (is_match ? "PASS" : "FAIL") << "\n";
    }

    std::cout << "--------------------------------------------------------------\n";

    // Vitis HLS requires a return value of 0 for a successful C Simulation
    if (error_cnt == 0) {
        std::cout << ">> SIMULATION STATUS: PASSED\n";
        std::cout << "==============================================================\n";
        return 0;
    } else {
        std::cout << ">> SIMULATION STATUS: FAILED\n";
        std::cout << ">> Total mismatched samples: " << error_cnt << "\n";
        std::cout << "==============================================================\n";
        return 1;
    }
}
