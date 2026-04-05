(* @brief Main charging session state machine
 *
 *  Implements the full charge session lifecycle from cable insertion
 *  through energy transfer to safe disconnect.  Runs as a PROGRAM
 *  on the CycleCharge task (10 ms period).
 *
 *  Data sources:
 *    g_bms.rx    — battery measurements and contactor feedback
 *    g_evse.rx   — charger status and metering
 *    g_vcu       — control pilot, vehicle inputs, thermal
 *
 *  Data outputs:
 *    g_charge    — session state (state, mode, targets, energy)
 *    g_bms.tx    — contactor commands, charge enable, limits
 *    g_evse.tx   — charge request, parameters, vehicle status
 *
 *  State flow:
 *    IDLE -> CONNECTED -> NEGOTIATE -> ISOLATE -> PRECHARGE
 *         -> ACTIVE -> RAMPDOWN -> WELD_CHECK -> COMPLETE
 *
 *  Losing the BMS or EVSE link in any state from NEGOTIATE onward
 *  (except COMPLETE) aborts the session.
 *
 *  Precharge sub-states:
 *    PRE_CLOSE_NEG -> PRE_RELAY_ENGAGE -> PRE_VOLTAGE_WAIT
 *         -> PRE_VOLTAGE_OK -> PRE_CLOSE_POS -> PRE_RELAY_RELEASE
 *         -> PRE_COMPLETE | PRE_TIMEOUT
 *
 *  References:
 *    IEC 61851-1   Control Pilot states
 *    DIN 70121     DC charging communication
 *    ISO 15118     Plug & Charge
 *)
PROGRAM PRG_ChargingStateMachine
VAR
    prevState       : E_ChargingState;
    stateEntryTime  : UDINT;       (* timestamp when current state was entered [ms] *)
    preEntryTime    : UDINT;       (* timestamp for precharge sub-state entry [ms] *)
    rampStartCurrent: REAL;        (* current at rampdown entry [A] *)

    voltageDelta    : REAL;        (* |bus - pack| for precharge check [V] *)
    currentLimit    : REAL;        (* effective current request [A] *)
    dtSeconds       : REAL;        (* cycle time in seconds for energy calc *)

    prevEnergy      : REAL;        (* energy accumulator carry-over [kWh] *)
END_VAR

(* ──────────────────────────────────────────────────────────────
   Timestamp update — always runs first
   ────────────────────────────────────────────────────────────── *)
g_vcu.systemTime := T_PLC_MS();

(* ──────────────────────────────────────────────────────────────
   State entry detection — reset entry timer on every transition
   ────────────────────────────────────────────────────────────── *)
IF g_charge.state <> prevState THEN
    stateEntryTime := g_vcu.systemTime;
    prevState      := g_charge.state;
END_IF

(* ──────────────────────────────────────────────────────────────
   Communication loss — abort any session that has left CONNECTED
   ────────────────────────────────────────────────────────────── *)
IF g_charge.state <> E_ChargingState.CHARGE_IDLE
   AND g_charge.state <> E_ChargingState.CHARGE_CONNECTED
   AND g_charge.state <> E_ChargingState.CHARGE_COMPLETE
   AND g_charge.state <> E_ChargingState.CHARGE_ABORT
   AND (NOT g_bms.commOk OR NOT g_evse.commOk) THEN
    g_charge.state := E_ChargingState.CHARGE_ABORT;
END_IF

(* ══════════════════════════════════════════════════════════════
   MAIN STATE MACHINE
   ══════════════════════════════════════════════════════════════ *)
CASE g_charge.state OF

(* ─────────────────────── IDLE ─────────────────────── *)
E_ChargingState.CHARGE_IDLE:

    (* All outputs safe *)
    g_bms.tx.cmdMainPos   := FALSE;
    g_bms.tx.cmdMainNeg   := FALSE;
    g_bms.tx.cmdPrecharge := FALSE;
    g_bms.tx.cmdAcLine    := FALSE;
    g_bms.tx.chargeEnable := FALSE;
    g_charge.ccActive        := FALSE;
    g_charge.cvActive        := FALSE;
    g_charge.chargeComplete  := FALSE;
    g_charge.vehicleState    := E_VehicleChargeState.VCS_STANDBY;
    g_charge.prechargeStep   := E_PrechargeStep.PRE_IDLE;

    (* Transition: cable connected, parking brake engaged, no latched weld *)
    IF g_vcu.pilot.cpState = E_ControlPilot.CP_STATE_B
       AND g_vcu.parkingBrake
       AND NOT g_bms.rx.weldDetected THEN
        g_charge.vehicleState := E_VehicleChargeState.VCS_PLUG_DETECTED;
        g_charge.state := E_ChargingState.CHARGE_CONNECTED;
    END_IF


