(* @brief CAN receive handler for BMS and EVSE messages
 *
 *  Decodes incoming CAN frames and populates:
 *    - g_bms.rx   (5 messages from BMS on CAN3)
 *    - g_evse.rx   (3 messages from EVSE on CAN4)
 *
 *  Runs as PROGRAM on CycleCharge task (10ms).
 *  All multi-byte signals are little-endian (Intel byte order).
 *  J1939 extended 29-bit CAN identifiers.
 *)
PROGRAM PRG_ChargerCAN_RX
VAR
    (* ── BMS receive instances (CAN3) ── *)
    rxBmsPackData   : CanRx;
    rxBmsCellVolts  : CanRx;
    rxBmsCellTemps  : CanRx;
    rxBmsCtrStatus  : CanRx;
    rxBmsLimits     : CanRx;

    (* ── EVSE receive instances (CAN4) ── *)
    rxEvseStatus    : CanRx;
    rxEvseMetering  : CanRx;
    rxEvseProtocol  : CanRx;

    (* ── Data buffers ── *)
    dataBmsPackData   : ARRAY[0..7] OF BYTE;
    dataBmsCellVolts  : ARRAY[0..7] OF BYTE;
    dataBmsCellTemps  : ARRAY[0..7] OF BYTE;
    dataBmsCtrStatus  : ARRAY[0..7] OF BYTE;
    dataBmsLimits     : ARRAY[0..7] OF BYTE;
    dataEvseStatus    : ARRAY[0..7] OF BYTE;
    dataEvseMetering  : ARRAY[0..7] OF BYTE;
    dataEvseProtocol  : ARRAY[0..7] OF BYTE;

    (* ── Decode helpers ── *)
    rawU16 : UINT;
END_VAR

(* ══════════════════════════════════════════════════════════════
   CAN3 — BMS MESSAGES (5 receive)
   ══════════════════════════════════════════════════════════════ *)

(* ── 1. BMS Pack Data ── *)
rxBmsPackData(
    iCAN           := ADR(g_can3),
    iCanId         := CAN_ID_BMS_PACK_DATA,
    iCanIdExtended := TRUE,
    iTimeoutLimit  := T#500MS,
    oData          => dataBmsPackData
);
IF rxBmsPackData.oNewData THEN
    (* Pack voltage: bytes 0-1, 0.1 V/bit, little-endian *)
    rawU16 := BYTE_TO_UINT(dataBmsPackData[0])
           OR SHL(BYTE_TO_UINT(dataBmsPackData[1]), 8);
    g_bms.rx.packVoltage := UINT_TO_REAL(rawU16) * 0.1;

    (* Pack current: bytes 2-3, 0.1 A/bit, offset -3200 A *)
    rawU16 := BYTE_TO_UINT(dataBmsPackData[2])
           OR SHL(BYTE_TO_UINT(dataBmsPackData[3]), 8);
    g_bms.rx.packCurrent := (UINT_TO_REAL(rawU16) * 0.1) - 3200.0;

    (* SOC: byte 4, 1 %/bit *)
    g_bms.rx.soc := dataBmsPackData[4];

    (* SOH: byte 5, 1 %/bit *)
    g_bms.rx.soh := dataBmsPackData[5];

    g_bms.commOk     := TRUE;
    g_bms.lastRxTime := g_vcu.systemTime;
END_IF

(* ── 2. BMS Cell Voltages ── *)
rxBmsCellVolts(
    iCAN           := ADR(g_can3),
    iCanId         := CAN_ID_BMS_CELL_VOLTS,
    iCanIdExtended := TRUE,
    iTimeoutLimit  := T#500MS,
    oData          => dataBmsCellVolts
);
IF rxBmsCellVolts.oNewData THEN
    (* Cell voltage min: bytes 0-1, 1 mV/bit *)
    g_bms.rx.cellVoltageMin :=
        BYTE_TO_UINT(dataBmsCellVolts[0])
        OR SHL(BYTE_TO_UINT(dataBmsCellVolts[1]), 8);

    (* Cell voltage max: bytes 2-3, 1 mV/bit *)
    g_bms.rx.cellVoltageMax :=
        BYTE_TO_UINT(dataBmsCellVolts[2])
        OR SHL(BYTE_TO_UINT(dataBmsCellVolts[3]), 8);

    g_bms.commOk     := TRUE;
    g_bms.lastRxTime := g_vcu.systemTime;
