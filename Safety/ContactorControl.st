(* @brief Contactor monitoring — command/feedback validation
 *
 *  Monitors the three HV contactors (K1, K2, K3) by comparing
 *  commanded state against actual feedback from the BMS.
 *
 *  Detects two failure modes per contactor:
 *    - Weld:       command = OPEN  but feedback = CLOSED after timeout
 *    - Open circuit: command = CLOSE but feedback = OPEN  after timeout
 *
 *  On any weld detection, latches g_bms.rx.weldDetected := TRUE so the
 *  charging state machine can react in WELD_CHECK or any other state.
 *  The flag is also set by a BMS weld report and is only cleared by a
 *  power cycle.
 *
 *  On critical failure (weld), forces all contactor commands to OPEN
 *  as a last-resort safety measure independent of the state machine.
 *
 *  Runs as a PROGRAM on CycleSafety task (10 ms period).
 *
 *  Contactors:
 *    K1  Main positive   cmdMainPos   / fbkMainPos
 *    K2  Main negative   cmdMainNeg   / fbkMainNeg
 *    K3  Precharge relay  cmdPrecharge / fbkPrecharge
 *)
PROGRAM PRG_ContactorControl
VAR
    (* ── K1: Main Positive ── *)
    prevCmdPos      : BOOL;
    posCloseTimer   : UDINT;     (* timestamp when close command issued *)
    posOpenTimer    : UDINT;     (* timestamp when open command issued *)
    posCloseCheck   : BOOL;      (* TRUE = waiting for close confirmation *)
    posOpenCheck    : BOOL;      (* TRUE = waiting for open confirmation *)
    posWeld         : BOOL;      (* latched weld detection *)

    (* ── K2: Main Negative ── *)
    prevCmdNeg      : BOOL;
    negCloseTimer   : UDINT;
    negOpenTimer    : UDINT;
    negCloseCheck   : BOOL;
    negOpenCheck    : BOOL;
    negWeld         : BOOL;

    (* ── K3: Precharge Relay ── *)
    prevCmdPre      : BOOL;
    preCloseTimer   : UDINT;
    preOpenTimer    : UDINT;
    preCloseCheck   : BOOL;
    preOpenCheck    : BOOL;
    preWeld         : BOOL;
END_VAR

(* ══════════════════════════════════════════════════════════════
   EMERGENCY OPEN — if any weld is latched, force all contactors open
   ══════════════════════════════════════════════════════════════ *)
IF posWeld OR negWeld OR preWeld OR g_bms.rx.weldDetected THEN
    g_bms.tx.cmdMainPos   := FALSE;
    g_bms.tx.cmdMainNeg   := FALSE;
    g_bms.tx.cmdPrecharge := FALSE;
    g_bms.tx.cmdAcLine    := FALSE;
    g_bms.tx.chargeEnable := FALSE;
END_IF

(* ══════════════════════════════════════════════════════════════
   K1 — MAIN POSITIVE CONTACTOR
   ══════════════════════════════════════════════════════════════ *)

(* Rising edge: close command just issued *)
IF g_bms.tx.cmdMainPos AND NOT prevCmdPos THEN
    posCloseTimer := g_vcu.systemTime;
    posCloseCheck := TRUE;
END_IF

(* Falling edge: open command just issued *)
IF NOT g_bms.tx.cmdMainPos AND prevCmdPos THEN
    posOpenTimer := g_vcu.systemTime;
    posOpenCheck := TRUE;
END_IF

(* Check close confirmation *)
IF posCloseCheck THEN
    IF g_bms.rx.fbkMainPos = E_ContactorState.CTR_CLOSED THEN
        posCloseCheck := FALSE;   (* confirmed *)
    ELSIF (g_vcu.systemTime - posCloseTimer) > CTR_FEEDBACK_TIMEOUT_MS THEN
        posCloseCheck := FALSE;   (* timeout — open circuit detected *)
    END_IF
END_IF

