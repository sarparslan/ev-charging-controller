(* @brief AC charge control — single-phase onboard charger interface
 *
 *  Manages AC charging by setting current limits for the onboard
 *  charger (OBC).  Voltage regulation is handled by the OBC itself;
 *  the VCU only controls the AC current setpoint.
 *
 *  Only active when g_charge.state = CHARGE_ACTIVE
 *  and g_charge.mode = MODE_AC.
 *
 *  Runs as a PROGRAM on CycleCharge task (10 ms period).
 *)
PROGRAM PRG_ACChargeControl
VAR
    currentRequest  : REAL;
    acEnabled       : BOOL;
END_VAR

(* Only run when AC charging is active *)
acEnabled := (g_charge.state = E_ChargingState.CHARGE_ACTIVE)
         AND (g_charge.mode = E_ChargeMode.MODE_AC);

IF NOT acEnabled THEN
    RETURN;
END_IF

(* ── Current regulation ── *)
currentRequest := g_bms.rx.maxChargeCurrent;

(* Apply mode limit *)
IF currentRequest > CHARGE_AC_CURRENT_MAX THEN
    currentRequest := CHARGE_AC_CURRENT_MAX;
END_IF

(* Apply EVSE limit — pilot signal advertised current *)
IF currentRequest > g_evse.rx.maxCurrent THEN
    currentRequest := g_evse.rx.maxCurrent;
END_IF

(* Apply thermal derating *)
currentRequest := currentRequest
    * USINT_TO_REAL(g_vcu.thermal.derateFactor) / 100.0;

(* ── Voltage: OBC handles regulation, we just pass pack voltage ── *)
g_charge.targetVoltage := g_bms.rx.packVoltage;
g_charge.targetCurrent := currentRequest;

END_PROGRAM
