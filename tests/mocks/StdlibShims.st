(* @brief Conversions common PLC runtimes provide but the RuSTy stdlib lacks
 *
 *  TO_BYTE usually accepts any integer (and enum); RuSTy resolves
 *  enum and mixed-width arguments to DINT and has no DINT overload.
 *)
FUNCTION TO_BYTE__DINT : BYTE
VAR_INPUT
    in : DINT;
END_VAR
    TO_BYTE__DINT := DINT_TO_BYTE(in);
END_FUNCTION
