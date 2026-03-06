{attribute 'strict'}
TYPE E_ControlPilot :
(
    CP_STATE_A  := 0,   (* Not connected — 12V *)
    CP_STATE_B  := 1,   (* Connected, not ready — 9V *)
    CP_STATE_C  := 2,   (* Ready, charging allowed — 6V *)
    CP_STATE_D  := 3,   (* With ventilation — 3V *)
    CP_STATE_E  := 4,   (* No power / short — 0V *)
    CP_STATE_F  := 5    (* Error — -12V *)
) := CP_STATE_A;
END_TYPE
