(* @brief BMS device interface — CAN3
 *
 *  Groups all BMS-related data under a single GVL instance.
 *  rx = data received from BMS, tx = data sent to BMS.
 *)
TYPE ST_Bms :
STRUCT
    rx          : ST_BmsRx;               (* incoming data from BMS *)
    tx          : ST_BmsTx;               (* outgoing commands to BMS *)
    commOk      : BOOL;                   (* communication alive *)
    lastRxTime  : UDINT;                  (* [ms] last valid reception timestamp *)
END_STRUCT
END_TYPE