(* ─────────────────── CONNECTED ────────────────────── *)
E_ChargingState.CHARGE_CONNECTED:

    g_charge.vehicleState := E_VehicleChargeState.VCS_LOCK_ENGAGED;

    (* Wait for CP state C (vehicle ready) + both comms alive *)
    IF g_vcu.pilot.cpState = E_ControlPilot.CP_STATE_C
       AND g_bms.commOk
       AND g_evse.commOk THEN
        g_charge.vehicleState := E_VehicleChargeState.VCS_CHARGE_READY;
        g_charge.state := E_ChargingState.CHARGE_NEGOTIATE;
    END_IF

    (* Cable removed -> back to idle *)
    IF g_vcu.pilot.cpState = E_ControlPilot.CP_STATE_A THEN
        g_charge.state := E_ChargingState.CHARGE_IDLE;
    END_IF


(* ─────────────────── NEGOTIATE ────────────────────── *)
E_ChargingState.CHARGE_NEGOTIATE:

    (* Latch protocol from EVSE *)
    g_charge.protocol := g_evse.rx.protocol;

    (* Determine charge mode from protocol + EVSE capabilities *)
    IF g_evse.rx.maxVoltage > 0.0 AND g_evse.rx.maxCurrent > 0.0 THEN
        IF g_evse.rx.maxVoltage >= CHARGE_VOLTAGE_MIN THEN
            g_charge.mode := E_ChargeMode.MODE_DC;
        ELSE
            g_charge.mode := E_ChargeMode.MODE_AC;
        END_IF
    END_IF

    (* Calculate initial target voltage from pack voltage *)
    g_charge.targetVoltage := g_bms.rx.packVoltage;

    (* Record start SOC *)
    g_charge.startSoc := g_bms.rx.soc;

    (* Reset energy counter *)
    g_charge.energyDelivered := 0.0;
    g_charge.sessionTime := 0;
    prevEnergy := 0.0;

    (* Transition when mode is determined and EVSE is available *)
    IF g_charge.mode <> E_ChargeMode.MODE_NONE
       AND g_evse.rx.available
       AND g_bms.commOk THEN
        g_charge.state := E_ChargingState.CHARGE_ISOLATE;
    END_IF

    (* Negotiation timeout: 10 seconds *)
    IF (g_vcu.systemTime - stateEntryTime) > 10000 THEN
        g_charge.state := E_ChargingState.CHARGE_ABORT;
    END_IF


(* ─────────────────── ISOLATE ──────────────────────── *)
E_ChargingState.CHARGE_ISOLATE:

    (* Wait for EVSE to report valid insulation test *)
    IF g_evse.rx.isolationValid THEN
        IF g_charge.mode = E_ChargeMode.MODE_DC THEN
            (* DC: enter precharge sequence *)
            g_charge.prechargeStep := E_PrechargeStep.PRE_CLOSE_NEG;
            preEntryTime := g_vcu.systemTime;
            g_charge.state := E_ChargingState.CHARGE_PRECHARGE;
        ELSE
            (* AC: skip precharge, go directly to active *)
            g_bms.tx.cmdAcLine := TRUE;
            g_charge.state := E_ChargingState.CHARGE_ACTIVE;
        END_IF
    END_IF

    (* Isolation timeout: 30 seconds *)
    IF (g_vcu.systemTime - stateEntryTime) > 30000 THEN
        g_charge.state := E_ChargingState.CHARGE_ABORT;
    END_IF


