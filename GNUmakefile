# GNUmakefile - poDateTime: the library and its tests (design 12.1-12.3).
#
# `make` builds the library podatetime under both size models in build/;
# `make check` builds each test program under both and compares its output
# with test/<Test>.expected. install and vax come with steps 2 and 6 of
# design 12.4.

POC ?= poc
BUILD := build
SRCS := $(wildcard src/*.Mod)
TEST_SRCS := test/TimeTests.Mod $(wildcard test/data/*.Mod)
TESTS := DurationsTest InstantsTest CalendarTest
IMPORTS := -import-path src -import-path test -import-path test/data

.PHONY: all check check-o2 check-oc clean data
.SECONDEXPANSION:

all: $(BUILD)/O2/stamp $(BUILD)/OC/stamp

$(BUILD)/%/stamp: $(SRCS)
	mkdir -p $(BUILD)/$*
	$(POC) -$* -output-dir $(BUILD)/$* -library podatetime $(SRCS)
	touch $@

check: check-o2 check-oc

check-o2: $(TESTS:%=$(BUILD)/O2/%.passed)
check-oc: $(TESTS:%=$(BUILD)/OC/%.passed)

# $* is <model>/<Test>
$(BUILD)/%.passed: $(SRCS) $(TEST_SRCS) test/$$(notdir $$*).Mod test/$$(notdir $$*).expected
	mkdir -p $(BUILD)/$(dir $*)
	$(POC) -$(patsubst %/,%,$(dir $*)) -output-dir $(BUILD)/$(dir $*) $(IMPORTS) \
	  -o $(BUILD)/$* test/$(notdir $*).Mod
	$(BUILD)/$* > $(BUILD)/$*.out
	diff -u test/$(notdir $*).expected $(BUILD)/$*.out
	touch $@

# the reference tables, which need Python; they are checked in, so that
# the tests do not
data:
	python3 -I tools/calendar-data.py > test/data/CalendarData.Mod
	python3 -I tools/instants-data.py > test/data/InstantsData.Mod

clean:
	rm -rf $(BUILD)