END_IF

(* ── 3. BMS Cell Temperatures ── *)
rxBmsCellTemps(
    iCAN           := ADR(g_can3),
    iCanId         := CAN_ID_BMS_CELL_TEMPS,
    iCanIdExtended := TRUE,
    iTimeoutLimit  := T#500MS,
    oData          => dataBmsCellTemps
);
IF rxBmsCellTemps.oNewData THEN
    (* All temps: 1 C/bit, offset -40 C *)
    g_bms.rx.cellTempMin := BYTE_TO_INT(dataBmsCellTemps[0]) - 40;
    g_bms.rx.cellTempMax := BYTE_TO_INT(dataBmsCellTemps[1]) - 40;
    g_bms.rx.inletTemp   := BYTE_TO_INT(dataBmsCellTemps[2]) - 40;
    g_bms.rx.cableTemp   := BYTE_TO_INT(dataBmsCellTemps[3]) - 40;
    g_bms.rx.coolantTemp := BYTE_TO_INT(dataBmsCellTemps[4]) - 40;

    g_bms.commOk     := TRUE;
    g_bms.lastRxTime := g_vcu.systemTime;
END_IF

(* ── 4. BMS Contactor Status ── *)
rxBmsCtrStatus(
    iCAN           := ADR(g_can3),
    iCanId         := CAN_ID_BMS_CTR_STATUS,
    iCanIdExtended := TRUE,
    iTimeoutLimit  := T#500MS,
    oData          => dataBmsCtrStatus
);
IF rxBmsCtrStatus.oNewData THEN
    (* Byte 0: four 2-bit contactor feedback fields *)
    g_bms.rx.fbkMainPos   := F_ToContactorState(dataBmsCtrStatus[0] AND BYTE#16#03);
    g_bms.rx.fbkMainNeg   := F_ToContactorState(SHR(dataBmsCtrStatus[0] AND BYTE#16#0C, 2));
    g_bms.rx.fbkPrecharge := F_ToContactorState(SHR(dataBmsCtrStatus[0] AND BYTE#16#30, 4));
    g_bms.rx.fbkAcLine    := F_ToContactorState(SHR(dataBmsCtrStatus[0] AND BYTE#16#C0, 6));

    (* Byte 1: summary flags *)
    g_bms.rx.contactorClosed := (dataBmsCtrStatus[1] AND 16#01) <> 0;
    (* Weld is a latched fault: the BMS can set it, never clear it *)
    IF (dataBmsCtrStatus[1] AND 16#02) <> 0 THEN
        g_bms.rx.weldDetected := TRUE;
    END_IF

    g_bms.commOk     := TRUE;
    g_bms.lastRxTime := g_vcu.systemTime;
END_IF

(* ── 5. BMS Limits ── *)
rxBmsLimits(
    iCAN           := ADR(g_can3),
    iCanId         := CAN_ID_BMS_LIMITS,
    iCanIdExtended := TRUE,
    iTimeoutLimit  := T#500MS,
    oData          => dataBmsLimits
);
IF rxBmsLimits.oNewData THEN
    (* Max charge current: bytes 0-1, 0.1 A/bit *)
    rawU16 := BYTE_TO_UINT(dataBmsLimits[0])
           OR SHL(BYTE_TO_UINT(dataBmsLimits[1]), 8);
    g_bms.rx.maxChargeCurrent := UINT_TO_REAL(rawU16) * 0.1;

    (* Max discharge current: bytes 2-3, 0.1 A/bit *)
    rawU16 := BYTE_TO_UINT(dataBmsLimits[2])
           OR SHL(BYTE_TO_UINT(dataBmsLimits[3]), 8);
    g_bms.rx.maxDischargeCurrent := UINT_TO_REAL(rawU16) * 0.1;

    g_bms.commOk     := TRUE;
    g_bms.lastRxTime := g_vcu.systemTime;
END_IF


(* ══════════════════════════════════════════════════════════════
   CAN4 — EVSE MESSAGES (3 receive)
   ══════════════════════════════════════════════════════════════ *)

(* ── 6. EVSE Status ── *)
rxEvseStatus(
    iCAN           := ADR(g_can4),
    iCanId         := CAN_ID_EVSE_STATUS,
    iCanIdExtended := TRUE,
    iTimeoutLimit  := T#1000MS,
    oData          => dataEvseStatus
);
IF rxEvseStatus.oNewData THEN
    (* Byte 0 bit 0: available *)
    g_evse.rx.available      := (dataEvseStatus[0] AND 16#01) <> 0;
    (* Byte 0 bit 1: isolation valid *)
    g_evse.rx.isolationValid := (dataEvseStatus[0] AND 16#02) <> 0;

    (* Max voltage: bytes 1-2, 0.1 V/bit *)
    rawU16 := BYTE_TO_UINT(dataEvseStatus[1])
           OR SHL(BYTE_TO_UINT(dataEvseStatus[2]), 8);
    g_evse.rx.maxVoltage := UINT_TO_REAL(rawU16) * 0.1;

    (* Max current: bytes 3-4, 0.1 A/bit *)
    rawU16 := BYTE_TO_UINT(dataEvseStatus[3])
           OR SHL(BYTE_TO_UINT(dataEvseStatus[4]), 8);
    g_evse.rx.maxCurrent := UINT_TO_REAL(rawU16) * 0.1;

    g_evse.commOk     := TRUE;
    g_evse.lastRxTime := g_vcu.systemTime;
END_IF

(* ── 7. EVSE Metering ── *)
rxEvseMetering(
    iCAN           := ADR(g_can4),
    iCanId         := CAN_ID_EVSE_METERING,
    iCanIdExtended := TRUE,
    iTimeoutLimit  := T#1000MS,
    oData          => dataEvseMetering
);
IF rxEvseMetering.oNewData THEN
    (* Present voltage: bytes 0-1, 0.1 V/bit, 0xFFFF = invalid *)
    rawU16 := BYTE_TO_UINT(dataEvseMetering[0])
           OR SHL(BYTE_TO_UINT(dataEvseMetering[1]), 8);
    IF rawU16 <> 16#FFFF THEN
        g_evse.rx.presentVoltage := UINT_TO_REAL(rawU16) * 0.1;
    ELSE
        g_evse.rx.presentVoltage := 0.0;
    END_IF

    (* Present current: bytes 2-3, 0.1 A/bit, 0xFFFF = invalid *)
    rawU16 := BYTE_TO_UINT(dataEvseMetering[2])
           OR SHL(BYTE_TO_UINT(dataEvseMetering[3]), 8);
    IF rawU16 <> 16#FFFF THEN
        g_evse.rx.presentCurrent := UINT_TO_REAL(rawU16) * 0.1;
    ELSE
        g_evse.rx.presentCurrent := 0.0;
    END_IF

    g_evse.commOk     := TRUE;
    g_evse.lastRxTime := g_vcu.systemTime;
END_IF

(* ── 8. EVSE Protocol ── *)
rxEvseProtocol(
    iCAN           := ADR(g_can4),
    iCanId         := CAN_ID_EVSE_PROTOCOL,
    iCanIdExtended := TRUE,
    iTimeoutLimit  := T#1000MS,
    oData          => dataEvseProtocol
);
IF rxEvseProtocol.oNewData THEN
    (* Byte 0 bits 1:0 — charge protocol *)
    g_evse.rx.protocol := F_ToChargeProtocol(dataEvseProtocol[0] AND 16#03);

    g_evse.commOk     := TRUE;
    g_evse.lastRxTime := g_vcu.systemTime;
END_IF


(* ══════════════════════════════════════════════════════════════
   COMMUNICATION TIMEOUT CHECK
   ══════════════════════════════════════════════════════════════ *)

(* BMS timeout: 500ms *)
IF (g_vcu.systemTime - g_bms.lastRxTime) > COMM_BMS_TIMEOUT_MS THEN
    g_bms.commOk := FALSE;
END_IF

(* EVSE timeout: 1000ms *)
IF (g_vcu.systemTime - g_evse.lastRxTime) > COMM_EVSE_TIMEOUT_MS THEN
    g_evse.commOk := FALSE;
END_IF

END_PROGRAM