(* ─────────────────── PRECHARGE ────────────────────── *)
E_ChargingState.CHARGE_PRECHARGE:

    (* DC precharge sub-state machine *)
    CASE g_charge.prechargeStep OF

        E_PrechargeStep.PRE_CLOSE_NEG:
            g_bms.tx.cmdMainNeg := TRUE;
            IF g_bms.rx.fbkMainNeg = E_ContactorState.CTR_CLOSED THEN
                g_charge.prechargeStep := E_PrechargeStep.PRE_RELAY_ENGAGE;
                preEntryTime := g_vcu.systemTime;
            END_IF

        E_PrechargeStep.PRE_RELAY_ENGAGE:
            g_bms.tx.cmdPrecharge := TRUE;
            IF g_bms.rx.fbkPrecharge = E_ContactorState.CTR_CLOSED THEN
                g_charge.prechargeStep := E_PrechargeStep.PRE_VOLTAGE_WAIT;
                preEntryTime := g_vcu.systemTime;
            END_IF

        E_PrechargeStep.PRE_VOLTAGE_WAIT:
            (* Monitor bus voltage vs pack voltage *)
            g_charge.actualVoltage := g_evse.rx.presentVoltage;
            voltageDelta := g_bms.rx.packVoltage - g_charge.actualVoltage;
            IF voltageDelta < 0.0 THEN
                voltageDelta := -voltageDelta;  (* ABS equivalent *)
            END_IF

            IF voltageDelta <= PRECHARGE_TOLERANCE_V THEN
                g_charge.prechargeStep := E_PrechargeStep.PRE_VOLTAGE_OK;
                preEntryTime := g_vcu.systemTime;
            END_IF

        E_PrechargeStep.PRE_VOLTAGE_OK:
            (* Re-check voltage after 50ms settle to confirm stable match *)
            IF (g_vcu.systemTime - preEntryTime) > CTR_CLOSE_DELAY_MS THEN
                g_charge.actualVoltage := g_evse.rx.presentVoltage;
                voltageDelta := g_bms.rx.packVoltage - g_charge.actualVoltage;
                IF voltageDelta < 0.0 THEN
                    voltageDelta := -voltageDelta;
                END_IF

                IF voltageDelta <= PRECHARGE_TOLERANCE_V THEN
                    g_charge.prechargeStep := E_PrechargeStep.PRE_CLOSE_POS;
                ELSE
                    (* Voltage drifted — return to monitoring *)
                    g_charge.prechargeStep := E_PrechargeStep.PRE_VOLTAGE_WAIT;
                END_IF
                preEntryTime := g_vcu.systemTime;
            END_IF

        E_PrechargeStep.PRE_CLOSE_POS:
            g_bms.tx.cmdMainPos := TRUE;
            IF g_bms.rx.fbkMainPos = E_ContactorState.CTR_CLOSED THEN
                g_charge.prechargeStep := E_PrechargeStep.PRE_RELAY_RELEASE;
                preEntryTime := g_vcu.systemTime;
            END_IF

        E_PrechargeStep.PRE_RELAY_RELEASE:
            (* Open precharge relay — main path now carries current *)
            g_bms.tx.cmdPrecharge := FALSE;
            IF g_bms.rx.fbkPrecharge = E_ContactorState.CTR_OPEN THEN
                g_charge.prechargeStep := E_PrechargeStep.PRE_COMPLETE;
            END_IF

        E_PrechargeStep.PRE_COMPLETE:
            (* Precharge done — enter active charging *)
            g_charge.state := E_ChargingState.CHARGE_ACTIVE;

    END_CASE

    (* Global precharge timeout: 5 seconds *)
    IF (g_vcu.systemTime - stateEntryTime) > PRECHARGE_TIMEOUT_MS THEN
        g_charge.prechargeStep := E_PrechargeStep.PRE_TIMEOUT;
        g_charge.state := E_ChargingState.CHARGE_ABORT;
    END_IF


