MODULE TimeStringsTest;

  (* Tests of TimeStrings' fixed formats: what each writer gives, against
     strings written by hand and against Python's datetime.isoformat
     (test/data/StringsData.Mod); round trips of every writer through its
     reader, over the whole range; and strings the readers must refuse,
     leaving their result and pos alone. *)

  IMPORT C := Calendar, D := Durations, I := Instants, S := TimeStrings, StringsData,
    T := TimeTests;

  CONST trips = 20000;

  VAR
    s: ARRAY 128 OF CHAR;
    seed: HUGEINT;

  (* 0 .. n - 1, from a linear congruential generator, which wraps *)
  PROCEDURE Random(n: HUGEINT): HUGEINT;
  BEGIN
    seed := seed * 6364136223846793005 + 1442695040888963407;
    RETURN (seed DIV 65536) MOD n
  END Random;

  PROCEDURE SetDate(VAR d: C.Date; year, month, day: LONGINT);
  BEGIN
    ASSERT(C.SetDate(d, year, month, day))
  END SetDate;

  PROCEDURE SetDateTime(VAR dt: C.DateTime; year, month, day, hour, minute, second, nanosecond: LONGINT);
  BEGIN
    ASSERT(C.SetDateTime(dt, year, month, day, hour, minute, second, nanosecond))
  END SetDateTime;

  PROCEDURE SetOffset(VAR odt: C.OffsetDateTime; year, month, day, hour, minute, second,
                      nanosecond, offset: LONGINT);
  BEGIN
    SetDateTime(odt, year, month, day, hour, minute, second, nanosecond);  odt.offset := offset
  END SetOffset;

  PROCEDURE SetTime(VAR t: C.TimeOfDay; hour, minute, second, nanosecond: LONGINT);
  BEGIN
    ASSERT(C.SetTimeOfDay(t, hour, minute, second, nanosecond))
  END SetTime;

  PROCEDURE SetPeriod(VAR p: C.Period; years, months, days: LONGINT);
  BEGIN
    p.years := years;  p.months := months;  p.days := days
  END SetPeriod;

  PROCEDURE Dates;
    VAR d: C.Date; dt: C.DateTime;
  BEGIN
    SetDate(d, 2026, 10, 28);  s := "";  S.Date(d, s);  T.Str("Date", s, "2026-10-28");
    SetDate(d, -44, 3, 15);  s := "";  S.Date(d, s);  T.Str("Date -44", s, "-0044-03-15");
    SetDate(d, 0, 1, 1);  s := "";  S.Date(d, s);  T.Str("Date 0", s, "0000-01-01");
    SetDate(d, -1, 12, 31);  s := "";  S.Date(d, s);  T.Str("Date -1", s, "-0001-12-31");
    SetDate(d, -9999, 1, 1);  s := "";  S.Date(d, s);  T.Str("Date first", s, "-9999-01-01");
    SetDate(d, 9999, 12, 31);  s := "";  S.Date(d, s);  T.Str("Date last", s, "9999-12-31");
    (* a DateTime is a Date: only the date is written *)
    SetDateTime(dt, 2026, 10, 28, 14, 5, 9, 0);  s := "";  S.Date(dt, s);
    T.Str("Date of a DateTime", s, "2026-10-28")
  END Dates;

  PROCEDURE Times;
    VAR t: C.TimeOfDay;
  BEGIN
    SetTime(t, 14, 5, 9, 500000000);
    s := "";  S.TimeOfDay(t, 1, s);  T.Str("TimeOfDay 1", s, "14:05:09.5");
    s := "";  S.TimeOfDay(t, S.shortest, s);  T.Str("TimeOfDay shortest", s, "14:05:09.500");
    s := "";  S.TimeOfDay(t, 0, s);  T.Str("TimeOfDay 0", s, "14:05:09");
    s := "";  S.TimeOfDay(t, 9, s);  T.Str("TimeOfDay 9", s, "14:05:09.500000000");
    SetTime(t, 0, 0, 0, 0);
    s := "";  S.TimeOfDay(t, S.shortest, s);  T.Str("TimeOfDay midnight", s, "00:00:00");
    SetTime(t, 23, 59, 59, 999999999);
    s := "";  S.TimeOfDay(t, 3, s);  T.Str("TimeOfDay cut, not rounded", s, "23:59:59.999");
    s := "";  S.TimeOfDay(t, S.shortest, s);  T.Str("TimeOfDay shortest 9", s, "23:59:59.999999999");
    SetTime(t, 1, 2, 3, 120000);
    s := "";  S.TimeOfDay(t, S.shortest, s);  T.Str("TimeOfDay shortest 6", s, "01:02:03.000120")
  END Times;

  PROCEDURE DateTimes;
    VAR dt: C.DateTime; odt: C.OffsetDateTime; t: I.Instant;
  BEGIN
    SetDateTime(dt, 2026, 10, 28, 14, 5, 9, 0);
    s := "";  S.DateTime(dt, S.shortest, s);  T.Str("DateTime", s, "2026-10-28T14:05:09");
    SetOffset(odt, 2026, 10, 28, 14, 5, 9, 0, -4 * 3600);
    s := "";  S.OffsetDateTime(odt, S.shortest, s);
    T.Str("OffsetDateTime", s, "2026-10-28T14:05:09-04:00");
    odt.offset := 0;  s := "";  S.OffsetDateTime(odt, 3, s);
    T.Str("OffsetDateTime Z", s, "2026-10-28T14:05:09.000Z");
    odt.offset := 5 * 3600 + 30 * 60;  s := "";  S.OffsetDateTime(odt, 0, s);
    T.Str("OffsetDateTime +05:30", s, "2026-10-28T14:05:09+05:30");
    odt.offset := -(25 * 3600 + 59 * 60 + 59);  s := "";  S.OffsetDateTime(odt, 0, s);
    T.Str("OffsetDateTime -25:59:59", s, "2026-10-28T14:05:09-25:59:59");
    odt.offset := 1172;  s := "";  S.OffsetDateTime(odt, 0, s);
    T.Str("OffsetDateTime seconds", s, "2026-10-28T14:05:09+00:19:32");
    odt.offset := -1;  s := "";  S.OffsetDateTime(odt, 0, s);
    T.Str("OffsetDateTime -1 s", s, "2026-10-28T14:05:09-00:00:01");
    I.FromUnix(t, 1793193906, 120000000);
    s := "";  S.Instant(t, S.shortest, s);  T.Str("Instant", s, "2026-10-28T13:25:06.120Z");
    s := "";  S.Instant(I.earliest, S.shortest, s);  T.Str("Instant earliest", s, "-9999-01-01T00:00:00Z");
    s := "";  S.Instant(I.latest, S.shortest, s);
    T.Str("Instant latest", s, "9999-12-31T23:59:59.999999999Z");
    s := "";  S.Instant(I.latest, 0, s);  T.Str("Instant latest 0", s, "9999-12-31T23:59:59Z")
  END DateTimes;

  PROCEDURE Spans;
  BEGIN
    s := "";  S.Duration(0, s);  T.Str("Duration 0", s, "PT0S");
    s := "";  S.Duration(90 * D.minute, s);  T.Str("Duration 90 min", s, "PT1H30M");
    s := "";  S.Duration(-D.second DIV 2, s);  T.Str("Duration -0.5 s", s, "-PT0.5S");
    s := "";  S.Duration(26 * D.hour, s);  T.Str("Duration 26 h", s, "PT26H");
    s := "";  S.Duration(D.hour + D.second DIV 2, s);  T.Str("Duration 1 h 0.5 s", s, "PT1H0.5S");
    s := "";  S.Duration(1, s);  T.Str("Duration 1 ns", s, "PT0.000000001S");
    s := "";  S.Duration(D.minute, s);  T.Str("Duration 1 min", s, "PT1M");
    s := "";  S.Duration(D.max, s);  T.Str("Duration max", s, "PT2562047H47M16.854775807S");
    s := "";  S.Duration(D.min, s);  T.Str("Duration min", s, "-PT2562047H47M16.854775808S");
    s := "";  S.Elapsed(26 * D.hour + 3 * D.minute + 4 * D.second + D.second DIV 2, 1, s);
    T.Str("Elapsed", s, "26:03:04.5");
    s := "";  S.Elapsed(-D.second, S.shortest, s);  T.Str("Elapsed -1 s", s, "-0:00:01");
    s := "";  S.Elapsed(0, S.shortest, s);  T.Str("Elapsed 0", s, "0:00:00");
    s := "";  S.Elapsed(D.min, 9, s);  T.Str("Elapsed min", s, "-2562047:47:16.854775808");
    s := "";  S.Elapsed(D.second DIV 2, S.shortest, s);  T.Str("Elapsed shortest", s, "0:00:00.500")
  END Spans;

  PROCEDURE Periods;
    VAR p: C.Period;
  BEGIN
    SetPeriod(p, 1, 2, 3);  s := "";  S.Period(p, s);  T.Str("Period", s, "P1Y2M3D");
    SetPeriod(p, 0, 0, 0);  s := "";  S.Period(p, s);  T.Str("Period 0", s, "P0D");
    SetPeriod(p, 0, -1, 0);  s := "";  S.Period(p, s);  T.Str("Period -1 M", s, "-P1M");
    SetPeriod(p, -1, -2, -3);  s := "";  S.Period(p, s);  T.Str("Period negative", s, "-P1Y2M3D");
    SetPeriod(p, 1, -2, 0);  s := "";  S.Period(p, s);  T.Str("Period mixed", s, "P1Y-2M");
    SetPeriod(p, -1, 2, -3);  s := "";  S.Period(p, s);  T.Str("Period mixed 2", s, "P-1Y2M-3D");
    SetPeriod(p, 0, 0, 45);  s := "";  S.Period(p, s);  T.Str("Period days", s, "P45D");
    SetPeriod(p, MIN(LONGINT), 0, 0);  s := "";  S.Period(p, s);
    IF MAX(LONGINT) = 2147483647 THEN T.Str("Period MIN", s, "-P2147483648Y")
    ELSE T.Str("Period MIN", s, "-P9223372036854775808Y")
    END
  END Periods;

  (* appended at the first 0X, cut short, always ending in 0X *)
  PROCEDURE Appending;
    VAR d: C.Date; short: ARRAY 5 OF CHAR; full: ARRAY 3 OF CHAR;
  BEGIN
    SetDate(d, 2026, 10, 28);
    s := "on ";  S.Date(d, s);  T.Str("appended", s, "on 2026-10-28");
    short := "";  S.Date(d, short);  T.Str("cut short", short, "2026");
    full[0] := "a";  full[1] := "b";  full[2] := "c";  S.Date(d, full);
    T.True("no 0X", (full[0] = "a") & (full[1] = "b") & (full[2] = 0X))
  END Appending;

  PROCEDURE Row(seconds, nanosecond, offset: HUGEINT; digits: INTEGER; text: ARRAY OF CHAR);
    VAR t, u: I.Instant; odt: C.OffsetDateTime; pos: LONGINT;
  BEGIN
    I.FromUnix(t, seconds, nanosecond);
    C.FromInstant(odt, t, SHORT(offset));
    s := "";  S.OffsetDateTime(odt, digits, s);
    IF s # text THEN T.Str("table OffsetDateTime", s, text) END;
    pos := 0;
    IF ~S.ReadInstant(u, text, pos) OR (pos # LEN(text) - 1) THEN T.Str("table ReadInstant", "FALSE", text)
    ELSE
      (* the text keeps only digits of the nanosecond *)
      IF digits = 0 THEN I.Truncate(t, t, D.second)
      ELSIF digits = 3 THEN I.Truncate(t, t, D.millisecond)
      ELSE I.Truncate(t, t, D.microsecond)
      END;
      IF ~I.Equal(t, u) THEN T.Failed("table ReadInstant", seconds, nanosecond, offset) END
    END
  END Row;

  PROCEDURE Table;
  BEGIN
    StringsData.Each(Row);
    T.Count(StringsData.Count());
    T.True("table size", StringsData.Count() > 2500)
  END Table;

  (* ---- readers ---- *)

  PROCEDURE ReadsDate(label, text: ARRAY OF CHAR; year, month, day, end: LONGINT);
    VAR d: C.Date; pos: LONGINT;
  BEGIN
    pos := 0;
    T.True(label, S.ReadDate(d, text, pos) & (d.year = year) & (d.month = month)
      & (d.day = day) & (pos = end))
  END ReadsDate;

  PROCEDURE ReadsOffset(label, text: ARRAY OF CHAR; year, month, day, hour, minute, second,
                        nanosecond, offset: LONGINT);
    VAR odt: C.OffsetDateTime; pos: LONGINT;
  BEGIN
    pos := 0;
    T.True(label, S.ReadOffsetDateTime(odt, text, pos) & (odt.year = year) & (odt.month = month)
      & (odt.day = day) & (odt.hour = hour) & (odt.minute = minute) & (odt.second = second)
      & (odt.nanosecond = nanosecond) & (odt.offset = offset) & (pos = LEN(text) - 1))
  END ReadsOffset;

  PROCEDURE ReadsDuration(label, text: ARRAY OF CHAR; d: D.Duration);
    VAR r: D.Duration; pos: LONGINT;
  BEGIN
    pos := 0;
    T.True(label, S.ReadDuration(r, text, pos) & (r = d) & (pos = LEN(text) - 1))
  END ReadsDuration;

  PROCEDURE ReadsPeriod(label, text: ARRAY OF CHAR; years, months, days: LONGINT);
    VAR p: C.Period; pos: LONGINT;
  BEGIN
    pos := 0;
    T.True(label, S.ReadPeriod(p, text, pos) & (p.years = years) & (p.months = months)
      & (p.days = days) & (pos = LEN(text) - 1))
  END ReadsPeriod;

  PROCEDURE Reading;
    VAR
      d: C.Date; t: C.TimeOfDay; dt: C.DateTime; odt: C.OffsetDateTime; i: I.Instant;
      pos: LONGINT;
  BEGIN
    ReadsDate("ReadDate", "2026-10-28", 2026, 10, 28, 10);
    ReadsDate("ReadDate -44", "-0044-03-15", -44, 3, 15, 11);
    ReadsDate("ReadDate leaves the rest", "2026-10-28T14:05", 2026, 10, 28, 10);
    pos := 3;
    T.True("ReadDate at pos", S.ReadDate(d, "on 2026-10-28.", pos) & (pos = 13) & (d.day = 28));
    (* a DateTime through a VAR Date: only the date changes *)
    SetDateTime(dt, 2000, 1, 1, 12, 34, 56, 7);  pos := 0;
    T.True("ReadDate into a DateTime", S.ReadDate(dt, "2026-10-28", pos)
      & (dt.year = 2026) & (dt.hour = 12) & (dt.nanosecond = 7));

    pos := 0;
    T.True("ReadTimeOfDay", S.ReadTimeOfDay(t, "14:05:09.5", pos) & (t.hour = 14)
      & (t.minute = 5) & (t.second = 9) & (t.nanosecond = 500000000) & (pos = 10));
    pos := 0;
    T.True("ReadTimeOfDay 9 digits", S.ReadTimeOfDay(t, "23:59:59.123456789", pos)
      & (t.nanosecond = 123456789));

    pos := 0;
    T.True("ReadDateTime", S.ReadDateTime(dt, "2026-10-28T14:05:09", pos)
      & (dt.year = 2026) & (dt.hour = 14) & (dt.second = 9) & (pos = 19));
    pos := 0;
    T.True("ReadDateTime t", S.ReadDateTime(dt, "2026-10-28t14:05:09", pos));
    pos := 0;
    T.True("ReadDateTime space", S.ReadDateTime(dt, "2026-10-28 14:05:09", pos));
    pos := 0;
    T.True("ReadDateTime leaves the offset", S.ReadDateTime(dt, "2026-10-28T14:05:09Z", pos)
      & (pos = 19));

    ReadsOffset("ReadOffsetDateTime", "2026-10-28T14:05:09-04:00", 2026, 10, 28, 14, 5, 9, 0, -14400);
    ReadsOffset("ReadOffsetDateTime z", "2026-10-28T14:05:09.25z", 2026, 10, 28, 14, 5, 9, 250000000, 0);
    ReadsOffset("ReadOffsetDateTime +hh", "2026-10-28T14:05:09+05", 2026, 10, 28, 14, 5, 9, 0, 18000);
    ReadsOffset("ReadOffsetDateTime +hh:mm:ss", "2026-10-28T14:05:09+00:19:32",
      2026, 10, 28, 14, 5, 9, 0, 1172);
    ReadsOffset("ReadOffsetDateTime -00:00", "2026-10-28T14:05:09-00:00", 2026, 10, 28, 14, 5, 9, 0, 0);
    ReadsOffset("ReadOffsetDateTime +25:59:59", "2026-10-28T14:05:09+25:59:59",
      2026, 10, 28, 14, 5, 9, 0, 93599);
    (* valid as an OffsetDateTime, though before Instants.earliest *)
    ReadsOffset("ReadOffsetDateTime before earliest", "-9999-01-01T00:00:00+01:00",
      -9999, 1, 1, 0, 0, 0, 0, 3600);

    pos := 0;
    T.True("ReadInstant", S.ReadInstant(i, "2026-10-28T09:25:06.12-04:00", pos)
      & (i.seconds = 1793193906) & (i.nanosecond = 120000000) & (pos = 28));
    pos := 0;
    T.True("ReadInstant earliest", S.ReadInstant(i, "-9999-01-01T01:00:00+01:00", pos)
      & I.Equal(i, I.earliest));
    pos := 0;
    T.True("ReadInstant latest", S.ReadInstant(i, "9999-12-31T23:59:59.999999999Z", pos)
      & I.Equal(i, I.latest));

    ReadsDuration("ReadDuration", "PT1H30M", 90 * D.minute);
    ReadsDuration("ReadDuration -0.5 s", "-PT0.5S", -D.second DIV 2);
    ReadsDuration("ReadDuration 0", "PT0S", 0);
    ReadsDuration("ReadDuration D W", "P1W2DT3H", 9 * D.day + 3 * D.hour);
    ReadsDuration("ReadDuration D", "P1D", D.day);
    ReadsDuration("ReadDuration 9 digits", "PT0.000000001S", 1);
    ReadsDuration("ReadDuration big", "PT100000S", 100000 * D.second);
    ReadsDuration("ReadDuration max", "PT2562047H47M16.854775807S", D.max);
    ReadsDuration("ReadDuration min", "-PT2562047H47M16.854775808S", D.min);
    ReadsDuration("ReadDuration min seconds", "-PT9223372036.854775808S", D.min);
    ReadsDuration("ReadDuration elapsed", "26:03:04.5", 26 * D.hour + 3 * D.minute + 4 * D.second
      + D.second DIV 2);
    ReadsDuration("ReadDuration elapsed -", "-0:00:01", -D.second);
    ReadsDuration("ReadDuration elapsed min", "-2562047:47:16.854775808", D.min);

    ReadsPeriod("ReadPeriod", "P1Y2M3D", 1, 2, 3);
    ReadsPeriod("ReadPeriod W", "P1Y2M3W4D", 1, 2, 25);
    ReadsPeriod("ReadPeriod 0", "P0D", 0, 0, 0);
    ReadsPeriod("ReadPeriod -", "-P1M", 0, -1, 0);
    ReadsPeriod("ReadPeriod mixed", "P1Y-2M", 1, -2, 0);
    ReadsPeriod("ReadPeriod - mixed", "-P1Y-2M", -1, 2, 0);
    ReadsPeriod("ReadPeriod W and D signs", "P-1W2D", 0, 0, -5);
    IF MAX(LONGINT) = 2147483647 THEN
      ReadsPeriod("ReadPeriod MIN", "-P2147483648Y", MIN(LONGINT), 0, 0);
      ReadsPeriod("ReadPeriod MIN field", "P-2147483648Y", MIN(LONGINT), 0, 0)
    ELSE
      ReadsPeriod("ReadPeriod MIN", "-P9223372036854775808Y", MIN(LONGINT), 0, 0);
      ReadsPeriod("ReadPeriod MIN field", "P-9223372036854775808Y", MIN(LONGINT), 0, 0)
    END
  END Reading;

  (* :60 where UTC is 23:59:60 on a month's last day (doc/leap-seconds.md) *)
  PROCEDURE LeapSeconds;
    VAR i: I.Instant; dt: C.DateTime; t: C.TimeOfDay; pos: LONGINT;
  BEGIN
    ReadsOffset("leap Z", "2016-12-31T23:59:60Z", 2016, 12, 31, 23, 59, 59, 999999999, 0);
    ReadsOffset("leap -05:00", "2016-12-31T18:59:60-05:00", 2016, 12, 31, 18, 59, 59, 999999999, -18000);
    ReadsOffset("leap fraction ignored", "2016-12-31T23:59:60.5Z", 2016, 12, 31, 23, 59, 59, 999999999, 0);
    ReadsOffset("leap June", "2015-06-30T23:59:60Z", 2015, 6, 30, 23, 59, 59, 999999999, 0);
    pos := 0;
    T.True("leap ReadInstant", S.ReadInstant(i, "2016-12-31T23:59:60Z", pos)
      & (i.seconds = 1483228799) & (i.nanosecond = 999999999));
    pos := 0;
    T.True("leap not last day", ~S.ReadInstant(i, "2016-12-30T23:59:60Z", pos) & (pos = 0));
    pos := 0;
    T.True("leap not last minute", ~S.ReadInstant(i, "2016-12-31T23:58:60Z", pos));
    pos := 0;
    T.True("leap wrong offset", ~S.ReadInstant(i, "2016-12-31T23:59:60-05:00", pos));
    pos := 0;
    T.True("leap no offset", ~S.ReadDateTime(dt, "2016-12-31T23:59:60", pos));
    pos := 0;
    T.True("leap TimeOfDay", ~S.ReadTimeOfDay(t, "23:59:60", pos));
    pos := 0;
    T.True("leap 61", ~S.ReadInstant(i, "2016-12-31T23:59:61Z", pos))
  END LeapSeconds;

  (* ---- refused ---- *)

  PROCEDURE NoDate(text: ARRAY OF CHAR);
    VAR d: C.Date; pos: LONGINT;
  BEGIN
    SetDate(d, 1999, 9, 9);  pos := 0;
    IF S.ReadDate(d, text, pos) OR (pos # 0) OR (d.year # 1999) THEN T.Str("ReadDate refuses", "TRUE", text) END;
    T.Count(1)
  END NoDate;

  PROCEDURE NoTime(text: ARRAY OF CHAR);
    VAR t: C.TimeOfDay; pos: LONGINT;
  BEGIN
    SetTime(t, 9, 9, 9, 9);  pos := 0;
    IF S.ReadTimeOfDay(t, text, pos) OR (pos # 0) OR (t.nanosecond # 9) THEN
      T.Str("ReadTimeOfDay refuses", "TRUE", text)
    END;
    T.Count(1)
  END NoTime;

  PROCEDURE NoInstant(text: ARRAY OF CHAR);
    VAR i: I.Instant; pos: LONGINT;
  BEGIN
    I.FromUnix(i, 99, 9);  pos := 0;
    IF S.ReadInstant(i, text, pos) OR (pos # 0) OR (i.seconds # 99) THEN
      T.Str("ReadInstant refuses", "TRUE", text)
    END;
    T.Count(1)
  END NoInstant;

  PROCEDURE NoOffsetDateTime(text: ARRAY OF CHAR);
    VAR odt: C.OffsetDateTime; pos: LONGINT;
  BEGIN
    SetOffset(odt, 1999, 9, 9, 9, 9, 9, 9, 9);  pos := 0;
    IF S.ReadOffsetDateTime(odt, text, pos) OR (pos # 0) OR (odt.offset # 9) THEN
      T.Str("ReadOffsetDateTime refuses", "TRUE", text)
    END;
    T.Count(1)
  END NoOffsetDateTime;

  PROCEDURE NoDuration(text: ARRAY OF CHAR);
    VAR d: D.Duration; pos: LONGINT;
  BEGIN
    d := 99;  pos := 0;
    IF S.ReadDuration(d, text, pos) OR (pos # 0) OR (d # 99) THEN T.Str("ReadDuration refuses", "TRUE", text) END;
    T.Count(1)
  END NoDuration;

  PROCEDURE NoPeriod(text: ARRAY OF CHAR);
    VAR p: C.Period; pos: LONGINT;
  BEGIN
    SetPeriod(p, 9, 9, 9);  pos := 0;
    IF S.ReadPeriod(p, text, pos) OR (pos # 0) OR (p.years # 9) THEN T.Str("ReadPeriod refuses", "TRUE", text) END;
    T.Count(1)
  END NoPeriod;

  PROCEDURE Refused;
    VAR d: C.Date; t: C.TimeOfDay; pos: LONGINT;
  BEGIN
    NoDate("");  NoDate("2026");  NoDate("2026-10");  NoDate("2026-1-28");  NoDate("2026-10-2");
    NoDate("26-10-28");  NoDate("20261028");  NoDate("2026/10/28");  NoDate("2026-13-01");
    NoDate("2026-00-01");  NoDate("2026-02-29");  NoDate("2026-10-32");  NoDate("2026-10-00");
    NoDate("+2026-10-28");  NoDate("-0000-01-01");  NoDate("10000-01-01");  NoDate("-10000-01-01");
    NoDate(" 2026-10-28");  NoDate("2026-10-289");  NoDate("2026-1a-28");
    pos := 11;  T.True("ReadDate pos at end", ~S.ReadDate(d, "2026-10-28", pos) & (pos = 11));
    pos := 10;  T.True("ReadDate pos at 0X", ~S.ReadDate(d, "2026-10-28", pos));
    pos := -1;  T.True("ReadDate pos negative", ~S.ReadDate(d, "2026-10-28", pos) & (pos = -1));

    NoTime("");  NoTime("14:05");  NoTime("14");  NoTime("140509");  NoTime("24:00:00");
    NoTime("14:60:00");  NoTime("14:05:60");  NoTime("14:05:9");  NoTime("14:05:09.");
    NoTime("14:05:09.1234567890");  NoTime("14:05:091");
    NoTime("1:05:09");
    (* a comma is not a decimal sign: the time ends before it *)
    pos := 0;  T.True("ReadTimeOfDay comma", S.ReadTimeOfDay(t, "14:05:09,5", pos) & (pos = 8)
      & (t.nanosecond = 0));

    NoInstant("2026-10-28T14:05:09");  NoInstant("2026-10-28T14:05:09+0530");
    NoInstant("2026-10-28T14:05:09+5:30");  NoInstant("2026-10-28T14:05:09+05:3");
    NoInstant("2026-10-28T14:05:09+26:00");  NoInstant("2026-10-28T14:05:09+05:60");
    NoInstant("2026-10-28T14:05:09+05:30:60");  NoInstant("2026-10-28T14:05:09 Z");
    NoInstant("2026-10-28_14:05:09Z");  NoInstant("2026-10-28T14:05Z");
    NoInstant("20261028T140509Z");  NoInstant("2026-10-28T14:05:09Z1");
    NoInstant("-9999-01-01T00:00:00+01:00");  NoInstant("9999-12-31T23:59:59.999999999-00:00:01");
    NoInstant("9999-12-31T23:00:00-05:00");
    NoOffsetDateTime("2026-10-28T14:05:09");  NoOffsetDateTime("2026-10-28T14:05:09+26");
    NoOffsetDateTime("2026-10-28T14:05:09X");

    NoDuration("");  NoDuration("P");  NoDuration("PT");  NoDuration("P1DT");  NoDuration("P1Y");
    NoDuration("P1M");  NoDuration("PT1D");  NoDuration("PT1W");  NoDuration("PT1M1H");
    NoDuration("PT1H1H");  NoDuration("P1D1W");  NoDuration("PT0.5H");  NoDuration("PT0.5M");
    NoDuration("P0.5D");  NoDuration("PT.5S");  NoDuration("PT1.S");  NoDuration("PT1");
    NoDuration("PT-1H");  NoDuration("+PT1H");  NoDuration("pt1h");  NoDuration("PT1h");
    NoDuration("PT0.1234567890S");  NoDuration("PT2562047H47M16.854775808S");
    NoDuration("-PT2562047H47M16.854775809S");  NoDuration("PT9223372036854775808S");
    NoDuration("PT2562048H");  NoDuration("P106752D");
    NoDuration("1:00");  NoDuration("1:60:00");  NoDuration("1:00:60");  NoDuration(":00:00");
    NoDuration("1:0:00");  NoDuration("2562048:00:00");  NoDuration("-2562047:47:16.854775809");
    NoDuration("1:00:00.");  NoDuration("-");

    NoPeriod("");  NoPeriod("P");  NoPeriod("P1");  NoPeriod("P1H");  NoPeriod("PT1H");
    NoPeriod("P1M1Y");  NoPeriod("P1D1W");  NoPeriod("P1Y1Y");  NoPeriod("P1.5Y");  NoPeriod("P-");
    NoPeriod("P--1Y");  NoPeriod("P+1Y");  NoPeriod("p1y");  NoPeriod("1Y");
    IF MAX(LONGINT) = 2147483647 THEN
      NoPeriod("P2147483648Y");  NoPeriod("-P2147483649Y");  NoPeriod("P306783379W");
      NoPeriod("P1W2147483641D")
    ELSE
      NoPeriod("P9223372036854775808Y");  NoPeriod("-P9223372036854775809Y");
      NoPeriod("P1317624576693539402W");  NoPeriod("P1W9223372036854775801D")
    END
  END Refused;

  (* ---- round trips ---- *)

  (* every 1000th day or so, and the last *)
  PROCEDURE DateTrips;
    VAR d, r: C.Date; n, last: HUGEINT; pos, bad: LONGINT;
  BEGIN
    bad := 0;  SetDate(d, C.minYear, 1, 1);  n := C.DayNumber(d);
    SetDate(d, C.maxYear, 12, 31);  last := C.DayNumber(d);
    WHILE n <= last DO
      ASSERT(C.FromDayNumber(d, n));
      s := "";  S.Date(d, s);  pos := 0;
      IF ~S.ReadDate(r, s, pos) OR (C.CompareDates(d, r) # 0) OR (s[pos] # 0X) THEN
        INC(bad);  T.Str("Date trip", "FALSE", s)
      END;
      IF (n < last) & (n + 2000 > last) THEN n := last ELSE n := n + 1 + Random(1999) END
    END;
    T.Int("Date trips", bad, 0)
  END DateTrips;

  (* 10^n *)
  PROCEDURE Power(n: HUGEINT): HUGEINT;
    VAR x: HUGEINT;
  BEGIN
    x := 1;
    WHILE n > 0 DO x := x * 10;  DEC(n) END;
    RETURN x
  END Power;

  PROCEDURE Trips;
    VAR
      t, u: I.Instant; odt, o: C.OffsetDateTime; k, bad, pos, offset: LONGINT;
      d, r: D.Duration; p, q: C.Period;
  BEGIN
    bad := 0;
    FOR k := 1 TO trips DO
      I.FromUnix(t, I.earliest.seconds + Random(I.latest.seconds - I.earliest.seconds + 1),
        Random(D.second));
      s := "";  S.Instant(t, 9, s);  pos := 0;
      IF ~S.ReadInstant(u, s, pos) OR ~I.Equal(t, u) THEN INC(bad);  T.Str("Instant trip", "FALSE", s) END;
      offset := SHORT(Random(2 * 93599 + 1) - 93599);
      C.FromInstant(odt, t, offset);
      s := "";  S.OffsetDateTime(odt, S.shortest, s);  pos := 0;
      IF ~S.ReadOffsetDateTime(o, s, pos) OR (C.CompareDateTimes(odt, o) # 0) OR (o.offset # odt.offset) THEN
        INC(bad);  T.Str("OffsetDateTime trip", "FALSE", s)
      END
    END;
    T.Int("Instant trips", bad, 0);

    bad := 0;
    FOR k := 1 TO trips DO
      (* every size of duration, not only the huge ones a uniform draw gives *)
      d := Random(D.max) DIV Power(Random(19));
      IF Random(2) = 0 THEN d := -d END;
      IF k = 1 THEN d := D.min ELSIF k = 2 THEN d := D.max END;
      s := "";  S.Duration(d, s);  pos := 0;
      IF ~S.ReadDuration(r, s, pos) OR (r # d) OR (s[pos] # 0X) THEN INC(bad);  T.Str("Duration trip", "FALSE", s) END;
      s := "";  S.Elapsed(d, 9, s);  pos := 0;
      IF ~S.ReadDuration(r, s, pos) OR (r # d) OR (s[pos] # 0X) THEN INC(bad);  T.Str("Elapsed trip", "FALSE", s) END
    END;
    T.Int("Duration trips", bad, 0);

    bad := 0;
    FOR k := 1 TO trips DO
      SetPeriod(p, SHORT(Random(20001) - 10000), SHORT(Random(41) - 20), SHORT(Random(2001) - 1000));
      IF Random(4) = 0 THEN p.years := 0 END;
      IF Random(4) = 0 THEN p.months := 0 END;
      IF Random(4) = 0 THEN p.days := 0 END;
      IF k = 1 THEN SetPeriod(p, MIN(LONGINT), MAX(LONGINT), MIN(LONGINT)) END;
      s := "";  S.Period(p, s);  pos := 0;
      IF ~S.ReadPeriod(q, s, pos) OR (p.years # q.years) OR (p.months # q.months) OR (p.days # q.days) THEN
        INC(bad);  T.Str("Period trip", "FALSE", s)
      END
    END;
    T.Int("Period trips", bad, 0)
  END Trips;

BEGIN
  seed := 19700101;
  T.Start("TimeStrings");
  Dates;  Times;  DateTimes;  Spans;  Periods;  Appending;  Table;
  Reading;  LeapSeconds;  Refused;  DateTrips;  Trips;
  T.Finish
END TimeStringsTest.
