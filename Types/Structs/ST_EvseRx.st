(* @brief Data received FROM the EVSE via CAN4
 *
 *  Populated by PRG_ChargerCAN_RX from 3 CAN messages:
 *    - EVSE Status       (0x18FF8040)
 *    - EVSE Metering     (0x18FF8140)
 *    - EVSE Protocol     (0x18FF8240)
 *)
TYPE ST_EvseRx :
STRUCT
    (* Status *)
    available           : BOOL;           (* EVSE ready to charge *)
    isolationValid      : BOOL;           (* insulation test passed *)

    (* Capability *)
    maxVoltage          : REAL;           (* [V] EVSE max output voltage *)
    maxCurrent          : REAL;           (* [A] EVSE max output current *)

    (* Live metering *)
    presentVoltage      : REAL;           (* [V] measured bus voltage *)
    presentCurrent      : REAL;           (* [A] measured charge current *)

    (* Protocol *)
    protocol            : E_ChargeProtocol;
END_STRUCT
END_TYPE
