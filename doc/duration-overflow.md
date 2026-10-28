# Overflow in duration arithmetic

Written 2026-10-28. This document records the decision on Q4 in
[date-time-design.md](date-time-design.md): what the library's own
procedures do when a duration or an instant does not fit.

**Decision: option 4.** The procedures that return a result saturate. A
checked form with a `BOOLEAN` result is added wherever overflow can come
from input.

## 1. The problem

A `Durations.Duration` is a `HUGEINT` of nanoseconds, so it holds about
±292 years. An `Instants.Instant` is limited to the years -9999..9999.

Overflow can happen in these procedures:

| procedure | how it overflows |
|---|---|
| `Instants.Between`, `Calendar.Difference` | two instants or date-times more than 292 years apart. **This one is easy to hit**, because instants span 20 000 years, and it can come from input: two parsed dates. |
| `Durations.Of`, `Scale`, `Sum`, `Difference` | large arguments |
| `Durations.FromSeconds` | a huge or infinite `LONGREAL` |
| `Durations.Abs` | `ABS(MIN(HUGEINT))` |
| `Instants.Add`, `Subtract` | going past the year -9999 or 9999 |

Readings from `Clocks` never get close.

The plain operators `+`, `-` and `*` on two `Duration`s are ordinary
`HUGEINT` arithmetic and wrap, as poc promises. They are outside this
decision.

## 2. The options

### 2.1 Saturate

The result is clamped to `Durations.min`/`max`, or to
`Instants.earliest`/`latest`. Go's `Time.Sub` and Rust's `saturating_*`
methods work this way.

- **For:**
  - A procedure never traps.
  - The result keeps its sign and order. "Further apart than 292 years"
    is still a very long duration.
  - `max` works naturally as "forever" for a timeout.
- **Against:**
  - The wrong answer is silent.
  - If a saturated value goes back into a plain operator, it wraps.
    `Durations.max + 1` becomes `min`, so the clamp is undone with no
    warning.

### 2.2 `ASSERT`

The procedure stops the program with status 10. This is the nearest
thing Oberon has to Ada's `Constraint_Error`, Java's
`ArithmeticException` from `Duration.plus`, and Python's
`OverflowError`.

- **For:** the failure is loud.
- **Against:**
  - Oberon has no exceptions, so the program cannot recover. It just
    stops.
  - It breaks the design's own rule (design §4.3): a failure that comes
    from input returns `BOOLEAN`, and `ASSERT` is kept for mistakes in
    the program itself. `Between` on two parsed dates fails because of
    its input.

### 2.3 A `BOOLEAN` result on every procedure

For example, `Sum(VAR r: Duration; a, b: Duration): BOOLEAN`.

- **For:** every failure is explicit.
- **Against:** it throws away the reason for making `Duration` a bare
  `HUGEINT`, which is that it can be a function result:
  `Clocks.Since(start)`, or `Between(b, a) > timeout`.

### 2.4 Saturating functions, plus checked forms (chosen)

This follows Rust's pairs of `saturating_*` and `checked_*` methods. The
function forms saturate, as in 2.1. A checked form, with a `BOOLEAN`
result and a `VAR` result, is added only where overflow can come from
input.

- **For:**
  - Durations keep working as function results.
  - It follows design §4.3's rule for failures that come from input.
- **Against:** a few more procedures to write and document.

## 3. What the decision adds

**Checked forms.** Each returns `FALSE` on overflow, and then leaves its
`VAR` result unchanged, as every `BOOLEAN` procedure in the library
does:

```oberon
(* Durations *)
PROCEDURE CheckedScale*(VAR r: Duration; d: Duration; n: HUGEINT): BOOLEAN;
PROCEDURE CheckedFromSeconds*(VAR d: Duration; x: LONGREAL): BOOLEAN;   (* FALSE for NaN and infinities too *)

(* Instants *)
PROCEDURE CheckedBetween*(VAR d: Durations.Duration; later, earlier: Instant): BOOLEAN;

(* Calendar *)
PROCEDURE CheckedDifference*(VAR d: Durations.Duration; later, earlier: DateTime): BOOLEAN;
```

**What stays saturating only:**

- `Sum`, `Difference`, `Of` and `Abs` take durations the program has
  built itself, and anything near ±292 years is a mistake in the
  program.
- `Instants.Add` and `Subtract` are left as they are.

Either of these can gain a checked form later without changing the
saturating one.

**Documentation:** the comment at the head of `Durations` says that a
saturated value is `min` or `max`, and that it must not be fed back
into the plain `+`, `-` or `*`, which wrap.

**Tests:**

- each saturating procedure at and past both limits;
- each checked form returning `FALSE`, with its result unchanged;
- `CheckedBetween` on the earliest and latest instants.
