MODULE TimePlatform;

  (* The operating system's part of the library, for VAX/VMS 5.5-2 (design
     section 11): the clocks, in nanoseconds, and the TZ logical name.
     Internal: programs use Clocks and TimeZones. The system services are
     declared here rather than imported from STARLET, so that the library
     needs POCRTL only; their arguments and codes are from the VMS 5.5
     System Services Reference Manual and $JPIDEF and $LNMDEF.

     The system clock is local time (Q22): WallClock gives it as it
     stands, and Clocks and TimeZones turn it into UTC through the local
     zone. VMS has no zone database, so LocalOffset never answers and
     ZoneInfoDirectory is empty (Q6).

     Monotonic reads EXE$GL_ABSTIM_TICS, the 10 ms ticks since boot,
     through SYS.STB, which the library is linked with (Q8). It is an
     unsigned longword that wraps after 497 days; the wraps are counted
     here, so a process must read it at least once in each 497 days.

     No ASSERTs. *)

  IMPORT SYSTEM, Platform;

  CONST
    (* seconds from the VMS epoch, 1858-11-17, to 1970-01-01 *)
    epoch = 3506716800;
    unitsPerSecond = 10000000;   (* 100 ns *)
    nanosecondsPerTick = 10000000;   (* 10 ms *)
    millisecondsPerDelay = 86400000;   (* a day, so that a delay fits a longword *)

    cpuTime = 1031;   (* JPI$_CPUTIM, a longword of 10 ms ticks *)
    translation = 2;   (* LNM$_STRING *)

  TYPE
    (* an item list of one item_list_3 entry and its terminating longword *)
    ItemList = RECORD
      bufferLength, itemCode: SYSTEM.INT16;
      buffer, returnLength: SYSTEM.ADDRESS;
      end: SYSTEM.INT32
    END;

    StatusBlock = RECORD
      status, count: SYSTEM.INT16;
      deviceSpecific: SYSTEM.INT32
    END;

  VAR
    ["VMS", "EXE$GL_ABSTIM_TICS"] absoluteTicks-: SYSTEM.INT32;
    lastTicks, wraps: HUGEINT;

  PROCEDURE ["VMS", "SYS$GETTIM"] GetTime(VAR time: HUGEINT): SYSTEM.INT32;
  PROCEDURE ["VMS", "SYS$GETJPIW"] GetProcessInformation(efn: SYSTEM.INT32;
    pid, processName: SYSTEM.ADDRESS; VAR items: ItemList; VAR iosb: StatusBlock;
    ast: SYSTEM.ADDRESS; astParameter: SYSTEM.INT32): SYSTEM.INT32;
  PROCEDURE ["VMS", "SYS$TRNLNM"] TranslateName(attributes: SYSTEM.ADDRESS;
    table-, name-: ARRAY OF CHAR; mode: SYSTEM.ADDRESS; VAR items: ItemList): SYSTEM.INT32;

  (* local time, as POSIX seconds since 1970 and 0 <= nanosecond < 10^9 *)
  PROCEDURE WallClock*(VAR seconds: HUGEINT; VAR nanosecond: LONGINT);
    VAR t: HUGEINT; status: SYSTEM.INT32;
  BEGIN
    status := GetTime(t);
    seconds := t DIV unitsPerSecond - epoch;
    nanosecond := SHORT(t MOD unitsPerSecond * 100)
  END WallClock;

  PROCEDURE WallClockIsLocal*(): BOOLEAN;
  BEGIN
    RETURN TRUE
  END WallClockIsLocal;

  (* since boot, never decreasing; setting the clock does not move it *)
  PROCEDURE MonotonicNanoseconds*(): HUGEINT;
    VAR ticks: HUGEINT;
  BEGIN
    ticks := absoluteTicks;
    IF ticks < 0 THEN ticks := ticks + 100000000H END;
    IF ticks < lastTicks THEN INC(wraps) END;
    lastTicks := ticks;
    RETURN (wraps * 100000000H + ticks) * nanosecondsPerTick
  END MonotonicNanoseconds;

  (* the CPU time this process has used; 0 if $GETJPI cannot say *)
  PROCEDURE ProcessNanoseconds*(): HUGEINT;
    VAR items: ItemList; iosb: StatusBlock; ticks: SYSTEM.INT32; result: HUGEINT;
  BEGIN
    items.bufferLength := 4;  items.itemCode := SYSTEM.VAL(SYSTEM.INT16, cpuTime);
    items.buffer := SYSTEM.ADR(ticks);  items.returnLength := 0;  items.end := 0;
    result := 0;
    IF ODD(GetProcessInformation(0, 0, 0, items, iosb, 0, 0)) & ODD(iosb.status) THEN
      result := ticks;  result := result * nanosecondsPerTick
    END;
    RETURN result
  END ProcessNanoseconds;

  PROCEDURE WallResolution*(): HUGEINT;
  BEGIN
    RETURN nanosecondsPerTick
  END WallResolution;

  PROCEDURE MonotonicResolution*(): HUGEINT;
  BEGIN
    RETURN nanosecondsPerTick
  END MonotonicResolution;

  (* at least nanoseconds, rounded up to milliseconds for Platform.Delay;
     nanoseconds <= 0 returns at once *)
  PROCEDURE Sleep*(nanoseconds: HUGEINT);
    VAR milliseconds, part: HUGEINT;
  BEGIN
    IF nanoseconds > 0 THEN
      milliseconds := (nanoseconds - 1) DIV 1000000 + 1;
      WHILE milliseconds > 0 DO
        part := milliseconds;
        IF part > millisecondsPerDelay THEN part := millisecondsPerDelay END;
        Platform.Delay(SHORT(part));
        milliseconds := milliseconds - part
      END
    END
  END Sleep;

  (* VMS has no zone of its own to ask *)
  PROCEDURE SystemLocal*(): BOOLEAN;
  BEGIN
    RETURN FALSE
  END SystemLocal;

  PROCEDURE LocalOffset*(seconds: HUGEINT; VAR offset: LONGINT; VAR isDst: BOOLEAN;
                         VAR abbreviation: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN FALSE
  END LocalOffset;

  PROCEDURE LocalZoneName*(VAR name: ARRAY OF CHAR);
  BEGIN
    name[0] := 0X
  END LocalZoneName;

  (* the translation of the logical name TZ in LNM$FILE_DEV, which is
     the process's, job's, group's and system's tables in turn; FALSE
     if it has none, or one too long for rule. DEFINE writes the name
     in capitals, so the search need not ignore case. *)
  PROCEDURE LocalRule*(VAR rule: ARRAY OF CHAR): BOOLEAN;
    VAR items: ItemList; length: SYSTEM.INT16; size, n: LONGINT; ok: BOOLEAN;
  BEGIN
    size := LEN(rule) - 1;
    IF size > 255 THEN size := 255 END;
    length := 0;
    items.bufferLength := SYSTEM.VAL(SYSTEM.INT16, size);
    items.itemCode := SYSTEM.VAL(SYSTEM.INT16, translation);
    items.buffer := SYSTEM.ADR(rule);  items.returnLength := SYSTEM.ADR(length);
    items.end := 0;
    ok := ODD(TranslateName(0, "LNM$FILE_DEV", "TZ", 0, items));
    n := length;
    ok := ok & (n > 0) & (n < size);
    IF ok THEN rule[n] := 0X ELSE rule[0] := 0X END;
    RETURN ok
  END LocalRule;

  PROCEDURE ZoneInfoDirectory*(VAR dir: ARRAY OF CHAR);
  BEGIN
    dir[0] := 0X
  END ZoneInfoDirectory;

BEGIN
  lastTicks := 0;  wraps := 0
END TimePlatform.
