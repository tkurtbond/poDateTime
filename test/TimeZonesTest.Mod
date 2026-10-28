MODULE TimeZonesTest;

  (* Tests of TimeZones: lookups and local times in the TZif files of
     test/data/zoneinfo/, fat and slim, by path, by name and as the
     process's local zone, against Python's zoneinfo and glibc
     (test/data/ZonesData.Mod); POSIX rules against glibc, and before
     1970, where glibc uses none, by the calendar's 400-year cycle; files
     and rules that must be refused; and utc, Fixed, Now and Today.

     The makefile sets TZDIR to test/data/zoneinfo/slim, so that Named
     reads the slim files, and TZ to the fat America/New_York, so that
     the C library reads it for Local. *)

  IMPORT C := Calendar, I := Instants, TZ := TimeZones, Z := ZonesData, T := TimeTests;

  CONST
    files = "test/data/zoneinfo/";
    cycle = 146097 * 86400;   (* seconds in 400 Gregorian years *)

  VAR
    s: ARRAY 256 OF CHAR;
    current: ARRAY 64 OF CHAR;
    fat, slim, named, rule: TZ.Zone;
    bad: LONGINT;

  PROCEDURE Concat(a, b: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);
    VAR i, n: LONGINT;
  BEGIN
    COPY(a, s);  n := 0;
    WHILE s[n] # 0X DO INC(n) END;
    i := 0;
    WHILE (b[i] # 0X) & (n < LEN(s) - 1) DO s[n] := b[i];  INC(n);  INC(i) END;
    s[n] := 0X
  END Concat;

  PROCEDURE Open(form, zone: ARRAY OF CHAR): TZ.Zone;
    VAR z: TZ.Zone; path: ARRAY 256 OF CHAR;
  BEGIN
    Concat(files, form, path);  Concat(path, "/", path);  Concat(path, zone, path);
    ASSERT(TZ.FromFile(path, z));
    RETURN z
  END Open;

  PROCEDURE SetDateTime(VAR dt: C.DateTime; year, month, day, hour, minute, second: LONGINT);
  BEGIN
    ASSERT(C.SetDateTime(dt, year, month, day, hour, minute, second, 0))
  END SetDateTime;

  PROCEDURE At(seconds: HUGEINT; VAR t: I.Instant);
  BEGIN
    I.FromUnix(t, seconds, 0)
  END At;

  PROCEDURE Has(label: ARRAY OF CHAR; z: TZ.Zone; seconds: HUGEINT; offset: LONGINT; isDst: BOOLEAN;
                abbreviation: ARRAY OF CHAR);
    VAR t: I.Instant; info: TZ.Info;
  BEGIN
    At(seconds, t);  z.Lookup(t, info);
    T.Int(label, info.offset, offset);
    T.True(label, info.isDst = isDst);
    T.Str(label, info.abbreviation, abbreviation)
  END Has;

  (* a check of a table's row, counted as one, and told with the row's
     seconds and the offsets got and expected when it fails *)
  PROCEDURE Matches(label: ARRAY OF CHAR; z: TZ.Zone; seconds: HUGEINT; offset: LONGINT; isDst: BOOLEAN;
                    abbreviation: ARRAY OF CHAR);
    VAR t: I.Instant; info: TZ.Info;
  BEGIN
    At(seconds, t);  z.Lookup(t, info);
    IF (info.offset # offset) OR (info.isDst # isDst) OR (info.abbreviation # abbreviation) THEN
      INC(bad);  T.Failed(label, seconds, info.offset, offset);  T.Str(label, info.abbreviation, abbreviation)
    ELSE T.Count(1)
    END
  END Matches;

  (* the instant t of every local time comes back from that local time
     with earlier or with later *)
  PROCEDURE Returns(label: ARRAY OF CHAR; z: TZ.Zone; seconds: HUGEINT);
    VAR t, u, v: I.Instant; odt: C.OffsetDateTime;
  BEGIN
    At(seconds, t);  TZ.ToLocal(z, t, odt);
    IF ~TZ.ToInstant(z, odt, TZ.earlier, u) OR ~TZ.ToInstant(z, odt, TZ.later, v)
      OR ~I.Equal(t, u) & ~I.Equal(t, v) THEN
      INC(bad);  T.Failed(label, seconds, u.seconds, v.seconds)
    ELSE T.Count(1)
    END
  END Returns;

  PROCEDURE Switch(zone: ARRAY OF CHAR);
  BEGIN
    IF current # zone THEN
      COPY(zone, current);
      fat := Open("fat", zone);  slim := Open("slim", zone);
      ASSERT(TZ.Named(zone, named))
    END
  END Switch;

  PROCEDURE LookupRow(zone: ARRAY OF CHAR; seconds: HUGEINT; offset: LONGINT; isDst: BOOLEAN;
                      abbreviation: ARRAY OF CHAR);
  BEGIN
    Switch(zone);
    Matches("Lookup fat", fat, seconds, offset, isDst, abbreviation);
    Matches("Lookup slim", slim, seconds, offset, isDst, abbreviation);
    Matches("Lookup Named", named, seconds, offset, isDst, abbreviation);
    IF zone = "America/New_York" THEN
      Matches("Lookup Local", TZ.Local(), seconds, offset, isDst, abbreviation);
      Returns("Returns Local", TZ.Local(), seconds)
    END;
    Returns("Returns fat", fat, seconds);
    Returns("Returns slim", slim, seconds)
  END LookupRow;

  PROCEDURE Reads(label: ARRAY OF CHAR; z: TZ.Zone; dt: C.DateTime; choice: INTEGER; ok: BOOLEAN;
                  seconds: HUGEINT);
    VAR t: I.Instant; got: BOOLEAN;
  BEGIN
    got := TZ.ToInstant(z, dt, choice, t);
    IF (got # ok) OR ok & ((t.seconds # seconds) OR (t.nanosecond # 0)) THEN
      INC(bad);  T.Failed(label, seconds, t.seconds, choice)
    ELSE T.Count(1)
    END
  END Reads;

  PROCEDURE LocalRow(zone: ARRAY OF CHAR; year, month, day, hour, minute, second, kind: LONGINT;
                     earlier, later: HUGEINT);
    VAR dt: C.DateTime;

    PROCEDURE In(label: ARRAY OF CHAR; z: TZ.Zone);
    BEGIN
      Reads(label, z, dt, TZ.earlier, TRUE, earlier);
      Reads(label, z, dt, TZ.later, TRUE, later);
      Reads(label, z, dt, TZ.strict, kind = Z.once, earlier)
    END In;

  BEGIN
    Switch(zone);
    SetDateTime(dt, year, month, day, hour, minute, second);
    In("ToInstant fat", fat);  In("ToInstant slim", slim);
    IF zone = "America/New_York" THEN In("ToInstant Local", TZ.Local()) END
  END LocalRow;

  PROCEDURE RuleRow(text: ARRAY OF CHAR; seconds: HUGEINT; offset: LONGINT; isDst: BOOLEAN;
                    abbreviation: ARRAY OF CHAR);
    VAR earlier: HUGEINT; label: ARRAY 64 OF CHAR;
  BEGIN
    IF current # text THEN
      COPY(text, current);
      ASSERT(TZ.Posix(text, rule));
      rule.GetName(s);  T.Str("Posix name", s, text)
    END;
    Concat("Rule ", text, label);
    Matches(label, rule, seconds, offset, isDst, abbreviation);
    Concat("Returns rule ", text, label);
    Returns(label, rule, seconds);
    Concat("Rule 400 years before ", text, label);
    earlier := seconds - cycle;
    WHILE earlier > I.earliest.seconds DO
      Matches(label, rule, earlier, offset, isDst, abbreviation);
      earlier := earlier - 4 * cycle
    END
  END RuleRow;

  PROCEDURE Tables;
  BEGIN
    bad := 0;  current := "";
    Z.EachLookup(LookupRow);  Z.EachLocal(LocalRow);
    current := "";
    Z.EachRule(RuleRow);
    T.True("tables", bad = 0)
  END Tables;

  PROCEDURE FixedZones;
    VAR z: TZ.Zone;

    PROCEDURE Named(label: ARRAY OF CHAR; offset: LONGINT; name, abbreviation: ARRAY OF CHAR);
      VAR z: TZ.Zone;
    BEGIN
      z := TZ.Fixed(offset);
      z.GetName(s);  T.Str(label, s, name);
      Has(label, z, 0, offset, FALSE, abbreviation);
      Has(label, z, I.latest.seconds, offset, FALSE, abbreviation)
    END Named;

  BEGIN
    TZ.utc.GetName(s);  T.Str("utc name", s, "UTC");
    Has("utc", TZ.utc, 1793197506, 0, FALSE, "UTC");
    Has("utc earliest", TZ.utc, I.earliest.seconds, 0, FALSE, "UTC");
    T.True("Fixed(0) is utc", TZ.Fixed(0) = TZ.utc);
    Named("Fixed India", 19800, "+05:30", "+0530");
    Named("Fixed Newfoundland", -12600, "-03:30", "-0330");
    Named("Fixed hours", 3600, "+01:00", "+01");
    Named("Fixed seconds", -1521, "-00:25:21", "-002521");
    Named("Fixed largest", 93599, "+25:59:59", "+255959");
    Named("Fixed smallest", -93599, "-25:59:59", "-255959");
    T.True("Fixed too large", TZ.Fixed(93600) = NIL);
    T.True("Fixed too small", TZ.Fixed(-93600) = NIL);
    z := TZ.Fixed(3600);
    T.True("Fixed new each time", z # TZ.Fixed(3600))
  END FixedZones;

  PROCEDURE NoRule(text: ARRAY OF CHAR);
    VAR z: TZ.Zone;
  BEGIN
    z := TZ.utc;
    IF TZ.Posix(text, z) OR (z # TZ.utc) THEN Concat("Posix refuses ", text, s);  T.True(s, FALSE)
    ELSE T.Count(1)
    END
  END NoRule;

  PROCEDURE Rules;
    VAR z: TZ.Zone;
  BEGIN
    ASSERT(TZ.Posix("EST5", z));
    Has("Posix no DST", z, 1793197506, -18000, FALSE, "EST");
    ASSERT(TZ.Posix("EST+5EDT+4:00:00,M3.2.0/2:00:00,M11.1.0/2", z));
    Has("Posix signs", z, 1783000000, -14400, TRUE, "EDT");
    ASSERT(TZ.Posix("ABCDEFGHIJKLMNOPQRS5", z));
    Has("Posix long abbreviation cut", z, 0, -18000, FALSE, "ABCDEFGHIJKLMNO");
    ASSERT(TZ.Posix("<+0530>-5:30", z));
    Has("Posix quoted", z, 0, 19800, FALSE, "+0530");
    ASSERT(TZ.Posix("XXX3YYY,M3.2.0/-167,M11.1.0/167", z));
    ASSERT(TZ.Posix("EST24", z));
    (* daylight saving time all year, version 3's extension *)
    ASSERT(TZ.Posix("EST5EDT,0/0,J365/25", z));
    Has("Posix all year", z, 1767225600, -14400, TRUE, "EDT");
    (* where one year's end meets the next's start *)
    Has("Posix all year, New Year", z, 1767243599, -14400, TRUE, "EDT");
    Has("Posix all year, New Year after", z, 1767243600, -14400, TRUE, "EDT");
    Has("Posix all year, earliest", z, I.earliest.seconds, -14400, TRUE, "EDT");
    Has("Posix all year, latest", z, I.latest.seconds, -14400, TRUE, "EDT");
    (* the hours in which the year of UTC is not the year of local time,
       which glibc reads wrongly and the table leaves out *)
    ASSERT(TZ.Posix("XXX3YYY,J365/23,J60/0", z));
    Has("Posix before the year's end", z, 978309000, -10800, FALSE, "XXX");
    Has("Posix at the year's end", z, 978314399, -10800, FALSE, "XXX");
    Has("Posix after the year's end", z, 978314400, -7200, TRUE, "YYY");
    ASSERT(TZ.Posix("XXX3YYY,365/12,59/2", z));
    Has("Posix day 365 of a leap year", z, 978310800, -7200, TRUE, "YYY");
    Has("Posix day 365 of a common year", z, 1009846800, -10800, FALSE, "XXX");
    NoRule("");  NoRule("EST");  NoRule("ES5");  NoRule("5");  NoRule("EST5EDT");
    NoRule("EST5EDT,M3.2.0");  NoRule("EST5EDT,M3.2.0,");  NoRule("EST25");  NoRule("EST5:60");
    NoRule("EST5:5");  NoRule("EST1234");  NoRule("EST5EDT,M13.1.0,M11.1.0");
    NoRule("EST5EDT,M0.1.0,M11.1.0");  NoRule("EST5EDT,M3.6.0,M11.1.0");
    NoRule("EST5EDT,M3.0.0,M11.1.0");  NoRule("EST5EDT,M3.2.7,M11.1.0");
    NoRule("EST5EDT,M3.2,M11.1.0");  NoRule("EST5EDT,J0,J365");  NoRule("EST5EDT,J366,J1");
    NoRule("EST5EDT,366,1");  NoRule("EST5EDT,M3.2.0/168,M11.1.0");  NoRule("EST5EDT25,J1,J2");
    NoRule("<AB>5");  NoRule("<+0530-5:30");  NoRule("<+05 30>-5:30");  NoRule("EST5 ");
    NoRule(" EST5");  NoRule("EST5EDT,M3.2.0,M11.1.0x");  NoRule(":America/New_York");
    NoRule("America/New_York");  NoRule("EST5EDT;M3.2.0,M11.1.0")
  END Rules;

  PROCEDURE NoFile(name: ARRAY OF CHAR);
    VAR z: TZ.Zone; path: ARRAY 256 OF CHAR;
  BEGIN
    Concat(files, "made/", path);  Concat(path, name, path);
    z := TZ.utc;
    IF TZ.FromFile(path, z) OR (z # TZ.utc) THEN Concat("FromFile refuses ", name, s);  T.True(s, FALSE)
    ELSE T.Count(1)
    END
  END NoFile;

  PROCEDURE Files;
    VAR z: TZ.Zone;
  BEGIN
    z := Open("made", "v1");
    Has("v1 DST", z, 994000000, -14400, TRUE, "EDT");
    Has("v1 after", z, 1278000000, -18000, FALSE, "EST");
    Has("v1 before", z, 0, -18000, FALSE, "EST");
    z.GetName(s);  T.Str("FromFile name", s, "test/data/zoneinfo/made/v1");
    z := Open("made", "good");
    Has("footer DST", z, 1278000000, -14400, TRUE, "EDT");
    Has("footer standard", z, 1267000000, -18000, FALSE, "EST");
    Has("last transition", z, 1067148000, -18000, FALSE, "EST");
    Has("before last transition", z, 1067147999, -14400, TRUE, "EDT");
    z := Open("made", "v4");
    Has("v4 summer", z, 1278000000, -14400, TRUE, "EDT");
    Has("v4 winter", z, 1267000000, -14400, TRUE, "EDT");
    z := Open("made", "footer");
    Has("footer alone", z, 0, 19800, FALSE, "+0530");
    z := Open("made", "type0");
    Has("type 0 alone", z, 0, -12600, FALSE, "-0330");
    Has("type 0 latest", z, I.latest.seconds, -12600, FALSE, "-0330");
    (* before the first transition: type 0, which Python does not use *)
    z := Open("fat", "America/New_York");
    Has("before first", z, -2717650801, -17762, FALSE, "LMT");
    Has("earliest", z, I.earliest.seconds, -17762, FALSE, "LMT");
    Has("latest", z, I.latest.seconds, -18000, FALSE, "EST");
    z := Open("slim", "Europe/Dublin");
    Has("Dublin earliest", z, I.earliest.seconds, -1521, FALSE, "LMT");
    NoFile("leap");  NoFile("bad-magic");  NoFile("bad-version");  NoFile("truncated");
    NoFile("no-footer");  NoFile("bad-footer");  NoFile("bad-index");  NoFile("descending");
    NoFile("bad-isdst");  NoFile("bad-abbreviation");  NoFile("bad-offset");
    NoFile("unterminated");  NoFile("no-types");  NoFile("missing");  NoFile("")
  END Files;

  PROCEDURE NoName(name: ARRAY OF CHAR);
    VAR z: TZ.Zone;
  BEGIN
    z := TZ.utc;
    IF TZ.Named(name, z) OR (z # TZ.utc) THEN Concat("Named refuses ", name, s);  T.True(s, FALSE)
    ELSE T.Count(1)
    END
  END NoName;

  PROCEDURE Names;
    VAR z, y: TZ.Zone; long: ARRAY 300 OF CHAR; i: LONGINT;
  BEGIN
    ASSERT(TZ.Named("America/New_York", z));
    z.GetName(s);  T.Str("Named name", s, "America/New_York");
    ASSERT(TZ.Named("America/New_York", y));
    T.True("Named kept", z = y);
    ASSERT(TZ.Named("Europe/London", y));
    T.True("Named another", z # y);
    Has("Named London", y, 1783000000, 3600, TRUE, "BST");
    NoName("");  NoName("/etc/localtime");  NoName("../fat/America/New_York");
    NoName("America/../America/New_York");  NoName("America/./New_York");  NoName(".");
    NoName("America/New York");  NoName("America/New_York ");  NoName("Nowhere/Zone");
    NoName("America");  NoName("America/New_York/");
    FOR i := 0 TO 255 DO long[i] := "a" END;
    long[256] := 0X;  NoName(long);
    (* the system's own database, where only what every release agrees on
       is checked *)
    ASSERT(TZ.FromFile("/usr/share/zoneinfo/America/New_York", z));
    Has("system New York summer", z, 1783000000, -14400, TRUE, "EDT");
    Has("system New York winter", z, 1767225600, -18000, FALSE, "EST");
    ASSERT(TZ.FromFile("/usr/share/zoneinfo/Asia/Kolkata", z));
    Has("system Kolkata", z, 1767225600, 19800, FALSE, "IST")
  END Names;

  PROCEDURE Locals;
    VAR z: TZ.Zone; n, m: LONGINT; suffix: ARRAY 64 OF CHAR;
  BEGIN
    z := TZ.Local();
    T.True("Local kept", z = TZ.Local());
    (* TZ is the path of the fat America/New_York, which differs between
       checkouts *)
    z.GetName(s);  suffix := "test/data/zoneinfo/fat/America/New_York";
    n := 0;  WHILE s[n] # 0X DO INC(n) END;
    m := 0;  WHILE suffix[m] # 0X DO INC(m) END;
    WHILE (m > 0) & (n > 0) & (s[n - 1] = suffix[m - 1]) DO DEC(n);  DEC(m) END;
    T.True("Local name", m = 0);
    Has("Local earliest", z, I.earliest.seconds, -17762, FALSE, "LMT");
    Has("Local latest", z, I.latest.seconds, -18000, FALSE, "EST")
  END Locals;

  PROCEDURE Resolving;
    VAR z: TZ.Zone; dt: C.DateTime; odt: C.OffsetDateTime; t: I.Instant;

    PROCEDURE Gives(label: ARRAY OF CHAR; choice: INTEGER; hour, minute, offset: LONGINT);
    BEGIN
      IF TZ.Resolve(z, dt, choice, odt) THEN
        T.Int(label, odt.year * 10000 + odt.month * 100 + odt.day, 20260000 + dt.month * 100 + dt.day);
        T.Int(label, odt.hour * 100 + odt.minute, hour * 100 + minute);
        T.Int(label, odt.offset, offset)
      ELSE T.True(label, FALSE)
      END
    END Gives;

  BEGIN
    ASSERT(TZ.Named("America/New_York", z));
    At(1793193906, t);  TZ.ToLocal(z, t, odt);
    T.Int("ToLocal", odt.hour * 10000 + odt.minute * 100 + odt.second, 92506);
    T.Int("ToLocal offset", odt.offset, -14400);
    SetDateTime(dt, 2026, 3, 8, 2, 30, 0);
    Gives("Resolve gap earlier", TZ.earlier, 3, 30, -14400);
    Gives("Resolve gap later", TZ.later, 3, 30, -14400);
    T.True("Resolve gap strict", ~TZ.Resolve(z, dt, TZ.strict, odt));
    SetDateTime(dt, 2026, 11, 1, 1, 30, 0);
    Gives("Resolve overlap earlier", TZ.earlier, 1, 30, -14400);
    Gives("Resolve overlap later", TZ.later, 1, 30, -18000);
    T.True("Resolve overlap strict", ~TZ.Resolve(z, dt, TZ.strict, odt));
    SetDateTime(dt, 2026, 10, 28, 9, 25, 6);
    Gives("Resolve once strict", TZ.strict, 9, 25, -14400);
    (* local times whose instants are beyond Instants' range *)
    SetDateTime(dt, -9999, 1, 1, 0, 0, 0);
    T.True("ToInstant before earliest", ~TZ.ToInstant(TZ.Fixed(3600), dt, TZ.earlier, t));
    T.True("ToInstant at earliest", TZ.ToInstant(TZ.utc, dt, TZ.earlier, t)
      & I.Equal(t, I.earliest));
    SetDateTime(dt, 9999, 12, 31, 23, 59, 59);
    T.True("ToInstant after latest", ~TZ.ToInstant(TZ.Fixed(-3600), dt, TZ.earlier, t))
  END Resolving;

  PROCEDURE Clock;
    VAR odt: C.OffsetDateTime; d: C.Date; z: TZ.Zone;
  BEGIN
    TZ.Now(TZ.utc, odt);
    T.True("Now", (odt.year >= 2026) & (odt.year < 2100) & (odt.offset = 0));
    z := TZ.Fixed(50400);
    TZ.Today(z, d);  TZ.Now(z, odt);
    (* unless the day ends between the two *)
    T.True("Today", (d.year = odt.year) & (d.month = odt.month) & (d.day = odt.day)
      OR (odt.hour = 0) & (odt.minute = 0));
    T.Int("Now offset", odt.offset, 50400)
  END Clock;

BEGIN
  T.Start("TimeZones");
  FixedZones;  Rules;  Files;  Names;  Locals;  Resolving;  Clock;  Tables;
  T.Finish
END TimeZonesTest.
