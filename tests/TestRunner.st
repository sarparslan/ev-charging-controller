(* @brief Off-target scenario tests for the charging controller
 *
 *  Runs the real controller programs cycle by cycle against a simulated
 *  BMS and EVSE. The simulator talks to the VCU only through CAN frames:
 *  it injects RX frames and reads contactor commands back from the
 *  transmitted BMS charge command, so the CAN codecs are exercised too.
 *
 *  Build and run: tests/run.sh
 *)

{external}
FUNCTION printf : DINT
VAR_INPUT {ref}
    format : STRING;
END_VAR
VAR_INPUT
    args : ...;
END_VAR
END_FUNCTION

VAR_GLOBAL
    (* ── Test bookkeeping ── *)
    g_testsRun    : DINT;
    g_testsFailed : DINT;

    (* ── Simulated BMS / EVSE ── *)
    g_simBmsAlive   : BOOL := TRUE;
    g_simEvseAlive  : BOOL := TRUE;
    g_simPackV      : REAL := 380.0;
    g_simBusV       : REAL;
    g_simSoc        : USINT := 40;
    g_simCellMaxMv  : UINT := 3900;
    g_simBmsMaxI    : REAL := 150.0;
    g_simEvseMaxV   : REAL := 500.0;
    g_simEvseMaxI   : REAL := 125.0;
    g_simEvseAvail  : BOOL := TRUE;
    g_simIsolation  : BOOL := TRUE;
    g_simBusBlocked : BOOL;            (* precharge never raises bus voltage *)
    g_simK1Stuck    : BOOL;            (* K1 welded: stays closed once closed *)

    (* contactor feedback as the BMS reports it *)
    g_simK1 : BOOL;
    g_simK2 : BOOL;
    g_simK3 : BOOL;
    g_simAc : BOOL;

    (* order of contactor events: 1/2/3 = K1/K2/K3 closed, -1/-2/-3 = opened *)
    g_simSeq    : ARRAY[0..15] OF INT;
    g_simSeqLen : INT;
END_VAR

(* ══════════════════════════════════════════════════════════════
   Assertion helpers
   ══════════════════════════════════════════════════════════════ *)
FUNCTION Check : BOOL
VAR_INPUT
    cond : BOOL;
    name : STRING[120];
END_VAR
    g_testsRun := g_testsRun + 1;
    IF cond THEN
        printf('  PASS  %s$N', REF(name));
    ELSE
        g_testsFailed := g_testsFailed + 1;
        printf('  FAIL  %s$N', REF(name));
    END_IF
    Check := cond;
END_FUNCTION

FUNCTION Section : BOOL
VAR_INPUT
    name : STRING[120];
END_VAR
    printf('$N%s$N', REF(name));
    Section := TRUE;
END_FUNCTION

FUNCTION Near : BOOL
VAR_INPUT
    a, b, tol : REAL;
END_VAR
    Near := (a - b) <= tol AND (b - a) <= tol;
END_FUNCTION

(* ══════════════════════════════════════════════════════════════
   Simulated CAN bus access
   ══════════════════════════════════════════════════════════════ *)
FUNCTION SimPush : BOOL
VAR_INPUT
    id : DWORD;
    d  : ARRAY[0..7] OF BYTE;
END_VAR
VAR
    i, slot : INT := -1;
END_VAR
    slot := -1;
    FOR i := 0 TO 15 DO
        IF slot < 0 AND (g_simRx[i].id = id OR g_simRx[i].id = 0) THEN
            slot := i;
        END_IF
    END_FOR
    g_simRx[slot].id := id;
    g_simRx[slot].data := d;
    g_simRx[slot].pending := TRUE;
    SimPush := TRUE;
END_FUNCTION

FUNCTION SimTxByte : BYTE
VAR_INPUT
    id  : DWORD;
    idx : INT;
END_VAR
VAR
    i : INT;
END_VAR
    SimTxByte := 0;
    FOR i := 0 TO 15 DO
        IF g_simTx[i].count > 0 AND g_simTx[i].id = id THEN
            SimTxByte := g_simTx[i].data[idx];
        END_IF
    END_FOR
END_FUNCTION

