(* @brief Charge session state — internal to VCU
 *
 *  Holds the current charging session lifecycle data.
 *  Not directly tied to a CAN device; computed by the state machine.
 *)
TYPE ST_ChargeSession :
STRUCT
    (* State machine *)
    state               : E_ChargingState;
    mode                : E_ChargeMode;
    protocol            : E_ChargeProtocol;
    prechargeStep       : E_PrechargeStep;
    vehicleState        : E_VehicleChargeState;

    (* Control flags *)
    ccActive            : BOOL;           (* constant current phase active *)
    cvActive            : BOOL;           (* constant voltage phase active *)
    chargeComplete      : BOOL;           (* session completed normally *)

    (* Setpoints *)
    targetVoltage       : REAL;           (* [V] voltage setpoint *)
    targetCurrent       : REAL;           (* [A] current setpoint *)

    (* Measurements *)
    actualVoltage       : REAL;           (* [V] measured bus voltage *)
    actualCurrent       : REAL;           (* [A] measured charge current *)

    (* Session statistics *)
    startSoc            : USINT;          (* [%] SOC at session start *)
    energyDelivered     : REAL;           (* [kWh] cumulative energy *)
    sessionTime         : UDINT;          (* [ms] elapsed time in ACTIVE *)
END_STRUCT
END_TYPE
