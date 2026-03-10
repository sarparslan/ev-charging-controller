(* @brief Data sent TO the BMS via CAN3
 *
 *  Consumed by PRG_ChargerCAN_TX for 2 CAN messages:
 *    - BMS Charge Cmd     (0x0CEF2810)  50ms
 *    - BMS Charge Lim     (0x18FF9010)  100ms
 *)
TYPE ST_BmsTx :
STRUCT
    (* Contactor commands *)
    cmdMainPos          : BOOL;
    cmdMainNeg          : BOOL;
    cmdPrecharge        : BOOL;
    cmdAcLine           : BOOL;

    (* Charge control *)
    chargeEnable        : BOOL;
    chargeMode          : E_ChargeMode;
    targetVoltage       : REAL;           (* [V] voltage setpoint *)
    targetCurrent       : REAL;           (* [A] current setpoint *)
    derateFactor        : USINT;          (* [%] thermal derating 0-100 *)
END_STRUCT
END_TYPE
