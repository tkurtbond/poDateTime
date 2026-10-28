# Instants near the ends of the years, at an offset

Written 2026-10-28. This document records the decision on Q12 in
[date-time-design.md](date-time-design.md): what `Calendar.FromInstant`
does when the offset carries the civil time outside the years
-9999..9999.

**Decision: option 1.** `FromInstant` saturates, as before. A new
`CheckedFromInstant` returns `FALSE` and leaves its result unchanged.

## 1. The problem

The instants cover exactly the civil years read as UTC:
`Instants.earliest` is -9999-01-01T00:00:00Z and `Instants.latest` is
9999-12-31T23:59:59.999999999Z. So `ToUTCInstant` and `FromUTCInstant`
always succeed.

`FromInstant(odt, t, offset)` adds the offset to give the civil time.
Offsets go to ±25:59:59, so within 26 hours of either end the civil time
can fall outside the years:

| instant | offset | true civil time |
|---|---|---|
| `latest` | +14:00 | 10000-01-01T13:59:59.999999999 |
| `earliest` | -05:00 | -10000-12-31T19:00:00 |

The case that matters in practice is `Instants.latest` used as "never"
or "forever", and then shown in local time through `TimeZones.ToLocal`
or the formatting of steps 2 and 3.

## 2. The options

### 2.1 Saturate, with a checked form

`FromInstant` gives 9999-12-31T23:59:59.999999999 or
-9999-01-01T00:00:00, with the offset asked for.
`CheckedFromInstant(VAR odt; t; offset): BOOLEAN` refuses instead.

- **For:**
  - It is the library's rule for overflow
    ([duration-overflow.md](duration-overflow.md), option 4): the plain
    procedures saturate, and a `Checked` form reports.
  - "Forever" shows as 9999-12-31T23:59:59.999999999 in any zone.
- **Against:**
  - One more procedure.
  - Unlike a saturated `Duration`, which is `min` or `max` and can be
    recognized, the result is an ordinary date-time that names an
    instant up to 26 hours from `t`. `ToInstant(FromInstant(t))` is then
    not `t`.

### 2.2 `FromInstant` returns a `BOOLEAN`, with no saturating form

- **For:**
  - It never gives a wrong answer silently.
  - Python does this. Checked 2026-10-28:
    `datetime.max.replace(tzinfo=timezone.utc).astimezone(timezone(timedelta(hours=1)))`
    raises `OverflowError: date value out of range`. Java's
    `OffsetDateTime.ofInstant` is documented to throw
    `DateTimeException` past its range.
- **Against:**
  - Every caller checks, `ToLocal` and the formatting included, for a
    case that arises only within a day of the year 10000.
  - Printing "forever" in local time fails unless the caller handles it.

### 2.3 `ASSERT`

- **For:**
  - It is simple.
- **Against:**
  - The instant and the offset are both valid. The library keeps
    `ASSERT` for invalid arguments.

### 2.4 Narrow the instants by 26 hours at each end

Every instant then converts at every offset.

- **For:**
  - `FromInstant` cannot fail.
- **Against:**
  - `ToInstant` of a valid `OffsetDateTime` near the ends then falls
    outside the instants instead. Whichever range is wider, one
    direction fails.
  - `ToUTCInstant` and `FromUTCInstant` would no longer be total.

## 3. Why option 1

It follows the rule already decided for overflow, gives "forever" a
natural printed form, and lets a program that needs an exact answer ask
for one. The cost, a result that names the wrong instant, is stated in
`FromInstant`'s comment.

`ToInstant` near the ends is the same problem in the other direction. It
is Q13, settled the same way in
[offset-to-instant.md](offset-to-instant.md).

## 4. What the code does

In `src/Calendar.Mod`:

- `CheckedFromInstant` adds the offset to `t.seconds` and refuses a
  result outside `Instants.earliest.seconds .. Instants.latest.seconds`.
  Its result is left unchanged then.
- `FromInstant` calls it. On failure, a negative offset gives the first
  moment of the years and a positive one the last, since only an offset
  toward an end can carry `t` past it. The offset is kept.
- Both `ASSERT` 23 for an offset beyond ±25:59:59.

`test/CalendarTest.Mod` checks:

- `CheckedFromInstant` on an ordinary instant;
- `latest` at 0 and -01:00, and `earliest` at +01:00, which succeed;
- `latest` at +00:00:01 and `earliest` at -00:00:01, which fail and
  leave the result unchanged;
- `latest` - 25:59:58 at +25:59:58, which reaches
  9999-12-31T23:59:59.999999999 exactly, and the same instant at
  +25:59:59, which fails;
- `FromInstant`'s saturated results, with their offsets.
