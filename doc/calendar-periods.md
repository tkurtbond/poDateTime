# Adding and measuring calendar periods

Written 2026-10-28. This document records the decision on Q11 in
[date-time-design.md](date-time-design.md): in what order
`Calendar.AddPeriod` applies a period's years, months and days, and how
`Calendar.PeriodBetween` measures one.

**Decision: option 1.** `AddPeriod` adds the years and months together
as one count of months, then the days. `PeriodBetween` counts whole
months, then takes the days from where those months land, in both
directions.

## 1. The problem

The design promises that the two undo each other:

```
AddPeriod(from, PeriodBetween(from, to)) = to
```

Adding months clamps the day to the length of the month reached:
2020-01-31 + 1 month is 2020-02-29. A period can therefore not be added
part by part without losing that promise, and the first draft of the
design said "years, then months, then days".

### 1.1 Clamping twice

When the years and months go in separately, the day can be clamped at
each step:

| start | add | years, then months | months together |
|---|---|---|---|
| 2020-02-29 | 1 year 1 month | 2021-02-28, then **2021-03-28** | 13 months: **2021-03-29** |

`PeriodBetween(2020-02-29, 2021-03-29)` is 1 year 1 month 0 days by any
reasonable count. Added back in sequence, it gives 03-28.

### 1.2 Java's backward periods

The first draft named Java's `Period.between` as the algorithm. Java
counts the months between the two dates, and moves one month back if
the day of `to` is short of the day of `from`.

- **Forward,** it takes the days from `from` plus those months to `to`,
  so the promise holds.
- **Backward,** it subtracts the length of `to`'s month from the
  difference of the days. That misses when the day of `from` would be
  clamped:

| from → to | Java | Java added back | here |
|---|---|---|---|
| 2023-03-31 → 2023-02-28 | -1 month -3 days | 02-28, then **02-25** | -1 month 0 days |
| 2021-03-10 → 2020-01-15 | -1 year -1 month -26 days | correct | the same |

## 2. The options

### 2.1 Months together, then days; one rule both ways

`AddPeriod` adds `years * 12 + months` in one step, then the days.
`PeriodBetween` counts the months, moves one back toward `from` if the
day of `to` is short of it, and takes the days from where `from` plus
those months lands to `to`.

- **For:**
  - The promise holds for every pair of dates.
  - The years, months and days share one sign, and the months stay
    within -11..11.
  - It is Python's `dateutil.relativedelta`, in both directions. Checked
    2026-10-28: 2023-03-31 → 2023-02-28 is `months=-1`, and 2020-02-29 +
    1 year 1 month is 2021-03-29. Java's `Period.addTo` adds the same
    way, by total months.
- **Against:**
  - Near month ends, `AddPeriod` is not `AddYears`, then `AddMonths`,
    then `AddDays`. A program that wants that order calls the three
    itself.

### 2.2 Years, then months, then days, with `PeriodBetween` fitted to it

`PeriodBetween` takes the days from where the separate steps land.

- **For:**
  - The promise holds.
  - `AddPeriod` is exactly the three single steps.
- **Against:**
  - The results are odd: 2020-02-29 → 2021-03-29 is "1 year 1 month
    1 day", because the separate steps reach 03-28.
  - No library in the design's survey does this.

### 2.3 Java exactly

The promise is weakened to forward periods.

- **For:**
  - It can be explained by pointing to Java.
- **Against:**
  - A period measured backward does not always lead back, as with
    03-31 → 02-28 above, and nothing is gained by that.

## 3. Why option 1

It is the only option that keeps the promise and gives natural answers.
`dateutil` behaves the same way, and Java adds periods the same way.

## 4. What the code does

In `src/Calendar.Mod`:

- `AddPeriod` and `SubtractPeriod` both go through `Shift`, which moves
  the date by a count of months and then by a count of days. A result
  outside the years is `FALSE` and leaves the date unchanged.
- `PeriodBetween` does this:
  1. `months` is the difference of `year * 12 + month`.
  2. It moves one toward zero when the day of `to` is short of the day
     of `from`: forward if `to.day < from.day`, backward if `to.day >
     from.day`.
  3. `days` runs from `from` plus `months`, clamped, to `to`.
  4. `months` is split into years and months, toward zero.

`test/CalendarTest.Mod` checks the examples above. It also checks the
promise, the one sign and `ABS(months) <= 11` for 200 000 pseudo-random
pairs of dates, half of them within a few years of each other, where
month ends matter, and half anywhere in -9999..9999.
