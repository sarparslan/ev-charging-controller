(* @brief EVSE device interface — CAN4
 *
 *  Groups all EVSE-related data under a single GVL instance.
 *  rx = data received from EVSE, tx = data sent to EVSE.
 *)
TYPE ST_Evse :
STRUCT
    rx          : ST_EvseRx;              (* incoming data from EVSE *)
    tx          : ST_EvseTx;              (* outgoing data to EVSE *)
    commOk      : BOOL;                   (* communication alive *)
    lastRxTime  : UDINT;                  (* [ms] last valid reception timestamp *)
END_STRUCT
END_TYPE
