(* @brief CAN transmit handler for BMS and EVSE messages
 *
 *  Encodes outgoing CAN frames from:
 *    - g_bms.tx    (2 messages to BMS on CAN3)
 *    - g_evse.tx   (3 messages to EVSE on CAN4)
 *
 *  Runs as PROGRAM on CycleCharge task (10ms).
 *  All multi-byte signals are little-endian (Intel byte order).
 *  J1939 extended 29-bit CAN identifiers.
 *
 *  Transmit rates:
 *    50ms  — BMS Charge Cmd   (safety-critical contactor commands)
 *    100ms — Charge Request, Charge Params, BMS Charge Lim
 *    250ms — Charge Status    (informational)
 *)
PROGRAM PRG_ChargerCAN_TX
VAR
    (* ── EVSE transmit instances (CAN4) ── *)
    txChargeRequest : CanTx;
    txChargeParams  : CanTx;
    txChargeStatus  : CanTx;

    (* ── BMS transmit instances (CAN3) ── *)
    txBmsChargeCmd  : CanTx;
    txBmsChargeLim  : CanTx;

    (* ── Data buffers ── *)
    dataChargeRequest : ARRAY[0..7] OF BYTE;
    dataChargeParams  : ARRAY[0..7] OF BYTE;
    dataChargeStatus  : ARRAY[0..7] OF BYTE;
    dataBmsChargeCmd  : ARRAY[0..7] OF BYTE;
    dataBmsChargeLim  : ARRAY[0..7] OF BYTE;

    (* ── Encode helpers ── *)
    encU16 : UINT;
END_VAR

(* ══════════════════════════════════════════════════════════════
   CAN4 — EVSE MESSAGES (3 transmit)
   ══════════════════════════════════════════════════════════════ *)

(* ── 9. Charge Request  (100ms) ── *)

(* Byte 0: state [3:0] + mode [5:4] *)
dataChargeRequest[0] := TO_BYTE(g_evse.tx.state) AND 16#0F;
dataChargeRequest[0] := dataChargeRequest[0]
    OR SHL(TO_BYTE(g_evse.tx.mode) AND BYTE#16#03, 4);

(* Byte 1: alive counter *)
IF g_evse.tx.aliveCounter < ALIVE_COUNTER_MAX THEN
    g_evse.tx.aliveCounter := g_evse.tx.aliveCounter + 1;
ELSE
    g_evse.tx.aliveCounter := 0;
END_IF
dataChargeRequest[1] := g_evse.tx.aliveCounter;

(* Byte 2: chargeEnable [bit 0] + emergencyStop [bit 1] *)
dataChargeRequest[2] := 0;
IF g_evse.tx.chargeEnable THEN
    dataChargeRequest[2] := dataChargeRequest[2] OR 16#01;
END_IF
IF g_evse.tx.emergencyStop THEN
    dataChargeRequest[2] := dataChargeRequest[2] OR 16#02;
END_IF

(* Bytes 3-7: reserved *)
dataChargeRequest[3] := 0;
dataChargeRequest[4] := 0;
dataChargeRequest[5] := 0;
dataChargeRequest[6] := 0;
dataChargeRequest[7] := 0;

txChargeRequest(
    iEnable        := TRUE,
    iCAN           := ADR(g_can4),
    iForceSend     := FALSE,
    iTransmitRate  := T#100MS,
    iCanId         := CAN_ID_CHARGE_REQUEST,
    iCanIdExtended := TRUE,
    iByteCount     := 8,
    iData          := dataChargeRequest
);


(* ── 10. Charge Params  (100ms) ── *)

(* Bytes 0-1: target voltage, 0.1 V/bit, little-endian *)
encU16 := REAL_TO_UINT(g_evse.tx.targetVoltage * 10.0);
dataChargeParams[0] := TO_BYTE(encU16 AND 16#FF);
dataChargeParams[1] := TO_BYTE(SHR(encU16, 8) AND 16#FF);

(* Bytes 2-3: target current, 0.1 A/bit, little-endian *)
encU16 := REAL_TO_UINT(g_evse.tx.targetCurrent * 10.0);
dataChargeParams[2] := TO_BYTE(encU16 AND 16#FF);
dataChargeParams[3] := TO_BYTE(SHR(encU16, 8) AND 16#FF);

(* Byte 4: CC/CV flag *)
dataChargeParams[4] := g_evse.tx.ccCvFlag;

(* Byte 5: battery SOC *)
dataChargeParams[5] := g_evse.tx.soc;

(* Bytes 6-7: reserved *)
dataChargeParams[6] := 0;
dataChargeParams[7] := 0;

txChargeParams(
    iEnable        := TRUE,
    iCAN           := ADR(g_can4),
    iForceSend     := FALSE,
    iTransmitRate  := T#100MS,
    iCanId         := CAN_ID_CHARGE_PARAMS,
    iCanIdExtended := TRUE,
    iByteCount     := 8,
    iData          := dataChargeParams
);


(* ── 11. Charge Status  (250ms) ── *)

(* Byte 0: vehicle state *)
dataChargeStatus[0] := TO_BYTE(g_evse.tx.vehicleState);

(* Byte 1: precharge step *)
dataChargeStatus[1] := TO_BYTE(g_evse.tx.prechargeStep);

(* Byte 2: parkingBrake [bit 0] + ignitionOn [bit 1] + chargeComplete [bit 2] *)
dataChargeStatus[2] := 0;
IF g_evse.tx.parkingBrake THEN
    dataChargeStatus[2] := dataChargeStatus[2] OR 16#01;
END_IF
IF g_evse.tx.ignitionOn THEN
    dataChargeStatus[2] := dataChargeStatus[2] OR 16#02;
END_IF
IF g_evse.tx.chargeComplete THEN
    dataChargeStatus[2] := dataChargeStatus[2] OR 16#04;
END_IF

(* Bytes 3-7: reserved *)
dataChargeStatus[3] := 0;
dataChargeStatus[4] := 0;
dataChargeStatus[5] := 0;
dataChargeStatus[6] := 0;
dataChargeStatus[7] := 0;

txChargeStatus(
    iEnable        := TRUE,
    iCAN           := ADR(g_can4),
    iForceSend     := FALSE,
    iTransmitRate  := T#250MS,
    iCanId         := CAN_ID_CHARGE_STATUS,
    iCanIdExtended := TRUE,
    iByteCount     := 8,
    iData          := dataChargeStatus
);

END_PROGRAM
