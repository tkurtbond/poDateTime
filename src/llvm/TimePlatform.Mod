MODULE TimePlatform;

  (* The operating system's part of the library, for LLVM (design section
     11): the clocks, in nanoseconds. Internal: programs use Clocks. The
     work is in TimePlatform.c beside this file, compiled by clang for the
     target from the system's own headers, under names that start with
     "TimePlatform.-".

     The local zone's part of the interface (SystemLocal, LocalOffset,
     LocalZoneName, LocalRule, ZoneInfoDirectory) comes with TimeZones,
     step 4 of design 12.4. *)

  IMPORT SYSTEM;

  PROCEDURE ["C", "TimePlatform.-wall-clock"] CWallClock(seconds, nanosecond: SYSTEM.ADDRESS);
  PROCEDURE ["C", "TimePlatform.-monotonic"] CMonotonic(): SYSTEM.INT64;
  PROCEDURE ["C", "TimePlatform.-process"] CProcess(): SYSTEM.INT64;
  PROCEDURE ["C", "TimePlatform.-wall-resolution"] CWallResolution(): SYSTEM.INT64;
  PROCEDURE ["C", "TimePlatform.-monotonic-resolution"] CMonotonicResolution(): SYSTEM.INT64;
  PROCEDURE ["C", "TimePlatform.-sleep"] CSleep(nanoseconds: SYSTEM.INT64);

  (* UTC, as POSIX seconds since 1970 and 0 <= nanosecond < 10^9 *)
  PROCEDURE WallClock*(VAR seconds: HUGEINT; VAR nanosecond: LONGINT);
    VAR s, n: SYSTEM.INT64;
  BEGIN
    CWallClock(SYSTEM.ADR(s), SYSTEM.ADR(n));
    seconds := s;  nanosecond := SHORT(n)
  END WallClock;

  (* CLOCK_MONOTONIC: since an unspecified start, never decreasing *)
  PROCEDURE MonotonicNanoseconds*(): HUGEINT;
  BEGIN
    RETURN CMonotonic()
  END MonotonicNanoseconds;

  (* CLOCK_PROCESS_CPUTIME_ID *)
  PROCEDURE ProcessNanoseconds*(): HUGEINT;
  BEGIN
    RETURN CProcess()
  END ProcessNanoseconds;

  PROCEDURE WallResolution*(): HUGEINT;
  BEGIN
    RETURN CWallResolution()
  END WallResolution;

  PROCEDURE MonotonicResolution*(): HUGEINT;
  BEGIN
    RETURN CMonotonicResolution()
  END MonotonicResolution;

  (* at least nanoseconds; nanoseconds <= 0 returns at once *)
  PROCEDURE Sleep*(nanoseconds: HUGEINT);
  BEGIN
    CSleep(nanoseconds)
  END Sleep;

END TimePlatform.
