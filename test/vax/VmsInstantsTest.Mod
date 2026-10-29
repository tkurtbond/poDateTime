MODULE VmsInstantsTest;

  (* Tests of VmsInstants, on VMS only. The times are read by $BINTIM
     (DateTimes.FromText) and compared with the quadwords Python's
     datetime gives, so that the VMS epoch is checked against VMS itself.
     The run defines TZ as newYork, the rule TimeZonesTest uses, so that
     summer, winter, the gap and the overlap are known. *)

  IMPORT DT := DateTimes, Clocks, D := Durations, I := Instants, TZ := TimeZones,
    VI := VmsInstants, T := TimeTests;

  CONST
    newYork = "EST5EDT,M3.2.0,M11.1.0";
    ticks = DT.ticksPerSecond;
    (* local times as quadwords, and the Unix seconds of their instants *)
    unixEpoch = 35067168000000000;       (* 1970-01-01 00:00 *)
    summer = 52898832000000000;          (* 2026-07-04 12:00 EDT *)
    summerSeconds = 1783180800;
    winter = 52751952000000000;          (* 2026-01-15 12:00 EST *)
    winterSeconds = 1768496400;
    gap = 52796538000000000;             (* 2026-03-08 02:30, skipped *)
    gapSeconds = 1772955000;             (* read as 03:30 EDT *)
    afterGap = 52796574000000000;        (* 2026-03-08 03:30 *)
    overlap = 53002134000000000;         (* 2026-11-01 01:30, twice *)
    overlapEarlier = 1793511000;         (* EDT *)
    overlapLater = 1793514600;           (* EST *)
    year10000 = 2569090176000000000;     (* 10000-01-01 00:00 *)
    vmsEpochSeconds = -3506698800;       (* 1858-11-17 00:00 EST *)

  VAR t, u: DT.Time;  i: I.Instant;  d: D.Duration;  local: TZ.Zone;  rule: ARRAY 64 OF CHAR;

  PROCEDURE Text(label, text: ARRAY OF CHAR; expected: DT.Time);
  BEGIN
    T.True(label, ODD(DT.FromText(text, t)));
    T.Int(label, t, expected)
  END Text;

  PROCEDURE Is(label: ARRAY OF CHAR; ok: BOOLEAN; seconds, nanosecond: HUGEINT);
  BEGIN
    T.True(label, ok & (i.seconds = seconds) & (i.nanosecond = nanosecond));
    IF ok & ((i.seconds # seconds) OR (i.nanosecond # nanosecond)) THEN
      T.Failed(label, i.seconds, i.nanosecond, 0)
    END
  END Is;

  PROCEDURE AgainstVms;
  BEGIN
    Text("$BINTIM epoch", "17-NOV-1858 00:00:00.00", 0);
    Text("$BINTIM 1970", "1-JAN-1970 00:00:00.00", unixEpoch);
    Text("$BINTIM summer", "4-JUL-2026 12:00:00.00", summer);
    Text("$BINTIM winter", "15-JAN-2026 12:00:00.00", winter);
    Text("$BINTIM delta", "0 00:00:01.00", -ticks)
  END AgainstVms;

  PROCEDURE ToInstant;
  BEGIN
    Is("ToInstant epoch", VI.ToInstant(0, TZ.strict, i), vmsEpochSeconds, 0);
    Is("ToInstant 1970", VI.ToInstant(unixEpoch, TZ.strict, i), 5 * 3600, 0);
    Is("ToInstant summer", VI.ToInstant(summer, TZ.strict, i), summerSeconds, 0);
    Is("ToInstant winter", VI.ToInstant(winter, TZ.strict, i), winterSeconds, 0);
    Is("ToInstant fraction", VI.ToInstant(summer + 1234567, TZ.strict, i),
      summerSeconds, 123456700);
    T.True("ToInstant gap strict", ~VI.ToInstant(gap, TZ.strict, i));
    Is("ToInstant gap", VI.ToInstant(gap, TZ.earlier, i), gapSeconds, 0);
    T.True("ToInstant overlap strict", ~VI.ToInstant(overlap, TZ.strict, i));
    Is("ToInstant overlap earlier", VI.ToInstant(overlap, TZ.earlier, i), overlapEarlier, 0);
    Is("ToInstant overlap later", VI.ToInstant(overlap, TZ.later, i), overlapLater, 0);
    T.True("ToInstant delta", ~VI.ToInstant(-ticks, TZ.earlier, i));
    T.True("ToInstant year 10000", ~VI.ToInstant(year10000, TZ.earlier, i))
  END ToInstant;

  PROCEDURE FromInstant;
  BEGIN
    I.FromUnix(i, summerSeconds, 123456789);
    T.True("FromInstant summer", VI.FromInstant(t, i));
    T.Int("FromInstant summer", t, summer + 1234567);
    I.FromUnix(i, winterSeconds, 0);
    T.True("FromInstant winter", VI.FromInstant(t, i));
    T.Int("FromInstant winter", t, winter);
    I.FromUnix(i, gapSeconds, 0);
    T.True("FromInstant after gap", VI.FromInstant(t, i));
    T.Int("FromInstant after gap", t, afterGap);
    I.FromUnix(i, overlapEarlier, 0);
    T.True("FromInstant overlap EDT", VI.FromInstant(t, i));
    T.Int("FromInstant overlap EDT", t, overlap);
    I.FromUnix(i, overlapLater, 0);
    T.True("FromInstant overlap EST", VI.FromInstant(t, i));
    T.Int("FromInstant overlap EST", t, overlap);
    I.FromUnix(i, vmsEpochSeconds, 0);
    T.True("FromInstant epoch", VI.FromInstant(t, i));
    T.Int("FromInstant epoch", t, 0);
    I.FromUnix(i, vmsEpochSeconds - 1, 999999999);
    T.True("FromInstant before epoch", ~VI.FromInstant(t, i));
    T.True("FromInstant earliest", ~VI.FromInstant(t, I.earliest))
  END FromInstant;

  PROCEDURE Deltas;
  BEGIN
    T.True("ToDuration 1 s", VI.ToDuration(-ticks, d));
    T.Int("ToDuration 1 s", d, D.second);
    T.True("ToDuration 100 ns", VI.ToDuration(-1, d));
    T.Int("ToDuration 100 ns", d, 100);
    T.True("ToDuration longest", VI.ToDuration(-(D.max DIV 100), d));
    T.Int("ToDuration longest", d, D.max DIV 100 * 100);
    T.True("ToDuration too long", ~VI.ToDuration(-(D.max DIV 100) - 1, d));
    T.True("ToDuration zero", ~VI.ToDuration(0, d));
    T.True("ToDuration absolute", ~VI.ToDuration(summer, d));
    T.True("FromDuration 1 s", VI.FromDuration(t, D.second));
    T.Int("FromDuration 1 s", t, -ticks);
    T.True("FromDuration truncates", VI.FromDuration(t, 199));
    T.Int("FromDuration truncates", t, -1);
    T.True("FromDuration 99 ns", ~VI.FromDuration(t, 99));
    T.True("FromDuration negative", ~VI.FromDuration(t, -D.second))
  END Deltas;

  (* the clocks agree to within a second, which allows for the 10 ms tick
     and the time between the two reads *)
  PROCEDURE Now;
  BEGIN
    Clocks.Now(i);
    u := DT.Now();
    T.True("FromInstant Now", VI.FromInstant(t, i));
    T.True("Now agrees", ABS(u - t) < ticks);
    IF ABS(u - t) >= ticks THEN T.Failed("Now agrees", u, t, 0) END
  END Now;

BEGIN
  T.Start("VmsInstants");
  local := TZ.Local();  local.GetName(rule);
  T.Str("TZ", rule, newYork);
  AgainstVms;  ToInstant;  FromInstant;  Deltas;  Now;
  T.Finish
END VmsInstantsTest.
