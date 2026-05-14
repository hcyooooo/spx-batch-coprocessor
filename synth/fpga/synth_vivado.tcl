set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ../..]]

set top "spx_thashx4_core"
set part "xc7a35tcpg236-1"
set clock_period_ns 10.0
set mem_words_per_cycle ""

if {$argc >= 1} {
  set top [lindex $argv 0]
}
if {$argc >= 2} {
  set part [lindex $argv 1]
}
if {$argc >= 3} {
  set clock_period_ns [lindex $argv 2]
}
if {$argc >= 4} {
  set mem_words_per_cycle [lindex $argv 3]
}

set build_name $top
set synth_generics [list]
if {$top eq "spx_descriptor_adapter"} {
  if {$mem_words_per_cycle eq ""} {
    set mem_words_per_cycle 1
  }
  if {![regexp {^(1|2|4)$} $mem_words_per_cycle]} {
    error "MEM_WORDS_PER_CYCLE must be one of 1, 2, or 4; got '$mem_words_per_cycle'"
  }
  set build_name "${top}_${mem_words_per_cycle}w"
  lappend synth_generics "MEM_WORDS_PER_CYCLE=$mem_words_per_cycle"
} elseif {$mem_words_per_cycle ne ""} {
  puts "WARNING: Ignoring MEM_WORDS_PER_CYCLE=$mem_words_per_cycle for top=$top"
}

set build_dir [file normalize [file join $script_dir build $build_name]]
set report_dir [file join $build_dir reports]
file mkdir $build_dir
file mkdir $report_dir
set xdc_file [file join $build_dir clock.xdc]
set synth_utilization_report [file join $report_dir synth_utilization.rpt]
set synth_utilization_hier_report [file join $report_dir synth_utilization_hier.rpt]
set utilization_report [file join $report_dir utilization.rpt]
set utilization_hier_report [file join $report_dir utilization_hier.rpt]
set timing_summary_report [file join $report_dir timing_summary.rpt]
set clock_utilization_report [file join $report_dir clock_utilization.rpt]

proc parse_util_metric {report_path label} {
  set fp [open $report_path "r"]
  set text [read $fp]
  close $fp

  set suffix_re ""
  if {[string index $label end] eq "*"} {
    set label [string range $label 0 end-1]
    set suffix_re "\\*?"
  }
  set label_re [string map {\\ \\\\ * \\*} $label]
  set pattern [format {\|\s*%s%s\s*\|\s*([0-9.]+)\s*\|} $label_re $suffix_re]
  foreach line [split $text "\n"] {
    if {[regexp $pattern $line -> value]} {
      return $value
    }
  }
  return "unavailable"
}

set rtl_files [list \
  [file join $repo_root rtl common spx_thashx4_pkg.sv] \
  [file join $repo_root rtl core spx_keccak_round.sv] \
  [file join $repo_root rtl core spx_keccakx4_core.sv] \
  [file join $repo_root rtl core spx_thashx4_core.sv] \
]
if {$top in {"spx_cop_wrapper" "spx_cvxif_adapter" "spx_cvxif_adapter_coarse"}} {
  lappend rtl_files [file join $repo_root rtl wrapper spx_cop_wrapper.sv]
}
if {$top eq "spx_cvxif_adapter"} {
  lappend rtl_files [file join $repo_root rtl cvxif spx_cvxif_adapter.sv]
}
if {$top eq "spx_cvxif_adapter_coarse"} {
  lappend rtl_files [file join $repo_root rtl cvxif spx_cvxif_adapter_coarse.sv]
}
if {$top in {"spx_wots_chainx4_core" "spx_descriptor_adapter"}} {
  lappend rtl_files [file join $repo_root rtl core spx_wots_chainx4_core.sv]
}
if {$top eq "spx_descriptor_adapter"} {
  lappend rtl_files [file join $repo_root rtl cvxif spx_descriptor_adapter.sv]
}

puts "INFO: Synthesizing standalone accelerator top=$top part=$part clock=${clock_period_ns}ns"
if {[llength $synth_generics] > 0} {
  puts "INFO: Synthesis generics: $synth_generics"
}
puts "INFO: Vivado flow mode: out_of_context accelerator-only implementation"
puts "INFO: Repository root: $repo_root"
puts "INFO: Build directory: $build_dir"

set xdc_fp [open $xdc_file "w"]
puts $xdc_fp "create_clock -name clk -period $clock_period_ns \[get_ports clk\]"
close $xdc_fp

read_verilog -sv $rtl_files
read_xdc $xdc_file
if {[llength $synth_generics] > 0} {
  synth_design -top $top -part $part -flatten_hierarchy rebuilt \
    -mode out_of_context -generic $synth_generics
} else {
  synth_design -top $top -part $part -flatten_hierarchy rebuilt -mode out_of_context
}

report_utilization -file $synth_utilization_report
report_utilization -hierarchical -file $synth_utilization_hier_report

opt_design

report_utilization -hierarchical -file $utilization_hier_report
report_utilization -file $utilization_report

place_design
route_design

report_utilization -hierarchical -file $utilization_hier_report
report_utilization -file $utilization_report
report_timing_summary -delay_type max -report_unconstrained -check_timing_verbose \
  -file $timing_summary_report
report_clock_utilization -file $clock_utilization_report

set summary_file [open [file join $report_dir ppa_summary.txt] "w"]
puts $summary_file "top: $top"
if {$top eq "spx_descriptor_adapter"} {
  puts $summary_file "mem_words_per_cycle: $mem_words_per_cycle"
}
puts $summary_file "part: $part"
puts $summary_file "clock_period_ns: $clock_period_ns"
puts $summary_file "lut: [parse_util_metric $utilization_report {Slice LUTs*}]"
puts $summary_file "ff: [parse_util_metric $utilization_report {Slice Registers}]"
puts $summary_file "bram: [parse_util_metric $utilization_report {Block RAM Tile}]"
puts $summary_file "dsp: [parse_util_metric $utilization_report {DSPs}]"

set timing_paths [get_timing_paths -quiet -max_paths 1 -nworst 1 -setup]
if {[llength $timing_paths] > 0} {
  set wns [get_property SLACK [lindex $timing_paths 0]]
  set critical_delay_ns [expr {$clock_period_ns - $wns}]
  puts $summary_file "wns_ns: $wns"
  if {$wns >= 0.0} {
    puts $summary_file "timing_met: yes"
  } else {
    puts $summary_file "timing_met: no"
  }
  puts $summary_file "critical_delay_ns: $critical_delay_ns"
  if {$critical_delay_ns > 0.0} {
    set fmax_mhz [expr {1000.0 / $critical_delay_ns}]
    puts $summary_file [format "estimated_fmax_mhz: %.2f" $fmax_mhz]
  } else {
    puts $summary_file "estimated_fmax_mhz: unavailable"
  }
} else {
  puts $summary_file "wns_ns: unavailable"
  puts $summary_file "timing_met: unavailable"
  puts $summary_file "critical_delay_ns: unavailable"
  puts $summary_file "estimated_fmax_mhz: unavailable"
}
puts $summary_file "synth_utilization_report: $synth_utilization_report"
puts $summary_file "synth_utilization_hier_report: $synth_utilization_hier_report"
puts $summary_file "utilization_report: $utilization_report"
puts $summary_file "utilization_hier_report: $utilization_hier_report"
puts $summary_file "timing_report: $timing_summary_report"
close $summary_file

write_checkpoint -force [file join $build_dir ${build_name}_routed.dcp]
puts "INFO: Reports written under $report_dir"
