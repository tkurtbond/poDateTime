# poDateTime: dates, times and durations for poc

Written 2026-10-28. This is a design to review. No code exists yet. It
proposes a library of Oberon-2 modules for the Peaseblossom Oberon
Compiler (`poc`) that:

- reads the clocks (wall clock, monotonic clock, CPU time);
- represents points on the timeline, civil dates and times, durations
  and calendar periods;
- does arithmetic on them: subtracting one date/time from another gives
  a duration, and adding a duration or a period to a date/time gives
  another date/time;
- converts between UTC and local time through time zones;
- turns all of these into strings and reads them back from strings.

Section 1 is what poc and its runtime already have. Section 2 surveys
how Ada, Modula-3, Python, Ruby, C and C++ handle dates, times and
durations. Section 3 lists the lessons drawn from the survey. Sections
4-12 are the design, and section 13 lists the open questions.

What poc accepts was checked against the installed `poc` 0.9.0
(`/usr/bin/poc`, library path `/usr/lib/poc`), not against the
Peaseblossom source tree. The language facts in section 2 come from the
sources listed at the start of that section.

## 1. What poc has today

**The language, as poc implements it.** These points shape everything
below:

- **A function cannot return a record or an array.** Checked with poc
  0.9.0: "the result type of a procedure cannot be a record or an
  array". A value that is a record comes back through a `VAR` parameter.
  A value that is a single integer can be a function result, and it can
  be used with `+`, `-`, `<` and `=`.
- **Oberon has no distinct types.** `TYPE Duration = HUGEINT` is only
  another name for `HUGEINT`. The compiler cannot keep two integer
  quantities apart, but it can keep two record types apart.
- **`HUGEINT`** is 64 bits under both size models and on both backends.
  `LONGINT` is 32 bits under `-O2`, the default, and 64 under `-OC`. A
  test program using `HUGEINT` `DIV`, `MOD` and record parameters built
  and ran on Linux, and passed `-check` and `-emit-macro32` for
  `vax-dec-vms`.
- **`DIV` and `MOD` floor**, as the Oberon report says: `-7 DIV 3 = -3`
  and `-7 MOD 3 = 2`. Calendar algorithms come out simpler with this
  than in C, which truncates.
- **Integer overflow wraps**, and poc promises that it does. Nothing
  traps.
- There are **no exceptions**. Failure is reported by a `BOOLEAN` result,
  or by `ASSERT`/`HALT`, which stop the program.
- **Extensions available:** `HUGEINT`, `ASSERT`, read-only parameters
  (`x-`), record and array literals, `["C"]` and `["VMS"]` external
  procedures, and a module part in C (`<Module>.c` beside
  `<Module>.Mod`, LLVM only). `-strict` rejects all of them. The design
  needs `HUGEINT`, so it cannot be strict Oberon-2.
- **Every variable starts at zero**, locals included.

**The runtime, `poc-rtl`.**

- `Platform.GetClock(t, d)` and `Oberon.GetClock` give the local time in
  the Oberon system's packed format: `d` holds the year modulo 100, the
  month and the day; `t` holds the hour, minute and second.
  `Files.GetDate` uses the same format.
- `Platform.GetTimeOfDay(sec, usec)` gives the seconds and microseconds
  since 1970. The seconds are a `LONGINT`, which wraps in 2038 under
  `-O2`.
- `Platform.Time()` gives milliseconds since the program started, modulo
  `7FFFFFFFH`. `Platform.Delay(ms)` sleeps.
- On LLVM, `Platform.c` wraps `gettimeofday` and `localtime`. On the VAX,
  `Platform` uses `SYS$GETTIM`, whose result is local time.
- `OutStr` appends text at a string's first `0X` and silently cuts what
  does not fit. `InStr` reads from `s[pos]` and moves `pos` past the
  token only if it succeeds. The string procedures here follow both
  conventions.
- **On VMS only,** the `VMSLIB` library has a module named `DateTimes`:
  VMS's 100-nanosecond quadword times, wrapping `$BINTIM`, `$ASCTIM`,
  `LIB$ADD_TIMES` and `LIB$FORMAT_DATE_TIME`. Its own comment points
  portable programs to `Oberon.Time` and `Platform.GetClock`.
  - **Oberon has one global module namespace**, so this library must not
    use the name `DateTimes`, nor any other runtime module's name.

So poc has no portable, 2038-safe, zone-aware date/time library. Nor
does it have a duration type or any formatting or parsing of dates.

## 2. Survey

Sources: the GNAT 16.1 run-time specs (`a-calend.ads`, `a-catizo.ads`,
`a-calari.ads`, `a-calfor.ads`) and the Ada RM, §9.6, §D.8 and §D.14;
the Modula-3 SRC `libm3` interfaces `Time`, `Date`, `FmtTime` and
`Tick`; Python 3.14's `datetime`, `zoneinfo` and `time`; Ruby 4.0's
`Time`, `Date` and `Process.clock_gettime`; C23 and POSIX.1-2024
`<time.h>`; C++20's `<chrono>`. The specific behaviours quoted for
Python, Ruby and C were run on atla on 2026-10-28.

### 2.1 Ada

- **`Ada.Calendar`** has a private type `Time` and the predefined
  fixed-point type `Duration`, in seconds.
  - `Clock` returns the current time.
  - `Split` and `Time_Of` convert between a `Time` and its year, month,
    day and seconds of the day.
  - The operators are overloaded: `Time + Duration`, `Time - Duration`
    and `Time - Time` (which gives a `Duration`), and the comparisons.
    So "subtract two times to get a duration" is written exactly that
    way.
  - `Year_Number` is only `1901 .. 2399`.
  - An out-of-range result raises `Time_Error`.
- **`Duration`** is a fixed-point type. The RM only requires a range of
  at least ±86 400 s and a `Duration'Small` of at most 20 ms. GNAT uses
  a 64-bit count of nanoseconds, which is about ±292 years.
- **Ada 2005 added child packages:**
  - `Ada.Calendar.Time_Zones`: `Time_Offset` is a number of minutes in
    `-1680 .. 1680`, and `UTC_Time_Offset` gives the local offset. There
    are only offsets; there are no named zones.
  - `Ada.Calendar.Arithmetic`: `Day_Count`, `Time - Time` in whole days,
    and `Difference`, which gives days, seconds and leap seconds.
  - `Ada.Calendar.Formatting`: `Day_Of_Week`, a `Split` that gives hour,
    minute, second and sub-second, and `Image`/`Value` for one fixed
    format, `"2026-10-28 14:05:09.50"`. Each takes a `Time_Zone`
    parameter, and there are optional `Leap_Second` flags.
- **`Ada.Real_Time`** is a separate, monotonic clock. It has its own
  `Time` and `Time_Span` types, with constructors `Seconds`,
  `Milliseconds` and so on, and `To_Duration`. `delay until` uses it.
  `Ada.Execution_Time` gives CPU time.
- **Lessons:**
  - The wall clock and the monotonic clock are separate types, so they
    cannot be mixed by mistake.
  - Durations are exact (fixed point), not floating point.
  - Formatting lives in a separate package from the core.
  - Calendar arithmetic (days) is separate from elapsed arithmetic
    (seconds).
  - The year range is too small, and time zones are offsets only.

### 2.2 Modula-3

- **`Time`:** `Time.T = LONGREAL`, seconds since an epoch the
  implementation chooses. `Time.Now()` returns it, and `Time.Grain` is
  the clock's resolution. A duration is also a `LONGREAL`, so
  "duration" and "time" are the same type.
- **`Date`:** `Date.T` is a record holding the year, a `month` from the
  enumeration `{Jan .. Dec}`, the day, hour, minute and second, an
  `offset` from UTC in seconds, a `zone: TEXT` and a `weekDay`.
  - `Date.FromTime(t, z)` and `Date.ToTime(d)` convert. `ToTime` raises
    `Date.Error` for a date it cannot convert, and ignores `weekDay`.
  - A time zone is the opaque `Date.TimeZone`. `Local` and `UTC` are
    provided.
- **`FmtTime.Long(t)` and `FmtTime.Short(t)`** give two fixed renderings.
  There is no parsing.
- **`Tick`** is a monotonic counter (`Tick.Now`, `Tick.ToSeconds`).
- **Lessons:** this is the language closest to Oberon, and its interfaces
  are small and easy to read. But a `LONGREAL` time loses sub-second
  precision as the epoch recedes: at 2^31 seconds a double resolves
  about 0.5 µs. A broken-down record that carries the offset and the
  zone's name is convenient for output.

### 2.3 Python

- **`datetime`:**
  - `date`, `time` and `datetime` are civil types with microsecond
    precision and years `1 .. 9999`, in the proleptic Gregorian calendar.
  - `timedelta` holds days, seconds and microseconds, normalized, with a
    range of ±999 999 999 days. `str(-timedelta(seconds=1))` is
    `"-1 day, 23:59:59"`: the normalized form surprises people.
  - A `datetime` is **naive** (no zone) or **aware** (it has a `tzinfo`).
    The two cannot be compared or subtracted, which is a frequent
    source of bugs.
  - `timezone` is a fixed offset. `zoneinfo.ZoneInfo` (3.9) reads the
    IANA database.
  - **An ambiguous local time** is resolved by the `fold` attribute (PEP
    495). **A nonexistent one** is read with the offset in force before
    the transition: `2026-03-08 02:30` in New York becomes 07:30 UTC.
  - **Arithmetic on an aware `datetime` is wall-clock arithmetic in its
    zone.** `datetime(2026,11,1,0,30,tzinfo=NY) + timedelta(hours=1)`
    gives `01:30-04:00`, while the true instant an hour later is
    `01:30-05:00`. This is a well-known pitfall.
  - Strings: `isoformat`/`fromisoformat`, which takes any ISO 8601 form
    since 3.11, and `strftime`/`strptime`, C's `%` patterns.
- **`time`:** `time()` and `time_ns()`, `monotonic()`, `perf_counter()`,
  `process_time()`, and C's `struct_time`, `gmtime`, `localtime` and
  `mktime`.
- **Lessons:** keep civil (zoneless) date-times and instants apart, as
  Python's naive and aware types do, but make the difference a matter of
  type, not of a field that may be `None`. Be explicit about which kind
  of arithmetic is being done. `strftime`'s pattern language is the one
  most programmers already know.

### 2.4 Ruby

- **`Time`** is an instant with a UTC offset (`utc_offset`, `zone`), held
  as a rational number with nanosecond precision.
  - `Time#-(Time)` returns a `Float` of seconds, and `Time + Numeric`
    adds seconds.
  - **There is no duration type in core**: `ActiveSupport::Duration` in
    Rails fills the gap.
