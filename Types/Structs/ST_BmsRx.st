(* @brief Data received FROM the BMS via CAN3
 *
 *  Populated by PRG_ChargerCAN_RX from 5 CAN messages:
 *    - BMS Pack Data      (0x18FFA028)
 *    - BMS Cell Volts     (0x18FFA128)
 *    - BMS Cell Temps     (0x18FFA228)
 *    - BMS Contactor Fbk  (0x18FFA328)
 *    - BMS Limits         (0x18FFA428)
 *)
TYPE ST_BmsRx :
STRUCT
    (* Pack-level measurements *)
    packVoltage         : REAL;           (* [V] total pack voltage *)
    packCurrent         : REAL;           (* [A] pack current, + = charge *)
    soc                 : USINT;          (* [%] state of charge 0-100 *)
    soh                 : USINT;          (* [%] state of health 0-100 *)

    (* Cell-level measurements *)
    cellVoltageMin      : UINT;           (* [mV] lowest cell voltage *)
    cellVoltageMax      : UINT;           (* [mV] highest cell voltage *)
    cellTempMin         : INT;            (* [C] coldest cell *)
    cellTempMax         : INT;            (* [C] hottest cell *)

    (* Thermal sensors *)
    inletTemp           : INT;            (* [C] coolant inlet *)
    cableTemp           : INT;            (* [C] charge cable *)
    coolantTemp         : INT;            (* [C] coolant loop *)

    (* Contactor feedback from BMS *)
    fbkMainPos          : E_ContactorState;
    fbkMainNeg          : E_ContactorState;
    fbkPrecharge        : E_ContactorState;
    fbkAcLine           : E_ContactorState;
    contactorClosed     : BOOL;           (* summary: main path closed *)
    weldDetected        : BOOL;           (* contactor weld detected — latched until power cycle *)

    (* Charge limits *)
    maxChargeCurrent    : REAL;           (* [A] max allowed charge current *)
    maxDischargeCurrent : REAL;           (* [A] max allowed discharge current *)
END_STRUCT
END_TYPE