(* ─────────────────── ACTIVE ───────────────────────── *)
E_ChargingState.CHARGE_ACTIVE:

    (* Set vehicle state based on mode *)
    IF g_charge.mode = E_ChargeMode.MODE_DC THEN
        g_charge.vehicleState := E_VehicleChargeState.VCS_CHARGING_DC;
    ELSE
        g_charge.vehicleState := E_VehicleChargeState.VCS_CHARGING_AC;
    END_IF

    (* Enable charge on BMS side *)
    g_bms.tx.chargeEnable := TRUE;
    g_bms.tx.chargeMode   := g_charge.mode;

    (* ── Current limit = MIN(BMS allowed, EVSE max, mode max) ── *)
    (* Recomputed every cycle so CV also follows BMS, EVSE and thermal limits *)
    currentLimit := g_bms.rx.maxChargeCurrent;

    IF g_charge.mode = E_ChargeMode.MODE_DC THEN
        IF currentLimit > CHARGE_DC_CURRENT_MAX THEN
            currentLimit := CHARGE_DC_CURRENT_MAX;
        END_IF
    ELSE
        IF currentLimit > CHARGE_AC_CURRENT_MAX THEN
            currentLimit := CHARGE_AC_CURRENT_MAX;
        END_IF
    END_IF

    IF currentLimit > g_evse.rx.maxCurrent THEN
        currentLimit := g_evse.rx.maxCurrent;
    END_IF

    (* Apply thermal derating *)
    currentLimit := currentLimit * USINT_TO_REAL(g_vcu.thermal.derateFactor) / 100.0;

    (* ── CC-CV control logic ── *)
    (* Phase 1: Constant Current — charge at max rate until cell voltage threshold *)
    IF g_bms.rx.cellVoltageMax < CHARGE_CELL_MV_MAX THEN
        g_charge.ccActive := TRUE;
        g_charge.cvActive := FALSE;

        g_charge.targetCurrent := currentLimit;
        g_charge.targetVoltage := g_bms.rx.packVoltage;

    (* Phase 2: Constant Voltage — hold voltage, taper current *)
    ELSE
        g_charge.ccActive := FALSE;
        g_charge.cvActive := TRUE;

        g_charge.targetVoltage := CHARGE_VOLTAGE_MAX;
        (* Current naturally tapers as cells reach full voltage *)
        g_charge.targetCurrent := currentLimit;
    END_IF

    (* ── Actual measurement tracking ── *)
    g_charge.actualVoltage := g_evse.rx.presentVoltage;
    g_charge.actualCurrent := g_evse.rx.presentCurrent;

    (* ── Energy accumulation: P = V * I, E += P * dt ── *)
    dtSeconds := 0.010;  (* 10ms cycle *)
    g_charge.energyDelivered := prevEnergy
        + (g_charge.actualVoltage
           * g_charge.actualCurrent
           * dtSeconds / 3600000.0);     (* W*s -> kWh *)
    prevEnergy := g_charge.energyDelivered;

    (* ── Session timer ── *)
    g_charge.sessionTime := g_vcu.systemTime - stateEntryTime;

    (* ── Charge completion conditions ── *)
    (* SOC target reached *)
    IF g_bms.rx.soc >= SOC_CHARGE_COMPLETE THEN
        g_charge.chargeComplete := TRUE;
        g_charge.state := E_ChargingState.CHARGE_RAMPDOWN;
    END_IF

    (* CV taper current below threshold *)
    IF g_charge.cvActive
       AND g_charge.actualCurrent <= CHARGE_CV_TAPER_A
       AND g_charge.actualCurrent > 0.0 THEN
        g_charge.chargeComplete := TRUE;
        g_charge.state := E_ChargingState.CHARGE_RAMPDOWN;
    END_IF

    (* Cell over-voltage hard cutoff *)
    IF g_bms.rx.cellVoltageMax >= CHARGE_CELL_MV_ABS_MAX THEN
        g_charge.state := E_ChargingState.CHARGE_RAMPDOWN;
    END_IF


(* ─────────────────── RAMPDOWN ─────────────────────── *)
E_ChargingState.CHARGE_RAMPDOWN:

    g_charge.vehicleState := E_VehicleChargeState.VCS_CHARGE_ENDING;

    (* Linear current ramp-down over 2 seconds *)
    IF rampStartCurrent <= 0.0 THEN
        rampStartCurrent := g_charge.targetCurrent;
    END_IF

    IF rampStartCurrent > 0.0 THEN
        g_charge.targetCurrent := rampStartCurrent
            * (1.0 - UDINT_TO_REAL(g_vcu.systemTime - stateEntryTime) / 2000.0);

        IF g_charge.targetCurrent < 0.0 THEN
            g_charge.targetCurrent := 0.0;
        END_IF
    END_IF

    (* Transition when current reaches zero or 2s elapsed *)
    IF g_charge.targetCurrent <= 0.0
       OR (g_vcu.systemTime - stateEntryTime) > 2000 THEN
        g_charge.targetCurrent := 0.0;
        g_charge.state := E_ChargingState.CHARGE_WELD_CHECK;
        rampStartCurrent := 0.0;
    END_IF


