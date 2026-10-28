# GNUmakefile - poDateTime: the library and its tests (design 12.1-12.3).
#
# `make` builds the library podatetime under both size models in build/;
# `make check` builds each test program under both and compares its output
# with test/<Test>.expected. vax comes with step 6 of design 12.4.
# install is left for later: poc -install-library writes into poc's own
# library directory, which needs root.

POC ?= poc
BUILD := build
# a dependency only: poc compiles TimePlatform.c beside TimePlatform.Mod itself
SRCS := src/llvm/TimePlatform.Mod $(wildcard src/*.Mod)
C_SRCS := src/llvm/TimePlatform.c
TEST_SRCS := test/TimeTests.Mod $(wildcard test/data/*.Mod) $(shell find test/data/zoneinfo -type f)
TESTS := DurationsTest InstantsTest CalendarTest ClocksTest TimeStringsTest TimeZonesTest
IMPORTS := -import-path src -import-path src/llvm -import-path test -import-path test/data
ZONEINFO := $(CURDIR)/test/data/zoneinfo

.PHONY: all check check-o2 check-oc clean data zone-files
.SECONDEXPANSION:

all: $(BUILD)/O2/stamp $(BUILD)/OC/stamp

$(BUILD)/%/stamp: $(SRCS) $(C_SRCS)
	mkdir -p $(BUILD)/$*
	$(POC) -$* -output-dir $(BUILD)/$* -library podatetime $(SRCS)
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

# the TZif files the zone tables are made from, from the system's tzdata.zi
zone-files:
	python3 -I tools/zone-files.py

clean:
	rm -rf $(BUILD)
