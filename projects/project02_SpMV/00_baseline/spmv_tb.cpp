#include <iostream>
#include <iomanip>
#include <cmath>

#include "spmv.hpp"

/**
 * Software reference model (Golden Model) for the SpMV.
 * Used to compute the expected results and verify the hardware implementation.
 */
void golden_mvm(
    const mtx_data_t values[NNZ], const vec_data_t x[NCOLS],
    const int col_idx[NNZ], const int row_ptr[NROWS + 1],
    out_data_t y[NROWS]
) {
    // Iterate over all rows (dense pattern)
    L1: for (int row = 0; row < NROWS; row++) {
        out_data_t sum = 0.0f;

        // Iterate over all columns (dense pattern)
        L2: for (int col = 0; col < NCOLS; col++) {
            mtx_data_t matrix_val = 0.0f;

            // Search for the specific column in the current CSR row
            for (int idx = row_ptr[row]; idx < row_ptr[row + 1]; idx++) {
                if (col_idx[idx] == col) {
                    matrix_val = values[idx];
                    break;
                }
            }

            // --- MAC ---
            sum += matrix_val * x[col];
        }

        y[row] = sum;
    }
}

int main() {
    mtx_data_t values[NNZ];
    vec_data_t x[NCOLS];

    int        col_idx[NNZ];
    int        row_ptr[NROWS + 1];

    out_data_t hw_y[NROWS];
    out_data_t sw_y[NROWS];

    //-----------------------------------------------------------------
    // Deterministic Vector Generation
    //-----------------------------------------------------------------
    for (int i = 0; i < NCOLS; i++) {
        x[i] = (vec_data_t)((i % 17) + 1);
    }

    //-----------------------------------------------------------------
    // Deterministic Sparse Matrix Generation (CRS)
    //-----------------------------------------------------------------
    const int nnz_per_row = NNZ / NROWS;

    int ptr = 0;

    row_ptr[0] = 0;
    for (int row = 0; row < NROWS; row++) {
        for (int k = 0; k < nnz_per_row; k++) {
            values[ptr] = (mtx_data_t)((ptr % 23) + 1);

            col_idx[ptr] = (row * 13 + k * 7) % NCOLS;

            ptr++;
        }

        row_ptr[row + 1] = ptr;
    }

    // Fill Remaining NNZ (if NNZ not divisible by NROWS)
    while (ptr < NNZ) {
        values[ptr] = (mtx_data_t)((ptr % 11) + 1);

        col_idx[ptr] = ptr % NCOLS;

        ptr++;

        row_ptr[NROWS] = ptr;
    }

    //-----------------------------------------------------------------
    // DUT
    //-----------------------------------------------------------------
    spmv(values, x, col_idx, row_ptr, hw_y);

    //-----------------------------------------------------------------
    // Reference
    //-----------------------------------------------------------------
    golden_mvm(values, x, col_idx, row_ptr, sw_y);

    //-----------------------------------------------------------------
    // Verification
    //-----------------------------------------------------------------
    std::cout << "==============================================================\n";
    std::cout << "                    SPMV TESTBENCH                            \n";
    std::cout << "==============================================================\n";
    std::cout << "Rows : " << NROWS << "\n";
    std::cout << "Cols : " << NCOLS << "\n";
    std::cout << "NNZ  : " << NNZ   << "\n";
    std::cout << "==============================================================\n";
    std::cout << std::left
              << std::setw(10) << "ROW"
              << std::setw(18) << "DUT"
              << std::setw(18) << "REFERENCE"
              << std::setw(10) << "STATUS"
              << "\n";
    std::cout << "--------------------------------------------------------------\n";

    // Result verification
    int error_cnt = 0;
    for (int row = 0; row < NROWS; row++) {
        bool is_match = (hw_y[row] == sw_y[row]);
        if (!is_match) {
            error_cnt++;
        }

        std::cout << std::left
                  << std::setw(10) << row
                  << std::setw(18) << hw_y[row]
                  << std::setw(18) << sw_y[row]
                  << std::setw(10) << (is_match ? "PASS" : "FAIL")
                  << "\n";
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
