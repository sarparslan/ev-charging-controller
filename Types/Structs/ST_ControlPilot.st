(* @brief IEC 61851-1 Control Pilot signal data *)
TYPE ST_ControlPilot :
STRUCT
    cpState         : E_ControlPilot;     (* current CP state A-F *)
    cpDuty          : REAL;               (* [%] PWM duty cycle 0-100 *)
    proximityState  : E_ProximityState;   (* plug proximity detection *)
END_STRUCT
END_TYPE
