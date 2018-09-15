#!/bin/bash

e4shared --job=inf_cyl --post --slice-list="0,:,0,0" \
         --add-vars="Tvib" \
         --output-file=stag-prof-50Pa-vib-specific.data
gnuplot plot-prof.gplot
