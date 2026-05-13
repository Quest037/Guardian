# SquadMovementAndFormations.md

# Squad Movement & Formation Control
## PX4 and ArduPilot Multi-Agent Coordination Concepts

---

# Overview

This document explains a practical architecture for controlling multiple autonomous drones or rovers in a squad/wingman configuration using:

- PX4
- ArduPilot
- Offboard / Guided control
- Formation controllers
- Dynamic leader replacement ("promotion")

The goal is to support:

- formations
- coordinated movement
- mission continuity
- autonomous failover
- resilient swarm behavior

---

# Core Concepts

## Primary Vehicle

The **primary** vehicle is the active mission executor.

Responsibilities:
- follows mission waypoints
- determines squad direction
- broadcasts telemetry/state
- acts as squad leader

Examples:
- lead drone
- lead rover
- command unit

---

## Wingmen

Wingmen are support vehicles that:

- maintain formation around the primary
- do not independently execute the mission while following
- retain a local copy of the mission onboard
- can become the new primary if needed

Wingmen continuously receive:
- primary position
- heading
- velocity
- formation instructions

---

# Why Every Vehicle Stores the Mission

Every vehicle stores the same mission because:

- the primary may fail
- communication may be lost
- a replacement leader may be required immediately

This enables:

- seamless promotion
- mission continuation
- decentralized redundancy

Important distinction:

| Concept | Meaning |
|---|---|
| Mission Ownership | Vehicle stores mission locally |
| Mission Authority | Vehicle actively executes mission |

Normally:
- all vehicles own the mission
- only one executes it

---

# PX4 Modes Relevant to Swarm Control

## AUTO Modes

PX4 AUTO modes are internally controlled autonomous navigation states.

Examples:
- AUTO_MISSION
- AUTO_LOITER
- AUTO_RTL

In AUTO:
- PX4 navigation logic owns movement
- the autopilot generates path setpoints internally

Good for:
- waypoint missions
- autonomous navigation

Not ideal for:
- advanced formation control
- swarm dynamics
- real-time squad coordination

---

## OFFBOARD Mode

OFFBOARD mode transfers high-level control authority to an external computer.

The external controller continuously streams:
- velocity setpoints
- position setpoints
- steering commands
- actuator targets

PX4 still handles:
- stabilization
- low-level control
- actuator management

But movement decisions come externally.

---

# What Is an Offboard Setpoint?

An Offboard setpoint is simply:

> A target command continuously sent to PX4.

Examples:
- velocity = 2 m/s
- steering = 0
- position = X,Y,Z
- yaw = 90°

PX4 expects these continuously.

Example:

```text
20 Hz:
    velocity = 0
    steering = 0
```
This means:

stay stopped
remain in OFFBOARD mode
Why Setpoints Must Be Streamed Continuously

PX4 treats Offboard commands as:

control input
heartbeat
proof external control is alive

If streaming stops:

PX4 exits OFFBOARD mode
Offboard-loss failsafe triggers

Possible fallback behaviors:

HOLD
RETURN
LOITER
MANUAL
failsafe actions

Configured using PX4 failsafe parameters.

Why AUTO_LOITER Can Cause Problems

AUTO_LOITER is still part of PX4's autonomous navigation stack.

This means:

navigation controllers remain active
position-holding logic continues
loiter behaviors continue internally

For rovers or formations this can create unwanted movement.

Better pattern:

AUTO_MISSION
→ OFFBOARD
→ stream desired formation commands

instead of:

AUTO_MISSION
→ AUTO_LOITER
ArduPilot Equivalent Concepts

ArduPilot uses similar concepts with different names.

PX4	ArduPilot
OFFBOARD	GUIDED
AUTO_MISSION	AUTO
FOLLOW_TARGET	FOLLOW / Follow Me

In ArduPilot:

GUIDED mode allows external command authority
companion computers can stream movement targets
formation logic is typically external
FOLLOW_TARGET vs Formation Control

FOLLOW_TARGET alone is usually insufficient for real formations.

FOLLOW_TARGET means:

Follow a moving target directly.

This creates:

single-file following
simple pursuit behavior

Not:

coordinated formations
offset positioning
tactical movement
Formation Controller Concept

A Formation Controller sits above the autopilot.

Responsibilities:

calculate formation geometry
assign offsets
maintain spacing
avoid collisions
update wingman targets dynamically

Each wingman receives:

Desired Position =
    Primary Position
    + Formation Offset
Example Formations
Convoy
P
W1
W2
W3
Chevron
W1       W2
   \   /
     P
   /   \
W3       W4
Arrowhead
        P
      /   \
    W1     W2
   /         \
 W3           W4
How Formations Work Internally

Primary broadcasts:

GPS position
heading
velocity
mission state

Formation controller computes:

desired relative offsets

Wingmen receive:

virtual target positions

Wingmen then:

fly/drive toward their assigned offset targets

Usually via:

PX4 OFFBOARD
ArduPilot GUIDED
Recommended Architecture
Primary Vehicle

Runs:

mission execution
squad coordination
telemetry broadcast

Mode:

AUTO_MISSION
Wingmen

Run:

formation following
dynamic positioning

Mode:

OFFBOARD (PX4)
GUIDED (ArduPilot)
Promotion System (Leader Replacement)
Goal

If the primary fails:

another vehicle becomes leader
mission continues seamlessly
Promotion Workflow
Step 1 — Detect Failure

Triggers:

heartbeat timeout
telemetry loss
crash detection
no movement
explicit distress signal
Step 2 — Elect Replacement

Choose:

nearest vehicle to mission path
healthiest vehicle
highest battery
best communication quality

This vehicle becomes:

new primary
Step 3 — Resume Mission

New primary:

switches into mission execution mode
resumes mission from latest checkpoint

Examples:

PX4 AUTO_MISSION
ArduPilot AUTO
Step 4 — Reassign Wingmen

Remaining vehicles:

switch follow target
update formation references
reposition around new primary
Recommended State Architecture
Primary
AUTO_MISSION
Wingmen
OFFBOARD / GUIDED
→ formation-follow logic
On Promotion
Wingman promoted
→ switch to mission mode
→ continue mission
Important Design Principle

Avoid allowing:

all vehicles
all autopilots

to independently execute the mission simultaneously.

That causes:

drift
timing divergence
conflicting navigation
formation instability

Instead:

One vehicle:
    executes mission

Others:
    follow formation targets
Summary

Best-practice swarm architecture:

Role	Behavior
Primary	Executes mission
Wingmen	Follow formation targets
Formation Controller	Computes offsets
OFFBOARD/GUIDED	External squad control
Mission Storage	Stored on every vehicle
Promotion	Transfers mission authority

This architecture enables:

resilient squads
dynamic formations
leader replacement
convoy movement
tactical coordination
autonomous continuation after failures