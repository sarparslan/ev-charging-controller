{attribute 'strict'}
TYPE E_VehicleChargeState :
(
    VCS_STANDBY       := 0,
    VCS_PLUG_DETECTED := 1,
    VCS_LOCK_ENGAGED  := 2,
    VCS_CHARGE_READY  := 3,
    VCS_CHARGING_DC   := 4,
    VCS_CHARGING_AC   := 5,
    VCS_CHARGE_ENDING := 6,
    VCS_FAULT         := 7
) := VCS_STANDBY;
END_TYPE
