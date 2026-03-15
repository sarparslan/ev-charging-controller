(* @brief Global Variable List — device-centric architecture
 *
 *  Each external device has its own GVL instance with rx/tx separation.
 *  g_charge holds internal session state, g_vcu holds vehicle-level signals.
 *
 *  Data flow:
 *    CAN3 (BMS)  <-->  g_bms.rx / g_bms.tx
 *    CAN4 (EVSE) <-->  g_evse.rx / g_evse.tx
 *    State machine  ->  g_charge (session lifecycle)
 *    Vehicle I/O    ->  g_vcu (pilot, thermal)
 *)
VAR_GLOBAL
    g_bms       : ST_Bms;
    g_evse      : ST_Evse;
    g_charge    : ST_ChargeSession;
    g_vcu       : ST_Vcu;
    g_can3      : BYTE := 3;              (* CAN bus handle — BMS *)
    g_can4      : BYTE := 4;              (* CAN bus handle — EVSE *)
END_VAR

VAR_GLOBAL CONSTANT
    (* ── CAN Message IDs (J1939 extended 29-bit) ── *)

    (* CAN3: BMS -> VCU (RX) *)
    CAN_ID_BMS_PACK_DATA    : DWORD := 16#18FFA028;
    CAN_ID_BMS_CELL_VOLTS   : DWORD := 16#18FFA128;
    CAN_ID_BMS_CELL_TEMPS   : DWORD := 16#18FFA228;
    CAN_ID_BMS_CTR_STATUS   : DWORD := 16#18FFA328;
    CAN_ID_BMS_LIMITS       : DWORD := 16#18FFA428;

    (* CAN3: VCU -> BMS (TX) *)
    CAN_ID_BMS_CHARGE_CMD   : DWORD := 16#0CEF2810;
    CAN_ID_BMS_CHARGE_LIM   : DWORD := 16#18FF9010;

    (* CAN4: EVSE -> VCU (RX) *)
    CAN_ID_EVSE_STATUS      : DWORD := 16#18FF8040;
    CAN_ID_EVSE_METERING    : DWORD := 16#18FF8140;
    CAN_ID_EVSE_PROTOCOL    : DWORD := 16#18FF8240;

    (* CAN4: VCU -> EVSE (TX) *)
    CAN_ID_CHARGE_REQUEST   : DWORD := 16#0CEF4010;
    CAN_ID_CHARGE_PARAMS    : DWORD := 16#0CEF4011;
    CAN_ID_CHARGE_STATUS    : DWORD := 16#18FF7010;

    (* ── Communication Timeouts ── *)
    COMM_BMS_TIMEOUT_MS     : UDINT := 500;
    COMM_EVSE_TIMEOUT_MS    : UDINT := 1000;

    (* ── Alive Counter ── *)
    ALIVE_COUNTER_MAX       : USINT := 255;
END_VAR
