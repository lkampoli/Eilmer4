# makefile for the Numerical Methods package
#
# We can specify the LDC2 compiler as DMD=ldmd2 on the command-line
# when invoking this makefile.  Can also ask for gdc.
DMD ?= dmd
PLATFORM ?= linux

UTIL_DIR := ../util
include $(UTIL_DIR)/util_files.mk

include nm_files.mk

DEMO_PROGRAMS := ridder_demo \
	linesearch_demo \
	nelmin_demo nelmin_complex_demo \
	rungekutta_demo \
	newtoncotes_demo \
	gaussquad_demo \
	bbla_demo 

TEST_PROGRAMS := bbla_test bbla_complex_test \
	bracketing_test bracketing_complex_test \
	gaussquad_test gaussquad_complex_test \
	linesearch_test linesearch_complex_test \
	newtoncotes_test newtoncotes_complex_test \
	ridder_test ridder_complex_test \
	brent_test brent_complex_test \
	rungekutta_test rungekutta_complex_test \
	smla_test smla_complex_test \
	rsla_test rsla_complex_test \
	luabbla_test complex_number_test \
	newton_test newton_complex_test

LUA := ../../extern/lua-5.1.4
LIBLUA := $(LUA)/lib/liblua.a
LIBLUAPATH := $(LUA)/lib
ifeq ($(DMD), dmd)
    # DFLAGS := -w
    DFLAGS := -w -O -release -inline -boundscheck=off
    OF := -of
    DLINKFLAGS := -L-L$(LIBLUAPATH) -L-llua -L-ldl
endif
ifeq ($(DMD), ldmd2)
    DFLAGS := -w -O -release -inline -boundscheck=off
    OF := -of
    DLINKFLAGS := -L-L$(LIBLUAPATH) -L-llua -L-ldl
endif
ifeq ($(DMD), gdc)
    DFLAGS := -Wall -O2 -frelease -fno-debug
    OF := -o
    DLINKFLAGS := -L$(LIBLUAPATH) $(LIBLUA) -ldl
endif

# ----------------------------------------------------------------------
# Here begins the list of targets, starting with the top-level actions.
#
# The default target is test, because that is most likely your interest
# if you are invoking this makefile from within the gas models directory.
# ----------------------------------------------------------------------

test: ${TEST_PROGRAMS}
	tclsh nm-package-test.tcl

demo: ${DEMO_PROGRAMS}
	echo "Demo codes built."

clean:
	- rm *.o
	- rm ${DEMO_PROGRAMS}
	- rm ${TEST_PROGRAMS}
	- cd $(LUA); make clean

# Specific targets, for individual artefacts.

$(LIBLUA):
	cd $(LUA); make linux local

bbla_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=$@ \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

bbla_complex_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=bbla_test -version=complex_numbers \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

bracketing_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=$@ \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

bracketing_complex_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=bracketing_test -version=complex_numbers \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

gaussquad_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=$@ \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

gaussquad_complex_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -version=gaussquad_test -version=complex_numbers \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

linesearch_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=$@ \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

linesearch_complex_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=linesearch_test -version=complex_numbers \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

newtoncotes_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=$@ \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

newtoncotes_complex_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=newtoncotes_test -version=complex_numbers \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

ridder_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=$@ \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

ridder_complex_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=ridder_test -version=complex_number \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

rungekutta_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=$@ \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

rungekutta_complex_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=rungekutta_test -version=complex_numbers \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

brent_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=$@ \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

brent_complex_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=brent_test -version=complex_numbers \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

smla_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=$@ \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

smla_complex_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=smla_test -version=complex_numbers \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

rsla_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=$@ \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

rsla_complex_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=rsla_test -version=complex_numbers \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

luabbla_test: luabbla.d bbla.d complex.d number.d $(UTIL_FILES) $(LIBLUA) $(UTIL_FILES)
	dmd -of$@ -debug -g -w -dip1008 -version=$@ \
		luabbla.d bbla.d complex.d number.d $(UTIL_FILES) $(DLINKFLAGS)

complex_number_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -version=complex_number_test -version=complex_numbers \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

newton_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=$@ \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

newton_complex_test: $(NM_FILES) $(UTIL_DIR)/msg_service.d
	dmd -of$@ -debug -g -w -dip1008 -version=newton_test -version=complex_numbers \
		$(NM_FILES) $(UTIL_DIR)/msg_service.d

# Some demo targets. These are left over from the early days of development.
# They should continue to work and provide a minimal example of how to get
# going with particular modules.

ridder_demo: ridder_demo.d ridder.d bracketing.d complex.d
	dmd -g ridder_demo.d ridder.d bracketing.d complex.d

linesearch_demo: linesearch_demo.d linesearch.d complex.d
	dmd -g linesearch_demo.d linesearch.d complex.d

nelmin_demo: nelmin_demo.d nelmin.d complex.d number.d
	dmd -g nelmin_demo.d nelmin.d complex.d number.d

nelmin_complex_demo: nelmin_demo.d nelmin.d complex.d number.d
	dmd -of$@ -g nelmin_demo.d nelmin.d complex.d number.d -version=complex_numbers

rungekutta_demo: rungekutta_demo.d rungekutta.d complex.d
	dmd -g rungekutta_demo.d rungekutta.d complex.d

newtoncotes_demo: newtoncotes_demo.d newtoncotes.d complex.d
	dmd -g newtoncotes_demo.d newtoncotes.d complex.d

gaussquad_demo: gaussquad_demo.d gaussquad.d complex.d
	dmd -g gaussquad_demo.d gaussquad.d complex.d

bbla_demo: bbla_demo.d bbla.d complex.d
	dmd -g bbla_demo.d bbla.d complex.d