- **`Date`** is a civil date counted by its Julian Day Number.
  - `Date#-` returns a `Rational` of days.
  - `>>` adds months, clamping to the month's end: Jan 31 >> 1 is Feb 28.
  - **By default `Date` switches from the Julian calendar to the
    Gregorian on 1582-10-15** (`Date::ITALY`), so `Date.new(1582,10,15) -
    1` is 1582-10-04. This surprises anyone who expects the proleptic
    Gregorian calendar.
  - `DateTime` is deprecated.
- **Strings:** `strftime`, extended with `%N` (fractional seconds, `%3N`
  for milliseconds) and `%:z` (an offset with a colon);
  `Time.strptime`; `iso8601` and `xmlschema`; and the heuristic
  `Date.parse`.
- **Clocks:** `Process.clock_gettime(Process::CLOCK_MONOTONIC)`.
- **Lessons:**
  - Durations need a type of their own.
  - A `Float` of seconds is lossy, and it lets seconds and days be mixed
    with no warning.
  - Clamping month arithmetic is what people expect.
  - The calendar must be stated: proleptic Gregorian, with no switch.
  - `%N` and `%:z` are worth adopting.

### 2.5 C (C23, POSIX.1-2024)

- **Types and conversions:**
  - `time_t` is seconds since 1970 (POSIX); `time()` reads it.
  - `struct tm` holds the broken-down time:
    - `tm_year` counts from 1900 and `tm_mon` is `0 .. 11`;
    - it also has `tm_wday`, `tm_yday` and `tm_isdst`;
    - POSIX.1-2024 standardized `tm_gmtoff` and `tm_zone`, which glibc
      and the BSDs have long had.
  - `gmtime` and `localtime` convert a `time_t` to a `struct tm`, and
    their `_r` forms do so without static storage. C23 added both `_r`
    forms and `timegm` to ISO C.
  - `mktime` (local time) and `timegm` (UTC) convert back, and normalize
    fields that are out of range: January 62 becomes March 3 (run on
    atla).
- **Durations:** `difftime` returns a `double`. There is no duration type
  besides `struct timespec`.
