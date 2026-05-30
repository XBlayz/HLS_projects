#==============================================================================
# run_vivado_power.tcl
# Post-synthesis OOC power analysis for an HLS-generated IP.
# Vivado 2025.2
#
# Workflow (vivado_workflows.md):
#   Step 1  - Create project
#   Step 2  - Import IP repository
#   Step 3  - Instantiate IP and generate targets
#   Step 4  - Run IP OOC synthesis  (${IP_NAME}_synth_1)
#   Step 5  - Generate IP RTL wrapper
#   Step 6  - Import clock constraint
#   Step 7  - Import testbench
#   Step 8  - Run top-level synthesis (synth_1)
#   Step 9  - Post-synthesis timing simulation + SAIF
#   Step 10 - Power report  (OOC netlist + SAIF annotation)
#
# Usage (called by workflow.bat via -tclargs):
#   vivado -mode batch -source scripts/run_vivado_power.tcl \
#          -tclargs <COMP_VERSION> <COMP_NAME>
#
#   PROJECT_NAME    : name of the project directory        (e.g., project01_FIR)
#   COMP_VERSION    : name of the HLS component directory  (e.g., fir_baseline)
#   COMP_NAME       : name of the top-level HLS function   (e.g., fir)
#   TB_FILE_NAME    : name of the testbench file           (Default: ${PROJECT_NAME}_${COMP_NAME}_tb)
#   CLOCK_FILE_NAME : name of the clock constraint file    (Default: ${PROJECT_NAME}_${COMP_NAME}_clk)
#   SIM_TIME        : co-simulation duration               (Default: 1000ns)
#==============================================================================


#------------------------------------------------------------------------------
# Arguments received from workflow.bat via -tclargs
#------------------------------------------------------------------------------
if {[llength $argv] < 6} {
    puts "\[FAIL \] Arguments missing."
    puts "\[FAIL \] Usage: vivado ... -tclargs <COMP_VERSION> <COMP_NAME>"
    exit 1
}

set PROJECT_NAME    [lindex $argv 0]   ;# e.g., project01_FIR
set COMP_VERSION    [lindex $argv 1]   ;# e.g., fir_baseline
set COMP_NAME       [lindex $argv 2]   ;# e.g., fir
set TB_FILE_NAME    [lindex $argv 3]   ;# Default: ${PROJECT_NAME}_${COMP_NAME}_tb"
set CLOCK_FILE_NAME [lindex $argv 4]   ;# Default: ${PROJECT_NAME}_${COMP_NAME}_clk"
set SIM_RUNTIME     [lindex $argv 5]   ;# Default: 1000ns

# Derived names by convention (modify if naming convention differs)
set TOP_MODULE  $COMP_NAME
set IP_NAME     "${COMP_NAME}_0"
set TB_MODULE   "${COMP_NAME}_tb"


#------------------------------------------------------------------------------
# Vivado configuration -- Modify for each project
#------------------------------------------------------------------------------
set PART       "xc7z020clg484-3"

set IP_VENDOR  "xilinx.com"
set IP_LIBRARY "hls"
set IP_VERSION "1.0"

set NUM_JOBS     8


#------------------------------------------------------------------------------
# Derived paths -- Do not modify
#
# Vivado CWD = project root (e.g., projects/project01_FIR/)
#   build/
#     <COMP_VERSION>/
#       ip_repo/          <- IP extracted by workflow.bat
#       vivado_prj/       <- Vivado project created below
#       reports/          <- power report
#   src/
#     vivado/
#       <COMP_NAME>_tb.vhd
#       const/clk.xdc
#------------------------------------------------------------------------------
set PRJ_NAME   "vivado_prj"
set BUILD_DIR  "."
set PRJ_DIR    "${BUILD_DIR}/${PRJ_NAME}"
set IP_REPO_DIR "${BUILD_DIR}/ip_repo"
set TB_FILE    "../../../srcs/vivado/${TB_FILE_NAME}.vhd"
set CLOCK_FILE "../../../srcs/vivado/const/${CLOCK_FILE_NAME}.xdc"
set REPORT_DIR "../../../reports/${PROJECT_NAME}"

