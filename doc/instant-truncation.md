# Truncating an instant to any unit

Written 2026-10-28. This document records the decision on Q14 in
[date-time-design.md](date-time-design.md): which units
`Instants.Truncate` takes.

**Decision: option 2.** Any positive unit. A unit that neither divides
a second nor is whole seconds has its remainder found from the two
fields, multiplying modulo the unit.

## 1. The problem

The design gives `Truncate(r, t, unit)` as "down to a multiple of
`unit` since 1970", for any unit, as `Durations.Truncate` takes any
positive unit.

An instant is `seconds` and `nanosecond`. As one count of nanoseconds
it needs 69 bits, more than a `HUGEINT`. The first version therefore
took only the two cases where the fields can be worked separately:

- **a unit that divides a second** (1 ns, 1 µs, 1 ms, 250 ms): only
  `nanosecond` changes;
- **a unit of whole seconds** (1 s, 1 min, 90 min, 1 day): only
  `seconds` changes.

Every other positive unit failed `ASSERT` 20:

| unit | why it failed |
|---|---|
| 3 ms, 7 ms, 400 ms | does not divide a second: 1 s / 400 ms = 2.5 |
| 1.5 s, 2.5 s | above a second, not whole seconds |
| 16 666 667 ns | 1/60 s rounded: a frame or tick period |

## 2. The options

### 2.1 Keep the restriction, documented

- **For:**
  - No more arithmetic.
  - Every common unit works.
- **Against:**
  - It traps on reasonable values, and the interface gives no warning.
  - It differs from `Durations.Truncate`, which has the same name.

### 2.2 Any positive unit

The two short paths stay. Otherwise the remainder is

```
((seconds MOD unit) * 10^9 + nanosecond) MOD unit
```

with the product taken modulo `unit` by doubling, and each sum by an
addition that cannot overflow, so that nothing exceeds 64 bits.

- **For:**
  - It does what the design says, and what `Durations.Truncate` does.
  - `ASSERT` 20 is then only for a unit that is not positive, as in
    `Durations`.
  - It can be checked against Python's integers, which have no width.
- **Against:**
  - About 25 more lines, for units that few programs use.

### 2.3 A `BOOLEAN` result instead of a trap

- **Against:**
  - The unit is nearly always a constant. A bad one is a programming
    error, and the library `ASSERT`s on those (design §4). A `BOOLEAN`
    would be a check that callers leave out.

## 3. Why option 2

It is small, it stays inside `Instants`, it can be tested completely,
and it removes a trap that nothing in the interface warned of.

### 3.1 Weeks

"Since 1970" means that `Durations.week` gives Thursdays, since
1970-01-01 was one. A week that starts on Monday, as ISO's does, needs
`Calendar.DayOfWeek` and `AddDays`. The comment on `Truncate` says so.
The same holds for days: `Durations.day` gives midnight UTC, not
midnight in a zone.

## 4. What the code does

In `src/Instants.Mod`:

- `Truncate` takes the short paths when `second MOD unit = 0` or
  `unit MOD second = 0`.
- Otherwise:
  1. `MultiplyModulo(seconds MOD unit, second, unit)` doubles and adds,
     through `AddModulo`, which compares with `m - y` before adding.
  2. `AddModulo` adds the nanosecond, itself taken `MOD unit`.
  3. The remainder is subtracted as seconds and nanoseconds, with a
     borrow.
  4. `Set` clamps a result below `earliest`.
- Floored `MOD` makes the remainder of a negative `seconds`
  non-negative, so the result is always at or before `t`.

`tools/instants-data.py` writes `test/data/InstantsData.Mod`, 960 rows
from Python's integers. It covers:

- **units:** the odd ones above, 1 s ± 1 ns, 1 day + 1 ns, 2^62 + 1,
  `Durations.max`, some random ones, and some that the short paths take;
- **instants:** the ends of the range and the epoch on either side,
  plus random instants, both across the whole range and near 1970.

`test/InstantsTest.Mod` checks every row, and a few cases by hand:

- 7 ms;
- 1.5 s, either side of 1970;
- a unit of 1 day + 1 ns at `earliest`, which clamps;
- `latest` truncated to `Durations.max`.

Two mutations were caught: `AddModulo` as a plain `(x + y) MOD m`, and
the borrow left out.
