# Offset date-times near the ends of the instants

Written 2026-10-28. This document records the decision on Q13 in
[date-time-design.md](date-time-design.md): what `Calendar.ToInstant`
does when the offset carries a valid `OffsetDateTime` outside the
instants. It is the converse of Q12,
[instant-offsets.md](instant-offsets.md).

**Decision: option 1.** `ToInstant` saturates, as before. A new
`CheckedToInstant` returns `FALSE` and leaves its result unchanged.
`Format.ReadInstant`, `TimeZones.ToInstant` and `TimeZones.Resolve` use
the checked form.

## 1. The problem

The instants cover exactly the civil years read as UTC (Q12). An
`OffsetDateTime` is valid when its fields are within the years and its
offset within ±25:59:59. Taking away the offset can then leave the
instants:

| `OffsetDateTime` | true instant |
|---|---|
| -9999-01-01T00:00:00+01:00 | -10000-12-31T23:00:00Z, an hour before `earliest` |
| 9999-12-31T23:00:00-05:00 | 10000-01-01T04:00:00Z, past `latest` |

`ToInstant` went through `Instants.FromUnix`, which clamps, and said
nothing. `ToUTCInstant` cannot meet this, since an offset of 0 always
fits.

### 1.1 How it differs from Q12

- **The saturated value is recognizable.** In Q12 it is an ordinary
  date-time that names another instant. Here it is `Instants.earliest`
  or `Instants.latest`, which `Instants.Add` already saturates to, and
  which a program uses for "never" or "forever": like a `Duration`'s
  `min` and `max`.
- **Some callers must not clamp.** A reader of strings should refuse a
  time it cannot hold. A `Format.ReadInstant` that went through a clamping
  `ToInstant` would accept "-9999-01-01T00:00:00+01:00" as `earliest`.
  `TimeZones.ToInstant(z, dt, choice, VAR t): BOOLEAN` already reports
  failure, and should report this one. So steps 2 and 3 need the
  checked form; in Q12 it is there for completeness.
- **Python** is no guide. Checked 2026-10-28: `datetime.min` at +01:00
  raises `OverflowError` from `astimezone(timezone.utc)`, but its
  `timestamp()` returns -62135600400.0.

## 2. The options

### 2.1 Saturate, with a checked form

`ToInstant` gives `earliest` or `latest`.
`CheckedToInstant(VAR t; odt): BOOLEAN` refuses instead.

- **For:**
  - It is the rule of Q4 and Q12: the plain procedure saturates, a
    `Checked` form reports.
  - The saturated value is the recognizable `earliest` or `latest`.
  - `ReadInstant` and `TimeZones.ToInstant` refuse what they should.
- **Against:**
  - One more procedure.
  - At the ends, `FromInstant(ToInstant(odt), odt.offset)` is not
    `odt`: -9999-01-01T00:00+01:00 comes back as 01:00+01:00.

### 2.2 `ToInstant` returns a `BOOLEAN`, with no saturating form

- **For:**
  - Nothing is clamped silently.
- **Against:**
  - It breaks the pairing of Q12.
  - Every caller checks, for inputs found only in the first or last day
    of 20 000 years.

### 2.3 Narrow `ValidOffsetDateTime`

An `OffsetDateTime` is valid only if it names an instant. `ToInstant`
then cannot fail, and `ASSERT`s 23 on anything else.

- **For:**
  - Validity means "names a moment".
  - No new procedure.
- **Against:**
  - Validity depends on the fields and the offset together: a program
    can set each to a legal value and trap.
  - `AddDays` on an `OffsetDateTime`, through a `VAR Date`, can make a
    valid value invalid without noticing.
  - `ReadInstant` still needs the check.

### 2.4 Widen the instants by 26 hours at each end

`ToInstant` then cannot fail.

- **Against:**
  - It undoes Q12's reasoning: `FromInstant` fails more often, and
    `FromUTCInstant`, which cannot fail now, could.
  - `earliest` and `latest` would no longer print as -9999-01-01 and
    9999-12-31 in UTC.

## 3. Why option 1

It is the same rule as Q12, and here its saturated value misleads less.
The checked form has real callers, and the design names them, so that
steps 2 and 3 use it.

## 4. What the code does

In `src/Calendar.Mod`:

- `CheckedToInstant` takes the offset from the civil time read as UTC,
  and refuses a result outside `Instants.earliest.seconds ..
  Instants.latest.seconds`. Its result is left unchanged then.
- `ToInstant` still goes through `Instants.FromUnix`, which clamps to
  the same limits.
- Both `ASSERT` 23 for an invalid `OffsetDateTime`.

`test/CalendarTest.Mod` checks:

- `CheckedToInstant` on an ordinary date-time;
- -9999-01-01T00:00+01:00, which `ToInstant` saturates to `earliest`
  and `CheckedToInstant` refuses, leaving its result unchanged;
- -9999-01-01T01:00+01:00, which is `earliest` exactly, and
  -9999-01-01T00:00-25:59:59;
- 9999-12-31T23:59:59.999999999 at -00:00:01, which saturates to
  `latest` and is refused, at 00:00, which is `latest` exactly, and at
  +25:59:59.