- **Clocks:** `clock_gettime` with `CLOCK_REALTIME`, `CLOCK_MONOTONIC` or
  `CLOCK_PROCESS_CPUTIME_ID` (all four of poc's Unix systems have them),
  `timespec_get` (C11), `clock()` and `nanosleep`.
- **Strings:** `strftime`, and `strptime`, which is POSIX only.
- **Time zones:** the `TZ` variable, either a POSIX rule string
  (`EST5EDT,M3.2.0,M11.1.0`) or a zone name looked up in
  `/usr/share/zoneinfo`, applied by `tzset`. The zone is global state.
- **Lessons:**
  - `struct tm`'s offsets (years from 1900, months from 0) are a classic
    source of off-by-one errors.
  - The global time zone cannot express "this time in Tokyo" without
    changing `TZ`.
  - Normalizing out-of-range fields hides mistakes.
  - A 32-bit `time_t` ends in 2038.
  - Still, `strftime`'s `%` directives, the POSIX `TZ` rule syntax and
    the TZif files (RFC 8536) are the shared vocabulary every other
    language here reuses.

### 2.6 C++ (`<chrono>`, C++11/C++20)

- **`duration<Rep, Period>`** is a count of ticks with a compile-time
  ratio, for example `milliseconds`. Conversions are checked:
  `duration_cast`, `floor`, `ceil` and `round` make any loss of
  precision explicit.
- **`time_point<Clock, Duration>`** is tied to its clock, so a
  `steady_clock` time point and a `system_clock` one cannot be mixed.
  `time_point - time_point` gives a duration.
- **C++20 adds the calendar:**
  - the field types `year`, `month`, `day`, `weekday` and `last`,
    combined into `year_month_day`, which may be invalid (Feb 30) and
    reports it through `ok()`;
  - `sys_days`, a day count since 1970, used for date arithmetic;
  - `hh_mm_ss`, a time of day split into fields;
  - `local_t` and `local_days`, a local time with no zone, whose type
    differs from `sys_time`'s;
  - `time_zone` and `zoned_time`, backed by the IANA database
    (`locate_zone`, `current_zone`);
  - `choose::earliest` and `choose::latest` for an ambiguous local time,
    and the exceptions `ambiguous_local_time` and
    `nonexistent_local_time`;
  - `utc_clock`, `tai_clock` and `gps_clock`, which know leap seconds;
  - `std::format` and `chrono::parse`, with `%` directives.
- **Month arithmetic:** `year_month_day + months(1)` from Jan 31 gives an
  invalid Feb 31. The caller must check it and snap it to the month's
  end, as `year_month_day_last` does.
- **Lessons:** this is the most careful design of the six:
  - sys time and local time are separate types;
  - the units are typed;
  - the algorithms (Howard Hinnant's `days_from_civil`) are integer-only
    and exact.
  
  Much of it depends on templates and operator overloading, which Oberon
  does not have. What can be carried over:
  - the separation into instant, local date-time, duration and zone;
  - integer ticks;
  - explicit choices for ambiguous and nonexistent local times;
  - Hinnant's algorithms.

### 2.7 Summary

| | instant | civil date-time | duration | calendar period | zones | monotonic | format / parse |
|---|---|---|---|---|---|---|---|
| Ada | `Calendar.Time` (private) | via `Split` | fixed point, ns (GNAT) | days only | offsets | `Real_Time` | one fixed format |
| Modula-3 | `LONGREAL` s | `Date.T` record | `LONGREAL` | none | Local, UTC | `Tick` | output only |
| Python | aware `datetime` | naive `datetime` | `timedelta`, µs | none (3rd party) | IANA | `monotonic` | `%`, ISO |
| Ruby | `Time` | `Date` | Float/Rational | `>>` months | offsets, system | `clock_gettime` | `%` (+`%N`), ISO |
| C | `time_t`/`timespec` | `struct tm` | `double` | via `mktime` | global `TZ` | `CLOCK_MONOTONIC` | `%` |
| C++20 | `sys_time` | `local_time`, `year_month_day` | `duration<>` | `months`, `years` | IANA | `steady_clock` | `%` |

## 3. Lessons for this design

1. **Four separate concepts with four separate types**, as in C++20,
   Python and Ada:
   - an *instant* (a point on the UTC timeline);
   - a *civil date-time* (fields on a calendar, with no zone);
   - a *duration* (elapsed time, exact);
   - a *period* (calendar years, months and days).

   Mixing them is the main source of bugs in all six languages.
2. **Two kinds of arithmetic, with different names.** *Elapsed*
   arithmetic is instant ± duration. *Calendar* arithmetic is civil
   date ± period. Python's aware-`datetime` pitfall comes from giving
   both the same `+`.
3. **Integer ticks, never floating point**, as Ada/GNAT, C++ and C's
   `timespec` do. Nanoseconds is the unit that `clock_gettime`, C++, Go
   and Python's `time_ns` share.
4. **The proleptic Gregorian calendar, astronomical year numbering, and
   months 1-12, days of the week 1-7 (ISO).** None of C's 1900 or zero
   offsets, and none of Ruby's 1582 switch.
5. **Validate; do not normalize silently.** A constructor reports
   failure. As in C++, a civil record may hold invalid fields and can be
   tested, instead of being quietly rolled over as `mktime` does.
6. **Explicit resolution of local times in gaps and overlaps**: C++'s
   `choose`, Python's `fold`, and a strict mode that refuses them.
7. **Zones are values, not global state**, unlike C's `TZ`. Named zones
   come from TZif files and POSIX rule strings, the data every Unix
   already ships.
8. **A separate monotonic clock**, as Ada `Real_Time`, C++ `steady_clock`
   and C `CLOCK_MONOTONIC` provide.
9. **`strftime`-style patterns**: C, Python, Ruby and C++ all use them,
   and Ada's GNAT `GNAT.Calendar.Time_IO` does too. Add Ruby's `%N` and
   `%:z`. Also offer fixed ISO 8601 / RFC 3339 procedures, which most
   programs need and which are easy to get right.
10. **No locale.** English month and day names only, as in the C locale.
    That keeps output reproducible and the VAX port small.

## 4. Overview

### 4.1 Modules

| Module | What it is | Imports | Per target? |
|---|---|---|---|
| `Durations` | `Duration`, a `HUGEINT` of nanoseconds; units, splitting, rounding, saturating arithmetic | — | no |
| `Instants` | `Instant`, a point on the UTC timeline; elapsed arithmetic; Unix time | `Durations` | no |
| `Calendar` | `Date`, `TimeOfDay`, `DateTime`, `OffsetDateTime`, `Period`; Gregorian rules; calendar arithmetic; instant ↔ civil at a given offset | `Durations`, `Instants` | no |
| `TimeZones` | `Zone` objects: UTC, fixed offsets, the local zone, POSIX `TZ` rules, IANA TZif files; local ↔ instant with gap/overlap choices | `Calendar`, `Instants`, `Durations`, `TimePlatform`, `Files` | no |
| `Clocks` | `Now`, `Monotonic`, `ProcessTime`, `Sleep`, resolutions | `Instants`, `Durations`, `TimePlatform` | no |
| `TimeStrings` | ISO 8601 / RFC 3339 output and input; `%` patterns; durations and periods as text | all of the above | no |
| `TimePlatform` | the operating system's part: the clocks, the local offset, the zoneinfo directory | `SYSTEM`, `Platform` (VAX: `STARLET`) | **yes**: `src/llvm/` (with a C part) and `src/vax/` |
| `VmsInstants` | conversions between `VMSLIB`'s `DateTimes.Time` and `Instant`/`Duration` (§11.1) | `DateTimes`, `Durations`, `Instants`, `TimeZones` | **VAX only**: `src/vax/` |

The dependencies go one way, with no cycles:

```
Durations ← Instants ← Calendar ← TimeZones ← TimeStrings
                 ↖        ↖           ↑
                  Clocks ← TimePlatform
```

**Only `TimePlatform` differs between the targets**, and the VAX
library adds `VmsInstants`. Everything else is portable Oberon, compiled
unchanged for LLVM and for the VAX. That
follows Peaseblossom's own split between `rtl/llvm` and `rtl/vax`.
`TimePlatform` is internal: programs import `Clocks` and `TimeZones`
instead.

### 4.2 Names

- **The module names were chosen to avoid poc's runtime modules and
  `VMSLIB`'s `DateTimes`/`Timers`.** `Calendar`, Ada's name for the
  civil module, is short and common, but the review found it safe (Q1,
  decided 2026-10-28).
- **The library is `podatetime`:** `poc -library podatetime ...`, and
  `PODATETIME` on VMS.

### 4.3 Conventions common to every module

- **Records are returned through a first `VAR` parameter**, since a
  function cannot return a record: `Instants.Add(r, t, d)` sets `r` to
  `t + d`. The result may be one of the inputs (`Add(t, t, d)`), because
  the inputs are value or read-only parameters and are read before `r`
  is written.
- **A procedure that can fail because of its input returns `BOOLEAN`**
  and leaves its `VAR` result unchanged when it returns `FALSE`. That
  covers construction from fields, parsing, zone lookup, and resolving a
  local time. These are failures a program is expected to handle.
- **A precondition on a value the program built itself is an `ASSERT`.**
  An invalid `Date` passed to `AddDays`, or a unit of 0 passed to
  `Durations.Truncate`, is a programming error, as in Ada's
  `Constraint_Error` or C++'s preconditions. It traps with status 10.
  Each module's comment lists its `ASSERT` numbers.
- **Saturation:** results that do not fit are clamped to
  `Durations.min`/`max`, or to `Instants.earliest`/`latest`, not wrapped.
  Go's `time.Sub` does the same. This applies to the library's own
  procedures only. `+` on two `Duration`s is ordinary `HUGEINT` addition
  and wraps, as poc promises. Where overflow can come from input, a
  checked form (`CheckedBetween` and the like) returns `BOOLEAN` instead.
  See [duration-overflow.md](duration-overflow.md) (Q4).
- **The language extensions used**, and no others:
  - `HUGEINT`;
  - `ASSERT`;
  - read-only parameters (`s-: ARRAY OF CHAR`, as `InStr` uses them, so
    that a string constant can be passed and long strings are not
    copied);
  - in `TimePlatform` only, `SYSTEM` and external procedures.

  No record literals, field initializers or declarations after
  procedures: this keeps the source within reach of a future port to
  another compiler that has `HUGEINT`.
- **Both size models:** every module compiles and passes its tests under
  `-O2` and `-OC`. The record fields are `LONGINT` (32 bits are enough
  for every field), and all intermediate arithmetic is `HUGEINT`.
- **Text output** follows `OutStr`: append at the first `0X`, cut short
  silently, and always end in `0X`.
- **Text input** follows `InStr`: read from `s[pos]`, stop at the first
  `0X` or at `LEN(s)`, and on success move `pos` past what was used.
  Unlike `InStr`, which sets a global `Done`, the procedures return
  `BOOLEAN`. A global flag cannot be relied on in a VMS AST routine.
- **Zero values:** every variable starts zeroed.
  - A zero `Duration` is no time.
  - A zero `Instant` is 1970-01-01T00:00:00Z.
  - A zero `Date` (year 0, month 0, day 0) is invalid. It serves as
    "not set", and `Calendar.ValidDate` says so.

## 5. `Durations`

```oberon
MODULE Durations;
  CONST
    nanosecond* = 1;  microsecond* = 1000;  millisecond* = 1000000;
    second* = 1000000000;  minute* = 60 * second;  hour* = 60 * minute;
    day* = 24 * hour;  week* = 7 * day;   (* elapsed days: exactly 86 400 s *)
    min* = MIN(HUGEINT);  max* = MAX(HUGEINT);   (* the saturated values *)

  TYPE Duration* = HUGEINT;   (* nanoseconds; about ±292 years *)

  PROCEDURE Of*(days, hours, minutes, seconds, nanoseconds: HUGEINT): Duration;   (* saturating *)
  PROCEDURE Sum*(a, b: Duration): Duration;          (* saturating a + b *)
  PROCEDURE Difference*(a, b: Duration): Duration;   (* saturating a - b *)
  PROCEDURE Scale*(d: Duration; n: HUGEINT): Duration;   (* saturating d * n *)
  PROCEDURE CheckedScale*(VAR r: Duration; d: Duration; n: HUGEINT): BOOLEAN;   (* FALSE on overflow *)
  PROCEDURE Abs*(d: Duration): Duration;             (* ABS, MIN saturates to MAX *)
  PROCEDURE Whole*(d, unit: Duration): HUGEINT;      (* d / unit, toward zero: Whole(90 * minute, hour) = 1 *)
  PROCEDURE Truncate*(d, unit: Duration): Duration;  (* toward zero, to a multiple of unit *)
  PROCEDURE Floor*(d, unit: Duration): Duration;     (* toward -∞ *)
  PROCEDURE Round*(d, unit: Duration): Duration;     (* half away from zero *)
  PROCEDURE Split*(d: Duration; VAR negative: BOOLEAN;
                   VAR days, hours, minutes, seconds, nanoseconds: LONGINT);   (* of ABS(d) *)
  PROCEDURE ToSeconds*(d: Duration): LONGREAL;
  PROCEDURE FromSeconds*(x: LONGREAL): Duration;    (* rounded, saturating; NaN gives 0 *)
  PROCEDURE CheckedFromSeconds*(VAR d: Duration; x: LONGREAL): BOOLEAN;   (* FALSE on overflow, NaN, infinity *)
END Durations.
```

**Why a bare `HUGEINT`, not a record:**

- A `Duration` can be a function result: `Instants.Between(a, b)`,
  `Clocks.Monotonic()`.
- It works with `+ - * DIV < = #` and in constant expressions:
  `CONST timeout = 30 * Durations.second`.
- It is what Go chose, and it is how GNAT represents Ada's `Duration`.

The cost is that the compiler cannot tell a `Duration` from any other
`HUGEINT`. That is acceptable: the dangerous mix-up is between an
instant and a duration, and `Instant` is a record.

**Why nanoseconds:**

- It is the unit of `clock_gettime`, `timespec`, C++'s `nanoseconds`,
  Python's `time_ns` and GNAT. VMS's 100 ns ticks convert exactly
  (× 100).
- ±292 years covers every elapsed time a program measures.
- An interval longer than that is a calendar question, answered by
  `Calendar.DaysBetween` or `PeriodBetween`.

`Split` gives `days` as exactly 24 hours; the count fits in a `LONGINT`
even under `-O2` (at most 106 751). `day` and `week` are elapsed time,
not calendar days. The difference matters across a daylight-saving
change, and section 6.3 says how each is used.

## 6. `Instants`

```oberon
MODULE Instants;
  IMPORT Durations;
  TYPE
    Instant* = RECORD
      seconds-: HUGEINT;     (* since 1970-01-01T00:00:00Z, leap seconds not counted (POSIX time) *)
      nanosecond-: LONGINT   (* 0 .. 999 999 999 *)
    END;
  VAR earliest-, latest-: Instant;   (* -9999-01-01T00:00:00Z, 9999-12-31T23:59:59.999999999Z *)

  PROCEDURE FromUnix*(VAR t: Instant; seconds, nanoseconds: HUGEINT);   (* normalizes nanoseconds of either sign *)
  PROCEDURE FromUnixMilliseconds*(VAR t: Instant; ms: HUGEINT);
  PROCEDURE UnixSeconds*(t: Instant): HUGEINT;          (* floor *)
  PROCEDURE UnixMilliseconds*(t: Instant): HUGEINT;     (* floor, saturating *)
  PROCEDURE Add*(VAR r: Instant; t: Instant; d: Durations.Duration);        (* saturating at earliest/latest *)
  PROCEDURE Subtract*(VAR r: Instant; t: Instant; d: Durations.Duration);
  PROCEDURE Between*(later, earlier: Instant): Durations.Duration;          (* later - earlier, saturating *)
  PROCEDURE CheckedBetween*(VAR d: Durations.Duration; later, earlier: Instant): BOOLEAN;   (* FALSE beyond ±292 years *)
  PROCEDURE Compare*(a, b: Instant): INTEGER;           (* -1, 0, 1 *)
  PROCEDURE Equal*(a, b: Instant): BOOLEAN;
  PROCEDURE Before*(a, b: Instant): BOOLEAN;
  PROCEDURE Truncate*(VAR r: Instant; t: Instant; unit: Durations.Duration);   (* down to a multiple of any unit since 1970 *)
END Instants.
```

### 6.1 Representation

- **A record**, so that an `Instant` and a `Duration` cannot be confused:
  `Instants.Add(r, t, d)` takes one of each, and nothing adds two
  instants.
- **Seconds and nanoseconds, as in `struct timespec`.** One `HUGEINT` of
  nanoseconds would allow only 1678-2262. One of 100 ns ticks (.NET,
  VMS) would allow ±29 000 years, but at a different resolution from
  `Durations`.
- **Read-only fields** (`-`) keep the invariant `0 ≤ nanosecond <
  10^9`. A program builds an instant with `FromUnix`, a clock, a
  calendar conversion or a parse.
- **The range is limited to the years -9999..9999**, so that every
  instant converts to a date and can be written in ISO 8601's four-digit
  (or signed, expanded) years. The record itself could reach much
  further; the limit is the same as `Calendar`'s years, so that
  `FromUTCInstant` and `ToUTCInstant` need no failure result (Q2,
  decided 2026-10-28). At an offset, the first and last 26 hours of the
  years saturate, with checked forms beside (Q12, Q13).

### 6.2 Leap seconds

They are not modelled. The timeline is POSIX time: every day has 86 400
seconds. This is the choice of C, POSIX, Python, Ruby, Go and C++'s
`system_clock`. It is what every Unix clock reports, and VMS 5.5-2 knows
nothing of leap seconds either. "Right" TZif zones, whose transitions
count leap seconds, are refused (section 8.3). The timestamp readers
accept a second of `60` where a leap second can occur, and read it as
the last nanosecond of the minute before (section 10.1). See Q5 and
[leap-seconds.md](leap-seconds.md).

### 6.3 Subtracting and adding date/times: which arithmetic

| Question | Use |
|---|---|
| How long between two moments? | `Instants.Between(b, a)`: a `Duration` |
| The moment 90 minutes after `t`? | `Instants.Add(r, t, 90 * Durations.minute)` |
| The same wall-clock time tomorrow in New York? | `TimeZones.ToLocal` → `Calendar.AddDays` → `TimeZones.ToInstant` |
| How many days between two dates? | `Calendar.DaysBetween(a, b)` |
| How many years, months and days old? | `Calendar.PeriodBetween(p, birth, today)` |
| Elapsed time on a stopwatch? | `Clocks.Monotonic()` twice, then subtract |

### 6.4 Truncating

`Truncate` takes any positive unit. An instant in nanoseconds needs 69
bits, so a unit that neither divides a second nor is whole seconds,
such as 7 ms or 1.5 s, has its remainder found from the two fields,
multiplying modulo the unit. The multiples count from 1970, so
`Durations.day` gives midnight UTC and `Durations.week` gives
Thursdays; days and weeks in a zone, or ISO weeks, go through
`Calendar` and `TimeZones`. See
[instant-truncation.md](instant-truncation.md) (Q14).

## 7. `Calendar`

```oberon
MODULE Calendar;
  IMPORT Durations, Instants;
  CONST
    January* = 1; ... December* = 12;
    Monday* = 1; ... Sunday* = 7;      (* ISO 8601 *)
    minYear* = -9999; maxYear* = 9999;

  TYPE
    Date* = RECORD year*, month*, day*: LONGINT END;
    TimeOfDay* = RECORD hour*, minute*, second*, nanosecond*: LONGINT END;
    DateTime* = RECORD (Date) hour*, minute*, second*, nanosecond*: LONGINT END;
    OffsetDateTime* = RECORD (DateTime) offset*: LONGINT END;   (* seconds east of UTC: -05:00 is -18000 *)
    Period* = RECORD years*, months*, days*: LONGINT END;
```

### 7.1 The types

- **`Date`, `TimeOfDay` and `DateTime` are civil.** They hold fields with
  no zone. They are Python's naive `date`/`time`/`datetime` and C++'s
  `year_month_day`, `hh_mm_ss` and `local_time`.
- **`OffsetDateTime`** is a civil date-time together with the offset that
  places it on the timeline. It is what an RFC 3339 string holds, and
  what `TimeZones.ToLocal` produces. It is Java's `OffsetDateTime`, and
  close to Ruby's `Time`.
- **The offset is in seconds east of UTC**, the sign ISO 8601 and RFC
  3339 write. C's `timezone` variable and POSIX `TZ` strings use the
  opposite sign; it is converted where they are read. Offsets are
  limited to ±25:59:59; the largest real one is +14:00.
- **The types extend one another** (Oberon-2 type extension):
  `OffsetDateTime` extends `DateTime`, which extends `Date`. So a
  `DateTime` can be passed wherever a `Date` is expected:
  `Calendar.DayOfWeek(dt)`, or `Calendar.AddMonths(dt, 1)` through a
  `VAR Date` parameter, which changes the date part and keeps the time.
  This is the one use of extension in the design. It replaces the
  `GetDate`/`SetDate` boilerplate that composition would need.
- **The fields are exported writable**, as C++'s `year_month_day` is
  writable and checked with `ok()`. A program can write `d.day := 1`, and
  `ValidDate(d)` tests the result. Procedures that take a civil value
  `ASSERT` that it is valid.
- **The calendar is the proleptic Gregorian** in astronomical numbering:
  year 0 is 1 BC and -43 is 44 BC. There is no Julian switch. The years
  are limited to `minYear .. maxYear`.

### 7.2 Procedures

```oberon
  (* the calendar's rules *)
  PROCEDURE IsLeapYear*(year: LONGINT): BOOLEAN;
  PROCEDURE DaysInMonth*(year, month: LONGINT): LONGINT;
  PROCEDURE DaysInYear*(year: LONGINT): LONGINT;

  (* construction and validity; FALSE leaves the result unchanged *)
  PROCEDURE SetDate*(VAR d: Date; year, month, day: LONGINT): BOOLEAN;
  PROCEDURE SetTimeOfDay*(VAR t: TimeOfDay; hour, minute, second, nanosecond: LONGINT): BOOLEAN;
  PROCEDURE SetDateTime*(VAR dt: DateTime; year, month, day, hour, minute, second, nanosecond: LONGINT): BOOLEAN;
  PROCEDURE ValidDate*(d: Date): BOOLEAN;
  PROCEDURE ValidTimeOfDay*(t: TimeOfDay): BOOLEAN;
  PROCEDURE ValidDateTime*(dt: DateTime): BOOLEAN;
  PROCEDURE ValidOffsetDateTime*(odt: OffsetDateTime): BOOLEAN;
  PROCEDURE Combine*(VAR dt: DateTime; d: Date; t: TimeOfDay);
  PROCEDURE GetTimeOfDay*(dt: DateTime; VAR t: TimeOfDay);

  (* day numbers: days since 1970-01-01, C++'s sys_days *)
  PROCEDURE DayNumber*(d: Date): HUGEINT;
  PROCEDURE FromDayNumber*(VAR d: Date; n: HUGEINT): BOOLEAN;   (* FALSE outside the years *)

  (* questions about a date *)
  PROCEDURE DayOfWeek*(d: Date): LONGINT;    (* Monday 1 .. Sunday 7 *)
  PROCEDURE DayOfYear*(d: Date): LONGINT;    (* 1 .. 366 *)
  PROCEDURE IsoWeek*(d: Date; VAR weekYear, week: LONGINT);   (* ISO 8601 week date *)
  PROCEDURE NthWeekday*(VAR d: Date; year, month, weekday, n: LONGINT): BOOLEAN;   (* n = -1: the last *)

  (* calendar arithmetic; a result outside the years is FALSE *)
  PROCEDURE AddDays*(VAR d: Date; n: HUGEINT): BOOLEAN;
  PROCEDURE AddMonths*(VAR d: Date; n: HUGEINT): BOOLEAN;    (* clamped: Jan 31 + 1 = Feb 28/29 *)
  PROCEDURE AddYears*(VAR d: Date; n: HUGEINT): BOOLEAN;     (* clamped: Feb 29 + 1 = Feb 28 *)
  PROCEDURE AddPeriod*(VAR d: Date; p: Period): BOOLEAN;     (* years and months together, then days *)
  PROCEDURE SubtractPeriod*(VAR d: Date; p: Period): BOOLEAN;
  PROCEDURE DaysBetween*(later, earlier: Date): HUGEINT;
  PROCEDURE PeriodBetween*(VAR p: Period; from, to: Date);   (* dateutil's relativedelta: AddPeriod(from, p) = to *)
  PROCEDURE CompareDates*(a, b: Date): INTEGER;
  PROCEDURE CompareDateTimes*(a, b: DateTime): INTEGER;      (* by the fields, not by an instant *)

  (* elapsed arithmetic on civil date-times, as if every day were 86 400 s (no zone) *)
  PROCEDURE AddDuration*(VAR dt: DateTime; d: Durations.Duration): BOOLEAN;
  PROCEDURE Difference*(later, earlier: DateTime): Durations.Duration;   (* saturating *)
  PROCEDURE CheckedDifference*(VAR d: Durations.Duration; later, earlier: DateTime): BOOLEAN;

  (* civil <-> instant at a known offset; no zone rules are involved *)
  PROCEDURE ToInstant*(odt: OffsetDateTime; VAR t: Instants.Instant);   (* saturating *)
  PROCEDURE CheckedToInstant*(VAR t: Instants.Instant; odt: OffsetDateTime): BOOLEAN;
  PROCEDURE FromInstant*(VAR odt: OffsetDateTime; t: Instants.Instant; offset: LONGINT);   (* saturating *)
  PROCEDURE CheckedFromInstant*(VAR odt: OffsetDateTime; t: Instants.Instant; offset: LONGINT): BOOLEAN;
  PROCEDURE ToUTCInstant*(dt: DateTime; VAR t: Instants.Instant);         (* dt read as UTC *)
  PROCEDURE FromUTCInstant*(VAR dt: DateTime; t: Instants.Instant);

  (* the Oberon system's packed clock (Platform.GetClock, Files.GetDate) *)
  PROCEDURE FromOberonClock*(VAR dt: DateTime; t, d: LONGINT): BOOLEAN;   (* years 00-99 read as 1970-2069 *)
  PROCEDURE ToOberonClock*(dt: DateTime; VAR t, d: LONGINT);
END Calendar.
```

### 7.3 Algorithms

- **`DayNumber` and `FromDayNumber`** are Howard Hinnant's
  `days_from_civil` and `civil_from_days`, the code behind C++20's
  `sys_days`. They are pure integer arithmetic on a 400-year era, and
  floored `DIV` makes their negative-year corrections unnecessary.
- **Everything else goes through the day number:**
  - `DayOfWeek` is `(n + 3) MOD 7 + 1`, since 1970-01-01 was a Thursday;
  - `DaysBetween` is a difference of day numbers;
  - `AddDays` is a day number and back.
- **`AddMonths`** works on `year * 12 + month - 1`, then clamps the day.
- **`AddPeriod`** adds `years * 12 + months` in one step, then the
  days, as Java's `Period.addTo` does.
- **`PeriodBetween`** counts whole months, then the days from where those
  months land, in both directions, as Python's `dateutil.relativedelta`
  does. Its `years`, `months` and `days` all have the same sign, and
  `AddPeriod(from, PeriodBetween(from, to)) = to` for every pair of
  dates. Java's `Period.between` is the same forward but not backward.
  See [calendar-periods.md](calendar-periods.md) (Q11).
- **`FromInstant`** can carry an instant within 26 hours of either end
  out of the years, as `Instants.latest` at +14:00 would be in 10000.
  It then saturates at the first or last moment of the years and keeps
  the offset, so the result names a different instant;
  `CheckedFromInstant` returns `FALSE` instead. See
  [instant-offsets.md](instant-offsets.md) (Q12).
- **`ToInstant`** can carry an `OffsetDateTime` in the first or last 26
  hours of the years past the instants, as -9999-01-01T00:00+01:00 is
  an hour before `Instants.earliest`. It then saturates at `earliest`
  or `latest`; `CheckedToInstant` returns `FALSE` instead, and is what
  `TimeZones.ToInstant`, `Resolve` and `TimeStrings.ReadInstant` use.
  See [offset-to-instant.md](offset-to-instant.md) (Q13).

### 7.4 Elapsed arithmetic on civil date-times

`AddDuration` and `Difference` let a program do elapsed arithmetic on
civil values that it knows are in UTC, or that never cross a zone
change. Python's naive arithmetic does the same. Their comments must say
plainly that across a daylight-saving change in a real zone they give
wall-clock answers, not elapsed ones. The way to get elapsed answers is
through `Instants` (section 6.3).

## 8. `TimeZones`

```oberon
MODULE TimeZones;
  IMPORT Calendar, Instants, Durations, TimePlatform, Files;
  CONST
    earlier* = 0; later* = 1; strict* = 2;   (* resolving a local time *)
    abbreviationLength* = 16;
  TYPE
    Info* = RECORD
      offset*: LONGINT;      (* seconds east of UTC *)
      isDst*: BOOLEAN;
      abbreviation*: ARRAY abbreviationLength OF CHAR   (* "EST", "+0530"; may be "" *)
    END;
    Zone* = POINTER TO ZoneDesc;
    ZoneDesc* = RECORD END;   (* abstract *)

  (* What a zone is: its offset at an instant, and its name. An extension of
     ZoneDesc that implements these two is a zone every procedure here takes. *)
  PROCEDURE (z: Zone) Lookup*(t: Instants.Instant; VAR info: Info);
  PROCEDURE (z: Zone) GetName*(VAR name: ARRAY OF CHAR);

  VAR utc-: Zone;
  PROCEDURE Local*(): Zone;                      (* the process's zone, as section 8.3 says *)
  PROCEDURE Fixed*(offset: LONGINT): Zone;      (* NIL if |offset| > 25:59:59 *)
  PROCEDURE Posix*(rule-: ARRAY OF CHAR; VAR z: Zone): BOOLEAN;   (* "EST5EDT,M3.2.0,M11.1.0" *)
  PROCEDURE Named*(name-: ARRAY OF CHAR; VAR z: Zone): BOOLEAN;   (* "America/New_York", from TZif *)
  PROCEDURE FromFile*(path-: ARRAY OF CHAR; VAR z: Zone): BOOLEAN;   (* a TZif file by its path *)

  PROCEDURE ToLocal*(z: Zone; t: Instants.Instant; VAR odt: Calendar.OffsetDateTime);
  PROCEDURE ToInstant*(z: Zone; dt: Calendar.DateTime; choice: INTEGER; VAR t: Instants.Instant): BOOLEAN;
  PROCEDURE Resolve*(z: Zone; dt: Calendar.DateTime; choice: INTEGER; VAR odt: Calendar.OffsetDateTime): BOOLEAN;
  PROCEDURE Now*(z: Zone; VAR odt: Calendar.OffsetDateTime);
  PROCEDURE Today*(z: Zone; VAR d: Calendar.Date);
END TimeZones.
```

### 8.1 Zones are objects

- **A zone is an object with a type-bound `Lookup`**, Oberon-2's own
  form of Python's `tzinfo` and Modula-3's opaque `TimeZone`.
- **Five kinds are built in:** UTC, fixed, local, POSIX and TZif. A
  program can add its own by extending `ZoneDesc`, for example a zone
  computed from a table it carries.
- **Only `Lookup` (instant → offset) has to be written.** `ToInstant`
  (local → instant) is generic: it tries the offsets in force a day
  before and a day after the local time, which is how C++ and Python
  implement it. So an extension gets correct gap and overlap handling
  for free.
- **`ToInstant` and `Resolve` return `FALSE`** for a local time whose
  instant would fall outside `Instants.earliest .. latest`. They go
  through `Calendar.CheckedToInstant`, not the saturating `ToInstant`
  (Q13).
- **Zones are on the heap and never change**, so they can be shared and
  kept. `Named` caches each zone it has read, by name.

### 8.2 Gaps and overlaps

These are the cases where `ToInstant` and `Resolve` need `choice`.

| local time | `earlier` | `later` | `strict` |
|---|---|---|---|
| exists once | that instant | that instant | that instant |
| **overlap** (clocks go back; 01:30 happens twice) | the first (DST) | the second (standard) | `FALSE` |
| **gap** (clocks go forward; 02:30 never happens) | read with the offset before the gap, so 02:30 EST = 03:30 EDT | the same | `FALSE` |

- **Overlaps** follow C++'s `choose::earliest`/`latest` and Python's
  `fold` = 0/1. `strict` follows C++'s exceptions, as a `FALSE`.
- **Gaps** follow Python and Java: shift forward by the gap's length.
  This was checked with Python on 2026-10-28: 2026-03-08 02:30 in New
  York becomes 07:30 UTC.

### 8.3 Where zone data comes from

**`Posix(rule)`** parses a POSIX `TZ` string:

- the forms `std offset [dst [offset] [,start[/time],end[/time]]]`;
- the `Jn`, `n` and `Mm.w.d` rules, which `Calendar.NthWeekday`
  computes;
- quoted names such as `<+0530>`;
- the RFC 8536 extensions: hours up to ±167, and DST all year.

This is portable code, with no file access.

**`Named(name)` and `FromFile(path)`** read TZif files, versions 1-4
(RFC 8536):

- They use the 64-bit data of a version 2+ file.
- Instants after the last transition use the file's footer, which is a
  POSIX rule.
- The directory comes from `TimePlatform.ZoneInfoDirectory`: `TZDIR`,
  or else `/usr/share/zoneinfo`, which all four of poc's Unix systems
  have.
- **`name` is refused** if it is absolute, empty, longer than 255
  characters, or contains `..` or a character outside `A-Za-z0-9/_+-`.
  A zone name often comes from user input, and must not reach outside
  the directory.
- Leap-second records are refused (section 6.2).
- **On VMS, `Named` always returns `FALSE`**, for simplicity (Q6,
  decided 2026-10-28). There is no zoneinfo directory there, and
  `TimePlatform.ZoneInfoDirectory` gives `""`. The reader itself is
  portable Oberon over `Files`, so `FromFile` still works on VMS for a
  program that brings its own TZif file.

**`Local()`**, decided per target by `TimePlatform` when it is first
called:

- **Unix:** it asks the C library, through `localtime_r` and
  `tm_gmtoff`/`tm_zone`. So the program agrees with every C program on
  the machine, whatever `TZ` or `/etc/localtime` says.
  - Its `GetName` is `TZ`'s value, or `/etc/localtime`'s target where
    that is a symbolic link, or else `"localtime"`.
  - A program that wants a zone it can name and hand on can call
    `Named` with the result.
  - *On 32-bit FreeBSD `time_t` is 32 bits.* There, and wherever
    `localtime_r` fails, the local zone answers from `/etc/localtime`
    read as TZif instead. The C part is compiled with
    `_TIME_BITS=64`, so 32-bit glibc gets a 64-bit `time_t`.
- **VMS 5.5-2:** the system clock is local time, and the system has no
  zone database.
  - If the logical name `TZ` translates to a POSIX rule, `Local()` is
    `Posix` of it.
  - VMS 5.5-2 has no logical name for the offset from UTC.
    `SYS$TIMEZONE_DIFFERENTIAL` is not defined there (Q7).
  - Otherwise `Local()` is `Fixed(0)`, named `"VMS"`, and `Clocks.Now`
    is then really local time, not UTC. The module's comment must say
    so.

### 8.4 What `TimeZones` does not do

- Historical changes before a zone's first transition use its first
  type, as `zdump` does.
- No Windows zone names.
- No locale-specific zone names.

## 9. `Clocks`

```oberon
MODULE Clocks;
  IMPORT Instants, Durations, TimePlatform;
  PROCEDURE Now*(VAR t: Instants.Instant);           (* the wall clock, UTC; can jump when the clock is set *)
  PROCEDURE Monotonic*(): Durations.Duration;        (* since an unspecified start; never decreases *)
  PROCEDURE Since*(start: Durations.Duration): Durations.Duration;   (* Monotonic() - start *)
  PROCEDURE ProcessTime*(): Durations.Duration;      (* CPU time used by this process *)
  PROCEDURE Sleep*(d: Durations.Duration);           (* at least d; d <= 0 returns at once *)
  PROCEDURE WallResolution*(): Durations.Duration;
  PROCEDURE MonotonicResolution*(): Durations.Duration;
END Clocks.
```

- **A monotonic reading is a `Duration`, not an `Instant`.** It has no
  meaning as a date, and making it a different type from `Instant`
  stops it from being formatted as one. Ada's `Real_Time.Time` and
  C++'s `steady_clock` make the same separation.
- **On Unix** the clocks are `clock_gettime`, with `CLOCK_REALTIME`,
  `CLOCK_MONOTONIC` and `CLOCK_PROCESS_CPUTIME_ID`, and `clock_getres`
  for the resolutions. `Sleep` is `nanosleep`, resumed after `EINTR`, as
  `Platform.Delay` is.
- **On VMS:**
  - `Now` is `SYS$GETTIM` (100 ns units counted from 1858-11-17,
    local), converted to UTC with the offset of the local zone. The
    clock ticks every 10 ms.
  - `Monotonic` is `EXE$GL_ABSTIM_TICS`, the 10 ms ticks since boot,
    read from user mode through `SYS.STB` and widened past its 497-day
    wrap within the process (Q8). Setting the clock does not change it.
    A `SYS$GETTIM` made non-decreasing would be no substitute. It jumps
    forward when the operator sets the clock forward, and stands still
    when the clock is set back, which VMS 5.5 sites do each autumn for
    daylight saving time. This needs poc 0.10.0's external variables.
  - `ProcessTime` is `$GETJPI` `JPI$_CPUTIM`, in 10 ms units.
  - `Sleep` is `Platform.Delay`, rounded up to milliseconds.

## 10. `TimeStrings`

### 10.1 Fixed formats: ISO 8601 extended format and RFC 3339

```oberon
MODULE TimeStrings;
  IMPORT Durations, Instants, Calendar;   (* and TimeZones, for FormatIn (10.2) *)
  CONST shortest* = -1;   (* digits: 0, 3, 6 or 9 fractional digits, the fewest that are exact *)

  (* output: appended at s's first 0X, as OutStr does *)
  PROCEDURE Date*(d: Calendar.Date; VAR s: ARRAY OF CHAR);                            (* 2026-10-28 *)
  PROCEDURE TimeOfDay*(t: Calendar.TimeOfDay; digits: INTEGER; VAR s: ARRAY OF CHAR);   (* 14:05:09.5 *)
  PROCEDURE DateTime*(dt: Calendar.DateTime; digits: INTEGER; VAR s: ARRAY OF CHAR);    (* 2026-10-28T14:05:09 *)
  PROCEDURE OffsetDateTime*(odt: Calendar.OffsetDateTime; digits: INTEGER; VAR s: ARRAY OF CHAR);   (* ...-04:00, Z for 0 *)
  PROCEDURE Instant*(t: Instants.Instant; digits: INTEGER; VAR s: ARRAY OF CHAR);       (* 2026-10-28T18:05:09Z *)
  PROCEDURE Duration*(d: Durations.Duration; VAR s: ARRAY OF CHAR);                    (* PT1H30M, -PT0.5S, PT0S *)
  PROCEDURE Elapsed*(d: Durations.Duration; digits: INTEGER; VAR s: ARRAY OF CHAR);    (* 26:03:04.5, -0:00:01 *)
  PROCEDURE Period*(p: Calendar.Period; VAR s: ARRAY OF CHAR);                          (* P1Y2M3D, P0D *)

  (* input: from s[pos]; TRUE moves pos past the text, as InStr does *)
  PROCEDURE ReadDate*(VAR d: Calendar.Date; s-: ARRAY OF CHAR; VAR pos: LONGINT): BOOLEAN;
  PROCEDURE ReadTimeOfDay*(VAR t: Calendar.TimeOfDay; s-: ARRAY OF CHAR; VAR pos: LONGINT): BOOLEAN;
  PROCEDURE ReadDateTime*(VAR dt: Calendar.DateTime; s-: ARRAY OF CHAR; VAR pos: LONGINT): BOOLEAN;
  PROCEDURE ReadOffsetDateTime*(VAR odt: Calendar.OffsetDateTime; s-: ARRAY OF CHAR; VAR pos: LONGINT): BOOLEAN;
  PROCEDURE ReadInstant*(VAR t: Instants.Instant; s-: ARRAY OF CHAR; VAR pos: LONGINT): BOOLEAN;   (* needs an offset or Z *)
  PROCEDURE ReadDuration*(VAR d: Durations.Duration; s-: ARRAY OF CHAR; VAR pos: LONGINT): BOOLEAN;
  PROCEDURE ReadPeriod*(VAR p: Calendar.Period; s-: ARRAY OF CHAR; VAR pos: LONGINT): BOOLEAN;
```

**Output:**

- **Years before `0000`** are written in ISO 8601's expanded form,
  `-0044`, a sign and four digits, by agreement as the standard
  requires. RFC 3339 allows only `0000 .. 9999`; a program that must
  produce RFC 3339 keeps to that range. `Calendar.maxYear` is 9999, so
  no `+` year is written.
- **A fraction is cut, not rounded**, so that `23:59:59.9999` with 3
  digits stays in its second, its minute and its day.
- **`shortest`** writes 0, 3, 6 or 9 digits for the date-times, as
  Java's `LocalTime.toString` does, but `Duration` strips every
  trailing zero (`PT0.5S`), as Java's `Duration.toString` does.
- **An offset** is `Z` for 0, `±hh:mm` otherwise, and `±hh:mm:ss`
  when it has seconds, as Python writes it (Q15).
- **`Duration` writes hours, minutes and seconds only**: 26 hours is
  `PT26H`, never `P1DT2H`, because a `Duration`'s day is not a calendar
  day. Java's `Duration.toString` does the same.
- **`Period`** writes a leading `-` when every nonzero field is
  negative (`-P1M`), and a `-` on each negative field when the signs
  are mixed (`P1Y-2M`). Zero is `P0D` (Q16).
- **`Elapsed`** is the clock style, `[-]h:mm:ss[.f]`, with the hours
  unbounded. It avoids Python's `"-1 day, 23:59:59"`.

**Input:**

- **The date-time readers** take the extended format, the RFC 3339
  profile and ISO 8601's lower-case `t`/`z`. Between the date and the
  time they also take a space, which RFC 3339 allows.
- They take 1-9 fractional digits, and the offsets `Z`, `±hh:mm` and
  `±hh`, and `±hh:mm:ss` (Q15), up to 25:59:59. `-00:00` is read as 0.
- **They are strict**, so that text which is not a time is less likely
  to be read as one:
  - nothing is skipped before the text;
  - the seconds are required (`14:05` is refused), and the fraction
    takes `.` only, not the comma ISO 8601 also allows;
  - each field has exactly its width, with a year of four digits after
    an optional `-`; `+` years and `-0000` are refused;
  - text followed at once by a digit is refused, so that `+0530` is not
    read as `+05` and `2026-10-289` is not read as a date. Anything
    else may follow: `2026-10-28T14:05` read as a date ends before the
    `T`, and `14:05:09,5` read as a time ends before the comma.
  - `ReadDuration` and `ReadPeriod` take the designators in upper case
    only.
- **`ReadInstant` refuses** a time whose instant falls outside
  `Instants.earliest .. latest`, such as `-9999-01-01T00:00:00+01:00`.
  It goes through `Calendar.CheckedToInstant` (Q13).
- **The basic format (`20261028T140509Z`) is not read**, so that a
  malformed string is less likely to be read as something (Q3, decided
  2026-10-28). A program that needs it can use a pattern such as
  `%Y%m%dT%H%M%S%z`.
- **A second of `60`** is accepted only by `ReadOffsetDateTime`,
  `ReadInstant` and `Parse` with an offset, and only where the UTC time
  is 23:59:60 on the last day of a month. It is read as `59.999999999`.
  Everywhere else it is refused. The rule and the reasons are in
  [leap-seconds.md](leap-seconds.md).
- **`ReadDuration`** takes:
  - the ISO form `[-]P[nW][nD][T[nH][nM][n[.f]S]]`, with `D` read as
    exactly 24 hours and `W` as 7 days, as Java's `Duration.parse` reads
    them;
  - the `Elapsed` form.
  
  It refuses `Y` and `M` before the `T`. Those are calendar units, read
  by `ReadPeriod` (`P1Y2M3W4D`).
- **`ReadPeriod`** takes a leading `-` and a `-` on any field; a
  field's `-` after a leading one cancels it, so `-P1Y-2M` is -1 years
  and +2 months, as Java's `Period.parse` reads it (Q16).

### 10.2 Patterns

```oberon
  (* output of odt by pattern; abbreviation is %Z's text *)
  PROCEDURE Format*(pattern-: ARRAY OF CHAR; odt: Calendar.OffsetDateTime;
                    abbreviation-: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);
  PROCEDURE FormatIn*(pattern-: ARRAY OF CHAR; t: Instants.Instant; z: TimeZones.Zone;
                      VAR s: ARRAY OF CHAR);   (* ToLocal, then Format with the zone's abbreviation *)

  (* input by pattern; given tells which fields the text supplied *)
  CONST   (* elements of given *)
    yearGiven* = 0; monthGiven* = 1; dayGiven* = 2; hourGiven* = 3; minuteGiven* = 4;
    secondGiven* = 5; fractionGiven* = 6; offsetGiven* = 7; weekdayGiven* = 8;
  PROCEDURE Parse*(pattern-: ARRAY OF CHAR; VAR odt: Calendar.OffsetDateTime; VAR given: SET;
                   s-: ARRAY OF CHAR; VAR pos: LONGINT): BOOLEAN;
END TimeStrings.
```

**The directives** are C's `strftime`, with GNU's and Ruby's extensions
where the C directives are not enough:

| | |
|---|---|
| `%Y %C %y %G %g` | year; century; 2-digit year; ISO week-year, full and 2-digit |
| `%m %B %b %h` | month 01-12; `October`; `Oct`; `Oct` |
| `%d %e %j` | day 01-31; day with a leading space; day of year 001-366 |
| `%H %I %k %l %M %S %p %P` | hour 00-23 and 01-12, the same space-padded; minute; second; `AM`/`PM`, `am`/`pm` |
| `%N %3N %6N %9N` | fractional seconds: 9 digits, or as many as given (Ruby, GNU `date`) |
| `%A %a %u %w %V %U %W` | `Wednesday`; `Wed`; ISO weekday 1-7; weekday 0-6 from Sunday; ISO week; week from Sunday or Monday |
| `%z %:z %::z %Z` | `-0400`; `-04:00`; `-04:00:00`; the abbreviation |
| `%s` | Unix seconds |
| `%F %T %R %D %c %x %X` | `%Y-%m-%d`; `%H:%M:%S`; `%H:%M`; `%m/%d/%y`; and the C locale's `%a %b %e %H:%M:%S %Y`, `%m/%d/%y`, `%H:%M:%S` |
| `%n %t %%` | line feed; tab; `%` |
| flags `- _ 0 ^` | no padding; pad with spaces; pad with zeros; upper case (glibc, Ruby) |

**Rules:**

- **`%Y` writes at least four digits**, after a `-` for a negative
  year: `0044`, `-0044`, as `Date` writes them (Q18). `%C`, `%y`, `%G`
  and `%g` are floored: -44 gives `-1`, `56`.
- **`%z` and `%:z` write an offset's seconds when it has them**,
  `-002521` and `-00:25:21`, as Python does (Q21). `Parse`'s `%z`
  takes `Z`, `±hh`, `±hhmm`, `±hhmmss` and the forms with colons.
- **Flags** (`-`, `_`, `0`, `^`) come before any directive; `^` is
  the only one that changes a name or `%c`. A width is taken only by
  `%N` (1..9 digits), colons only by `%z`. `Parse` reads the flags and
  ignores them, except that `_` lets a number start with spaces.
- **Names are English only.** There is no locale (lesson 10).
- **An unknown directive** is written as it stands by `Format`, as glibc
  does, and makes `Parse` return `FALSE`.
- **`Parse` reads its directives strictly:**
  - numbers no wider than the directive's own width;
  - names in either case, full or abbreviated;
  - literal characters exactly;
  - a blank in the pattern matches any run of blanks, as `strptime`'s
    does.
- **`Parse` fills only what the text gives** and records what it filled
  in `given`. Every other field is 2000-01-01T00:00:00, offset 0; 2000
  is a leap year, so a month and day without a year, such as syslog's
  `Feb 29`, can always be read (Q20).
  - Like Ruby's `_strptime`, this lets the program decide what a missing
    field means. C's `strptime` instead leaves missing fields as they
    were, and Python defaults them to 1900.
  - `%Z` takes an offset only from a name with one meaning: `UTC`,
    `UT`, `GMT` or `Z` gives 0, and `+0530` or `-03` its own. Any other
    name is read and skipped (Q19).
  - `%s` sets every field, and overrides any other date or time.
  - `%G`/`%V`/`%u` together set the date; without `%u` it is the
    week's Monday. `%j` with a year sets the month and day. Either
    marks the year, month and day as given.
  - `%I` or `%l` with `%p` sets the hour, which must agree with `%H`.
  - `%z` and an offset from `%Z` must agree.
  - A second of 60 is read only with an offset, and only where UTC is
    at 23:59:60 on a month's last day, as `ReadOffsetDateTime` reads
    it (section 6.2).
  - A day of the week, `%V`, `%U` or `%W` that disagrees with the date
    fails, when the text gives the whole date; without it the date is
    not the text's to check. `%U` and `%W` are only checked.
  - `%y` reads 69-99 as 19xx and 00-68 as 20xx, POSIX's pivot.

## 11. `TimePlatform`, the per-target module

```oberon
MODULE TimePlatform;   (* internal: for Clocks and TimeZones *)
  PROCEDURE WallClock*(VAR seconds: HUGEINT; VAR nanosecond: LONGINT);   (* UTC, POSIX time *)
  PROCEDURE MonotonicNanoseconds*(): HUGEINT;
  PROCEDURE ProcessNanoseconds*(): HUGEINT;
  PROCEDURE WallResolution*(): HUGEINT;
  PROCEDURE MonotonicResolution*(): HUGEINT;
  PROCEDURE Sleep*(nanoseconds: HUGEINT);
  PROCEDURE SystemLocal*(): BOOLEAN;   (* whether LocalOffset is the system's own *)
  PROCEDURE LocalOffset*(seconds: HUGEINT; VAR offset: LONGINT; VAR isDst: BOOLEAN;
                         VAR abbreviation: ARRAY OF CHAR): BOOLEAN;
  PROCEDURE LocalZoneName*(VAR name: ARRAY OF CHAR);
  PROCEDURE LocalRule*(VAR rule: ARRAY OF CHAR): BOOLEAN;   (* VMS: the TZ logical's translation *)
  PROCEDURE ZoneInfoDirectory*(VAR dir: ARRAY OF CHAR);
END TimePlatform.
```

- **`src/llvm/TimePlatform.Mod` with `TimePlatform.c`.** This is
  `Platform.c`'s approach: the C part is compiled for the target against
  the system's own headers. Those headers know `struct timespec`, `struct
  tm`, `tm_gmtoff`, and NetBSD's renamed `__clock_gettime50` and
  `__localtime_r50`. The C interface uses fixed-width types only
  (`int32_t`, `int64_t`), so it means the same under `-O2` and `-OC`.
  Its names start with `TimePlatform.-`, so no Oberon name can collide
  with them.
- **`src/vax/TimePlatform.Mod`** uses `["VMS"]` calls through `STARLET`
  (`SYS$GETTIM`, `SYS$GETJPIW`, `SYS$TRNLNM`), from the `VMSDEF` library.
  - The offset from the VMS epoch is 3 506 716 800 s: 40 587 days from
    1858-11-17 to 1970-01-01.
  - It needs `POCRTL` and `VMSDEF`, not `VMSLIB`.
  - Facts about VMS come from the VAX/VMS 5.5-2 manuals only, as
    Peaseblossom's `AGENTS.md` requires.
### 11.1 `VmsInstants`, VAX only

This module converts between `VMSLIB`'s `DateTimes.Time` and this
library's types, for programs that use both. It is in the first VAX
version (Q9, decided 2026-10-28).

```oberon
MODULE VmsInstants;   (* VAX only: src/vax/ *)
  IMPORT DateTimes, Durations, Instants, TimeZones;

  (* absolute times: a DateTimes.Time is local time, as SYS$GETTIM gives it *)
  PROCEDURE ToInstant*(t: DateTimes.Time; choice: INTEGER; VAR i: Instants.Instant): BOOLEAN;
  PROCEDURE FromInstant*(VAR t: DateTimes.Time; i: Instants.Instant): BOOLEAN;

  (* delta times: a DateTimes.Time below zero *)
  PROCEDURE ToDuration*(t: DateTimes.Time; VAR d: Durations.Duration): BOOLEAN;
  PROCEDURE FromDuration*(VAR t: DateTimes.Time; d: Durations.Duration): BOOLEAN;
END VmsInstants.
```

**The time zone.** A VMS absolute time is local, so both directions go
through `TimeZones.Local()`, the same zone `Clocks.Now` uses (§8.3). As a
result, `VmsInstants.FromInstant` of `Clocks.Now` agrees with
`DateTimes.Now()` to within the clock's 10 ms tick.

**`ToInstant`:**
- resolves the local time with `choice`, as `TimeZones.ToInstant` does;
- returns `FALSE` for a delta time, for a year past 9999, and for a
  `strict` choice that meets a gap or an overlap.

**`FromInstant`** returns `FALSE` for an instant before
1858-11-17 00:00 local, which VMS cannot represent.

**Deltas:**
- `ToDuration` gives a positive `Duration` for a delta time, and returns
  `FALSE` for an absolute time.
- `FromDuration` gives a delta time, truncated to 100 ns. It returns
  `FALSE` for a duration shorter than 100 ns, since a zero quadword is
  not a delta time.

**What it needs:**
- It is the only module in the library that needs `VMSLIB`.
- Programs that import it must link `VMSLIB` as well.
- `DateTimes.Format` (`LIB$FORMAT_DATE_TIME`) works on its results; see
  Q10.

## 12. Build, tests and order of work

### 12.1 Layout

```
src/            Durations Instants Calendar TimeZones Clocks TimeStrings (.Mod)
src/llvm/       TimePlatform.Mod TimePlatform.c
src/vax/        TimePlatform.Mod VmsInstants.Mod
test/           one test program per module, expected output beside it
test/data/      reference tables generated by Python (tools/), checked in
examples/       small programs for the README
GNUmakefile     all, check, check-o2, check-oc, install, vax
```

### 12.2 Building

- **LLVM:** `poc -library podatetime src/llvm/TimePlatform.Mod
  src/*.Mod`, once for each size model. `poc -install-library
  podatetime` installs it.
- **VAX:** the same command with `-target vax-dec-vms` and
  `src/vax/TimePlatform.Mod`, giving `PODATETIME.OLB` and a shareable
  image, as Peaseblossom's Phase 17 libraries are built.

### 12.3 Tests

- **Exhaustive:** `DayNumber`/`FromDayNumber` round-trip every day from
  -9999-01-01 to 9999-12-31, about 7.3 million days, which takes
  seconds.
- **Reference tables generated by Python's `datetime` and `zoneinfo`,**
  and checked in so that the tests need no Python on the BSDs or the
  VAX:
  - day of the week and ISO week for a sample of dates;
  - `ToLocal` and `ToInstant` around every transition of a handful of
    zones, 1970-2040: New York, London, Lord Howe (a 30-minute DST),
    Kolkata, Chatham, Apia (the skipped day), Casablanca (negative DST)
    and Dublin.
  - The offset and abbreviation come from `zoneinfo`, which must agree
    with glibc's `localtime`; the daylight saving flag comes from glibc,
    for `zoneinfo` has none.
  - POSIX rules are checked against glibc's `localtime` with `TZ` set to
    the rule, not against `zoneinfo`, which counts `Jn` wrongly in leap
    years, counts `n` from 1, and reads a rule in the year of UTC.
    glibc uses no rule before 1970 and also reads a rule in the year of
    UTC, so the tests check earlier years by the 400-year cycle, leave
    out the hours at a year's edge where the two years differ, and
    check some of those by hand.
  - The zone tables are made from TZif files checked in under
    `test/data/zoneinfo/`, in both zic's fat and slim forms, with a
    few made-up files for version 1, version 4, leap-second records and
    damage. The system's own database is checked only for facts every
    tzdata version agrees on (Q17).
- **Self-checking:** every string procedure is tested by writing a value
  and reading it back, and by a table of strings that must be refused.
- **Against the system:** `Format` is compared with the C library's
  `strftime` in the C locale for every directive the two share.
- **Where they run:** under `-O2` and `-OC` on atla, and on the BSD VMs
  that Peaseblossom's `make check` uses. On the SIMH VAX they run once
  the VAX target exists.

### 12.4 Order of work

Each step is reviewed before the next one starts.

1. `Durations`, `Instants` and `Calendar`: pure code, no I/O, with the
   tests in 12.3.
2. `TimePlatform` (LLVM) and `Clocks`.
3. `TimeStrings`, fixed formats (10.1).
4. `TimeZones`: UTC, `Fixed`, `Posix`, the system's `Local`, then the
   TZif reader with `Named`.
5. `TimeStrings`, patterns (10.2).
6. `TimePlatform` and `VmsInstants` for the VAX, and the whole test suite
   on VAX/VMS 5.5-2.

## 13. Open questions for review

- **Q1.** Is `Calendar` the right name for the civil module, or should it
  be `CivilTimes`, to avoid colliding with a user's module? *Decided
  2026-10-28: `Calendar` is safe and stays.*
- **Q2.** Should an `Instant` have nanosecond resolution and a range
  limited to years ±9999, as proposed, or a wider range? *Decided
  2026-10-28: as proposed. Nanoseconds, and the range tied to
  `Calendar.minYear .. maxYear`, so that converting an instant to a date
  cannot fail. Widening the years later changes only those constants and
  the tests.*
- **Q3.** Should the readers also take ISO 8601's basic format
  (`20261028T140509Z`)? It is cheap to add, but makes a malformed string
  more likely to be read as something. *Decided 2026-10-28: no. The
  readers take the extended format only, so that malformed strings are
  less likely to be read as something.*
- **Q4.** Should `Durations` saturate (proposed), or `ASSERT` on
  overflow? *Decided 2026-10-28: the procedures that return a result
  saturate, and checked forms with `BOOLEAN` results are added where
  overflow can come from input. The options and the reasons are in
  [duration-overflow.md](duration-overflow.md).*
- **Q5.** Should leap seconds be modelled in any way, for example with a
  `utc_clock`-style conversion? The proposal is no. *Decided
  2026-10-28: they are not modelled. The timestamp readers accept `:60`
  where a leap second can occur, and read it as `:59.999999999`. A
  `LeapSeconds` module is possible future work, not planned. See
  [leap-seconds.md](leap-seconds.md).*
- **Q6.** On VMS, should `Named` be offered, reading TZif files a site
  copies to a directory named by a logical name, or should it be left
  out? *Decided 2026-10-28: left out, for simplicity. `Named` returns
  `FALSE` on VMS, and `FromFile` still works (§8.3).*
- **Q7.** Does VAX/VMS 5.5-2 define `SYS$TIMEZONE_DIFFERENTIAL`, or did
  it arrive with DECdts or OpenVMS 6? This has to be checked against the
  5.5-2 manuals. If it is absent, only the `TZ` logical and `Fixed(0)`
  remain. *Checked 2026-10-28 on the VAX guest (VMS V5.5-2H4, the
  `claude` account), and found absent:*
  - *`F$TRNLNM` and `SHOW LOGICAL` find no `SYS$TIMEZONE_DIFFERENTIAL`.*
  - *`SHOW LOGICAL/TABLE=*` finds no name containing `TIMEZONE`, `TDF`,
    `DTSS`, `UTC` or `TZ`, except `ST_TIMEZONE` = `"EDT"` in
    `LNM$SYSTEM_TABLE`. That comes from the LBL Software Tools installed
    on this VAX, not from VMS. It is a zone abbreviation, not an offset,
    and is not used.*
  - *`SYS$MANAGER`, `SYS$STARTUP` and `SYS$SYSTEM` have no `UTC`,
    `TDF`, `TIMEZONE` or `DTSS` files.*
  - *The system help library, `HELPLIB.HLB`, never mentions `TIMEZONE`
    or a time differential.*
  
  *So `Local()` on VMS is the `TZ` logical's rule, or else `Fixed(0)`
  (§8.3). The printed 5.5-2 manuals have not been searched. The
  evidence is the 5.5-2 system and its own help library.*
- **Q8.** On VMS, is there a non-decreasing clock better than a clamped
  `SYS$GETTIM`, such as `EXE$GL_ABSTIM_TICS` through `SYS.STB`, that an
  unprivileged program can read? *Decided 2026-10-28: yes. `Monotonic`
  on VMS reads `EXE$GL_ABSTIM_TICS`, as proposed below. It is to be
  implemented once poc 0.10.0, which allows external variables, is
  installed. The research:*
  - *Why the clamp is poor.* `$SETIME` (`SET TIME`) needs OPER and
    LOG_IO. *Introduction to VMS 5.5 System Services* §10.8 gives
    "changes between standard time and daylight savings time" as a
    reason to call it. So on 5.5 a clamped `SYS$GETTIM` stands still for
    an hour every autumn.
  - *What 5.5 offers.* The *VMS 5.5 System Services Reference Manual*
    has `$GETTIM` with one argument, updated every 10 ms, and
    `SYI$_BOOTTIME`, which is a time of day and so is no better. The 5.5
    *New Features* manual and the 5.5 and 5.5-2 release notes add
    nothing on clocks. `LIB$STAT_TIMER`'s elapsed time (*LIB$ manual*,
    5.0, Table 2-10) is a system-time difference, so it is no better.
  - *Newer VMS* (VSI's *System Services Reference Manual*, as on
    docs.vmssoftware.com). `$GETTIM` has a `flags` argument there, and
    `flags` = 1 gives 100 ns units since boot that `$SETIME` does not
    change. The argument is passed "by value (Alpha and Integrity
    servers)" only. `$GETTIM_PREC` and `$GETUTC` are newer too. None of
    these is in the 5.5 manuals, so none can be used.
  - *The cell* (*VMS Internals and Data Structures*, 5.2):
    - §11.3.2: `EXE$GL_ABSTIM_TICS` counts 10 ms ticks since boot. The
      interval-timer interrupt increments it, and it is "never
      adjusted". `$SETIME` adjusts `EXE$GQ_SYSTIME` only.
    - App. C.1.3: it is defined in `SYSTEM_DATA_CELLS`, in the base
      image `SYS.EXE`. Table F.2 gives the base image's pages UR and
      URKW, so user mode can read it.
    - §29.6: an image linked with `SYS.STB` records the version of each
      executive category it uses. If a category's major ID differs from
      the running system's, activation fails with `SS$_SYSVERDIF`
      (5.2 on).
  - *Checked on the VAX guest* (V5.5-2H4, the `claude` account): a
    MACRO-32 program linked with `SYS$SYSTEM:SYS.STB/SELECTIVE_SEARCH`
    read the cell in user mode with no privileges. It read 699926 and
    then, one second later, 700026. Its image depends only on
    `SYS$K_STABLE` (1.80), so it needs relinking only if that
    category's major ID changes.
  - *In poc 0.9.0*, `VAR ["VMS", …]` and `VAR ["C", …]` are refused for
    `vax-dec-vms`, so there is no external variable. A
    `PROCEDURE ["VMS", "EXE$GL_ABSTIM_TICS"]` declaration does work:
    `SYSTEM.VAL(SYSTEM.ADDRESS, P)` is compiled as
    `MOVAB G^EXE$GL_ABSTIM_TICS`, and `SYSTEM.GET` then reads the cell.
    This was checked with `-emit-macro32` only, not built or run. It is
    not used: the implementation waits for poc 0.10.0, which declares
    the cell as an external variable.
  - *The proposal.* `Monotonic` on VMS reads `EXE$GL_ABSTIM_TICS` and
    multiplies by 10 ms. The cell is an unsigned longword, so it wraps
    after about 497 days, and `TimePlatform` keeps a wrap count. That
    holds if the process calls `Monotonic` at least once every 497
    days. `MonotonicResolution` is 10 ms. The clamped `SYS$GETTIM`
    remains the fallback.
  - *To check when it is implemented:*
    - whether poc can link a program with `SYS.STB`, for example
      through `-link` or a library's manifest, and so whether every
      program that imports `Clocks` will be linked with it;
    - whether tying `Clocks` to `SYS.STB` is acceptable. A program built
      on 5.5-2 may refuse to start on a VMS whose `STABLE` category has
      a different major ID.
- **Q9.** Should `VmsInstants` (section 11) be in the first VAX
  version? *Decided 2026-10-28: yes. Its interface is in §11.1.*
- **Q10.** Should the patterns also take VMS's `LIB$FORMAT_DATE_TIME`
  directives (`!Y4-!MN0-!D0`), for programs ported from VMS? The
  proposal is no: `%` only. *Decided 2026-10-28: no. A VMS program that
  needs VMS's directives uses `LIB$FORMAT_DATE_TIME` directly, through
  `DateTimes.Format`, with `VmsInstants.FromInstant` to get the time.*
- **Q11.** In what order does `AddPeriod` apply a period's years, months
  and days, and how does `PeriodBetween` measure one? Found during step
  1: "years, then months, then days" can clamp the day twice, and Java's
  backward `Period.between` does not always lead back, so either breaks
  `AddPeriod(from, PeriodBetween(from, to)) = to`. *Decided 2026-10-28:
  the years and months go in together, then the days; `PeriodBetween`
  counts whole months, then takes the days from where they land, in
  both directions, as `dateutil.relativedelta` does. The options and the
  reasons are in [calendar-periods.md](calendar-periods.md).*
- **Q12.** What does `FromInstant` do when the offset carries the civil
  time outside the years? Found during step 1: the instants cover the
  years read as UTC, so at an offset the last and first 26 hours of
  them have no civil time. *Decided 2026-10-28: `FromInstant`
  saturates at the first or last moment of the years, keeping the
  offset, as the library's other plain procedures saturate (Q4); a new
  `CheckedFromInstant` returns `FALSE`. The options and the reasons are
  in [instant-offsets.md](instant-offsets.md).*
- **Q13.** What does `ToInstant` do when the offset carries a valid
  `OffsetDateTime` outside the instants? Found during step 1; the
  converse of Q12. *Decided 2026-10-28: `ToInstant` saturates at
  `Instants.earliest` or `latest`; a new `CheckedToInstant` returns
  `FALSE`, and `TimeZones.ToInstant`, `Resolve` and
  `TimeStrings.ReadInstant` use it, so that they refuse such times. The
  options and the reasons are in
  [offset-to-instant.md](offset-to-instant.md).*
- **Q14.** Which units does `Instants.Truncate` take? Found during step
  1: an instant in nanoseconds needs 69 bits, and the first version
  took only units that divide a second or are whole seconds, trapping
  on 7 ms or 1.5 s. *Decided 2026-10-28: any positive unit; the others
  have their remainder found from the two fields, multiplying modulo
  the unit, and are checked against a table from Python's integers. The
  options and the reasons are in
  [instant-truncation.md](instant-truncation.md).*
- **Q15.** How are offsets with seconds written and read? Found during
  step 3: `Calendar` allows any offset up to ±25:59:59, and tzdb's local
  mean times have seconds (Amsterdam +00:19:32 until 1937), but RFC 3339
  and ISO 8601 have no seconds in an offset. *Decided 2026-10-28:
  `±hh:mm:ss` is written when the seconds are nonzero and read, as
  Python does, so that every `OffsetDateTime` is written exactly and
  read back. Such a string is not RFC 3339, but it arises only for
  historical zones, and every RFC 3339 string is still read. Rounding
  the offset would name a different instant; writing UTC would lose
  the local time.*
- **Q16.** How are periods with mixed signs written? Found during step
  3: a `Calendar.Period`'s fields each have their own sign, and ISO
  8601 has no negative periods. *Decided 2026-10-28: a leading `-` when
  every nonzero field is negative, as `Duration` writes `-PT0.5S` and
  ISO 8601-2 writes negatives; a `-` on each negative field otherwise,
  as Java writes them all. The reader takes both, and Java's output, so
  every `Period` is written and read back. Java's per-field signs
  throughout read less naturally; refusing mixed signs would leave
  valid `Period`s that cannot be written.*
- **Q17.** What zone data do the TZif tests read? Found during step 4:
  the hosts' databases differ (2026c fat on atla, 2023c on OpenBSD,
  2026c slim on NetBSD, 2026b on FreeBSD), and Casablanca's
  transitions differ between them. *Decided 2026-10-28: the tables'
  own TZif files are checked in under `test/data/zoneinfo/`, fat and
  slim, made with `zic`, with made-up files for the edge cases; the
  tables come from Python's `ZoneInfo.from_file` on those files. Every
  host, and later the VAX, then gives the same results, and a tzdata
  update cannot break the tests. The system's database is checked only
  for facts all versions agree on. Reading it with tables limited to
  agreed years would break at the next tzdata release; making the
  tables at test time needs Python, which NetBSD and the VAX lack.*
- **Q18.** How does `%Y` write years before 1000 and negative years?
  Found during step 5: glibc writes year 44 as `44` and -44 as `-44`,
  Ruby as `0044` and `-0044`. *Decided 2026-10-28: at least four
  digits, after a `-` for a negative year, as Ruby and ISO 8601's
  expanded form write them, so that `%F` gives what `Date` gives and
  `Parse` can read `%Y%m%d`; `%-Y` gives glibc's form. `Parse` reads
  up to four digits after an optional `-`. `%C`, like every number
  but `%Y` and `%G`, counts its sign toward its two places, as glibc
  and Ruby write it, so `%C%y` reads `-156` back as -44, but `%C`
  alone reads only -9..99.
  `%C`, `%y`, `%G` and `%g` are floored, as both write them. The
  comparison with `strftime` covers `%Y`, `%F`, `%G` and `%c` for the
  years 1000..9999 only.*
- **Q19.** What does `Parse` do with `%Z`? Found during step 5: an
  abbreviation does not always name one offset (`IST` is India, Israel
  or Ireland). glibc skips it, Ruby looks it up in a table, Python takes
  `UTC`, `GMT` and the local zone's names only. *Decided 2026-10-28:
  `%Z` reads letters, or a sign and digits, at most 15 characters.
  `UTC`, `UT`, `GMT` and `Z`, in either case, give offset 0, and a
  numeric abbreviation such as `+0530` or `-03` its own offset; both set
  `offsetGiven`. Any other name is read and skipped, as glibc does.
  Ruby's table would give a wrong offset silently for an ambiguous name;
  refusing `%Z` would leave `Format`'s output unreadable by its own
  pattern.*
- **Q20.** What does `Parse` do when the text gives no year? Found
  during step 5: with 1970 for a missing year, `02-29` read by `%m-%d`
  is refused, as Python's 1900 refuses it (cpython issue 70647), and
  `Mon 10-28` read by `%a %m-%d` fails, since 1970-10-28 was a
  Wednesday. *Decided 2026-10-28: a missing year is 2000, a leap year,
  so that every month and day that exists in some year is read; the
  other fields not given stay -01-01T00:00:00, offset 0. A weekday,
  `%V`, `%U` and `%W` are checked against the date only when the text
  gives all of it: a year, month and day, a year and `%j`, or a week
  date. Keeping
  1970 leaves syslog's `Feb 29` unreadable; 1972 for February 29 alone
  makes the default depend on the text; Ruby's current year makes
  `Parse` depend on the clock.*
- **Q21.** How do `%z` and `%:z` write an offset with seconds? Found
  during step 5: glibc, GNU `date` and Ruby drop the seconds, writing
  Dublin's -00:25:21 as `-0025` and `-00:25`, and keep them only in
  `%::z`; Python writes `-002521` and `-00:25:21`. *Decided 2026-10-28:
  the seconds are written when they are nonzero, as Python writes them
  and as Q15 decided for the fixed formats, so that `Format` never
  writes an instant it does not hold and `Parse` reads it back. `%::z`
  always writes them. Such offsets are historical only; the comparison
  with `strftime` leaves them out. `Parse`'s `%z` reads `Z`, `±hh`,
  `±hhmm`, `±hhmmss`, `±hh:mm` and `±hh:mm:ss`.*
