#!/usr/bin/env python3
"""Write test/data/ZonesData.Mod: what TimeZones must give for the TZif
files of test/data/zoneinfo/ (tools/zone-files.py) and for POSIX rules.

- Lookups: each zone's offset, daylight saving flag and abbreviation a
  second before and at each of its transitions from 1900 to 2040, and at
  some instants up to 9999. The offset and abbreviation are Python's
  ZoneInfo.from_file's and the flag is glibc's, for Python has none; the
  two must agree on the offset and abbreviation. Instants before a
  zone's first transition are left to the test, because Python reads
  them with the first standard time type, not with type 0 (RFC 8536).
- Local times: around each transition from 1970 to 2040, whether the
  local time is in a gap or an overlap, and the instants of folds 0 and
  1 from Python. In a gap TimeZones reads fold 0's, with the offset
  before it, for both earlier and later (design 8.2).
- POSIX rules: from glibc's localtime with TZ set to the rule, a second
  before and at each transition from 1970 to 2100 and at some instants
  up to 9999. glibc does not use a rule before 1970, so the test checks
  earlier years by the 400-year cycle of the calendar. glibc reads a
  rule in the year of UTC, so the hours in which that differs from the
  year of local standard time are left out, and the test checks some
  there by hand. Python's zoneinfo
  is not used here: it counts Jn's days wrongly in leap years and n's
  from 1, and it reads a rule in the year of UTC, not of local time.

Usage: tools/zones-data.py > test/data/ZonesData.Mod
"""

import datetime
import os
import random
import struct
import sys
import time
import zoneinfo

ZONES = ["America/New_York", "Europe/London", "Australia/Lord_Howe",
         "Asia/Kolkata", "Pacific/Chatham", "Pacific/Apia",
         "Africa/Casablanca", "Europe/Dublin"]
DIR = os.path.abspath("test/data/zoneinfo/fat")
RULES = [
    "EST5EDT,M3.2.0,M11.1.0",
    "CET-1CEST,M3.5.0,M10.5.0/3",
    "IST-1GMT0,M10.5.0,M3.5.0/1",   # negative daylight saving time
    "AEST-10AEDT,M10.1.0,M4.1.0/3",   # the southern hemisphere
    "<+1030>-10:30<+11>-11,M10.1.0,M4.1.0",
    "<+1245>-12:45<+1345>,M9.5.0/2:45,M4.1.0/3:45",
    "<-03>3<-02>,M3.5.0/-2,M10.5.0/-1",   # negative times
    "<-02>2<-01>,M3.5.0/-1,M10.5.0/0",
    "XXX3YYY,J60/2,J300/2",
    "XXX3YYY,59/2,299/2",
    "XXX3YYY,365/12,59/2",   # day 365 is January 1 in a common year
    "XXX3YYY,J365/23,J60/0",   # across the year's end
    "XXX3YYY2:30,M2.4.3/26,M11.5.6/-3",
    "<+0530>-5:30",
    "UTC0",
    "MST7",
]
UTC = datetime.timezone.utc
FIRST = int(datetime.datetime(1, 1, 2, tzinfo=UTC).timestamp())
LAST = int(datetime.datetime(9999, 12, 30, tzinfo=UTC).timestamp())


def year_start(y):
    return int(datetime.datetime(y, 1, 1, tzinfo=UTC).timestamp())


def glibc(tz, t):
    os.environ["TZ"] = tz
    time.tzset()
    tm = time.localtime(t)
    return tm.tm_gmtoff, tm.tm_isdst > 0, tm.tm_zone


def changes(info, start, end, step=86400):
    """The instants in start..end at which info changes: found a day at a
    time, then to the second"""
    found = []
    t, now = start, info(start)
    while t < end:
        u = min(t + step, end)
        later = info(u)
        if later != now:
            low, high = t, u
            while high - low > 1:
                middle = (low + high) // 2
                if info(middle) == now:
                    low = middle
                else:
                    high = middle
            found.append(high)
            t, now = high, info(high)
        else:
            t = u
    return found


def transitions(path):
    """The transition times of a TZif file's 64-bit block"""
    b = open(path, "rb").read()
    counts = struct.unpack(">6I", b[20:44])
    isut, isstd, leap, times, types, chars = counts
    skip = 44 + times * 5 + types * 6 + chars + leap * 8 + isstd + isut
    counts = struct.unpack(">6I", b[skip + 20:skip + 44])
    isut, isstd, leap, times, types, chars = counts
    p = skip + 44
    return list(struct.unpack(">%dq" % times, b[p:p + 8 * times]))


def zone_info(z):
    def info(t):
        d = datetime.datetime.fromtimestamp(t, z)
        return int(d.utcoffset().total_seconds()), d.tzname()
    return info


