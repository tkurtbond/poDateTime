MODULE RealFormat;

  (* What DurationsTest may do with a LONGREAL on the system it runs on
     (design Q25), for the VAX: G_floating, which has no NaN and no
     infinity; 0/0 and an overflow trap.

     No ASSERTs. *)

  CONST
    (* 0/0 gives a NaN and an overflow an infinity, rather than a trap *)
    ieee* = FALSE;

END RealFormat.
