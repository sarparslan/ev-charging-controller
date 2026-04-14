(* @brief DC charge control — voltage and current regulation
 *
 *  Manages the DC charging interface between VCU and EVSE.
 *  Reads battery limits from BMS, applies safety constraints,
 *  and outputs regulated voltage/current requests to the EVSE.
 *
 *  Only active when g_charge.state = CHARGE_ACTIVE
 *  and g_charge.mode = MODE_DC.
 *
 *  Runs as a PROGRAM on CycleCharge task (10 ms period).
 *)
PROGRAM PRG_DCChargeControl
VAR
    voltageRequest  : REAL;
    currentRequest  : REAL;
    dcEnabled       : BOOL;
END_VAR

(* Only run when DC charging is active *)
dcEnabled := (g_charge.state = E_ChargingState.CHARGE_ACTIVE)
         AND (g_charge.mode = E_ChargeMode.MODE_DC);

IF NOT dcEnabled THEN
    RETURN;
END_IF

(* ── Voltage regulation ── *)
(* CC phase: track pack voltage *)
(* CV phase: hold at max voltage *)
IF g_charge.ccActive THEN
    voltageRequest := g_bms.rx.packVoltage;
ELSE
    voltageRequest := CHARGE_VOLTAGE_MAX;
END_IF

(* Clamp to EVSE capability *)
IF voltageRequest > g_evse.rx.maxVoltage THEN
    voltageRequest := g_evse.rx.maxVoltage;
END_IF

(* ── Current regulation ── *)
currentRequest := g_bms.rx.maxChargeCurrent;

(* Apply mode limit *)
IF currentRequest > CHARGE_DC_CURRENT_MAX THEN
    currentRequest := CHARGE_DC_CURRENT_MAX;
END_IF

(* Apply EVSE limit *)
IF currentRequest > g_evse.rx.maxCurrent THEN
    currentRequest := g_evse.rx.maxCurrent;
END_IF

(* Apply thermal derating *)
currentRequest := currentRequest
    * USINT_TO_REAL(g_vcu.thermal.derateFactor) / 100.0;

(* CV phase: let current taper naturally *)
IF g_charge.cvActive AND (currentRequest > g_charge.actualCurrent) THEN
    currentRequest := g_charge.actualCurrent;
END_IF

(* ── Output to charge session ── *)
g_charge.targetVoltage := voltageRequest;
g_charge.targetCurrent := currentRequest;

END_PROGRAM
