MODULE Clocks;

  (* The clocks (design section 9): the wall clock as an Instant, and a
     monotonic clock and the process's CPU time as Durations. A monotonic
     reading is a Duration since an unspecified start, not an Instant, so
     that it cannot be taken for a date. The wall clock can jump when the
     clock is set; the monotonic clock cannot. On VMS the system clock is
     local time, which TimeZones.Now turns into UTC through the local
     zone (Q22); where that zone is Fixed(0), named "VMS", Now is really
     local time.

     No ASSERTs. *)

  IMPORT Durations, Instants, Calendar, TimeZones, TimePlatform;

  PROCEDURE Now*(VAR t: Instants.Instant);
    VAR seconds: HUGEINT; nanosecond: LONGINT; odt: Calendar.OffsetDateTime;
  BEGIN
    IF TimePlatform.WallClockIsLocal() THEN
      TimeZones.Now(TimeZones.utc, odt);
      Calendar.ToInstant(odt, t)
    ELSE
      TimePlatform.WallClock(seconds, nanosecond);
      Instants.FromUnix(t, seconds, nanosecond)
    END
  END Now;

  PROCEDURE Monotonic*(): Durations.Duration;
  BEGIN
    RETURN TimePlatform.MonotonicNanoseconds()
  END Monotonic;

  (* Monotonic() - start, saturating *)
  PROCEDURE Since*(start: Durations.Duration): Durations.Duration;
  BEGIN
    RETURN Durations.Difference(Monotonic(), start)
  END Since;

  PROCEDURE ProcessTime*(): Durations.Duration;
  BEGIN
    RETURN TimePlatform.ProcessNanoseconds()
  END ProcessTime;

  (* at least d; d <= 0 returns at once *)
  PROCEDURE Sleep*(d: Durations.Duration);
  BEGIN
    IF d > 0 THEN TimePlatform.Sleep(d) END
  END Sleep;

  PROCEDURE WallResolution*(): Durations.Duration;
  BEGIN
    RETURN TimePlatform.WallResolution()
  END WallResolution;

  PROCEDURE MonotonicResolution*(): Durations.Duration;
  BEGIN
    RETURN TimePlatform.MonotonicResolution()
  END MonotonicResolution;

END Clocks.
