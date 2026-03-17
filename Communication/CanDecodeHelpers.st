(* @brief Raw CAN field -> strict enum conversions
 *
 *  Strict enums cannot be assigned from integers, so each 2-bit field
 *  is mapped explicitly. Unknown codes fall back to the safe value.
 *)
FUNCTION F_ToContactorState : E_ContactorState
VAR_INPUT
    raw : BYTE;       (* 2-bit field, already shifted to bits 1:0 *)
END_VAR
    CASE raw OF
        0: F_ToContactorState := E_ContactorState.CTR_OPEN;
        1: F_ToContactorState := E_ContactorState.CTR_CLOSING;
        2: F_ToContactorState := E_ContactorState.CTR_CLOSED;
    ELSE
        F_ToContactorState := E_ContactorState.CTR_WELDED;
    END_CASE
END_FUNCTION

FUNCTION F_ToChargeProtocol : E_ChargeProtocol
VAR_INPUT
    raw : BYTE;       (* 2-bit field, bits 1:0 *)
END_VAR
    CASE raw OF
        1: F_ToChargeProtocol := E_ChargeProtocol.PROTO_DIN70121;
        2: F_ToChargeProtocol := E_ChargeProtocol.PROTO_ISO15118;
    ELSE
        F_ToChargeProtocol := E_ChargeProtocol.PROTO_UNKNOWN;
    END_CASE
END_FUNCTION
