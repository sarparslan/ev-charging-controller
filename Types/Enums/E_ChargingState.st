{attribute 'strict'}
TYPE E_ChargingState :
(
    CHARGE_IDLE       := 0,
    CHARGE_CONNECTED  := 1,
    CHARGE_NEGOTIATE  := 2,
    CHARGE_ISOLATE    := 3,
    CHARGE_PRECHARGE  := 4,
    CHARGE_ACTIVE     := 5,
    CHARGE_RAMPDOWN   := 6,
    CHARGE_WELD_CHECK := 7,
    CHARGE_COMPLETE   := 8,
    CHARGE_ABORT      := 9,
    CHARGE_PAUSED     := 10
) := CHARGE_IDLE;
END_TYPE