# Paths internal to the Vivado project (automatically derived)
set IP_SYNTH_RUN      "${IP_NAME}_synth_1"
set XCI_FILE          "${PRJ_DIR}/${PRJ_NAME}.srcs/sources_1/ip/${IP_NAME}/${IP_NAME}.xci"
set SAIF_XSIM         "dump.saif"
set SAIF_FILE         "${PRJ_DIR}/${PRJ_NAME}.sim/sim_1/synth/timing/xsim/${SAIF_XSIM}"
set POWER_REPORT_DIR  "${REPORT_DIR}/${COMP_VERSION}/vivado/power"
set POWER_REPORT_FILE "${POWER_REPORT_DIR}/${COMP_NAME}_post-synth_power_report"


#------------------------------------------------------------------------------
# Helper procedures
#------------------------------------------------------------------------------

proc print_section {n title} {
    puts ""
    puts "========================================================"
    puts " STEP $n -- $title"
    puts "========================================================"
}

proc print_ok   {msg} { puts "\[ OK  \] $msg" }
proc print_info {msg} { puts "\[INFO \] $msg" }
proc print_warn {msg} { puts "\[WARN \] $msg" }
proc print_fail {msg} { puts "\[FAIL \] $msg" }

# Asserts that a Vivado run completed with 100% progress.
proc assert_run_ok {run_name} {
    set progress [get_property PROGRESS [get_runs $run_name]]
    set status   [get_property STATUS   [get_runs $run_name]]
    if {$progress ne "100%"} {
        print_fail "Run '$run_name' did not complete -- STATUS: $status  PROGRESS: $progress"
        error "Run '$run_name' failed"
    }
    print_ok "Run '$run_name' -- $status"
}

# Asserts that a required file or directory exists.
proc assert_exists {path label} {
    if {![file exists $path]} {
        print_fail "$label not found: $path"
        error "Required path missing: $path"
    }
    print_ok "$label: $path"
}


#------------------------------------------------------------------------------
# Initial banner
#------------------------------------------------------------------------------
puts ""
puts "========================================================"
puts " TARGET: $COMP_VERSION  ($COMP_NAME)"
puts " PART  : $PART"
puts " BUILD : $BUILD_DIR"
puts "========================================================"


#------------------------------------------------------------------------------
# Step 1 -- Create project
#------------------------------------------------------------------------------
print_section 1 "Create project"

file mkdir $PRJ_DIR
create_project $PRJ_NAME $PRJ_DIR -part $PART -force

set_property target_language    VHDL  [current_project]
set_property simulator_language Mixed [current_project]

print_ok "Project '$PRJ_NAME' created -- PART: $PART"


#------------------------------------------------------------------------------
# Step 2 -- Import IP repository
#------------------------------------------------------------------------------
print_section 2 "Import IP repository"

set abs_ip_repo [file normalize $IP_REPO_DIR]
assert_exists $abs_ip_repo "IP repository directory"

set_property ip_repo_paths $abs_ip_repo [current_project]
update_ip_catalog -rebuild

print_ok "IP catalog updated -- repo: $IP_REPO_DIR"


#------------------------------------------------------------------------------
# Step 3 -- Instantiate IP and generate targets
#------------------------------------------------------------------------------
print_section 3 "Instantiate IP and generate targets"

print_info "Creating IP: ${IP_VENDOR}:${IP_LIBRARY}:${TOP_MODULE}:${IP_VERSION} -> $IP_NAME"

create_ip \
    -name        $TOP_MODULE \
    -vendor      $IP_VENDOR  \
    -library     $IP_LIBRARY \
    -version     $IP_VERSION \
    -module_name $IP_NAME

set XCI_FILE [file normalize $XCI_FILE]

generate_target {instantiation_template} [get_files $XCI_FILE]
update_compile_order -fileset sources_1

generate_target all [get_files $XCI_FILE]
catch { config_ip_cache -export [get_ips -all $IP_NAME] }
export_ip_user_files \
    -of_objects [get_files $XCI_FILE] \
    -no_script -sync -force -quiet

assert_exists $XCI_FILE "XCI file"
print_ok "IP '$IP_NAME' instantiated and all targets generated"


#------------------------------------------------------------------------------
# Step 4 -- IP OOC synthesis
#------------------------------------------------------------------------------
print_section 4 "IP OOC synthesis  ($IP_SYNTH_RUN)"

create_ip_run [get_files -of_objects [get_fileset sources_1] $XCI_FILE]

print_info "Launching $IP_SYNTH_RUN ($NUM_JOBS jobs)..."

