{attribute 'strict'}
TYPE E_ProximityState :
(
    PROX_NOT_CONNECTED := 0,
    PROX_CONNECTED     := 1,
    PROX_LOCKED        := 2,
    PROX_ERROR         := 3
) := PROX_NOT_CONNECTED;
END_TYPE
