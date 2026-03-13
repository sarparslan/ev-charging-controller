(* @brief Thermal management data *)
TYPE ST_ThermalData :
STRUCT
    inletTemp       : INT;                (* [C] coolant inlet temperature *)
    cableTemp       : INT;                (* [C] charge cable temperature *)
    coolantTemp     : INT;                (* [C] coolant loop temperature *)
    derateFactor    : USINT;              (* [%] thermal derating 0=stop, 100=full *)
    coolingMode     : E_CoolingMode;      (* active cooling level *)
END_STRUCT
END_TYPE
