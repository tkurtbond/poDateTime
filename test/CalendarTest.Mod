MODULE CalendarTest;

  (* Tests of Calendar: every day of the years against a plain day-by-day
     count, a table from Python's datetime (test/data/CalendarData.Mod),
     and the arithmetic at month ends and the range's ends. *)

  IMPORT C := Calendar, D := Durations, I := Instants, CalendarData, T := TimeTests;

  VAR
    seed: HUGEINT;
    tableFailures: LONGINT;

  PROCEDURE IsDate(label: ARRAY OF CHAR; d: C.Date; year, month, day: LONGINT);
  BEGIN
    T.True(label, (d.year = year) & (d.month = month) & (d.day = day));
    IF (d.year # year) OR (d.month # month) OR (d.day # day) THEN
      T.Failed(label, d.year, d.month, d.day)
    END
  END IsDate;

  PROCEDURE IsTime(label: ARRAY OF CHAR; dt: C.DateTime; hour, minute, second, nanosecond: LONGINT);
  BEGIN
    T.True(label, (dt.hour = hour) & (dt.minute = minute) & (dt.second = second)
      & (dt.nanosecond = nanosecond));
    IF (dt.hour # hour) OR (dt.minute # minute) OR (dt.second # second)
      OR (dt.nanosecond # nanosecond) THEN
      T.Failed(label, dt.hour, dt.minute, dt.second)
    END
  END IsTime;

  (* a pseudo-random number in 0 .. n - 1, the same on every target *)
  PROCEDURE Random(n: HUGEINT): HUGEINT;
  BEGIN
    seed := seed * 6364136223846793005 + 1442695040888963407;
    RETURN seed DIV 65536 MOD n
  END Random;

  PROCEDURE RandomDate(VAR d: C.Date; low, high: HUGEINT);
    VAR ok: BOOLEAN;
  BEGIN
    ok := C.FromDayNumber(d, low + Random(high - low + 1));
    ASSERT(ok)
  END RandomDate;

  (* Every day from -9999-01-01 to 9999-12-31, against a date moved on a
     day at a time by the month lengths alone. *)
  PROCEDURE EveryDay;
    VAR n: HUGEINT; expected, d: C.Date; weekday, failures: LONGINT; ok: BOOLEAN;
  BEGIN
    ok := C.SetDate(expected, C.minYear, C.January, 1);
    weekday := C.Monday;  failures := 0;
    n := -4371587;
    WHILE (n <= 2932896) & (failures < 10) DO
      IF ~C.FromDayNumber(d, n) OR (d.year # expected.year) OR (d.month # expected.month)
        OR (d.day # expected.day) THEN
        T.Failed("FromDayNumber", n, d.month, d.day);  INC(failures)
      ELSIF C.DayNumber(d) # n THEN
        T.Failed("DayNumber", n, C.DayNumber(d), 0);  INC(failures)
      ELSIF C.DayOfWeek(d) # weekday THEN
        T.Failed("DayOfWeek", n, C.DayOfWeek(d), weekday);  INC(failures)
      END;
      INC(expected.day);
      IF expected.day > C.DaysInMonth(expected.year, expected.month) THEN
        expected.day := 1;  INC(expected.month);
        IF expected.month > C.December THEN expected.month := C.January;  INC(expected.year) END
      END;
      weekday := weekday MOD 7 + 1;
      INC(n)
    END;
    T.Count(1);
    T.Int("EveryDay end", expected.year, C.maxYear + 1);
    T.True("FromDayNumber before", ~C.FromDayNumber(d, -4371588));
    T.True("FromDayNumber after", ~C.FromDayNumber(d, 2932897))
  END EveryDay;

  PROCEDURE Row(year, month, day, weekday, dayOfYear, weekYear, week: LONGINT;
                dayNumber: HUGEINT);
    VAR d: C.Date; y, w: LONGINT;
  BEGIN
    IF ~C.SetDate(d, year, month, day) THEN
      T.Failed("table SetDate", year, month, day);  INC(tableFailures)
    ELSE
      C.IsoWeek(d, y, w);
      IF (C.DayNumber(d) # dayNumber) OR (C.DayOfWeek(d) # weekday)
        OR (C.DayOfYear(d) # dayOfYear) OR (y # weekYear) OR (w # week) THEN
        T.Failed("table", year, month, day);  INC(tableFailures)
      END
    END
  END Row;

  PROCEDURE Table;
  BEGIN
    tableFailures := 0;
    CalendarData.Each(Row);
    T.Count(1);
    T.Int("table failures", tableFailures, 0);
    T.True("table size", CalendarData.Count() > 3000)
  END Table;

  PROCEDURE Rules;
    VAR d: C.Date; t: C.TimeOfDay; dt: C.DateTime; odt: C.OffsetDateTime;
  BEGIN
    T.True("IsLeapYear", C.IsLeapYear(2000) & C.IsLeapYear(2024) & ~C.IsLeapYear(1900)
      & ~C.IsLeapYear(2023) & C.IsLeapYear(0) & C.IsLeapYear(-4) & ~C.IsLeapYear(-100)
      & C.IsLeapYear(-400) & ~C.IsLeapYear(-1));
    T.Int("DaysInMonth Feb", C.DaysInMonth(2024, C.February), 29);
    T.Int("DaysInMonth Feb 1900", C.DaysInMonth(1900, C.February), 28);
    T.Int("DaysInMonth Apr", C.DaysInMonth(2023, C.April), 30);
    T.Int("DaysInMonth Dec", C.DaysInMonth(2023, C.December), 31);
    T.Int("DaysInYear", C.DaysInYear(2000) + C.DaysInYear(2100), 731);

    T.True("ValidDate zero", ~C.ValidDate(d));
    T.True("SetDate", C.SetDate(d, 2024, C.February, 29));
    IsDate("SetDate", d, 2024, 2, 29);
    T.True("SetDate Feb 30", ~C.SetDate(d, 2024, C.February, 30));
    IsDate("SetDate unchanged", d, 2024, 2, 29);
    T.True("SetDate Feb 29 2023", ~C.SetDate(d, 2023, C.February, 29));
    T.True("SetDate month 13", ~C.SetDate(d, 2023, 13, 1));
    T.True("SetDate year", ~C.SetDate(d, 10000, 1, 1) & ~C.SetDate(d, -10000, 12, 31));
    T.True("SetDate ends", C.SetDate(d, -9999, 1, 1) & C.SetDate(d, 9999, 12, 31));
    T.True("SetTimeOfDay", C.SetTimeOfDay(t, 23, 59, 59, 999999999));
    T.True("SetTimeOfDay 24", ~C.SetTimeOfDay(t, 24, 0, 0, 0));
    T.True("SetTimeOfDay 60", ~C.SetTimeOfDay(t, 0, 0, 60, 0) & ~C.SetTimeOfDay(t, 0, 60, 0, 0));
    T.True("SetTimeOfDay ns", ~C.SetTimeOfDay(t, 0, 0, 0, 1000000000) & ~C.SetTimeOfDay(t, 0, 0, 0, -1));
    T.True("ValidTimeOfDay", C.ValidTimeOfDay(t) & (t.nanosecond = 999999999));
    T.True("SetDateTime", C.SetDateTime(dt, 2026, 10, 28, 12, 30, 15, 5));
    T.True("ValidDateTime", C.ValidDateTime(dt));
    T.True("SetDateTime bad", ~C.SetDateTime(dt, 2026, 10, 32, 12, 30, 15, 5) & (dt.day = 28));
    C.GetTimeOfDay(dt, t);
    T.True("GetTimeOfDay", (t.hour = 12) & (t.minute = 30) & (t.second = 15) & (t.nanosecond = 5));
    T.True("Combine", C.SetDate(d, 1999, 12, 31));
    C.Combine(dt, d, t);
    IsDate("Combine date", dt, 1999, 12, 31);
    IsTime("Combine time", dt, 12, 30, 15, 5);
    C.Combine(odt, d, t);  odt.offset := 93599;
    T.True("ValidOffsetDateTime", C.ValidOffsetDateTime(odt));
    odt.offset := -93600;
    T.True("ValidOffsetDateTime offset", ~C.ValidOffsetDateTime(odt))
  END Rules;

  PROCEDURE Questions;
    VAR d: C.Date; y, w: LONGINT;
  BEGIN
    T.True("NthWeekday", C.NthWeekday(d, 2026, C.March, C.Sunday, 2));
    IsDate("NthWeekday 2nd Sunday", d, 2026, 3, 8);
    T.True("NthWeekday last", C.NthWeekday(d, 2026, C.October, C.Sunday, -1));
    IsDate("NthWeekday last Sunday", d, 2026, 10, 25);
    T.True("NthWeekday first", C.NthWeekday(d, 2026, C.October, C.Thursday, 1));
    IsDate("NthWeekday 1st Thursday", d, 2026, 10, 1);
    T.True("NthWeekday 5th", C.NthWeekday(d, 2026, C.October, C.Saturday, 5));
    IsDate("NthWeekday 5th Saturday", d, 2026, 10, 31);
    T.True("NthWeekday 5th last", C.NthWeekday(d, 2026, C.October, C.Thursday, -5));
    IsDate("NthWeekday 5th last Thursday", d, 2026, 10, 1);
    T.True("NthWeekday none", ~C.NthWeekday(d, 2021, C.February, C.Monday, 5) & (d.day = 1));
    T.True("NthWeekday none last", ~C.NthWeekday(d, 2021, C.February, C.Monday, -5));
    T.True("NthWeekday 0", ~C.NthWeekday(d, 2026, C.March, C.Sunday, 0));
    T.True("NthWeekday weekday", ~C.NthWeekday(d, 2026, C.March, 8, 1));
    T.True("NthWeekday month", ~C.NthWeekday(d, 2026, 0, C.Sunday, 1));
    T.True("NthWeekday year", ~C.NthWeekday(d, 10000, 1, C.Sunday, 1));
    T.True("NthWeekday huge", ~C.NthWeekday(d, 2026, 1, C.Sunday, MAX(LONGINT)));
    T.True("NthWeekday -huge", ~C.NthWeekday(d, 2026, 1, C.Sunday, MIN(LONGINT)));

    T.True("IsoWeek", C.SetDate(d, 2026, 10, 28));
    C.IsoWeek(d, y, w);
    T.True("IsoWeek 2026-10-28", (y = 2026) & (w = 44));
    T.True("IsoWeek end", C.SetDate(d, 9999, 12, 31));
    C.IsoWeek(d, y, w);
    T.True("IsoWeek 9999-12-31", (y = 9999) & (w = 52));
    T.True("IsoWeek start", C.SetDate(d, -9999, 1, 1));
    C.IsoWeek(d, y, w);
    T.True("IsoWeek -9999-01-01", (y = -9999) & (w = 1));
    T.True("DayOfYear", C.SetDate(d, 2024, 12, 31) & (C.DayOfYear(d) = 366));
    T.True("DaysBetween", C.SetDate(d, 2024, 3, 1));
    T.Int("DaysBetween value", C.DaysBetween(d, d), 0)
  END Questions;

  PROCEDURE Arithmetic;
    VAR d, e: C.Date; dt: C.DateTime; ok: BOOLEAN;
  BEGIN
    ok := C.SetDate(d, 2020, C.January, 31);
    T.True("AddMonths", C.AddMonths(d, 1));  IsDate("AddMonths clamp", d, 2020, 2, 29);
    ok := C.SetDate(d, 2021, C.January, 31);
    T.True("AddMonths 2021", C.AddMonths(d, 1));  IsDate("AddMonths clamp 2021", d, 2021, 2, 28);
    ok := C.SetDate(d, 2021, C.March, 31);
    T.True("AddMonths -", C.AddMonths(d, -13));  IsDate("AddMonths -13", d, 2020, 2, 29);
    ok := C.SetDate(d, 2020, C.February, 29);
    T.True("AddYears", C.AddYears(d, 1));  IsDate("AddYears clamp", d, 2021, 2, 28);
    ok := C.SetDate(d, 2020, C.February, 29);
    T.True("AddYears 4", C.AddYears(d, 4));  IsDate("AddYears 4", d, 2024, 2, 29);
    ok := C.SetDate(d, -9999, C.January, 1);
    T.True("AddMonths before", ~C.AddMonths(d, -1));  IsDate("AddMonths unchanged", d, -9999, 1, 1);
    T.True("AddDays before", ~C.AddDays(d, -1));
    T.True("AddYears before", ~C.AddYears(d, -1));
    T.True("AddMonths huge", ~C.AddMonths(d, D.min) & ~C.AddMonths(d, D.max));
    T.True("AddDays huge", ~C.AddDays(d, D.min) & ~C.AddDays(d, D.max));
    T.True("AddYears huge", ~C.AddYears(d, D.min) & ~C.AddYears(d, D.max));
    T.True("AddDays across", C.AddDays(d, 2932896 + 4371587));
    IsDate("AddDays to the end", d, 9999, 12, 31);
    T.True("AddDays after", ~C.AddDays(d, 1) & ~C.AddMonths(d, 1) & ~C.AddYears(d, 1));
    T.True("AddYears across", C.AddYears(d, -19998));  IsDate("AddYears to the start", d, -9999, 12, 31);
    ok := C.SetDate(d, 2024, C.March, 1);
    T.True("AddDays -1", C.AddDays(d, -1));  IsDate("AddDays leap", d, 2024, 2, 29);

    (* a DateTime through VAR Date keeps its time *)
    ok := C.SetDateTime(dt, 2024, 1, 31, 13, 14, 15, 16);
    T.True("AddMonths DateTime", C.AddMonths(dt, 1));
    IsDate("AddMonths DateTime date", dt, 2024, 2, 29);
    IsTime("AddMonths DateTime time", dt, 13, 14, 15, 16);
    T.True("AddDays DateTime", C.AddDays(dt, 1));
    IsDate("AddDays DateTime date", dt, 2024, 3, 1);
    IsTime("AddDays DateTime time", dt, 13, 14, 15, 16);
    T.True("SetDate DateTime", C.SetDate(dt, 2000, 1, 1));
    IsTime("SetDate DateTime time", dt, 13, 14, 15, 16);

    ok := C.SetDate(d, 2024, 1, 1);  ok := C.SetDate(e, 2023, 12, 31);
    T.Int("DaysBetween", C.DaysBetween(d, e), 1);
    T.Int("DaysBetween -", C.DaysBetween(e, d), -1);
    T.Int("CompareDates", C.CompareDates(d, e), 1);
    T.Int("CompareDates -", C.CompareDates(e, d), -1);
    T.Int("CompareDates =", C.CompareDates(d, d), 0)
  END Arithmetic;

  PROCEDURE Periods;
    VAR from, to, d: C.Date; p: C.Period; ok: BOOLEAN; i, failures: LONGINT;
      sign: LONGINT;
  BEGIN
    ok := C.SetDate(d, 2020, C.February, 29);
    p.years := 1;  p.months := 1;  p.days := 0;
    T.True("AddPeriod", C.AddPeriod(d, p));
    IsDate("AddPeriod months at once", d, 2021, 3, 29);
    p.years := 0;  p.months := 1;  p.days := 1;
    ok := C.SetDate(d, 2021, 1, 31);
    T.True("AddPeriod days after months", C.AddPeriod(d, p));
    IsDate("AddPeriod 1 month 1 day", d, 2021, 3, 1);
    T.True("SubtractPeriod", C.SubtractPeriod(d, p));
    IsDate("SubtractPeriod 1 month 1 day", d, 2021, 1, 31);
    p.years := MIN(LONGINT);  p.months := MIN(LONGINT);  p.days := MIN(LONGINT);
    T.True("SubtractPeriod huge", ~C.SubtractPeriod(d, p) & ~C.AddPeriod(d, p));
    IsDate("AddPeriod unchanged", d, 2021, 1, 31);
    p.years := 0;  p.months := 0;  p.days := 1;
    ok := C.SetDate(d, 9999, 12, 31);
    T.True("AddPeriod after", ~C.AddPeriod(d, p));

    ok := C.SetDate(from, 2020, 1, 15);  ok := C.SetDate(to, 2021, 3, 10);
    C.PeriodBetween(p, from, to);
    T.True("PeriodBetween", (p.years = 1) & (p.months = 1) & (p.days = 23));
    C.PeriodBetween(p, to, from);
    T.True("PeriodBetween -", (p.years = -1) & (p.months = -1) & (p.days = -26));
    ok := C.SetDate(from, 2023, 3, 31);  ok := C.SetDate(to, 2023, 2, 28);
    C.PeriodBetween(p, from, to);
    T.True("PeriodBetween month end -", (p.years = 0) & (p.months = -1) & (p.days = 0));
    ok := C.SetDate(from, 2020, 2, 29);  ok := C.SetDate(to, 2021, 2, 28);
    C.PeriodBetween(p, from, to);
    T.True("PeriodBetween leap day", (p.years = 0) & (p.months = 11) & (p.days = 30));
    C.PeriodBetween(p, from, from);
    T.True("PeriodBetween 0", (p.years = 0) & (p.months = 0) & (p.days = 0));

    (* AddPeriod(from, PeriodBetween(from, to)) = to, with one sign, for
       dates near each other, where month ends matter, and far apart *)
    failures := 0;
    i := 0;
    WHILE (i < 200000) & (failures < 10) DO
      IF i MOD 2 = 0 THEN
        RandomDate(from, -4371587, 2932896);  RandomDate(to, -4371587, 2932896)
      ELSE
        RandomDate(from, -1000, 1000);  RandomDate(to, -1000, 1000)
      END;
      C.PeriodBetween(p, from, to);
      d := from;
      IF C.DaysBetween(to, from) > 0 THEN sign := 1 ELSE sign := -1 END;
      IF ~C.AddPeriod(d, p) OR (C.CompareDates(d, to) # 0)
        OR (p.years * sign < 0) OR (p.months * sign < 0) OR (p.days * sign < 0)
        OR (ABS(p.months) > 11) THEN
        T.Failed("PeriodBetween", C.DayNumber(from), C.DayNumber(to), p.days);
        INC(failures)
      END;
      INC(i)
    END;
    T.Count(1)
  END Periods;

  PROCEDURE Times;
    VAR dt, e: C.DateTime; odt: C.OffsetDateTime; t, u: I.Instant; d: D.Duration;
      ok: BOOLEAN; time, date: LONGINT;
  BEGIN
    ok := C.SetDateTime(dt, 1970, 1, 1, 0, 0, 0, 0);
    C.ToUTCInstant(dt, t);
    T.True("ToUTCInstant epoch", (t.seconds = 0) & (t.nanosecond = 0));
    ok := C.SetDateTime(dt, 2026, 10, 28, 14, 5, 6, 7);
    C.ToUTCInstant(dt, t);
    T.True("ToUTCInstant", (t.seconds = 1793196306) & (t.nanosecond = 7));
    C.FromUTCInstant(e, t);
    T.Int("FromUTCInstant", C.CompareDateTimes(e, dt), 0);
    C.FromUTCInstant(e, I.earliest);
    IsDate("FromUTCInstant earliest", e, -9999, 1, 1);  IsTime("earliest time", e, 0, 0, 0, 0);
    C.FromUTCInstant(e, I.latest);
    IsDate("FromUTCInstant latest", e, 9999, 12, 31);
    IsTime("latest time", e, 23, 59, 59, 999999999);

    (* 2026-10-28T10:05:06-04:00 is 14:05:06Z *)
    ok := C.SetDateTime(odt, 2026, 10, 28, 10, 5, 6, 7);  odt.offset := -4 * 3600;
    C.ToInstant(odt, u);
    T.True("ToInstant", I.Equal(t, u));
    C.FromInstant(odt, t, 5 * 3600 + 30 * 60);
    IsDate("FromInstant date", odt, 2026, 10, 28);
    IsTime("FromInstant time", odt, 19, 35, 6, 7);
    T.Int("FromInstant offset", odt.offset, 19800);
    C.FromInstant(odt, t, -14 * 3600);
    IsTime("FromInstant -14", odt, 0, 5, 6, 7);
    (* beyond the years: FromInstant saturates, CheckedFromInstant refuses
       (doc/instant-offsets.md) *)
    T.True("CheckedFromInstant", C.CheckedFromInstant(odt, t, 3600));
    IsTime("CheckedFromInstant time", odt, 15, 5, 6, 7);
    T.Int("CheckedFromInstant offset", odt.offset, 3600);
    T.True("CheckedFromInstant latest UTC", C.CheckedFromInstant(odt, I.latest, 0));
    T.True("CheckedFromInstant latest -", C.CheckedFromInstant(odt, I.latest, -3600));
    IsTime("CheckedFromInstant latest - time", odt, 22, 59, 59, 999999999);
    T.True("CheckedFromInstant earliest +", C.CheckedFromInstant(odt, I.earliest, 3600));
    IsTime("CheckedFromInstant earliest + time", odt, 1, 0, 0, 0);
    T.True("CheckedFromInstant past 9999",
      ~C.CheckedFromInstant(odt, I.latest, 1) & (odt.hour = 1) & (odt.offset = 3600));
    T.True("CheckedFromInstant before -9999", ~C.CheckedFromInstant(odt, I.earliest, -1));
    (* 93599 s is the largest offset, 25:59:59 *)
    I.Subtract(u, I.latest, 93598 * D.second);
    T.True("CheckedFromInstant max offset", C.CheckedFromInstant(odt, u, 93598));
    IsTime("CheckedFromInstant max offset time", odt, 23, 59, 59, 999999999);
    T.True("CheckedFromInstant max offset past", ~C.CheckedFromInstant(odt, u, 93599));
    C.FromInstant(odt, I.latest, 14 * 3600);
    IsDate("FromInstant past 9999", odt, 9999, 12, 31);
    IsTime("FromInstant past 9999 time", odt, 23, 59, 59, 999999999);
    T.Int("FromInstant past 9999 offset", odt.offset, 14 * 3600);
    C.FromInstant(odt, I.earliest, -3600);
    IsDate("FromInstant before -9999", odt, -9999, 1, 1);
    IsTime("FromInstant before -9999 time", odt, 0, 0, 0, 0);
    T.Int("FromInstant before -9999 offset", odt.offset, -3600);
    (* beyond the instants: ToInstant saturates, CheckedToInstant refuses
       (doc/offset-to-instant.md) *)
    ok := C.SetDateTime(odt, 2026, 10, 28, 10, 5, 6, 7);  odt.offset := -4 * 3600;
    T.True("CheckedToInstant", C.CheckedToInstant(u, odt) & I.Equal(t, u));
    ok := C.SetDateTime(odt, -9999, 1, 1, 0, 0, 0, 0);  odt.offset := 3600;
    C.ToInstant(odt, u);
    T.True("ToInstant before earliest", I.Equal(u, I.earliest));
    T.True("CheckedToInstant before earliest",
      ~C.CheckedToInstant(u, odt) & I.Equal(u, I.earliest));
    u := t;
    T.True("CheckedToInstant refused leaves t", ~C.CheckedToInstant(u, odt) & I.Equal(u, t));
    odt.hour := 1;
    T.True("CheckedToInstant earliest", C.CheckedToInstant(u, odt) & I.Equal(u, I.earliest));
    odt.offset := -93599;  odt.hour := 0;
    T.True("CheckedToInstant earliest -", C.CheckedToInstant(u, odt));
    T.True("CheckedToInstant earliest - value",
      (u.seconds = I.earliest.seconds + 93599) & (u.nanosecond = 0));
    ok := C.SetDateTime(odt, 9999, 12, 31, 23, 59, 59, 999999999);  odt.offset := -1;
    C.ToInstant(odt, u);
    T.True("ToInstant after latest", I.Equal(u, I.latest));
    T.True("CheckedToInstant after latest", ~C.CheckedToInstant(u, odt));
    odt.offset := 0;
    T.True("CheckedToInstant latest", C.CheckedToInstant(u, odt) & I.Equal(u, I.latest));
    ok := C.SetDateTime(odt, 9999, 12, 31, 23, 59, 59, 999999999);  odt.offset := 93599;
    T.True("CheckedToInstant latest +", C.CheckedToInstant(u, odt));
    T.True("CheckedToInstant latest + value",
      (u.seconds = I.latest.seconds - 93599) & (u.nanosecond = 999999999));

    ok := C.SetDateTime(dt, 2024, 2, 28, 23, 0, 0, 999999999);
    T.True("AddDuration", C.AddDuration(dt, 3600 * D.second + 1));
    IsDate("AddDuration date", dt, 2024, 2, 29);  IsTime("AddDuration time", dt, 0, 0, 1, 0);
    T.True("AddDuration -", C.AddDuration(dt, -D.day));
    IsDate("AddDuration - date", dt, 2024, 2, 28);
    T.True("AddDuration max", C.AddDuration(dt, D.max) & (dt.year = 2316));
    ok := C.SetDateTime(dt, 9999, 12, 31, 23, 59, 59, 999999999);
    T.True("AddDuration past", ~C.AddDuration(dt, 1) & (dt.nanosecond = 999999999));
    ok := C.SetDateTime(dt, 2024, 1, 1, 0, 0, 0, 0);
    ok := C.SetDateTime(e, 2023, 12, 31, 23, 59, 59, 500000000);
    T.Int("Difference", C.Difference(dt, e), 500 * D.millisecond);
    T.Int("Difference -", C.Difference(e, dt), -500 * D.millisecond);
    T.True("CheckedDifference", C.CheckedDifference(d, dt, e) & (d = 500 * D.millisecond));
    ok := C.SetDateTime(e, 1000, 1, 1, 0, 0, 0, 0);
    T.True("CheckedDifference far", ~C.CheckedDifference(d, dt, e));
    T.Int("Difference far", C.Difference(dt, e), D.max);
    T.Int("CompareDateTimes", C.CompareDateTimes(dt, e), 1);
    ok := C.SetDateTime(e, 2024, 1, 1, 0, 0, 0, 1);
    T.Int("CompareDateTimes ns", C.CompareDateTimes(dt, e), -1);

    ok := C.SetDateTime(dt, 2026, 10, 28, 14, 5, 6, 7);
    C.ToOberonClock(dt, time, date);
    T.Int("ToOberonClock d", date, 26 * 512 + 10 * 32 + 28);
    T.Int("ToOberonClock t", time, 14 * 4096 + 5 * 64 + 6);
    T.True("FromOberonClock", C.FromOberonClock(e, time, date));
    IsDate("FromOberonClock date", e, 2026, 10, 28);  IsTime("FromOberonClock time", e, 14, 5, 6, 0);
    T.True("FromOberonClock 1999", C.FromOberonClock(e, 0, 99 * 512 + 12 * 32 + 31) & (e.year = 1999));
    T.True("FromOberonClock 1970", C.FromOberonClock(e, 0, 70 * 512 + 1 * 32 + 1) & (e.year = 1970));
    T.True("FromOberonClock 2069", C.FromOberonClock(e, 0, 69 * 512 + 1 * 32 + 1) & (e.year = 2069));
    T.True("FromOberonClock bad", ~C.FromOberonClock(e, 0, 26 * 512 + 2 * 32 + 30)
      & ~C.FromOberonClock(e, 24 * 4096, 26 * 512 + 32 + 1)
      & ~C.FromOberonClock(e, 0, 100 * 512 + 32 + 1) & ~C.FromOberonClock(e, -1, 26 * 512 + 32 + 1)
      & ~C.FromOberonClock(e, 0, -1) & (e.year = 2069))
  END Times;

BEGIN
  T.Start("Calendar");
  seed := 19700101;
  EveryDay;  Table;  Rules;  Questions;  Arithmetic;  Periods;  Times;
  T.Finish
END CalendarTest.
