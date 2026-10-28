MODULE TimePlatform;

  (* The operating system's part of the library, for LLVM (design section
     11): the clocks, in nanoseconds, and the local zone, which is the C
     library's. Internal: programs use Clocks and TimeZones. The work is
     in TimePlatform.c beside this file, compiled by clang for the target
     from the system's own headers, under names that start with
     "TimePlatform.-".

     No ASSERTs. *)

  IMPORT SYSTEM;

  PROCEDURE ["C", "TimePlatform.-wall-clock"] CWallClock(seconds, nanosecond: SYSTEM.ADDRESS);
  PROCEDURE ["C", "TimePlatform.-monotonic"] CMonotonic(): SYSTEM.INT64;
  PROCEDURE ["C", "TimePlatform.-process"] CProcess(): SYSTEM.INT64;
  PROCEDURE ["C", "TimePlatform.-wall-resolution"] CWallResolution(): SYSTEM.INT64;
  PROCEDURE ["C", "TimePlatform.-monotonic-resolution"] CMonotonicResolution(): SYSTEM.INT64;
  PROCEDURE ["C", "TimePlatform.-sleep"] CSleep(nanoseconds: SYSTEM.INT64);
  PROCEDURE ["C", "TimePlatform.-system-local"] CSystemLocal(): SYSTEM.INT32;
  PROCEDURE ["C", "TimePlatform.-local-offset"] CLocalOffset(seconds: SYSTEM.INT64;
    offset, isDst, abbreviation: SYSTEM.ADDRESS; length: SYSTEM.INT32): SYSTEM.INT32;
  PROCEDURE ["C", "TimePlatform.-local-zone-name"] CLocalZoneName(name: SYSTEM.ADDRESS;
    length: SYSTEM.INT32);
  PROCEDURE ["C", "TimePlatform.-zone-info-directory"] CZoneInfoDirectory(dir: SYSTEM.ADDRESS;
    length: SYSTEM.INT32);

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

  (* whether LocalOffset answers for the local zone; on Unix it does *)
  PROCEDURE SystemLocal*(): BOOLEAN;
  BEGIN
    RETURN CSystemLocal() # 0
  END SystemLocal;

  (* the local zone at POSIX time seconds; FALSE where the C library
     cannot say, as beyond a 32-bit time_t *)
  PROCEDURE LocalOffset*(seconds: HUGEINT; VAR offset: LONGINT; VAR isDst: BOOLEAN;
                         VAR abbreviation: ARRAY OF CHAR): BOOLEAN;
    VAR o, dst: SYSTEM.INT32; ok: BOOLEAN;
  BEGIN
    ok := CLocalOffset(seconds, SYSTEM.ADR(o), SYSTEM.ADR(dst), SYSTEM.ADR(abbreviation),
      SHORT(LEN(abbreviation))) # 0;
    IF ok THEN offset := o;  isDst := dst # 0 END;
    RETURN ok
  END LocalOffset;

  PROCEDURE LocalZoneName*(VAR name: ARRAY OF CHAR);
  BEGIN
    CLocalZoneName(SYSTEM.ADR(name), SHORT(LEN(name)))
  END LocalZoneName;

  (* for VMS, where the TZ logical name may hold a POSIX rule; Unix has
     the C library *)
  PROCEDURE LocalRule*(VAR rule: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN FALSE
  END LocalRule;

  PROCEDURE ZoneInfoDirectory*(VAR dir: ARRAY OF CHAR);
  BEGIN
    CZoneInfoDirectory(SYSTEM.ADR(dir), SHORT(LEN(dir)))
  END ZoneInfoDirectory;

END TimePlatform.