(* Check open confirmation — weld detection *)
IF posOpenCheck THEN
    IF g_bms.rx.fbkMainPos = E_ContactorState.CTR_OPEN THEN
        posOpenCheck := FALSE;    (* confirmed *)
    ELSIF (g_vcu.systemTime - posOpenTimer) > CTR_FEEDBACK_TIMEOUT_MS THEN
        posOpenCheck := FALSE;
        posWeld := TRUE;          (* WELD: contactor stuck closed *)
    END_IF
END_IF

prevCmdPos := g_bms.tx.cmdMainPos;

(* ══════════════════════════════════════════════════════════════
   K2 — MAIN NEGATIVE CONTACTOR
   ══════════════════════════════════════════════════════════════ *)

(* Rising edge: close command just issued *)
IF g_bms.tx.cmdMainNeg AND NOT prevCmdNeg THEN
    negCloseTimer := g_vcu.systemTime;
    negCloseCheck := TRUE;
END_IF

(* Falling edge: open command just issued *)
IF NOT g_bms.tx.cmdMainNeg AND prevCmdNeg THEN
    negOpenTimer := g_vcu.systemTime;
    negOpenCheck := TRUE;
END_IF

(* Check close confirmation *)
IF negCloseCheck THEN
    IF g_bms.rx.fbkMainNeg = E_ContactorState.CTR_CLOSED THEN
        negCloseCheck := FALSE;
    ELSIF (g_vcu.systemTime - negCloseTimer) > CTR_FEEDBACK_TIMEOUT_MS THEN
        negCloseCheck := FALSE;
    END_IF
END_IF

(* Check open confirmation — weld detection *)
IF negOpenCheck THEN
    IF g_bms.rx.fbkMainNeg = E_ContactorState.CTR_OPEN THEN
        negOpenCheck := FALSE;
    ELSIF (g_vcu.systemTime - negOpenTimer) > CTR_FEEDBACK_TIMEOUT_MS THEN
        negOpenCheck := FALSE;
        negWeld := TRUE;
    END_IF
END_IF

prevCmdNeg := g_bms.tx.cmdMainNeg;

(* ══════════════════════════════════════════════════════════════
   K3 — PRECHARGE RELAY
   ══════════════════════════════════════════════════════════════ *)

(* Rising edge: close command just issued *)
IF g_bms.tx.cmdPrecharge AND NOT prevCmdPre THEN
    preCloseTimer := g_vcu.systemTime;
    preCloseCheck := TRUE;
END_IF

(* Falling edge: open command just issued *)
IF NOT g_bms.tx.cmdPrecharge AND prevCmdPre THEN
    preOpenTimer := g_vcu.systemTime;
    preOpenCheck := TRUE;
END_IF

(* Check close confirmation *)
IF preCloseCheck THEN
    IF g_bms.rx.fbkPrecharge = E_ContactorState.CTR_CLOSED THEN
        preCloseCheck := FALSE;
    ELSIF (g_vcu.systemTime - preCloseTimer) > CTR_FEEDBACK_TIMEOUT_MS THEN
        preCloseCheck := FALSE;
    END_IF
END_IF

(* Check open confirmation — weld detection *)
IF preOpenCheck THEN
    IF g_bms.rx.fbkPrecharge = E_ContactorState.CTR_OPEN THEN
        preOpenCheck := FALSE;
    ELSIF (g_vcu.systemTime - preOpenTimer) > CTR_FEEDBACK_TIMEOUT_MS THEN
        preOpenCheck := FALSE;
        preWeld := TRUE;
    END_IF
END_IF

prevCmdPre := g_bms.tx.cmdPrecharge;

(* ══════════════════════════════════════════════════════════════
   WELD SUMMARY — single flag for state machine consumption
   ══════════════════════════════════════════════════════════════ *)
(* Latched: never cleared here, so a BMS-reported weld is kept as well *)
IF posWeld OR negWeld OR preWeld THEN
    g_bms.rx.weldDetected := TRUE;
END_IF

END_PROGRAM
