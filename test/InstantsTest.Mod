MODULE InstantsTest;

  (* Tests of Instants: normalizing, the range's ends, Between near the
     limits of a Duration, and Truncate against a table from Python's
     integers (test/data/InstantsData.Mod). *)

  IMPORT D := Durations, I := Instants, InstantsData, T := TimeTests;

  CONST s = D.second;

  VAR a, b, r: I.Instant;  d: D.Duration;  tableFailures: LONGINT;

  PROCEDURE Is(label: ARRAY OF CHAR; t: I.Instant; seconds, nanosecond: HUGEINT);
  BEGIN
    T.True(label, (t.seconds = seconds) & (t.nanosecond = nanosecond));
    IF (t.seconds # seconds) OR (t.nanosecond # nanosecond) THEN
      T.Failed(label, t.seconds, t.nanosecond, 0)
    END
  END Is;

  PROCEDURE Construction;
  BEGIN
    Is("earliest", I.earliest, -377705116800, 0);
    Is("latest", I.latest, 253402300799, 999999999);
    I.FromUnix(r, 0, 0);  Is("FromUnix 0", r, 0, 0);
    I.FromUnix(r, 10, 1500000000);  Is("FromUnix carry", r, 11, 500000000);
    I.FromUnix(r, 10, -1);  Is("FromUnix borrow", r, 9, 999999999);
    I.FromUnix(r, 0, -3500000000);  Is("FromUnix borrow 4", r, -4, 500000000);
    I.FromUnix(r, D.max, 0);  Is("FromUnix huge", r, 253402300799, 999999999);
    I.FromUnix(r, D.min, 0);  Is("FromUnix -huge", r, -377705116800, 0);
    I.FromUnix(r, D.max, D.max);  Is("FromUnix huge carry", r, 253402300799, 999999999);
    I.FromUnix(r, 253402300799, 999999999);  Is("FromUnix latest", r, 253402300799, 999999999);
    I.FromUnix(r, 253402300800, 0);  Is("FromUnix past latest", r, 253402300799, 999999999);
    I.FromUnix(r, -377705116801, 999999999);  Is("FromUnix before earliest", r, -377705116800, 0);
    I.FromUnixMilliseconds(r, 1500);  Is("FromUnixMilliseconds", r, 1, 500000000);
    I.FromUnixMilliseconds(r, -1);  Is("FromUnixMilliseconds -", r, -1, 999000000);
    I.FromUnix(r, -1, 999999999);
    T.Int("UnixSeconds", I.UnixSeconds(r), -1);
    T.Int("UnixMilliseconds", I.UnixMilliseconds(r), -1);
    I.FromUnix(r, -2, 1);
    T.Int("UnixMilliseconds floor", I.UnixMilliseconds(r), -2000);
    T.Int("UnixMilliseconds latest", I.UnixMilliseconds(I.latest), 253402300799999);
    T.Int("UnixMilliseconds earliest", I.UnixMilliseconds(I.earliest), -377705116800000)
  END Construction;

  PROCEDURE Arithmetic;
  BEGIN
    I.FromUnix(a, 100, 900000000);
    I.Add(r, a, 200 * D.millisecond);  Is("Add carry", r, 101, 100000000);
    I.Add(r, a, -1);  Is("Add -", r, 100, 899999999);
    I.Add(r, a, -1000 * D.millisecond);  Is("Add -1 s", r, 99, 900000000);
    I.Subtract(r, a, 1000 * D.millisecond);  Is("Subtract", r, 99, 900000000);
    I.Subtract(r, a, -200 * D.millisecond);  Is("Subtract -", r, 101, 100000000);
    I.Add(r, a, D.max);  Is("Add max", r, 9223372137, 754775807);
    I.Add(r, a, D.min);  Is("Add min", r, -9223371936, 45224192);
    I.Subtract(r, a, D.min);  Is("Subtract min", r, 9223372137, 754775808);
    I.Subtract(r, a, D.max);  Is("Subtract max", r, -9223371936, 45224193);
    I.Add(r, I.latest, 1);  Is("Add past latest", r, 253402300799, 999999999);
    I.Subtract(r, I.earliest, 1);  Is("Subtract past earliest", r, -377705116800, 0);
    a := r;  I.Add(a, a, s);  Is("Add in place", a, -377705116799, 0);

    I.FromUnix(a, 10, 0);  I.FromUnix(b, 3, 500000000);
    T.Int("Between", I.Between(a, b), 6500 * D.millisecond);
    T.Int("Between -", I.Between(b, a), -6500 * D.millisecond);
    T.Int("Between ends", I.Between(I.latest, I.earliest), D.max);
    T.Int("Between ends -", I.Between(I.earliest, I.latest), D.min);
    (* the largest and smallest Durations, exactly, and one past each *)
    I.FromUnix(a, 9223372036, 854775807);  I.FromUnix(b, 0, 0);
    T.True("CheckedBetween max", I.CheckedBetween(d, a, b) & (d = D.max));
    I.FromUnix(a, 9223372036, 854775808);
    d := 1;
    T.True("CheckedBetween past max", ~I.CheckedBetween(d, a, b) & (d = 1));
    T.Int("Between past max", I.Between(a, b), D.max);
    I.FromUnix(a, -9223372037, 145224192);
    T.True("CheckedBetween min", I.CheckedBetween(d, a, b) & (d = D.min));
    I.FromUnix(a, -9223372037, 145224191);
    T.True("CheckedBetween past min", ~I.CheckedBetween(d, a, b));
    T.Int("Between past min", I.Between(a, b), D.min);
    (* the same, away from 0 *)
    I.FromUnix(a, 9223372036 + 1000, 854775807 + 500000000);  I.FromUnix(b, 1000, 500000000);
    T.True("CheckedBetween max offset", I.CheckedBetween(d, a, b) & (d = D.max))
  END Arithmetic;

  PROCEDURE Comparisons;
  BEGIN
    I.FromUnix(a, 5, 1);  I.FromUnix(b, 5, 2);
    T.Int("Compare <", I.Compare(a, b), -1);
    T.Int("Compare >", I.Compare(b, a), 1);
    T.Int("Compare =", I.Compare(a, a), 0);
    I.FromUnix(b, 4, 2);
    T.Int("Compare seconds", I.Compare(a, b), 1);
    T.True("Equal", I.Equal(a, a) & ~I.Equal(a, b));
    T.True("Before", I.Before(b, a) & ~I.Before(a, b) & ~I.Before(a, a))
  END Comparisons;

  PROCEDURE Truncation;
  BEGIN
    I.FromUnix(a, 3725, 123456789);
    I.Truncate(r, a, D.millisecond);  Is("Truncate ms", r, 3725, 123000000);
    I.Truncate(r, a, D.nanosecond);  Is("Truncate ns", r, 3725, 123456789);
    I.Truncate(r, a, s);  Is("Truncate s", r, 3725, 0);
    I.Truncate(r, a, D.hour);  Is("Truncate hour", r, 3600, 0);
    I.Truncate(r, a, D.day);  Is("Truncate day", r, 0, 0);
    I.FromUnix(a, -1, 500000000);
    I.Truncate(r, a, s);  Is("Truncate s -", r, -1, 0);
    I.Truncate(r, a, D.minute);  Is("Truncate minute -", r, -60, 0);
    I.Truncate(r, a, D.day);  Is("Truncate day -", r, -86400, 0);
    I.Truncate(r, I.earliest, D.week);  Is("Truncate earliest", r, -377705116800, 0);
    I.Truncate(r, I.latest, D.millisecond);  Is("Truncate latest", r, 253402300799, 999000000);
    (* units that neither divide a second nor are whole seconds *)
    I.FromUnix(a, 3725, 123456789);
    I.Truncate(r, a, 7 * D.millisecond);  Is("Truncate 7 ms", r, 3725, 120000000);
    I.Truncate(r, a, 1500 * D.millisecond);  Is("Truncate 1.5 s", r, 3724, 500000000);
    I.FromUnix(a, -1, 0);
    I.Truncate(r, a, 1500 * D.millisecond);  Is("Truncate 1.5 s -", r, -2, 500000000);
    I.Truncate(r, I.earliest, D.day + 1);  Is("Truncate before earliest", r, -377705116800, 0);
    I.Truncate(r, I.latest, D.max);  Is("Truncate latest max", r, 249031044995, 78946789)
  END Truncation;

  PROCEDURE Row(seconds, nanosecond, unit, truncatedSeconds, truncatedNanosecond: HUGEINT);
  BEGIN
    I.FromUnix(a, seconds, nanosecond);
    I.Truncate(r, a, unit);
    IF (r.seconds # truncatedSeconds) OR (r.nanosecond # truncatedNanosecond) THEN
      T.Failed("Truncate table", seconds, nanosecond, unit);  INC(tableFailures)
    END
  END Row;

  PROCEDURE Table;
  BEGIN
    tableFailures := 0;
    InstantsData.Each(Row);
    T.Count(1);
    T.Int("Truncate table failures", tableFailures, 0);
    T.True("Truncate table size", InstantsData.Count() > 900)
  END Table;

BEGIN
  T.Start("Instants");
  Construction;  Arithmetic;  Comparisons;  Truncation;  Table;
  T.Finish
END InstantsTest.
