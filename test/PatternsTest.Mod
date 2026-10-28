MODULE PatternsTest;

  (* Tests of TimeStrings' patterns (design 10.2): what Format writes,
     against glibc's strftime (test/data/PatternsData.Mod) and against
     strings written by hand for what glibc lacks or writes otherwise
     (Q18, Q21); what Parse reads, with its defaults and checks (Q19, Q20);
     strings it must refuse, leaving its results and pos alone; and round
     trips through Format and Parse over the whole range. *)

  IMPORT C := Calendar, I := Instants, S := TimeStrings, Z := TimeZones, PatternsData,
    T := TimeTests;

  CONST
    trips = 5000;
    Y = S.yearGiven;  Mo = S.monthGiven;  D = S.dayGiven;  H = S.hourGiven;
    Mi = S.minuteGiven;  Se = S.secondGiven;  N = S.fractionGiven;  O = S.offsetGiven;
    W = S.weekdayGiven;

  VAR
    s: ARRAY 256 OF CHAR;
    base: C.OffsetDateTime;
    seed: HUGEINT;
    table, tableBad: LONGINT;

  (* 0 .. n - 1, from a linear congruential generator, which wraps *)
  PROCEDURE Random(n: HUGEINT): HUGEINT;
  BEGIN
    seed := seed * 6364136223846793005 + 1442695040888963407;
    RETURN (seed DIV 65536) MOD n
  END Random;

  PROCEDURE SetOffset(VAR odt: C.OffsetDateTime; year, month, day, hour, minute, second,
                      nanosecond, offset: LONGINT);
  BEGIN
    ASSERT(C.SetDateTime(odt, year, month, day, hour, minute, second, nanosecond));
    odt.offset := offset
  END SetOffset;

  PROCEDURE Length(x-: ARRAY OF CHAR): LONGINT;
    VAR n: LONGINT;
  BEGIN
    n := 0;
    WHILE (n < LEN(x)) & (x[n] # 0X) DO INC(n) END;
    RETURN n
  END Length;

  (* Format of odt by pattern, with abbreviation for %Z *)
  PROCEDURE Writes(pattern: ARRAY OF CHAR; odt: C.OffsetDateTime; abbreviation, expected: ARRAY OF CHAR);
  BEGIN
    s := "";  S.Format(pattern, odt, abbreviation, s);  T.Str(pattern, s, expected)
  END Writes;

  (* the same, of base, 2026-10-28T14:05:09.123456789-04:00 in EDT *)
  PROCEDURE Base(pattern, expected: ARRAY OF CHAR);
  BEGIN
    Writes(pattern, base, "EDT", expected)
  END Base;

  (* Parse of all of text by pattern, which must give expected, as
     OffsetDateTime writes it, and given *)
  PROCEDURE Reads(pattern, text, expected: ARRAY OF CHAR; given: SET);
    VAR odt: C.OffsetDateTime; g: SET; pos: LONGINT; ok: BOOLEAN;
  BEGIN
    pos := 0;  ok := S.Parse(pattern, odt, g, text, pos);
    IF ok THEN s := "";  S.OffsetDateTime(odt, S.shortest, s) ELSE s := "FALSE" END;
    T.Str(text, s, expected);
    IF ok THEN
      T.True(text, g = given);
      T.Int(text, pos, Length(text))
    END
  END Reads;

  (* Parse of text by pattern must fail, leaving its results alone *)
  PROCEDURE Refuses(pattern, text: ARRAY OF CHAR);
    VAR odt: C.OffsetDateTime; g: SET; pos: LONGINT; ok: BOOLEAN;
  BEGIN
    odt := base;  g := {3, 11};  pos := 0;
    ok := S.Parse(pattern, odt, g, text, pos);
    T.True(text, ~ok & (pos = 0) & (g = {3, 11}) & (C.CompareDateTimes(odt, base) = 0)
      & (odt.offset = base.offset))
  END Refuses;

  PROCEDURE Directives;
    VAR odt: C.OffsetDateTime;
  BEGIN
    Base("%Y-%m-%d %H:%M:%S", "2026-10-28 14:05:09");
    Base("%N|%1N|%3N|%6N|%9N|%-N|%_3N", "123456789|1|123|123456|123456789|123456789|123");
    Base("%z|%:z|%::z|%Z|%^Z", "-0400|-04:00|-04:00:00|EDT|EDT");
    Writes("[%Z]", base, "", "[]");
    Writes("%^Z|%Z", base, "edt", "EDT|edt");
    Base("%a|%A|%b|%B|%h|%^a|%^A|%^b|%^B", "Wed|Wednesday|Oct|October|Oct|WED|WEDNESDAY|OCT|OCTOBER");
    Base("%p|%P|%^P|%I|%l|%k", "PM|pm|PM|02| 2|14");
    Base("%c|%^c", "Wed Oct 28 14:05:09 2026|WED OCT 28 14:05:09 2026");
    Base("%F|%T|%R|%D|%x|%X", "2026-10-28|14:05:09|14:05|10/28/26|10/28/26|14:05:09");
    Base("%s|%-s|%_s", "1793210709|1793210709|1793210709");
    Base("%u|%w|%V|%U|%W|%j|%G|%g", "3|3|44|43|43|301|2026|26");
    Base("100%%|%%Y", "100%|%Y");
    s := "";  S.Format("a%nb%tc", base, "", s);
    T.True("%n %t", (s[0] = "a") & (s[1] = 0AX) & (s[2] = "b") & (s[3] = 09X) & (s[4] = "c") & (s[5] = 0X));

    SetOffset(odt, 2026, 3, 5, 4, 7, 8, 0, 0);
    Writes("%d|%-d|%_d|%0d|%e|%-e|%0e|%_e", odt, "", "05|5| 5|05| 5|5|05| 5");
    Writes("%j|%-j|%_j|%H|%-H|%_H|%k|%0k|%-k", odt, "", "064|64| 64|04|4| 4| 4|04|4");
    Writes("%I|%-I|%l|%p|%P|%m|%-m|%_m|%_y|%-y", odt, "", "04|4| 4|AM|am|03|3| 3|26|26");
    Writes("%_Y|%-Y|%0Y|%_C|%_G", odt, "", "2026|2026|2026|20|2026");
    Writes("%z|%:z|%::z", odt, "", "+0000|+00:00|+00:00:00");
    SetOffset(odt, 2026, 3, 5, 0, 0, 0, 0, 3600);
    Writes("%z|%:z|%::z|%I %p|%l", odt, "", "+0100|+01:00|+01:00:00|12 AM|12");
    SetOffset(odt, 2026, 3, 5, 12, 0, 0, 0, -93599);
    Writes("%z|%:z|%::z|%I %p", odt, "", "-255959|-25:59:59|-25:59:59|12 PM");

    (* offsets with seconds, as local mean times have them (Q21) *)
    SetOffset(odt, 1900, 1, 1, 0, 0, 0, 0, -1521);
    Writes("%z|%:z|%::z", odt, "", "-002521|-00:25:21|-00:25:21");
    odt.offset := 1172;
    Writes("%z|%:z|%::z", odt, "", "+001932|+00:19:32|+00:19:32");

    (* years before 1000 and negative ones (Q18) *)
    SetOffset(odt, -44, 3, 15, 0, 0, 0, 0, 0);
    Writes("%Y|%-Y|%_Y|%C|%-C|%y|%F|%G|%g|%D", odt, "", "-0044|-44|  -44|-1|-1|56|-0044-03-15|-0044|56|03/15/56");
    Writes("%c", odt, "", "Thu Mar 15 00:00:00 -0044");
    SetOffset(odt, 999, 6, 1, 0, 0, 0, 0, 0);
    Writes("%Y|%-Y|%C|%-C|%y", odt, "", "0999|999|09|9|99");
    SetOffset(odt, 0, 6, 1, 0, 0, 0, 0, 0);
    Writes("%Y|%C|%y|%F", odt, "", "0000|00|00|0000-06-01");
    SetOffset(odt, -1, 6, 1, 0, 0, 0, 0, 0);
    Writes("%Y|%C|%y", odt, "", "-0001|-1|99");
    SetOffset(odt, -9999, 1, 1, 0, 0, 0, 0, 0);
    Writes("%Y|%C|%y|%G|%V|%s", odt, "", "-9999|-100|01|-9999|01|-377705116800");
    SetOffset(odt, 9999, 12, 31, 23, 59, 59, 999999999, 0);
    Writes("%Y|%G|%V|%s.%N", odt, "", "9999|9999|52|253402300799.999999999");
    SetOffset(odt, 1969, 12, 31, 23, 59, 59, 0, 0);
    Writes("%s", odt, "", "-1");

    (* unknown directives, as they stand *)
    Base("%Q|%E|%10N|%0N|%5z|%:a|%:::z|%-", "%Q|%E|%10N|123456789|%5z|%:a|%:::z|%-");
    Base("%", "%");
    Base("x%", "x%")
  END Directives;

  PROCEDURE Appending;
    VAR short: ARRAY 8 OF CHAR; z: Z.Zone; t: I.Instant; odt: C.OffsetDateTime;
  BEGIN
    s := "on ";  S.Format("%F", base, "", s);  T.Str("append", s, "on 2026-10-28");
    short := "";  S.Format("%F %T", base, "", short);  T.Str("cut short", short, "2026-10");
    short := "";  S.Format("%Z", base, "ABCDEFGHIJ", short);  T.Str("cut %Z", short, "ABCDEFG");
    short := "";  S.Format("%c", base, "", short);  T.Str("cut %c", short, "Wed Oct");
    short := "1234567";  S.Format("%Y", base, "", short);  T.Str("full", short, "1234567");

    ASSERT(Z.Posix("EST5EDT,M3.2.0,M11.1.0", z));
    C.ToInstant(base, t);
    s := "";  S.FormatIn("%F %T %z %Z", t, z, s);  T.Str("FormatIn EDT", s, "2026-10-28 14:05:09 -0400 EDT");
    SetOffset(odt, 2026, 1, 15, 12, 0, 0, 0, 0);  C.ToInstant(odt, t);
    s := "";  S.FormatIn("%F %T %z %Z", t, z, s);  T.Str("FormatIn EST", s, "2026-01-15 07:00:00 -0500 EST");
    s := "";  S.FormatIn("%F %T %:z", t, Z.Fixed(19800), s);  T.Str("FormatIn fixed", s, "2026-01-15 17:30:00 +05:30");
    (* FromInstant's saturation, at the last instant *)
    s := "";  S.FormatIn("%F %T.%N %:z", I.latest, Z.Fixed(50400), s);
    T.Str("FormatIn latest", s, "9999-12-31 23:59:59.999999999 +14:00")
  END Appending;

  PROCEDURE Fields;
  BEGIN
    Reads("%Y-%m-%d", "2026-10-28", "2026-10-28T00:00:00Z", {Y, Mo, D});
    Reads("%F %T.%N %z", "2026-10-28 14:05:09.123456789 -0400", "2026-10-28T14:05:09.123456789-04:00",
      {Y, Mo, D, H, Mi, Se, N, O});
    Reads("%c", "Wed Oct 28 14:05:09 2026", "2026-10-28T14:05:09Z", {Y, Mo, D, H, Mi, Se, W});
    Reads("%c", "wed oct 28 14:05:09 2026", "2026-10-28T14:05:09Z", {Y, Mo, D, H, Mi, Se, W});
    Reads("%c", "Sun Mar  1 00:00:00 2026", "2026-03-01T00:00:00Z", {Y, Mo, D, H, Mi, Se, W});
    Reads("%D %R", "10/28/26 14:05", "2026-10-28T14:05:00Z", {Y, Mo, D, H, Mi});
    Reads("%x %X", "10/28/69 14:05:09", "1969-10-28T14:05:09Z", {Y, Mo, D, H, Mi, Se});
    Reads("%H%M%S", "140509", "2000-01-01T14:05:09Z", {H, Mi, Se});

    (* fields not given: 2000-01-01T00:00:00Z (Q20) *)
    Reads("%b %e", "Feb 29", "2000-02-29T00:00:00Z", {Mo, D});
    Reads("%b %e %T", "Oct  5 14:05:09", "2000-10-05T14:05:09Z", {Mo, D, H, Mi, Se});
    Reads("%Y", "2026", "2026-01-01T00:00:00Z", {Y});
    Reads("%M", "05", "2000-01-01T00:05:00Z", {Mi});
    Reads("100%%", "100%", "2000-01-01T00:00:00Z", {});
    Reads("", "", "FALSE", {});

    (* a weekday is checked against a full date only *)
    Reads("%a %m-%d", "Mon 10-28", "2000-10-28T00:00:00Z", {Mo, D, W});
    Reads("%A %Y", "Monday 2026", "2026-01-01T00:00:00Z", {Y, W});
    Reads("%a %F", "WEDNESDAY 2026-10-28", "2026-10-28T00:00:00Z", {Y, Mo, D, W});
    Refuses("%a %F", "Mon 2026-10-28");
    Refuses("%u %F", "1 2026-10-28");
    Reads("%u %F", "3 2026-10-28", "2026-10-28T00:00:00Z", {Y, Mo, D, W});
    Reads("%w %F", "0 2026-11-01", "2026-11-01T00:00:00Z", {Y, Mo, D, W});
    Refuses("%w %F", "7 2026-11-01");
    Reads("%U %W %F", "43 43 2026-10-28", "2026-10-28T00:00:00Z", {Y, Mo, D});
    Refuses("%U %F", "44 2026-10-28");
    Refuses("%W %F", "42 2026-10-28");
    Reads("%U %W %F", "00 00 2026-01-03", "2026-01-03T00:00:00Z", {Y, Mo, D});
    Reads("%U %W %F", "01 00 2026-01-04", "2026-01-04T00:00:00Z", {Y, Mo, D});
    Reads("%V %F", "44 2026-10-28", "2026-10-28T00:00:00Z", {Y, Mo, D});
    Refuses("%V %F", "43 2026-10-28");
    Refuses("%G %F", "2025 2026-10-28");

    (* ISO week dates *)
    Reads("%G-W%V-%u", "2026-W44-3", "2026-10-28T00:00:00Z", {Y, Mo, D, W});
    Reads("%G-W%V", "2026-W01", "2025-12-29T00:00:00Z", {Y, Mo, D});
    Reads("%G-W%V-%u", "2026-W53-7", "2027-01-03T00:00:00Z", {Y, Mo, D, W});
    Refuses("%G-W%V-%u", "2025-W53-1");
    Refuses("%G-W%V-%u", "2026-W00-1");
    Refuses("%G-W%V-%u", "2026-W44-8");
    Reads("%g-W%V-%u", "26-W44-3", "2026-10-28T00:00:00Z", {Y, Mo, D, W});
    Reads("%Y %G-W%V-%u", "2025 2026-W01-1", "2025-12-29T00:00:00Z", {Y, Mo, D, W});
    Refuses("%Y %G-W%V-%u", "2026 2026-W01-1");
    Refuses("%F %G-W%V-%u", "2026-10-29 2026-W44-3");
    Reads("%G-W%V-%u", "-9998-W01-1", "-9999-12-31T00:00:00Z", {Y, Mo, D, W});
    Reads("%G-W%V-%u", "-9999-W01-1", "-9999-01-01T00:00:00Z", {Y, Mo, D, W});
    Refuses("%G-W%V-%u", "-9999-W00-7");

    (* days of the year *)
    Reads("%Y %j", "2026 301", "2026-10-28T00:00:00Z", {Y, Mo, D});
    Reads("%Y %j", "2024 366", "2024-12-31T00:00:00Z", {Y, Mo, D});
    Refuses("%Y %j", "2026 366");
    Refuses("%Y %j", "2026 000");
    Reads("%j", "60", "2000-02-29T00:00:00Z", {Mo, D});
    Reads("%Y %j %m-%d", "2026 301 10-28", "2026-10-28T00:00:00Z", {Y, Mo, D});
    Refuses("%Y %j %m-%d", "2026 301 10-29");

    (* the 12-hour clock *)
    Reads("%I:%M %p", "12:30 am", "2000-01-01T00:30:00Z", {H, Mi});
    Reads("%I:%M %p", "12:30 PM", "2000-01-01T12:30:00Z", {H, Mi});
    Reads("%l:%M %P", " 1:30 pm", "2000-01-01T13:30:00Z", {H, Mi});
    Reads("%I:%M", "01:30", "2000-01-01T01:30:00Z", {H, Mi});
    Reads("%H %I %p", "13 01 PM", "2000-01-01T13:00:00Z", {H});
    Reads("%p %H", "AM 13", "2000-01-01T13:00:00Z", {H});
    Refuses("%H %I %p", "13 01 AM");
    Refuses("%I %p", "01 XM");
    Refuses("%I", "00");
    Refuses("%I", "13")
  END Fields;

  PROCEDURE Offsets;
  BEGIN
    Reads("%z", "Z", "2000-01-01T00:00:00Z", {O});
    Reads("%z", "z", "2000-01-01T00:00:00Z", {O});
    Reads("%z", "+05", "2000-01-01T00:00:00+05:00", {O});
    Reads("%z", "+0530", "2000-01-01T00:00:00+05:30", {O});
    Reads("%z", "+053015", "2000-01-01T00:00:00+05:30:15", {O});
    Reads("%z", "+05:30", "2000-01-01T00:00:00+05:30", {O});
    Reads("%:z", "+05:30:15", "2000-01-01T00:00:00+05:30:15", {O});
    Reads("%::z", "-00:25:21", "2000-01-01T00:00:00-00:25:21", {O});
    Reads("%::z", "-002521", "2000-01-01T00:00:00-00:25:21", {O});
    Reads("%z", "+0000", "2000-01-01T00:00:00Z", {O});
    Reads("%z", "-255959", "2000-01-01T00:00:00-25:59:59", {O});
    Refuses("%z", "+0560");
    Refuses("%z", "+053060");
    Refuses("%::z", "+05:30:60");
    Refuses("%z", "+2600");
    Refuses("%z", "+05:3");
    Refuses("%z", "0530");
    Refuses("%z", "+5");
    Refuses("%z", "+05301");
    Refuses("%z", "+0530:15");
    Refuses("%z", "UTC");

    (* %Z: an offset only from a name with one meaning (Q19) *)
    Reads("%F %T %Z", "2026-10-28 14:05:09 UTC", "2026-10-28T14:05:09Z", {Y, Mo, D, H, Mi, Se, O});
    Reads("%Z", "gmt", "2000-01-01T00:00:00Z", {O});
    Reads("%Z", "Ut", "2000-01-01T00:00:00Z", {O});
    Reads("%Z", "Z", "2000-01-01T00:00:00Z", {O});
    Reads("%Z", "EDT", "2000-01-01T00:00:00Z", {});
    Reads("%Z", "-03", "2000-01-01T00:00:00-03:00", {O});
    Reads("%Z", "+0530", "2000-01-01T00:00:00+05:30", {O});
    Reads("%Z", "ABCDEFGHIJKLMNO", "2000-01-01T00:00:00Z", {});
    Refuses("%Z", "ABCDEFGHIJKLMNOP");
    Refuses("%Z", "");
    Refuses("%Z", "+5");
    Reads("%z %Z", "-0400 EDT", "2000-01-01T00:00:00-04:00", {O});
    Reads("%Z %z", "-03 -0300", "2000-01-01T00:00:00-03:00", {O});
    Refuses("%z %Z", "-0400 UTC");
    Refuses("%Z %z", "-03 -0400");
    Reads("%Z%z", "EST-0500", "2000-01-01T00:00:00-05:00", {O})
  END Offsets;

  PROCEDURE Numbers;
  BEGIN
    (* years: four digits after a sign, %C and %y floored (Q18) *)
    Reads("%Y", "-0044", "-0044-01-01T00:00:00Z", {Y});
    Reads("%Y", "-44", "-0044-01-01T00:00:00Z", {Y});
    Reads("%Y", "44", "0044-01-01T00:00:00Z", {Y});
    Reads("%Y", "0000", "0000-01-01T00:00:00Z", {Y});
    Reads("%Y", "-9999", "-9999-01-01T00:00:00Z", {Y});
    Reads("%Y%m%d", "20261028", "2026-10-28T00:00:00Z", {Y, Mo, D});
    Refuses("%Y", "10000");
    Refuses("%Y", "-10000");
    Refuses("%Y", "-0");
    Refuses("%Y", "-");
    Refuses("%Y", "+2026");
    Reads("%C%y", "-156", "-0044-01-01T00:00:00Z", {Y});
    Reads("%C%y", "2026", "2026-01-01T00:00:00Z", {Y});
    Reads("%C %y", "-1 99", "-0001-01-01T00:00:00Z", {Y});
    Reads("%C", "19", "1900-01-01T00:00:00Z", {Y});
    (* the sign counts toward %C's two places, as it does in what Format
       writes, so that %C%y reads back; -10 and below cannot be read *)
    Reads("%C", "-9", "-0900-01-01T00:00:00Z", {Y});
    Refuses("%C", "-99");
    Refuses("%C", "-100");
    Reads("%y", "68", "2068-01-01T00:00:00Z", {Y});
    Reads("%y", "69", "1969-01-01T00:00:00Z", {Y});
    Reads("%y", "00", "2000-01-01T00:00:00Z", {Y});
    Reads("%-y", "5", "2005-01-01T00:00:00Z", {Y});
    Refuses("%y", "-5");
    Reads("%Y %y", "1999 05", "1999-01-01T00:00:00Z", {Y});

    (* widths, ranges and padding *)
    Reads("%e", " 5", "2000-01-05T00:00:00Z", {D});
    Reads("%e", "5", "2000-01-05T00:00:00Z", {D});
    Reads("%_d", " 5", "2000-01-05T00:00:00Z", {D});
    Reads("%-d", "5", "2000-01-05T00:00:00Z", {D});
    Refuses("%d", " 5");
    Refuses("%e", "  5");
    Reads("%k", " 0", "2000-01-01T00:00:00Z", {H});
    Reads("%_j", "  9", "2000-01-09T00:00:00Z", {Mo, D});
    Reads("%m-%d", "02-29", "2000-02-29T00:00:00Z", {Mo, D});
    Refuses("%m", "13");
    Refuses("%m", "00");
    Refuses("%d", "32");
    Refuses("%d", "00");
    Refuses("%Y-%m-%d", "2026-02-29");
    Refuses("%m-%d", "04-31");
    Refuses("%H", "24");
    Refuses("%k", "24");
    Refuses("%M", "60");
    Refuses("%S", "61");
    Refuses("%S", "60");
    Refuses("%d", "");
    Refuses("%d", "x");

    (* fractions *)
    Reads("%T.%N", "14:05:09.5", "2000-01-01T14:05:09.500Z", {H, Mi, Se, N});
    Reads("%T.%3N", "14:05:09.123", "2000-01-01T14:05:09.123Z", {H, Mi, Se, N});
    Reads("%T.%N", "14:05:09.000000001", "2000-01-01T14:05:09.000000001Z", {H, Mi, Se, N});
    Refuses("%T.%3N", "14:05:09.1234");
    Refuses("%T.%N", "14:05:09.");
    Refuses("%T.%N", "14:05:09.1234567891");

    (* %s sets every field, at the offset given or 0 *)
    Reads("%s", "0", "1970-01-01T00:00:00Z", {Y, Mo, D, H, Mi, Se});
    Reads("%s", "-1", "1969-12-31T23:59:59Z", {Y, Mo, D, H, Mi, Se});
    Reads("%s.%N", "1.5", "1970-01-01T00:00:01.500Z", {Y, Mo, D, H, Mi, Se, N});
    Reads("%s %z", "0 +0100", "1970-01-01T01:00:00+01:00", {Y, Mo, D, H, Mi, Se, O});
    Reads("%s", "1793210709", "2026-10-28T18:05:09Z", {Y, Mo, D, H, Mi, Se});
    Reads("%Y %s", "1999 0", "1970-01-01T00:00:00Z", {Y, Mo, D, H, Mi, Se});
    Reads("%s", "253402300799", "9999-12-31T23:59:59Z", {Y, Mo, D, H, Mi, Se});
    Reads("%s", "-377705116800", "-9999-01-01T00:00:00Z", {Y, Mo, D, H, Mi, Se});
    Refuses("%s", "253402300800");
    Refuses("%s", "-377705116801");
    Refuses("%s", "99999999999999999999");
    Refuses("%s", "-");
    Refuses("%s %z", "253402300799 +0100");
    Refuses("%s %z", "-377705116800 -0100");

    (* leap seconds, only where UTC is at 23:59:60 on a month's last day *)
    Reads("%FT%T%z", "2016-12-31T23:59:60Z", "2016-12-31T23:59:59.999999999Z", {Y, Mo, D, H, Mi, Se, O});
    Reads("%FT%T.%N%z", "2016-12-31T23:59:60.5Z", "2016-12-31T23:59:59.999999999Z",
      {Y, Mo, D, H, Mi, Se, N, O});
    Reads("%FT%T%:z", "2016-12-31T18:59:60-05:00", "2016-12-31T18:59:59.999999999-05:00",
      {Y, Mo, D, H, Mi, Se, O});
    Refuses("%FT%T%z", "2016-12-30T23:59:60Z");
    Refuses("%FT%T%z", "2016-12-31T22:59:60Z");
    Refuses("%F %T", "2016-12-31 23:59:60");
    Refuses("%FT%T%z", "9999-12-31T23:59:60-0100")
  END Numbers;

  PROCEDURE Text;
    VAR odt: C.OffsetDateTime; given: SET; pos: LONGINT; ok: BOOLEAN;
  BEGIN
    (* blanks match any run of blanks, including none *)
    Reads("%Y %m", "2026   10", "2026-10-01T00:00:00Z", {Y, Mo});
    Reads("%Y %m", "202610", "2026-10-01T00:00:00Z", {Y, Mo});
    Reads("%Y%n%m%t%d", "2026 10 28", "2026-10-28T00:00:00Z", {Y, Mo, D});
    Refuses("%Y-%m", "2026 -10");
    Refuses("%Y-%m", "2026/10");
    Refuses("x%Y", "X2026");

    (* names, in either case, in full or in three letters *)
    Reads("%B", "oct", "2000-10-01T00:00:00Z", {Mo});
    Reads("%b", "OCTOBER", "2000-10-01T00:00:00Z", {Mo});
    Reads("%h", "May", "2000-05-01T00:00:00Z", {Mo});
    Reads("%B %Y", "September 2026", "2026-09-01T00:00:00Z", {Y, Mo});
    Reads("%A", "thu", "2000-01-01T00:00:00Z", {W});
    Refuses("%B", "Ju");
    Refuses("%B", "Xyz");
    Refuses("%a", "Mo");

    (* flags are read and do nothing; unknown directives fail *)
    Reads("%^a %-d %_m %0Y", "FRI 5  6 2026", "2026-06-05T00:00:00Z", {Y, Mo, D, W});
    Refuses("%Q", "%Q");
    Refuses("%10N", "1");
    Refuses("%0N", "");
    Refuses("%:a", "Mon");
    Refuses("%:::z", "+05:30");
    Refuses("%5d", "5");
    Refuses("%", "%");

    (* the text may go on, but not with a digit *)
    Refuses("%H", "123");
    Refuses("%F", "2026-10-281");
    pos := 0;
    ok := S.Parse("%H", odt, given, "12:", pos);
    T.True("then a colon", ok & (pos = 2) & (given = {H}) & (odt.hour = 12));
    pos := 0;
    ok := S.Parse("%z", odt, given, "+05:", pos);
    T.True("then a colon after %z", ok & (pos = 3) & (odt.offset = 18000));
    pos := 0;
    ok := S.Parse("%Y %m", odt, given, "2026 10 ", pos);
    T.True("then a blank", ok & (pos = 7));
    pos := 0;
    ok := S.Parse("%B", odt, given, "Sept", pos);
    T.True("Sept", ok & (pos = 3) & (odt.month = 9));

    (* from pos, which must be within the text *)
    pos := 3;
    ok := S.Parse("%F", odt, given, "on 2026-10-28.", pos);
    T.True("from pos", ok & (pos = 13) & (odt.year = 2026) & (odt.day = 28));
    pos := 14;  odt := base;
    ok := S.Parse("%F", odt, given, "on 2026-10-28.", pos);
    T.True("pos at the end", ~ok & (pos = 14));
    pos := -1;
    ok := S.Parse("%F", odt, given, "2026-10-28", pos);
    T.True("pos before", ~ok & (pos = -1));
    pos := 0;
    ok := S.Parse("", odt, given, "x", pos);
    T.True("empty pattern", ok & (pos = 0) & (given = {}))
  END Text;

  (* the rows of PatternsData: what Format writes and what Parse reads back *)
  PROCEDURE Row(year, month, day, hour, minute, second, offset: LONGINT;
                abbreviation, pattern, text: ARRAY OF CHAR);
    VAR odt, r: C.OffsetDateTime; given, expected: SET; pos: LONGINT; ok: BOOLEAN;
  BEGIN
    INC(table);
    SetOffset(odt, year, month, day, hour, minute, second, 0, offset);
    s := "";  S.Format(pattern, odt, abbreviation, s);
    IF s # text THEN INC(tableBad);  T.Str(pattern, s, text) END;
    pos := 0;  ok := S.Parse(pattern, r, given, text, pos);
    IF pattern[1] = "s" THEN expected := {Y .. Se, O}
    ELSIF pattern[1] = "c" THEN expected := {Y .. Se, W};  odt.offset := 0
    ELSE expected := {Y .. Se, O, W}
    END;
    IF ~ok OR (pos # Length(text)) OR (given # expected) OR (C.CompareDateTimes(r, odt) # 0)
        OR (r.offset # odt.offset) THEN
      INC(tableBad);  T.Str(pattern, "Parse failed", text)
    END
  END Row;

  PROCEDURE Table;
  BEGIN
    table := 0;  tableBad := 0;
    PatternsData.Each(Row);
    T.Int("table rows", table, PatternsData.Count());
    T.Int("table", tableBad, 0)
  END Table;

  (* Format, then Parse with the same pattern, over the whole range *)
  PROCEDURE Trips;
    CONST
      first = -377705116800;  span = 377705116800 + 253402300799 + 1;
    VAR
      k, bad, pos: LONGINT; p: INTEGER; odt, r: C.OffsetDateTime; t: I.Instant; given: SET;
      weekYear, week: LONGINT; ok: BOOLEAN;
      pattern: ARRAY 64 OF CHAR;
  BEGIN
    bad := 0;
    FOR k := 1 TO trips DO
      I.FromUnix(t, first + Random(span), Random(1000000000));
      C.FromInstant(odt, t, SHORT(Random(2 * 93599 + 1) - 93599));
      IF k = 1 THEN SetOffset(odt, -9999, 1, 1, 0, 0, 0, 0, 0)
      ELSIF k = 2 THEN SetOffset(odt, 9999, 12, 31, 23, 59, 59, 999999999, 0)
      END;
      FOR p := 0 TO 4 DO
        CASE p OF
          0: pattern := "%Y-%m-%dT%H:%M:%S.%N%::z"
        | 1: pattern := "%A %e %B %Y %l:%M:%S.%N %P %:z"
        | 2: pattern := "%G-W%V-%u %T.%N %z"
        | 3: pattern := "%-Y/%-j %-H:%-M:%-S.%N%z"
        | 4: pattern := "%s.%N %z"
        END;
        C.IsoWeek(odt, weekYear, week);
        (* a week-year beyond the years, and an instant beyond the
           instants, cannot be read *)
        ok := ~((p = 2) & ((weekYear < C.minYear) OR (weekYear > C.maxYear)))
          & ~((p = 4) & ~C.CheckedToInstant(t, odt));
        IF ok THEN
          s := "";  S.Format(pattern, odt, "", s);
          pos := 0;
          IF ~S.Parse(pattern, r, given, s, pos) OR (s[pos] # 0X) OR (C.CompareDateTimes(r, odt) # 0)
              OR (r.offset # odt.offset) THEN
            INC(bad);  T.Str(pattern, "trip failed", s)
          END
        END
      END
    END;
    T.Int("trips", bad, 0)
  END Trips;

BEGIN
  seed := 20261028;
  SetOffset(base, 2026, 10, 28, 14, 5, 9, 123456789, -14400);
  T.Start("Patterns");
  Directives;  Appending;  Fields;  Offsets;  Numbers;  Text;  Table;  Trips;
  T.Finish
END PatternsTest.
