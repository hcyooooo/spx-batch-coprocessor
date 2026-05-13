set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ../..]]

set top "spx_thashx4_core"
set part "xc7a35tcpg236-1"
set clock_period_ns 10.0

if {$argc >= 1} {
  set top [lindex $argv 0]
}
if {$argc >= 2} {
  set part [lindex $argv 1]
}
if {$argc >= 3} {
  set clock_period_ns [lindex $argv 2]
}

set build_dir [file normalize [file join $script_dir build $top]]
set report_dir [file join $build_dir reports]
file mkdir $build_dir
file mkdir $report_dir
set xdc_file [file join $build_dir clock.xdc]

set rtl_files [list \
  [file join $repo_root rtl common spx_thashx4_pkg.sv] \
  [file join $repo_root rtl core spx_keccak_round.sv] \
  [file join $repo_root rtl core spx_keccakx4_core.sv] \
  [file join $repo_root rtl core spx_thashx4_core.sv] \
]

puts "INFO: Synthesizing standalone accelerator top=$top part=$part clock=${clock_period_ns}ns"
puts "INFO: Repository root: $repo_root"
puts "INFO: Build directory: $build_dir"

set xdc_fp [open $xdc_file "w"]
puts $xdc_fp "create_clock -name clk -period $clock_period_ns \[get_ports clk\]"
close $xdc_fp

read_verilog -sv $rtl_files
read_xdc $xdc_file
synth_design -top $top -part $part -flatten_hierarchy rebuilt

opt_design
place_design
route_design

report_utilization -hierarchical -file [file join $report_dir utilization_hier.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -report_unconstrained -check_timing_verbose \
  -file [file join $report_dir timing_summary.rpt]
report_clock_utilization -file [file join $report_dir clock_utilization.rpt]

set summary_file [open [file join $report_dir ppa_summary.txt] "w"]
puts $summary_file "top: $top"
puts $summary_file "part: $part"
puts $summary_file "clock_period_ns: $clock_period_ns"

set timing_paths [get_timing_paths -quiet -max_paths 1 -nworst 1 -setup]
if {[llength $timing_paths] > 0} {
  set wns [get_property SLACK [lindex $timing_paths 0]]
  set critical_delay_ns [expr {$clock_period_ns - $wns}]
  puts $summary_file "wns_ns: $wns"
  puts $summary_file "critical_delay_ns: $critical_delay_ns"
  if {$critical_delay_ns > 0.0} {
    set fmax_mhz [expr {1000.0 / $critical_delay_ns}]
    puts $summary_file [format "estimated_fmax_mhz: %.2f" $fmax_mhz]
  } else {
    puts $summary_file "estimated_fmax_mhz: unavailable"
  }
} else {
  puts $summary_file "wns_ns: unavailable"
  puts $summary_file "critical_delay_ns: unavailable"
  puts $summary_file "estimated_fmax_mhz: unavailable"
}
puts $summary_file "utilization_report: [file join $report_dir utilization.rpt]"
puts $summary_file "timing_report: [file join $report_dir timing_summary.rpt]"
close $summary_file

write_checkpoint -force [file join $build_dir ${top}_routed.dcp]
puts "INFO: Reports written under $report_dir"
