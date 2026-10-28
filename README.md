# poDateTime - dates, times and time zones for Oberon-2

This software is developed with the aid of AI.

poDateTime is a library of Oberon-2 modules for dates, times, durations
and time zones, built with poc, the
[Peaseblossom Oberon Compiler](https://github.com/tkurtbond/peaseblossom).
It runs on Linux, NetBSD, OpenBSD and FreeBSD through poc's LLVM
backend; a port to VAX/VMS 5.5-2 is in progress.

## The modules

- `Durations`: elapsed time, as a count of nanoseconds of about
  ±292 years.
- `Instants`: points on the time line, as POSIX seconds and
  nanoseconds, over the years -9999..9999.
- `Calendar`: civil dates, times of day and date-times in the
  proleptic Gregorian calendar, with offsets from UTC, ISO weeks, and
  calendar periods of years, months and days.
- `Clocks`: the wall clock, a monotonic clock, the process's CPU
  time, and sleeping.
- `TimeZones`: fixed offsets, POSIX `TZ` rules, and the TZif files of
  the tz database.
- `TimeStrings`: ISO 8601 and RFC 3339 forms, and `strftime`'s
  patterns, to and from strings.
- `TimePlatform`: what each target supplies, and the only module that
  differs between them.

## Building

`make` builds the library `podatetime` under both of poc's size
models, `-O2` and `-OC`, in `build/`; `make check` runs the tests under
both. The tests need only poc; their reference tables, made with
Python's `datetime` and `zoneinfo` and with glibc's `strftime`, are
checked in under `test/data/`, and `make data` makes them again.

## Documents

`doc/date-time-design.md` is the design: a survey of what Ada,
Modula-3, Python, Ruby, C and C++ provide, the interface of each
module, the order of work, and the questions decided along the way.
The other files in `doc/` keep the reasons for single decisions.
`PLAN.md` points to the order of work, and `AGENTS.md` gives the
current state and the project's standing rules.

## License

BSD 3-Clause; see `LICENSE`.
