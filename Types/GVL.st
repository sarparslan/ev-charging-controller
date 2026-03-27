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

    (* ── Charging Limits ── *)
    CHARGE_VOLTAGE_MIN      : REAL := 200.0;    (* [V] min DC voltage for mode detect *)
    CHARGE_VOLTAGE_MAX      : REAL := 420.0;    (* [V] max pack voltage *)
    CHARGE_DC_CURRENT_MAX   : REAL := 200.0;    (* [A] max DC charge current *)
    CHARGE_AC_CURRENT_MAX   : REAL := 32.0;     (* [A] max AC charge current *)
    CHARGE_CELL_MV_MAX      : UINT := 4150;     (* [mV] CC->CV transition threshold *)
    CHARGE_CELL_MV_ABS_MAX  : UINT := 4200;     (* [mV] hard cutoff per cell *)
    CHARGE_CV_TAPER_A       : REAL := 2.0;      (* [A] CV completion threshold *)
    SOC_CHARGE_COMPLETE     : USINT := 100;     (* [%] SOC completion target *)

    (* ── Precharge Parameters ── *)
    PRECHARGE_TOLERANCE_V   : REAL := 10.0;     (* [V] max |bus - pack| delta *)
    PRECHARGE_TIMEOUT_MS    : UDINT := 5000;    (* [ms] global precharge timeout *)

    (* ── Contactor Timing ── *)
    CTR_CLOSE_DELAY_MS      : UDINT := 50;      (* [ms] settle time after voltage match *)
    CTR_WELD_CHECK_MS       : UDINT := 200;     (* [ms] weld detection window *)
    CTR_FEEDBACK_TIMEOUT_MS : UDINT := 150;     (* [ms] max time for contactor response *)

    (* ── Alive Counter ── *)
    ALIVE_COUNTER_MAX       : USINT := 255;
END_VAR
