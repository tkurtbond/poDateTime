MODULE TimeStrings;

  (* Dates, times, durations and periods to and from text in fixed
     formats: ISO 8601's extended format and RFC 3339's profile of it
     (design section 10.1). The patterns of 10.2 come with step 5.

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

  IMPORT Durations, Instants, Calendar;

  CONST
    shortest* = -1;   (* digits: 0, 3, 6 or 9 fractional digits, the fewest that are exact *)

    second = Durations.second;
    (* longer than any text written here: a Period under -OC is 66 *)
    maxText = 96;

  TYPE
    (* text being built, before it is appended to the caller's string *)
    Text = RECORD
      s: ARRAY maxText OF CHAR;
      n: LONGINT
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

  (* A date-time with an offset. A second of 60 is taken only where the
     time in UTC is 23:59:60 on the last day of a month, and is read as
     59.999999999, whatever fraction follows (doc/leap-seconds.md). *)
  PROCEDURE ReadOffsetFields(s-: ARRAY OF CHAR; VAR i: LONGINT; VAR odt: Calendar.OffsetDateTime): BOOLEAN;
    VAR ok: BOOLEAN; t: Instants.Instant; utc: Calendar.DateTime;
  BEGIN
    ok := ReadDateTimeFields(s, i, odt) & ReadOffset(s, i, odt.offset);
    IF ok & (odt.second = 60) THEN
      odt.second := 59;  odt.nanosecond := 0;
      ok := Calendar.CheckedToInstant(t, odt);
      IF ok THEN
        Calendar.FromUTCInstant(utc, t);
        ok := (utc.hour = 23) & (utc.minute = 59) & (utc.second = 59)
          & (utc.day = Calendar.DaysInMonth(utc.year, utc.month));
        odt.nanosecond := second - 1
      END
    END;
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

END TimeStrings.
