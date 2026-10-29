MODULE VmsInstants;

  (* Between VMSLIB's DateTimes.Time and this library's types (design
     section 11.1), for programs that use both. A Time of zero or more is
     an absolute time, local, in 100 ns units from 1858-11-17 00:00, as
     SYS$GETTIM gives it; below zero it is a delta time. Absolute times
     go through TimeZones.Local(), the zone Clocks.Now uses (Q22), so
     that FromInstant of Clocks.Now agrees with DateTimes.Now() to within
     the clock's 10 ms tick. Programs that import this module link VMSLIB
     as well.

     No ASSERTs. *)

  IMPORT DateTimes, Durations, Instants, Calendar, TimeZones;

  CONST
    (* seconds from the VMS epoch, 1858-11-17, to 1970-01-01 *)
    epoch = 3506716800;
    nanosecondsPerUnit = 100;

  (* the instant of the absolute time t, its local time resolved with
     choice as TimeZones.ToInstant does; FALSE for a delta time, a year
     past 9999, or a strict choice that meets a gap or an overlap *)
  PROCEDURE ToInstant*(t: DateTimes.Time; choice: INTEGER; VAR i: Instants.Instant): BOOLEAN;
    VAR u: Instants.Instant; dt: Calendar.DateTime; seconds: HUGEINT; ok: BOOLEAN;
  BEGIN
    ok := t >= 0;
    IF ok THEN
      seconds := t DIV DateTimes.ticksPerSecond - epoch;
      ok := seconds <= Instants.latest.seconds
    END;
    IF ok THEN
      Instants.FromUnix(u, seconds, t MOD DateTimes.ticksPerSecond * nanosecondsPerUnit);
      Calendar.FromUTCInstant(dt, u);
      ok := TimeZones.ToInstant(TimeZones.Local(), dt, choice, i)
    END;
    RETURN ok
  END ToInstant;

  (* the absolute time of i, local, truncated to 100 ns; FALSE before
     1858-11-17 00:00 local, which VMS cannot hold *)
  PROCEDURE FromInstant*(VAR t: DateTimes.Time; i: Instants.Instant): BOOLEAN;
    VAR odt: Calendar.OffsetDateTime; seconds: HUGEINT; ok: BOOLEAN;
  BEGIN
    (* ToLocal's fields saturate at the ends of the years, but its offset
       is the one in force at i *)
    TimeZones.ToLocal(TimeZones.Local(), i, odt);
    seconds := i.seconds + odt.offset + epoch;
    ok := seconds >= 0;
    IF ok THEN
      t := seconds * DateTimes.ticksPerSecond + i.nanosecond DIV nanosecondsPerUnit
    END;
    RETURN ok
  END FromInstant;

  (* the length of the delta time t; FALSE for an absolute time, or one
     too long for a Duration *)
  PROCEDURE ToDuration*(t: DateTimes.Time; VAR d: Durations.Duration): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN
    ok := (t < 0) & (t >= -(Durations.max DIV nanosecondsPerUnit));
    IF ok THEN d := -t * nanosecondsPerUnit END;
    RETURN ok
  END ToDuration;

  (* the delta time of d, truncated to 100 ns; FALSE for under 100 ns,
     since a zero quadword is not a delta time *)
  PROCEDURE FromDuration*(VAR t: DateTimes.Time; d: Durations.Duration): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN
    ok := d >= nanosecondsPerUnit;
    IF ok THEN t := -(d DIV nanosecondsPerUnit) END;
    RETURN ok
  END FromDuration;

END VmsInstants.
