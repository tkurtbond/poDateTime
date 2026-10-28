# Leap seconds

Written 2026-10-28. This document records the decision on Q5 in
[date-time-design.md](date-time-design.md): whether, and how, the library
deals with leap seconds.

**Decision: option 2.** Leap seconds are not modelled. The timestamp
readers accept a second of `60` where a leap second can occur, and read
it as the last nanosecond of the minute before. Option 3, a separate
`LeapSeconds` module, is noted as possible future work but is not
planned.

## 1. Background

- **27 leap seconds** have been inserted into UTC since 1972. The last
  was at 2016-12-31T23:59:60Z. None has ever been removed.
- **They are being retired.** In 2022 the 27th General Conference on
  Weights and Measures decided to stop inserting them by 2035. The table
  of leap seconds is short, and it will soon stop changing.
- **Every clock poc reads ignores them.**
  - POSIX time has no 23:59:60.
  - During a leap second, Linux repeats a second or steps the clock
    back.
  - Some providers smear the second over several hours.
  - VAX/VMS 5.5-2 has no notion of leap seconds.

  A leap-second table therefore could not make `Clocks.Now` any more
  accurate.
- **What the surveyed languages do:**
  - C, POSIX, Python, Ruby, Go and C++'s `system_clock` ignore leap
    seconds.
  - Ada 2005 has them:
    - `Ada.Calendar.Arithmetic.Difference` returns a separate count of
      leap seconds;
    - `Ada.Calendar.Formatting.Split` and `Time_Of` take a `Leap_Second`
      flag;
    - GNAT keeps a built-in table for these.
  - C++20 has `utc_clock`, `tai_clock` and `gps_clock`, which count leap
    seconds using the tz database's leap-second data. `system_clock`
    does not.
- **The tz database's `right/` zones** have TZif files that count leap
  seconds. Almost nobody uses them.
- **RFC 3339 allows a second of `60`**, and real timestamps, for example
  from logs or from GPS receivers, contain it.

## 2. The options

### 2.1 Ignore leap seconds entirely

This was the original proposal: POSIX time, and the readers refuse a
second of `60`.

- **For:**
  - It is the simplest option.
  - It agrees with every clock.
  - There is only one `Instant` type.
- **Against:** a valid RFC 3339 timestamp, such as
  `2016-12-31T23:59:60Z`, fails to parse.

### 2.2 Ignore them, but read `:60` (chosen)

The model stays POSIX time, but a reader accepts a second of `60` where
a leap second can occur, and reads it as `59.999999999` of the same
minute. No table is needed.

- **For:**
  - Real timestamps parse.
  - The date stays the same and the order of instants stays right.
  - The model does not change.
  - It costs a few lines in `TimeStrings`.
- **Against:**
  - Two different strings read as the same instant.
  - A value read from `:60` is written back as `:59.999999999`, not as
    `:60`.

### 2.3 A separate `LeapSeconds` module

This would work like C++'s `utc_clock`. It would hold the table of 27
leap seconds, either built in or read from the tz database's
`leapseconds` or `leap-seconds.list`. It would provide:

- TAI − UTC at an instant;
- the elapsed SI seconds between two instants;
- whether an instant falls at a leap second, so that formatting can
  write `:60`.

`Instant` itself would not change, so the module could be added at any
time.

- **For:** it serves the rare program that needs exact elapsed time over
  years, such as astronomy or GPS.
- **Against:**
  - A table has to be maintained. That matters less now that the table
    will stop changing by 2035.
  - Nobody has asked for it.

### 2.4 Count leap seconds inside `Instant`

This makes `Instant` like TAI. **Rejected:**

- Every clock reading and every TZif file would have to be converted.
- `Durations.day` would no longer equal one calendar day.

## 3. What the decision means

**Where `:60` is accepted:**

- In `TimeStrings.ReadOffsetDateTime` and `ReadInstant`.
- In `TimeStrings.Parse`, when the text also gives an offset
  (`offsetGiven`).

**The rule:**

1. Read the text with the second set to `59`.
2. Convert it to UTC with the offset that was read.
3. Accept it only if the UTC time is 23:59:59 on the last day of a
   month. ITU-R TF.460 allows a leap second at the end of any month,
   and in practice they have been put only at the end of June or
   December.
4. Store the result as second `59`, nanosecond `999 999 999`. Any
   fractional digits after `:60` are ignored, so `23:59:60.5Z` and
   `23:59:60Z` read the same.

**Where `:60` is still refused:**

- `ReadTimeOfDay` and `ReadDateTime`, and `Parse` without an offset.
  Without an offset, a civil time cannot be placed in UTC, so the
  library cannot tell whether a leap second could occur there.
- `Calendar.SetTimeOfDay`, `SetDateTime` and the `Valid*` procedures.
  The civil types keep `second` in `0 .. 59`.

**Output** never writes `:60`.

**`TimeZones`** still refuses TZif files that have leap-second records,
which are the `right/` zones (design §8.3).

**Tests:**

- `2016-12-31T23:59:60Z` and `2016-12-31T18:59:60-05:00` are accepted;
- `2016-12-30T23:59:60Z` and `2016-12-31T23:58:60Z` are refused;
- `2016-12-31T23:59:60` with no offset is refused, for both
  `ReadDateTime` and `Parse`.
