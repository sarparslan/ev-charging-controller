# EV Charging Controller

[![tests](https://github.com/sarparslan/ev-charging-controller/actions/workflows/tests.yml/badge.svg)](https://github.com/sarparslan/ev-charging-controller/actions/workflows/tests.yml)

IEC 61131-3 Structured Text implementation of a Vehicle Control Unit (VCU) charging subsystem for electric vehicles. Written for IEC 61131-3 PLC runtimes, this project manages the complete DC and AC charge session lifecycle — from cable insertion through energy transfer to safe disconnect.

## Architecture

Each external device owns a struct in the Global Variable List with explicit `rx` / `tx` separation:

| Instance | Type | Role |
|----------|------|------|
| `g_bms` | `ST_Bms` | Battery Management System — pack measurements, cell data, contactor feedback, charge limits |
| `g_evse` | `ST_Evse` | Electric Vehicle Supply Equipment — charger status, metering, protocol negotiation |
| `g_charge` | `ST_ChargeSession` | Internal session state — computed by state machine, not tied to a CAN device |
| `g_vcu` | `ST_Vcu` | Vehicle-level signals — control pilot, parking brake, thermal management |

All CAN communication uses **J1939 extended 29-bit identifiers** with **little-endian (Intel) byte order**.

## Project Structure

```
Types/          Enums, structs and GVL (CAN IDs, constants)
Communication/  CAN RX decode (8 msgs) and TX encode (5 msgs)
Control/        Charging state machine, DC and AC charge control
Safety/         HV contactor monitoring and weld detection
tests/          Scenario tests, simulated BMS/EVSE and platform mocks
```

## Charge Session Lifecycle

![Charging state machine](docs/state-machine.png)

### State Descriptions

| State | Purpose |
|-------|---------|
| **IDLE** | All outputs safe. Waits for CP State B + parking brake |
| **CONNECTED** | Cable locked. Waits for CP State C + BMS/EVSE comms alive |
| **NEGOTIATE** | Latches protocol, determines DC/AC mode from EVSE capabilities. 10s timeout |
| **ISOLATE** | Waits for EVSE insulation test. DC → precharge, AC → direct to active. 30s timeout |
| **PRECHARGE** | 6-step DC bus voltage equalization with 50ms settle re-check. 5s global timeout |
| **ACTIVE** | CC-CV charge control with energy accumulation and thermal derating |
| **RAMPDOWN** | Linear current ramp-down to zero over 2 seconds |
| **WELD_CHECK** | Opens all contactors, waits 200ms, checks for welded contacts |
| **COMPLETE** | Charge finished normally. Waits for cable removal |
| **ABORT** | Emergency safe state. All contactors open, waits for cable removal |
| **PAUSED** | Entered while `g_charge.pauseRequest` is set (grid/user). Zero current, contactors held. Resumes when the request clears |

## DC Precharge Sequence

![HV power path and precharge order](docs/hv-power-path.png)

The precharge sub-state machine equalizes the HV bus voltage to the battery pack voltage before closing the main contactors, preventing inrush current damage.

## CC-CV Charging

The active charge state implements a standard **Constant Current – Constant Voltage** algorithm:

- **CC Phase**: Charges at `MIN(BMS_limit, mode_limit, EVSE_limit) × derateFactor/100` until any cell reaches 4150 mV
- **CV Phase**: Holds voltage at 420V while current tapers naturally. Completes when taper current falls below 2A
- **Hard cutoff**: Any cell reaching 4200 mV forces immediate ramp-down

Energy accumulation: `E += V × I × dt / 3,600,000` (W·s → kWh) computed every 10ms cycle.

## CAN Communication

![CAN message flow between VCU, BMS and EVSE](docs/can-message-flow.png)

| Bus | Device | Messages | Cycle |
|-----|--------|----------|-------|
| CAN3 | BMS | 5 RX + 2 TX | RX: event, TX: 50ms / 100ms |
| CAN4 | EVSE | 3 RX + 3 TX | RX: event, TX: 100ms / 250ms |

- **Encoding**: little-endian; voltage and current 0.1/bit, current offset −3200 A, temperature offset −40 °C
- **Watchdogs**: BMS 500 ms, EVSE 1000 ms, rollover-safe; losing either link at any point after CONNECTED triggers ABORT

## Safety

![Contactor control on the safety task](docs/contactor-control.png)

- **Contactor monitoring** runs on its own safety task: 150 ms feedback timeout on close and open
- **Weld detection** latches if a contactor stays closed after an open command (or the BMS reports a weld), forces all contactors open, and blocks new sessions until power cycle
- **Precharge** re-checks the bus voltage after 50 ms before closing K1
- **Strict enums** (`{attribute 'strict'}`) give compile-time type safety

## Testing

The controller is verified off-target with the open-source [RuSTy](https://github.com/PLC-lang/rusty) IEC 61131-3 compiler. `tests/run.sh` compiles the real sources together with mocks for the platform libraries and runs them cycle by cycle against a simulated BMS and EVSE that talk to the VCU only through CAN frames.

```bash
tests/run.sh
```

Scenarios cover a full DC session (including contactor order), AC mode, CC→CV transition, pause/resume, comm loss during precharge and while charging, negotiation and precharge timeouts, the alive counter, and weld detection. The same tests run in GitHub Actions on every push.

## Standards & References

| Standard | Application |
|----------|-------------|
| IEC 61851-1 | Control Pilot state machine (CP states A–F) |
| IEC 61131-3 | Structured Text programming language |
| DIN 70121 | DC charging communication protocol |
| ISO 15118 | Plug & Charge, bidirectional communication |
| SAE J1939 | CAN extended frame format (29-bit identifiers) |

## Build Environment

- **Target**: IEC 61131-3 PLC runtime — not yet run on target hardware
- **Libraries**: a vendor CAN library providing `CanRx` / `CanTx`, and OSCAT for `T_PLC_MS`
- **Language**: IEC 61131-3 Structured Text
- **Task configuration**: CycleCharge (10ms) for control logic, CycleSafety (10ms) for contactor monitoring
- **POU type**: All modules are `PROGRAM` (singleton instances)
