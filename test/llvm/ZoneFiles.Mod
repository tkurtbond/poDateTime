MODULE ZoneFiles;

  (* What TimeZonesTest needs of the system it runs on (design Q24), for
     Unix: the zone files where they are checked in, under
     test/data/zoneinfo/; Named and the system's own database; and the
     local zone the fat America/New_York, which the makefile names in TZ.

     No ASSERTs. *)

  CONST
    (* Named, /usr/share/zoneinfo, and Local the fat America/New_York *)
    database* = TRUE;
    (* the first instant at which Local is New York's *)
    localSince* = MIN(HUGEINT);

  (* the path of form's zone, such as "fat" and "America/New_York" *)
  PROCEDURE Path*(form, zone: ARRAY OF CHAR; VAR path: ARRAY OF CHAR);
    VAR i, n: LONGINT;

    PROCEDURE Add(s: ARRAY OF CHAR);
    BEGIN
      i := 0;
      WHILE (s[i] # 0X) & (n < LEN(path) - 1) DO path[n] := s[i];  INC(n);  INC(i) END;
      path[n] := 0X
    END Add;

  BEGIN
    n := 0;  Add("test/data/zoneinfo/");  Add(form);  Add("/");  Add(zone)
  END Path;

  (* the files are there already *)
  PROCEDURE Prepare*;
  END Prepare;

END ZoneFiles.
