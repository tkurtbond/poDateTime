# AGENTS.md

Notes for agents (and people) working in this repository.

## What this is

poDateTime is a library of Oberon-2 modules for dates, times, durations
and time zones, built with the Peaseblossom Oberon Compiler (`poc`). It
provides clocks, instants, civil dates and times, durations, calendar
periods, time zones, and conversion to and from strings.

The design is `doc/date-time-design.md`, which includes a survey of
Ada, Modula-3, Python, Ruby, C and C++. Read it before writing code.
Its section 12.4 gives the order of work, in six steps, each reviewed
before the next starts. Its section 13 lists the questions for review
and their decisions. Do not settle an open question silently. Raise it
with the user, then record the decision in section 13; a decision that
needs its reasons kept gets a note of its own in `doc/`, linked from
there.

**The current state:** step 1 (`Durations`, `Instants`, `Calendar` and
their tests) is done and reviewed. Q11-Q14 were decided
during it. Step 2 (`TimePlatform` for LLVM, and `Clocks`) is done and
reviewed; `TimePlatform`'s zone procedures come with step 4. Step 3
(`TimeStrings`, fixed formats) is done and reviewed; Q15 and Q16 were
decided during it. Step 4 (`TimeZones`, and `TimePlatform`'s zone
procedures for LLVM) is done and reviewed; Q17 was decided during it.
Step 5 (`TimeStrings`, patterns) is done and reviewed; Q18-Q21 were
decided during it. Step 6 (the VAX port) is next. Steps 1-5 pass under
both models on Linux and on the
local BSD VMs (cymoril, OpenBSD i386; artos, NetBSD amd64; alerik,
FreeBSD amd64), not yet on the VAX.

## The compiler

- **Use the installed `poc`**: `/usr/bin/poc`, version 0.10.0 (d849a15)
  since 2026-10-28. Its libraries are in `/usr/lib/poc`. Check what the
  compiler accepts by running it, not by reading its source.
  0.10.0 allows external variables, which `Monotonic` on VMS needs
  (design Q8).
- **Under `-OC`, `SHORT` of a `HUGEINT` gives a 32-bit `INTEGER`**, not
  the 64-bit `LONGINT`, and cuts the value without a word; a `HUGEINT`
  cannot be assigned to a `LONGINT` at all. Use `SHORT` only for values
  that fit in 32 bits, and `TimeStrings.Long`'s pieces otherwise.
- **On i386 a `LONGREAL` result is an 80-bit x87 value** until it is
  stored, so a function's result compared at once can differ from the
  same value stored. Tests store it in a global first.
- **Building and testing:** `make` builds the library under both size
  models in `build/`; `make check` runs the tests under both.
- **`~/Repos/Oberon/Peaseblossom` is reference only.** Read its
  `doc/users-guide.md`, its runtime (`rtl/`) and its `AGENTS.md` for
  conventions, but never modify, build or commit anything there.
- **Targets:** `x86_64-redhat-linux-gnu` (LLVM, the default) and
  `vax-dec-vms`. The LLVM target also covers the BSDs that
  Peaseblossom tests on.
- **Size models:** under `-O2`, the default, `INTEGER` and `LONGINT` are
  16 and 32 bits; under `-OC` they are 32 and 64. `HUGEINT` is 64 bits
  under both. Every module must compile and pass its tests under both.
- **Building:** `poc -library podatetime <files>`. A module's C part is
  `<Module>.c` beside `<Module>.Mod` (LLVM only).

## Language rules

- **Functions cannot return records or arrays** in poc. Records come
  back through a first `VAR` parameter (design §4.3).
- **The extensions used**, and no others:
  - `HUGEINT`;
  - `ASSERT`;
  - read-only parameters (`x-`);
  - `SYSTEM` and `["C"]`/`["VMS"]` external procedures, **in
    `TimePlatform` only**.
  
  No record or array literals and no field initializers. The library
  cannot be `-strict` clean, because it needs `HUGEINT`.
- **Only `TimePlatform` is per target** (`src/llvm/`, `src/vax/`). The
  VAX-only `VmsInstants` (`src/vax/`) is the one module that uses
  `VMSLIB`.
  Everything in `src/` is portable and compiled unchanged for both.
- **Module names** must not collide with poc's runtime modules, nor with
  VMSLIB's `DateTimes` and `Timers`. Oberon has one global module
  namespace.
- **Strings:**
  - Output appends at the first `0X`, as `OutStr` does.
  - Input reads from `s[pos]`, as `InStr` does, but reports success as a
    `BOOLEAN` result, not a global `Done`.

## Style

Match Peaseblossom's `rtl/` sources:

- a two-space indent;
- full-word names (`DaysInMonth`, not `DIM`);
- exported constants and procedures named as in the design;
- a comment at the head of each module saying what it is for and
  listing its `ASSERT` numbers;
- comments that explain why, not what the next line does.

Documentation is Markdown in `doc/`, terse, in the register of
Peaseblossom's `doc/research/` surveys.

## VMS

- **Facts about VMS come only from the VAX/VMS 5.5-2 manuals**, or the
  nearest earlier 5.x release if 5.5-2 does not cover the point. Do not
  rely on OpenVMS 6 or later, or on memory. Newer manuals may point to
  a facility, but check that it is in the 5.5 manuals before using it.
  Mark anything not yet checked as open.
- **The `claude` account** on the VAX guest may be used for checks. Its
  password is in `~/.netrc-claude-vax`, under the same rules: never
  printed, recorded or put on a command line. Peaseblossom's
  `tools/vax-do` reads it with `VAX_NETRC=~/.netrc-claude-vax
  VAX_USER=claude`.
- **The VAX account passwords are in `~/.netrc-poc-vax`. Never print
  them**, never echo them, and never put them in a file, a command line
  that is logged, or a commit.
- **Never type into the SIMH console window.** Use the means that
  Peaseblossom's `AGENTS.md` describes for reaching the VAX.

## Testing

Design §12.3 has the details. In short:

- exhaustive round trips of the calendar arithmetic over the years
  -9999..9999;
- reference tables generated by Python's `datetime` and `zoneinfo` and
  checked in under `test/data/`, so that the tests need no Python on the
  BSDs or the VAX;
- string round trips, and strings that must be refused;
- runs under `-O2` and `-OC` on Linux, on the BSD VMs, and on the VAX
  once the VAX port exists. The VMs are cymoril, artos and alerik, as in
  Peaseblossom's `AGENTS.md`. Copy the tree to a fresh
  `~/podatetime-check` on each (`git archive HEAD | ssh host tar -xf -
  -C ~/podatetime-check`) and run `gmake -k check` there.

Report test results as they are. If something was not run on a target,
say so.

## Git

- Work on `main` only until the user says otherwise.
- **Commit only when the user asks.** End commit messages with:

  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- Leave scratch files in the session's scratchpad, not in the
  repository.
