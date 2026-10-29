# GNUmakefile - poDateTime: the library and its tests (design 12.1-12.3).
#
# `make` builds the library podatetime under both size models in build/;
# `make check` builds each test program under both and compares its output
# with test/<Test>.expected. `make vax` builds podatetime and vmsinstants
# for vax-dec-vms under both, as MACRO-32 for VMS to assemble, in
# build/vax/vax-dec-vms/<model>/, laid out as the kit's [.LIB.POC] is
# (design 12.2).
#
# `make install` installs podatetime under both models in
# $(POC_OBERON_LIBRARIES)/podatetime (poc puts each in <triple>/<model>/
# there), where other repos' poc makefiles find it with -library-path.
# `make install-vax` adds the VAX's podatetime there, and vmsinstants in
# $(POC_OBERON_LIBRARIES)/vmsinstants; it is separate because poc's VAX
# target is packaged on its own on some systems. `make uninstall` removes
# what they wrote.

POC ?= poc
BUILD := build

# Each library in its own directory under POC_OBERON_LIBRARIES, so a
# program names only the libraries it uses.
POC_OBERON_LIBRARIES ?= /usr/local/sw/versions/oberon/poc/lib
LIBDIR = $(POC_OBERON_LIBRARIES)/podatetime
VMS_LIBDIR = $(POC_OBERON_LIBRARIES)/vmsinstants
LIBMODS := TimePlatform Durations Instants Calendar TimeZones Clocks TimeStrings
TRIPLE = $(shell $(POC) -version | sed -n 's/^target \([^ ]*\).*/\1/p')
MODELS := O2 OC
# a dependency only: poc compiles TimePlatform.c beside TimePlatform.Mod itself
SRCS := src/llvm/TimePlatform.Mod $(wildcard src/*.Mod)
C_SRCS := src/llvm/TimePlatform.c
TEST_SRCS := test/TimeTests.Mod test/llvm/ZoneFiles.Mod test/llvm/RealFormat.Mod $(wildcard test/data/*.Mod) $(shell find test/data/zoneinfo -type f)
TESTS := DurationsTest InstantsTest CalendarTest ClocksTest TimeStringsTest TimeZonesTest PatternsTest
IMPORTS := -import-path src -import-path src/llvm -import-path test -import-path test/llvm \
  -import-path test/data
ZONEINFO := $(CURDIR)/test/data/zoneinfo

.PHONY: all check check-o2 check-oc vax install install-vax uninstall clean data zone-files \
  FORCE
.SECONDEXPANSION:

all: $(BUILD)/O2/stamp $(BUILD)/OC/stamp

# what poc -version says, rewritten only when it changes, so that every
# stamp below depends on the compiler: a library records the poc that
# built it, and another poc refuses it
POC_STAMP := $(BUILD)/poc-version

$(POC_STAMP): FORCE
	@mkdir -p $(BUILD)
	@$(POC) -version > $@.new
	@if cmp -s $@.new $@; then rm -f $@.new; else mv $@.new $@; fi

$(BUILD)/%/stamp: $(SRCS) $(C_SRCS) $(POC_STAMP)
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

$(VAX_LIB)/%/podatetime.stamp: $(VAX_SRCS) $(POC_STAMP)
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
$(BUILD)/%.passed: $(SRCS) $(C_SRCS) $(TEST_SRCS) test/$$(notdir $$*).Mod test/$$(notdir $$*).expected \
  $(POC_STAMP)
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

# Install only a library whose tests pass; the VAX's cannot be run here,
# so install-vax needs only the build. poc -install-library copies only
# what a program needs: for LLVM the archive, the shared object, the
# manifest and each module's .sym and .owner; for the VAX the manifest,
# the build and setup procedures and each module's .mar, .sym and .owner.
# A library records the poc that built it, and another poc refuses it:
# install again after upgrading poc.
install: all check
	install -d $(LIBDIR)
	for m in $(MODELS); do \
	  $(POC) -$$m -library-path $(BUILD)/$$m -output-dir $(LIBDIR) -install-library podatetime || exit 1; \
	done

install-vax: vax
	install -d $(LIBDIR) $(VMS_LIBDIR)
	for m in $(MODELS); do \
	  $(POC) -target vax-dec-vms -$$m -library-path $(BUILD)/vax -output-dir $(LIBDIR) \
	    -install-library podatetime && \
	  $(POC) -target vax-dec-vms -$$m -library-path $(BUILD)/vax -output-dir $(VMS_LIBDIR) \
	    -install-library vmsinstants || exit 1; \
	done

# Remove what install and install-vax wrote, and only that.
uninstall:
	for m in $(MODELS); do \
	  d=$(LIBDIR)/$(TRIPLE)/$$m; \
	  rm -f $$d/libpodatetime.a $$d/libpodatetime.so $$d/podatetime.library \
	    $(foreach x,$(LIBMODS),$$d/$(x).sym $$d/$(x).owner); \
	  rmdir $$d $(LIBDIR)/$(TRIPLE) 2>/dev/null; \
	  d=$(LIBDIR)/vax-dec-vms/$$m; \
	  rm -f $$d/podatetime.library $$d/podatetime_build.com $$d/podatetime_setup.com \
	    $(foreach x,$(LIBMODS),$$d/$(x).mar $$d/$(x).sym $$d/$(x).owner); \
	  rmdir $$d $(LIBDIR)/vax-dec-vms 2>/dev/null; \
	  d=$(VMS_LIBDIR)/vax-dec-vms/$$m; \
	  rm -f $$d/vmsinstants.library $$d/vmsinstants_build.com $$d/vmsinstants_setup.com \
	    $$d/VmsInstants.mar $$d/VmsInstants.sym $$d/VmsInstants.owner; \
	  rmdir $$d $(VMS_LIBDIR)/vax-dec-vms 2>/dev/null; \
	done; \
	rmdir $(LIBDIR) $(VMS_LIBDIR) 2>/dev/null; true

clean:
	rm -rf $(BUILD)
