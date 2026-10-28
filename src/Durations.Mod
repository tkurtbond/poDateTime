MODULE Durations;

  (* Elapsed time: a Duration is a HUGEINT of nanoseconds, about +-292
     years (design section 5). Being a bare HUGEINT, it can be a function
     result and a constant (CONST timeout = 30 * Durations.second), and
     + - * DIV < = # work on it.

     The procedures here saturate: a result that does not fit is min or
     max, never wrapped (duration-overflow.md, Q4). A saturated value must
     not be fed back into the plain + - or *, which wrap as poc promises,
     so that max + 1 is min. CheckedScale and CheckedFromSeconds return
     FALSE instead, for overflow that can come from input.

     day and week are elapsed time, 86 400 and 604 800 seconds, not
     calendar days; across a daylight-saving change the two differ.

     ASSERT numbers:
       20  Whole, Truncate, Floor or Round with a unit that is not
           positive *)

  CONST
    nanosecond* = 1;  microsecond* = 1000;  millisecond* = 1000000;
    second* = 1000000000;  minute* = 60 * second;  hour* = 60 * minute;
    day* = 24 * hour;  week* = 7 * day;
    min* = MIN(HUGEINT);  max* = MAX(HUGEINT);

    (* 2^20 and 2^40, for taking a LONGREAL apart without ENTIER, which
       under -O2 holds only 32 bits *)
    two20 = 1048576.0D0;  two40 = 1099511627776.0D0;
    (* the first LONGREAL past max: 2^63 *)
    limit = 9223372036854775808.0D0;

  TYPE Duration* = HUGEINT;

  (* a * b, or FALSE if it does not fit. Floored DIV would let C's usual
     test miss by one, so each case is set up for a quotient that floors
     the right way, and MIN DIV -1, which poc does not check, is never
     computed. *)
  PROCEDURE Multiply(VAR r: HUGEINT; a, b: HUGEINT): BOOLEAN;
    VAR fits: BOOLEAN;
  BEGIN
    IF (a = 0) OR (b = 0) THEN fits := TRUE
    ELSIF a > 0 THEN
      IF b > 0 THEN fits := a <= max DIV b
      ELSE fits := (b = -1) OR (a <= min DIV b)
      END
    ELSIF b > 0 THEN fits := (a = -1) OR (b <= min DIV a)
    ELSE fits := (b # min) & (a >= -(max DIV (-b)))
    END;
    IF fits THEN r := a * b END;
    RETURN fits
  END Multiply;

  (* a * b, saturated to the sign of the true product *)
  PROCEDURE SaturatingProduct(a, b: HUGEINT): HUGEINT;
    VAR r: HUGEINT;
  BEGIN
    IF ~Multiply(r, a, b) THEN
      IF (a < 0) = (b < 0) THEN r := max ELSE r := min END
    END;
    RETURN r
  END SaturatingProduct;

  PROCEDURE Sum*(a, b: Duration): Duration;
    VAR r: Duration;
  BEGIN
    IF (b > 0) & (a > max - b) THEN r := max
    ELSIF (b < 0) & (a < min - b) THEN r := min
    ELSE r := a + b
    END;
    RETURN r
  END Sum;

  PROCEDURE Difference*(a, b: Duration): Duration;
    VAR r: Duration;
  BEGIN
    IF (b < 0) & (a > max + b) THEN r := max
    ELSIF (b > 0) & (a < min + b) THEN r := min
    ELSE r := a - b
    END;
    RETURN r
  END Difference;

  PROCEDURE Of*(days, hours, minutes, seconds, nanoseconds: HUGEINT): Duration;
  BEGIN
    RETURN Sum(Sum(Sum(Sum(SaturatingProduct(days, day), SaturatingProduct(hours, hour)),
      SaturatingProduct(minutes, minute)), SaturatingProduct(seconds, second)), nanoseconds)
  END Of;

  PROCEDURE Scale*(d: Duration; n: HUGEINT): Duration;
  BEGIN
    RETURN SaturatingProduct(d, n)
  END Scale;

  PROCEDURE CheckedScale*(VAR r: Duration; d: Duration; n: HUGEINT): BOOLEAN;
  BEGIN
    RETURN Multiply(r, d, n)
  END CheckedScale;

  PROCEDURE Abs*(d: Duration): Duration;
  BEGIN
    IF d = min THEN d := max ELSIF d < 0 THEN d := -d END;
    RETURN d
  END Abs;

  (* d / unit, toward zero *)
  PROCEDURE Whole*(d, unit: Duration): HUGEINT;
    VAR q: HUGEINT;
  BEGIN
    ASSERT(unit > 0, 20);
    q := d DIV unit;
    IF (q < 0) & (d MOD unit # 0) THEN INC(q) END;
    RETURN q
  END Whole;

  (* toward zero, to a multiple of unit; the result is no further from 0
     than d, so it always fits *)
  PROCEDURE Truncate*(d, unit: Duration): Duration;
  BEGIN
    RETURN Whole(d, unit) * unit
  END Truncate;

  (* toward minus infinity; saturates near min, where the multiple below d
     does not exist *)
  PROCEDURE Floor*(d, unit: Duration): Duration;
  BEGIN
    ASSERT(unit > 0, 20);
    RETURN Difference(d, d MOD unit)
  END Floor;

  (* to the nearest multiple of unit, half away from zero *)
  PROCEDURE Round*(d, unit: Duration): Duration;
    VAR t, rest: Duration;
  BEGIN
    t := Truncate(d, unit);
    rest := Abs(d - t);
    (* rest >= unit - rest, not 2 * rest >= unit, which can overflow *)
    IF rest >= unit - rest THEN
      IF d < 0 THEN t := Difference(t, unit) ELSE t := Sum(t, unit) END
    END;
    RETURN t
  END Round;

  (* ABS(d) in parts. MIN(HUGEINT) has no ABS, so a negative d is taken
     apart as it is and the parts negated, which always fit. *)
  PROCEDURE Split*(d: Duration; VAR negative: BOOLEAN;
                   VAR days, hours, minutes, seconds, nanoseconds: LONGINT);
    VAR whole, part: HUGEINT;
  BEGIN
    negative := d < 0;
    whole := Whole(d, second);
    part := d - whole * second;
    IF negative THEN whole := -whole; part := -part END;
    nanoseconds := SHORT(part);
    seconds := SHORT(whole MOD 60);  whole := whole DIV 60;
    minutes := SHORT(whole MOD 60);  whole := whole DIV 60;
    hours := SHORT(whole MOD 24);
    days := SHORT(whole DIV 24)
  END Split;

  (* whole seconds and the rest apart, so that a long duration keeps its
     nanoseconds as far as a LONGREAL can *)
  PROCEDURE ToSeconds*(d: Duration): LONGREAL;
    VAR whole, part: LONGREAL;
  BEGIN
    whole := d DIV second;  part := d MOD second;
    RETURN whole + part / second
  END ToSeconds;

  (* x, a whole number with ABS(x) < 2^63, as a HUGEINT, in three pieces
     of at most 23, 20 and 20 bits *)
  PROCEDURE Entier(x: LONGREAL): HUGEINT;
    VAR high, middle, low: HUGEINT; rest: LONGREAL;
  BEGIN
    high := ENTIER(x / two40);
    rest := x - high * two40;
    middle := ENTIER(rest / two20);
    low := ENTIER(rest - middle * two20);
    RETURN (high * 1048576 + middle) * 1048576 + low
  END Entier;

  PROCEDURE CheckedFromSeconds*(VAR d: Duration; x: LONGREAL): BOOLEAN;
    VAR y: LONGREAL; ok: BOOLEAN;
  BEGIN
    y := x * second;
    (* half away from zero; x # x is a NaN, which no comparison passes *)
    IF y >= 0 THEN y := y + 0.5D0 ELSE y := y - 0.5D0 END;
    ok := (x = x) & (y > -limit - 1024.0D0) & (y < limit);
    IF ok THEN
      IF y >= 0 THEN d := Entier(y)
      (* -limit itself is MIN(HUGEINT), which Entier cannot negate *)
      ELSIF y <= -limit THEN d := min
      ELSE d := -Entier(-y)
      END
    END;
    RETURN ok
  END CheckedFromSeconds;

  PROCEDURE FromSeconds*(x: LONGREAL): Duration;
    VAR d: Duration;
  BEGIN
    IF ~CheckedFromSeconds(d, x) THEN
      IF x # x THEN d := 0 ELSIF x > 0 THEN d := max ELSE d := min END
    END;
    RETURN d
  END FromSeconds;

END Durations.
