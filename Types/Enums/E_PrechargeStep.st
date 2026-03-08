{attribute 'strict'}
TYPE E_PrechargeStep :
(
    PRE_IDLE          := 0,
    PRE_CLOSE_NEG     := 1,
    PRE_RELAY_ENGAGE  := 2,
    PRE_VOLTAGE_WAIT  := 3,
    PRE_VOLTAGE_OK    := 4,
    PRE_CLOSE_POS     := 5,
    PRE_RELAY_RELEASE := 6,
    PRE_COMPLETE      := 7,
    PRE_TIMEOUT       := 8
) := PRE_IDLE;
END_TYPE
