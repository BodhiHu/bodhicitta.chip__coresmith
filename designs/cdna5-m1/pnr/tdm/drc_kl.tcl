gds read pnr/tdm/tdm_klayout.gds
load tdm
select top cell
flatten tdm_flat
load tdm_flat
select top cell
drc catchup
set n [drc listall count total]
set rpt [open "pnr/tdm/magic_drc.rpt" w]
puts $rpt "Design: tdm"
puts $rpt "DRC count: $n"
puts $rpt [drc listall why]
close $rpt
puts "DRC violations: $n"
quit -noprompt
