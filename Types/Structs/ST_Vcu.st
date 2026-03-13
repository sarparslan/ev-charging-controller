(* @brief VCU-level signals — vehicle and system data
 *
 *  Internal signals not tied to a specific CAN device.
 *  Includes control pilot, vehicle inputs, and thermal management.
 *)
TYPE ST_Vcu :
STRUCT
    (* System *)
    systemTime          : UDINT;          (* [ms] PLC system time *)

    (* Control Pilot — IEC 61851-1 *)
    pilot               : ST_ControlPilot;

    (* Vehicle inputs *)
    parkingBrake        : BOOL;
    ignitionOn          : BOOL;

    (* Thermal management *)
    thermal             : ST_ThermalData;
END_STRUCT
END_TYPE