FUNCTION Lo : BYTE
VAR_INPUT x : UINT; END_VAR
    Lo := UINT_TO_BYTE(x AND 16#FF);
END_FUNCTION

FUNCTION Hi : BYTE
VAR_INPUT x : UINT; END_VAR
    Hi := UINT_TO_BYTE(SHR(x, 8));
END_FUNCTION

FUNCTION Ctr : BYTE
VAR_INPUT closed : BOOL; END_VAR
    IF closed THEN Ctr := 2; ELSE Ctr := 0; END_IF   (* CTR_CLOSED / CTR_OPEN *)
END_FUNCTION

FUNCTION SeqAdd : BOOL
VAR_INPUT code : INT; END_VAR
    IF g_simSeqLen <= 15 THEN
        g_simSeq[g_simSeqLen] := code;
        g_simSeqLen := g_simSeqLen + 1;
    END_IF
    SeqAdd := TRUE;
END_FUNCTION

(* ══════════════════════════════════════════════════════════════
   BMS / EVSE model — one 10 ms step
   ══════════════════════════════════════════════════════════════ *)
FUNCTION SimDevices : BOOL
VAR
    d     : ARRAY[0..7] OF BYTE;
    cmd   : BYTE;
    k1, k2, k3, ac : BOOL;
    current : REAL;
END_VAR
    (* Contactor commands as transmitted by the VCU (BMS charge command) *)
    cmd := SimTxByte(CAN_ID_BMS_CHARGE_CMD, 0);
    k1 := (cmd AND 16#01) <> 0;
    k2 := (cmd AND 16#02) <> 0;
    k3 := (cmd AND 16#04) <> 0;
    ac := (cmd AND 16#08) <> 0;
    IF g_simK1Stuck AND g_simK1 THEN
        k1 := TRUE;
    END_IF

    IF k1 <> g_simK1 THEN IF k1 THEN SeqAdd(1); ELSE SeqAdd(-1); END_IF END_IF
    IF k2 <> g_simK2 THEN IF k2 THEN SeqAdd(2); ELSE SeqAdd(-2); END_IF END_IF
    IF k3 <> g_simK3 THEN IF k3 THEN SeqAdd(3); ELSE SeqAdd(-3); END_IF END_IF
    g_simK1 := k1; g_simK2 := k2; g_simK3 := k3; g_simAc := ac;

    (* HV bus charges through K3 (slow) or K1 (fast) once K2 is closed *)
    IF g_simK2 AND g_simK1 THEN
        g_simBusV := g_simPackV;
    ELSIF g_simK2 AND g_simK3 AND NOT g_simBusBlocked THEN
        g_simBusV := g_simBusV + (g_simPackV - g_simBusV) * 0.2;
    ELSIF NOT g_simK2 THEN
        g_simBusV := g_simBusV * 0.8;
    END_IF

    current := 0.0;
    IF g_simK1 AND g_simK2 AND g_charge.state = E_ChargingState.CHARGE_ACTIVE THEN
        current := g_charge.targetCurrent;
    END_IF

    IF g_simBmsAlive THEN
        d[0] := Lo(REAL_TO_UINT(g_simPackV * 10.0));  d[1] := Hi(REAL_TO_UINT(g_simPackV * 10.0));
        d[2] := Lo(REAL_TO_UINT((current + 3200.0) * 10.0));
        d[3] := Hi(REAL_TO_UINT((current + 3200.0) * 10.0));
        d[4] := g_simSoc;  d[5] := 98;  d[6] := 0;  d[7] := 0;
        SimPush(CAN_ID_BMS_PACK_DATA, d);

        d[0] := Lo(3800);  d[1] := Hi(3800);
        d[2] := Lo(g_simCellMaxMv);  d[3] := Hi(g_simCellMaxMv);
        d[4] := 0; d[5] := 0;
        SimPush(CAN_ID_BMS_CELL_VOLTS, d);

        d[0] := 60; d[1] := 67; d[2] := 65; d[3] := 70; d[4] := 62;   (* 20..30 C *)
        SimPush(CAN_ID_BMS_CELL_TEMPS, d);

        d[0] := Ctr(g_simK1) OR SHL(Ctr(g_simK2), 2) OR SHL(Ctr(g_simK3), 4) OR SHL(Ctr(g_simAc), 6);
        d[1] := 0;
        IF g_simK1 AND g_simK2 THEN d[1] := 16#01; END_IF
        d[2] := 0; d[3] := 0; d[4] := 0;
        SimPush(CAN_ID_BMS_CTR_STATUS, d);

        d[0] := Lo(REAL_TO_UINT(g_simBmsMaxI * 10.0));  d[1] := Hi(REAL_TO_UINT(g_simBmsMaxI * 10.0));
        d[2] := Lo(2000);  d[3] := Hi(2000);
        SimPush(CAN_ID_BMS_LIMITS, d);
    END_IF

    IF g_simEvseAlive THEN
        d[0] := 0;
        IF g_simEvseAvail THEN d[0] := d[0] OR 16#01; END_IF
        IF g_simIsolation THEN d[0] := d[0] OR 16#02; END_IF
        d[1] := Lo(REAL_TO_UINT(g_simEvseMaxV * 10.0));  d[2] := Hi(REAL_TO_UINT(g_simEvseMaxV * 10.0));
        d[3] := Lo(REAL_TO_UINT(g_simEvseMaxI * 10.0));  d[4] := Hi(REAL_TO_UINT(g_simEvseMaxI * 10.0));
        SimPush(CAN_ID_EVSE_STATUS, d);

        d[0] := Lo(REAL_TO_UINT(g_simBusV * 10.0));  d[1] := Hi(REAL_TO_UINT(g_simBusV * 10.0));
        d[2] := Lo(REAL_TO_UINT(current * 10.0));    d[3] := Hi(REAL_TO_UINT(current * 10.0));
        d[4] := 0;
        SimPush(CAN_ID_EVSE_METERING, d);

        d[0] := 2;   (* ISO 15118 *)
        d[1] := 0; d[2] := 0; d[3] := 0;
        SimPush(CAN_ID_EVSE_PROTOCOL, d);
    END_IF
    SimDevices := TRUE;
END_FUNCTION

(* One controller cycle: devices, then CycleCharge and CycleSafety tasks *)
FUNCTION Cycle : BOOL
    g_simTimeMs := g_simTimeMs + 10;
    SimDevices();
    PRG_ChargerCAN_RX();
    PRG_ChargingStateMachine();
    PRG_DCChargeControl();
    PRG_ACChargeControl();
    PRG_ChargerCAN_TX();
    PRG_ContactorControl();
    Cycle := TRUE;
END_FUNCTION

FUNCTION Run : BOOL
VAR_INPUT ms : UDINT; END_VAR
VAR i : UDINT; END_VAR
    FOR i := 1 TO ms / 10 DO
        Cycle();
    END_FOR
    Run := TRUE;
END_FUNCTION

(* Run until the session reaches a state, up to a time limit *)
FUNCTION RunUntil : BOOL
VAR_INPUT
    target : E_ChargingState;
    maxMs  : UDINT;
END_VAR
VAR i : UDINT; END_VAR
    FOR i := 1 TO maxMs / 10 DO
        IF g_charge.state = target THEN
            RunUntil := TRUE;
            RETURN;
        END_IF
        Cycle();
    END_FOR
    RunUntil := g_charge.state = target;
END_FUNCTION

(* Nominal plant, cable unplugged, session back in IDLE *)
FUNCTION ResetScenario : BOOL
    g_simBmsAlive := TRUE;   g_simEvseAlive := TRUE;
    g_simPackV := 380.0;     g_simSoc := 40;          g_simCellMaxMv := 3900;
    g_simBmsMaxI := 150.0;   g_simEvseMaxV := 500.0;  g_simEvseMaxI := 125.0;
    g_simEvseAvail := TRUE;  g_simIsolation := TRUE;
    g_simBusBlocked := FALSE; g_simK1Stuck := FALSE;
    g_charge.pauseRequest := FALSE;
    g_vcu.thermal.derateFactor := 100;
    g_vcu.parkingBrake := TRUE;
    g_vcu.pilot.cpState := E_ControlPilot.CP_STATE_A;
    RunUntil(E_ChargingState.CHARGE_IDLE, 10000);
    Run(100);
    g_simSeqLen := 0;
    ResetScenario := TRUE;
END_FUNCTION

(* Plug in and let the vehicle request charge *)
FUNCTION PlugIn : BOOL
    g_vcu.pilot.cpState := E_ControlPilot.CP_STATE_B;
    Run(50);
    g_vcu.pilot.cpState := E_ControlPilot.CP_STATE_C;
    PlugIn := TRUE;
END_FUNCTION

(* ══════════════════════════════════════════════════════════════
   Scenarios
   ══════════════════════════════════════════════════════════════ *)
FUNCTION TestCanDecoding : BOOL
    Section('CAN RX decoding');
    ResetScenario();
    Run(50);
    Check(Near(g_bms.rx.packVoltage, 380.0, 0.05), 'pack voltage decoded at 0.1 V/bit');
    Check(Near(g_bms.rx.packCurrent, 0.0, 0.05), 'pack current decoded with -3200 A offset');
    Check(g_bms.rx.cellTempMax = 27, 'cell temperature decoded with -40 C offset');
    Check(g_bms.rx.cellVoltageMax = 3900, 'cell voltage max decoded in mV');
    Check(Near(g_evse.rx.maxCurrent, 125.0, 0.05), 'EVSE max current decoded');
    Check(g_evse.rx.protocol = E_ChargeProtocol.PROTO_ISO15118, 'EVSE protocol mapped to strict enum');
    Check(g_bms.commOk AND g_evse.commOk, 'both links report alive');
END_FUNCTION

FUNCTION TestDcSession : BOOL
VAR
    seqOk : BOOL;
END_VAR
    Section('DC session: plug-in to complete');
    ResetScenario();
    PlugIn();
    Check(RunUntil(E_ChargingState.CHARGE_PRECHARGE, 2000), 'reaches PRECHARGE');
    Check(g_charge.mode = E_ChargeMode.MODE_DC, 'EVSE above 200 V selects DC mode');
    Check(RunUntil(E_ChargingState.CHARGE_ACTIVE, 5000), 'precharge completes into ACTIVE');
    seqOk := g_simSeqLen >= 4
             AND g_simSeq[0] = 2 AND g_simSeq[1] = 3
             AND g_simSeq[2] = 1 AND g_simSeq[3] = -3;
    Check(seqOk, 'contactor order K2 -> K3 -> K1 -> open K3');
    Run(2000);
    Check(g_charge.ccActive AND g_charge.targetCurrent > 100.0, 'CC phase requests high current');
    Check(g_charge.energyDelivered > 0.0, 'energy accumulates while charging');
    g_simSoc := 100;
    Check(RunUntil(E_ChargingState.CHARGE_COMPLETE, 5000), 'SOC target ramps down to COMPLETE');
    Check(g_charge.chargeComplete, 'chargeComplete flag set');
    Check(NOT g_bms.tx.cmdMainPos AND NOT g_bms.tx.cmdMainNeg AND NOT g_bms.tx.cmdPrecharge,
          'all contactors commanded open');
    g_vcu.pilot.cpState := E_ControlPilot.CP_STATE_A;
    Check(RunUntil(E_ChargingState.CHARGE_IDLE, 500), 'unplug returns to IDLE');
END_FUNCTION

FUNCTION TestAcSession : BOOL
    Section('AC session');
    ResetScenario();
    g_simEvseMaxV := 150.0;
    g_simEvseMaxI := 48.0;
    PlugIn();
    Check(RunUntil(E_ChargingState.CHARGE_ACTIVE, 2000), 'reaches ACTIVE');
    Check(g_charge.mode = E_ChargeMode.MODE_AC, 'EVSE below 200 V selects AC mode');
    Check(g_simSeqLen = 0, 'no DC contactor activity');
    Run(200);
    Check(g_bms.tx.cmdAcLine, 'AC line contactor commanded');
    Check(g_charge.targetCurrent <= 32.0 + 0.01, 'current clamped to 32 A AC limit');
END_FUNCTION

FUNCTION TestCvFollowsLimits : BOOL
    Section('CV phase follows BMS limit');
    ResetScenario();
    PlugIn();
    RunUntil(E_ChargingState.CHARGE_ACTIVE, 5000);
    Run(500);
    g_simCellMaxMv := 4160;
    Run(200);
    Check(g_charge.cvActive, 'cell above 4150 mV switches to CV');
    g_simBmsMaxI := 20.0;
    Run(200);
    Check(g_charge.targetCurrent <= 20.0 + 0.01, 'CV current request drops with BMS limit');
    g_simCellMaxMv := 4200;
    Check(RunUntil(E_ChargingState.CHARGE_RAMPDOWN, 200), '4200 mV hard cutoff ramps down');
END_FUNCTION

FUNCTION TestPauseResume : BOOL
VAR
    tPaused : UDINT;
END_VAR
    Section('Pause and resume');
    ResetScenario();
    PlugIn();
    RunUntil(E_ChargingState.CHARGE_ACTIVE, 5000);
    Run(1000);
    g_charge.pauseRequest := TRUE;
    Check(RunUntil(E_ChargingState.CHARGE_PAUSED, 100), 'pauseRequest enters PAUSED');
    Run(100);
    tPaused := g_charge.sessionTime;
    Check(g_charge.targetCurrent = 0.0, 'current request is zero while paused');
    Check(g_bms.tx.cmdMainPos AND g_bms.tx.cmdMainNeg, 'contactors held closed while paused');
    Run(3000);
    Check(g_charge.sessionTime = tPaused, 'session time frozen while paused');
    g_charge.pauseRequest := FALSE;
    Check(RunUntil(E_ChargingState.CHARGE_ACTIVE, 100), 'clearing the request resumes ACTIVE');
    Run(500);
    Check(g_charge.sessionTime > tPaused AND g_charge.sessionTime < tPaused + 1000,
          'session time continues from before the pause');
    g_charge.pauseRequest := TRUE;
    RunUntil(E_ChargingState.CHARGE_PAUSED, 100);
    g_vcu.pilot.cpState := E_ControlPilot.CP_STATE_A;
    Check(RunUntil(E_ChargingState.CHARGE_COMPLETE, 3000), 'unplug while paused ramps down to COMPLETE');
    Check(NOT g_bms.tx.cmdMainPos, 'contactors opened after unplug while paused');
END_FUNCTION

FUNCTION TestCommLossInPrecharge : BOOL
    Section('BMS link lost during precharge');
    ResetScenario();
    PlugIn();
    RunUntil(E_ChargingState.CHARGE_PRECHARGE, 2000);
    g_simBmsAlive := FALSE;
    Check(RunUntil(E_ChargingState.CHARGE_ABORT, 1000), 'aborts within 1 s, before the 5 s precharge timeout');
    Run(20);
    Check(NOT g_bms.tx.cmdMainNeg AND NOT g_bms.tx.cmdPrecharge, 'contactors commanded open');
    Check((SimTxByte(CAN_ID_CHARGE_REQUEST, 2) AND 16#02) <> 0, 'emergency stop sent to EVSE');
END_FUNCTION

FUNCTION TestCommLossWhileCharging : BOOL
    Section('EVSE link lost while charging');
    ResetScenario();
    PlugIn();
    RunUntil(E_ChargingState.CHARGE_ACTIVE, 5000);
    Run(500);
    g_simEvseAlive := FALSE;
    Check(RunUntil(E_ChargingState.CHARGE_ABORT, 1500), 'aborts after the 1000 ms EVSE watchdog');
END_FUNCTION

FUNCTION TestTimeouts : BOOL
    Section('Timeouts');
    ResetScenario();
    g_simEvseAvail := FALSE;
    PlugIn();
    Check(RunUntil(E_ChargingState.CHARGE_NEGOTIATE, 500), 'enters NEGOTIATE');
    Run(9000);
    Check(g_charge.state = E_ChargingState.CHARGE_NEGOTIATE, 'still negotiating before 10 s');
    Check(RunUntil(E_ChargingState.CHARGE_ABORT, 2000), 'negotiation times out after 10 s');

    ResetScenario();
    g_simBusBlocked := TRUE;
    PlugIn();
    RunUntil(E_ChargingState.CHARGE_PRECHARGE, 2000);
    Check(RunUntil(E_ChargingState.CHARGE_ABORT, 6000), 'precharge times out when bus never rises');
    Check(g_charge.prechargeStep = E_PrechargeStep.PRE_TIMEOUT, 'precharge step reports PRE_TIMEOUT');
END_FUNCTION

FUNCTION TestAliveCounter : BOOL
VAR
    a, b   : BYTE;
    stepOk : BOOL;
END_VAR
    Section('Charge request alive counter');
    ResetScenario();
    a := SimTxByte(CAN_ID_CHARGE_REQUEST, 1);
    Cycle();
    b := SimTxByte(CAN_ID_CHARGE_REQUEST, 1);
    IF a = 255 THEN
        stepOk := b = 0;
    ELSE
        stepOk := b = a + 1;
    END_IF
    Check(stepOk, 'increments every cycle and wraps 255 -> 0');
END_FUNCTION

FUNCTION main : DINT
    printf('EV charging controller - scenario tests$N');
    TestCanDecoding();
    TestDcSession();
    TestAcSession();
    TestCvFollowsLimits();
    TestPauseResume();
    TestCommLossInPrecharge();
    TestCommLossWhileCharging();
    TestTimeouts();
    TestAliveCounter();
    printf('$N%d tests, %d failed$N', g_testsRun, g_testsFailed);
    IF g_testsFailed = 0 THEN
        main := 0;
    ELSE
        main := 1;
    END_IF
END_FUNCTION
