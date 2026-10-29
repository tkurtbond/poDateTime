MODULE RealFormat;

  (* What DurationsTest may do with a LONGREAL on the system it runs on
     (design Q25), for LLVM: an IEEE double, with NaNs and infinities.

     No ASSERTs. *)

  CONST
    (* 0/0 gives a NaN and an overflow an infinity, rather than a trap *)
    ieee* = TRUE;

END RealFormat.
