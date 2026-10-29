MODULE DurationsTest;

  (* Tests of Durations, above all at the edges, where it saturates. The
     checks with a NaN or an infinity run only where a LONGREAL has them
     (RealFormat, design Q25). *)

  IMPORT D := Durations, RF := RealFormat, T := TimeTests;

  CONST
    max = D.max;  min = D.min;
    s = D.second;

  VAR
    r: D.Duration;
    negative: BOOLEAN;
    days, hours, minutes, seconds, nanoseconds: LONGINT;
    (* a LONGREAL result is compared once stored here: on i386 it comes
       back in an x87 register with 80 bits, and is rounded to 64 only
       when stored *)
    stored: LONGREAL;

  PROCEDURE Constants;
  BEGIN
    T.Int("minute", D.minute, 60000000000);
    T.Int("hour", D.hour, 3600000000000);
    T.Int("day", D.day, 86400000000000);
    T.Int("week", D.week, 604800000000000)
  END Constants;

  PROCEDURE Sums;
  BEGIN
    T.Int("Sum", D.Sum(2, 3), 5);
    T.Int("Sum max", D.Sum(max, 1), max);
    T.Int("Sum max-1", D.Sum(max - 1, 1), max);
    T.Int("Sum min", D.Sum(min, -1), min);
    T.Int("Sum min max", D.Sum(min, max), -1);
    T.Int("Difference", D.Difference(2, 3), -1);
    T.Int("Difference max", D.Difference(max, -1), max);
    T.Int("Difference min", D.Difference(min, 1), min);
    T.Int("Difference 0 min", D.Difference(0, min), max);
    T.Int("Difference -1 min", D.Difference(-1, min), max);
    T.Int("Difference min min", D.Difference(min, min), 0);
    T.Int("Of", D.Of(1, 2, 3, 4, 5), D.day + 2 * D.hour + 3 * D.minute + 4 * s + 5);
    T.Int("Of negative", D.Of(0, -1, 30, 0, 0), -30 * D.minute);
    T.Int("Of max", D.Of(106752, 0, 0, 0, 0), max);
    T.Int("Of min", D.Of(-106752, 0, 0, 0, 0), min);
    T.Int("Of huge", D.Of(0, 0, 0, max, 0), max)
  END Sums;

  PROCEDURE Scales;
  BEGIN
    T.Int("Scale", D.Scale(D.minute, 90), 90 * D.minute);
    T.Int("Scale -", D.Scale(D.minute, -2), -2 * D.minute);
    T.Int("Scale max", D.Scale(max, 2), max);
    T.Int("Scale max -", D.Scale(max, -2), min);
    T.Int("Scale max -1", D.Scale(max, -1), -max);
    T.Int("Scale min -1", D.Scale(min, -1), max);
    T.Int("Scale -1 min", D.Scale(-1, min), max);
    T.Int("Scale min 1", D.Scale(min, 1), min);
    T.Int("Scale min 0", D.Scale(min, 0), 0);
    T.Int("Scale - -", D.Scale(-3037000500, -3037000500), max);
    T.Int("Scale - - fits", D.Scale(-3037000499, -3037000499), 9223372030926249001);
    T.Int("Scale half min", D.Scale(-4611686018427387904, 2), min);
    T.Int("Scale half min +", D.Scale(4611686018427387904, -2), min);
    T.Int("Scale past half min", D.Scale(-4611686018427387905, 2), min);
    T.True("CheckedScale", D.CheckedScale(r, 7, 6) & (r = 42));
    r := 5;
    T.True("CheckedScale overflow", ~D.CheckedScale(r, max DIV 2 + 1, 2) & (r = 5));
    T.True("CheckedScale half min", D.CheckedScale(r, -4611686018427387904, 2) & (r = min));
    T.True("CheckedScale min -1", ~D.CheckedScale(r, min, -1));
    T.True("CheckedScale - - edge", ~D.CheckedScale(r, -3037000500, -3037000500));
    T.Int("Abs", D.Abs(-5), 5);
    T.Int("Abs min", D.Abs(min), max);
    T.Int("Abs max", D.Abs(max), max)
  END Scales;

  PROCEDURE Rounding;
  BEGIN
    T.Int("Whole", D.Whole(90 * D.minute, D.hour), 1);
    T.Int("Whole -", D.Whole(-90 * D.minute, D.hour), -1);
    T.Int("Whole exact -", D.Whole(-2 * D.hour, D.hour), -2);
    T.Int("Whole min", D.Whole(min, s), -9223372036);
    T.Int("Truncate", D.Truncate(1500, 1000), 1000);
    T.Int("Truncate -", D.Truncate(-1500, 1000), -1000);
    T.Int("Truncate min", D.Truncate(min, s), -9223372036000000000);
    T.Int("Floor", D.Floor(1500, 1000), 1000);
    T.Int("Floor -", D.Floor(-1500, 1000), -2000);
    T.Int("Floor exact", D.Floor(-2000, 1000), -2000);
    T.Int("Floor min", D.Floor(min, s), min);
    T.Int("Floor min+1", D.Floor(min + 1, s), min);
    T.Int("Round half", D.Round(1500, 1000), 2000);
    T.Int("Round below", D.Round(1499, 1000), 1000);
    T.Int("Round half -", D.Round(-1500, 1000), -2000);
    T.Int("Round below -", D.Round(-1499, 1000), -1000);
    T.Int("Round odd unit", D.Round(2, 3), 3);
    T.Int("Round odd unit 1", D.Round(1, 3), 0);
    T.Int("Round max", D.Round(max, s), max);
    T.Int("Round min", D.Round(min, s), min);
    T.Int("Round big unit", D.Round(max, max), max);
    T.Int("Round big unit half", D.Round(max DIV 2 + 1, max), max);
    T.Int("Round big unit below", D.Round(max DIV 2, max), 0)
  END Rounding;

  PROCEDURE Splits;
  BEGIN
    D.Split(D.Of(1, 2, 3, 4, 5), negative, days, hours, minutes, seconds, nanoseconds);
    T.True("Split", ~negative & (days = 1) & (hours = 2) & (minutes = 3) & (seconds = 4)
      & (nanoseconds = 5));
    D.Split(-D.Of(1, 2, 3, 4, 5), negative, days, hours, minutes, seconds, nanoseconds);
    T.True("Split -", negative & (days = 1) & (hours = 2) & (minutes = 3) & (seconds = 4)
      & (nanoseconds = 5));
    (* 9223372036854775808 ns is 106751 d 23:47:16.854775808 *)
    D.Split(min, negative, days, hours, minutes, seconds, nanoseconds);
    T.True("Split min", negative & (days = 106751) & (hours = 23) & (minutes = 47)
      & (seconds = 16) & (nanoseconds = 854775808));
    D.Split(max, negative, days, hours, minutes, seconds, nanoseconds);
    T.True("Split max", ~negative & (days = 106751) & (hours = 23) & (minutes = 47)
      & (seconds = 16) & (nanoseconds = 854775807));
    D.Split(0, negative, days, hours, minutes, seconds, nanoseconds);
    T.True("Split 0", ~negative & (days = 0) & (nanoseconds = 0))
  END Splits;

  PROCEDURE Seconds;
    VAR x: LONGREAL;
  BEGIN
    T.True("ToSeconds", D.ToSeconds(1500 * D.millisecond) = 1.5D0);
    T.True("ToSeconds -", D.ToSeconds(-1500 * D.millisecond) = -1.5D0);
    stored := D.ToSeconds(max);  T.True("ToSeconds max", stored = 9223372036.854775807D0);
    T.Int("FromSeconds", D.FromSeconds(1.5D0), 1500 * D.millisecond);
    T.Int("FromSeconds -", D.FromSeconds(-1.5D0), -1500 * D.millisecond);
    T.Int("FromSeconds round", D.FromSeconds(0.0000000005D0), 1);
    T.Int("FromSeconds round -", D.FromSeconds(-0.0000000005D0), -1);
    T.Int("FromSeconds day", D.FromSeconds(86400.0D0), D.day);
    T.Int("FromSeconds year", D.FromSeconds(31536000.0D0), 365 * D.day);
    (* 2^62 ns, exactly representable *)
    T.Int("FromSeconds 2^62", D.FromSeconds(4611686018.427387904D0), 4611686018427387904);
    T.Int("FromSeconds -2^62", D.FromSeconds(-4611686018.427387904D0), -4611686018427387904);
    T.Int("FromSeconds max", D.FromSeconds(9223372037.0D0), max);
    T.Int("FromSeconds min", D.FromSeconds(-9223372037.0D0), min);
    T.Int("FromSeconds -2^63", D.FromSeconds(-9223372036.854775808D0), min);
    T.Int("FromSeconds huge", D.FromSeconds(1.0D300), max);
    T.Int("FromSeconds -huge", D.FromSeconds(-1.0D300), min);
    T.Int("FromSeconds largest", D.FromSeconds(MAX(LONGREAL)), max);
    T.Int("FromSeconds -largest", D.FromSeconds(-MAX(LONGREAL)), min);
    r := 7;
    IF RF.ieee THEN
      x := 0.0D0;  x := x / x;
      T.Int("FromSeconds NaN", D.FromSeconds(x), 0);
      T.True("CheckedFromSeconds NaN", ~D.CheckedFromSeconds(r, x) & (r = 7));
      x := 1.0D300;  x := x * x;
      T.Int("FromSeconds infinity", D.FromSeconds(x), max);
      T.Int("FromSeconds -infinity", D.FromSeconds(-x), min);
      T.True("CheckedFromSeconds infinity", ~D.CheckedFromSeconds(r, x) & (r = 7))
    END;
    T.True("CheckedFromSeconds max", ~D.CheckedFromSeconds(r, 9223372037.0D0));
    T.True("CheckedFromSeconds", D.CheckedFromSeconds(r, 2.0D0) & (r = 2 * s))
  END Seconds;

BEGIN
  T.Start("Durations");
  Constants;  Sums;  Scales;  Rounding;  Splits;  Seconds;
  T.Finish
END DurationsTest.
