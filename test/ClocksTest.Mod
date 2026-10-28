MODULE ClocksTest;

  (* Tests of Clocks. The clocks cannot be compared with fixed values, so
     these check what must hold however loaded the machine: the wall clock
     against Platform's gettimeofday, the monotonic clock never going
     back, sleeps at least as long as asked, and resolutions that are
     possible. The bounds above are loose for the same reason. *)

  IMPORT Clocks, D := Durations, I := Instants, Platform, T := TimeTests;

  CONST
    (* 2026-10-01T00:00:00Z and 2100-01-01T00:00:00Z *)
    after = 1790812800;  before = 4102444800;
    readings = 100000;

  VAR start, d: D.Duration;

  PROCEDURE WallClock;
    VAR t, u: I.Instant; sec, usec: LONGINT; difference: HUGEINT;
  BEGIN
    Clocks.Now(t);
    T.True("Now plausible", (t.seconds > after) & (t.seconds < before));
    T.True("Now nanosecond", (t.nanosecond >= 0) & (t.nanosecond < D.second));
    (* under -O2 sec is a LONGINT of 32 bits, so compare modulo 2^32 *)
    Platform.GetTimeOfDay(sec, usec);
    difference := (sec - t.seconds) MOD 100000000H;
    T.True("Now against gettimeofday", (difference <= 2) OR (difference >= 100000000H - 2));
    Clocks.Now(u);
    T.True("Now again", ~I.Before(u, t) OR (I.Between(t, u) < D.second))
  END WallClock;

  PROCEDURE Monotonic;
    VAR previous, now: D.Duration; n: LONGINT; backward: BOOLEAN;
  BEGIN
    previous := Clocks.Monotonic();  backward := FALSE;
    FOR n := 1 TO readings DO
      now := Clocks.Monotonic();
      IF now < previous THEN backward := TRUE END;
      previous := now
    END;
    T.True("Monotonic never goes back", ~backward);
    T.True("Monotonic positive", previous > 0);
    start := Clocks.Monotonic();
    T.True("Since", Clocks.Since(start) >= 0);
    T.Int("Since saturates", Clocks.Since(D.min), D.max)
  END Monotonic;

  PROCEDURE Sleeping;
    VAR t, u: I.Instant;
  BEGIN
    Clocks.Now(t);
    start := Clocks.Monotonic();
    Clocks.Sleep(20 * D.millisecond);
    d := Clocks.Since(start);
    T.True("Sleep at least", d >= 20 * D.millisecond);
    T.True("Sleep not far over", d < 5 * D.second);
    Clocks.Now(u);
    (* the wall clock may be set meanwhile, so only loosely *)
    T.True("Sleep wall clock", (I.Between(u, t) > 0) & (I.Between(u, t) < 5 * D.second));
    start := Clocks.Monotonic();
    Clocks.Sleep(0);  Clocks.Sleep(-D.second);  Clocks.Sleep(D.min);
    T.True("Sleep <= 0 at once", Clocks.Since(start) < D.second);
    start := Clocks.Monotonic();
    Clocks.Sleep(1);
    T.True("Sleep 1 ns", Clocks.Since(start) >= 1)
  END Sleeping;

  PROCEDURE ProcessTime;
    VAR first, now: D.Duration; previous: D.Duration; backward: BOOLEAN;
  BEGIN
    first := Clocks.ProcessTime();
    T.True("ProcessTime positive", first > 0);
    (* spin until the CPU time moves, for at most 5 s of real time *)
    start := Clocks.Monotonic();  previous := first;  backward := FALSE;
    REPEAT
      now := Clocks.ProcessTime();
      IF now < previous THEN backward := TRUE END;
      previous := now
    UNTIL (now > first) OR (Clocks.Since(start) > 5 * D.second);
    T.True("ProcessTime moves", now > first);
    T.True("ProcessTime never goes back", ~backward)
  END ProcessTime;

  PROCEDURE Resolutions;
  BEGIN
    T.True("WallResolution", (Clocks.WallResolution() > 0) & (Clocks.WallResolution() <= D.second));
    T.True("MonotonicResolution",
      (Clocks.MonotonicResolution() > 0) & (Clocks.MonotonicResolution() <= D.second))
  END Resolutions;

BEGIN
  T.Start("Clocks");
  WallClock;  Monotonic;  Sleeping;  ProcessTime;  Resolutions;
  T.Finish
END ClocksTest.