(* ──────────────── WELD_CHECK ──────────────────────── *)
E_ChargingState.CHARGE_WELD_CHECK:

    (* Open all contactors *)
    g_bms.tx.cmdMainPos   := FALSE;
    g_bms.tx.cmdMainNeg   := FALSE;
    g_bms.tx.cmdPrecharge := FALSE;
    g_bms.tx.cmdAcLine    := FALSE;
    g_bms.tx.chargeEnable := FALSE;

    (* Wait for weld detection window *)
    IF (g_vcu.systemTime - stateEntryTime) > CTR_WELD_CHECK_MS THEN
        IF g_bms.rx.weldDetected THEN
            (* Weld found -> abort with contactor fault *)
            g_charge.state := E_ChargingState.CHARGE_ABORT;
        ELSE
            g_charge.state := E_ChargingState.CHARGE_COMPLETE;
        END_IF
    END_IF


(* ─────────────────── COMPLETE ─────────────────────── *)
E_ChargingState.CHARGE_COMPLETE:

    g_charge.vehicleState := E_VehicleChargeState.VCS_CHARGE_ENDING;
    g_charge.targetCurrent := 0.0;
    g_charge.targetVoltage := 0.0;
    g_charge.ccActive := FALSE;
    g_charge.cvActive := FALSE;
    g_bms.tx.chargeEnable := FALSE;

    (* Wait for cable removal to return to idle *)
    IF g_vcu.pilot.cpState = E_ControlPilot.CP_STATE_A THEN
        g_charge.state := E_ChargingState.CHARGE_IDLE;
    END_IF


(* ─────────────────── ABORT ────────────────────────── *)
E_ChargingState.CHARGE_ABORT:

    (* Immediate safe state: open all contactors *)
    g_bms.tx.cmdMainPos   := FALSE;
    g_bms.tx.cmdMainNeg   := FALSE;
    g_bms.tx.cmdPrecharge := FALSE;
    g_bms.tx.cmdAcLine    := FALSE;
    g_bms.tx.chargeEnable := FALSE;

    g_charge.targetCurrent := 0.0;
    g_charge.targetVoltage := 0.0;
    g_charge.ccActive := FALSE;
    g_charge.cvActive := FALSE;
    g_charge.vehicleState := E_VehicleChargeState.VCS_FAULT;

    (* Return to idle once cable is removed *)
    IF g_vcu.pilot.cpState = E_ControlPilot.CP_STATE_A THEN
        g_charge.state := E_ChargingState.CHARGE_IDLE;
    END_IF

END_CASE

(* ══════════════════════════════════════════════════════════════
   TX STRUCT SYNCHRONIZATION
   Copy session data to TX structs so CAN TX can read them.
   ══════════════════════════════════════════════════════════════ *)

(* BMS TX: targets + derate *)
g_bms.tx.targetVoltage := g_charge.targetVoltage;
g_bms.tx.targetCurrent := g_charge.targetCurrent;
g_bms.tx.derateFactor  := g_vcu.thermal.derateFactor;

(* EVSE TX: charge request fields *)
g_evse.tx.state         := g_charge.state;
g_evse.tx.mode          := g_charge.mode;
g_evse.tx.chargeEnable  := g_bms.tx.chargeEnable;
g_evse.tx.emergencyStop := (g_charge.state = E_ChargingState.CHARGE_ABORT);

(* EVSE TX: charge params *)
g_evse.tx.targetVoltage := g_charge.targetVoltage;
g_evse.tx.targetCurrent := g_charge.targetCurrent;
IF g_charge.ccActive THEN
    g_evse.tx.ccCvFlag := 16#01;
ELSIF g_charge.cvActive THEN
    g_evse.tx.ccCvFlag := 16#02;
ELSE
    g_evse.tx.ccCvFlag := 16#00;
END_IF
g_evse.tx.soc := g_bms.rx.soc;

(* EVSE TX: vehicle status *)
g_evse.tx.vehicleState    := g_charge.vehicleState;
g_evse.tx.prechargeStep   := g_charge.prechargeStep;
g_evse.tx.parkingBrake    := g_vcu.parkingBrake;
g_evse.tx.ignitionOn      := g_vcu.ignitionOn;
g_evse.tx.chargeComplete  := g_charge.chargeComplete;

END_PROGRAM
