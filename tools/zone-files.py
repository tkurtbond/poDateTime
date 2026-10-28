#!/usr/bin/env python3
"""Write the TZif files the TimeZones tests read (design Q17), under
test/data/zoneinfo/:

  fat/, slim/  the zones of design 12.3, compiled by zic in both its
               forms from a tzdata.zi, by default the system's;
  made/        small files written here: version 1, version 4 with an
               extended footer, one with a leap second, and damaged ones
               that must be refused.

The files are checked in, so that every host tests the same data and a
tzdata release cannot break the tests; tools/zones-data.py makes the
tables from them.

Usage: tools/zone-files.py [tzdata.zi]
"""

import os
import shutil
import struct
import subprocess
import sys
import tempfile

ZONES = ["America/New_York", "Europe/London", "Australia/Lord_Howe",
         "Asia/Kolkata", "Pacific/Chatham", "Pacific/Apia",
         "Africa/Casablanca", "Europe/Dublin"]
OUT = "test/data/zoneinfo"


def compile_zones(source):
    for form in ("fat", "slim"):
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(["zic", "-b", form, "-d", tmp, source], check=True)
            for zone in ZONES:
                target = os.path.join(OUT, form, zone)
                os.makedirs(os.path.dirname(target), exist_ok=True)
                shutil.copyfile(os.path.join(tmp, zone), target)


def block(times, indexes, types, chars, size, leaps=()):
    """A header and data block; types are (offset, isdst, abbreviation
    index), leaps (time, correction)."""
    fmt = ">i" if size == 4 else ">q"
    data = b"".join(struct.pack(fmt, t) for t in times)
    data += bytes(indexes)
    data += b"".join(struct.pack(">iBB", o, d, a) for o, d, a in types)
    data += chars
    data += b"".join(struct.pack(fmt + "i", t, c) for t, c in leaps)
    data += bytes(len(types)) * 2   # isstd, isut
    return data


def header(version, times, types, chars, leaps=()):
    return (b"TZif" + version + bytes(15)
            + struct.pack(">6I", len(types), len(types), len(leaps),
                          len(times), len(types), len(chars)))


def tzif(version, times, indexes, types, chars, footer=b"", leaps=()):
    v1 = header(version, times, types, chars, leaps) + block(
        times, indexes, types, chars, 4, leaps)
    if version == b"\0":
        return v1
    return (v1 + header(version, times, types, chars, leaps)
            + block(times, indexes, types, chars, 8, leaps)
            + b"\n" + footer + b"\n")


# A zone of -05:00 with daylight saving time at -04:00 from 2000 to 2003,
# and its abbreviations
TIMES = [954658800, 972799200, 986108400, 1004248800, 1018162800,
         1035698400, 1049612400, 1067148000]
INDEXES = [1, 0] * 4
TYPES = [(-18000, 0, 0), (-14400, 1, 4)]
CHARS = b"EST\0EDT\0"


def made():
    files = {
        # version 1: 32-bit data and no footer, so EST after 2003
        "v1": tzif(b"\0", TIMES, INDEXES, TYPES, CHARS),
        # version 4, whose footer keeps daylight saving time all year, a
        # version 3 extension (RFC 8536 3.3.1)
        "v4": tzif(b"4", TIMES, INDEXES, TYPES, CHARS, b"EST5EDT,0/0,J365/25"),
        # no transitions: the footer alone
        "footer": tzif(b"2", [], [], [(19800, 0, 0)], b"IST\0",
                       b"<+0530>-5:30"),
        # no transitions and no footer: type 0 alone
        "type0": tzif(b"2", [], [], [(-12600, 0, 0)], b"-0330\0"),
        "leap": tzif(b"2", TIMES, INDEXES, TYPES, CHARS, b"EST5",
                     [(78796800, 1)]),
    }
    good = tzif(b"2", TIMES, INDEXES, TYPES, CHARS, b"EST5EDT,M3.2.0,M11.1.0")
    second = len(header(b"2", TIMES, TYPES, CHARS)) + len(
        block(TIMES, INDEXES, TYPES, CHARS, 4))
    data = second + 44
    after_times = data + 8 * len(TIMES)
    after_indexes = after_times + len(TIMES)

    def changed(at, new):
        return good[:at] + new + good[at + len(new):]

    files.update({
        "good": good,
        "bad-magic": changed(second, b"TZiF"),
        "bad-version": changed(4, b"1"),
        "truncated": good[:len(good) // 2],
        "no-footer": good[:good.rindex(b"\n", 0, len(good) - 1) + 1],
        "bad-footer": tzif(b"2", TIMES, INDEXES, TYPES, CHARS, b"EST5EDT"),
        "bad-index": changed(after_times + 3, b"\x02"),
        "descending": changed(data + 8, struct.pack(">q", TIMES[0] - 1)),
        "bad-isdst": changed(after_indexes + 4, b"\x02"),
        "bad-abbreviation": changed(after_indexes + 5, b"\x08"),
        "bad-offset": changed(after_indexes, struct.pack(">i", 26 * 3600)),
        "unterminated": tzif(b"2", TIMES, INDEXES, TYPES, b"EST\0EDT",
                             b"EST5EDT,M3.2.0,M11.1.0"),
        "no-types": tzif(b"2", [], [], [], b"\0", b"EST5"),
    })
    os.makedirs(os.path.join(OUT, "made"), exist_ok=True)
    for name, contents in files.items():
        with open(os.path.join(OUT, "made", name), "wb") as f:
            f.write(contents)


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else "/usr/share/zoneinfo/tzdata.zi"
    compile_zones(source)
    made()


main()
