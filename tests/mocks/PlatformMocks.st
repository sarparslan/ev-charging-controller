(* @brief Host-side stand-ins for the target platform libraries
 *
 *  The controller is written against a vendor CAN library (CanRx / CanTx)
 *  and OSCAT (T_PLC_MS). These mocks replace them for off-target tests:
 *    - T_PLC_MS returns g_simTimeMs, advanced by the test harness
 *    - CanRx delivers frames queued in g_simRx, one per call
 *    - CanTx records the last frame sent per CAN ID in g_simTx
 *)
TYPE ST_SimFrame :
STRUCT
    id      : DWORD;
    data    : ARRAY[0..7] OF BYTE;
    pending : BOOL;                 (* RX: waiting to be read *)
    count   : UDINT;                (* TX: number of transmissions *)
END_STRUCT
END_TYPE

VAR_GLOBAL
    g_simTimeMs : UDINT;
    g_simRx     : ARRAY[0..15] OF ST_SimFrame;
    g_simTx     : ARRAY[0..15] OF ST_SimFrame;
END_VAR

FUNCTION T_PLC_MS : UDINT
    T_PLC_MS := g_simTimeMs;
END_FUNCTION

FUNCTION_BLOCK CanRx
VAR_INPUT
    iCAN           : POINTER TO BYTE;
    iCanId         : DWORD;
    iCanIdExtended : BOOL;
    iTimeoutLimit  : TIME;
END_VAR
VAR_OUTPUT
    oData    : ARRAY[0..7] OF BYTE;
    oNewData : BOOL;
END_VAR
VAR
    i : INT;
END_VAR
    oNewData := FALSE;
    FOR i := 0 TO 15 DO
        IF g_simRx[i].pending AND g_simRx[i].id = iCanId THEN
            oData := g_simRx[i].data;
            oNewData := TRUE;
            g_simRx[i].pending := FALSE;
            RETURN;
        END_IF
    END_FOR
END_FUNCTION_BLOCK

FUNCTION_BLOCK CanTx
VAR_INPUT
    iEnable        : BOOL;
    iCAN           : POINTER TO BYTE;
    iForceSend     : BOOL;
    iTransmitRate  : TIME;
    iCanId         : DWORD;
    iCanIdExtended : BOOL;
    iByteCount     : USINT;
    iData          : ARRAY[0..7] OF BYTE;
END_VAR
VAR
    i    : INT;
    slot : INT := -1;
END_VAR
    IF NOT iEnable THEN
        RETURN;
    END_IF
    IF slot < 0 THEN
        FOR i := 0 TO 15 DO
            IF slot < 0 AND (g_simTx[i].id = iCanId OR g_simTx[i].count = 0) THEN
                slot := i;
            END_IF
        END_FOR
    END_IF
    g_simTx[slot].id := iCanId;
    g_simTx[slot].data := iData;
    g_simTx[slot].count := g_simTx[slot].count + 1;
END_FUNCTION_BLOCK
