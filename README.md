# EV Charging Controller

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
```

## Build Environment

- **Target**: IEC 61131-3 PLC runtime — not yet run on target hardware
- **Libraries**: a vendor CAN library providing `CanRx` / `CanTx`, and OSCAT for `T_PLC_MS`
- **Language**: IEC 61131-3 Structured Text
- **Task configuration**: CycleCharge (10ms) for control logic, CycleSafety (10ms) for contactor monitoring
- **POU type**: All modules are `PROGRAM` (singleton instances)