def lookups(rng):
    rows = []
    for name in ZONES:
        path = os.path.join(DIR, name)
        z = zoneinfo.ZoneInfo.from_file(open(path, "rb"))
        info = zone_info(z)
        listed = [t for t in transitions(path) if t > FIRST]
        # those of the footer after the file's last
        ts = listed + changes(info, max(listed[-1:] + [year_start(2030)]) + 1,
                              year_start(2041))
        ts = sorted(set(t for t in ts if year_start(1900) <= t < year_start(2041)))
        last = ts[-1] if ts else year_start(2041)
        times = set()
        for t in ts:
            times.update([t - 1, t])
        if listed:
            times = {t for t in times if t >= listed[0]}
        for _ in range(20):
            times.add(rng.randint(last, LAST))
        for y in (2100, 2400, 9999):
            for t in changes(info, year_start(y), min(year_start(y) + 365 * 86400, LAST)):
                times.update([t - 1, t])
        for t in sorted(times):
            offset, abbreviation = info(t)
            c_offset, isdst, c_abbreviation = glibc(":" + path, t)
            if (offset, abbreviation) != (c_offset, c_abbreviation):
                sys.exit("%s at %d: zoneinfo %s %s, glibc %s %s" % (
                    name, t, offset, abbreviation, c_offset, c_abbreviation))
            rows.append('r("%s", %d, %d, %s, "%s");' % (
                name, t, offset, "TRUE" if isdst else "FALSE", abbreviation))
    return rows


def local_times():
    rows = []
    for name in ZONES:
        path = os.path.join(DIR, name)
        z = zoneinfo.ZoneInfo.from_file(open(path, "rb"))
        info = zone_info(z)
        ts = changes(info, year_start(1970), year_start(2041))
        cases = set()
        for t in ts:
            before, after = info(t - 1)[0], info(t)[0]
            for base in (t + before, t + after):
                for delta in (-3601, -1, 0, 1, 1800, 3599):
                    cases.add(base + delta)
            cases.add(t + (before + after) // 2)
        for local in sorted(cases):
            dt = datetime.datetime.fromtimestamp(local, UTC).replace(tzinfo=None)
            fold0 = int(dt.replace(tzinfo=z, fold=0).timestamp())
            fold1 = int(dt.replace(tzinfo=z, fold=1).timestamp())
            back = datetime.datetime.fromtimestamp(fold0, z).replace(tzinfo=None)
            if back != dt:
                kind, later = "gap", fold0
            elif fold0 != fold1:
                kind, later = "overlap", fold1
            else:
                kind, later = "once", fold0
            rows.append('r("%s", %d, %d, %d, %d, %d, %d, %s, %d, %d);' % (
                name, dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second,
                kind, fold0, later))
    return rows


def rules(rng):
    rows = []
    for rule in RULES:
        info = lambda t: glibc(rule, t)
        ts = changes(info, 0, year_start(2101))
        times = set()
        for t in ts:
            times.update([t - 1, t])
        for _ in range(20):
            times.add(rng.randint(0, LAST))
        for y in (2400, 9999):
            for t in changes(info, year_start(y), min(year_start(y) + 365 * 86400, LAST)):
                times.update([t - 1, t])
        times.update([0, year_start(2001) - 1, year_start(2001)])
        glibc(rule, 0)
        standard = -time.timezone
        for t in sorted(times):
            if (datetime.datetime.fromtimestamp(t, UTC).year
                    != datetime.datetime.fromtimestamp(t + standard, UTC).year):
                continue
            offset, isdst, abbreviation = info(t)
            rows.append('r("%s", %d, %d, %s, "%s");' % (
                rule, t, offset, "TRUE" if isdst else "FALSE", abbreviation))
    return rows


def write(kind, comment, row_type, rows):
    chunk = 250
    print("  (* %s *)" % comment)
    print("  TYPE %sRow* = %s;" % (kind, row_type))
    print()
    for i in range(0, len(rows), chunk):
        print("  PROCEDURE %s%d(r: %sRow);" % (kind, i // chunk, kind))
        print("  BEGIN")
        for row in rows[i:i + chunk]:
            print("    " + row)
        print("  END %s%d;" % (kind, i // chunk))
        print()
    print("  PROCEDURE Each%s*(r: %sRow);" % (kind, kind))
    print("  BEGIN")
    for i in range(0, len(rows), chunk):
        print("    %s%d(r);" % (kind, i // chunk))
    print("  END Each%s;" % kind)
    print()
    print("  PROCEDURE %sCount*(): LONGINT;" % kind)
    print("  BEGIN")
    print("    RETURN %d" % len(rows))
    print("  END %sCount;" % kind)
    print()


def main():
    rng = random.Random(19700101)
    lookup_rows = lookups(rng)
    local_rows = local_times()
    rule_rows = rules(rng)
    print("MODULE ZonesData;")
    print()
    print("  (* Generated by tools/zones-data.py from Python's zoneinfo and"
          " glibc;")
    print("     do not edit. *)")
    print()
    print("  CONST once* = 0;  gap* = 1;  overlap* = 2;")
    print()
    write("Lookup", "a zone of test/data/zoneinfo, an instant's POSIX seconds,"
          " and the\n     offset, flag and abbreviation there",
          "PROCEDURE (zone: ARRAY OF CHAR; seconds: HUGEINT; offset: LONGINT;\n"
          "                               isDst: BOOLEAN; abbreviation: ARRAY OF CHAR)",
          lookup_rows)
    write("Local", "a zone, a local time, its kind, and the POSIX seconds of"
          " earlier and\n     later",
          "PROCEDURE (zone: ARRAY OF CHAR; year, month, day, hour, minute, second,\n"
          "                              kind: LONGINT; earlier, later: HUGEINT)",
          local_rows)
    write("Rule", "a POSIX rule, an instant's POSIX seconds, and the offset,"
          " flag and\n     abbreviation there",
          "PROCEDURE (rule: ARRAY OF CHAR; seconds: HUGEINT; offset: LONGINT;\n"
          "                             isDst: BOOLEAN; abbreviation: ARRAY OF CHAR)",
          rule_rows)
    print("END ZonesData.")


main()
