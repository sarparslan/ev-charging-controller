(* @brief Data sent TO the EVSE via CAN4
 *
 *  Consumed by PRG_ChargerCAN_TX for 3 CAN messages:
 *    - Charge Request     (0x0CEF4010)  100ms
 *    - Charge Params      (0x0CEF4011)  100ms
 *    - Charge Status      (0x18FF7010)  250ms
 *)
TYPE ST_EvseTx :
STRUCT
    (* Charge request *)
    state               : E_ChargingState;
    mode                : E_ChargeMode;
    aliveCounter        : USINT;
    chargeEnable        : BOOL;
    emergencyStop       : BOOL;

    (* Charge parameters *)
    targetVoltage       : REAL;           (* [V] requested voltage *)
    targetCurrent       : REAL;           (* [A] requested current *)
    ccCvFlag            : USINT;          (* 0x01=CC, 0x02=CV *)
    soc                 : USINT;          (* [%] battery SOC for EVSE display *)

    (* Vehicle status *)
    vehicleState        : E_VehicleChargeState;
    prechargeStep       : E_PrechargeStep;
    parkingBrake        : BOOL;
    ignitionOn          : BOOL;
    chargeComplete      : BOOL;
END_STRUCT
END_TYPE
