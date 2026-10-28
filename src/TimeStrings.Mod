MODULE TimeStrings;

  (* Dates, times, durations and periods to and from text in fixed
     formats, ISO 8601's extended format and RFC 3339's profile of it
     (design section 10.1), and date-times by strftime's patterns (10.2).

     Output is appended at s's first 0X, as OutStr does: cut short
     silently, and s always ends in a 0X. A fraction is cut, not rounded,
     so that 23:59:59.9999 never becomes the next day.

     Input reads from s[pos], as InStr does, and returns TRUE with pos
     moved past the text, or FALSE with pos and the result unchanged.
     Nothing is skipped before the text, and what follows is the caller's,
     except a digit: text followed at once by a digit is refused, so that
     "+0530" is not read as +05 and "14:05:091" not as 14:05:09.

     ASSERT numbers:
       20  an invalid Date
       21  an invalid TimeOfDay
       22  an invalid DateTime
       23  an invalid OffsetDateTime
       24  digits neither shortest nor 0..9 *)

  IMPORT Durations, Instants, Calendar, TimeZones;

  CONST
    shortest* = -1;   (* digits: 0, 3, 6 or 9 fractional digits, the fewest that are exact *)

    second = Durations.second;
    (* longer than any text written here: a Period under -OC is 66 *)
    maxText = 96;

    (* elements of Parse's given *)
    yearGiven* = 0;  monthGiven* = 1;  dayGiven* = 2;  hourGiven* = 3;  minuteGiven* = 4;
    secondGiven* = 5;  fractionGiven* = 6;  offsetGiven* = 7;  weekdayGiven* = 8;
    (* elements of Fields.given beyond the exported ones *)
    centuryGiven = 9;  shortYearGiven = 10;  weekYearGiven = 11;  shortWeekYearGiven = 12;
    weekGiven = 13;  yearDayGiven = 14;  hour12Given = 15;  pmGiven = 16;
    secondsGiven = 17;  sundayWeekGiven = 18;  mondayWeekGiven = 19;

  TYPE
    (* a month's or weekday's name *)
    Name = ARRAY 12 OF CHAR;

    (* text being built, before it is appended to the caller's string *)
    Text = RECORD
      s: ARRAY maxText OF CHAR;
      n: LONGINT
    END;

  (* what Parse has read so far. given holds the exported elements and the
     ones below, for the fields that settle the date-time only at the end. *)
    Fields = RECORD
      given: SET;
      year, month, day, hour, minute, second, nanosecond, offset: LONGINT;
      century, shortYear, weekYear, shortWeekYear, week, weekday, yearDay: LONGINT;
      hour12, sundayWeek, mondayWeek: LONGINT;
      pm: BOOLEAN;
      seconds: HUGEINT
    END;

  (* ---- output ---- *)

  PROCEDURE Open(VAR t: Text);
  BEGIN
    t.n := 0;  t.s[0] := 0X
  END Open;

  PROCEDURE Put(VAR t: Text; c: CHAR);
  BEGIN
    t.s[t.n] := c;  INC(t.n);  t.s[t.n] := 0X
  END Put;

  (* t at s's first 0X, as OutStr.String appends: if s has no 0X, its last
     character becomes one *)
  PROCEDURE Close(VAR t: Text; VAR s: ARRAY OF CHAR);
    VAR e, k: LONGINT;
  BEGIN
    e := 0;
    WHILE (e < LEN(s)) & (s[e] # 0X) DO INC(e) END;
    IF e = LEN(s) THEN e := LEN(s) - 1 END;
    k := 0;
    WHILE (k < t.n) & (e < LEN(s) - 1) DO s[e] := t.s[k];  INC(e);  INC(k) END;
    s[e] := 0X
  END Close;

  (* the digits of ABS(x), at least width of them. They are taken from a
     value made negative, since MIN(HUGEINT) has no ABS. *)
  PROCEDURE Digits(VAR t: Text; x: HUGEINT; width: INTEGER);
    VAR reversed: ARRAY 24 OF CHAR; n: INTEGER; q, r: HUGEINT;
  BEGIN
    IF x > 0 THEN x := -x END;
    n := 0;
    REPEAT
      (* truncated division of a value <= 0: remainder in -9..0 *)
      q := x DIV 10;  r := x MOD 10;
      IF r # 0 THEN INC(q);  DEC(r, 10) END;
      reversed[n] := CHR(ORD("0") - SHORT(SHORT(r)));  INC(n);
      x := q
    UNTIL x = 0;
    WHILE n < width DO reversed[n] := "0";  INC(n) END;
    WHILE n > 0 DO DEC(n);  Put(t, reversed[n]) END
  END Digits;

  (* the number of fractional digits for nanosecond, digits being shortest
     or 0..9 *)
  PROCEDURE Places(nanosecond: LONGINT; digits: INTEGER): INTEGER;
  BEGIN
    IF digits = shortest THEN
      IF nanosecond = 0 THEN digits := 0
      ELSIF nanosecond MOD 1000000 = 0 THEN digits := 3
      ELSIF nanosecond MOD 1000 = 0 THEN digits := 6
      ELSE digits := 9
      END
    ELSE
      ASSERT((digits >= 0) & (digits <= 9), 24)
    END;
    RETURN digits
  END Places;

  (* "." and the first places digits of nanosecond's nine *)
  PROCEDURE Fraction(VAR t: Text; nanosecond: LONGINT; places: INTEGER);
    VAR nine: Text; k: INTEGER;
  BEGIN
    IF places > 0 THEN
      Open(nine);  Digits(nine, nanosecond, 9);
      Put(t, ".");
      FOR k := 0 TO places - 1 DO Put(t, nine.s[k]) END
    END
  END Fraction;

  PROCEDURE PutDate(VAR t: Text; year, month, day: LONGINT);
  BEGIN
    (* ISO 8601's expanded form for a negative year, -0044 *)
    IF year < 0 THEN Put(t, "-") END;
    Digits(t, year, 4);  Put(t, "-");  Digits(t, month, 2);  Put(t, "-");  Digits(t, day, 2)
  END PutDate;

  PROCEDURE PutTime(VAR t: Text; hour, minute, second, nanosecond: LONGINT; digits: INTEGER);
  BEGIN
    Digits(t, hour, 2);  Put(t, ":");  Digits(t, minute, 2);  Put(t, ":");  Digits(t, second, 2);
    Fraction(t, nanosecond, Places(nanosecond, digits))
  END PutTime;

  (* Z for 0; otherwise +hh:mm, or +hh:mm:ss for an offset in seconds,
     such as a zone's local mean time *)
  PROCEDURE PutOffset(VAR t: Text; offset: LONGINT);
  BEGIN
    IF offset = 0 THEN Put(t, "Z")
    ELSE
      IF offset < 0 THEN Put(t, "-");  offset := -offset ELSE Put(t, "+") END;
      Digits(t, offset DIV 3600, 2);  Put(t, ":");  Digits(t, offset DIV 60 MOD 60, 2);
      IF offset MOD 60 # 0 THEN Put(t, ":");  Digits(t, offset MOD 60, 2) END
    END
  END PutOffset;

  PROCEDURE Date*(d: Calendar.Date; VAR s: ARRAY OF CHAR);
    VAR t: Text;
  BEGIN
    ASSERT(Calendar.ValidDate(d), 20);
    Open(t);  PutDate(t, d.year, d.month, d.day);  Close(t, s)
  END Date;

  PROCEDURE TimeOfDay*(time: Calendar.TimeOfDay; digits: INTEGER; VAR s: ARRAY OF CHAR);
    VAR t: Text;
  BEGIN
    ASSERT(Calendar.ValidTimeOfDay(time), 21);
    Open(t);  PutTime(t, time.hour, time.minute, time.second, time.nanosecond, digits);
    Close(t, s)
  END TimeOfDay;

  PROCEDURE PutDateTime(VAR t: Text; dt: Calendar.DateTime; digits: INTEGER);
  BEGIN
    PutDate(t, dt.year, dt.month, dt.day);  Put(t, "T");
    PutTime(t, dt.hour, dt.minute, dt.second, dt.nanosecond, digits)
  END PutDateTime;

  PROCEDURE DateTime*(dt: Calendar.DateTime; digits: INTEGER; VAR s: ARRAY OF CHAR);
    VAR t: Text;
  BEGIN
    ASSERT(Calendar.ValidDateTime(dt), 22);
    Open(t);  PutDateTime(t, dt, digits);  Close(t, s)
  END DateTime;

  PROCEDURE OffsetDateTime*(odt: Calendar.OffsetDateTime; digits: INTEGER; VAR s: ARRAY OF CHAR);
    VAR t: Text;
  BEGIN
    ASSERT(Calendar.ValidOffsetDateTime(odt), 23);
    Open(t);  PutDateTime(t, odt, digits);  PutOffset(t, odt.offset);  Close(t, s)
  END OffsetDateTime;

  PROCEDURE Instant*(i: Instants.Instant; digits: INTEGER; VAR s: ARRAY OF CHAR);
    VAR t: Text; dt: Calendar.DateTime;
  BEGIN
    Calendar.FromUTCInstant(dt, i);
    Open(t);  PutDateTime(t, dt, digits);  Put(t, "Z");  Close(t, s)
  END Instant;

  (* hours, minutes and seconds only, since a Duration's day is not a
     calendar day: PT26H, -PT0.5S, PT0S. The fraction has as many digits
     as it needs, as Java's Duration.toString writes it. *)
  PROCEDURE Duration*(d: Durations.Duration; VAR s: ARRAY OF CHAR);
    VAR
      t: Text; negative: BOOLEAN; days, hours, minutes, seconds, nanoseconds: LONGINT;
      places: INTEGER; rest: LONGINT;
  BEGIN
    Durations.Split(d, negative, days, hours, minutes, seconds, nanoseconds);
    Open(t);
    IF negative THEN Put(t, "-") END;
    Put(t, "P");  Put(t, "T");
    IF (days # 0) OR (hours # 0) THEN Digits(t, days * 24 + hours, 1);  Put(t, "H") END;
    IF minutes # 0 THEN Digits(t, minutes, 1);  Put(t, "M") END;
    IF (seconds # 0) OR (nanoseconds # 0) OR (d = 0) THEN
      Digits(t, seconds, 1);
      places := 9;  rest := nanoseconds;
      WHILE (places > 0) & (rest MOD 10 = 0) DO DEC(places);  rest := rest DIV 10 END;
      Fraction(t, nanoseconds, places);
      Put(t, "S")
    END;
    Close(t, s)
  END Duration;

  (* the clock style, [-]h:mm:ss[.f], the hours unbounded: 26:03:04.5,
     -0:00:01 *)
  PROCEDURE Elapsed*(d: Durations.Duration; digits: INTEGER; VAR s: ARRAY OF CHAR);
    VAR t: Text; negative: BOOLEAN; days, hours, minutes, seconds, nanoseconds: LONGINT;
  BEGIN
    Durations.Split(d, negative, days, hours, minutes, seconds, nanoseconds);
    Open(t);
    IF negative THEN Put(t, "-") END;
    Digits(t, days * 24 + hours, 1);  Put(t, ":");
    Digits(t, minutes, 2);  Put(t, ":");  Digits(t, seconds, 2);
    Fraction(t, nanoseconds, Places(nanoseconds, digits));
    Close(t, s)
  END Elapsed;

  (* a period's field, unless it is 0; its sign unless outside has it *)
  PROCEDURE Field(VAR t: Text; x: LONGINT; designator: CHAR; outside: BOOLEAN);
  BEGIN
    IF x # 0 THEN
      IF (x < 0) & ~outside THEN Put(t, "-") END;
      Digits(t, x, 1);  Put(t, designator)
    END
  END Field;

  (* P1Y2M3D, P0D. A period with no field above 0 is written with one
     sign in front, -P1Y2M, as a Duration is; one whose fields differ in
     sign gives each negative field its own, P1Y-2M, as Java writes every
     period. *)
  PROCEDURE Period*(p: Calendar.Period; VAR s: ARRAY OF CHAR);
    VAR t: Text; outside: BOOLEAN;
  BEGIN
    outside := (p.years <= 0) & (p.months <= 0) & (p.days <= 0)
      & ((p.years # 0) OR (p.months # 0) OR (p.days # 0));
    Open(t);
    IF outside THEN Put(t, "-") END;
    Put(t, "P");
    Field(t, p.years, "Y", outside);  Field(t, p.months, "M", outside);
    Field(t, p.days, "D", outside);
    IF (p.years = 0) & (p.months = 0) & (p.days = 0) THEN Put(t, "0");  Put(t, "D") END;
    Close(t, s)
  END Period;

  (* ---- input ---- *)

  (* s[i], or 0X past the end of s *)
  PROCEDURE At(s-: ARRAY OF CHAR; i: LONGINT): CHAR;
    VAR c: CHAR;
  BEGIN
    IF (i >= 0) & (i < LEN(s)) THEN c := s[i] ELSE c := 0X END;
    RETURN c
  END At;

  PROCEDURE IsDigit(c: CHAR): BOOLEAN;
  BEGIN
    RETURN (c >= "0") & (c <= "9")
  END IsDigit;

  (* whether pos is within s's text, which ends at its first 0X *)
  PROCEDURE Within(s-: ARRAY OF CHAR; pos: LONGINT): BOOLEAN;
    VAR e: LONGINT;
  BEGIN
    e := 0;
    WHILE (e < LEN(s)) & (s[e] # 0X) DO INC(e) END;
    RETURN (pos >= 0) & (pos < e)
  END Within;

  (* the end of what a reader took: anything but a digit may follow *)
  PROCEDURE Ends(s-: ARRAY OF CHAR; i: LONGINT): BOOLEAN;
  BEGIN
    RETURN ~IsDigit(At(s, i))
  END Ends;

  PROCEDURE Skip(s-: ARRAY OF CHAR; VAR i: LONGINT; c: CHAR): BOOLEAN;
    VAR found: BOOLEAN;
  BEGIN
    found := At(s, i) = c;
    IF found THEN INC(i) END;
    RETURN found
  END Skip;

  (* exactly width digits *)
  PROCEDURE Fixed(s-: ARRAY OF CHAR; VAR i: LONGINT; width: INTEGER; VAR x: LONGINT): BOOLEAN;
    VAR k: INTEGER;
  BEGIN
    x := 0;  k := 0;
    WHILE (k < width) & IsDigit(At(s, i + k)) DO
      x := x * 10 + (ORD(At(s, i + k)) - ORD("0"));  INC(k)
    END;
    IF k = width THEN INC(i, width) END;
    RETURN k = width
  END Fixed;

  (* One or more digits, as -x: a negative value reaches one further than
     a positive, so MIN(HUGEINT) and MIN(LONGINT) can be read. FALSE if
     -x would fall below low. *)
  PROCEDURE Negated(s-: ARRAY OF CHAR; VAR i: LONGINT; low: HUGEINT; VAR x: HUGEINT): BOOLEAN;
    VAR ok: BOOLEAN; digit, tens: HUGEINT;
  BEGIN
    ok := IsDigit(At(s, i));  x := 0;
    WHILE ok & IsDigit(At(s, i)) DO
      digit := ORD(At(s, i)) - ORD("0");
      (* x * 10 - digit >= low, without overflow; low DIV 10 floors *)
      IF x < low DIV 10 THEN ok := FALSE
      ELSE
        tens := x * 10;
        IF tens < low + digit THEN ok := FALSE ELSE x := tens - digit;  INC(i) END
      END
    END;
    RETURN ok
  END Negated;

  (* "." and 1-9 digits, as nanoseconds; none at all is 0 *)
  PROCEDURE ReadFraction(s-: ARRAY OF CHAR; VAR i: LONGINT; VAR nanosecond: LONGINT): BOOLEAN;
    VAR ok: BOOLEAN; places: INTEGER;
  BEGIN
    ok := TRUE;  nanosecond := 0;
    IF Skip(s, i, ".") THEN
      places := 0;
      WHILE (places < 9) & IsDigit(At(s, i)) DO
        nanosecond := nanosecond * 10 + (ORD(At(s, i)) - ORD("0"));  INC(places);  INC(i)
      END;
      ok := (places > 0) & ~IsDigit(At(s, i));
      WHILE places < 9 DO nanosecond := nanosecond * 10;  INC(places) END
    END;
    RETURN ok
  END ReadFraction;

  (* [-]yyyy-mm-dd, the year in 0000..9999 or -9999..-0001 *)
  PROCEDURE ReadDateFields(s-: ARRAY OF CHAR; VAR i: LONGINT; VAR d: Calendar.Date): BOOLEAN;
    VAR negative, ok: BOOLEAN; year, month, day: LONGINT;
  BEGIN
    negative := Skip(s, i, "-");
    ok := Fixed(s, i, 4, year) & Skip(s, i, "-") & Fixed(s, i, 2, month)
      & Skip(s, i, "-") & Fixed(s, i, 2, day);
    IF ok & negative THEN ok := year # 0;  year := -year END;
    RETURN ok & Calendar.SetDate(d, year, month, day)
  END ReadDateFields;

  (* hh:mm:ss[.f]; a second of 60 is let through, for the caller to judge *)
  PROCEDURE ReadTimeFields(s-: ARRAY OF CHAR; VAR i: LONGINT; VAR t: Calendar.TimeOfDay): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN
    ok := Fixed(s, i, 2, t.hour) & Skip(s, i, ":") & Fixed(s, i, 2, t.minute)
      & Skip(s, i, ":") & Fixed(s, i, 2, t.second) & ReadFraction(s, i, t.nanosecond);
    RETURN ok & (t.hour <= 23) & (t.minute <= 59) & (t.second <= 60)
  END ReadTimeFields;

  (* a date, T, t or a space, and a time *)
  PROCEDURE ReadDateTimeFields(s-: ARRAY OF CHAR; VAR i: LONGINT; VAR dt: Calendar.DateTime): BOOLEAN;
    VAR ok: BOOLEAN; d: Calendar.Date; t: Calendar.TimeOfDay;
  BEGIN
    ok := ReadDateFields(s, i, d)
      & (Skip(s, i, "T") OR Skip(s, i, "t") OR Skip(s, i, " "))
      & ReadTimeFields(s, i, t);
    IF ok THEN
      dt.year := d.year;  dt.month := d.month;  dt.day := d.day;
      dt.hour := t.hour;  dt.minute := t.minute;  dt.second := t.second;
      dt.nanosecond := t.nanosecond
    END;
    RETURN ok
  END ReadDateTimeFields;

  (* Z, z, +hh, +hh:mm or +hh:mm:ss, or the same with -, up to 25:59:59 *)
  PROCEDURE ReadOffset(s-: ARRAY OF CHAR; VAR i: LONGINT; VAR offset: LONGINT): BOOLEAN;
    VAR ok, negative: BOOLEAN; hours, minutes, seconds: LONGINT;
  BEGIN
    IF Skip(s, i, "Z") OR Skip(s, i, "z") THEN ok := TRUE;  offset := 0
    ELSE
      negative := At(s, i) = "-";
      ok := (Skip(s, i, "+") OR Skip(s, i, "-")) & Fixed(s, i, 2, hours);
      minutes := 0;  seconds := 0;
      IF ok & Skip(s, i, ":") THEN
        ok := Fixed(s, i, 2, minutes);
        IF ok & Skip(s, i, ":") THEN ok := Fixed(s, i, 2, seconds) END
      END;
      ok := ok & (hours <= 25) & (minutes <= 59) & (seconds <= 59);
      offset := hours * 3600 + minutes * 60 + seconds;
      IF negative THEN offset := -offset END
    END;
    RETURN ok
  END ReadOffset;

  (* Whether odt, read with a second of 60 and holding 59, is at a leap
     second: where the time in UTC is 23:59:60 on the last day of a month.
     It is then read as 59.999999999, whatever fraction followed
     (doc/leap-seconds.md). *)
  PROCEDURE LeapSecond(VAR odt: Calendar.OffsetDateTime): BOOLEAN;
    VAR ok: BOOLEAN; t: Instants.Instant; utc: Calendar.DateTime;
  BEGIN
    odt.nanosecond := 0;
    ok := Calendar.CheckedToInstant(t, odt);
    IF ok THEN
      Calendar.FromUTCInstant(utc, t);
      ok := (utc.hour = 23) & (utc.minute = 59) & (utc.second = 59)
        & (utc.day = Calendar.DaysInMonth(utc.year, utc.month));
      odt.nanosecond := second - 1
    END;
    RETURN ok
  END LeapSecond;

  (* a date-time with an offset; a second of 60 only at a leap second *)
  PROCEDURE ReadOffsetFields(s-: ARRAY OF CHAR; VAR i: LONGINT; VAR odt: Calendar.OffsetDateTime): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN
    ok := ReadDateTimeFields(s, i, odt) & ReadOffset(s, i, odt.offset);
    IF ok & (odt.second = 60) THEN odt.second := 59;  ok := LeapSecond(odt) END;
    RETURN ok
  END ReadOffsetFields;

  (* The readers below read into a local, and copy it field by field,
     since the caller's VAR record may be an extension (Calendar's
     comment). *)

  PROCEDURE ReadDate*(VAR d: Calendar.Date; s-: ARRAY OF CHAR; VAR pos: LONGINT): BOOLEAN;
    VAR ok: BOOLEAN; i: LONGINT; r: Calendar.Date;
  BEGIN
    i := pos;
    ok := Within(s, pos) & ReadDateFields(s, i, r) & Ends(s, i);
    IF ok THEN d.year := r.year;  d.month := r.month;  d.day := r.day;  pos := i END;
    RETURN ok
  END ReadDate;

  PROCEDURE ReadTimeOfDay*(VAR t: Calendar.TimeOfDay; s-: ARRAY OF CHAR; VAR pos: LONGINT): BOOLEAN;
    VAR ok: BOOLEAN; i: LONGINT; r: Calendar.TimeOfDay;
  BEGIN
    i := pos;
    ok := Within(s, pos) & ReadTimeFields(s, i, r) & (r.second <= 59) & Ends(s, i);
    IF ok THEN
      t.hour := r.hour;  t.minute := r.minute;  t.second := r.second;
      t.nanosecond := r.nanosecond;  pos := i
    END;
    RETURN ok
  END ReadTimeOfDay;

  PROCEDURE ReadDateTime*(VAR dt: Calendar.DateTime; s-: ARRAY OF CHAR; VAR pos: LONGINT): BOOLEAN;
    VAR ok: BOOLEAN; i: LONGINT; r: Calendar.DateTime;
  BEGIN
    i := pos;
    ok := Within(s, pos) & ReadDateTimeFields(s, i, r) & (r.second <= 59) & Ends(s, i);
    IF ok THEN
      dt.year := r.year;  dt.month := r.month;  dt.day := r.day;
      dt.hour := r.hour;  dt.minute := r.minute;  dt.second := r.second;
      dt.nanosecond := r.nanosecond;  pos := i
    END;
    RETURN ok
  END ReadDateTime;

  PROCEDURE ReadOffsetDateTime*(VAR odt: Calendar.OffsetDateTime; s-: ARRAY OF CHAR;
                                VAR pos: LONGINT): BOOLEAN;
    VAR ok: BOOLEAN; i: LONGINT; r: Calendar.OffsetDateTime;
  BEGIN
    i := pos;
    ok := Within(s, pos) & ReadOffsetFields(s, i, r) & Ends(s, i);
    IF ok THEN
      odt.year := r.year;  odt.month := r.month;  odt.day := r.day;
      odt.hour := r.hour;  odt.minute := r.minute;  odt.second := r.second;
      odt.nanosecond := r.nanosecond;  odt.offset := r.offset;  pos := i
    END;
    RETURN ok
  END ReadOffsetDateTime;

  (* needs an offset or Z, and refuses a time outside the instants, as
     -9999-01-01T00:00:00+01:00 is (Q13) *)
  PROCEDURE ReadInstant*(VAR t: Instants.Instant; s-: ARRAY OF CHAR; VAR pos: LONGINT): BOOLEAN;
    VAR ok: BOOLEAN; i: LONGINT; r: Calendar.OffsetDateTime; u: Instants.Instant;
  BEGIN
    i := pos;
    ok := Within(s, pos) & ReadOffsetFields(s, i, r) & Ends(s, i)
      & Calendar.CheckedToInstant(u, r);
    IF ok THEN t := u;  pos := i END;
    RETURN ok
  END ReadInstant;

  (* -x * unit added to the negative sum, if it fits *)
  PROCEDURE Accumulate(VAR sum: HUGEINT; x, unit: HUGEINT): BOOLEAN;
    VAR ok: BOOLEAN; product: HUGEINT;
  BEGIN
    ok := Durations.CheckedScale(product, x, unit) & (sum >= Durations.min - product);
    IF ok THEN sum := sum + product END;
    RETURN ok
  END Accumulate;

  (* The ISO form [-]P[nW][nD][T[nH][nM][n[.f]S]], with D read as 24 hours
     and W as 7 days, or the Elapsed form [-]h:mm:ss[.f]. Y, and M before
     the T, are calendar units, read by ReadPeriod. The sum is kept
     negative until the end, so that Durations.min can be read. *)
  PROCEDURE ReadDuration*(VAR d: Durations.Duration; s-: ARRAY OF CHAR; VAR pos: LONGINT): BOOLEAN;
    VAR
      ok, negative, any, inTime, fraction: BOOLEAN; i: LONGINT; sum, x: HUGEINT;
      rank, last: INTEGER; unit: HUGEINT; c: CHAR; minutes, seconds, nanosecond: LONGINT;
  BEGIN
    i := pos;  sum := 0;
    ok := Within(s, pos);
    negative := Skip(s, i, "-");
    IF ~ok THEN
    ELSIF Skip(s, i, "P") THEN
      any := FALSE;  inTime := FALSE;  last := 0;
      LOOP
        IF ~inTime & Skip(s, i, "T") THEN
          inTime := TRUE;  ok := IsDigit(At(s, i))
        END;
        IF ~ok OR ~IsDigit(At(s, i)) THEN EXIT END;
        ok := Negated(s, i, Durations.min, x);
        fraction := At(s, i) = ".";
        ok := ok & ReadFraction(s, i, nanosecond);
        IF ~ok THEN EXIT END;
        c := At(s, i);  INC(i);  rank := 0;
        IF ~inTime THEN
          IF c = "W" THEN rank := 1;  unit := Durations.week
          ELSIF c = "D" THEN rank := 2;  unit := Durations.day
          END
        ELSIF c = "H" THEN rank := 3;  unit := Durations.hour
        ELSIF c = "M" THEN rank := 4;  unit := Durations.minute
        ELSIF c = "S" THEN rank := 5;  unit := second
        END;
        (* in order, each once, and a fraction on the seconds only *)
        ok := (rank > last) & (~fraction OR (rank = 5))
          & Accumulate(sum, x, unit);
        IF ok & (rank = 5) THEN ok := Accumulate(sum, nanosecond, -1) END;
        IF ~ok THEN EXIT END;
        last := rank;  any := TRUE
      END;
      ok := ok & any
    ELSE
      ok := Negated(s, i, Durations.min, x) & Skip(s, i, ":") & Fixed(s, i, 2, minutes)
        & Skip(s, i, ":") & Fixed(s, i, 2, seconds) & ReadFraction(s, i, nanosecond)
        & (minutes <= 59) & (seconds <= 59)
        & Accumulate(sum, x, Durations.hour) & Accumulate(sum, -minutes, Durations.minute)
        & Accumulate(sum, -seconds, second) & Accumulate(sum, nanosecond, -1)
    END;
    ok := ok & Ends(s, i);
    IF ok & ~negative THEN ok := sum # Durations.min;  sum := -sum END;
    IF ok THEN d := sum;  pos := i END;
    RETURN ok
  END ReadDuration;

  (* a + b, if it fits *)
  PROCEDURE Add(VAR r: HUGEINT; a, b: HUGEINT): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN
    ok := ~((b > 0) & (a > MAX(HUGEINT) - b) OR (b < 0) & (a < MIN(HUGEINT) - b));
    IF ok THEN r := a + b END;
    RETURN ok
  END Add;

  (* [-]P[n Y][n M][n W][n D], each n with its own optional -, and W read as
     7 days: P1Y2M3W4D, -P1M, P1Y-2M. A - in front negates every field. *)
  (* x, which fits in a LONGINT. Under -OC, SHORT of a HUGEINT gives a
     32-bit INTEGER, not the 64-bit LONGINT, so x goes over in 21-bit
     pieces, each of which fits either way. *)
  PROCEDURE Long(x: HUGEINT): LONGINT;
    CONST piece = 2097152;
    VAR r: LONGINT;
  BEGIN
    r := SHORT(x DIV piece DIV piece);
    r := r * piece + SHORT(x DIV piece MOD piece);
    RETURN r * piece + SHORT(x MOD piece)
  END Long;

  PROCEDURE ReadPeriod*(VAR p: Calendar.Period; s-: ARRAY OF CHAR; VAR pos: LONGINT): BOOLEAN;
    VAR
      ok, negative, minus, any: BOOLEAN; i: LONGINT; x: HUGEINT; c: CHAR;
      rank, last: INTEGER; years, months, days: HUGEINT;
  BEGIN
    i := pos;  years := 0;  months := 0;  days := 0;
    ok := Within(s, pos);
    negative := Skip(s, i, "-");
    ok := ok & Skip(s, i, "P");
    any := FALSE;  last := 0;
    WHILE ok & ((At(s, i) = "-") OR IsDigit(At(s, i))) DO
      minus := Skip(s, i, "-");
      ok := Negated(s, i, MIN(LONGINT), x);
      (* x is -n; the field is -n if exactly one sign says negative *)
      IF ok & (minus = negative) THEN ok := x # MIN(HUGEINT);  x := -x END;
      c := At(s, i);  INC(i);  rank := 0;
      IF c = "Y" THEN rank := 1;  ok := ok & Add(years, years, x)
      ELSIF c = "M" THEN rank := 2;  ok := ok & Add(months, months, x)
      ELSIF c = "W" THEN rank := 3;  ok := ok & Durations.CheckedScale(x, x, 7) & Add(days, days, x)
      ELSIF c = "D" THEN rank := 4;  ok := ok & Add(days, days, x)
      END;
      ok := ok & (rank > last);
      last := rank;  any := TRUE
    END;
    ok := ok & any & Ends(s, i)
      & (years >= MIN(LONGINT)) & (years <= MAX(LONGINT))
      & (months >= MIN(LONGINT)) & (months <= MAX(LONGINT))
      & (days >= MIN(LONGINT)) & (days <= MAX(LONGINT));
    IF ok THEN
      p.years := Long(years);  p.months := Long(months);  p.days := Long(days);  pos := i
    END;
    RETURN ok
  END ReadPeriod;

  (* ---- patterns (design 10.2) ---- *)

  (* the first 0X of s, or its last place if it has none, as Close finds it *)
  PROCEDURE End(VAR s: ARRAY OF CHAR): LONGINT;
    VAR e: LONGINT;
  BEGIN
    e := 0;
    WHILE (e < LEN(s)) & (s[e] # 0X) DO INC(e) END;
    IF e = LEN(s) THEN e := LEN(s) - 1 END;
    RETURN e
  END End;

  (* x appended at s's first 0X, as Close appends a Text *)
  PROCEDURE Append(x-: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);
    VAR e, k: LONGINT;
  BEGIN
    e := End(s);  k := 0;
    WHILE (k < LEN(x)) & (x[k] # 0X) & (e < LEN(s) - 1) DO s[e] := x[k];  INC(e);  INC(k) END;
    s[e] := 0X
  END Append;

  PROCEDURE Upper(c: CHAR): CHAR;
  BEGIN
    IF (c >= "a") & (c <= "z") THEN c := CHR(ORD(c) - ORD("a") + ORD("A")) END;
    RETURN c
  END Upper;

  PROCEDURE MonthName(month: LONGINT; VAR name: Name);
  BEGIN
    CASE month OF
      1: name := "January"
    | 2: name := "February"
    | 3: name := "March"
    | 4: name := "April"
    | 5: name := "May"
    | 6: name := "June"
    | 7: name := "July"
    | 8: name := "August"
    | 9: name := "September"
    | 10: name := "October"
    | 11: name := "November"
    | 12: name := "December"
    END
  END MonthName;

  (* Calendar's weekdays, Monday 1 to Sunday 7 *)
  PROCEDURE WeekdayName(weekday: LONGINT; VAR name: Name);
  BEGIN
    CASE weekday OF
      1: name := "Monday"
    | 2: name := "Tuesday"
    | 3: name := "Wednesday"
    | 4: name := "Thursday"
    | 5: name := "Friday"
    | 6: name := "Saturday"
    | 7: name := "Sunday"
    END
  END WeekdayName;

  (* name, or its first three letters *)
  PROCEDURE PutName(VAR t: Text; name-: ARRAY OF CHAR; abbreviated: BOOLEAN);
    VAR k: INTEGER;
  BEGIN
    k := 0;
    WHILE (name[k] # 0X) & (~abbreviated OR (k < 3)) DO Put(t, name[k]);  INC(k) END
  END PutName;

  (* x padded to width with pad, "0" or " ", or not at all for 0X. The
     sign counts toward the width, and zeros go after it and spaces before
     it, as printf puts them: %C of -44 is -1. *)
  PROCEDURE Number(VAR t: Text; x: HUGEINT; width: INTEGER; pad: CHAR);
    VAR digits: Text; k, n: LONGINT;
  BEGIN
    Open(digits);  Digits(digits, x, 1);
    n := digits.n;
    IF x < 0 THEN INC(n) END;
    IF pad = " " THEN FOR k := n TO width - 1 DO Put(t, " ") END END;
    IF x < 0 THEN Put(t, "-") END;
    IF pad = "0" THEN FOR k := n TO width - 1 DO Put(t, "0") END END;
    FOR k := 0 TO digits.n - 1 DO Put(t, digits.s[k]) END
  END Number;

  (* the width of %Y and %G: four digits, and a - before a negative year,
     as Date writes it (Q18) *)
  PROCEDURE YearWidth(year: LONGINT): INTEGER;
    VAR width: INTEGER;
  BEGIN
    IF year < 0 THEN width := 5 ELSE width := 4 END;
    RETURN width
  END YearWidth;

  (* +hhmm with no colons, +hh:mm with one, +hh:mm:ss with two; the
     seconds also when the offset has them (Q21) *)
  PROCEDURE PutNumericOffset(VAR t: Text; offset: LONGINT; colons: INTEGER);
  BEGIN
    IF offset < 0 THEN Put(t, "-");  offset := -offset ELSE Put(t, "+") END;
    Digits(t, offset DIV 3600, 2);
    IF colons > 0 THEN Put(t, ":") END;
    Digits(t, offset DIV 60 MOD 60, 2);
    IF (colons = 2) OR (offset MOD 60 # 0) THEN
      IF colons > 0 THEN Put(t, ":") END;
      Digits(t, offset MOD 60, 2)
    END
  END PutNumericOffset;

  (* the padding a directive's flag asks for: none for -, its own for no
     flag *)
  PROCEDURE Pad(flag, default: CHAR): CHAR;
  BEGIN
    IF flag = "-" THEN flag := 0X ELSIF flag = 0X THEN flag := default END;
    RETURN flag
  END Pad;

  (* %U's and %W's week: the weeks start on the year's first Sunday or
     Monday, first, and the days before it are week 0 *)
  PROCEDURE WeekOfYear(d: Calendar.Date; first: LONGINT): LONGINT;
  BEGIN
    RETURN (Calendar.DayOfYear(d) - 1 + 7 - (Calendar.DayOfWeek(d) - first) MOD 7) DIV 7
  END WeekOfYear;

  (* pattern written at s's end; odt is valid *)
  PROCEDURE Expand(pattern-: ARRAY OF CHAR; VAR odt: Calendar.OffsetDateTime;
                   abbreviation-: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);
    VAR
      i, j, e, k: LONGINT; c: CHAR; pad: CHAR; upper, known: BOOLEAN;
      width, colons: INTEGER; t: Text; name: Name;
      weekYear, week: LONGINT;
  BEGIN
    i := 0;
    WHILE (i < LEN(pattern)) & (pattern[i] # 0X) DO
      IF pattern[i] # "%" THEN
        Open(t);  Put(t, pattern[i]);  Close(t, s);  INC(i)
      ELSE
        (* %, flags, a width for N, colons for z, and the directive *)
        j := i + 1;  pad := 0X;  upper := FALSE;
        WHILE (j < LEN(pattern)) & ((pattern[j] = "-") OR (pattern[j] = "_") OR (pattern[j] = "0")
            OR (pattern[j] = "^")) DO
          IF pattern[j] = "^" THEN upper := TRUE
          ELSIF pattern[j] = "_" THEN pad := " "
          ELSE pad := pattern[j]
          END;
          INC(j)
        END;
        width := -1;
        WHILE (j < LEN(pattern)) & IsDigit(pattern[j]) & (width < 10) DO
          IF width < 0 THEN width := 0 END;
          width := width * 10 + (ORD(pattern[j]) - ORD("0"));  INC(j)
        END;
        colons := 0;
        WHILE (j < LEN(pattern)) & (pattern[j] = ":") & (colons < 3) DO INC(colons);  INC(j) END;
        IF j < LEN(pattern) THEN c := pattern[j] ELSE c := 0X END;
        known := ((width < 0) OR (c = "N") & (width >= 1) & (width <= 9))
          & ((colons = 0) OR (c = "z") & (colons <= 2));
        e := End(s);  Open(t);
        IF known THEN
          CASE c OF
            "Y": Number(t, odt.year, YearWidth(odt.year), Pad(pad, "0"))
          | "C": Number(t, odt.year DIV 100, 2, Pad(pad, "0"))
          | "y": Number(t, odt.year MOD 100, 2, Pad(pad, "0"))
          | "G":
              Calendar.IsoWeek(odt, weekYear, week);
              Number(t, weekYear, YearWidth(weekYear), Pad(pad, "0"))
          | "g": Calendar.IsoWeek(odt, weekYear, week);  Number(t, weekYear MOD 100, 2, Pad(pad, "0"))
          | "m": Number(t, odt.month, 2, Pad(pad, "0"))
          | "B", "b", "h": MonthName(odt.month, name);  PutName(t, name, c # "B")
          | "d": Number(t, odt.day, 2, Pad(pad, "0"))
          | "e": Number(t, odt.day, 2, Pad(pad, " "))
          | "j": Number(t, Calendar.DayOfYear(odt), 3, Pad(pad, "0"))
          | "H": Number(t, odt.hour, 2, Pad(pad, "0"))
          | "k": Number(t, odt.hour, 2, Pad(pad, " "))
          | "I": Number(t, (odt.hour + 11) MOD 12 + 1, 2, Pad(pad, "0"))
          | "l": Number(t, (odt.hour + 11) MOD 12 + 1, 2, Pad(pad, " "))
          | "M": Number(t, odt.minute, 2, Pad(pad, "0"))
          | "S": Number(t, odt.second, 2, Pad(pad, "0"))
          | "p":
              IF odt.hour < 12 THEN Put(t, "A") ELSE Put(t, "P") END;
              Put(t, "M")
          | "P":
              IF odt.hour < 12 THEN Put(t, "a") ELSE Put(t, "p") END;
              Put(t, "m")
          | "N":
              IF width < 0 THEN width := 9 END;
              Open(t);  Digits(t, odt.nanosecond, 9);  t.n := width;  t.s[width] := 0X
          | "A", "a": WeekdayName(Calendar.DayOfWeek(odt), name);  PutName(t, name, c = "a")
          | "u": Number(t, Calendar.DayOfWeek(odt), 1, Pad(pad, "0"))
          | "w": Number(t, Calendar.DayOfWeek(odt) MOD 7, 1, Pad(pad, "0"))
          | "V": Calendar.IsoWeek(odt, weekYear, week);  Number(t, week, 2, Pad(pad, "0"))
          | "U": Number(t, WeekOfYear(odt, Calendar.Sunday), 2, Pad(pad, "0"))
          | "W": Number(t, WeekOfYear(odt, Calendar.Monday), 2, Pad(pad, "0"))
          | "z": PutNumericOffset(t, odt.offset, colons)
          | "Z": Append(abbreviation, s)
          | "s":
              Number(t, Calendar.DayNumber(odt) * 86400 + odt.hour * 3600 + odt.minute * 60
                + odt.second - odt.offset, 1, Pad(pad, "0"))
          | "F": Expand("%Y-%m-%d", odt, abbreviation, s)
          | "T", "X": Expand("%H:%M:%S", odt, abbreviation, s)
          | "R": Expand("%H:%M", odt, abbreviation, s)
          | "D", "x": Expand("%m/%d/%y", odt, abbreviation, s)
          | "c": Expand("%a %b %e %H:%M:%S %Y", odt, abbreviation, s)
          | "n": Put(t, 0AX)
          | "t": Put(t, 09X)
          | "%": Put(t, "%")
          ELSE known := FALSE
          END
        END;
        IF known THEN
          INC(j);  Close(t, s);
          IF upper THEN
            k := e;
            WHILE (k < LEN(s)) & (s[k] # 0X) DO s[k] := Upper(s[k]);  INC(k) END
          END
        ELSE
          (* an unknown directive as it stands, as glibc writes it *)
          IF c # 0X THEN INC(j) END;
          Open(t);
          FOR k := i TO j - 1 DO Put(t, pattern[k]) END;
          Close(t, s)
        END;
        i := j
      END
    END
  END Expand;

  (* odt written by pattern at s's first 0X; abbreviation is what %Z
     writes *)
  PROCEDURE Format*(pattern-: ARRAY OF CHAR; odt: Calendar.OffsetDateTime;
                    abbreviation-: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);
  BEGIN
    ASSERT(Calendar.ValidOffsetDateTime(odt), 23);
    Expand(pattern, odt, abbreviation, s)
  END Format;

  (* t in zone z, as ToLocal gives it, by pattern, with the zone's
     abbreviation for %Z *)
  PROCEDURE FormatIn*(pattern-: ARRAY OF CHAR; t: Instants.Instant; z: TimeZones.Zone;
                      VAR s: ARRAY OF CHAR);
    VAR info: TimeZones.Info; odt: Calendar.OffsetDateTime;
  BEGIN
    z.Lookup(t, info);  Calendar.FromInstant(odt, t, info.offset);
    Format(pattern, odt, info.abbreviation, s)
  END FormatIn;

  PROCEDURE IsBlank(c: CHAR): BOOLEAN;
  BEGIN
    RETURN (c = " ") OR (c >= 09X) & (c <= 0DX)
  END IsBlank;

  PROCEDURE IsLetter(c: CHAR): BOOLEAN;
  BEGIN
    RETURN (Upper(c) >= "A") & (Upper(c) <= "Z")
  END IsLetter;

  (* A number, as Number writes it: at least one digit, after up to
     width - 1 spaces when spaces may pad it, and at most width characters
     in all, the sign among them. A - is taken when low is negative, and
     does not count toward the width when signExtra is set, for %Y and %G.
     -0 is refused, and so is a number outside low..high. *)
  PROCEDURE ReadNumber(s-: ARRAY OF CHAR; VAR i: LONGINT; width: INTEGER; spaces, signExtra: BOOLEAN;
                       low, high: LONGINT; VAR x: LONGINT): BOOLEAN;
    VAR k, n: INTEGER; negative, ok: BOOLEAN;
  BEGIN
    k := 0;
    IF spaces THEN
      WHILE (k < width - 1) & (At(s, i) = " ") DO INC(k);  INC(i) END
    END;
    negative := (low < 0) & Skip(s, i, "-");
    IF negative & ~signExtra THEN INC(k) END;
    n := 0;  x := 0;
    WHILE (n < width - k) & IsDigit(At(s, i)) DO
      x := x * 10 + (ORD(At(s, i)) - ORD("0"));  INC(n);  INC(i)
    END;
    ok := n > 0;
    IF negative THEN ok := ok & (x # 0);  x := -x END;
    RETURN ok & (x >= low) & (x <= high)
  END ReadNumber;

  (* a number with no sign, or whose sign counts toward width *)
  PROCEDURE ReadIn(s-: ARRAY OF CHAR; VAR i: LONGINT; width: INTEGER; spaces: BOOLEAN;
                   low, high: LONGINT; VAR x: LONGINT): BOOLEAN;
  BEGIN
    RETURN ReadNumber(s, i, width, spaces, FALSE, low, high, x)
  END ReadIn;

  (* name in either case, in full or in its first three letters, the full
     name first *)
  PROCEDURE ReadName(s-: ARRAY OF CHAR; VAR i: LONGINT; name-: ARRAY OF CHAR): BOOLEAN;
    VAR k: LONGINT; ok: BOOLEAN;
  BEGIN
    k := 0;
    WHILE (name[k] # 0X) & (Upper(At(s, i + k)) = Upper(name[k])) DO INC(k) END;
    ok := (name[k] = 0X) OR (k >= 3);
    IF name[k] = 0X THEN INC(i, k) ELSIF k >= 3 THEN INC(i, 3) END;
    RETURN ok
  END ReadName;

  (* +hh, +hhmm or +hhmmss, or +hh:mm or +hh:mm:ss, or the same with -, up
     to 25:59:59; colons decides between the two forms *)
  PROCEDURE ReadNumericOffset(s-: ARRAY OF CHAR; VAR i: LONGINT; colons: BOOLEAN;
                              VAR offset: LONGINT): BOOLEAN;
    VAR ok, negative, colon: BOOLEAN; hours, minutes, seconds: LONGINT;
  BEGIN
    negative := At(s, i) = "-";
    ok := (Skip(s, i, "+") OR Skip(s, i, "-")) & Fixed(s, i, 2, hours);
    minutes := 0;  seconds := 0;
    colon := colons & (At(s, i) = ":") & IsDigit(At(s, i + 1));
    IF ok & (colon OR ~colons & IsDigit(At(s, i))) THEN
      IF colon THEN INC(i) END;
      ok := Fixed(s, i, 2, minutes);
      IF ok & (colon & (At(s, i) = ":") & IsDigit(At(s, i + 1)) OR ~colon & IsDigit(At(s, i))) THEN
        IF colon THEN INC(i) END;
        ok := Fixed(s, i, 2, seconds)
      END
    END;
    ok := ok & (hours <= 25) & (minutes <= 59) & (seconds <= 59);
    offset := hours * 3600 + minutes * 60 + seconds;
    IF negative THEN offset := -offset END;
    RETURN ok
  END ReadNumericOffset;

  (* Z or z, or a numeric offset with or without colons (Q21) *)
  PROCEDURE ReadZoneOffset(s-: ARRAY OF CHAR; VAR i: LONGINT; VAR offset: LONGINT): BOOLEAN;
    VAR ok: BOOLEAN; j: LONGINT;
  BEGIN
    IF Skip(s, i, "Z") OR Skip(s, i, "z") THEN ok := TRUE;  offset := 0
    ELSE
      j := i;
      ok := ReadNumericOffset(s, i, FALSE, offset);
      IF ~ok OR (At(s, i) = ":") THEN i := j;  ok := ReadNumericOffset(s, i, TRUE, offset) END
    END;
    RETURN ok
  END ReadZoneOffset;

  (* An abbreviation, as %Z writes it: letters, or a sign and digits, at
     most 15 of them. Only a name with one meaning gives an offset: UTC,
     UT, GMT or Z gives 0, a numeric one its own (Q19). *)
  PROCEDURE ReadAbbreviation(s-: ARRAY OF CHAR; VAR i: LONGINT; VAR offset: LONGINT;
                             VAR known: BOOLEAN): BOOLEAN;
    CONST longest = 15;
    VAR ok: BOOLEAN; n: LONGINT; name: ARRAY longest + 1 OF CHAR;
  BEGIN
    IF IsLetter(At(s, i)) THEN
      n := 0;
      WHILE IsLetter(At(s, i)) & (n < longest) DO name[n] := Upper(At(s, i));  INC(n);  INC(i) END;
      name[n] := 0X;
      ok := ~IsLetter(At(s, i));
      known := (name = "UTC") OR (name = "UT") OR (name = "GMT") OR (name = "Z");
      offset := 0
    ELSE
      ok := ReadNumericOffset(s, i, FALSE, offset);  known := TRUE
    END;
    RETURN ok
  END ReadAbbreviation;

  (* offset into f, which must agree with any offset the text gave before *)
  PROCEDURE GiveOffset(VAR f: Fields; offset: LONGINT): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN
    ok := ~(offsetGiven IN f.given) OR (f.offset = offset);
    f.offset := offset;  INCL(f.given, offsetGiven);
    RETURN ok
  END GiveOffset;

  (* %s: POSIX seconds, which must name an instant *)
  PROCEDURE ReadSeconds(s-: ARRAY OF CHAR; VAR i: LONGINT; VAR seconds: HUGEINT): BOOLEAN;
    VAR ok, negative: BOOLEAN;
  BEGIN
    negative := Skip(s, i, "-");
    ok := Negated(s, i, -MAX(HUGEINT), seconds);
    IF ~negative THEN seconds := -seconds END;
    RETURN ok & (seconds >= Instants.earliest.seconds) & (seconds <= Instants.latest.seconds)
  END ReadSeconds;

  (* s read from i by pattern into f, which settles nothing yet *)
  PROCEDURE Match(pattern-: ARRAY OF CHAR; VAR f: Fields; s-: ARRAY OF CHAR;
                  VAR i: LONGINT): BOOLEAN;
    VAR
      ok, spaces, known: BOOLEAN; j, x, places, offset: LONGINT; c, pad: CHAR; width, colons: INTEGER;
      name: Name;
  BEGIN
    ok := TRUE;  j := 0;
    WHILE ok & (j < LEN(pattern)) & (pattern[j] # 0X) DO
      c := pattern[j];
      IF IsBlank(c) THEN
        WHILE IsBlank(At(s, i)) DO INC(i) END;  INC(j)
      ELSIF c # "%" THEN
        ok := Skip(s, i, c);  INC(j)
      ELSE
        INC(j);  pad := 0X;
        WHILE (j < LEN(pattern)) & ((pattern[j] = "-") OR (pattern[j] = "_") OR (pattern[j] = "0")
            OR (pattern[j] = "^")) DO
          IF pattern[j] = "_" THEN pad := " " ELSIF pattern[j] # "^" THEN pad := pattern[j] END;
          INC(j)
        END;
        width := -1;
        WHILE (j < LEN(pattern)) & IsDigit(pattern[j]) & (width < 10) DO
          IF width < 0 THEN width := 0 END;
          width := width * 10 + (ORD(pattern[j]) - ORD("0"));  INC(j)
        END;
        colons := 0;
        WHILE (j < LEN(pattern)) & (pattern[j] = ":") & (colons < 3) DO INC(colons);  INC(j) END;
        IF j < LEN(pattern) THEN c := pattern[j] ELSE c := 0X END;
        INC(j);
        ok := ((width < 0) OR (c = "N") & (width >= 1) & (width <= 9))
          & ((colons = 0) OR (c = "z") & (colons <= 2));
        (* the numbers Format pads with spaces may start with them *)
        spaces := (pad = " ") OR (pad = 0X) & ((c = "e") OR (c = "k") OR (c = "l"));
        IF ok THEN
          CASE c OF
            "Y":
              ok := ReadNumber(s, i, 4, spaces, TRUE, Calendar.minYear, Calendar.maxYear, f.year);
              INCL(f.given, yearGiven)
          | "C":
              (* -100, for -9999..-9901, is too wide to read *)
              ok := ReadIn(s, i, 2, spaces, -99, 99, f.century);
              INCL(f.given, centuryGiven)
          | "y": ok := ReadIn(s, i, 2, spaces, 0, 99, f.shortYear);  INCL(f.given, shortYearGiven)
          | "G":
              ok := ReadNumber(s, i, 4, spaces, TRUE, Calendar.minYear, Calendar.maxYear, f.weekYear);
              INCL(f.given, weekYearGiven)
          | "g":
              ok := ReadIn(s, i, 2, spaces, 0, 99, f.shortWeekYear);
              INCL(f.given, shortWeekYearGiven)
          | "m": ok := ReadIn(s, i, 2, spaces, 1, 12, f.month);  INCL(f.given, monthGiven)
          | "B", "b", "h":
              x := 1;
              REPEAT MonthName(x, name);  ok := ReadName(s, i, name);  INC(x) UNTIL ok OR (x > 12);
              f.month := x - 1;  INCL(f.given, monthGiven)
          | "d", "e": ok := ReadIn(s, i, 2, spaces, 1, 31, f.day);  INCL(f.given, dayGiven)
          | "j": ok := ReadIn(s, i, 3, spaces, 1, 366, f.yearDay);  INCL(f.given, yearDayGiven)
          | "H", "k": ok := ReadIn(s, i, 2, spaces, 0, 23, f.hour);  INCL(f.given, hourGiven)
          | "I", "l": ok := ReadIn(s, i, 2, spaces, 1, 12, f.hour12);  INCL(f.given, hour12Given)
          | "M": ok := ReadIn(s, i, 2, spaces, 0, 59, f.minute);  INCL(f.given, minuteGiven)
          | "S": ok := ReadIn(s, i, 2, spaces, 0, 60, f.second);  INCL(f.given, secondGiven)
          | "p", "P":
              IF ReadName(s, i, "AM") THEN f.pm := FALSE
              ELSIF ReadName(s, i, "PM") THEN f.pm := TRUE
              ELSE ok := FALSE
              END;
              INCL(f.given, pmGiven)
          | "N":
              IF width < 0 THEN width := 9 END;
              places := 0;  f.nanosecond := 0;
              WHILE (places < width) & IsDigit(At(s, i)) DO
                f.nanosecond := f.nanosecond * 10 + (ORD(At(s, i)) - ORD("0"));  INC(places);  INC(i)
              END;
              ok := places > 0;
              WHILE places < 9 DO f.nanosecond := f.nanosecond * 10;  INC(places) END;
              INCL(f.given, fractionGiven)
          | "A", "a":
              x := 1;
              REPEAT WeekdayName(x, name);  ok := ReadName(s, i, name);  INC(x) UNTIL ok OR (x > 7);
              f.weekday := x - 1;  INCL(f.given, weekdayGiven)
          | "u": ok := ReadIn(s, i, 1, spaces, 1, 7, f.weekday);  INCL(f.given, weekdayGiven)
          | "w":
              ok := ReadIn(s, i, 1, spaces, 0, 6, f.weekday);
              IF f.weekday = 0 THEN f.weekday := Calendar.Sunday END;
              INCL(f.given, weekdayGiven)
          | "V": ok := ReadIn(s, i, 2, spaces, 1, 53, f.week);  INCL(f.given, weekGiven)
          | "U": ok := ReadIn(s, i, 2, spaces, 0, 53, f.sundayWeek);  INCL(f.given, sundayWeekGiven)
          | "W": ok := ReadIn(s, i, 2, spaces, 0, 53, f.mondayWeek);  INCL(f.given, mondayWeekGiven)
          | "z": ok := ReadZoneOffset(s, i, offset) & GiveOffset(f, offset)
          | "Z":
              ok := ReadAbbreviation(s, i, offset, known);
              IF ok & known THEN ok := GiveOffset(f, offset) END
          | "s": ok := ReadSeconds(s, i, f.seconds);  INCL(f.given, secondsGiven)
          | "F": ok := Match("%Y-%m-%d", f, s, i)
          | "T", "X": ok := Match("%H:%M:%S", f, s, i)
          | "R": ok := Match("%H:%M", f, s, i)
          | "D", "x": ok := Match("%m/%d/%y", f, s, i)
          | "c": ok := Match("%a %b %e %H:%M:%S %Y", f, s, i)
          | "n", "t": WHILE IsBlank(At(s, i)) DO INC(i) END
          | "%": ok := Skip(s, i, "%")
          ELSE ok := FALSE
          END
        END
      END
    END;
    RETURN ok
  END Match;

  (* a year of %y or %g: after %C's century, or else by POSIX's pivot *)
  PROCEDURE Expanded(f-: Fields; short: LONGINT): LONGINT;
    VAR year: LONGINT;
  BEGIN
    IF centuryGiven IN f.given THEN year := f.century * 100 + short
    ELSIF short >= 69 THEN year := 1900 + short
    ELSE year := 2000 + short
    END;
    RETURN year
  END Expanded;

  PROCEDURE InYears(year: LONGINT): BOOLEAN;
  BEGIN
    RETURN (year >= Calendar.minYear) & (year <= Calendar.maxYear)
  END InYears;

  (* the day number of the Monday that starts ISO week 1 of weekYear, the
     week that holds January 4 *)
  PROCEDURE WeekOne(weekYear: LONGINT): HUGEINT;
    VAR d: Calendar.Date;
  BEGIN
    d.year := weekYear;  d.month := 1;  d.day := 4;
    RETURN Calendar.DayNumber(d) - (Calendar.DayOfWeek(d) - 1)
  END WeekOne;

  (* The date-time that f gives, with every field not given defaulted to
     2000-01-01T00:00:00 at offset 0 (Q20). A field that the date settles,
     such as a day of the week, is checked only when the text gives the
     date in full, with its year. *)
  PROCEDURE Settle(VAR f: Fields; VAR r: Calendar.OffsetDateTime): BOOLEAN;
    VAR
      ok, yearKnown, weekYearKnown, full: BOOLEAN;
      year, weekYear, weekday, isoYear, isoWeek, hour: LONGINT;
      d: Calendar.Date; t: Instants.Instant; settled: SET;
  BEGIN
    IF ~(offsetGiven IN f.given) THEN f.offset := 0 END;
    IF ~(fractionGiven IN f.given) THEN f.nanosecond := 0 END;
    IF secondsGiven IN f.given THEN
      (* %s names the instant, whatever else the text says *)
      Instants.FromUnix(t, f.seconds, f.nanosecond);
      ok := Calendar.CheckedFromInstant(r, t, f.offset);
      f.given := f.given + {yearGiven .. secondGiven}
    ELSE
      yearKnown := TRUE;
      IF yearGiven IN f.given THEN year := f.year
      ELSIF shortYearGiven IN f.given THEN year := Expanded(f, f.shortYear)
      ELSIF centuryGiven IN f.given THEN year := f.century * 100
      ELSE year := 2000;  yearKnown := FALSE
      END;
      weekYearKnown := TRUE;
      IF weekYearGiven IN f.given THEN weekYear := f.weekYear
      ELSIF shortWeekYearGiven IN f.given THEN weekYear := Expanded(f, f.shortWeekYear)
      ELSE weekYear := 2000;  weekYearKnown := FALSE
      END;
      IF ~(monthGiven IN f.given) THEN f.month := 1 END;
      IF ~(dayGiven IN f.given) THEN f.day := 1 END;
      ok := InYears(year) & InYears(weekYear);
      IF weekYearKnown & (weekGiven IN f.given) THEN
        (* an ISO week date, on its Monday if the text gives no weekday *)
        IF weekdayGiven IN f.given THEN weekday := f.weekday ELSE weekday := Calendar.Monday END;
        ok := ok & Calendar.FromDayNumber(d, WeekOne(weekYear) + (f.week - 1) * 7 + weekday - 1);
        IF ~yearKnown THEN year := d.year END;
        settled := {yearGiven .. dayGiven};  full := TRUE
      ELSIF yearDayGiven IN f.given THEN
        ok := ok & (f.yearDay <= Calendar.DaysInYear(year)) & Calendar.SetDate(d, year, 1, 1)
          & Calendar.FromDayNumber(d, Calendar.DayNumber(d) + f.yearDay - 1);
        settled := {monthGiven, dayGiven};  full := yearKnown
      ELSE
        ok := ok & Calendar.SetDate(d, year, f.month, f.day);
        settled := {};
        full := yearKnown & (monthGiven IN f.given) & (dayGiven IN f.given)
      END;
      IF yearKnown THEN INCL(f.given, yearGiven) END;
      (* what the text gives must agree with the date it settled *)
      ok := ok & (d.year = year)
        & (~(monthGiven IN f.given) OR (d.month = f.month))
        & (~(dayGiven IN f.given) OR (d.day = f.day));
      f.given := f.given + settled;
      IF ok & full THEN
        Calendar.IsoWeek(d, isoYear, isoWeek);
        weekday := Calendar.DayOfWeek(d);
        ok := (~(weekdayGiven IN f.given) OR (weekday = f.weekday))
          & (~weekYearKnown OR (isoYear = weekYear))
          & (~(weekGiven IN f.given) OR (isoWeek = f.week))
          & (~(sundayWeekGiven IN f.given) OR (WeekOfYear(d, Calendar.Sunday) = f.sundayWeek))
          & (~(mondayWeekGiven IN f.given) OR (WeekOfYear(d, Calendar.Monday) = f.mondayWeek))
      END;
      IF hour12Given IN f.given THEN
        hour := f.hour12 MOD 12;
        IF f.pm THEN INC(hour, 12) END;
        ok := ok & (~(hourGiven IN f.given) OR (f.hour = hour));
        f.hour := hour;  INCL(f.given, hourGiven)
      END;
      IF ~(hourGiven IN f.given) THEN f.hour := 0 END;
      IF ~(minuteGiven IN f.given) THEN f.minute := 0 END;
      IF ~(secondGiven IN f.given) THEN f.second := 0 END;
      r.year := d.year;  r.month := d.month;  r.day := d.day;
      r.hour := f.hour;  r.minute := f.minute;  r.second := f.second;
      r.nanosecond := f.nanosecond;  r.offset := f.offset;
      IF f.second = 60 THEN
        (* only at a leap second, which needs the offset to place it *)
        r.second := 59;
        ok := ok & (offsetGiven IN f.given) & Calendar.ValidOffsetDateTime(r) & LeapSecond(r)
      ELSE
        ok := ok & Calendar.ValidOffsetDateTime(r)
      END
    END;
    RETURN ok
  END Settle;

  (* s read from pos by pattern: odt holds what the text gives and the
     defaults of Settle, and given tells which of odt's fields the text
     gave, and whether it gave a weekday *)
  PROCEDURE Parse*(pattern-: ARRAY OF CHAR; VAR odt: Calendar.OffsetDateTime; VAR given: SET;
                   s-: ARRAY OF CHAR; VAR pos: LONGINT): BOOLEAN;
    VAR ok: BOOLEAN; i: LONGINT; f: Fields; r: Calendar.OffsetDateTime;
  BEGIN
    f.given := {};  f.pm := FALSE;
    f.year := 0;  f.month := 0;  f.day := 0;  f.hour := 0;  f.minute := 0;  f.second := 0;
    f.nanosecond := 0;  f.offset := 0;  f.century := 0;  f.shortYear := 0;  f.weekYear := 0;
    f.shortWeekYear := 0;  f.week := 0;  f.weekday := 0;  f.yearDay := 0;  f.hour12 := 0;
    f.sundayWeek := 0;  f.mondayWeek := 0;  f.seconds := 0;
    i := pos;
    ok := Within(s, pos) & Match(pattern, f, s, i) & Ends(s, i) & Settle(f, r);
    IF ok THEN
      odt.year := r.year;  odt.month := r.month;  odt.day := r.day;
      odt.hour := r.hour;  odt.minute := r.minute;  odt.second := r.second;
      odt.nanosecond := r.nanosecond;  odt.offset := r.offset;
      given := f.given * {yearGiven .. weekdayGiven};  pos := i
    END;
    RETURN ok
  END Parse;

END TimeStrings.
