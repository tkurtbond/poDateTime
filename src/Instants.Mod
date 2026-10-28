MODULE Instants;

  (* Points on the timeline: POSIX seconds since 1970-01-01T00:00:00Z
     and a nanosecond, as in struct timespec (design section 6). Leap
     seconds are not counted. The range is the years -9999..9999, the
     same as Calendar's, so that every instant has a date.

     The procedures saturate at earliest and latest (Q4). Results are
     written field by field, so that r may be one of the inputs and may
     be an extension of Instant.

     ASSERT numbers:
       20  Truncate with a unit that is not positive *)

  IMPORT Durations;

  CONST
    second = Durations.second;
    (* -9999-01-01T00:00:00Z and 9999-12-31T23:59:59Z *)
    earliestSeconds = -377705116800;  latestSeconds = 253402300799;
    (* Durations.max and min as seconds and nanoseconds, nanoseconds
       0 .. second - 1 *)
    maxSeconds = 9223372036;  maxNanoseconds = 854775807;
    minSeconds = -9223372037;  minNanoseconds = 145224192;

  TYPE
    Instant* = RECORD
      seconds-: HUGEINT;
      nanosecond-: LONGINT
    END;

  VAR earliest-, latest-: Instant;

  (* r := seconds + nanosecond, given 0 <= nanosecond < second, clamped *)
  PROCEDURE Set(VAR r: Instant; seconds: HUGEINT; nanosecond: HUGEINT);
  BEGIN
    IF seconds < earliestSeconds THEN
      r.seconds := earliestSeconds;  r.nanosecond := 0
    ELSIF seconds > latestSeconds THEN
      r.seconds := latestSeconds;  r.nanosecond := second - 1
    ELSE
      r.seconds := seconds;  r.nanosecond := SHORT(nanosecond)
    END
  END Set;

  PROCEDURE FromUnix*(VAR t: Instant; seconds, nanoseconds: HUGEINT);
  BEGIN
    Set(t, Durations.Sum(seconds, nanoseconds DIV second), nanoseconds MOD second)
  END FromUnix;

  PROCEDURE FromUnixMilliseconds*(VAR t: Instant; ms: HUGEINT);
  BEGIN
    Set(t, ms DIV 1000, ms MOD 1000 * Durations.millisecond)
  END FromUnixMilliseconds;

  PROCEDURE UnixSeconds*(t: Instant): HUGEINT;
  BEGIN
    RETURN t.seconds
  END UnixSeconds;

  (* within the years -9999..9999 this cannot overflow *)
  PROCEDURE UnixMilliseconds*(t: Instant): HUGEINT;
  BEGIN
    RETURN t.seconds * 1000 + t.nanosecond DIV Durations.millisecond
  END UnixMilliseconds;

  (* d is split by floored DIV and MOD, so that its nanoseconds are never
     negative; its seconds, at most 2^33, cannot overflow t.seconds *)
  PROCEDURE Add*(VAR r: Instant; t: Instant; d: Durations.Duration);
    VAR seconds, nanosecond: HUGEINT;
  BEGIN
    seconds := t.seconds + d DIV second;
    nanosecond := t.nanosecond + d MOD second;
    IF nanosecond >= second THEN DEC(nanosecond, second); INC(seconds) END;
    Set(r, seconds, nanosecond)
  END Add;

  (* not Add(r, t, -d): -Durations.min wraps to itself *)
  PROCEDURE Subtract*(VAR r: Instant; t: Instant; d: Durations.Duration);
    VAR seconds, nanosecond: HUGEINT;
  BEGIN
    seconds := t.seconds - d DIV second;
    nanosecond := t.nanosecond - d MOD second;
    IF nanosecond < 0 THEN INC(nanosecond, second); DEC(seconds) END;
    Set(r, seconds, nanosecond)
  END Subtract;

  PROCEDURE CheckedBetween*(VAR d: Durations.Duration; later, earlier: Instant): BOOLEAN;
    VAR seconds, nanosecond: HUGEINT; fits: BOOLEAN;
  BEGIN
    seconds := later.seconds - earlier.seconds;
    nanosecond := later.nanosecond - earlier.nanosecond;
    IF nanosecond < 0 THEN INC(nanosecond, second); DEC(seconds) END;
    fits := ((seconds < maxSeconds) OR (seconds = maxSeconds) & (nanosecond <= maxNanoseconds))
      & ((seconds > minSeconds) OR (seconds = minSeconds) & (nanosecond >= minNanoseconds));
    IF fits THEN d := seconds * second + nanosecond END;
    RETURN fits
  END CheckedBetween;

  PROCEDURE Between*(later, earlier: Instant): Durations.Duration;
    VAR d: Durations.Duration;
  BEGIN
    IF ~CheckedBetween(d, later, earlier) THEN
      IF later.seconds > earlier.seconds THEN d := Durations.max ELSE d := Durations.min END
    END;
    RETURN d
  END Between;

  PROCEDURE Compare*(a, b: Instant): INTEGER;
    VAR c: INTEGER;
  BEGIN
    IF a.seconds < b.seconds THEN c := -1
    ELSIF a.seconds > b.seconds THEN c := 1
    ELSIF a.nanosecond < b.nanosecond THEN c := -1
    ELSIF a.nanosecond > b.nanosecond THEN c := 1
    ELSE c := 0
    END;
    RETURN c
  END Compare;

  PROCEDURE Equal*(a, b: Instant): BOOLEAN;
  BEGIN
    RETURN (a.seconds = b.seconds) & (a.nanosecond = b.nanosecond)
  END Equal;

  PROCEDURE Before*(a, b: Instant): BOOLEAN;
  BEGIN
    RETURN (a.seconds < b.seconds) OR (a.seconds = b.seconds) & (a.nanosecond < b.nanosecond)
  END Before;

  (* (x + y) MOD m, for 0 <= x, y < m, without overflow *)
  PROCEDURE AddModulo(x, y, m: HUGEINT): HUGEINT;
  BEGIN
    IF x >= m - y THEN RETURN x - (m - y) ELSE RETURN x + y END
  END AddModulo;

  (* x * y MOD m, for 0 <= x < m and y >= 0, by doubling, so that nothing
     exceeds m *)
  PROCEDURE MultiplyModulo(x, y, m: HUGEINT): HUGEINT;
    VAR r: HUGEINT;
  BEGIN
    r := 0;
    WHILE y > 0 DO
      IF ODD(y) THEN r := AddModulo(r, x, m) END;
      x := AddModulo(x, x, m);  y := y DIV 2
    END;
    RETURN r
  END MultiplyModulo;

  (* Down to a multiple of unit since 1970, for any positive unit
     (doc/instant-truncation.md). The instant in nanoseconds needs 69
     bits, more than a HUGEINT, so a unit that neither divides a second
     nor is whole seconds has its remainder found from the two fields,
     multiplying modulo the unit. Below earliest the result clamps.
     Durations.week gives Thursdays, as 1970-01-01 was one; ISO weeks
     need Calendar. *)
  PROCEDURE Truncate*(VAR r: Instant; t: Instant; unit: Durations.Duration);
    VAR remainder: HUGEINT; seconds, nanosecond: HUGEINT;
  BEGIN
    ASSERT(unit > 0, 20);
    IF second MOD unit = 0 THEN
      Set(r, t.seconds, t.nanosecond - t.nanosecond MOD unit)
    ELSIF unit MOD second = 0 THEN
      Set(r, t.seconds - t.seconds MOD (unit DIV second), 0)
    ELSE
      remainder := AddModulo(MultiplyModulo(t.seconds MOD unit, second, unit),
        t.nanosecond MOD unit, unit);
      seconds := t.seconds - remainder DIV second;
      nanosecond := t.nanosecond - remainder MOD second;
      IF nanosecond < 0 THEN INC(nanosecond, second);  DEC(seconds) END;
      Set(r, seconds, nanosecond)
    END
  END Truncate;

BEGIN
  Set(earliest, earliestSeconds, 0);
  Set(latest, latestSeconds, second - 1)
END Instants.
