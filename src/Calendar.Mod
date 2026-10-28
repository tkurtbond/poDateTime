MODULE Calendar;

  (* Civil dates and times in the proleptic Gregorian calendar, years
     -9999..9999 in astronomical numbering (design section 7). Day numbers
     count days since 1970-01-01, as C++'s sys_days; DayNumber and
     FromDayNumber are Howard Hinnant's days_from_civil and
     civil_from_days.

     A DateTime is a Date by extension, so it may be passed to a VAR Date
     parameter. Such procedures therefore write the fields one by one:
     assigning a whole Date to a VAR Date that holds a DateTime traps.

     ASSERT numbers:
       20  an invalid Date
       21  an invalid TimeOfDay
       22  an invalid DateTime
       23  an invalid OffsetDateTime, or an offset beyond +-25:59:59
       24  DaysInMonth with a month outside 1..12 *)

  IMPORT Durations, Instants;

  CONST
    January* = 1;  February* = 2;  March* = 3;  April* = 4;  May* = 5;  June* = 6;
    July* = 7;  August* = 8;  September* = 9;  October* = 10;  November* = 11;
    December* = 12;
    Monday* = 1;  Tuesday* = 2;  Wednesday* = 3;  Thursday* = 4;  Friday* = 5;
    Saturday* = 6;  Sunday* = 7;
    minYear* = -9999;  maxYear* = 9999;

    (* the day numbers of -9999-01-01 and 9999-12-31 *)
    minDay = -4371587;  maxDay = 2932896;
    (* months as year * 12 + month - 1 *)
    minMonth = minYear * 12;  maxMonth = maxYear * 12 + 11;
    maxOffset = 25 * 3600 + 59 * 60 + 59;
    secondsPerDay = 86400;
    second = Durations.second;

  TYPE
    Date* = RECORD year*, month*, day*: LONGINT END;
    TimeOfDay* = RECORD hour*, minute*, second*, nanosecond*: LONGINT END;
    DateTime* = RECORD (Date) hour*, minute*, second*, nanosecond*: LONGINT END;
    OffsetDateTime* = RECORD (DateTime) offset*: LONGINT END;
    Period* = RECORD years*, months*, days*: LONGINT END;

  PROCEDURE IsLeapYear*(year: LONGINT): BOOLEAN;
  BEGIN
    RETURN (year MOD 4 = 0) & ((year MOD 100 # 0) OR (year MOD 400 = 0))
  END IsLeapYear;

  PROCEDURE DaysInMonth*(year, month: LONGINT): LONGINT;
    VAR days: LONGINT;
  BEGIN
    ASSERT((month >= January) & (month <= December), 24);
    IF month = February THEN
      IF IsLeapYear(year) THEN days := 29 ELSE days := 28 END
    ELSIF (month = April) OR (month = June) OR (month = September) OR (month = November) THEN
      days := 30
    ELSE days := 31
    END;
    RETURN days
  END DaysInMonth;

  PROCEDURE DaysInYear*(year: LONGINT): LONGINT;
    VAR days: LONGINT;
  BEGIN
    IF IsLeapYear(year) THEN days := 366 ELSE days := 365 END;
    RETURN days
  END DaysInYear;

  PROCEDURE ValidFields(year, month, day: LONGINT): BOOLEAN;
  BEGIN
    RETURN (year >= minYear) & (year <= maxYear) & (month >= January) & (month <= December)
      & (day >= 1) & (day <= DaysInMonth(year, month))
  END ValidFields;

  PROCEDURE ValidTimeFields(hour, minute, second, nanosecond: LONGINT): BOOLEAN;
  BEGIN
    RETURN (hour >= 0) & (hour <= 23) & (minute >= 0) & (minute <= 59)
      & (second >= 0) & (second <= 59) & (nanosecond >= 0) & (nanosecond <= 999999999)
  END ValidTimeFields;

  PROCEDURE ValidDate*(d: Date): BOOLEAN;
  BEGIN
    RETURN ValidFields(d.year, d.month, d.day)
  END ValidDate;

  PROCEDURE ValidTimeOfDay*(t: TimeOfDay): BOOLEAN;
  BEGIN
    RETURN ValidTimeFields(t.hour, t.minute, t.second, t.nanosecond)
  END ValidTimeOfDay;

  PROCEDURE ValidDateTime*(dt: DateTime): BOOLEAN;
  BEGIN
    RETURN ValidFields(dt.year, dt.month, dt.day)
      & ValidTimeFields(dt.hour, dt.minute, dt.second, dt.nanosecond)
  END ValidDateTime;

  PROCEDURE ValidOffsetDateTime*(odt: OffsetDateTime): BOOLEAN;
  BEGIN
    RETURN ValidDateTime(odt) & (odt.offset >= -maxOffset) & (odt.offset <= maxOffset)
  END ValidOffsetDateTime;

  PROCEDURE SetDate*(VAR d: Date; year, month, day: LONGINT): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN
    ok := ValidFields(year, month, day);
    IF ok THEN d.year := year;  d.month := month;  d.day := day END;
    RETURN ok
  END SetDate;

  PROCEDURE SetTimeOfDay*(VAR t: TimeOfDay; hour, minute, second, nanosecond: LONGINT): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN
    ok := ValidTimeFields(hour, minute, second, nanosecond);
    IF ok THEN
      t.hour := hour;  t.minute := minute;  t.second := second;  t.nanosecond := nanosecond
    END;
    RETURN ok
  END SetTimeOfDay;

  PROCEDURE SetDateTime*(VAR dt: DateTime;
                         year, month, day, hour, minute, second, nanosecond: LONGINT): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN
    ok := ValidFields(year, month, day) & ValidTimeFields(hour, minute, second, nanosecond);
    IF ok THEN
      dt.year := year;  dt.month := month;  dt.day := day;
      dt.hour := hour;  dt.minute := minute;  dt.second := second;  dt.nanosecond := nanosecond
    END;
    RETURN ok
  END SetDateTime;

  PROCEDURE Combine*(VAR dt: DateTime; d: Date; t: TimeOfDay);
  BEGIN
    ASSERT(ValidDate(d), 20);
    ASSERT(ValidTimeOfDay(t), 21);
    dt.year := d.year;  dt.month := d.month;  dt.day := d.day;
    dt.hour := t.hour;  dt.minute := t.minute;  dt.second := t.second;
    dt.nanosecond := t.nanosecond
  END Combine;

  PROCEDURE GetTimeOfDay*(dt: DateTime; VAR t: TimeOfDay);
  BEGIN
    ASSERT(ValidDateTime(dt), 22);
    t.hour := dt.hour;  t.minute := dt.minute;  t.second := dt.second;
    t.nanosecond := dt.nanosecond
  END GetTimeOfDay;

  (* Hinnant's days_from_civil, for any year. The year is counted from
     March, so that the leap day falls at its end. *)
  PROCEDURE DaysFromCivil(year, month, day: HUGEINT): HUGEINT;
    VAR era, yearOfEra, dayOfYear, dayOfEra: HUGEINT;
  BEGIN
    IF month <= February THEN DEC(year); INC(month, 9) ELSE DEC(month, 3) END;
    era := year DIV 400;
    yearOfEra := year - era * 400;
    dayOfYear := (153 * month + 2) DIV 5 + day - 1;
    dayOfEra := yearOfEra * 365 + yearOfEra DIV 4 - yearOfEra DIV 100 + dayOfYear;
    RETURN era * 146097 + dayOfEra - 719468
  END DaysFromCivil;

  (* Hinnant's civil_from_days, for any day number whose year fits a
     LONGINT; IsoWeek uses it a few days beyond the years *)
  PROCEDURE CivilFromDays(n: HUGEINT; VAR year, month, day: LONGINT);
    VAR era, dayOfEra, yearOfEra, dayOfYear, m, y: HUGEINT;
  BEGIN
    INC(n, 719468);
    era := n DIV 146097;
    dayOfEra := n - era * 146097;
    yearOfEra := (dayOfEra - dayOfEra DIV 1460 + dayOfEra DIV 36524 - dayOfEra DIV 146096) DIV 365;
    y := yearOfEra + era * 400;
    dayOfYear := dayOfEra - (365 * yearOfEra + yearOfEra DIV 4 - yearOfEra DIV 100);
    m := (5 * dayOfYear + 2) DIV 153;
    day := SHORT(dayOfYear - (153 * m + 2) DIV 5 + 1);
    IF m < 10 THEN INC(m, 3) ELSE DEC(m, 9) END;
    IF m <= February THEN INC(y) END;
    year := SHORT(y);  month := SHORT(m)
  END CivilFromDays;

  PROCEDURE DayNumber*(d: Date): HUGEINT;
  BEGIN
    ASSERT(ValidDate(d), 20);
    RETURN DaysFromCivil(d.year, d.month, d.day)
  END DayNumber;

  PROCEDURE FromDayNumber*(VAR d: Date; n: HUGEINT): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN
    ok := (n >= minDay) & (n <= maxDay);
    IF ok THEN CivilFromDays(n, d.year, d.month, d.day) END;
    RETURN ok
  END FromDayNumber;

  PROCEDURE WeekdayOf(n: HUGEINT): LONGINT;
  BEGIN
    (* 1970-01-01 was a Thursday *)
    RETURN SHORT((n + 3) MOD 7 + 1)
  END WeekdayOf;

  PROCEDURE DayOfWeek*(d: Date): LONGINT;
  BEGIN
    RETURN WeekdayOf(DayNumber(d))
  END DayOfWeek;

  PROCEDURE DayOfYear*(d: Date): LONGINT;
  BEGIN
    RETURN SHORT(DayNumber(d) - DaysFromCivil(d.year, January, 1) + 1)
  END DayOfYear;

  (* A week belongs to the year that holds its Thursday, so weekYear can
     be one beyond the years at either end. *)
  PROCEDURE IsoWeek*(d: Date; VAR weekYear, week: LONGINT);
    VAR n, thursday: HUGEINT; month, day: LONGINT;
  BEGIN
    n := DayNumber(d);
    thursday := n - WeekdayOf(n) + Thursday;
    CivilFromDays(thursday, weekYear, month, day);
    week := SHORT((thursday - DaysFromCivil(weekYear, January, 1)) DIV 7 + 1)
  END IsoWeek;

  (* The nth weekday of the month, or for n < 0 the -nth from its end:
     NthWeekday(d, 2026, March, Sunday, 2) is the second Sunday of March
     2026. *)
  PROCEDURE NthWeekday*(VAR d: Date; year, month, weekday, n: LONGINT): BOOLEAN;
    VAR day, last: LONGINT; ok: BOOLEAN;
  BEGIN
    ok := (year >= minYear) & (year <= maxYear) & (month >= January) & (month <= December)
      & (weekday >= Monday) & (weekday <= Sunday) & (n # 0) & (n >= -5) & (n <= 5);
    IF ok THEN
      last := DaysInMonth(year, month);
      IF n > 0 THEN
        day := 1 + (weekday - WeekdayOf(DaysFromCivil(year, month, 1))) MOD 7 + (n - 1) * 7
      ELSE
        day := last - (WeekdayOf(DaysFromCivil(year, month, last)) - weekday) MOD 7 + (n + 1) * 7
      END;
      ok := (day >= 1) & (day <= last);
      IF ok THEN d.year := year;  d.month := month;  d.day := day END
    END;
    RETURN ok
  END NthWeekday;

  (* d moved by months, its day clamped to the month's length; the result
     is known to be within the years *)
  PROCEDURE MoveMonths(VAR year, month, day: LONGINT; months: HUGEINT);
    VAR m: HUGEINT;
  BEGIN
    m := year * 12 + month - 1 + months;
    year := SHORT(m DIV 12);  month := SHORT(m MOD 12 + 1);
    IF day > DaysInMonth(year, month) THEN day := DaysInMonth(year, month) END
  END MoveMonths;

  PROCEDURE AddDays*(VAR d: Date; n: HUGEINT): BOOLEAN;
    VAR x: HUGEINT; ok: BOOLEAN;
  BEGIN
    x := DayNumber(d);
    (* compared before adding, so that no n can overflow *)
    ok := (n <= maxDay - x) & (n >= minDay - x);
    IF ok THEN ok := FromDayNumber(d, x + n) END;
    RETURN ok
  END AddDays;

  PROCEDURE AddMonths*(VAR d: Date; n: HUGEINT): BOOLEAN;
    VAR m: HUGEINT; ok: BOOLEAN;
  BEGIN
    ASSERT(ValidDate(d), 20);
    m := d.year * 12 + d.month - 1;
    ok := (n <= maxMonth - m) & (n >= minMonth - m);
    IF ok THEN MoveMonths(d.year, d.month, d.day, n) END;
    RETURN ok
  END AddMonths;

  PROCEDURE AddYears*(VAR d: Date; n: HUGEINT): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN
    ASSERT(ValidDate(d), 20);
    ok := (n <= maxYear - d.year) & (n >= minYear - d.year);
    IF ok THEN MoveMonths(d.year, d.month, d.day, n * 12) END;
    RETURN ok
  END AddYears;

  (* d moved by months, then by days. The months go in one step, as
     Java's Period.addTo does, so that 2020-02-29 + 1 year 1 month is
     2021-03-29, and PeriodBetween can be undone. *)
  PROCEDURE Shift(VAR d: Date; months, days: HUGEINT): BOOLEAN;
    VAR year, month, day: LONGINT; m, n: HUGEINT; ok: BOOLEAN;
  BEGIN
    ASSERT(ValidDate(d), 20);
    m := d.year * 12 + d.month - 1;
    ok := (months <= maxMonth - m) & (months >= minMonth - m);
    IF ok THEN
      year := d.year;  month := d.month;  day := d.day;
      MoveMonths(year, month, day, months);
      n := DaysFromCivil(year, month, day);
      ok := (days <= maxDay - n) & (days >= minDay - n);
      IF ok THEN CivilFromDays(n + days, d.year, d.month, d.day) END
    END;
    RETURN ok
  END Shift;

  PROCEDURE AddPeriod*(VAR d: Date; p: Period): BOOLEAN;
  BEGIN
    RETURN Shift(d, p.years * 12 + p.months, p.days)
  END AddPeriod;

  (* negated as HUGEINTs, since -MIN(LONGINT) wraps *)
  PROCEDURE SubtractPeriod*(VAR d: Date; p: Period): BOOLEAN;
    VAR months, days: HUGEINT;
  BEGIN
    months := p.years * 12 + p.months;  days := p.days;
    RETURN Shift(d, -months, -days)
  END SubtractPeriod;

  PROCEDURE DaysBetween*(later, earlier: Date): HUGEINT;
  BEGIN
    RETURN DayNumber(later) - DayNumber(earlier)
  END DaysBetween;

  (* Years, months and days of one sign, with AddPeriod(from, p) = to. For
     a forward period this is Java's Period.between. Backward, Java
     subtracts the length of to's month, which can miss: from 03-31 to
     02-28 it gives -1 month -3 days, which leads from 03-31 to 02-25. So
     both directions take the days from the date the months reach, as
     dateutil's relativedelta does (doc/calendar-periods.md). *)
  PROCEDURE PeriodBetween*(VAR p: Period; from, to: Date);
    VAR months, years: HUGEINT; year, month, day: LONGINT;
  BEGIN
    ASSERT(ValidDate(from) & ValidDate(to), 20);
    months := (to.year * 12 + to.month) - (from.year * 12 + from.month);
    IF (months > 0) & (to.day < from.day) THEN DEC(months)
    ELSIF (months < 0) & (to.day > from.day) THEN INC(months)
    END;
    year := from.year;  month := from.month;  day := from.day;
    MoveMonths(year, month, day, months);
    p.days := SHORT(DaysFromCivil(to.year, to.month, to.day) - DaysFromCivil(year, month, day));
    (* toward zero, so that years and months share the sign *)
    years := months DIV 12;
    IF (years < 0) & (months MOD 12 # 0) THEN INC(years) END;
    p.years := SHORT(years);  p.months := SHORT(months - years * 12)
  END PeriodBetween;

  PROCEDURE CompareFields(a, b: LONGINT; VAR c: INTEGER);
  BEGIN
    IF c = 0 THEN
      IF a < b THEN c := -1 ELSIF a > b THEN c := 1 END
    END
  END CompareFields;

  PROCEDURE CompareDates*(a, b: Date): INTEGER;
    VAR c: INTEGER;
  BEGIN
    ASSERT(ValidDate(a) & ValidDate(b), 20);
    c := 0;
    CompareFields(a.year, b.year, c);  CompareFields(a.month, b.month, c);
    CompareFields(a.day, b.day, c);
    RETURN c
  END CompareDates;

  PROCEDURE CompareDateTimes*(a, b: DateTime): INTEGER;
    VAR c: INTEGER;
  BEGIN
    ASSERT(ValidDateTime(a) & ValidDateTime(b), 22);
    c := 0;
    CompareFields(a.year, b.year, c);  CompareFields(a.month, b.month, c);
    CompareFields(a.day, b.day, c);  CompareFields(a.hour, b.hour, c);
    CompareFields(a.minute, b.minute, c);  CompareFields(a.second, b.second, c);
    CompareFields(a.nanosecond, b.nanosecond, c);
    RETURN c
  END CompareDateTimes;

  (* dt read as UTC, in seconds since 1970 *)
  PROCEDURE Seconds(dt: DateTime): HUGEINT;
  BEGIN
    RETURN DaysFromCivil(dt.year, dt.month, dt.day) * secondsPerDay
      + dt.hour * 3600 + dt.minute * 60 + dt.second
  END Seconds;

  (* dt := seconds since 1970 and a nanosecond, for seconds within the
     years *)
  PROCEDURE SetSeconds(VAR dt: DateTime; seconds: HUGEINT; nanosecond: LONGINT);
    VAR time: LONGINT;
  BEGIN
    CivilFromDays(seconds DIV secondsPerDay, dt.year, dt.month, dt.day);
    time := SHORT(seconds MOD secondsPerDay);
    dt.hour := time DIV 3600;  dt.minute := time DIV 60 MOD 60;  dt.second := time MOD 60;
    dt.nanosecond := nanosecond
  END SetSeconds;

  (* Elapsed arithmetic on a civil date-time, as if it were UTC: every day
     has 86 400 seconds. Across a daylight-saving change in a real zone
     the answer is in wall-clock time, not elapsed time; for elapsed time
     go through Instants. *)
  PROCEDURE AddDuration*(VAR dt: DateTime; d: Durations.Duration): BOOLEAN;
    VAR seconds, nanosecond: HUGEINT; ok: BOOLEAN;
  BEGIN
    ASSERT(ValidDateTime(dt), 22);
    seconds := Seconds(dt) + d DIV second;
    nanosecond := dt.nanosecond + d MOD second;
    IF nanosecond >= second THEN DEC(nanosecond, second); INC(seconds) END;
    ok := (seconds >= Instants.earliest.seconds) & (seconds <= Instants.latest.seconds);
    IF ok THEN SetSeconds(dt, seconds, SHORT(nanosecond)) END;
    RETURN ok
  END AddDuration;

  PROCEDURE ToUTCInstant*(dt: DateTime; VAR t: Instants.Instant);
  BEGIN
    ASSERT(ValidDateTime(dt), 22);
    Instants.FromUnix(t, Seconds(dt), dt.nanosecond)
  END ToUTCInstant;

  (* later - earlier, both read as UTC; see AddDuration *)
  PROCEDURE CheckedDifference*(VAR d: Durations.Duration; later, earlier: DateTime): BOOLEAN;
    VAR a, b: Instants.Instant;
  BEGIN
    ToUTCInstant(later, a);  ToUTCInstant(earlier, b);
    RETURN Instants.CheckedBetween(d, a, b)
  END CheckedDifference;

  PROCEDURE Difference*(later, earlier: DateTime): Durations.Duration;
    VAR a, b: Instants.Instant;
  BEGIN
    ToUTCInstant(later, a);  ToUTCInstant(earlier, b);
    RETURN Instants.Between(a, b)
  END Difference;

  (* FALSE, leaving t unchanged, when the offset carries odt past the
     instants, as -9999-01-01T00:00+01:00 is an hour before
     Instants.earliest. Only the first and last 26 hours of the years can
     fail (doc/offset-to-instant.md). Readers of strings and of zone times
     use this form, so that they refuse such times rather than clamp them. *)
  PROCEDURE CheckedToInstant*(VAR t: Instants.Instant; odt: OffsetDateTime): BOOLEAN;
    VAR seconds: HUGEINT; ok: BOOLEAN;
  BEGIN
    ASSERT(ValidOffsetDateTime(odt), 23);
    seconds := Seconds(odt) - odt.offset;
    ok := (seconds >= Instants.earliest.seconds) & (seconds <= Instants.latest.seconds);
    IF ok THEN Instants.FromUnix(t, seconds, odt.nanosecond) END;
    RETURN ok
  END CheckedToInstant;

  (* Where CheckedToInstant fails, the instant saturates at
     Instants.earliest or Instants.latest, the values Instants.Add
     saturates to. *)
  PROCEDURE ToInstant*(odt: OffsetDateTime; VAR t: Instants.Instant);
  BEGIN
    ASSERT(ValidOffsetDateTime(odt), 23);
    Instants.FromUnix(t, Seconds(odt) - odt.offset, odt.nanosecond)
  END ToInstant;

  (* FALSE, leaving odt unchanged, when the offset carries the civil time
     out of the years, as Instants.latest at +14:00 would be in 10000. Only
     instants within 26 hours of either end can fail (doc/instant-offsets.md). *)
  PROCEDURE CheckedFromInstant*(VAR odt: OffsetDateTime; t: Instants.Instant; offset: LONGINT): BOOLEAN;
    VAR seconds: HUGEINT; ok: BOOLEAN;
  BEGIN
    ASSERT((offset >= -maxOffset) & (offset <= maxOffset), 23);
    seconds := t.seconds + offset;
    ok := (seconds >= Instants.earliest.seconds) & (seconds <= Instants.latest.seconds);
    IF ok THEN SetSeconds(odt, seconds, t.nanosecond);  odt.offset := offset END;
    RETURN ok
  END CheckedFromInstant;

  (* Where CheckedFromInstant fails, the civil time saturates at the first
     or last moment of the years and keeps the offset asked for. The result
     is then a valid OffsetDateTime that names a different instant: up to
     26 hours from t. This lets a "forever" of Instants.latest be shown in
     any zone, as 9999-12-31T23:59:59.999999999. *)
  PROCEDURE FromInstant*(VAR odt: OffsetDateTime; t: Instants.Instant; offset: LONGINT);
  BEGIN
    IF ~CheckedFromInstant(odt, t, offset) THEN
      (* only an offset toward the nearer end can carry t past it *)
      IF offset < 0 THEN
        SetSeconds(odt, Instants.earliest.seconds, 0)
      ELSE
        SetSeconds(odt, Instants.latest.seconds, second - 1)
      END;
      odt.offset := offset
    END
  END FromInstant;

  PROCEDURE FromUTCInstant*(VAR dt: DateTime; t: Instants.Instant);
  BEGIN
    SetSeconds(dt, t.seconds, t.nanosecond)
  END FromUTCInstant;

  (* The Oberon system's packed clock: d is the year MOD 100 * 512 + the
     month * 32 + the day, t is the hour * 4096 + the minute * 64 + the
     second. Years 00-69 are read as 2000-2069, 70-99 as 1970-1999. *)
  PROCEDURE FromOberonClock*(VAR dt: DateTime; t, d: LONGINT): BOOLEAN;
    VAR year: LONGINT;
  BEGIN
    year := d DIV 512;
    IF year < 70 THEN INC(year, 2000) ELSE INC(year, 1900) END;
    RETURN (d >= 0) & (d DIV 512 <= 99) & (t >= 0)
      & SetDateTime(dt, year, d DIV 32 MOD 16, d MOD 32, t DIV 4096, t DIV 64 MOD 64, t MOD 64, 0)
  END FromOberonClock;

  PROCEDURE ToOberonClock*(dt: DateTime; VAR t, d: LONGINT);
  BEGIN
    ASSERT(ValidDateTime(dt), 22);
    d := dt.year MOD 100 * 512 + dt.month * 32 + dt.day;
    t := dt.hour * 4096 + dt.minute * 64 + dt.second
  END ToOberonClock;

END Calendar.
