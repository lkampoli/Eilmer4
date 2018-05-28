#!/usr/bin/tclsh
# Testing of the nm pacakge.
#
# RJG & PJ, 2015-10-24
#

package require tcltest 2.0
namespace import ::tcltest::*
configure -verbose {pass start body error}

set module_names [list bbla bbla_complex \
                      bracketing bracketing_complex \
                      gaussquad gaussquad_complex \
                      linesearch linesearch_complex \
                      newtoncotes newtoncotes_complex \
		      ridder ridder_complex \
                      brent brent_complex \
                      rungekutta rungekutta_complex \
                      rsla rsla_complex \
                      smla smla_complex]  

foreach name $module_names {
    test ${name}_test "Testing $name.d" \
	-body "exec [join [list ./ $name _test] {}]" \
	-result {} -returnCodes {0}
}

# test bbla-test {Testing bbla.d} -body {
#     exec ./bbla_test
# } -result {} -returnCodes {0}

puts ""
puts "=======================================  SUMMARY  ======================================="
cleanupTests
puts "========================================================================================="

