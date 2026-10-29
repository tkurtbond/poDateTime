# GNUmakefile - poDateTime: the library and its tests (design 12.1-12.3).
#
# `make` builds the library podatetime under both size models in build/;
# `make check` builds each test program under both and compares its output
# with test/<Test>.expected. `make vax` builds podatetime and vmsinstants
# for vax-dec-vms under both, as MACRO-32 for VMS to assemble, in
# build/vax/vax-dec-vms/<model>/, laid out as the kit's [.LIB.POC] is
# (design 12.2).
# install is left for later: poc -install-library writes into poc's own
# library directory, which needs root.

POC ?= poc
BUILD := build
# a dependency only: poc compiles TimePlatform.c beside TimePlatform.Mod itself
SRCS := src/llvm/TimePlatform.Mod $(wildcard src/*.Mod)
C_SRCS := src/llvm/TimePlatform.c
TEST_SRCS := test/TimeTests.Mod test/llvm/ZoneFiles.Mod test/llvm/RealFormat.Mod $(wildcard test/data/*.Mod) $(shell find test/data/zoneinfo -type f)
TESTS := DurationsTest InstantsTest CalendarTest ClocksTest TimeStringsTest TimeZonesTest PatternsTest
IMPORTS := -import-path src -import-path src/llvm -import-path test -import-path test/llvm \
  -import-path test/data
ZONEINFO := $(CURDIR)/test/data/zoneinfo

.PHONY: all check check-o2 check-oc vax clean data zone-files
.SECONDEXPANSION:

all: $(BUILD)/O2/stamp $(BUILD)/OC/stamp

$(BUILD)/%/stamp: $(SRCS) $(C_SRCS)
	mkdir -p $(BUILD)/$*
	$(POC) -$* -output-dir $(BUILD)/$* -library podatetime $(SRCS)
	touch $@

# the VAX's: TimePlatform for VMS reads EXE$GL_ABSTIM_TICS, which SYS.STB
# defines (Q8), and VmsInstants is a library of its own, which needs VMSLIB
# (Q23)
VAX_SRCS := src/vax/TimePlatform.Mod $(wildcard src/*.Mod)

VAX_LIB := $(BUILD)/vax/vax-dec-vms

vax: $(VAX_LIB)/O2/vmsinstants.stamp $(VAX_LIB)/OC/vmsinstants.stamp
.SECONDARY: $(VAX_LIB)/O2/podatetime.stamp $(VAX_LIB)/OC/podatetime.stamp

$(VAX_LIB)/%/podatetime.stamp: $(VAX_SRCS)
	$(POC) -target vax-dec-vms -$* -output-dir $(BUILD)/vax -library podatetime \
	  -link 'SYS$$SYSTEM:SYS.STB/SELECTIVE_SEARCH' $(VAX_SRCS)
	touch $@

$(VAX_LIB)/%/vmsinstants.stamp: src/vax/VmsInstants.Mod $(VAX_LIB)/%/podatetime.stamp
	$(POC) -target vax-dec-vms -$* -output-dir $(BUILD)/vax -library-path $(BUILD)/vax \
	  -library vmsinstants src/vax/VmsInstants.Mod
	touch $@

check: check-o2 check-oc

check-o2: $(TESTS:%=$(BUILD)/O2/%.passed)
check-oc: $(TESTS:%=$(BUILD)/OC/%.passed)

# $* is <model>/<Test>
$(BUILD)/%.passed: $(SRCS) $(C_SRCS) $(TEST_SRCS) test/$$(notdir $$*).Mod test/$$(notdir $$*).expected
	mkdir -p $(BUILD)/$(dir $*)
	$(POC) -$(patsubst %/,%,$(dir $*)) -output-dir $(BUILD)/$(dir $*) $(IMPORTS) \
	  -o $(BUILD)/$* test/$(notdir $*).Mod
	$(RUN_ENV) $(BUILD)/$* > $(BUILD)/$*.out
	diff -u test/$(notdir $*).expected $(BUILD)/$*.out
	touch $@

# Named reads the slim files, and the C library the fat America/New_York
$(BUILD)/O2/TimeZonesTest.passed $(BUILD)/OC/TimeZonesTest.passed: \
  RUN_ENV = TZ=$(ZONEINFO)/fat/America/New_York TZDIR=$(ZONEINFO)/slim

# the reference tables, which need Python; they are checked in, so that
# the tests do not
data:
	python3 -I tools/calendar-data.py > test/data/CalendarData.Mod
	python3 -I tools/instants-data.py > test/data/InstantsData.Mod
	python3 -I tools/strings-data.py > test/data/StringsData.Mod
	python3 -I tools/zones-data.py > test/data/ZonesData.Mod
	python3 -I tools/patterns-data.py > test/data/PatternsData.Mod
	python3 -I tools/zone-files-data.py > test/data/ZoneFilesData.Mod

# the TZif files the zone tables are made from, from the system's tzdata.zi
zone-files:
	python3 -I tools/zone-files.py

clean:
	rm -rf $(BUILD)
