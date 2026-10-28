MODULE TimeZones;

  (* Time zones (design section 8): a zone maps an instant to the offset,
     daylight saving flag and abbreviation in force there. Zones are
     objects. An extension of ZoneDesc needs only Lookup and GetName;
     ToInstant, the way back from a local time, is the same for every
     zone. It tries the offsets in force a day before and a day after the
     local time, as C++ and Python do (design 8.2).

     Five kinds are built in: utc, Fixed, the process's Local, Posix rules
     such as "EST5EDT,M3.2.0,M11.1.0", and TZif files (RFC 8536), by name
     from the system's zoneinfo directory or by path. A zone never changes
     once made, so it may be shared and kept; Named keeps each one it
     reads.

     Abbreviations longer than abbreviationLength - 1 are cut short.
     Before a TZif file's first transition its first type is used, as zdump
     does.

     On VMS the system clock is local time and Local() may be Fixed(0)
     named "VMS"; Clocks.Now is then local time, not UTC (design 8.3).

     ASSERT numbers:
       20  Lookup or GetName of ZoneDesc itself, which is abstract
       21  a choice other than earlier, later or strict *)

  IMPORT Calendar, Instants, TimePlatform, Files;

  CONST
    earlier* = 0;  later* = 1;  strict* = 2;   (* resolving a local time *)
    abbreviationLength* = 16;

    maxOffset = 25 * 3600 + 59 * 60 + 59;
    secondsPerDay = 86400;
    secondsPerCycle = 146097 * secondsPerDay;   (* 400 Gregorian years *)
    maxNameLength = 255;
    (* the largest real TZif file is about 100 kB *)
    maxFileLength = 1048576;
    headerLength = 44;

    (* the kinds of a POSIX rule's day *)
    julian = 0;   (* Jn, 1..365, February 29 never counted *)
    zeroBased = 1;   (* n, 0..365, February 29 counted *)
    monthly = 2;   (* Mm.w.d, the dth day of week w of month m *)

  TYPE
    Info* = RECORD
      offset*: LONGINT;   (* seconds east of UTC *)
      isDst*: BOOLEAN;
      abbreviation*: ARRAY abbreviationLength OF CHAR   (* "EST", "+0530"; may be "" *)
    END;
    Zone* = POINTER TO ZoneDesc;
    ZoneDesc* = RECORD END;   (* abstract *)

    Name = POINTER TO ARRAY OF CHAR;

    FixedZone = POINTER TO FixedZoneDesc;
    FixedZoneDesc = RECORD (ZoneDesc) name: Name;  info: Info END;

    (* when a POSIX rule's daylight saving time starts or ends: a day, and
       a time after that day's local midnight, which may be negative or
       beyond a day (RFC 8536 3.3.1) *)
    Day = RECORD kind, day, month, week, weekday, time: LONGINT END;
    Rule = RECORD
      std, dst: Info;
      hasDst: BOOLEAN;
      start, end: Day
    END;

    PosixZone = POINTER TO PosixZoneDesc;
    PosixZoneDesc = RECORD (ZoneDesc) name: Name;  rule: Rule END;

    Times = POINTER TO ARRAY OF HUGEINT;
    Types = POINTER TO ARRAY OF INTEGER;
    Infos = POINTER TO ARRAY OF Info;
    FileZone = POINTER TO FileZoneDesc;
    FileZoneDesc = RECORD (ZoneDesc)
      name: Name;
      count: LONGINT;   (* of transitions *)
      transitions: Times;   (* POSIX seconds, ascending *)
      types: Types;   (* the type each transition starts *)
      infos: Infos;
      hasRule: BOOLEAN;   (* the footer's, after the last transition *)
      rule: Rule
    END;

    (* the C library's local zone; fallback answers where it cannot *)
    LocalZone = POINTER TO LocalZoneDesc;
    LocalZoneDesc = RECORD (ZoneDesc) name: Name;  fallback: Zone END;

    Buffer = POINTER TO ARRAY OF CHAR;
    Cached = POINTER TO CachedDesc;
    CachedDesc = RECORD name: Name;  zone: Zone;  next: Cached END;

  VAR
    utc-: Zone;
    local: Zone;
    cache: Cached;

  PROCEDURE (z: Zone) Lookup*(t: Instants.Instant; VAR info: Info);
  BEGIN
    HALT(20)
  END Lookup;

  PROCEDURE (z: Zone) GetName*(VAR name: ARRAY OF CHAR);
  BEGIN
    HALT(20)
  END GetName;

  (* Strings and names *)

  PROCEDURE Length(s-: ARRAY OF CHAR): LONGINT;
    VAR n: LONGINT;
  BEGIN
    n := 0;
    WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END;
    RETURN n
  END Length;

  PROCEDURE NewName(s-: ARRAY OF CHAR): Name;
    VAR name: Name; i, n: LONGINT;
  BEGIN
    n := Length(s);
    NEW(name, n + 1);
    FOR i := 0 TO n - 1 DO name[i] := s[i] END;
    name[n] := 0X;
    RETURN name
  END NewName;

  (* info := from, field by field, so that info may be an extension *)
  PROCEDURE CopyInfo(VAR info: Info; from-: Info);
  BEGIN
    info.offset := from.offset;  info.isDst := from.isDst;
    COPY(from.abbreviation, info.abbreviation)
  END CopyInfo;

  PROCEDURE Append(VAR s: ARRAY OF CHAR; VAR n: LONGINT; ch: CHAR);
  BEGIN
    IF n < LEN(s) - 1 THEN s[n] := ch;  INC(n);  s[n] := 0X END
  END Append;

  PROCEDURE AppendTwo(VAR s: ARRAY OF CHAR; VAR n: LONGINT; x: LONGINT);
  BEGIN
    Append(s, n, CHR(ORD("0") + x DIV 10));  Append(s, n, CHR(ORD("0") + x MOD 10))
  END AppendTwo;

  (* Fixed zones *)

  (* "+05:30" as a name, and "+0530" as an abbreviation, as tzdata writes
     one for a zone with no name of its own; seconds only if there are some *)
  PROCEDURE OffsetText(offset: LONGINT; colons: BOOLEAN; VAR s: ARRAY OF CHAR);
    VAR n, a: LONGINT;
  BEGIN
    n := 0;  s[0] := 0X;
    IF offset < 0 THEN Append(s, n, "-");  a := -offset ELSE Append(s, n, "+");  a := offset END;
    AppendTwo(s, n, a DIV 3600);
    IF colons OR (a MOD 3600 # 0) THEN
      IF colons THEN Append(s, n, ":") END;
      AppendTwo(s, n, a DIV 60 MOD 60);
      IF a MOD 60 # 0 THEN
        IF colons THEN Append(s, n, ":") END;
        AppendTwo(s, n, a MOD 60)
      END
    END
  END OffsetText;

  PROCEDURE (z: FixedZone) Lookup*(t: Instants.Instant; VAR info: Info);
  BEGIN
    CopyInfo(info, z.info)
  END Lookup;

  PROCEDURE (z: FixedZone) GetName*(VAR name: ARRAY OF CHAR);
  BEGIN
    COPY(z.name^, name)
  END GetName;

  PROCEDURE NewFixed(offset: LONGINT; name-, abbreviation-: ARRAY OF CHAR): Zone;
    VAR z: FixedZone;
  BEGIN
    NEW(z);  z.name := NewName(name);
    z.info.offset := offset;  z.info.isDst := FALSE;  COPY(abbreviation, z.info.abbreviation);
    RETURN z
  END NewFixed;

  (* utc for 0; else named as "+05:30" and abbreviated as "+0530" *)
  PROCEDURE Fixed*(offset: LONGINT): Zone;
    VAR z: Zone; name: ARRAY 16 OF CHAR; abbreviation: ARRAY abbreviationLength OF CHAR;
  BEGIN
    IF (offset < -maxOffset) OR (offset > maxOffset) THEN z := NIL
    ELSIF offset = 0 THEN z := utc
    ELSE
      OffsetText(offset, TRUE, name);  OffsetText(offset, FALSE, abbreviation);
      z := NewFixed(offset, name, abbreviation)
    END;
    RETURN z
  END Fixed;

  (* POSIX rules *)

  PROCEDURE IsLetter(ch: CHAR): BOOLEAN;
  BEGIN
    RETURN (ch >= "A") & (ch <= "Z") OR (ch >= "a") & (ch <= "z")
  END IsLetter;

  PROCEDURE IsDigit(ch: CHAR): BOOLEAN;
  BEGIN
    RETURN (ch >= "0") & (ch <= "9")
  END IsDigit;

  PROCEDURE At(s-: ARRAY OF CHAR; pos: LONGINT): CHAR;
    VAR ch: CHAR;
  BEGIN
    IF pos < LEN(s) THEN ch := s[pos] ELSE ch := 0X END;
    RETURN ch
  END At;

  (* An abbreviation: three or more letters, or three or more letters,
     digits and signs between < and >. *)
  PROCEDURE ReadAbbreviation(s-: ARRAY OF CHAR; VAR pos: LONGINT; VAR a: ARRAY OF CHAR): BOOLEAN;
    VAR n, count: LONGINT; quoted, ok: BOOLEAN; ch: CHAR;
  BEGIN
    n := 0;  count := 0;  a[0] := 0X;
    quoted := At(s, pos) = "<";
    IF quoted THEN INC(pos) END;
    ch := At(s, pos);
    WHILE IsLetter(ch) OR quoted & (IsDigit(ch) OR (ch = "+") OR (ch = "-")) DO
      Append(a, n, ch);  INC(count);  INC(pos);  ch := At(s, pos)
    END;
    ok := count >= 3;
    IF quoted THEN ok := ok & (ch = ">");  INC(pos) END;
    RETURN ok
  END ReadAbbreviation;

  (* [+-]h[h[h]][:mm[:ss]], at most maxHours hours, as seconds *)
  PROCEDURE ReadClock(s-: ARRAY OF CHAR; VAR pos: LONGINT; maxHours: LONGINT; VAR x: LONGINT): BOOLEAN;
    VAR hours, minutes, seconds, digits: LONGINT; negative, ok: BOOLEAN;

    PROCEDURE Two(VAR v: LONGINT): BOOLEAN;
      VAR ok: BOOLEAN;
    BEGIN
      ok := IsDigit(At(s, pos)) & IsDigit(At(s, pos + 1));
      IF ok THEN
        v := (ORD(s[pos]) - ORD("0")) * 10 + ORD(s[pos + 1]) - ORD("0");  INC(pos, 2);
        ok := v <= 59
      END;
      RETURN ok
    END Two;

  BEGIN
    negative := At(s, pos) = "-";
    IF negative OR (At(s, pos) = "+") THEN INC(pos) END;
    hours := 0;  minutes := 0;  seconds := 0;  digits := 0;
    WHILE IsDigit(At(s, pos)) & (digits < 3) DO
      hours := hours * 10 + ORD(s[pos]) - ORD("0");  INC(pos);  INC(digits)
    END;
    ok := (digits > 0) & (hours <= maxHours);
    IF ok & (At(s, pos) = ":") THEN
      INC(pos);  ok := Two(minutes);
      IF ok & (At(s, pos) = ":") THEN INC(pos);  ok := Two(seconds) END
    END;
    x := hours * 3600 + minutes * 60 + seconds;
    IF negative THEN x := -x END;
    RETURN ok
  END ReadClock;

  PROCEDURE ReadNumber(s-: ARRAY OF CHAR; VAR pos: LONGINT; max: LONGINT; VAR x: LONGINT): BOOLEAN;
    VAR digits: LONGINT;
  BEGIN
    x := 0;  digits := 0;
    WHILE IsDigit(At(s, pos)) & (digits < 3) DO
      x := x * 10 + ORD(s[pos]) - ORD("0");  INC(pos);  INC(digits)
    END;
    RETURN (digits > 0) & (x <= max)
  END ReadNumber;

  (* Jn, n or Mm.w.d, and an optional /time, 02:00 if there is none *)
  PROCEDURE ReadDay(s-: ARRAY OF CHAR; VAR pos: LONGINT; VAR d: Day): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN
    IF At(s, pos) = "J" THEN
      INC(pos);  d.kind := julian;  ok := ReadNumber(s, pos, 365, d.day) & (d.day >= 1)
    ELSIF At(s, pos) = "M" THEN
      INC(pos);  d.kind := monthly;
      ok := ReadNumber(s, pos, 12, d.month) & (d.month >= 1) & (At(s, pos) = ".");
      IF ok THEN INC(pos);  ok := ReadNumber(s, pos, 5, d.week) & (d.week >= 1) & (At(s, pos) = ".") END;
      IF ok THEN INC(pos);  ok := ReadNumber(s, pos, 6, d.weekday) END
    ELSE
      d.kind := zeroBased;  ok := ReadNumber(s, pos, 365, d.day)
    END;
    d.time := 7200;
    IF ok & (At(s, pos) = "/") THEN INC(pos);  ok := ReadClock(s, pos, 167, d.time) END;
    RETURN ok
  END ReadDay;

  (* std offset [dst [offset] ,start[/time],end[/time]], the whole of s *)
  PROCEDURE ReadRule(s-: ARRAY OF CHAR; VAR rule: Rule): BOOLEAN;
    VAR pos, offset: LONGINT; ok: BOOLEAN;
  BEGIN
    pos := 0;
    ok := ReadAbbreviation(s, pos, rule.std.abbreviation) & ReadClock(s, pos, 24, offset);
    rule.std.offset := -offset;  rule.std.isDst := FALSE;
    rule.hasDst := ok & (At(s, pos) # 0X);
    IF rule.hasDst THEN
      ok := ReadAbbreviation(s, pos, rule.dst.abbreviation);
      rule.dst.offset := rule.std.offset + 3600;  rule.dst.isDst := TRUE;
      IF ok & (At(s, pos) # ",") THEN ok := ReadClock(s, pos, 24, offset);  rule.dst.offset := -offset END;
      (* POSIX leaves a rule with no dates to the implementation, and
         glibc's default is America's rule of 2007; refused, as Python does *)
      ok := ok & (At(s, pos) = ",");
      IF ok THEN INC(pos);  ok := ReadDay(s, pos, rule.start) & (At(s, pos) = ",") END;
      IF ok THEN INC(pos);  ok := ReadDay(s, pos, rule.end) END
    END;
    RETURN ok & (At(s, pos) = 0X)
  END ReadRule;

  (* the local seconds since 1970 at which d falls in year; a year just
     beyond Calendar's is found from one 400 years away, which has the
     same days *)
  PROCEDURE DayIn(d: Day; year: LONGINT): HUGEINT;
    VAR date: Calendar.Date; n: HUGEINT; weekday, week: LONGINT; ok: BOOLEAN;
  BEGIN
    IF year < Calendar.minYear THEN RETURN DayIn(d, year + 400) - secondsPerCycle
    ELSIF year > Calendar.maxYear THEN RETURN DayIn(d, year - 400) + secondsPerCycle
    END;
    ok := Calendar.SetDate(date, year, Calendar.January, 1);
    n := Calendar.DayNumber(date);
    IF d.kind = julian THEN
      n := n + d.day - 1;
      IF (d.day >= 60) & Calendar.IsLeapYear(year) THEN INC(n) END
    ELSIF d.kind = zeroBased THEN
      n := n + d.day
    ELSE
      weekday := d.weekday;
      IF weekday = 0 THEN weekday := Calendar.Sunday END;
      week := d.week;
      IF week = 5 THEN week := -1 END;
      ok := Calendar.NthWeekday(date, year, d.month, weekday, week);
      n := Calendar.DayNumber(date)
    END;
    RETURN n * secondsPerDay + d.time
  END DayIn;

  (* The latest start or end of daylight saving time at or before seconds,
     among those of the year around it and the years either side. So a
     rule whose times run past the end of the year, and a rule of daylight
     saving time all year, as "EST5EDT,0/0,J365/25", are both read right:
     there the end of one year is the start of the next, and the start,
     coming later in the list, wins. *)
  PROCEDURE RuleLookup(VAR rule: Rule; seconds: HUGEINT; VAR info: Info);
    VAR date: Calendar.Date; year, y: LONGINT; at, best: HUGEINT; found, dst: BOOLEAN;
  BEGIN
    IF ~rule.hasDst THEN CopyInfo(info, rule.std)
    ELSE
      IF Calendar.FromDayNumber(date, (seconds + rule.std.offset) DIV secondsPerDay) THEN
        year := date.year
      ELSIF seconds < 0 THEN year := Calendar.minYear
      ELSE year := Calendar.maxYear
      END;
      found := FALSE;  dst := FALSE;  best := 0;
      FOR y := year - 1 TO year + 1 DO
        at := DayIn(rule.start, y) - rule.std.offset;
        IF (at <= seconds) & (~found OR (at >= best)) THEN found := TRUE;  best := at;  dst := TRUE END;
        at := DayIn(rule.end, y) - rule.dst.offset;
        IF (at <= seconds) & (~found OR (at >= best)) THEN found := TRUE;  best := at;  dst := FALSE END
      END;
      IF ~found THEN
        (* before the first year's start and end: what holds before
           whichever comes first that year *)
        dst := DayIn(rule.end, year) - rule.dst.offset < DayIn(rule.start, year) - rule.std.offset
      END;
      IF dst THEN CopyInfo(info, rule.dst) ELSE CopyInfo(info, rule.std) END
    END
  END RuleLookup;

  PROCEDURE (z: PosixZone) Lookup*(t: Instants.Instant; VAR info: Info);
  BEGIN
    RuleLookup(z.rule, t.seconds, info)
  END Lookup;

  PROCEDURE (z: PosixZone) GetName*(VAR name: ARRAY OF CHAR);
  BEGIN
    COPY(z.name^, name)
  END GetName;

  (* A POSIX TZ rule, as "EST5EDT,M3.2.0,M11.1.0" or "<+0530>-5:30", with
     RFC 8536's extensions: transition times from -167 to 167 hours, and
     so daylight saving time all year. Its name is the rule. *)
  PROCEDURE Posix*(rule-: ARRAY OF CHAR; VAR z: Zone): BOOLEAN;
    VAR p: PosixZone; ok: BOOLEAN;
  BEGIN
    NEW(p);
    ok := ReadRule(rule, p.rule);
    IF ok THEN p.name := NewName(rule);  z := p END;
    RETURN ok
  END Posix;

  (* TZif files *)

  PROCEDURE (z: FileZone) Lookup*(t: Instants.Instant; VAR info: Info);
    VAR low, high, middle: LONGINT;
  BEGIN
    IF (z.count = 0) & z.hasRule OR (z.count > 0) & (t.seconds > z.transitions[z.count - 1]) & z.hasRule THEN
      RuleLookup(z.rule, t.seconds, info)
    ELSIF (z.count = 0) OR (t.seconds < z.transitions[0]) THEN
      CopyInfo(info, z.infos[0])
    ELSE
      (* the last transition at or before t *)
      low := 0;  high := z.count - 1;
      WHILE low < high DO
        middle := (low + high + 1) DIV 2;
        IF z.transitions[middle] <= t.seconds THEN low := middle ELSE high := middle - 1 END
      END;
      CopyInfo(info, z.infos[z.types[low]])
    END
  END Lookup;

  PROCEDURE (z: FileZone) GetName*(VAR name: ARRAY OF CHAR);
  BEGIN
    COPY(z.name^, name)
  END GetName;

  (* an unsigned big-endian number of size bytes at b[pos] *)
  PROCEDURE Unsigned(b: Buffer; pos, size: LONGINT): HUGEINT;
    VAR x: HUGEINT; i: LONGINT;
  BEGIN
    x := 0;
    FOR i := pos TO pos + size - 1 DO x := x * 256 + ORD(b[i]) END;
    RETURN x
  END Unsigned;

  (* a two's complement big-endian number of 4 or 8 bytes; a negative one
     is read through its complement, so that nothing overflows *)
  PROCEDURE Signed(b: Buffer; pos, size: LONGINT): HUGEINT;
    VAR x: HUGEINT; i: LONGINT;
  BEGIN
    IF ORD(b[pos]) < 128 THEN x := Unsigned(b, pos, size)
    ELSE
      x := 0;
      FOR i := pos TO pos + size - 1 DO x := x * 256 + (255 - ORD(b[i])) END;
      x := -x - 1
    END;
    RETURN x
  END Signed;

  PROCEDURE IsMagic(b: Buffer; pos: LONGINT): BOOLEAN;
  BEGIN
    RETURN (b[pos] = "T") & (b[pos + 1] = "Z") & (b[pos + 2] = "i") & (b[pos + 3] = "f")
  END IsMagic;

  (* The data block after the header at b[pos], with times of size bytes:
     4 for version 1, 8 after. end is where the block ends. FALSE for
     anything RFC 8536 does not allow, and for leap seconds, which
     Instants does not count (design 6.2). *)
  PROCEDURE ReadBlock(b: Buffer; length, pos, size: LONGINT; VAR z: FileZone;
                      VAR end: LONGINT): BOOLEAN;
    VAR utCount, stdCount, leapCount, timeCount, typeCount, charCount, blockLength: HUGEINT;
      i, p, types, chars, k, n, index: LONGINT; offset: HUGEINT; ok: BOOLEAN;
  BEGIN
    ok := (pos + headerLength <= length) & IsMagic(b, pos);
    IF ok THEN
      utCount := Unsigned(b, pos + 20, 4);  stdCount := Unsigned(b, pos + 24, 4);
      leapCount := Unsigned(b, pos + 28, 4);  timeCount := Unsigned(b, pos + 32, 4);
      typeCount := Unsigned(b, pos + 36, 4);  charCount := Unsigned(b, pos + 40, 4);
      blockLength := timeCount * (size + 1) + typeCount * 6 + charCount + leapCount * (size + 4)
        + stdCount + utCount;
      ok := (leapCount = 0) & (typeCount >= 1) & (typeCount <= 256) & (charCount >= 1)
        & ((stdCount = 0) OR (stdCount = typeCount)) & ((utCount = 0) OR (utCount = typeCount))
        & (blockLength <= length - pos - headerLength)
    END;
    IF ok THEN
      z.count := SHORT(timeCount);
      NEW(z.transitions, z.count + 1);  NEW(z.types, z.count + 1);
      NEW(z.infos, SHORT(typeCount));
      p := pos + headerLength;
      types := p + z.count * size + z.count;  chars := types + SHORT(typeCount) * 6;
      i := 0;
      WHILE ok & (i < z.count) DO
        z.transitions[i] := Signed(b, p + i * size, size);
        index := ORD(b[p + z.count * size + i]);
        z.types[i] := SHORT(index);
        ok := (index < typeCount) & ((i = 0) OR (z.transitions[i] > z.transitions[i - 1]));
        INC(i)
      END;
      i := 0;
      WHILE ok & (i < typeCount) DO
        k := types + i * 6;
        offset := Signed(b, k, 4);
        index := ORD(b[k + 5]);
        ok := (offset >= -maxOffset) & (offset <= maxOffset) & (ORD(b[k + 4]) <= 1) & (index < charCount);
        IF ok THEN
          z.infos[i].offset := SHORT(offset);  z.infos[i].isDst := b[k + 4] = 1X;
          (* the abbreviation must end within the characters *)
          k := chars + index;  n := 0;  z.infos[i].abbreviation[0] := 0X;
          WHILE (k < chars + charCount) & (b[k] # 0X) DO
            Append(z.infos[i].abbreviation, n, b[k]);  INC(k)
          END;
          ok := k < chars + charCount
        END;
        INC(i)
      END;
      end := pos + headerLength + SHORT(blockLength)
    END;
    RETURN ok
  END ReadBlock;

  (* RFC 8536 versions 1 to 4, and later ones as 4. A version 2 or later
     file is read from its second, 64-bit block and its footer; the first
     block is only skipped. *)
  PROCEDURE ReadZone(b: Buffer; length: LONGINT; VAR z: FileZone): BOOLEAN;
    VAR end, pos, n, i: LONGINT; footer: Buffer; ok: BOOLEAN;
  BEGIN
    NEW(z);  z.hasRule := FALSE;
    ok := ReadBlock(b, length, 0, 4, z, end);
    IF ok & (b[4] # 0X) THEN
      ok := (b[4] >= "2") & ReadBlock(b, length, end, 8, z, end)
        & (end < length) & (b[end] = 0AX);
      IF ok THEN
        pos := end + 1;  n := 0;
        WHILE (pos + n < length) & (b[pos + n] # 0AX) DO INC(n) END;
        ok := pos + n < length;
        IF ok & (n > 0) THEN
          NEW(footer, n + 1);
          FOR i := 0 TO n - 1 DO footer[i] := b[pos + i] END;
          footer[n] := 0X;
          ok := ReadRule(footer^, z.rule);  z.hasRule := ok
        END
      END
    END;
    RETURN ok
  END ReadZone;

  PROCEDURE Load(path-: ARRAY OF CHAR; VAR z: FileZone): BOOLEAN;
    VAR f: Files.File; r: Files.Rider; b: Buffer; length: LONGINT; ok: BOOLEAN;
  BEGIN
    f := Files.Old(path);
    ok := f # NIL;
    IF ok THEN
      length := Files.Length(f);
      ok := (length >= headerLength) & (length <= maxFileLength);
      IF ok THEN
        NEW(b, length);
        Files.Set(r, f, 0);  Files.ReadBytes(r, b^, length);
        ok := (r.res = 0) & ReadZone(b, length, z)
      END;
      Files.Close(f)
    END;
    RETURN ok
  END Load;

  (* a TZif file by its path, which is its name *)
  PROCEDURE FromFile*(path-: ARRAY OF CHAR; VAR z: Zone): BOOLEAN;
    VAR f: FileZone; ok: BOOLEAN;
  BEGIN
    ok := Load(path, f);
    IF ok THEN f.name := NewName(path);  z := f END;
    RETURN ok
  END FromFile;

  (* A name that cannot reach outside the zoneinfo directory: relative,
     and of the characters tzdata's names use, which leave out ".". A
     name often comes from what a user typed. *)
  PROCEDURE ValidName(name-: ARRAY OF CHAR): BOOLEAN;
    VAR i, n: LONGINT; ch: CHAR; ok: BOOLEAN;
  BEGIN
    n := Length(name);
    ok := (n >= 1) & (n <= maxNameLength) & (name[0] # "/");
    i := 0;
    WHILE ok & (i < n) DO
      ch := name[i];
      ok := IsLetter(ch) OR IsDigit(ch) OR (ch = "/") OR (ch = "_") OR (ch = "+") OR (ch = "-");
      INC(i)
    END;
    RETURN ok
  END ValidName;

  (* "America/New_York", from the zoneinfo directory; each zone read is
     kept, and the same zone is given for the same name *)
  PROCEDURE Named*(name-: ARRAY OF CHAR; VAR z: Zone): BOOLEAN;
    VAR c: Cached; f: FileZone; path: ARRAY 1024 OF CHAR; i, n: LONGINT; ok: BOOLEAN;
  BEGIN
    ok := ValidName(name);
    IF ok THEN
      c := cache;
      WHILE (c # NIL) & (c.name^ # name) DO c := c.next END;
      IF c # NIL THEN z := c.zone
      ELSE
        TimePlatform.ZoneInfoDirectory(path);
        n := Length(path);
        ok := (n > 0) & (n + 1 + Length(name) < LEN(path));
        IF ok THEN
          path[n] := "/";  INC(n);
          FOR i := 0 TO Length(name) DO path[n + i] := name[i] END;
          ok := Load(path, f)
        END;
        IF ok THEN
          f.name := NewName(name);
          NEW(c);  c.name := f.name;  c.zone := f;  c.next := cache;  cache := c;
          z := f
        END
      END
    END;
    RETURN ok
  END Named;

  (* The local zone *)

  (* what answers where the C library cannot: TZ's rule or zone, or
     /etc/localtime, or else UTC *)
  PROCEDURE Fallback(name-: ARRAY OF CHAR): Zone;
    VAR z: Zone;
  BEGIN
    IF ~Posix(name, z) & ~Named(name, z) & ~FromFile("/etc/localtime", z) THEN z := utc END;
    RETURN z
  END Fallback;

  PROCEDURE (z: LocalZone) Lookup*(t: Instants.Instant; VAR info: Info);
  BEGIN
    IF ~TimePlatform.LocalOffset(t.seconds, info.offset, info.isDst, info.abbreviation)
      OR (info.offset < -maxOffset) OR (info.offset > maxOffset) THEN
      IF z.fallback = NIL THEN z.fallback := Fallback(z.name^) END;
      z.fallback.Lookup(t, info)
    END
  END Lookup;

  PROCEDURE (z: LocalZone) GetName*(VAR name: ARRAY OF CHAR);
  BEGIN
    COPY(z.name^, name)
  END GetName;

  (* The process's zone, decided when first asked for (design 8.3). On
     Unix it is the C library's, named by TZ or by /etc/localtime's
     link; on VMS it is the TZ logical name's rule, or else Fixed(0)
     named "VMS". *)
  PROCEDURE Local*(): Zone;
    VAR z: LocalZone; name: ARRAY maxNameLength + 1 OF CHAR;
  BEGIN
    IF local = NIL THEN
      IF TimePlatform.SystemLocal() THEN
        NEW(z);  TimePlatform.LocalZoneName(name);  z.name := NewName(name);  z.fallback := NIL;
        local := z
      ELSIF ~TimePlatform.LocalRule(name) OR ~Posix(name, local) THEN
        local := NewFixed(0, "VMS", "")
      END
    END;
    RETURN local
  END Local;

  (* Between instants and local times *)

  PROCEDURE ToLocal*(z: Zone; t: Instants.Instant; VAR odt: Calendar.OffsetDateTime);
    VAR info: Info;
  BEGIN
    z.Lookup(t, info);
    Calendar.FromInstant(odt, t, info.offset)
  END ToLocal;

  PROCEDURE OffsetAt(z: Zone; seconds: HUGEINT): LONGINT;
    VAR t: Instants.Instant; info: Info;
  BEGIN
    Instants.FromUnix(t, seconds, 0);
    z.Lookup(t, info);
    RETURN info.offset
  END OffsetAt;

  (* The instant of the local time dt in z (design 8.2). It is read with
     the offsets in force a day before and a day after it; an offset that
     gives back itself is right. With two, dt is in an overlap and choice
     picks; with none, dt is in a gap and is read with the offset before
     it, so that 02:30 in a gap of an hour is 03:30 after it. FALSE if
     choice is strict and dt is in either, or if the instant is beyond
     Instants.earliest .. latest. Two transitions less than a day apart
     can hide one another from it, so that an overlap between them is
     read as a single offset; no zone in tzdata has those since 1970. *)
  PROCEDURE ToInstant*(z: Zone; dt: Calendar.DateTime; choice: INTEGER; VAR t: Instants.Instant): BOOLEAN;
    VAR u: Instants.Instant; odt: Calendar.OffsetDateTime; seconds: HUGEINT;
      before, after, offset: LONGINT; first, second, ok: BOOLEAN;
  BEGIN
    ASSERT((choice >= earlier) & (choice <= strict), 21);
    Calendar.ToUTCInstant(dt, u);
    seconds := u.seconds;
    before := OffsetAt(z, seconds - secondsPerDay);
    after := OffsetAt(z, seconds + secondsPerDay);
    first := OffsetAt(z, seconds - before) = before;
    second := (after # before) & (OffsetAt(z, seconds - after) = after);
    ok := TRUE;  offset := before;
    IF first & second THEN
      (* the larger offset gives the earlier instant *)
      ok := choice # strict;
      IF (choice = earlier) # (before > after) THEN offset := after END
    ELSIF second THEN offset := after
    ELSIF ~first THEN ok := choice # strict
    END;
    IF ok THEN
      odt.year := dt.year;  odt.month := dt.month;  odt.day := dt.day;
      odt.hour := dt.hour;  odt.minute := dt.minute;  odt.second := dt.second;
      odt.nanosecond := dt.nanosecond;  odt.offset := offset;
      ok := Calendar.CheckedToInstant(t, odt)
    END;
    RETURN ok
  END ToInstant;

  (* dt as ToInstant reads it, with the offset in force then; in a gap that
     is a later local time than dt *)
  PROCEDURE Resolve*(z: Zone; dt: Calendar.DateTime; choice: INTEGER; VAR odt: Calendar.OffsetDateTime): BOOLEAN;
    VAR t: Instants.Instant; info: Info; ok: BOOLEAN;
  BEGIN
    ok := ToInstant(z, dt, choice, t);
    IF ok THEN
      z.Lookup(t, info);
      ok := Calendar.CheckedFromInstant(odt, t, info.offset)
    END;
    RETURN ok
  END Resolve;

  PROCEDURE Now*(z: Zone; VAR odt: Calendar.OffsetDateTime);
    VAR t: Instants.Instant; seconds: HUGEINT; nanosecond: LONGINT;
  BEGIN
    TimePlatform.WallClock(seconds, nanosecond);
    Instants.FromUnix(t, seconds, nanosecond);
    ToLocal(z, t, odt)
  END Now;

  PROCEDURE Today*(z: Zone; VAR d: Calendar.Date);
    VAR odt: Calendar.OffsetDateTime;
  BEGIN
    Now(z, odt);
    d.year := odt.year;  d.month := odt.month;  d.day := odt.day
  END Today;

BEGIN
  utc := NewFixed(0, "UTC", "UTC");
  local := NIL;  cache := NIL
END TimeZones.
