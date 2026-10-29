MODULE ZoneFiles;

  (* What TimeZonesTest needs of the system it runs on (design Q24), for
     VMS. The zone files are written into the default directory first,
     from test/data/ZoneFilesData.Mod, since a binary file copied by FTP
     comes out padded to 512-byte records; each is named as
     tools/zone-files-data.py names it, FAT_NEW_YORK.TZIF for fat's
     America/New_York. VMS has no zone database (Q6), so Named and the
     system's are not checked, and Local is the TZ logical name's rule,
     which the run defines as New York's since 2007.

     No ASSERTs. *)

  IMPORT Files, ZoneFilesData;

  CONST
    (* Named, /usr/share/zoneinfo, and Local the fat America/New_York *)
    database* = FALSE;
    (* the first instant at which Local is New York's: 2007-01-01T00:00Z *)
    localSince* = 1167609600;

  VAR
    current: ARRAY 64 OF CHAR;
    file: Files.File;
    rider: Files.Rider;

  (* form's zone's file: "fat" and "America/New_York" give
     FAT_NEW_YORK.TZIF *)
  PROCEDURE Path*(form, zone: ARRAY OF CHAR; VAR path: ARRAY OF CHAR);
    VAR i, n, last: LONGINT;

    PROCEDURE Add(s: ARRAY OF CHAR; from: LONGINT);
      VAR ch: CHAR;
    BEGIN
      i := from;
      WHILE (s[i] # 0X) & (n < LEN(path) - 1) DO
        ch := CAP(s[i]);
        IF ch = "-" THEN ch := "_" END;
        path[n] := ch;  INC(n);  INC(i)
      END;
      path[n] := 0X
    END Add;

  BEGIN
    last := 0;  i := 0;
    WHILE zone[i] # 0X DO
      IF zone[i] = "/" THEN last := i + 1 END;
      INC(i)
    END;
    n := 0;  Add(form, 0);  Add("_", 0);  Add(zone, last);  Add(".TZIF", 0)
  END Path;

  PROCEDURE Digit(ch: CHAR): INTEGER;
  BEGIN
    IF ch >= "a" THEN RETURN ORD(ch) - ORD("a") + 10 ELSE RETURN ORD(ch) - ORD("0") END
  END Digit;

  PROCEDURE Close;
  BEGIN
    IF file # NIL THEN Files.Register(file);  Files.Close(file);  file := NIL END
  END Close;

  PROCEDURE Piece(name, hex: ARRAY OF CHAR);
    VAR i: LONGINT;
  BEGIN
    IF current # name THEN
      Close;  COPY(name, current);
      file := Files.New(name);  Files.Set(rider, file, 0)
    END;
    i := 0;
    WHILE hex[i] # 0X DO
      Files.Write(rider, CHR(Digit(hex[i]) * 16 + Digit(hex[i + 1])));  INC(i, 2)
    END
  END Piece;

  (* writes the zone files *)
  PROCEDURE Prepare*;
  BEGIN
    current := "";  file := NIL;
    ZoneFilesData.Each(Piece);
    Close
  END Prepare;

END ZoneFiles.