launch_runs $IP_SYNTH_RUN -jobs $NUM_JOBS
wait_on_run $IP_SYNTH_RUN

assert_run_ok $IP_SYNTH_RUN


#------------------------------------------------------------------------------
# Step 5 -- Generate IP RTL wrapper
#------------------------------------------------------------------------------
print_section 5 "Generate IP RTL wrapper"

make_wrapper \
    -files    [get_files $XCI_FILE] \
    -language SystemVerilog \
    -add

update_compile_order -fileset sources_1

set wrapper_top [get_property TOP [get_filesets sources_1]]
print_ok "Wrapper generated -- synthesis top: '$wrapper_top'"


#------------------------------------------------------------------------------
# Step 6 -- Import clock constraint
#------------------------------------------------------------------------------
print_section 6 "Import clock constraint"

assert_exists $CLOCK_FILE "Clock constraint file"

add_files -fileset constrs_1 -norecurse $CLOCK_FILE

print_ok "Constraint added: $CLOCK_FILE"


#------------------------------------------------------------------------------
# Step 7 -- Import testbench
#------------------------------------------------------------------------------
print_section 7 "Import testbench"

assert_exists $TB_FILE "Testbench file"

set_property SOURCE_SET sources_1 [get_filesets sim_1]
add_files -fileset sim_1 -norecurse $TB_FILE

set_property top     $TB_MODULE     [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

print_ok "Testbench '$TB_MODULE' added to sim_1"


#------------------------------------------------------------------------------
# Step 8 -- Top-level synthesis
#------------------------------------------------------------------------------
print_section 8 "Top-level synthesis  (synth_1)"

print_info "Launching synth_1 ($NUM_JOBS jobs)..."

launch_runs synth_1 -jobs $NUM_JOBS
wait_on_run synth_1

assert_run_ok synth_1


#------------------------------------------------------------------------------
# Step 9 -- Post-synthesis timing simulation + SAIF
#------------------------------------------------------------------------------
print_section 9 "Post-synthesis timing simulation + SAIF"

print_info "Simulation runtime : $SIM_RUNTIME"
print_info "SAIF output        : $SAIF_FILE"

set_property -name {xsim.simulate.runtime}          -value $SIM_RUNTIME -objects [get_filesets sim_1]
set_property -name {xsim.simulate.saif}             -value $SAIF_XSIM   -objects [get_filesets sim_1]
set_property -name {xsim.simulate.saif_all_signals} -value {true}       -objects [get_filesets sim_1]

print_info "Launching post-synthesis timing simulation..."

launch_simulation -mode post-synthesis -type timing

# Verify SAIF was produced before proceeding
assert_exists $SAIF_FILE "SAIF file"
print_ok "SAIF written to: $SAIF_FILE"


#------------------------------------------------------------------------------
# Step 10 -- Power report
#------------------------------------------------------------------------------
print_section 10 "Power report  (OOC netlist + SAIF annotation)"

file mkdir $POWER_REPORT_DIR

# Open OOC synthesis results (not the top-level synth or impl)
open_run $IP_SYNTH_RUN

# Load output capacitance and annotate switching activity from SAIF.
# If scope matching fails, try: read_saif <path> -scope fir_tb/uut_inst
set_load 5 [all_outputs]
read_saif [file normalize $SAIF_FILE]

print_ok "SAIF annotation loaded"

report_power \
    -name     ${IP_NAME}_power_1 \
    -file     "${POWER_REPORT_FILE}.txt" \
    -format   text \
    -hier     all \
    -xpe      "${POWER_REPORT_FILE}.xml" \
    -rpx      "${POWER_REPORT_FILE}.rpx"

assert_exists "${POWER_REPORT_FILE}.txt" "Text-Power report"
print_ok "Text-Power report written to: ${POWER_REPORT_FILE}.txt"

assert_exists "${POWER_REPORT_FILE}.xml" "XML-Power report"
print_ok "XML-Power report written to: ${POWER_REPORT_FILE}.xml"

assert_exists "${POWER_REPORT_FILE}.rpx" "RPX-Power report"
print_ok "RPX-Power report written to: ${POWER_REPORT_FILE}.rpx"


#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
puts ""
puts "========================================================"
puts " VIVADO WORKFLOW COMPLETED SUCCESSFULLY"
puts " Target : $COMP_VERSION  ($COMP_NAME)"
puts " Report : $POWER_REPORT_FILE"
puts "========================================================"
puts ""
