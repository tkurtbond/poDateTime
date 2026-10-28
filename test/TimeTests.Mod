MODULE TimeTests;

  (* What the test programs share: checks that print only when they fail,
     and a last line with the count, which the expected output holds, so
     that a check that silently stops running is noticed too.

     ASSERT numbers: none *)

  IMPORT Out;

  VAR name: ARRAY 32 OF CHAR;  checks, failures: LONGINT;

  PROCEDURE Start*(module: ARRAY OF CHAR);
  BEGIN
    COPY(module, name);  checks := 0;  failures := 0
  END Start;

  PROCEDURE Fail(label: ARRAY OF CHAR);
  BEGIN
    INC(failures);
    Out.String("FAIL ");  Out.String(label)
  END Fail;

  PROCEDURE True*(label: ARRAY OF CHAR; ok: BOOLEAN);
  BEGIN
    INC(checks);
    IF ~ok THEN Fail(label);  Out.Ln END
  END True;

  PROCEDURE Int*(label: ARRAY OF CHAR; got, expected: HUGEINT);
  BEGIN
    INC(checks);
    IF got # expected THEN
      Fail(label);  Out.String(": got ");  Out.Int(got, 0);
      Out.String(", expected ");  Out.Int(expected, 0);  Out.Ln
    END
  END Int;

  (* for checks run in a loop, counted as one *)
  PROCEDURE Count*(n: LONGINT);
  BEGIN
    INC(checks, n)
  END Count;

  PROCEDURE Failed*(label: ARRAY OF CHAR; a, b, c: HUGEINT);
  BEGIN
    Fail(label);  Out.String(": ");  Out.Int(a, 0);  Out.Char(" ");
    Out.Int(b, 0);  Out.Char(" ");  Out.Int(c, 0);  Out.Ln
  END Failed;

  PROCEDURE Finish*;
  BEGIN
    Out.String(name);  Out.String(": ");  Out.Int(checks, 0);
    IF failures = 0 THEN Out.String(" checks passed")
    ELSE Out.String(" checks, ");  Out.Int(failures, 0);  Out.String(" failed")
    END;
    Out.Ln;
    IF failures # 0 THEN HALT(1) END
  END Finish;

END TimeTests.
