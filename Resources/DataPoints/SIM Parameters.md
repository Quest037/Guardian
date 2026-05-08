# SIM Parameters

Full ArduPilot parameter list with PX4 equivalent candidates, plus the full PX4 parameter inventory.

## Data Sources

- ArduPilot: `Sources/GuardianHQ/Resources/ArduPilotSitl/Tools/autotest/param_metadata/apm.pdef.json`
- PX4: `Parameter Reference | PX4 Guide (main)` snapshot parsed from parameter headings
- Location: top-level `Resources/DataPoints` (outside bundled app resources).

## Caveat

- "PX4 Equivalent" is best-effort heuristic matching for scanability; many AP params have no direct 1:1 PX4 equivalent.

- ArduPilot parameter count: **4742**
- PX4 parameter count: **2537**

## ArduPilot -> PX4 (Best-Effort Equivalents)

| ArduPilot Param | PX4 Equivalent Candidate | Match Score | Units | Display Name |
|---|---|---:|---|---|
| `ACRO_BAL_PITCH` | — | 0.00 | — | Acro Balance Pitch |
| `ACRO_BAL_ROLL` | — | 0.00 | — | Acro Balance Roll |
| `ACRO_OPTIONS` | — | 0.00 | — | Acro mode options |
| `ACRO_RP_EXPO` | — | 0.00 | — | Acro Roll/Pitch Expo |
| `ACRO_RP_RATE` | — | 0.00 | deg/s | Acro Roll and Pitch Rate |
| `ACRO_RP_RATE_TC` | — | 0.00 | s | Acro roll/pitch rate control input time constant |
| `ACRO_THR_MID` | — | 0.00 | — | Acro Thr Mid |
| `ACRO_TRAINER` | — | 0.00 | — | Acro Trainer |
| `ACRO_Y_EXPO` | — | 0.00 | — | Acro Yaw Expo |
| `ACRO_Y_RATE` | — | 0.00 | deg/s | Acro Yaw Rate |
| `ACRO_Y_RATE_TC` | — | 0.00 | s | Acro yaw rate control input time constant |
| `ADSB_EMIT_TYPE` | `ADSB_EMIT_TYPE` | 1.00 | — | Emitter type |
| `ADSB_ICAO_ID` | `ADSB_ICAO_ID` | 1.00 | — | ICAO_ID vehicle identification number |
| `ADSB_ICAO_SPECL` | `ADSB_ICAO_SPECL` | 1.00 | — | ICAO_ID of special vehicle |
| `ADSB_LEN_WIDTH` | `ADSB_LEN_WIDTH` | 1.00 | — | Aircraft length and width |
| `ADSB_LIST_ALT` | `ADSB_LIST_MAX` | 0.62 | m | ADSB vehicle list altitude filter |
| `ADSB_LIST_MAX` | `ADSB_LIST_MAX` | 1.00 | — | ADSB vehicle list size |
| `ADSB_LIST_RADIUS` | `ADSB_LIST_MAX` | 0.62 | m | ADSB vehicle list radius filter |
| `ADSB_LOG` | `ADSB_EMIT_TYPE` | 0.45 | — | ADS-B logging |
| `ADSB_OFFSET_LAT` | `ADSB_GPS_OFF_LAT` | 0.52 | — | GPS antenna lateral offset |
| `ADSB_OFFSET_LON` | `ADSB_GPS_OFF_LON` | 0.52 | — | GPS antenna longitudinal offset |
| `ADSB_OPTIONS` | `ADSB_EMIT_TYPE` | 0.45 | — | ADS-B Options |
| `ADSB_RF_CAPABLE` | `ADSB_EMIT_TYPE` | 0.37 | — | RF capabilities |
| `ADSB_RF_SELECT` | `ADSB_EMIT_TYPE` | 0.37 | — | Transceiver RF selection |
| `ADSB_SQUAWK` | `ADSB_SQUAWK` | 1.00 | octal | Squawk code |
| `ADSB_TYPE` | `ADSB_EMIT_TYPE` | 0.62 | — | ADSB Type |
| `AEROM_ALT_ABORT` | — | 0.00 | m | Altitude Abort |
| `AEROM_ANG_ACCEL` | — | 0.00 | deg/s/s | Angular acceleration limit |
| `AEROM_ANG_TC` | — | 0.00 | s | Roll control filtertime constant |
| `AEROM_BOX_WIDTH` | — | 0.00 | m | Box Width |
| `AEROM_DEBUG` | — | 0.00 | — | Debug control |
| `AEROM_ENTRY_RATE` | — | 0.00 | deg/s | The roll rate to use when entering a roll maneuver |
| `AEROM_ERR_COR_D` | — | 0.00 | — | D gain for path error corrections |
| `AEROM_ERR_COR_P` | — | 0.00 | — | P gain for path error corrections |
| `AEROM_KE_RUDD` | — | 0.00 | % | KnifeEdge Rudder |
| `AEROM_KE_RUDD_LK` | — | 0.00 | s | KnifeEdge Rudder lookahead |
| `AEROM_LKAHD` | — | 0.00 | s | Lookahead |
| `AEROM_MIS_ANGLE` | — | 0.00 | deg | Mission angle |
| `AEROM_OPTIONS` | — | 0.00 | deg | Aerobatic options |
| `AEROM_PATH_SCALE` | — | 0.00 | — | Path Scale |
| `AEROM_ROL_COR_TC` | — | 0.00 | s | Roll control time constant |
| `AEROM_SPD_I` | — | 0.00 | % | I gain for speed controller |
| `AEROM_SPD_P` | — | 0.00 | % | P gain for speed controller |
| `AEROM_STALL_PIT` | — | 0.00 | deg | Stall turn pitch threshold |
| `AEROM_STALL_THR` | — | 0.00 | % | Stall turn throttle |
| `AEROM_THR_BOOST` | — | 0.00 | % | Throttle boost |
| `AEROM_THR_LKAHD` | — | 0.00 | s | The lookahead for throttle control |
| `AEROM_THR_MIN` | — | 0.00 | % | Minimum Throttle |
| `AEROM_THR_PIT_FF` | — | 0.00 | % | Throttle feed forward from pitch |
| `AEROM_TIME_COR_P` | — | 0.00 | s | Time constant for correction of our distance along the path |
| `AEROM_TS_I` | — | 0.00 | — | Timesync I gain |
| `AEROM_TS_P` | — | 0.00 | — | Timesync P gain |
| `AEROM_TS_RATE` | — | 0.00 | Hz | Timesync rate of send of NAMED_VALUE_FLOAT data |
| `AEROM_TS_SPDMAX` | — | 0.00 | m/s | Timesync speed max |
| `AEROM_YAW_ACCEL` | — | 0.00 | deg/s/s | Yaw acceleration |
| `AFS_AMSL_ERR_GPS` | — | 0.00 | m | Error margin for GPS based AMSL limit |
| `AFS_AMSL_LIMIT` | — | 0.00 | m | AMSL limit |
| `AFS_DUAL_LOSS` | — | 0.00 | — | Enable dual loss terminate due to failure of both GCS and GPS simultaneously |
| `AFS_ENABLE` | — | 0.00 | — | Enable Advanced Failsafe |
| `AFS_GCS_TIMEOUT` | — | 0.00 | s | GCS timeout |
| `AFS_GEOFENCE` | — | 0.00 | — | Enable geofence Advanced Failsafe |
| `AFS_HB_PIN` | — | 0.00 | — | Heartbeat Pin |
| `AFS_MAN_PIN` | — | 0.00 | — | Manual Pin |
| `AFS_MAX_COM_LOSS` | `COM_RAM_MAX` | 0.40 | — | Maximum number of comms loss events |
| `AFS_MAX_GPS_LOSS` | `GPS_2_GNSS` | 0.30 | — | Maximum number of GPS loss events |
| `AFS_MAX_RANGE` | — | 0.00 | km | Max allowed range |
| `AFS_OPTIONS` | — | 0.00 | — | AFS options |
| `AFS_QNH_PRESSURE` | — | 0.00 | hPa | QNH pressure |
| `AFS_RC` | `RC14_MAX` | 0.33 | — | Enable RC Advanced Failsafe |
| `AFS_RC_FAIL_TIME` | — | 0.00 | s | RC failure time |
| `AFS_RC_MAN_ONLY` | — | 0.00 | — | Enable RC Termination only in manual control modes |
| `AFS_TERMINATE` | — | 0.00 | — | Force Terminate |
| `AFS_TERM_ACTION` | — | 0.00 | — | Terminate action |
| `AFS_TERM_PIN` | — | 0.00 | — | Terminate Pin |
| `AFS_WP_COMMS` | — | 0.00 | — | Comms Waypoint |
| `AFS_WP_GPS_LOSS` | `GPS_2_GNSS` | 0.30 | — | GPS Loss Waypoint |
| `AHRS_COMP_BETA` | — | 0.00 | — | AHRS Velocity Complementary Filter Beta Coefficient |
| `AHRS_CUSTOM_PIT` | — | 0.00 | deg | Board orientation pitch offset |
| `AHRS_CUSTOM_ROLL` | — | 0.00 | deg | Board orientation roll offset |
| `AHRS_CUSTOM_YAW` | — | 0.00 | deg | Board orientation yaw offset |
| `AHRS_EKF_TYPE` | `EKF2_EN` | 0.50 | — | Use NavEKF Kalman filter for attitude and position estimation |
| `AHRS_GPS_GAIN` | `GPS_2_GNSS` | 0.35 | — | AHRS GPS gain |
| `AHRS_GPS_MINSATS` | `GPS_2_GNSS` | 0.35 | — | AHRS GPS Minimum satellites |
| `AHRS_GPS_USE` | `GPS_2_GNSS` | 0.35 | — | AHRS use GPS for DCM navigation and position-down |
| `AHRS_OPTIONS` | — | 0.00 | — | Optional AHRS behaviour |
| `AHRS_ORIENTATION` | — | 0.00 | — | Board Orientation |
| `AHRS_RP_P` | — | 0.00 | — | AHRS RP_P |
| `AHRS_TRIM_X` | — | 0.00 | rad | AHRS Trim Roll |
| `AHRS_TRIM_Y` | — | 0.00 | rad | AHRS Trim Pitch |
| `AHRS_TRIM_Z` | — | 0.00 | rad | AHRS Trim Yaw |
| `AHRS_WIND_MAX` | — | 0.00 | m/s | Maximum wind |
| `AHRS_YAW_P` | — | 0.00 | — | Yaw P |
| `AIS_LIST_MAX` | — | 0.00 | — | AIS vessel list size |
| `AIS_LOGGING` | — | 0.00 | — | AIS logging options |
| `AIS_TIME_OUT` | — | 0.00 | s | AIS vessel time out |
| `AIS_TYPE` | — | 0.00 | — | AIS receiver type |
| `ANGLE_MAX` | — | 0.00 | cdeg | Angle Max |
| `ARMING_ACCTHRESH` | — | 0.00 | m/s/s | Accelerometer error threshold |
| `ARMING_CHECK` | — | 0.00 | — | Arm Checks to Perform (bitmask) |
| `ARMING_CRSDP_IGN` | — | 0.00 | — | Disable CrashDump Arming check |
| `ARMING_MAGTHRESH` | — | 0.00 | mGauss | Compass magnetic field strength error threshold vs earth magnetic model |
| `ARMING_MIS_ITEMS` | — | 0.00 | — | Required mission items |
| `ARMING_NEED_LOC` | — | 0.00 | — | Require vehicle location |
| `ARMING_OPTIONS` | — | 0.00 | — | Arming options |
| `ARMING_RUDDER` | — | 0.00 | — | Arming with Rudder enable/disable |
| `AROT_AS_ACC_MAX` | — | 0.00 | cm/s/s | Forward Acceleration Limit |
| `AROT_COL_FILT_E` | — | 0.00 | Hz | Entry Phase Collective Filter |
| `AROT_COL_FILT_G` | — | 0.00 | Hz | Glide Phase Collective Filter |
| `AROT_ENABLE` | — | 0.00 | — | Enable settings for RSC Setpoint |
| `AROT_FW_V_FF` | `FW_RR_FF` | 0.40 | — | Velocity (horizontal) feed forward |
| `AROT_FW_V_P` | `FW_P_TC` | 0.40 | — | Velocity (horizontal) P gain |
| `AROT_HS_P` | — | 0.00 | — | P gain for head speed controller |
| `AROT_HS_SENSOR` | — | 0.00 | s | Main Rotor RPM Sensor |
| `AROT_HS_SET_PT` | — | 0.00 | RPM | Target Head Speed |
| `AROT_TARG_SP` | — | 0.00 | cm/s | Target Glide Ground Speed |
| `ARSPD2_AUTOCAL` | — | 0.00 | — | This parameter and function is not used by this vehicle. Always set to 0. |
| `ARSPD2_BUS` | — | 0.00 | — | Airspeed I2C bus |
| `ARSPD2_DEVID` | — | 0.00 | — | Airspeed ID |
| `ARSPD2_OFFSET` | — | 0.00 | — | Airspeed offset |
| `ARSPD2_PIN` | — | 0.00 | — | Airspeed pin |
| `ARSPD2_PSI_RANGE` | — | 0.00 | — | The PSI range of the device |
| `ARSPD2_RATIO` | — | 0.00 | — | Airspeed ratio |
| `ARSPD2_SKIP_CAL` | — | 0.00 | — | Skip airspeed offset calibration on startup |
| `ARSPD2_TUBE_ORDR` | — | 0.00 | — | Control pitot tube order |
| `ARSPD2_TYPE` | — | 0.00 | — | Airspeed type |
| `ARSPD2_USE` | — | 0.00 | — | Airspeed use |
| `ARSPD_AUTOCAL` | — | 0.00 | — | This parameter and function is not used by this vehicle. Always set to 0. |
| `ARSPD_BUS` | — | 0.00 | — | Airspeed I2C bus |
| `ARSPD_DEVID` | — | 0.00 | — | Airspeed ID |
| `ARSPD_ENABLE` | — | 0.00 | — | Airspeed Enable |
| `ARSPD_OFFSET` | — | 0.00 | — | Airspeed offset |
| `ARSPD_OFF_PCNT` | — | 0.00 | % | Maximum offset cal speed error |
| `ARSPD_OPTIONS` | — | 0.00 | — | Airspeed options bitmask |
| `ARSPD_PIN` | — | 0.00 | — | Airspeed pin |
| `ARSPD_PRIMARY` | — | 0.00 | — | Primary airspeed sensor |
| `ARSPD_PSI_RANGE` | — | 0.00 | — | The PSI range of the device |
| `ARSPD_RATIO` | — | 0.00 | — | Airspeed ratio |
| `ARSPD_SKIP_CAL` | — | 0.00 | — | Skip airspeed offset calibration on startup |
| `ARSPD_TUBE_ORDER` | — | 0.00 | — | Control pitot tube order |
| `ARSPD_TUBE_ORDR` | — | 0.00 | — | Control pitot tube order |
| `ARSPD_TYPE` | — | 0.00 | — | Airspeed type |
| `ARSPD_USE` | — | 0.00 | — | Airspeed use |
| `ARSPD_WIND_GATE` | — | 0.00 | — | Re-enable Consistency Check Gate Size |
| `ARSPD_WIND_MAX` | — | 0.00 | m/s | Maximum airspeed and ground speed difference |
| `ARSPD_WIND_WARN` | — | 0.00 | m/s | Airspeed and GPS speed difference that gives a warning |
| `ATC_ACCEL_P_MAX` | — | 0.00 | cdeg/s/s | Acceleration Max for Pitch |
| `ATC_ACCEL_R_MAX` | — | 0.00 | cdeg/s/s | Acceleration Max for Roll |
| `ATC_ACCEL_Y_MAX` | — | 0.00 | cdeg/s/s | Acceleration Max for Yaw |
| `ATC_ANGLE_BOOST` | — | 0.00 | — | Angle Boost |
| `ATC_ANG_LIM_TC` | — | 0.00 | — | Angle Limit (to maintain altitude) Time Constant |
| `ATC_ANG_PIT_P` | — | 0.00 | — | Pitch axis angle controller P gain |
| `ATC_ANG_RLL_P` | — | 0.00 | — | Roll axis angle controller P gain |
| `ATC_ANG_YAW_P` | — | 0.00 | — | Yaw axis angle controller P gain |
| `ATC_HOVR_ROL_TRM` | — | 0.00 | cdeg | Hover Roll Trim |
| `ATC_INPUT_TC` | — | 0.00 | s | Attitude control input time constant |
| `ATC_LAND_P_MULT` | — | 0.00 | — | Landed pitch gain multiplier |
| `ATC_LAND_R_MULT` | — | 0.00 | — | Landed roll gain multiplier |
| `ATC_LAND_Y_MULT` | — | 0.00 | — | Landed yaw gain multiplier |
| `ATC_PIRO_COMP` | — | 0.00 | — | Piro Comp Enable |
| `ATC_RATE_FF_ENAB` | — | 0.00 | — | Rate Feedforward Enable |
| `ATC_RATE_P_MAX` | — | 0.00 | deg/s | Angular Velocity Max for Pitch |
| `ATC_RATE_R_MAX` | — | 0.00 | deg/s | Angular Velocity Max for Roll |
| `ATC_RATE_Y_MAX` | — | 0.00 | deg/s | Angular Velocity Max for Yaw |
| `ATC_RAT_PIT_D` | — | 0.00 | — | Pitch axis rate controller D gain |
| `ATC_RAT_PIT_D_FF` | — | 0.00 | — | Pitch Derivative FeedForward Gain |
| `ATC_RAT_PIT_FF` | — | 0.00 | — | Pitch axis rate controller feed forward |
| `ATC_RAT_PIT_FLTD` | — | 0.00 | Hz | Pitch axis rate controller derivative frequency in Hz |
| `ATC_RAT_PIT_FLTE` | — | 0.00 | Hz | Pitch axis rate controller error frequency in Hz |
| `ATC_RAT_PIT_FLTT` | — | 0.00 | Hz | Pitch axis rate controller target frequency in Hz |
| `ATC_RAT_PIT_I` | — | 0.00 | — | Pitch axis rate controller I gain |
| `ATC_RAT_PIT_ILMI` | — | 0.00 | — | Pitch axis rate controller I-term leak minimum |
| `ATC_RAT_PIT_IMAX` | — | 0.00 | — | Pitch axis rate controller I gain maximum |
| `ATC_RAT_PIT_NEF` | — | 0.00 | — | Pitch Error notch filter index |
| `ATC_RAT_PIT_NTF` | — | 0.00 | — | Pitch Target notch filter index |
| `ATC_RAT_PIT_P` | — | 0.00 | — | Pitch axis rate controller P gain |
| `ATC_RAT_PIT_PDMX` | — | 0.00 | — | Pitch axis rate controller PD sum maximum |
| `ATC_RAT_PIT_SMAX` | — | 0.00 | — | Pitch slew rate limit |
| `ATC_RAT_RLL_D` | — | 0.00 | — | Roll axis rate controller D gain |
| `ATC_RAT_RLL_D_FF` | — | 0.00 | — | Roll Derivative FeedForward Gain |
| `ATC_RAT_RLL_FF` | — | 0.00 | — | Roll axis rate controller feed forward |
| `ATC_RAT_RLL_FLTD` | — | 0.00 | Hz | Roll axis rate controller derivative frequency in Hz |
| `ATC_RAT_RLL_FLTE` | — | 0.00 | Hz | Roll axis rate controller error frequency in Hz |
| `ATC_RAT_RLL_FLTT` | — | 0.00 | Hz | Roll axis rate controller target frequency in Hz |
| `ATC_RAT_RLL_I` | — | 0.00 | — | Roll axis rate controller I gain |
| `ATC_RAT_RLL_ILMI` | — | 0.00 | — | Roll axis rate controller I-term leak minimum |
| `ATC_RAT_RLL_IMAX` | — | 0.00 | — | Roll axis rate controller I gain maximum |
| `ATC_RAT_RLL_NEF` | — | 0.00 | — | Roll Error notch filter index |
| `ATC_RAT_RLL_NTF` | — | 0.00 | — | Roll Target notch filter index |
| `ATC_RAT_RLL_P` | — | 0.00 | — | Roll axis rate controller P gain |
| `ATC_RAT_RLL_PDMX` | — | 0.00 | — | Roll axis rate controller PD sum maximum |
| `ATC_RAT_RLL_SMAX` | — | 0.00 | — | Roll slew rate limit |
| `ATC_RAT_YAW_D` | — | 0.00 | — | Yaw axis rate controller D gain |
| `ATC_RAT_YAW_D_FF` | — | 0.00 | — | Yaw Derivative FeedForward Gain |
| `ATC_RAT_YAW_FF` | — | 0.00 | — | Yaw axis rate controller feed forward |
| `ATC_RAT_YAW_FLTD` | — | 0.00 | Hz | Yaw axis rate controller derivative frequency in Hz |
| `ATC_RAT_YAW_FLTE` | — | 0.00 | Hz | Yaw axis rate controller error frequency in Hz |
| `ATC_RAT_YAW_FLTT` | — | 0.00 | Hz | Yaw axis rate controller target frequency in Hz |
| `ATC_RAT_YAW_I` | — | 0.00 | — | Yaw axis rate controller I gain |
| `ATC_RAT_YAW_ILMI` | — | 0.00 | — | Yaw axis rate controller I-term leak minimum |
| `ATC_RAT_YAW_IMAX` | — | 0.00 | — | Yaw axis rate controller I gain maximum |
| `ATC_RAT_YAW_NEF` | — | 0.00 | — | Yaw Error notch filter index |
| `ATC_RAT_YAW_NTF` | — | 0.00 | Hz | Yaw Target notch filter index |
| `ATC_RAT_YAW_P` | — | 0.00 | — | Yaw axis rate controller P gain |
| `ATC_RAT_YAW_PDMX` | — | 0.00 | — | Yaw axis rate controller PD sum maximum |
| `ATC_RAT_YAW_SMAX` | — | 0.00 | — | Yaw slew rate limit |
| `ATC_SLEW_YAW` | — | 0.00 | cdeg/s | Yaw target slew rate |
| `ATC_THR_G_BOOST` | — | 0.00 | — | Throttle-gain boost |
| `ATC_THR_MIX_MAN` | — | 0.00 | — | Throttle Mix Manual |
| `ATC_THR_MIX_MAX` | — | 0.00 | — | Throttle Mix Maximum |
| `ATC_THR_MIX_MIN` | — | 0.00 | — | Throttle Mix Minimum |
| `AUTOTUNE_ACC_MAX` | — | 0.00 | — | AutoTune maximum allowable angular acceleration |
| `AUTOTUNE_AGGR` | — | 0.00 | — | Autotune aggressiveness |
| `AUTOTUNE_AXES` | — | 0.00 | — | Autotune axis bitmask |
| `AUTOTUNE_FRQ_MAX` | — | 0.00 | — | AutoTune maximum sweep frequency |
| `AUTOTUNE_FRQ_MIN` | — | 0.00 | — | AutoTune minimum sweep frequency |
| `AUTOTUNE_GN_MAX` | — | 0.00 | — | AutoTune maximum response gain |
| `AUTOTUNE_MIN_D` | — | 0.00 | — | AutoTune minimum D |
| `AUTOTUNE_RAT_MAX` | — | 0.00 | — | Autotune maximum allowable angular rate |
| `AUTOTUNE_SEQ` | — | 0.00 | — | AutoTune Sequence Bitmask |
| `AUTOTUNE_VELXY_P` | — | 0.00 | — | AutoTune velocity xy P gain |
| `AUTO_OPTIONS` | — | 0.00 | — | Auto mode options |
| `AVD_ENABLE` | — | 0.00 | — | Enable Avoidance using ADSB |
| `AVD_F_ACTION` | — | 0.00 | — | Collision Avoidance Behavior |
| `AVD_F_ALT_MIN` | — | 0.00 | m | ADS-B avoidance minimum altitude |
| `AVD_F_DIST_XY` | — | 0.00 | m | Distance Fail XY |
| `AVD_F_DIST_Z` | — | 0.00 | m | Distance Fail Z |
| `AVD_F_RCVRY` | — | 0.00 | — | Recovery behaviour after a fail event |
| `AVD_F_TIME` | — | 0.00 | s | Time Horizon Fail |
| `AVD_OBS_MAX` | — | 0.00 | — | Maximum number of obstacles to track |
| `AVD_W_ACTION` | — | 0.00 | — | Collision Avoidance Behavior - Warn |
| `AVD_W_DIST_XY` | — | 0.00 | m | Distance Warn XY |
| `AVD_W_DIST_Z` | — | 0.00 | m | Distance Warn Z |
| `AVD_W_TIME` | — | 0.00 | s | Time Horizon Warn |
| `AVOID_ACCEL_MAX` | — | 0.00 | m/s/s | Avoidance maximum acceleration |
| `AVOID_ALT_MIN` | — | 0.00 | m | Avoidance minimum altitude |
| `AVOID_ANGLE_MAX` | — | 0.00 | cdeg | Avoidance max lean angle in non-GPS flight modes |
| `AVOID_BACKUP_DZ` | — | 0.00 | m | Avoidance deadzone between stopping and backing away from obstacle |
| `AVOID_BACKUP_SPD` | — | 0.00 | m/s | Avoidance maximum horizontal backup speed |
| `AVOID_BACKZ_SPD` | — | 0.00 | m/s | Avoidance maximum vertical backup speed |
| `AVOID_BEHAVE` | — | 0.00 | — | Avoidance behaviour |
| `AVOID_DIST_MAX` | — | 0.00 | m | Avoidance distance maximum in non-GPS flight modes |
| `AVOID_ENABLE` | — | 0.00 | — | Avoidance control enable/disable |
| `AVOID_MARGIN` | — | 0.00 | m | Avoidance distance margin in GPS modes |
| `BARO1_DEVID` | — | 0.00 | — | Baro ID |
| `BARO1_GND_PRESS` | — | 0.00 | Pa | Ground Pressure |
| `BARO1_WCF_BCK` | — | 0.00 | — | Pressure error coefficient in negative X direction (backwards) |
| `BARO1_WCF_DN` | — | 0.00 | — | Pressure error coefficient in negative Z direction (down) |
| `BARO1_WCF_ENABLE` | — | 0.00 | — | Wind coefficient enable |
| `BARO1_WCF_FWD` | — | 0.00 | — | Pressure error coefficient in positive X direction (forward) |
| `BARO1_WCF_LFT` | — | 0.00 | — | Pressure error coefficient in negative Y direction (left) |
| `BARO1_WCF_RGT` | — | 0.00 | — | Pressure error coefficient in positive Y direction (right) |
| `BARO1_WCF_UP` | — | 0.00 | — | Pressure error coefficient in positive Z direction (up) |
| `BARO2_DEVID` | — | 0.00 | — | Baro ID2 |
| `BARO2_GND_PRESS` | — | 0.00 | Pa | Ground Pressure |
| `BARO2_WCF_BCK` | — | 0.00 | — | Pressure error coefficient in negative X direction (backwards) |
| `BARO2_WCF_DN` | — | 0.00 | — | Pressure error coefficient in negative Z direction (down) |
| `BARO2_WCF_ENABLE` | — | 0.00 | — | Wind coefficient enable |
| `BARO2_WCF_FWD` | — | 0.00 | — | Pressure error coefficient in positive X direction (forward) |
| `BARO2_WCF_LFT` | — | 0.00 | — | Pressure error coefficient in negative Y direction (left) |
| `BARO2_WCF_RGT` | — | 0.00 | — | Pressure error coefficient in positive Y direction (right) |
| `BARO2_WCF_UP` | — | 0.00 | — | Pressure error coefficient in positive Z direction (up) |
| `BARO3_DEVID` | — | 0.00 | — | Baro ID3 |
| `BARO3_GND_PRESS` | — | 0.00 | Pa | Absolute Pressure |
| `BARO3_WCF_BCK` | — | 0.00 | — | Pressure error coefficient in negative X direction (backwards) |
| `BARO3_WCF_DN` | — | 0.00 | — | Pressure error coefficient in negative Z direction (down) |
| `BARO3_WCF_ENABLE` | — | 0.00 | — | Wind coefficient enable |
| `BARO3_WCF_FWD` | — | 0.00 | — | Pressure error coefficient in positive X direction (forward) |
| `BARO3_WCF_LFT` | — | 0.00 | — | Pressure error coefficient in negative Y direction (left) |
| `BARO3_WCF_RGT` | — | 0.00 | — | Pressure error coefficient in positive Y direction (right) |
| `BARO3_WCF_UP` | — | 0.00 | — | Pressure error coefficient in positive Z direction (up) |
| `BARO_ALTERR_MAX` | — | 0.00 | m | Altitude error maximum |
| `BARO_ALT_OFFSET` | — | 0.00 | m | altitude offset |
| `BARO_EXT_BUS` | — | 0.00 | — | External baro bus |
| `BARO_FIELD_ELV` | — | 0.00 | m | field elevation |
| `BARO_FLTR_RNG` | — | 0.00 | % | Range in which sample is accepted |
| `BARO_GND_TEMP` | — | 0.00 | degC | ground temperature |
| `BARO_OPTIONS` | — | 0.00 | — | Barometer options |
| `BARO_PRIMARY` | — | 0.00 | — | Primary barometer |
| `BARO_PROBE_EXT` | — | 0.00 | — | External barometers to probe |
| `BATT2_AMP_OFFSET` | `BAT_AVRG_CURRENT` | 0.70 | V | AMP offset |
| `BATT2_AMP_PERVLT` | `BAT_AVRG_CURRENT` | 0.70 | A/V | Amps per volt |
| `BATT2_ARM_MAH` | `BAT2_CAPACITY` | 0.45 | mAh | Required arming remaining capacity |
| `BATT2_ARM_VOLT` | `BAT2_CAPACITY` | 0.45 | V | Required arming voltage |
| `BATT2_CAPACITY` | `BAT2_CAPACITY` | 1.00 | mAh | Battery capacity |
| `BATT2_CRT_MAH` | `BAT2_CAPACITY` | 0.45 | mAh | Battery critical capacity |
| `BATT2_CRT_VOLT` | `BAT2_CAPACITY` | 0.45 | V | Critical battery voltage |
| `BATT2_CURR_MULT` | `BAT_AVRG_CURRENT` | 0.70 | — | Scales reported power monitor current |
| `BATT2_CURR_PIN` | `BAT_AVRG_CURRENT` | 0.70 | — | Battery Current sensing pin |
| `BATT2_ESC_INDEX` | `BAT2_CAPACITY` | 0.45 | — | ESC Telemetry Index to write to |
| `BATT2_ESC_MASK` | `BAT2_CAPACITY` | 0.45 | — | ESC mask |
| `BATT2_FL_FF` | `BAT2_CAPACITY` | 0.45 | — | First order term |
| `BATT2_FL_FLTR` | `BAT2_CAPACITY` | 0.45 | Hz | Fuel level filter frequency |
| `BATT2_FL_FS` | `BAT2_CAPACITY` | 0.45 | — | Second order term |
| `BATT2_FL_FT` | `BAT2_CAPACITY` | 0.45 | — | Third order term |
| `BATT2_FL_OFF` | `BAT2_CAPACITY` | 0.45 | — | Offset term |
| `BATT2_FL_PIN` | `BAT2_CAPACITY` | 0.45 | — | Fuel level analog pin number |
| `BATT2_FL_VLT_MIN` | `BAT2_CAPACITY` | 0.40 | V | Empty fuel level voltage |
| `BATT2_FL_V_MULT` | `BAT2_V_FILT` | 0.60 | — | Fuel level voltage multiplier |
| `BATT2_FS_CRT_ACT` | `BAT2_CAPACITY` | 0.40 | — | Critical battery failsafe action |
| `BATT2_FS_LOW_ACT` | `BAT_LOW_THR` | 0.60 | — | Low battery failsafe action |
| `BATT2_FS_VOLTSRC` | `BAT2_CAPACITY` | 0.45 | — | Failsafe voltage source |
| `BATT2_I2C_ADDR` | `BAT2_CAPACITY` | 0.45 | — | Battery monitor I2C address |
| `BATT2_I2C_BUS` | `BAT2_CAPACITY` | 0.45 | — | Battery monitor I2C bus number |
| `BATT2_LOW_MAH` | `BAT_LOW_THR` | 0.70 | mAh | Low battery capacity |
| `BATT2_LOW_TIMER` | `BAT_LOW_THR` | 0.70 | s | Low voltage timeout |
| `BATT2_LOW_VOLT` | `BAT_LOW_THR` | 0.70 | V | Low battery voltage |
| `BATT2_MAX_AMPS` | `BAT2_CAPACITY` | 0.45 | A | Battery monitor max current |
| `BATT2_MAX_VOLT` | `BAT2_CAPACITY` | 0.45 | — | Maximum Battery Voltage |
| `BATT2_MONITOR` | `BAT2_CAPACITY` | 0.53 | — | Battery monitoring |
| `BATT2_OPTIONS` | `BAT2_CAPACITY` | 0.53 | — | Battery monitor options |
| `BATT2_SERIAL_NUM` | `BAT2_CAPACITY` | 0.45 | — | Battery serial number |
| `BATT2_SHUNT` | `BAT2_CAPACITY` | 0.53 | Ohm | Battery monitor shunt resistor |
| `BATT2_SUM_MASK` | `BAT2_CAPACITY` | 0.45 | — | Battery Sum mask |
| `BATT2_VLT_OFFSET` | `BAT2_CAPACITY` | 0.45 | V | Voltage offset |
| `BATT2_VOLT_MULT` | `BAT1_C_MULT` | 0.70 | — | Voltage Multiplier |
| `BATT2_VOLT_PIN` | `BAT2_CAPACITY` | 0.45 | — | Battery Voltage sensing pin |
| `BATT3_AMP_OFFSET` | `BAT_AVRG_CURRENT` | 0.70 | V | AMP offset |
| `BATT3_AMP_PERVLT` | `BAT_AVRG_CURRENT` | 0.70 | A/V | Amps per volt |
| `BATT3_ARM_MAH` | `BAT2_CAPACITY` | 0.45 | mAh | Required arming remaining capacity |
| `BATT3_ARM_VOLT` | `BAT2_CAPACITY` | 0.45 | V | Required arming voltage |
| `BATT3_CAPACITY` | `BAT2_CAPACITY` | 1.00 | mAh | Battery capacity |
| `BATT3_CRT_MAH` | `BAT2_CAPACITY` | 0.45 | mAh | Battery critical capacity |
| `BATT3_CRT_VOLT` | `BAT2_CAPACITY` | 0.45 | V | Critical battery voltage |
| `BATT3_CURR_MULT` | `BAT_AVRG_CURRENT` | 0.70 | — | Scales reported power monitor current |
| `BATT3_CURR_PIN` | `BAT_AVRG_CURRENT` | 0.70 | — | Battery Current sensing pin |
| `BATT3_ESC_INDEX` | `BAT2_CAPACITY` | 0.45 | — | ESC Telemetry Index to write to |
| `BATT3_ESC_MASK` | `BAT2_CAPACITY` | 0.45 | — | ESC mask |
| `BATT3_FL_FF` | `BAT2_CAPACITY` | 0.45 | — | First order term |
| `BATT3_FL_FLTR` | `BAT2_CAPACITY` | 0.45 | Hz | Fuel level filter frequency |
| `BATT3_FL_FS` | `BAT2_CAPACITY` | 0.45 | — | Second order term |
| `BATT3_FL_FT` | `BAT2_CAPACITY` | 0.45 | — | Third order term |
| `BATT3_FL_OFF` | `BAT2_CAPACITY` | 0.45 | — | Offset term |
| `BATT3_FL_PIN` | `BAT2_CAPACITY` | 0.45 | — | Fuel level analog pin number |
| `BATT3_FL_VLT_MIN` | `BAT2_CAPACITY` | 0.40 | V | Empty fuel level voltage |
| `BATT3_FL_V_MULT` | `BAT2_V_FILT` | 0.60 | — | Fuel level voltage multiplier |
| `BATT3_FS_CRT_ACT` | `BAT2_CAPACITY` | 0.40 | — | Critical battery failsafe action |
| `BATT3_FS_LOW_ACT` | `BAT_LOW_THR` | 0.60 | — | Low battery failsafe action |
| `BATT3_FS_VOLTSRC` | `BAT2_CAPACITY` | 0.45 | — | Failsafe voltage source |
| `BATT3_I2C_ADDR` | `BAT2_CAPACITY` | 0.45 | — | Battery monitor I2C address |
| `BATT3_I2C_BUS` | `BAT2_CAPACITY` | 0.45 | — | Battery monitor I2C bus number |
| `BATT3_LOW_MAH` | `BAT_LOW_THR` | 0.70 | mAh | Low battery capacity |
| `BATT3_LOW_TIMER` | `BAT_LOW_THR` | 0.70 | s | Low voltage timeout |
| `BATT3_LOW_VOLT` | `BAT_LOW_THR` | 0.70 | V | Low battery voltage |
| `BATT3_MAX_AMPS` | `BAT2_CAPACITY` | 0.45 | A | Battery monitor max current |
| `BATT3_MAX_VOLT` | `BAT2_CAPACITY` | 0.45 | — | Maximum Battery Voltage |
| `BATT3_MONITOR` | `BAT2_CAPACITY` | 0.53 | — | Battery monitoring |
| `BATT3_OPTIONS` | `BAT2_CAPACITY` | 0.53 | — | Battery monitor options |
| `BATT3_SERIAL_NUM` | `BAT2_CAPACITY` | 0.45 | — | Battery serial number |
| `BATT3_SHUNT` | `BAT2_CAPACITY` | 0.53 | Ohm | Battery monitor shunt resistor |
| `BATT3_SUM_MASK` | `BAT2_CAPACITY` | 0.45 | — | Battery Sum mask |
| `BATT3_VLT_OFFSET` | `BAT2_CAPACITY` | 0.45 | V | Voltage offset |
| `BATT3_VOLT_MULT` | `BAT1_C_MULT` | 0.70 | — | Voltage Multiplier |
| `BATT3_VOLT_PIN` | `BAT2_CAPACITY` | 0.45 | — | Battery Voltage sensing pin |
| `BATT4_AMP_OFFSET` | `BAT_AVRG_CURRENT` | 0.70 | V | AMP offset |
| `BATT4_AMP_PERVLT` | `BAT_AVRG_CURRENT` | 0.70 | A/V | Amps per volt |
| `BATT4_ARM_MAH` | `BAT2_CAPACITY` | 0.45 | mAh | Required arming remaining capacity |
| `BATT4_ARM_VOLT` | `BAT2_CAPACITY` | 0.45 | V | Required arming voltage |
| `BATT4_CAPACITY` | `BAT2_CAPACITY` | 1.00 | mAh | Battery capacity |
| `BATT4_CRT_MAH` | `BAT2_CAPACITY` | 0.45 | mAh | Battery critical capacity |
| `BATT4_CRT_VOLT` | `BAT2_CAPACITY` | 0.45 | V | Critical battery voltage |
| `BATT4_CURR_MULT` | `BAT_AVRG_CURRENT` | 0.70 | — | Scales reported power monitor current |
| `BATT4_CURR_PIN` | `BAT_AVRG_CURRENT` | 0.70 | — | Battery Current sensing pin |
| `BATT4_ESC_INDEX` | `BAT2_CAPACITY` | 0.45 | — | ESC Telemetry Index to write to |
| `BATT4_ESC_MASK` | `BAT2_CAPACITY` | 0.45 | — | ESC mask |
| `BATT4_FL_FF` | `BAT2_CAPACITY` | 0.45 | — | First order term |
| `BATT4_FL_FLTR` | `BAT2_CAPACITY` | 0.45 | Hz | Fuel level filter frequency |
| `BATT4_FL_FS` | `BAT2_CAPACITY` | 0.45 | — | Second order term |
| `BATT4_FL_FT` | `BAT2_CAPACITY` | 0.45 | — | Third order term |
| `BATT4_FL_OFF` | `BAT2_CAPACITY` | 0.45 | — | Offset term |
| `BATT4_FL_PIN` | `BAT2_CAPACITY` | 0.45 | — | Fuel level analog pin number |
| `BATT4_FL_VLT_MIN` | `BAT2_CAPACITY` | 0.40 | V | Empty fuel level voltage |
| `BATT4_FL_V_MULT` | `BAT2_V_FILT` | 0.60 | — | Fuel level voltage multiplier |
| `BATT4_FS_CRT_ACT` | `BAT2_CAPACITY` | 0.40 | — | Critical battery failsafe action |
| `BATT4_FS_LOW_ACT` | `BAT_LOW_THR` | 0.60 | — | Low battery failsafe action |
| `BATT4_FS_VOLTSRC` | `BAT2_CAPACITY` | 0.45 | — | Failsafe voltage source |
| `BATT4_I2C_ADDR` | `BAT2_CAPACITY` | 0.45 | — | Battery monitor I2C address |
| `BATT4_I2C_BUS` | `BAT2_CAPACITY` | 0.45 | — | Battery monitor I2C bus number |
| `BATT4_LOW_MAH` | `BAT_LOW_THR` | 0.70 | mAh | Low battery capacity |
| `BATT4_LOW_TIMER` | `BAT_LOW_THR` | 0.70 | s | Low voltage timeout |
| `BATT4_LOW_VOLT` | `BAT_LOW_THR` | 0.70 | V | Low battery voltage |
| `BATT4_MAX_AMPS` | `BAT2_CAPACITY` | 0.45 | A | Battery monitor max current |
| `BATT4_MAX_VOLT` | `BAT2_CAPACITY` | 0.45 | — | Maximum Battery Voltage |
| `BATT4_MONITOR` | `BAT2_CAPACITY` | 0.53 | — | Battery monitoring |
| `BATT4_OPTIONS` | `BAT2_CAPACITY` | 0.53 | — | Battery monitor options |
| `BATT4_SERIAL_NUM` | `BAT2_CAPACITY` | 0.45 | — | Battery serial number |
| `BATT4_SHUNT` | `BAT2_CAPACITY` | 0.53 | Ohm | Battery monitor shunt resistor |
| `BATT4_SUM_MASK` | `BAT2_CAPACITY` | 0.45 | — | Battery Sum mask |
| `BATT4_VLT_OFFSET` | `BAT2_CAPACITY` | 0.45 | V | Voltage offset |
| `BATT4_VOLT_MULT` | `BAT1_C_MULT` | 0.70 | — | Voltage Multiplier |
| `BATT4_VOLT_PIN` | `BAT2_CAPACITY` | 0.45 | — | Battery Voltage sensing pin |
| `BATT5_AMP_OFFSET` | `BAT_AVRG_CURRENT` | 0.70 | V | AMP offset |
| `BATT5_AMP_PERVLT` | `BAT_AVRG_CURRENT` | 0.70 | A/V | Amps per volt |
| `BATT5_ARM_MAH` | `BAT2_CAPACITY` | 0.45 | mAh | Required arming remaining capacity |
| `BATT5_ARM_VOLT` | `BAT2_CAPACITY` | 0.45 | V | Required arming voltage |
| `BATT5_CAPACITY` | `BAT2_CAPACITY` | 1.00 | mAh | Battery capacity |
| `BATT5_CRT_MAH` | `BAT2_CAPACITY` | 0.45 | mAh | Battery critical capacity |
| `BATT5_CRT_VOLT` | `BAT2_CAPACITY` | 0.45 | V | Critical battery voltage |
| `BATT5_CURR_MULT` | `BAT_AVRG_CURRENT` | 0.70 | — | Scales reported power monitor current |
| `BATT5_CURR_PIN` | `BAT_AVRG_CURRENT` | 0.70 | — | Battery Current sensing pin |
| `BATT5_ESC_INDEX` | `BAT2_CAPACITY` | 0.45 | — | ESC Telemetry Index to write to |
| `BATT5_ESC_MASK` | `BAT2_CAPACITY` | 0.45 | — | ESC mask |
| `BATT5_FL_FF` | `BAT2_CAPACITY` | 0.45 | — | First order term |
| `BATT5_FL_FLTR` | `BAT2_CAPACITY` | 0.45 | Hz | Fuel level filter frequency |
| `BATT5_FL_FS` | `BAT2_CAPACITY` | 0.45 | — | Second order term |
| `BATT5_FL_FT` | `BAT2_CAPACITY` | 0.45 | — | Third order term |
| `BATT5_FL_OFF` | `BAT2_CAPACITY` | 0.45 | — | Offset term |
| `BATT5_FL_PIN` | `BAT2_CAPACITY` | 0.45 | — | Fuel level analog pin number |
| `BATT5_FL_VLT_MIN` | `BAT2_CAPACITY` | 0.40 | V | Empty fuel level voltage |
| `BATT5_FL_V_MULT` | `BAT2_V_FILT` | 0.60 | — | Fuel level voltage multiplier |
| `BATT5_FS_CRT_ACT` | `BAT2_CAPACITY` | 0.40 | — | Critical battery failsafe action |
| `BATT5_FS_LOW_ACT` | `BAT_LOW_THR` | 0.60 | — | Low battery failsafe action |
| `BATT5_FS_VOLTSRC` | `BAT2_CAPACITY` | 0.45 | — | Failsafe voltage source |
| `BATT5_I2C_ADDR` | `BAT2_CAPACITY` | 0.45 | — | Battery monitor I2C address |
| `BATT5_I2C_BUS` | `BAT2_CAPACITY` | 0.45 | — | Battery monitor I2C bus number |
| `BATT5_LOW_MAH` | `BAT_LOW_THR` | 0.70 | mAh | Low battery capacity |
| `BATT5_LOW_TIMER` | `BAT_LOW_THR` | 0.70 | s | Low voltage timeout |
| `BATT5_LOW_VOLT` | `BAT_LOW_THR` | 0.70 | V | Low battery voltage |
| `BATT5_MAX_AMPS` | `BAT2_CAPACITY` | 0.45 | A | Battery monitor max current |
| `BATT5_MAX_VOLT` | `BAT2_CAPACITY` | 0.45 | — | Maximum Battery Voltage |
| `BATT5_MONITOR` | `BAT2_CAPACITY` | 0.53 | — | Battery monitoring |
| `BATT5_OPTIONS` | `BAT2_CAPACITY` | 0.53 | — | Battery monitor options |
| `BATT5_SERIAL_NUM` | `BAT2_CAPACITY` | 0.45 | — | Battery serial number |
| `BATT5_SHUNT` | `BAT2_CAPACITY` | 0.53 | Ohm | Battery monitor shunt resistor |
| `BATT5_SUM_MASK` | `BAT2_CAPACITY` | 0.45 | — | Battery Sum mask |
| `BATT5_VLT_OFFSET` | `BAT2_CAPACITY` | 0.45 | V | Voltage offset |
| `BATT5_VOLT_MULT` | `BAT1_C_MULT` | 0.70 | — | Voltage Multiplier |
| `BATT5_VOLT_PIN` | `BAT2_CAPACITY` | 0.45 | — | Battery Voltage sensing pin |
| `BATT6_AMP_OFFSET` | `BAT_AVRG_CURRENT` | 0.70 | V | AMP offset |
| `BATT6_AMP_PERVLT` | `BAT_AVRG_CURRENT` | 0.70 | A/V | Amps per volt |
| `BATT6_ARM_MAH` | `BAT2_CAPACITY` | 0.45 | mAh | Required arming remaining capacity |
| `BATT6_ARM_VOLT` | `BAT2_CAPACITY` | 0.45 | V | Required arming voltage |
| `BATT6_CAPACITY` | `BAT2_CAPACITY` | 1.00 | mAh | Battery capacity |
| `BATT6_CRT_MAH` | `BAT2_CAPACITY` | 0.45 | mAh | Battery critical capacity |
| `BATT6_CRT_VOLT` | `BAT2_CAPACITY` | 0.45 | V | Critical battery voltage |
| `BATT6_CURR_MULT` | `BAT_AVRG_CURRENT` | 0.70 | — | Scales reported power monitor current |
| `BATT6_CURR_PIN` | `BAT_AVRG_CURRENT` | 0.70 | — | Battery Current sensing pin |
| `BATT6_ESC_INDEX` | `BAT2_CAPACITY` | 0.45 | — | ESC Telemetry Index to write to |
| `BATT6_ESC_MASK` | `BAT2_CAPACITY` | 0.45 | — | ESC mask |
| `BATT6_FL_FF` | `BAT2_CAPACITY` | 0.45 | — | First order term |
| `BATT6_FL_FLTR` | `BAT2_CAPACITY` | 0.45 | Hz | Fuel level filter frequency |
| `BATT6_FL_FS` | `BAT2_CAPACITY` | 0.45 | — | Second order term |
| `BATT6_FL_FT` | `BAT2_CAPACITY` | 0.45 | — | Third order term |
| `BATT6_FL_OFF` | `BAT2_CAPACITY` | 0.45 | — | Offset term |
| `BATT6_FL_PIN` | `BAT2_CAPACITY` | 0.45 | — | Fuel level analog pin number |
| `BATT6_FL_VLT_MIN` | `BAT2_CAPACITY` | 0.40 | V | Empty fuel level voltage |
| `BATT6_FL_V_MULT` | `BAT2_V_FILT` | 0.60 | — | Fuel level voltage multiplier |
| `BATT6_FS_CRT_ACT` | `BAT2_CAPACITY` | 0.40 | — | Critical battery failsafe action |
| `BATT6_FS_LOW_ACT` | `BAT_LOW_THR` | 0.60 | — | Low battery failsafe action |
| `BATT6_FS_VOLTSRC` | `BAT2_CAPACITY` | 0.45 | — | Failsafe voltage source |
| `BATT6_I2C_ADDR` | `BAT2_CAPACITY` | 0.45 | — | Battery monitor I2C address |
| `BATT6_I2C_BUS` | `BAT2_CAPACITY` | 0.45 | — | Battery monitor I2C bus number |
| `BATT6_LOW_MAH` | `BAT_LOW_THR` | 0.70 | mAh | Low battery capacity |
| `BATT6_LOW_TIMER` | `BAT_LOW_THR` | 0.70 | s | Low voltage timeout |
| `BATT6_LOW_VOLT` | `BAT_LOW_THR` | 0.70 | V | Low battery voltage |
| `BATT6_MAX_AMPS` | `BAT2_CAPACITY` | 0.45 | A | Battery monitor max current |
| `BATT6_MAX_VOLT` | `BAT2_CAPACITY` | 0.45 | — | Maximum Battery Voltage |
| `BATT6_MONITOR` | `BAT2_CAPACITY` | 0.53 | — | Battery monitoring |
| `BATT6_OPTIONS` | `BAT2_CAPACITY` | 0.53 | — | Battery monitor options |
| `BATT6_SERIAL_NUM` | `BAT2_CAPACITY` | 0.45 | — | Battery serial number |
| `BATT6_SHUNT` | `BAT2_CAPACITY` | 0.53 | Ohm | Battery monitor shunt resistor |
| `BATT6_SUM_MASK` | `BAT2_CAPACITY` | 0.45 | — | Battery Sum mask |
| `BATT6_VLT_OFFSET` | `BAT2_CAPACITY` | 0.45 | V | Voltage offset |
| `BATT6_VOLT_MULT` | `BAT1_C_MULT` | 0.70 | — | Voltage Multiplier |
| `BATT6_VOLT_PIN` | `BAT2_CAPACITY` | 0.45 | — | Battery Voltage sensing pin |
| `BATT7_AMP_OFFSET` | `BAT_AVRG_CURRENT` | 0.70 | V | AMP offset |
| `BATT7_AMP_PERVLT` | `BAT_AVRG_CURRENT` | 0.70 | A/V | Amps per volt |
| `BATT7_ARM_MAH` | `BAT2_CAPACITY` | 0.45 | mAh | Required arming remaining capacity |
| `BATT7_ARM_VOLT` | `BAT2_CAPACITY` | 0.45 | V | Required arming voltage |
| `BATT7_CAPACITY` | `BAT2_CAPACITY` | 1.00 | mAh | Battery capacity |
| `BATT7_CRT_MAH` | `BAT2_CAPACITY` | 0.45 | mAh | Battery critical capacity |
| `BATT7_CRT_VOLT` | `BAT2_CAPACITY` | 0.45 | V | Critical battery voltage |
| `BATT7_CURR_MULT` | `BAT_AVRG_CURRENT` | 0.70 | — | Scales reported power monitor current |
| `BATT7_CURR_PIN` | `BAT_AVRG_CURRENT` | 0.70 | — | Battery Current sensing pin |
| `BATT7_ESC_INDEX` | `BAT2_CAPACITY` | 0.45 | — | ESC Telemetry Index to write to |
| `BATT7_ESC_MASK` | `BAT2_CAPACITY` | 0.45 | — | ESC mask |
| `BATT7_FL_FF` | `BAT2_CAPACITY` | 0.45 | — | First order term |
| `BATT7_FL_FLTR` | `BAT2_CAPACITY` | 0.45 | Hz | Fuel level filter frequency |
| `BATT7_FL_FS` | `BAT2_CAPACITY` | 0.45 | — | Second order term |
| `BATT7_FL_FT` | `BAT2_CAPACITY` | 0.45 | — | Third order term |
| `BATT7_FL_OFF` | `BAT2_CAPACITY` | 0.45 | — | Offset term |
| `BATT7_FL_PIN` | `BAT2_CAPACITY` | 0.45 | — | Fuel level analog pin number |
| `BATT7_FL_VLT_MIN` | `BAT2_CAPACITY` | 0.40 | V | Empty fuel level voltage |
| `BATT7_FL_V_MULT` | `BAT2_V_FILT` | 0.60 | — | Fuel level voltage multiplier |
| `BATT7_FS_CRT_ACT` | `BAT2_CAPACITY` | 0.40 | — | Critical battery failsafe action |
| `BATT7_FS_LOW_ACT` | `BAT_LOW_THR` | 0.60 | — | Low battery failsafe action |
| `BATT7_FS_VOLTSRC` | `BAT2_CAPACITY` | 0.45 | — | Failsafe voltage source |
| `BATT7_I2C_ADDR` | `BAT2_CAPACITY` | 0.45 | — | Battery monitor I2C address |
| `BATT7_I2C_BUS` | `BAT2_CAPACITY` | 0.45 | — | Battery monitor I2C bus number |
| `BATT7_LOW_MAH` | `BAT_LOW_THR` | 0.70 | mAh | Low battery capacity |
| `BATT7_LOW_TIMER` | `BAT_LOW_THR` | 0.70 | s | Low voltage timeout |
| `BATT7_LOW_VOLT` | `BAT_LOW_THR` | 0.70 | V | Low battery voltage |
| `BATT7_MAX_AMPS` | `BAT2_CAPACITY` | 0.45 | A | Battery monitor max current |
| `BATT7_MAX_VOLT` | `BAT2_CAPACITY` | 0.45 | — | Maximum Battery Voltage |
| `BATT7_MONITOR` | `BAT2_CAPACITY` | 0.53 | — | Battery monitoring |
| `BATT7_OPTIONS` | `BAT2_CAPACITY` | 0.53 | — | Battery monitor options |
| `BATT7_SERIAL_NUM` | `BAT2_CAPACITY` | 0.45 | — | Battery serial number |
| `BATT7_SHUNT` | `BAT2_CAPACITY` | 0.53 | Ohm | Battery monitor shunt resistor |
| `BATT7_SUM_MASK` | `BAT2_CAPACITY` | 0.45 | — | Battery Sum mask |
| `BATT7_VLT_OFFSET` | `BAT2_CAPACITY` | 0.45 | V | Voltage offset |
| `BATT7_VOLT_MULT` | `BAT1_C_MULT` | 0.70 | — | Voltage Multiplier |
| `BATT7_VOLT_PIN` | `BAT2_CAPACITY` | 0.45 | — | Battery Voltage sensing pin |
| `BATT8_AMP_OFFSET` | `BAT_AVRG_CURRENT` | 0.70 | V | AMP offset |
| `BATT8_AMP_PERVLT` | `BAT_AVRG_CURRENT` | 0.70 | A/V | Amps per volt |
| `BATT8_ARM_MAH` | `BAT2_CAPACITY` | 0.45 | mAh | Required arming remaining capacity |
| `BATT8_ARM_VOLT` | `BAT2_CAPACITY` | 0.45 | V | Required arming voltage |
| `BATT8_CAPACITY` | `BAT2_CAPACITY` | 1.00 | mAh | Battery capacity |
| `BATT8_CRT_MAH` | `BAT2_CAPACITY` | 0.45 | mAh | Battery critical capacity |
| `BATT8_CRT_VOLT` | `BAT2_CAPACITY` | 0.45 | V | Critical battery voltage |
| `BATT8_CURR_MULT` | `BAT_AVRG_CURRENT` | 0.70 | — | Scales reported power monitor current |
| `BATT8_CURR_PIN` | `BAT_AVRG_CURRENT` | 0.70 | — | Battery Current sensing pin |
| `BATT8_ESC_INDEX` | `BAT2_CAPACITY` | 0.45 | — | ESC Telemetry Index to write to |
| `BATT8_ESC_MASK` | `BAT2_CAPACITY` | 0.45 | — | ESC mask |
| `BATT8_FL_FF` | `BAT2_CAPACITY` | 0.45 | — | First order term |
| `BATT8_FL_FLTR` | `BAT2_CAPACITY` | 0.45 | Hz | Fuel level filter frequency |
| `BATT8_FL_FS` | `BAT2_CAPACITY` | 0.45 | — | Second order term |
| `BATT8_FL_FT` | `BAT2_CAPACITY` | 0.45 | — | Third order term |
| `BATT8_FL_OFF` | `BAT2_CAPACITY` | 0.45 | — | Offset term |
| `BATT8_FL_PIN` | `BAT2_CAPACITY` | 0.45 | — | Fuel level analog pin number |
| `BATT8_FL_VLT_MIN` | `BAT2_CAPACITY` | 0.40 | V | Empty fuel level voltage |
| `BATT8_FL_V_MULT` | `BAT2_V_FILT` | 0.60 | — | Fuel level voltage multiplier |
| `BATT8_FS_CRT_ACT` | `BAT2_CAPACITY` | 0.40 | — | Critical battery failsafe action |
| `BATT8_FS_LOW_ACT` | `BAT_LOW_THR` | 0.60 | — | Low battery failsafe action |
| `BATT8_FS_VOLTSRC` | `BAT2_CAPACITY` | 0.45 | — | Failsafe voltage source |
| `BATT8_I2C_ADDR` | `BAT2_CAPACITY` | 0.45 | — | Battery monitor I2C address |
| `BATT8_I2C_BUS` | `BAT2_CAPACITY` | 0.45 | — | Battery monitor I2C bus number |
| `BATT8_LOW_MAH` | `BAT_LOW_THR` | 0.70 | mAh | Low battery capacity |
| `BATT8_LOW_TIMER` | `BAT_LOW_THR` | 0.70 | s | Low voltage timeout |
| `BATT8_LOW_VOLT` | `BAT_LOW_THR` | 0.70 | V | Low battery voltage |
| `BATT8_MAX_AMPS` | `BAT2_CAPACITY` | 0.45 | A | Battery monitor max current |
| `BATT8_MAX_VOLT` | `BAT2_CAPACITY` | 0.45 | — | Maximum Battery Voltage |
| `BATT8_MONITOR` | `BAT2_CAPACITY` | 0.53 | — | Battery monitoring |
| `BATT8_OPTIONS` | `BAT2_CAPACITY` | 0.53 | — | Battery monitor options |
| `BATT8_SERIAL_NUM` | `BAT2_CAPACITY` | 0.45 | — | Battery serial number |
| `BATT8_SHUNT` | `BAT2_CAPACITY` | 0.53 | Ohm | Battery monitor shunt resistor |
| `BATT8_SUM_MASK` | `BAT2_CAPACITY` | 0.45 | — | Battery Sum mask |
| `BATT8_VLT_OFFSET` | `BAT2_CAPACITY` | 0.45 | V | Voltage offset |
| `BATT8_VOLT_MULT` | `BAT1_C_MULT` | 0.70 | — | Voltage Multiplier |
| `BATT8_VOLT_PIN` | `BAT2_CAPACITY` | 0.45 | — | Battery Voltage sensing pin |
| `BATT9_AMP_OFFSET` | `BAT_AVRG_CURRENT` | 0.70 | V | AMP offset |
| `BATT9_AMP_PERVLT` | `BAT_AVRG_CURRENT` | 0.70 | A/V | Amps per volt |
| `BATT9_ARM_MAH` | `BAT2_CAPACITY` | 0.45 | mAh | Required arming remaining capacity |
| `BATT9_ARM_VOLT` | `BAT2_CAPACITY` | 0.45 | V | Required arming voltage |
| `BATT9_CAPACITY` | `BAT2_CAPACITY` | 1.00 | mAh | Battery capacity |
| `BATT9_CRT_MAH` | `BAT2_CAPACITY` | 0.45 | mAh | Battery critical capacity |
| `BATT9_CRT_VOLT` | `BAT2_CAPACITY` | 0.45 | V | Critical battery voltage |
| `BATT9_CURR_MULT` | `BAT_AVRG_CURRENT` | 0.70 | — | Scales reported power monitor current |
| `BATT9_CURR_PIN` | `BAT_AVRG_CURRENT` | 0.70 | — | Battery Current sensing pin |
| `BATT9_ESC_INDEX` | `BAT2_CAPACITY` | 0.45 | — | ESC Telemetry Index to write to |
| `BATT9_ESC_MASK` | `BAT2_CAPACITY` | 0.45 | — | ESC mask |
| `BATT9_FL_FF` | `BAT2_CAPACITY` | 0.45 | — | First order term |
| `BATT9_FL_FLTR` | `BAT2_CAPACITY` | 0.45 | Hz | Fuel level filter frequency |
| `BATT9_FL_FS` | `BAT2_CAPACITY` | 0.45 | — | Second order term |
| `BATT9_FL_FT` | `BAT2_CAPACITY` | 0.45 | — | Third order term |
| `BATT9_FL_OFF` | `BAT2_CAPACITY` | 0.45 | — | Offset term |
| `BATT9_FL_PIN` | `BAT2_CAPACITY` | 0.45 | — | Fuel level analog pin number |
| `BATT9_FL_VLT_MIN` | `BAT2_CAPACITY` | 0.40 | V | Empty fuel level voltage |
| `BATT9_FL_V_MULT` | `BAT2_V_FILT` | 0.60 | — | Fuel level voltage multiplier |
| `BATT9_FS_CRT_ACT` | `BAT2_CAPACITY` | 0.40 | — | Critical battery failsafe action |
| `BATT9_FS_LOW_ACT` | `BAT_LOW_THR` | 0.60 | — | Low battery failsafe action |
| `BATT9_FS_VOLTSRC` | `BAT2_CAPACITY` | 0.45 | — | Failsafe voltage source |
| `BATT9_I2C_ADDR` | `BAT2_CAPACITY` | 0.45 | — | Battery monitor I2C address |
| `BATT9_I2C_BUS` | `BAT2_CAPACITY` | 0.45 | — | Battery monitor I2C bus number |
| `BATT9_LOW_MAH` | `BAT_LOW_THR` | 0.70 | mAh | Low battery capacity |
| `BATT9_LOW_TIMER` | `BAT_LOW_THR` | 0.70 | s | Low voltage timeout |
| `BATT9_LOW_VOLT` | `BAT_LOW_THR` | 0.70 | V | Low battery voltage |
| `BATT9_MAX_AMPS` | `BAT2_CAPACITY` | 0.45 | A | Battery monitor max current |
| `BATT9_MAX_VOLT` | `BAT2_CAPACITY` | 0.45 | — | Maximum Battery Voltage |
| `BATT9_MONITOR` | `BAT2_CAPACITY` | 0.53 | — | Battery monitoring |
| `BATT9_OPTIONS` | `BAT2_CAPACITY` | 0.53 | — | Battery monitor options |
| `BATT9_SERIAL_NUM` | `BAT2_CAPACITY` | 0.45 | — | Battery serial number |
| `BATT9_SHUNT` | `BAT2_CAPACITY` | 0.53 | Ohm | Battery monitor shunt resistor |
| `BATT9_SUM_MASK` | `BAT2_CAPACITY` | 0.45 | — | Battery Sum mask |
| `BATT9_VLT_OFFSET` | `BAT2_CAPACITY` | 0.45 | V | Voltage offset |
| `BATT9_VOLT_MULT` | `BAT1_C_MULT` | 0.70 | — | Voltage Multiplier |
| `BATT9_VOLT_PIN` | `BAT2_CAPACITY` | 0.45 | — | Battery Voltage sensing pin |
| `BATTA_AMP_OFFSET` | — | 0.00 | V | AMP offset |
| `BATTA_AMP_PERVLT` | — | 0.00 | A/V | Amps per volt |
| `BATTA_ARM_MAH` | — | 0.00 | mAh | Required arming remaining capacity |
| `BATTA_ARM_VOLT` | — | 0.00 | V | Required arming voltage |
| `BATTA_CAPACITY` | — | 0.00 | mAh | Battery capacity |
| `BATTA_CRT_MAH` | — | 0.00 | mAh | Battery critical capacity |
| `BATTA_CRT_VOLT` | — | 0.00 | V | Critical battery voltage |
| `BATTA_CURR_MULT` | — | 0.00 | — | Scales reported power monitor current |
| `BATTA_CURR_PIN` | — | 0.00 | — | Battery Current sensing pin |
| `BATTA_ESC_INDEX` | — | 0.00 | — | ESC Telemetry Index to write to |
| `BATTA_ESC_MASK` | — | 0.00 | — | ESC mask |
| `BATTA_FL_FF` | — | 0.00 | — | First order term |
| `BATTA_FL_FLTR` | — | 0.00 | Hz | Fuel level filter frequency |
| `BATTA_FL_FS` | — | 0.00 | — | Second order term |
| `BATTA_FL_FT` | — | 0.00 | — | Third order term |
| `BATTA_FL_OFF` | — | 0.00 | — | Offset term |
| `BATTA_FL_PIN` | — | 0.00 | — | Fuel level analog pin number |
| `BATTA_FL_VLT_MIN` | — | 0.00 | V | Empty fuel level voltage |
| `BATTA_FL_V_MULT` | — | 0.00 | — | Fuel level voltage multiplier |
| `BATTA_FS_CRT_ACT` | — | 0.00 | — | Critical battery failsafe action |
| `BATTA_FS_LOW_ACT` | — | 0.00 | — | Low battery failsafe action |
| `BATTA_FS_VOLTSRC` | — | 0.00 | — | Failsafe voltage source |
| `BATTA_I2C_ADDR` | — | 0.00 | — | Battery monitor I2C address |
| `BATTA_I2C_BUS` | — | 0.00 | — | Battery monitor I2C bus number |
| `BATTA_LOW_MAH` | — | 0.00 | mAh | Low battery capacity |
| `BATTA_LOW_TIMER` | — | 0.00 | s | Low voltage timeout |
| `BATTA_LOW_VOLT` | — | 0.00 | V | Low battery voltage |
| `BATTA_MAX_AMPS` | — | 0.00 | A | Battery monitor max current |
| `BATTA_MAX_VOLT` | — | 0.00 | — | Maximum Battery Voltage |
| `BATTA_MONITOR` | — | 0.00 | — | Battery monitoring |
| `BATTA_OPTIONS` | — | 0.00 | — | Battery monitor options |
| `BATTA_SERIAL_NUM` | — | 0.00 | — | Battery serial number |
| `BATTA_SHUNT` | — | 0.00 | Ohm | Battery monitor shunt resistor |
| `BATTA_SUM_MASK` | — | 0.00 | — | Battery Sum mask |
| `BATTA_VLT_OFFSET` | — | 0.00 | V | Voltage offset |
| `BATTA_VOLT_MULT` | — | 0.00 | — | Voltage Multiplier |
| `BATTA_VOLT_PIN` | — | 0.00 | — | Battery Voltage sensing pin |
| `BATTB_AMP_OFFSET` | — | 0.00 | V | AMP offset |
| `BATTB_AMP_PERVLT` | — | 0.00 | A/V | Amps per volt |
| `BATTB_ARM_MAH` | — | 0.00 | mAh | Required arming remaining capacity |
| `BATTB_ARM_VOLT` | — | 0.00 | V | Required arming voltage |
| `BATTB_CAPACITY` | — | 0.00 | mAh | Battery capacity |
| `BATTB_CRT_MAH` | — | 0.00 | mAh | Battery critical capacity |
| `BATTB_CRT_VOLT` | — | 0.00 | V | Critical battery voltage |
| `BATTB_CURR_MULT` | — | 0.00 | — | Scales reported power monitor current |
| `BATTB_CURR_PIN` | — | 0.00 | — | Battery Current sensing pin |
| `BATTB_ESC_INDEX` | — | 0.00 | — | ESC Telemetry Index to write to |
| `BATTB_ESC_MASK` | — | 0.00 | — | ESC mask |
| `BATTB_FL_FF` | — | 0.00 | — | First order term |
| `BATTB_FL_FLTR` | — | 0.00 | Hz | Fuel level filter frequency |
| `BATTB_FL_FS` | — | 0.00 | — | Second order term |
| `BATTB_FL_FT` | — | 0.00 | — | Third order term |
| `BATTB_FL_OFF` | — | 0.00 | — | Offset term |
| `BATTB_FL_PIN` | — | 0.00 | — | Fuel level analog pin number |
| `BATTB_FL_VLT_MIN` | — | 0.00 | V | Empty fuel level voltage |
| `BATTB_FL_V_MULT` | — | 0.00 | — | Fuel level voltage multiplier |
| `BATTB_FS_CRT_ACT` | — | 0.00 | — | Critical battery failsafe action |
| `BATTB_FS_LOW_ACT` | — | 0.00 | — | Low battery failsafe action |
| `BATTB_FS_VOLTSRC` | — | 0.00 | — | Failsafe voltage source |
| `BATTB_I2C_ADDR` | — | 0.00 | — | Battery monitor I2C address |
| `BATTB_I2C_BUS` | — | 0.00 | — | Battery monitor I2C bus number |
| `BATTB_LOW_MAH` | — | 0.00 | mAh | Low battery capacity |
| `BATTB_LOW_TIMER` | — | 0.00 | s | Low voltage timeout |
| `BATTB_LOW_VOLT` | — | 0.00 | V | Low battery voltage |
| `BATTB_MAX_AMPS` | — | 0.00 | A | Battery monitor max current |
| `BATTB_MAX_VOLT` | — | 0.00 | — | Maximum Battery Voltage |
| `BATTB_MONITOR` | — | 0.00 | — | Battery monitoring |
| `BATTB_OPTIONS` | — | 0.00 | — | Battery monitor options |
| `BATTB_SERIAL_NUM` | — | 0.00 | — | Battery serial number |
| `BATTB_SHUNT` | — | 0.00 | Ohm | Battery monitor shunt resistor |
| `BATTB_SUM_MASK` | — | 0.00 | — | Battery Sum mask |
| `BATTB_VLT_OFFSET` | — | 0.00 | V | Voltage offset |
| `BATTB_VOLT_MULT` | — | 0.00 | — | Voltage Multiplier |
| `BATTB_VOLT_PIN` | — | 0.00 | — | Battery Voltage sensing pin |
| `BATTC_AMP_OFFSET` | — | 0.00 | V | AMP offset |
| `BATTC_AMP_PERVLT` | — | 0.00 | A/V | Amps per volt |
| `BATTC_ARM_MAH` | — | 0.00 | mAh | Required arming remaining capacity |
| `BATTC_ARM_VOLT` | — | 0.00 | V | Required arming voltage |
| `BATTC_CAPACITY` | — | 0.00 | mAh | Battery capacity |
| `BATTC_CRT_MAH` | — | 0.00 | mAh | Battery critical capacity |
| `BATTC_CRT_VOLT` | — | 0.00 | V | Critical battery voltage |
| `BATTC_CURR_MULT` | — | 0.00 | — | Scales reported power monitor current |
| `BATTC_CURR_PIN` | — | 0.00 | — | Battery Current sensing pin |
| `BATTC_ESC_INDEX` | — | 0.00 | — | ESC Telemetry Index to write to |
| `BATTC_ESC_MASK` | — | 0.00 | — | ESC mask |
| `BATTC_FL_FF` | — | 0.00 | — | First order term |
| `BATTC_FL_FLTR` | — | 0.00 | Hz | Fuel level filter frequency |
| `BATTC_FL_FS` | — | 0.00 | — | Second order term |
| `BATTC_FL_FT` | — | 0.00 | — | Third order term |
| `BATTC_FL_OFF` | — | 0.00 | — | Offset term |
| `BATTC_FL_PIN` | — | 0.00 | — | Fuel level analog pin number |
| `BATTC_FL_VLT_MIN` | — | 0.00 | V | Empty fuel level voltage |
| `BATTC_FL_V_MULT` | — | 0.00 | — | Fuel level voltage multiplier |
| `BATTC_FS_CRT_ACT` | — | 0.00 | — | Critical battery failsafe action |
| `BATTC_FS_LOW_ACT` | — | 0.00 | — | Low battery failsafe action |
| `BATTC_FS_VOLTSRC` | — | 0.00 | — | Failsafe voltage source |
| `BATTC_I2C_ADDR` | — | 0.00 | — | Battery monitor I2C address |
| `BATTC_I2C_BUS` | — | 0.00 | — | Battery monitor I2C bus number |
| `BATTC_LOW_MAH` | — | 0.00 | mAh | Low battery capacity |
| `BATTC_LOW_TIMER` | — | 0.00 | s | Low voltage timeout |
| `BATTC_LOW_VOLT` | — | 0.00 | V | Low battery voltage |
| `BATTC_MAX_AMPS` | — | 0.00 | A | Battery monitor max current |
| `BATTC_MAX_VOLT` | — | 0.00 | — | Maximum Battery Voltage |
| `BATTC_MONITOR` | — | 0.00 | — | Battery monitoring |
| `BATTC_OPTIONS` | — | 0.00 | — | Battery monitor options |
| `BATTC_SERIAL_NUM` | — | 0.00 | — | Battery serial number |
| `BATTC_SHUNT` | — | 0.00 | Ohm | Battery monitor shunt resistor |
| `BATTC_SUM_MASK` | — | 0.00 | — | Battery Sum mask |
| `BATTC_VLT_OFFSET` | — | 0.00 | V | Voltage offset |
| `BATTC_VOLT_MULT` | — | 0.00 | — | Voltage Multiplier |
| `BATTC_VOLT_PIN` | — | 0.00 | — | Battery Voltage sensing pin |
| `BATTD_AMP_OFFSET` | — | 0.00 | V | AMP offset |
| `BATTD_AMP_PERVLT` | — | 0.00 | A/V | Amps per volt |
| `BATTD_ARM_MAH` | — | 0.00 | mAh | Required arming remaining capacity |
| `BATTD_ARM_VOLT` | — | 0.00 | V | Required arming voltage |
| `BATTD_CAPACITY` | — | 0.00 | mAh | Battery capacity |
| `BATTD_CRT_MAH` | — | 0.00 | mAh | Battery critical capacity |
| `BATTD_CRT_VOLT` | — | 0.00 | V | Critical battery voltage |
| `BATTD_CURR_MULT` | — | 0.00 | — | Scales reported power monitor current |
| `BATTD_CURR_PIN` | — | 0.00 | — | Battery Current sensing pin |
| `BATTD_ESC_INDEX` | — | 0.00 | — | ESC Telemetry Index to write to |
| `BATTD_ESC_MASK` | — | 0.00 | — | ESC mask |
| `BATTD_FL_FF` | — | 0.00 | — | First order term |
| `BATTD_FL_FLTR` | — | 0.00 | Hz | Fuel level filter frequency |
| `BATTD_FL_FS` | — | 0.00 | — | Second order term |
| `BATTD_FL_FT` | — | 0.00 | — | Third order term |
| `BATTD_FL_OFF` | — | 0.00 | — | Offset term |
| `BATTD_FL_PIN` | — | 0.00 | — | Fuel level analog pin number |
| `BATTD_FL_VLT_MIN` | — | 0.00 | V | Empty fuel level voltage |
| `BATTD_FL_V_MULT` | — | 0.00 | — | Fuel level voltage multiplier |
| `BATTD_FS_CRT_ACT` | — | 0.00 | — | Critical battery failsafe action |
| `BATTD_FS_LOW_ACT` | — | 0.00 | — | Low battery failsafe action |
| `BATTD_FS_VOLTSRC` | — | 0.00 | — | Failsafe voltage source |
| `BATTD_I2C_ADDR` | — | 0.00 | — | Battery monitor I2C address |
| `BATTD_I2C_BUS` | — | 0.00 | — | Battery monitor I2C bus number |
| `BATTD_LOW_MAH` | — | 0.00 | mAh | Low battery capacity |
| `BATTD_LOW_TIMER` | — | 0.00 | s | Low voltage timeout |
| `BATTD_LOW_VOLT` | — | 0.00 | V | Low battery voltage |
| `BATTD_MAX_AMPS` | — | 0.00 | A | Battery monitor max current |
| `BATTD_MAX_VOLT` | — | 0.00 | — | Maximum Battery Voltage |
| `BATTD_MONITOR` | — | 0.00 | — | Battery monitoring |
| `BATTD_OPTIONS` | — | 0.00 | — | Battery monitor options |
| `BATTD_SERIAL_NUM` | — | 0.00 | — | Battery serial number |
| `BATTD_SHUNT` | — | 0.00 | Ohm | Battery monitor shunt resistor |
| `BATTD_SUM_MASK` | — | 0.00 | — | Battery Sum mask |
| `BATTD_VLT_OFFSET` | — | 0.00 | V | Voltage offset |
| `BATTD_VOLT_MULT` | — | 0.00 | — | Voltage Multiplier |
| `BATTD_VOLT_PIN` | — | 0.00 | — | Battery Voltage sensing pin |
| `BATTE_AMP_OFFSET` | — | 0.00 | V | AMP offset |
| `BATTE_AMP_PERVLT` | — | 0.00 | A/V | Amps per volt |
| `BATTE_ARM_MAH` | — | 0.00 | mAh | Required arming remaining capacity |
| `BATTE_ARM_VOLT` | — | 0.00 | V | Required arming voltage |
| `BATTE_CAPACITY` | — | 0.00 | mAh | Battery capacity |
| `BATTE_CRT_MAH` | — | 0.00 | mAh | Battery critical capacity |
| `BATTE_CRT_VOLT` | — | 0.00 | V | Critical battery voltage |
| `BATTE_CURR_MULT` | — | 0.00 | — | Scales reported power monitor current |
| `BATTE_CURR_PIN` | — | 0.00 | — | Battery Current sensing pin |
| `BATTE_ESC_INDEX` | — | 0.00 | — | ESC Telemetry Index to write to |
| `BATTE_ESC_MASK` | — | 0.00 | — | ESC mask |
| `BATTE_FL_FF` | — | 0.00 | — | First order term |
| `BATTE_FL_FLTR` | — | 0.00 | Hz | Fuel level filter frequency |
| `BATTE_FL_FS` | — | 0.00 | — | Second order term |
| `BATTE_FL_FT` | — | 0.00 | — | Third order term |
| `BATTE_FL_OFF` | — | 0.00 | — | Offset term |
| `BATTE_FL_PIN` | — | 0.00 | — | Fuel level analog pin number |
| `BATTE_FL_VLT_MIN` | — | 0.00 | V | Empty fuel level voltage |
| `BATTE_FL_V_MULT` | — | 0.00 | — | Fuel level voltage multiplier |
| `BATTE_FS_CRT_ACT` | — | 0.00 | — | Critical battery failsafe action |
| `BATTE_FS_LOW_ACT` | — | 0.00 | — | Low battery failsafe action |
| `BATTE_FS_VOLTSRC` | — | 0.00 | — | Failsafe voltage source |
| `BATTE_I2C_ADDR` | — | 0.00 | — | Battery monitor I2C address |
| `BATTE_I2C_BUS` | — | 0.00 | — | Battery monitor I2C bus number |
| `BATTE_LOW_MAH` | — | 0.00 | mAh | Low battery capacity |
| `BATTE_LOW_TIMER` | — | 0.00 | s | Low voltage timeout |
| `BATTE_LOW_VOLT` | — | 0.00 | V | Low battery voltage |
| `BATTE_MAX_AMPS` | — | 0.00 | A | Battery monitor max current |
| `BATTE_MAX_VOLT` | — | 0.00 | — | Maximum Battery Voltage |
| `BATTE_MONITOR` | — | 0.00 | — | Battery monitoring |
| `BATTE_OPTIONS` | — | 0.00 | — | Battery monitor options |
| `BATTE_SERIAL_NUM` | — | 0.00 | — | Battery serial number |
| `BATTE_SHUNT` | — | 0.00 | Ohm | Battery monitor shunt resistor |
| `BATTE_SUM_MASK` | — | 0.00 | — | Battery Sum mask |
| `BATTE_VLT_OFFSET` | — | 0.00 | V | Voltage offset |
| `BATTE_VOLT_MULT` | — | 0.00 | — | Voltage Multiplier |
| `BATTE_VOLT_PIN` | — | 0.00 | — | Battery Voltage sensing pin |
| `BATTF_AMP_OFFSET` | — | 0.00 | V | AMP offset |
| `BATTF_AMP_PERVLT` | — | 0.00 | A/V | Amps per volt |
| `BATTF_ARM_MAH` | — | 0.00 | mAh | Required arming remaining capacity |
| `BATTF_ARM_VOLT` | — | 0.00 | V | Required arming voltage |
| `BATTF_CAPACITY` | — | 0.00 | mAh | Battery capacity |
| `BATTF_CRT_MAH` | — | 0.00 | mAh | Battery critical capacity |
| `BATTF_CRT_VOLT` | — | 0.00 | V | Critical battery voltage |
| `BATTF_CURR_MULT` | — | 0.00 | — | Scales reported power monitor current |
| `BATTF_CURR_PIN` | — | 0.00 | — | Battery Current sensing pin |
| `BATTF_ESC_INDEX` | — | 0.00 | — | ESC Telemetry Index to write to |
| `BATTF_ESC_MASK` | — | 0.00 | — | ESC mask |
| `BATTF_FL_FF` | — | 0.00 | — | First order term |
| `BATTF_FL_FLTR` | — | 0.00 | Hz | Fuel level filter frequency |
| `BATTF_FL_FS` | — | 0.00 | — | Second order term |
| `BATTF_FL_FT` | — | 0.00 | — | Third order term |
| `BATTF_FL_OFF` | — | 0.00 | — | Offset term |
| `BATTF_FL_PIN` | — | 0.00 | — | Fuel level analog pin number |
| `BATTF_FL_VLT_MIN` | — | 0.00 | V | Empty fuel level voltage |
| `BATTF_FL_V_MULT` | — | 0.00 | — | Fuel level voltage multiplier |
| `BATTF_FS_CRT_ACT` | — | 0.00 | — | Critical battery failsafe action |
| `BATTF_FS_LOW_ACT` | — | 0.00 | — | Low battery failsafe action |
| `BATTF_FS_VOLTSRC` | — | 0.00 | — | Failsafe voltage source |
| `BATTF_I2C_ADDR` | — | 0.00 | — | Battery monitor I2C address |
| `BATTF_I2C_BUS` | — | 0.00 | — | Battery monitor I2C bus number |
| `BATTF_LOW_MAH` | — | 0.00 | mAh | Low battery capacity |
| `BATTF_LOW_TIMER` | — | 0.00 | s | Low voltage timeout |
| `BATTF_LOW_VOLT` | — | 0.00 | V | Low battery voltage |
| `BATTF_MAX_AMPS` | — | 0.00 | A | Battery monitor max current |
| `BATTF_MAX_VOLT` | — | 0.00 | — | Maximum Battery Voltage |
| `BATTF_MONITOR` | — | 0.00 | — | Battery monitoring |
| `BATTF_OPTIONS` | — | 0.00 | — | Battery monitor options |
| `BATTF_SERIAL_NUM` | — | 0.00 | — | Battery serial number |
| `BATTF_SHUNT` | — | 0.00 | Ohm | Battery monitor shunt resistor |
| `BATTF_SUM_MASK` | — | 0.00 | — | Battery Sum mask |
| `BATTF_VLT_OFFSET` | — | 0.00 | V | Voltage offset |
| `BATTF_VOLT_MULT` | — | 0.00 | — | Voltage Multiplier |
| `BATTF_VOLT_PIN` | — | 0.00 | — | Battery Voltage sensing pin |
| `BATTG_AMP_OFFSET` | — | 0.00 | V | AMP offset |
| `BATTG_AMP_PERVLT` | — | 0.00 | A/V | Amps per volt |
| `BATTG_ARM_MAH` | — | 0.00 | mAh | Required arming remaining capacity |
| `BATTG_ARM_VOLT` | — | 0.00 | V | Required arming voltage |
| `BATTG_CAPACITY` | — | 0.00 | mAh | Battery capacity |
| `BATTG_CRT_MAH` | — | 0.00 | mAh | Battery critical capacity |
| `BATTG_CRT_VOLT` | — | 0.00 | V | Critical battery voltage |
| `BATTG_CURR_MULT` | — | 0.00 | — | Scales reported power monitor current |
| `BATTG_CURR_PIN` | — | 0.00 | — | Battery Current sensing pin |
| `BATTG_ESC_INDEX` | — | 0.00 | — | ESC Telemetry Index to write to |
| `BATTG_ESC_MASK` | — | 0.00 | — | ESC mask |
| `BATTG_FL_FF` | — | 0.00 | — | First order term |
| `BATTG_FL_FLTR` | — | 0.00 | Hz | Fuel level filter frequency |
| `BATTG_FL_FS` | — | 0.00 | — | Second order term |
| `BATTG_FL_FT` | — | 0.00 | — | Third order term |
| `BATTG_FL_OFF` | — | 0.00 | — | Offset term |
| `BATTG_FL_PIN` | — | 0.00 | — | Fuel level analog pin number |
| `BATTG_FL_VLT_MIN` | — | 0.00 | V | Empty fuel level voltage |
| `BATTG_FL_V_MULT` | — | 0.00 | — | Fuel level voltage multiplier |
| `BATTG_FS_CRT_ACT` | — | 0.00 | — | Critical battery failsafe action |
| `BATTG_FS_LOW_ACT` | — | 0.00 | — | Low battery failsafe action |
| `BATTG_FS_VOLTSRC` | — | 0.00 | — | Failsafe voltage source |
| `BATTG_I2C_ADDR` | — | 0.00 | — | Battery monitor I2C address |
| `BATTG_I2C_BUS` | — | 0.00 | — | Battery monitor I2C bus number |
| `BATTG_LOW_MAH` | — | 0.00 | mAh | Low battery capacity |
| `BATTG_LOW_TIMER` | — | 0.00 | s | Low voltage timeout |
| `BATTG_LOW_VOLT` | — | 0.00 | V | Low battery voltage |
| `BATTG_MAX_AMPS` | — | 0.00 | A | Battery monitor max current |
| `BATTG_MAX_VOLT` | — | 0.00 | — | Maximum Battery Voltage |
| `BATTG_MONITOR` | — | 0.00 | — | Battery monitoring |
| `BATTG_OPTIONS` | — | 0.00 | — | Battery monitor options |
| `BATTG_SERIAL_NUM` | — | 0.00 | — | Battery serial number |
| `BATTG_SHUNT` | — | 0.00 | Ohm | Battery monitor shunt resistor |
| `BATTG_SUM_MASK` | — | 0.00 | — | Battery Sum mask |
| `BATTG_VLT_OFFSET` | — | 0.00 | V | Voltage offset |
| `BATTG_VOLT_MULT` | — | 0.00 | — | Voltage Multiplier |
| `BATTG_VOLT_PIN` | — | 0.00 | — | Battery Voltage sensing pin |
| `BATT_AMP_OFFSET` | `BAT_AVRG_CURRENT` | 0.70 | V | AMP offset |
| `BATT_AMP_PERVLT` | `BAT_AVRG_CURRENT` | 0.70 | A/V | Amps per volt |
| `BATT_ANX_CANDRV` | `BAT2_CAPACITY` | 0.45 | — | Set ANX CAN driver |
| `BATT_ANX_ENABLE` | `BAT2_CAPACITY` | 0.53 | — | Enable ANX battery support |
| `BATT_ANX_INDEX` | `BAT2_CAPACITY` | 0.45 | — | ANX CAN battery index |
| `BATT_ANX_OPTIONS` | `BAT2_CAPACITY` | 0.45 | — | ANX CAN battery options |
| `BATT_ARM_MAH` | `BAT2_CAPACITY` | 0.45 | mAh | Required arming remaining capacity |
| `BATT_ARM_VOLT` | `BAT2_CAPACITY` | 0.45 | V | Required arming voltage |
| `BATT_CAPACITY` | `BAT2_CAPACITY` | 1.00 | mAh | Battery capacity |
| `BATT_CRT_MAH` | `BAT2_CAPACITY` | 0.45 | mAh | Battery critical capacity |
| `BATT_CRT_VOLT` | `BAT2_CAPACITY` | 0.45 | V | Critical battery voltage |
| `BATT_CURR_MULT` | `BAT_AVRG_CURRENT` | 0.70 | — | Scales reported power monitor current |
| `BATT_CURR_PIN` | `BAT_AVRG_CURRENT` | 0.70 | — | Battery Current sensing pin |
| `BATT_ESC_INDEX` | `BAT2_CAPACITY` | 0.45 | — | ESC Telemetry Index to write to |
| `BATT_ESC_MASK` | `BAT2_CAPACITY` | 0.45 | — | ESC mask |
| `BATT_FL_FF` | `BAT2_CAPACITY` | 0.45 | — | First order term |
| `BATT_FL_FLTR` | `BAT2_CAPACITY` | 0.45 | Hz | Fuel level filter frequency |
| `BATT_FL_FS` | `BAT2_CAPACITY` | 0.45 | — | Second order term |
| `BATT_FL_FT` | `BAT2_CAPACITY` | 0.45 | — | Third order term |
| `BATT_FL_OFF` | `BAT2_CAPACITY` | 0.45 | — | Offset term |
| `BATT_FL_PIN` | `BAT2_CAPACITY` | 0.45 | — | Fuel level analog pin number |
| `BATT_FL_VLT_MIN` | `BAT2_CAPACITY` | 0.40 | V | Empty fuel level voltage |
| `BATT_FL_V_MULT` | `BAT2_V_FILT` | 0.60 | — | Fuel level voltage multiplier |
| `BATT_FS_CRT_ACT` | `BAT2_CAPACITY` | 0.40 | — | Critical battery failsafe action |
| `BATT_FS_LOW_ACT` | `BAT_LOW_THR` | 0.60 | — | Low battery failsafe action |
| `BATT_FS_VOLTSRC` | `BAT2_CAPACITY` | 0.45 | — | Failsafe voltage source |
| `BATT_I2C_ADDR` | `BAT2_CAPACITY` | 0.45 | — | Battery monitor I2C address |
| `BATT_I2C_BUS` | `BAT2_CAPACITY` | 0.45 | — | Battery monitor I2C bus number |
| `BATT_LOW_MAH` | `BAT_LOW_THR` | 0.70 | mAh | Low battery capacity |
| `BATT_LOW_TIMER` | `BAT_LOW_THR` | 0.70 | s | Low voltage timeout |
| `BATT_LOW_VOLT` | `BAT_LOW_THR` | 0.70 | V | Low battery voltage |
| `BATT_MAX_AMPS` | `BAT2_CAPACITY` | 0.45 | A | Battery monitor max current |
| `BATT_MAX_VOLT` | `BAT2_CAPACITY` | 0.45 | — | Maximum Battery Voltage |
| `BATT_MONITOR` | `BAT2_CAPACITY` | 0.53 | — | Battery monitoring |
| `BATT_OPTIONS` | `BAT2_CAPACITY` | 0.53 | — | Battery monitor options |
| `BATT_SERIAL_NUM` | `BAT2_CAPACITY` | 0.45 | — | Battery serial number |
| `BATT_SHUNT` | `BAT2_CAPACITY` | 0.53 | Ohm | Battery monitor shunt resistor |
| `BATT_SOC1_C1` | `BAT1_C_MULT` | 0.70 | — | Battery estimator coefficient1 |
| `BATT_SOC1_C2` | `BAT1_C_MULT` | 0.70 | — | Battery estimator coefficient2 |
| `BATT_SOC1_C3` | `BAT1_C_MULT` | 0.70 | — | Battery estimator coefficient3 |
| `BATT_SOC1_IDX` | `BAT2_CAPACITY` | 0.45 | — | Battery estimator index |
| `BATT_SOC1_NCELL` | `BAT2_CAPACITY` | 0.45 | — | Battery estimator cell count |
| `BATT_SOC2_C1` | `BAT1_C_MULT` | 0.70 | — | Battery estimator coefficient1 |
| `BATT_SOC2_C2` | `BAT1_C_MULT` | 0.70 | — | Battery estimator coefficient2 |
| `BATT_SOC2_C3` | `BAT1_C_MULT` | 0.70 | — | Battery estimator coefficient3 |
| `BATT_SOC2_IDX` | `BAT2_CAPACITY` | 0.45 | — | Battery estimator index |
| `BATT_SOC2_NCELL` | `BAT2_CAPACITY` | 0.45 | — | Battery estimator cell count |
| `BATT_SOC3_C1` | `BAT1_C_MULT` | 0.70 | — | Battery estimator coefficient1 |
| `BATT_SOC3_C2` | `BAT1_C_MULT` | 0.70 | — | Battery estimator coefficient2 |
| `BATT_SOC3_C3` | `BAT1_C_MULT` | 0.70 | — | Battery estimator coefficient3 |
| `BATT_SOC3_IDX` | `BAT2_CAPACITY` | 0.45 | — | Battery estimator index |
| `BATT_SOC3_NCELL` | `BAT2_CAPACITY` | 0.45 | — | Battery estimator cell count |
| `BATT_SOC4_C1` | `BAT1_C_MULT` | 0.70 | — | Battery estimator coefficient1 |
| `BATT_SOC4_C2` | `BAT1_C_MULT` | 0.70 | — | Battery estimator coefficient2 |
| `BATT_SOC4_C3` | `BAT1_C_MULT` | 0.70 | — | Battery estimator coefficient3 |
| `BATT_SOC4_IDX` | `BAT2_CAPACITY` | 0.45 | — | Battery estimator index |
| `BATT_SOC4_NCELL` | `BAT2_CAPACITY` | 0.45 | — | Battery estimator cell count |
| `BATT_SOC_COUNT` | `BAT2_CAPACITY` | 0.45 | — | Count of SOC estimators |
| `BATT_SUM_MASK` | `BAT2_CAPACITY` | 0.45 | — | Battery Sum mask |
| `BATT_VLT_OFFSET` | `BAT2_CAPACITY` | 0.45 | V | Voltage offset |
| `BATT_VOLT_MULT` | `BAT1_C_MULT` | 0.70 | — | Voltage Multiplier |
| `BATT_VOLT_PIN` | `BAT2_CAPACITY` | 0.45 | — | Battery Voltage sensing pin |
| `BCN_ALT` | — | 0.00 | m | Beacon origin's altitude above sealevel in meters |
| `BCN_LATITUDE` | — | 0.00 | deg | Beacon origin's latitude |
| `BCN_LONGITUDE` | — | 0.00 | deg | Beacon origin's longitude |
| `BCN_ORIENT_YAW` | — | 0.00 | deg | Beacon systems rotation from north in degrees |
| `BCN_TYPE` | — | 0.00 | — | Beacon based position estimation device type |
| `BRD_ALT_CONFIG` | — | 0.00 | — | Alternative HW config |
| `BRD_BOOT_DELAY` | — | 0.00 | ms | Boot delay |
| `BRD_HEAT_I` | — | 0.00 | — | Board Heater I gain |
| `BRD_HEAT_IMAX` | — | 0.00 | — | Board Heater IMAX |
| `BRD_HEAT_LOWMGN` | — | 0.00 | degC | Board heater temp lower margin |
| `BRD_HEAT_P` | — | 0.00 | — | Board Heater P gain |
| `BRD_HEAT_TARG` | — | 0.00 | degC | Board heater temperature target |
| `BRD_IO_DSHOT` | — | 0.00 | — | Load DShot FW on IO |
| `BRD_IO_ENABLE` | — | 0.00 | — | Enable IO co-processor |
| `BRD_OPTIONS` | — | 0.00 | — | Board options |
| `BRD_PWM_VOLT_SEL` | — | 0.00 | — | Set PWM Out Voltage |
| `BRD_RADIO_ABLVL` | — | 0.00 | — | Auto-bind level |
| `BRD_RADIO_ABTIME` | — | 0.00 | — | Auto-bind time |
| `BRD_RADIO_BZOFS` | — | 0.00 | — | Transmitter buzzer adjustment |
| `BRD_RADIO_DEBUG` | — | 0.00 | — | debug level |
| `BRD_RADIO_DISCRC` | — | 0.00 | — | disable receive CRC |
| `BRD_RADIO_FCCTST` | — | 0.00 | — | Put radio into FCC test mode |
| `BRD_RADIO_PPSCH` | — | 0.00 | — | Packet rate channel |
| `BRD_RADIO_PROT` | — | 0.00 | — | protocol |
| `BRD_RADIO_SIGCH` | — | 0.00 | — | RSSI signal strength |
| `BRD_RADIO_STKMD` | — | 0.00 | — | Stick input mode |
| `BRD_RADIO_TELEM` | — | 0.00 | — | Enable telemetry |
| `BRD_RADIO_TESTCH` | — | 0.00 | — | Set radio to factory test channel |
| `BRD_RADIO_TPPSCH` | — | 0.00 | — | Telemetry PPS channel |
| `BRD_RADIO_TSIGCH` | — | 0.00 | — | RSSI value channel for telemetry data on transmitter |
| `BRD_RADIO_TXMAX` | — | 0.00 | — | Transmitter transmit power |
| `BRD_RADIO_TXPOW` | — | 0.00 | — | Telemetry Transmit power |
| `BRD_RADIO_TYPE` | — | 0.00 | — | Set type of direct attached radio |
| `BRD_RTC_TYPES` | — | 0.00 | — | Allowed sources of RTC time |
| `BRD_RTC_TZ_MIN` | — | 0.00 | — | Timezone offset from UTC |
| `BRD_SAFETYOPTION` | — | 0.00 | — | Options for safety button behavior |
| `BRD_SAFETY_DEFLT` | — | 0.00 | — | Sets default state of the safety switch |
| `BRD_SAFETY_MASK` | — | 0.00 | — | Outputs which ignore the safety switch state |
| `BRD_SBUS_OUT` | — | 0.00 | — | SBUS output rate |
| `BRD_SD_FENCE` | — | 0.00 | — | SDCard Fence size |
| `BRD_SD_MISSION` | — | 0.00 | — | SDCard Mission size |
| `BRD_SD_SLOWDOWN` | — | 0.00 | — | microSD slowdown |
| `BRD_SER1_RTSCTS` | — | 0.00 | — | Serial 1 flow control |
| `BRD_SER2_RTSCTS` | — | 0.00 | — | Serial 2 flow control |
| `BRD_SER3_RTSCTS` | — | 0.00 | — | Serial 3 flow control |
| `BRD_SER4_RTSCTS` | — | 0.00 | — | Serial 4 flow control |
| `BRD_SER5_RTSCTS` | — | 0.00 | — | Serial 5 flow control |
| `BRD_SER6_RTSCTS` | — | 0.00 | — | Serial 6 flow control |
| `BRD_SER7_RTSCTS` | — | 0.00 | — | Serial 7 flow control |
| `BRD_SER8_RTSCTS` | — | 0.00 | — | Serial 8 flow control |
| `BRD_SERIAL_NUM` | — | 0.00 | — | User-defined serial number |
| `BRD_TYPE` | — | 0.00 | — | Board type |
| `BRD_VBUS_MIN` | — | 0.00 | V | Autopilot board voltage requirement |
| `BRD_VSERVO_MIN` | — | 0.00 | V | Servo voltage requirement |
| `BTN_ENABLE` | — | 0.00 | — | Enable button reporting |
| `BTN_FUNC1` | — | 0.00 | — | Button Pin 1 RC Channel function |
| `BTN_FUNC2` | — | 0.00 | — | Button Pin 2 RC Channel function |
| `BTN_FUNC3` | — | 0.00 | — | Button Pin 3 RC Channel function |
| `BTN_FUNC4` | — | 0.00 | — | Button Pin 4 RC Channel function |
| `BTN_OPTIONS1` | — | 0.00 | — | Button Pin 1 Options |
| `BTN_OPTIONS2` | — | 0.00 | — | Button Pin 2 Options |
| `BTN_OPTIONS3` | — | 0.00 | — | Button Pin 3 Options |
| `BTN_OPTIONS4` | — | 0.00 | — | Button Pin 4 Options |
| `BTN_PIN1` | — | 0.00 | — | First button Pin |
| `BTN_PIN2` | — | 0.00 | — | Second button Pin |
| `BTN_PIN3` | — | 0.00 | — | Third button Pin |
| `BTN_PIN4` | — | 0.00 | — | Fourth button Pin |
| `BTN_REPORT_SEND` | — | 0.00 | — | Report send time |
| `CAM1_DURATION` | — | 0.00 | s | Camera shutter duration held open |
| `CAM1_FEEDBAK_PIN` | — | 0.00 | — | Camera feedback pin |
| `CAM1_FEEDBAK_POL` | — | 0.00 | — | Camera feedback pin polarity |
| `CAM1_HFOV` | — | 0.00 | deg | Camera horizontal field of view |
| `CAM1_INTRVAL_MIN` | — | 0.00 | s | Camera minimum time interval between photos |
| `CAM1_MNT_INST` | — | 0.00 | — | Camera Mount instance |
| `CAM1_OPTIONS` | — | 0.00 | — | Camera options |
| `CAM1_RELAY_ON` | — | 0.00 | — | Camera relay ON value |
| `CAM1_SERVO_OFF` | — | 0.00 | PWM | Camera servo OFF PWM value |
| `CAM1_SERVO_ON` | — | 0.00 | PWM | Camera servo ON PWM value |
| `CAM1_THERM_GAIN` | — | 0.00 | — | Camera1 Thermal Gain |
| `CAM1_THERM_PAL` | — | 0.00 | — | Camera1 Thermal Palette |
| `CAM1_THERM_RAW` | — | 0.00 | m | Camera1 Thermal Raw Data |
| `CAM1_TRIGG_DIST` | — | 0.00 | m | Camera trigger distance |
| `CAM1_TYPE` | `CAM_CAP_FBACK` | 0.33 | — | Camera shutter (trigger) type |
| `CAM1_VFOV` | — | 0.00 | deg | Camera vertical field of view |
| `CAM2_DURATION` | — | 0.00 | s | Camera shutter duration held open |
| `CAM2_FEEDBAK_PIN` | — | 0.00 | — | Camera feedback pin |
| `CAM2_FEEDBAK_POL` | — | 0.00 | — | Camera feedback pin polarity |
| `CAM2_HFOV` | — | 0.00 | deg | Camera horizontal field of view |
| `CAM2_INTRVAL_MIN` | — | 0.00 | s | Camera minimum time interval between photos |
| `CAM2_MNT_INST` | — | 0.00 | — | Camera Mount instance |
| `CAM2_OPTIONS` | — | 0.00 | — | Camera options |
| `CAM2_RELAY_ON` | — | 0.00 | — | Camera relay ON value |
| `CAM2_SERVO_OFF` | — | 0.00 | PWM | Camera servo OFF PWM value |
| `CAM2_SERVO_ON` | — | 0.00 | PWM | Camera servo ON PWM value |
| `CAM2_TRIGG_DIST` | — | 0.00 | m | Camera trigger distance |
| `CAM2_TYPE` | `CAM_CAP_FBACK` | 0.33 | — | Camera shutter (trigger) type |
| `CAM2_VFOV` | — | 0.00 | deg | Camera vertical field of view |
| `CAM_AUTO_ONLY` | `CAM_CAP_FBACK` | 0.32 | — | Distance-trigging in AUTO mode only |
| `CAM_MAX_ROLL` | `CAM_CAP_FBACK` | 0.32 | deg | Maximum photo roll angle. |
| `CAM_RC_BTN_DELAY` | `CAM_CAP_DELAY` | 0.52 | — | RunCam button delay before allowing further button presses |
| `CAM_RC_BT_DELAY` | `CAM_CAP_DELAY` | 0.52 | — | RunCam boot delay before allowing updates |
| `CAM_RC_CONTROL` | `CAM_CAP_MODE` | 0.32 | — | RunCam control option |
| `CAM_RC_FEATURES` | `CAM_CAP_MODE` | 0.32 | — | RunCam features available |
| `CAM_RC_MDE_DELAY` | `CAM_CAP_DELAY` | 0.52 | — | RunCam mode delay before allowing further button presses |
| `CAM_RC_TYPE` | `CAM_CAP_MODE` | 0.37 | — | RunCam device type |
| `CAN_D1_PC_ECU_ID` | — | 0.00 | — | ECU Node ID |
| `CAN_D1_PC_ECU_RT` | — | 0.00 | Hz | ECU command output rate |
| `CAN_D1_PC_ESC_BM` | — | 0.00 | — | ESC channels |
| `CAN_D1_PC_ESC_RT` | — | 0.00 | Hz | ESC output rate |
| `CAN_D1_PC_SRV_BM` | — | 0.00 | — | Servo channels |
| `CAN_D1_PC_SRV_RT` | — | 0.00 | Hz | Servo command output rate |
| `CAN_D1_PROTOCOL` | — | 0.00 | — | Enable use of specific protocol over virtual driver |
| `CAN_D1_PROTOCOL2` | — | 0.00 | — | Secondary protocol with 11 bit CAN addressing |
| `CAN_D1_UC_ESC_BM` | — | 0.00 | — | Output channels to be transmitted as ESC over DroneCAN |
| `CAN_D1_UC_ESC_OF` | — | 0.00 | — | ESC Output channels offset |
| `CAN_D1_UC_ESC_RV` | — | 0.00 | — | Bitmask for output channels for reversible ESCs over DroneCAN. |
| `CAN_D1_UC_NODE` | — | 0.00 | — | Own node ID |
| `CAN_D1_UC_NTF_RT` | — | 0.00 | Hz | Notify State rate |
| `CAN_D1_UC_OPTION` | — | 0.00 | — | DroneCAN options |
| `CAN_D1_UC_POOL` | — | 0.00 | — | CAN pool size |
| `CAN_D1_UC_RLY_RT` | — | 0.00 | Hz | DroneCAN relay output rate |
| `CAN_D1_UC_S1_BD` | — | 0.00 | — | DroneCAN Serial default baud rate |
| `CAN_D1_UC_S1_IDX` | — | 0.00 | — | DroneCAN Serial1 index |
| `CAN_D1_UC_S1_NOD` | — | 0.00 | — | Serial CAN remote node number |
| `CAN_D1_UC_S1_PRO` | — | 0.00 | — | Serial protocol of DroneCAN serial port |
| `CAN_D1_UC_S2_BD` | — | 0.00 | — | DroneCAN Serial default baud rate |
| `CAN_D1_UC_S2_IDX` | — | 0.00 | — | Serial port number on remote CAN node |
| `CAN_D1_UC_S2_NOD` | — | 0.00 | — | Serial CAN remote node number |
| `CAN_D1_UC_S2_PRO` | — | 0.00 | — | Serial protocol of DroneCAN serial port |
| `CAN_D1_UC_S3_BD` | — | 0.00 | — | Serial baud rate on remote CAN node |
| `CAN_D1_UC_S3_IDX` | — | 0.00 | — | Serial port number on remote CAN node |
| `CAN_D1_UC_S3_NOD` | — | 0.00 | — | Serial CAN remote node number |
| `CAN_D1_UC_S3_PRO` | — | 0.00 | — | Serial protocol of DroneCAN serial port |
| `CAN_D1_UC_SER_EN` | — | 0.00 | — | DroneCAN Serial enable |
| `CAN_D1_UC_SRV_BM` | — | 0.00 | — | Output channels to be transmitted as servo over DroneCAN |
| `CAN_D1_UC_SRV_RT` | — | 0.00 | Hz | Servo output rate |
| `CAN_D2_PC_ECU_ID` | — | 0.00 | — | ECU Node ID |
| `CAN_D2_PC_ECU_RT` | — | 0.00 | Hz | ECU command output rate |
| `CAN_D2_PC_ESC_BM` | — | 0.00 | — | ESC channels |
| `CAN_D2_PC_ESC_RT` | — | 0.00 | Hz | ESC output rate |
| `CAN_D2_PC_SRV_BM` | — | 0.00 | — | Servo channels |
| `CAN_D2_PC_SRV_RT` | — | 0.00 | Hz | Servo command output rate |
| `CAN_D2_PROTOCOL` | — | 0.00 | — | Enable use of specific protocol over virtual driver |
| `CAN_D2_PROTOCOL2` | — | 0.00 | — | Secondary protocol with 11 bit CAN addressing |
| `CAN_D2_UC_ESC_BM` | — | 0.00 | — | Output channels to be transmitted as ESC over DroneCAN |
| `CAN_D2_UC_ESC_OF` | — | 0.00 | — | ESC Output channels offset |
| `CAN_D2_UC_ESC_RV` | — | 0.00 | — | Bitmask for output channels for reversible ESCs over DroneCAN. |
| `CAN_D2_UC_NODE` | — | 0.00 | — | Own node ID |
| `CAN_D2_UC_NTF_RT` | — | 0.00 | Hz | Notify State rate |
| `CAN_D2_UC_OPTION` | — | 0.00 | — | DroneCAN options |
| `CAN_D2_UC_POOL` | — | 0.00 | — | CAN pool size |
| `CAN_D2_UC_RLY_RT` | — | 0.00 | Hz | DroneCAN relay output rate |
| `CAN_D2_UC_S1_BD` | — | 0.00 | — | DroneCAN Serial default baud rate |
| `CAN_D2_UC_S1_IDX` | — | 0.00 | — | DroneCAN Serial1 index |
| `CAN_D2_UC_S1_NOD` | — | 0.00 | — | Serial CAN remote node number |
| `CAN_D2_UC_S1_PRO` | — | 0.00 | — | Serial protocol of DroneCAN serial port |
| `CAN_D2_UC_S2_BD` | — | 0.00 | — | DroneCAN Serial default baud rate |
| `CAN_D2_UC_S2_IDX` | — | 0.00 | — | Serial port number on remote CAN node |
| `CAN_D2_UC_S2_NOD` | — | 0.00 | — | Serial CAN remote node number |
| `CAN_D2_UC_S2_PRO` | — | 0.00 | — | Serial protocol of DroneCAN serial port |
| `CAN_D2_UC_S3_BD` | — | 0.00 | — | Serial baud rate on remote CAN node |
| `CAN_D2_UC_S3_IDX` | — | 0.00 | — | Serial port number on remote CAN node |
| `CAN_D2_UC_S3_NOD` | — | 0.00 | — | Serial CAN remote node number |
| `CAN_D2_UC_S3_PRO` | — | 0.00 | — | Serial protocol of DroneCAN serial port |
| `CAN_D2_UC_SER_EN` | — | 0.00 | — | DroneCAN Serial enable |
| `CAN_D2_UC_SRV_BM` | — | 0.00 | — | Output channels to be transmitted as servo over DroneCAN |
| `CAN_D2_UC_SRV_RT` | — | 0.00 | Hz | Servo output rate |
| `CAN_D3_PC_ECU_ID` | — | 0.00 | — | ECU Node ID |
| `CAN_D3_PC_ECU_RT` | — | 0.00 | Hz | ECU command output rate |
| `CAN_D3_PC_ESC_BM` | — | 0.00 | — | ESC channels |
| `CAN_D3_PC_ESC_RT` | — | 0.00 | Hz | ESC output rate |
| `CAN_D3_PC_SRV_BM` | — | 0.00 | — | Servo channels |
| `CAN_D3_PC_SRV_RT` | — | 0.00 | Hz | Servo command output rate |
| `CAN_D3_PROTOCOL` | — | 0.00 | — | Enable use of specific protocol over virtual driver |
| `CAN_D3_PROTOCOL2` | — | 0.00 | — | Secondary protocol with 11 bit CAN addressing |
| `CAN_D3_UC_ESC_BM` | — | 0.00 | — | Output channels to be transmitted as ESC over DroneCAN |
| `CAN_D3_UC_ESC_OF` | — | 0.00 | — | ESC Output channels offset |
| `CAN_D3_UC_ESC_RV` | — | 0.00 | — | Bitmask for output channels for reversible ESCs over DroneCAN. |
| `CAN_D3_UC_NODE` | — | 0.00 | — | Own node ID |
| `CAN_D3_UC_NTF_RT` | — | 0.00 | Hz | Notify State rate |
| `CAN_D3_UC_OPTION` | — | 0.00 | — | DroneCAN options |
| `CAN_D3_UC_POOL` | — | 0.00 | — | CAN pool size |
| `CAN_D3_UC_RLY_RT` | — | 0.00 | Hz | DroneCAN relay output rate |
| `CAN_D3_UC_S1_BD` | — | 0.00 | — | DroneCAN Serial default baud rate |
| `CAN_D3_UC_S1_IDX` | — | 0.00 | — | DroneCAN Serial1 index |
| `CAN_D3_UC_S1_NOD` | — | 0.00 | — | Serial CAN remote node number |
| `CAN_D3_UC_S1_PRO` | — | 0.00 | — | Serial protocol of DroneCAN serial port |
| `CAN_D3_UC_S2_BD` | — | 0.00 | — | DroneCAN Serial default baud rate |
| `CAN_D3_UC_S2_IDX` | — | 0.00 | — | Serial port number on remote CAN node |
| `CAN_D3_UC_S2_NOD` | — | 0.00 | — | Serial CAN remote node number |
| `CAN_D3_UC_S2_PRO` | — | 0.00 | — | Serial protocol of DroneCAN serial port |
| `CAN_D3_UC_S3_BD` | — | 0.00 | — | Serial baud rate on remote CAN node |
| `CAN_D3_UC_S3_IDX` | — | 0.00 | — | Serial port number on remote CAN node |
| `CAN_D3_UC_S3_NOD` | — | 0.00 | — | Serial CAN remote node number |
| `CAN_D3_UC_S3_PRO` | — | 0.00 | — | Serial protocol of DroneCAN serial port |
| `CAN_D3_UC_SER_EN` | — | 0.00 | — | DroneCAN Serial enable |
| `CAN_D3_UC_SRV_BM` | — | 0.00 | — | Output channels to be transmitted as servo over DroneCAN |
| `CAN_D3_UC_SRV_RT` | — | 0.00 | Hz | Servo output rate |
| `CAN_LOGLEVEL` | — | 0.00 | — | Loglevel |
| `CAN_P1_BITRATE` | — | 0.00 | — | Bitrate of CAN interface |
| `CAN_P1_DRIVER` | — | 0.00 | — | Index of virtual driver to be used with physical CAN interface |
| `CAN_P1_FDBITRATE` | — | 0.00 | — | Bitrate of CANFD interface |
| `CAN_P1_OPTIONS` | — | 0.00 | — | CAN per-interface options |
| `CAN_P2_BITRATE` | — | 0.00 | — | Bitrate of CAN interface |
| `CAN_P2_DRIVER` | — | 0.00 | — | Index of virtual driver to be used with physical CAN interface |
| `CAN_P2_FDBITRATE` | — | 0.00 | — | Bitrate of CANFD interface |
| `CAN_P2_OPTIONS` | — | 0.00 | — | CAN per-interface options |
| `CAN_P3_BITRATE` | — | 0.00 | — | Bitrate of CAN interface |
| `CAN_P3_DRIVER` | — | 0.00 | — | Index of virtual driver to be used with physical CAN interface |
| `CAN_P3_FDBITRATE` | — | 0.00 | — | Bitrate of CANFD interface |
| `CAN_P3_OPTIONS` | — | 0.00 | — | CAN per-interface options |
| `CAN_SLCAN_CPORT` | — | 0.00 | — | SLCAN Route |
| `CAN_SLCAN_SDELAY` | — | 0.00 | — | SLCAN Start Delay |
| `CAN_SLCAN_SERNUM` | — | 0.00 | — | SLCAN Serial Port |
| `CAN_SLCAN_TIMOUT` | — | 0.00 | — | SLCAN Timeout |
| `CC_AXIS_MASK` | — | 0.00 | — | Custom Controller bitmask |
| `CC_TYPE` | — | 0.00 | — | Custom control type |
| `CGA_RATIO` | — | 0.00 | — | CoG adjustment ratio |
| `CHUTE_ALT_MIN` | — | 0.00 | m | Parachute min altitude in meters above home |
| `CHUTE_CRT_SINK` | — | 0.00 | m/s | Critical sink speed rate in m/s to trigger emergency parachute |
| `CHUTE_DELAY_MS` | — | 0.00 | ms | Parachute release delay |
| `CHUTE_ENABLED` | — | 0.00 | — | Parachute release enabled or disabled |
| `CHUTE_OPTIONS` | — | 0.00 | — | Parachute options |
| `CHUTE_SERVO_OFF` | — | 0.00 | PWM | Servo OFF PWM value |
| `CHUTE_SERVO_ON` | — | 0.00 | PWM | Parachute Servo ON PWM value |
| `CHUTE_TYPE` | — | 0.00 | — | Parachute release mechanism type (relay or servo) |
| `CIRCLE_OPTIONS` | — | 0.00 | — | Circle options |
| `CIRCLE_RADIUS` | — | 0.00 | cm | Circle Radius |
| `CIRCLE_RATE` | — | 0.00 | deg/s | Circle rate |
| `COMPASS_AUTODEC` | — | 0.00 | — | Auto Declination |
| `COMPASS_AUTO_ROT` | — | 0.00 | — | Automatically check orientation |
| `COMPASS_CAL_FIT` | `CAL_MAG0_ROLL` | 0.50 | — | Compass calibration fitness |
| `COMPASS_CUS_PIT` | — | 0.00 | deg | Custom orientation pitch offset |
| `COMPASS_CUS_ROLL` | — | 0.00 | deg | Custom orientation roll offset |
| `COMPASS_CUS_YAW` | — | 0.00 | deg | Custom orientation yaw offset |
| `COMPASS_DEC` | — | 0.00 | rad | Compass declination |
| `COMPASS_DEV_ID` | — | 0.00 | — | Compass device id |
| `COMPASS_DEV_ID2` | — | 0.00 | — | Compass2 device id |
| `COMPASS_DEV_ID3` | — | 0.00 | — | Compass3 device id |
| `COMPASS_DEV_ID4` | — | 0.00 | — | Compass4 device id |
| `COMPASS_DEV_ID5` | — | 0.00 | — | Compass5 device id |
| `COMPASS_DEV_ID6` | — | 0.00 | — | Compass6 device id |
| `COMPASS_DEV_ID7` | — | 0.00 | — | Compass7 device id |
| `COMPASS_DEV_ID8` | — | 0.00 | — | Compass8 device id |
| `COMPASS_DIA2_X` | — | 0.00 | — | Compass2 soft-iron diagonal X component |
| `COMPASS_DIA2_Y` | — | 0.00 | — | Compass2 soft-iron diagonal Y component |
| `COMPASS_DIA2_Z` | — | 0.00 | — | Compass2 soft-iron diagonal Z component |
| `COMPASS_DIA3_X` | — | 0.00 | — | Compass3 soft-iron diagonal X component |
| `COMPASS_DIA3_Y` | — | 0.00 | — | Compass3 soft-iron diagonal Y component |
| `COMPASS_DIA3_Z` | — | 0.00 | — | Compass3 soft-iron diagonal Z component |
| `COMPASS_DIA_X` | — | 0.00 | — | Compass soft-iron diagonal X component |
| `COMPASS_DIA_Y` | — | 0.00 | — | Compass soft-iron diagonal Y component |
| `COMPASS_DIA_Z` | — | 0.00 | — | Compass soft-iron diagonal Z component |
| `COMPASS_DISBLMSK` | — | 0.00 | — | Compass disable driver type mask |
| `COMPASS_ENABLE` | — | 0.00 | — | Enable Compass |
| `COMPASS_EXTERN2` | — | 0.00 | — | Compass2 is attached via an external cable |
| `COMPASS_EXTERN3` | — | 0.00 | — | Compass3 is attached via an external cable |
| `COMPASS_EXTERNAL` | — | 0.00 | — | Compass is attached via an external cable |
| `COMPASS_FLTR_RNG` | — | 0.00 | % | Range in which sample is accepted |
| `COMPASS_LEARN` | — | 0.00 | — | Learn compass offsets automatically |
| `COMPASS_MOT2_X` | — | 0.00 | mGauss/A | Motor interference compensation to compass2 for body frame X axis |
| `COMPASS_MOT2_Y` | — | 0.00 | mGauss/A | Motor interference compensation to compass2 for body frame Y axis |
| `COMPASS_MOT2_Z` | — | 0.00 | mGauss/A | Motor interference compensation to compass2 for body frame Z axis |
| `COMPASS_MOT3_X` | — | 0.00 | mGauss/A | Motor interference compensation to compass3 for body frame X axis |
| `COMPASS_MOT3_Y` | — | 0.00 | mGauss/A | Motor interference compensation to compass3 for body frame Y axis |
| `COMPASS_MOT3_Z` | — | 0.00 | mGauss/A | Motor interference compensation to compass3 for body frame Z axis |
| `COMPASS_MOTCT` | — | 0.00 | — | Motor interference compensation type |
| `COMPASS_MOT_X` | — | 0.00 | mGauss/A | Motor interference compensation for body frame X axis |
| `COMPASS_MOT_Y` | — | 0.00 | mGauss/A | Motor interference compensation for body frame Y axis |
| `COMPASS_MOT_Z` | — | 0.00 | mGauss/A | Motor interference compensation for body frame Z axis |
| `COMPASS_ODI2_X` | — | 0.00 | — | Compass2 soft-iron off-diagonal X component |
| `COMPASS_ODI2_Y` | — | 0.00 | — | Compass2 soft-iron off-diagonal Y component |
| `COMPASS_ODI2_Z` | — | 0.00 | — | Compass2 soft-iron off-diagonal Z component |
| `COMPASS_ODI3_X` | — | 0.00 | — | Compass3 soft-iron off-diagonal X component |
| `COMPASS_ODI3_Y` | — | 0.00 | — | Compass3 soft-iron off-diagonal Y component |
| `COMPASS_ODI3_Z` | — | 0.00 | — | Compass3 soft-iron off-diagonal Z component |
| `COMPASS_ODI_X` | — | 0.00 | — | Compass soft-iron off-diagonal X component |
| `COMPASS_ODI_Y` | — | 0.00 | — | Compass soft-iron off-diagonal Y component |
| `COMPASS_ODI_Z` | — | 0.00 | — | Compass soft-iron off-diagonal Z component |
| `COMPASS_OFFS_MAX` | — | 0.00 | — | Compass maximum offset |
| `COMPASS_OFS2_X` | — | 0.00 | mGauss | Compass2 offsets in milligauss on the X axis |
| `COMPASS_OFS2_Y` | — | 0.00 | mGauss | Compass2 offsets in milligauss on the Y axis |
| `COMPASS_OFS2_Z` | — | 0.00 | mGauss | Compass2 offsets in milligauss on the Z axis |
| `COMPASS_OFS3_X` | — | 0.00 | mGauss | Compass3 offsets in milligauss on the X axis |
| `COMPASS_OFS3_Y` | — | 0.00 | mGauss | Compass3 offsets in milligauss on the Y axis |
| `COMPASS_OFS3_Z` | — | 0.00 | mGauss | Compass3 offsets in milligauss on the Z axis |
| `COMPASS_OFS_X` | — | 0.00 | mGauss | Compass offsets in milligauss on the X axis |
| `COMPASS_OFS_Y` | — | 0.00 | mGauss | Compass offsets in milligauss on the Y axis |
| `COMPASS_OFS_Z` | — | 0.00 | mGauss | Compass offsets in milligauss on the Z axis |
| `COMPASS_OPTIONS` | — | 0.00 | — | Compass options |
| `COMPASS_ORIENT` | — | 0.00 | — | Compass orientation |
| `COMPASS_ORIENT2` | — | 0.00 | — | Compass2 orientation |
| `COMPASS_ORIENT3` | — | 0.00 | — | Compass3 orientation |
| `COMPASS_PMOT1_X` | — | 0.00 | — | Compass per-motor1 X |
| `COMPASS_PMOT1_Y` | — | 0.00 | — | Compass per-motor1 Y |
| `COMPASS_PMOT1_Z` | — | 0.00 | — | Compass per-motor1 Z |
| `COMPASS_PMOT2_X` | — | 0.00 | — | Compass per-motor2 X |
| `COMPASS_PMOT2_Y` | — | 0.00 | — | Compass per-motor2 Y |
| `COMPASS_PMOT2_Z` | — | 0.00 | — | Compass per-motor2 Z |
| `COMPASS_PMOT3_X` | — | 0.00 | — | Compass per-motor3 X |
| `COMPASS_PMOT3_Y` | — | 0.00 | — | Compass per-motor3 Y |
| `COMPASS_PMOT3_Z` | — | 0.00 | — | Compass per-motor3 Z |
| `COMPASS_PMOT4_X` | — | 0.00 | — | Compass per-motor4 X |
| `COMPASS_PMOT4_Y` | — | 0.00 | — | Compass per-motor4 Y |
| `COMPASS_PMOT4_Z` | — | 0.00 | — | Compass per-motor4 Z |
| `COMPASS_PMOT_EN` | — | 0.00 | — | per-motor compass correction enable |
| `COMPASS_PMOT_EXP` | — | 0.00 | — | per-motor exponential correction |
| `COMPASS_PRIO1_ID` | — | 0.00 | — | Compass device id with 1st order priority |
| `COMPASS_PRIO2_ID` | — | 0.00 | — | Compass device id with 2nd order priority |
| `COMPASS_PRIO3_ID` | — | 0.00 | — | Compass device id with 3rd order priority |
| `COMPASS_SCALE` | — | 0.00 | — | Compass1 scale factor |
| `COMPASS_SCALE2` | — | 0.00 | — | Compass2 scale factor |
| `COMPASS_SCALE3` | — | 0.00 | — | Compass3 scale factor |
| `COMPASS_USE` | — | 0.00 | — | Use compass for yaw |
| `COMPASS_USE2` | — | 0.00 | — | Compass2 used for yaw |
| `COMPASS_USE3` | — | 0.00 | — | Compass3 used for yaw |
| `CUST_ROT1_PITCH` | — | 0.00 | deg | Custom pitch |
| `CUST_ROT1_ROLL` | — | 0.00 | deg | Custom roll |
| `CUST_ROT1_YAW` | — | 0.00 | deg | Custom yaw |
| `CUST_ROT2_PITCH` | — | 0.00 | deg | Custom pitch |
| `CUST_ROT2_ROLL` | — | 0.00 | deg | Custom roll |
| `CUST_ROT2_YAW` | — | 0.00 | deg | Custom yaw |
| `CUST_ROT_ENABLE` | — | 0.00 | — | Enable Custom rotations |
| `DDS_DOMAIN_ID` | — | 0.00 | — | DDS DOMAIN ID |
| `DDS_ENABLE` | — | 0.00 | — | DDS enable |
| `DDS_IP0` | — | 0.00 | — | IPv4 Address 1st byte |
| `DDS_IP1` | — | 0.00 | — | IPv4 Address 2nd byte |
| `DDS_IP2` | — | 0.00 | — | IPv4 Address 3rd byte |
| `DDS_IP3` | — | 0.00 | — | IPv4 Address 4th byte |
| `DDS_MAX_RETRY` | — | 0.00 | — | DDS ping max attempts |
| `DDS_TIMEOUT_MS` | — | 0.00 | ms | DDS ping timeout |
| `DDS_UDP_PORT` | — | 0.00 | — | DDS UDP port |
| `DEV_OPTIONS` | — | 0.00 | — | Development options |
| `DID_BARO_ACC` | — | 0.00 | m | Barometer vertical accuraacy |
| `DID_CANDRIVER` | — | 0.00 | — | DroneCAN driver number |
| `DID_ENABLE` | — | 0.00 | — | Enable ODID subsystem |
| `DID_MAVPORT` | — | 0.00 | — | MAVLink serial port |
| `DID_OPTIONS` | — | 0.00 | — | OpenDroneID options |
| `DISARM_DELAY` | — | 0.00 | s | Disarm delay |
| `DIST_CUTOFF` | — | 0.00 | m | Precland distance cutoff |
| `DJIR_DEBUG` | — | 0.00 | — | DJIRS2 debug |
| `DJIR_UPSIDEDOWN` | — | 0.00 | — | DJIRS2 upside down |
| `DR_ENABLE` | — | 0.00 | — | Deadreckoning Enable |
| `DR_ENABLE_DIST` | — | 0.00 | m | Deadreckoning Enable Distance |
| `DR_FLY_ALT_MIN` | — | 0.00 | m | Deadreckoning Altitude Min |
| `DR_FLY_ANGLE` | — | 0.00 | deg | Deadreckoning Lean Angle |
| `DR_FLY_TIMEOUT` | — | 0.00 | s | Deadreckoning flight timeout |
| `DR_GPS_SACC_MAX` | `GPS_2_GNSS` | 0.30 | — | Deadreckoning GPS speed accuracy maximum threshold |
| `DR_GPS_SAT_MIN` | `GPS_SAT_INFO` | 0.50 | — | Deadreckoning GPS satellite count min threshold |
| `DR_GPS_TRIGG_SEC` | `GPS_2_GNSS` | 0.30 | s | Deadreckoning GPS check trigger seconds |
| `DR_NEXT_MODE` | — | 0.00 | — | Deadreckoning Next Mode |
| `EAHRS_LOG_RATE` | — | 0.00 | Hz | AHRS logging rate |
| `EAHRS_OPTIONS` | — | 0.00 | — | External AHRS options |
| `EAHRS_RATE` | — | 0.00 | Hz | AHRS data rate |
| `EAHRS_SENSORS` | — | 0.00 | — | External AHRS sensors |
| `EAHRS_TYPE` | — | 0.00 | — | AHRS type |
| `EFI_2K_CANDRV` | — | 0.00 | — | NMEA 2000 CAN driver |
| `EFI_2K_ENABLE` | — | 0.00 | — | Enable NMEA 2000 EFI driver |
| `EFI_2K_OPTIONS` | — | 0.00 | — | NMEA 2000 options |
| `EFI_COEF1` | — | 0.00 | — | EFI Calibration Coefficient 1 |
| `EFI_COEF2` | — | 0.00 | — | EFI Calibration Coefficient 2 |
| `EFI_DLA_ENABLE` | — | 0.00 | — | EFI DLA enable |
| `EFI_DLA_LPS` | — | 0.00 | litres | EFI DLA fuel scale |
| `EFI_FUEL_DENS` | — | 0.00 | kg/m/m/m | ECU Fuel Density |
| `EFI_H6K_CANDRV` | — | 0.00 | — | Halo6000 CAN driver |
| `EFI_H6K_ENABLE` | — | 0.00 | — | Enable Halo6000 EFI driver |
| `EFI_H6K_FUELTOT` | — | 0.00 | litres | Halo6000 total fuel capacity |
| `EFI_H6K_OPTIONS` | — | 0.00 | — | Halo6000 options |
| `EFI_H6K_START_FN` | — | 0.00 | — | Halo6000 start auxilliary function |
| `EFI_H6K_TELEM_RT` | — | 0.00 | Hz | Halo6000 telemetry rate |
| `EFI_INF_ENABLE` | — | 0.00 | — | EFI INF-Inject enable |
| `EFI_INF_IGN_AUX` | — | 0.00 | — | EFI INF-Inject ignition aux function |
| `EFI_INF_OPTIONS` | — | 0.00 | — | EFI INF-Inject options |
| `EFI_INF_THR_HZ` | — | 0.00 | Hz | EFI INF-Inject throttle rate |
| `EFI_SP_CANDRV` | — | 0.00 | — | Set SkyPower EFI CAN driver |
| `EFI_SP_ENABLE` | — | 0.00 | — | Enable SkyPower EFI support |
| `EFI_SP_GEN_CTRL` | — | 0.00 | — | SkyPower EFI enable generator control |
| `EFI_SP_GEN_FN` | — | 0.00 | — | SkyPower EFI generator control function |
| `EFI_SP_LOG_RT` | — | 0.00 | Hz | SkyPower EFI log rate |
| `EFI_SP_MIN_RPM` | — | 0.00 | — | SkyPower EFI minimum RPM |
| `EFI_SP_MODEL` | — | 0.00 | — | SkyPower EFI ECU model |
| `EFI_SP_RST_TIME` | — | 0.00 | s | SkyPower EFI restart time |
| `EFI_SP_START_FN` | — | 0.00 | — | SkyPower EFI start function |
| `EFI_SP_ST_DISARM` | — | 0.00 | — | SkyPower EFI allow start disarmed |
| `EFI_SP_THR_FN` | — | 0.00 | — | SkyPower EFI throttle function |
| `EFI_SP_THR_RATE` | — | 0.00 | Hz | SkyPower EFI throttle rate |
| `EFI_SP_TLM_RT` | — | 0.00 | Hz | SkyPower EFI telemetry rate |
| `EFI_SP_UPDATE_HZ` | — | 0.00 | Hz | SkyPower EFI update rate |
| `EFI_SVF_ARMCHECK` | — | 0.00 | — | Generator SVFFI arming check |
| `EFI_SVF_ENABLE` | — | 0.00 | — | Generator SVFFI enable |
| `EFI_THRLIN_COEF1` | — | 0.00 | — | Throttle linearisation - First Order |
| `EFI_THRLIN_COEF2` | — | 0.00 | — | Throttle linearisation - Second Order |
| `EFI_THRLIN_COEF3` | — | 0.00 | — | Throttle linearisation - Third Order |
| `EFI_THRLIN_EN` | — | 0.00 | — | Enable throttle linearisation |
| `EFI_THRLIN_OFS` | — | 0.00 | — | throttle linearization offset |
| `EFI_TYPE` | — | 0.00 | — | EFI communication type |
| `EK2_ABIAS_P_NSE` | — | 0.00 | m/s/s/s | Accelerometer bias stability (m/s^3) |
| `EK2_ACC_P_NSE` | — | 0.00 | m/s/s | Accelerometer noise (m/s^2) |
| `EK2_ALT_M_NSE` | — | 0.00 | m | Altitude measurement noise (m) |
| `EK2_ALT_SOURCE` | — | 0.00 | — | Primary altitude sensor source |
| `EK2_BCN_DELAY` | — | 0.00 | ms | Range beacon measurement delay (msec) |
| `EK2_BCN_I_GTE` | — | 0.00 | — | Range beacon measurement gate size |
| `EK2_BCN_M_NSE` | — | 0.00 | m | Range beacon measurement noise (m) |
| `EK2_CHECK_SCALE` | — | 0.00 | % | GPS accuracy check scaler (%) |
| `EK2_EAS_I_GATE` | — | 0.00 | — | Airspeed measurement gate size |
| `EK2_EAS_M_NSE` | — | 0.00 | m/s | Equivalent airspeed measurement noise (m/s) |
| `EK2_ENABLE` | — | 0.00 | — | Enable EKF2 |
| `EK2_FLOW_DELAY` | — | 0.00 | ms | Optical Flow measurement delay (msec) |
| `EK2_FLOW_I_GATE` | — | 0.00 | — | Optical Flow measurement gate size |
| `EK2_FLOW_M_NSE` | — | 0.00 | rad/s | Optical flow measurement noise (rad/s) |
| `EK2_FLOW_USE` | — | 0.00 | — | Optical flow use bitmask |
| `EK2_GBIAS_P_NSE` | — | 0.00 | rad/s/s | Rate gyro bias stability (rad/s/s) |
| `EK2_GLITCH_RAD` | — | 0.00 | m | GPS glitch radius gate size (m) |
| `EK2_GPS_CHECK` | `GPS_2_GNSS` | 0.35 | — | GPS preflight check |
| `EK2_GPS_TYPE` | `GPS_2_GNSS` | 0.43 | — | GPS mode control |
| `EK2_GSCL_P_NSE` | — | 0.00 | Hz | Rate gyro scale factor stability (1/s) |
| `EK2_GSF_RST_MAX` | — | 0.00 | — | Maximum number of resets to the EKF-GSF yaw estimate allowed |
| `EK2_GSF_RUN_MASK` | — | 0.00 | — | Bitmask of which EKF-GSF yaw estimators run |
| `EK2_GSF_USE_MASK` | — | 0.00 | — | Bitmask of which EKF-GSF yaw estimators are used |
| `EK2_GYRO_P_NSE` | — | 0.00 | rad/s | Rate gyro noise (rad/s) |
| `EK2_HGT_DELAY` | — | 0.00 | ms | Height measurement delay (msec) |
| `EK2_HGT_I_GATE` | — | 0.00 | — | Height measurement gate size |
| `EK2_HRT_FILT` | — | 0.00 | Hz | Height rate filter crossover frequency |
| `EK2_IMU_MASK` | — | 0.00 | — | Bitmask of active IMUs |
| `EK2_MAGB_P_NSE` | — | 0.00 | Gauss/s | Body magnetic field process noise (gauss/s) |
| `EK2_MAGE_P_NSE` | — | 0.00 | Gauss/s | Earth magnetic field process noise (gauss/s) |
| `EK2_MAG_CAL` | `CAL_MAG0_ROLL` | 0.50 | — | Magnetometer default fusion mode |
| `EK2_MAG_EF_LIM` | — | 0.00 | mGauss | EarthField error limit |
| `EK2_MAG_I_GATE` | — | 0.00 | — | Magnetometer measurement gate size |
| `EK2_MAG_MASK` | — | 0.00 | — | Bitmask of active EKF cores that will always use heading fusion |
| `EK2_MAG_M_NSE` | — | 0.00 | Gauss | Magnetometer measurement noise (Gauss) |
| `EK2_MAX_FLOW` | — | 0.00 | rad/s | Maximum valid optical flow rate |
| `EK2_NOAID_M_NSE` | — | 0.00 | m | Non-GPS operation position uncertainty (m) |
| `EK2_OGN_HGT_MASK` | — | 0.00 | — | Bitmask control of EKF reference height correction |
| `EK2_OPTIONS` | — | 0.00 | — | Optional EKF behaviour |
| `EK2_POSNE_M_NSE` | — | 0.00 | m | GPS horizontal position measurement noise (m) |
| `EK2_POS_I_GATE` | — | 0.00 | — | GPS position measurement gate size |
| `EK2_RNG_I_GATE` | — | 0.00 | — | Range finder measurement gate size |
| `EK2_RNG_M_NSE` | — | 0.00 | m | Range finder measurement noise (m) |
| `EK2_RNG_USE_HGT` | — | 0.00 | % | Range finder switch height percentage |
| `EK2_RNG_USE_SPD` | — | 0.00 | m/s | Range finder max ground speed |
| `EK2_TAU_OUTPUT` | — | 0.00 | cs | Output complementary filter time constant (centi-sec) |
| `EK2_TERR_GRAD` | — | 0.00 | — | Maximum terrain gradient |
| `EK2_VELD_M_NSE` | — | 0.00 | m/s | GPS vertical velocity measurement noise (m/s) |
| `EK2_VELNE_M_NSE` | — | 0.00 | m/s | GPS horizontal velocity measurement noise (m/s) |
| `EK2_VEL_I_GATE` | — | 0.00 | — | GPS velocity innovation gate size |
| `EK2_WIND_PSCALE` | — | 0.00 | — | Height rate to wind process noise scaler |
| `EK2_WIND_P_NSE` | — | 0.00 | m/s/s | Wind velocity process noise (m/s^2) |
| `EK2_YAW_I_GATE` | — | 0.00 | — | Yaw measurement gate size |
| `EK2_YAW_M_NSE` | — | 0.00 | rad | Yaw measurement noise (rad) |
| `EK3_ABIAS_P_NSE` | — | 0.00 | m/s/s/s | Accelerometer bias stability (m/s^3) |
| `EK3_ACC_BIAS_LIM` | — | 0.00 | m/s/s | Accelerometer bias limit |
| `EK3_ACC_P_NSE` | — | 0.00 | m/s/s | Accelerometer noise (m/s^2) |
| `EK3_AFFINITY` | — | 0.00 | — | EKF3 Sensor Affinity Options |
| `EK3_ALT_M_NSE` | — | 0.00 | m | Altitude measurement noise (m) |
| `EK3_BCN_DELAY` | — | 0.00 | ms | Range beacon measurement delay (msec) |
| `EK3_BCN_I_GTE` | — | 0.00 | — | Range beacon measurement gate size |
| `EK3_BCN_M_NSE` | — | 0.00 | m | Range beacon measurement noise (m) |
| `EK3_BETA_MASK` | — | 0.00 | — | Bitmask controlling sidelip angle fusion |
| `EK3_CHECK_SCALE` | — | 0.00 | % | GPS accuracy check scaler (%) |
| `EK3_DRAG_BCOEF_X` | — | 0.00 | kg/m/m | Ballistic coefficient for X axis drag |
| `EK3_DRAG_BCOEF_Y` | — | 0.00 | kg/m/m | Ballistic coefficient for Y axis drag |
| `EK3_DRAG_MCOEF` | — | 0.00 | 1/s | Momentum coefficient for propeller drag |
| `EK3_DRAG_M_NSE` | — | 0.00 | m/s/s | Observation noise for drag acceleration |
| `EK3_EAS_I_GATE` | — | 0.00 | — | Airspeed measurement gate size |
| `EK3_EAS_M_NSE` | — | 0.00 | m/s | Equivalent airspeed measurement noise (m/s) |
| `EK3_ENABLE` | — | 0.00 | — | Enable EKF3 |
| `EK3_ERR_THRESH` | — | 0.00 | — | EKF3 Lane Relative Error Sensitivity Threshold |
| `EK3_FLOW_DELAY` | — | 0.00 | ms | Optical Flow measurement delay (msec) |
| `EK3_FLOW_I_GATE` | — | 0.00 | — | Optical Flow measurement gate size |
| `EK3_FLOW_M_NSE` | — | 0.00 | rad/s | Optical flow measurement noise (rad/s) |
| `EK3_FLOW_USE` | — | 0.00 | — | Optical flow use bitmask |
| `EK3_GBIAS_P_NSE` | — | 0.00 | rad/s/s | Rate gyro bias stability (rad/s/s) |
| `EK3_GLITCH_RAD` | — | 0.00 | m | GPS glitch radius gate size (m) |
| `EK3_GND_EFF_DZ` | — | 0.00 | — | Baro height ground effect dead zone |
| `EK3_GPS_CHECK` | `GPS_2_GNSS` | 0.35 | — | GPS preflight check |
| `EK3_GPS_VACC_MAX` | `GPS_2_GNSS` | 0.30 | m | GPS vertical accuracy threshold |
| `EK3_GSF_RST_MAX` | — | 0.00 | — | Maximum number of resets to the EKF-GSF yaw estimate allowed |
| `EK3_GSF_RUN_MASK` | — | 0.00 | — | Bitmask of which EKF-GSF yaw estimators run |
| `EK3_GSF_USE_MASK` | — | 0.00 | — | Bitmask of which EKF-GSF yaw estimators are used |
| `EK3_GYRO_P_NSE` | — | 0.00 | rad/s | Rate gyro noise (rad/s) |
| `EK3_HGT_DELAY` | — | 0.00 | ms | Height measurement delay (msec) |
| `EK3_HGT_I_GATE` | — | 0.00 | — | Height measurement gate size |
| `EK3_HRT_FILT` | — | 0.00 | Hz | Height rate filter crossover frequency |
| `EK3_IMU_MASK` | — | 0.00 | — | Bitmask of active IMUs |
| `EK3_LOG_LEVEL` | — | 0.00 | — | Logging Level |
| `EK3_MAGB_P_NSE` | — | 0.00 | Gauss/s | Body magnetic field process noise (gauss/s) |
| `EK3_MAGE_P_NSE` | — | 0.00 | Gauss/s | Earth magnetic field process noise (gauss/s) |
| `EK3_MAG_CAL` | `CAL_MAG0_ROLL` | 0.50 | — | Magnetometer default fusion mode |
| `EK3_MAG_EF_LIM` | — | 0.00 | mGauss | EarthField error limit |
| `EK3_MAG_I_GATE` | — | 0.00 | — | Magnetometer measurement gate size |
| `EK3_MAG_MASK` | — | 0.00 | — | Bitmask of active EKF cores that will always use heading fusion |
| `EK3_MAG_M_NSE` | — | 0.00 | Gauss | Magnetometer measurement noise (Gauss) |
| `EK3_MAX_FLOW` | — | 0.00 | rad/s | Maximum valid optical flow rate |
| `EK3_NOAID_M_NSE` | — | 0.00 | m | Non-GPS operation position uncertainty (m) |
| `EK3_OGNM_TEST_SF` | — | 0.00 | — | On ground not moving test scale factor |
| `EK3_OGN_HGT_MASK` | — | 0.00 | — | Bitmask control of EKF reference height correction |
| `EK3_OPTIONS` | — | 0.00 | — | Optional EKF behaviour |
| `EK3_POSNE_M_NSE` | — | 0.00 | m | GPS horizontal position measurement noise (m) |
| `EK3_POS_I_GATE` | — | 0.00 | — | GPS position measurement gate size |
| `EK3_PRIMARY` | — | 0.00 | — | Primary core number |
| `EK3_RNG_I_GATE` | — | 0.00 | — | Range finder measurement gate size |
| `EK3_RNG_M_NSE` | — | 0.00 | m | Range finder measurement noise (m) |
| `EK3_RNG_USE_HGT` | — | 0.00 | % | Range finder switch height percentage |
| `EK3_RNG_USE_SPD` | — | 0.00 | m/s | Range finder max ground speed |
| `EK3_SRC1_POSXY` | — | 0.00 | — | Position Horizontal Source (Primary) |
| `EK3_SRC1_POSZ` | — | 0.00 | — | Position Vertical Source |
| `EK3_SRC1_VELXY` | — | 0.00 | — | Velocity Horizontal Source |
| `EK3_SRC1_VELZ` | — | 0.00 | — | Velocity Vertical Source |
| `EK3_SRC1_YAW` | — | 0.00 | — | Yaw Source |
| `EK3_SRC2_POSXY` | — | 0.00 | — | Position Horizontal Source (Secondary) |
| `EK3_SRC2_POSZ` | — | 0.00 | — | Position Vertical Source (Secondary) |
| `EK3_SRC2_VELXY` | — | 0.00 | — | Velocity Horizontal Source (Secondary) |
| `EK3_SRC2_VELZ` | — | 0.00 | — | Velocity Vertical Source (Secondary) |
| `EK3_SRC2_YAW` | — | 0.00 | — | Yaw Source (Secondary) |
| `EK3_SRC3_POSXY` | — | 0.00 | — | Position Horizontal Source (Tertiary) |
| `EK3_SRC3_POSZ` | — | 0.00 | — | Position Vertical Source (Tertiary) |
| `EK3_SRC3_VELXY` | — | 0.00 | — | Velocity Horizontal Source (Tertiary) |
| `EK3_SRC3_VELZ` | — | 0.00 | — | Velocity Vertical Source (Tertiary) |
| `EK3_SRC3_YAW` | — | 0.00 | — | Yaw Source (Tertiary) |
| `EK3_SRC_OPTIONS` | — | 0.00 | — | EKF Source Options |
| `EK3_TAU_OUTPUT` | — | 0.00 | cs | Output complementary filter time constant (centi-sec) |
| `EK3_TERR_GRAD` | — | 0.00 | — | Maximum terrain gradient |
| `EK3_VELD_M_NSE` | — | 0.00 | m/s | GPS vertical velocity measurement noise (m/s) |
| `EK3_VELNE_M_NSE` | — | 0.00 | m/s | GPS horizontal velocity measurement noise (m/s) |
| `EK3_VEL_I_GATE` | — | 0.00 | — | GPS velocity innovation gate size |
| `EK3_VIS_VERR_MAX` | — | 0.00 | m/s | Visual odometry maximum velocity error |
| `EK3_VIS_VERR_MIN` | — | 0.00 | m/s | Visual odometry minimum velocity error |
| `EK3_WENC_VERR` | — | 0.00 | m/s | Wheel odometry velocity error |
| `EK3_WIND_PSCALE` | — | 0.00 | — | Height rate to wind process noise scaler |
| `EK3_WIND_P_NSE` | — | 0.00 | m/s/s | Wind velocity process noise (m/s^2) |
| `EK3_YAW_I_GATE` | — | 0.00 | — | Yaw measurement gate size |
| `EK3_YAW_M_NSE` | — | 0.00 | rad | Yaw measurement noise (rad) |
| `ESC_CALIBRATION` | `ESC_HW_VER` | 0.37 | — | ESC Calibration |
| `ESC_HW_ENABLE` | `ESC_HW_VER` | 0.79 | — | Hobbywing ESC Enable |
| `ESC_HW_OFS` | `ESC_HW_VER` | 0.62 | — | Hobbywing ESC motor offset |
| `ESC_HW_POLES` | `ESC_HW_VER` | 0.62 | — | Hobbywing ESC motor poles |
| `ESC_TLM_MAV_OFS` | — | 0.00 | — | ESC Telemetry mavlink offset |
| `ESRC_EXTN_QUAL` | — | 0.00 | % | EKF Source ExternalNav Quality Threshold |
| `ESRC_EXTN_THRESH` | — | 0.00 | — | EKF Source ExternalNav Innovation Threshold |
| `ESRC_FLOW_QUAL` | — | 0.00 | % | EKF Source OpticalFlow Quality Threshold |
| `ESRC_FLOW_THRESH` | — | 0.00 | — | EKF Source OpticalFlow Innovation Threshold |
| `ESRC_RNGFND_MAX` | — | 0.00 | m | EKF Source Rangefinder Max |
| `FENCE_ACTION` | — | 0.00 | — | Fence Action |
| `FENCE_ALT_MAX` | — | 0.00 | m | Fence Maximum Altitude |
| `FENCE_ALT_MIN` | — | 0.00 | m | Fence Minimum Altitude |
| `FENCE_AUTOENABLE` | — | 0.00 | — | Fence Auto-Enable |
| `FENCE_ENABLE` | — | 0.00 | — | Fence enable/disable |
| `FENCE_MARGIN` | — | 0.00 | m | Fence Margin |
| `FENCE_OPTIONS` | — | 0.00 | — | Fence options |
| `FENCE_RADIUS` | — | 0.00 | m | Circular Fence Radius |
| `FENCE_TOTAL` | — | 0.00 | — | Fence polygon point total |
| `FENCE_TYPE` | — | 0.00 | — | Fence Type |
| `FFT_ATT_REF` | `ATT_EN` | 0.33 | — | FFT attenuation for bandwidth calculation |
| `FFT_BW_HOVER` | — | 0.00 | — | FFT learned bandwidth at hover |
| `FFT_ENABLE` | — | 0.00 | — | Enable |
| `FFT_FREQ_HOVER` | — | 0.00 | — | FFT learned hover frequency |
| `FFT_HMNC_FIT` | — | 0.00 | — | FFT harmonic fit frequency threshold |
| `FFT_HMNC_PEAK` | — | 0.00 | — | FFT harmonic peak target |
| `FFT_MAXHZ` | — | 0.00 | Hz | Maximum Frequency |
| `FFT_MINHZ` | — | 0.00 | Hz | Minimum Frequency |
| `FFT_NUM_FRAMES` | — | 0.00 | — | FFT output frames to retain and average |
| `FFT_OPTIONS` | — | 0.00 | — | FFT options |
| `FFT_SAMPLE_MODE` | — | 0.00 | — | Sample Mode |
| `FFT_SNR_REF` | — | 0.00 | — | FFT SNR reference threshold |
| `FFT_THR_REF` | — | 0.00 | — | FFT learned thrust reference |
| `FFT_WINDOW_OLAP` | — | 0.00 | — | FFT window overlap |
| `FFT_WINDOW_SIZE` | — | 0.00 | — | FFT window size |
| `FHLD_BRAKE_RATE` | — | 0.00 | deg/s | FlowHold Braking rate |
| `FHLD_FILT_HZ` | — | 0.00 | Hz | FlowHold Filter Frequency |
| `FHLD_FLOW_MAX` | — | 0.00 | — | FlowHold Flow Rate Max |
| `FHLD_QUAL_MIN` | — | 0.00 | — | FlowHold Flow quality minimum |
| `FHLD_XY_FILT_HZ` | — | 0.00 | Hz | FlowHold filter on input to control |
| `FHLD_XY_I` | — | 0.00 | — | FlowHold I gain |
| `FHLD_XY_IMAX` | — | 0.00 | cdeg | FlowHold Integrator Max |
| `FHLD_XY_P` | — | 0.00 | — | FlowHold P gain |
| `FILT1_NOTCH_ATT` | `ATT_EN` | 0.33 | dB | Notch Filter attenuation |
| `FILT1_NOTCH_FREQ` | — | 0.00 | Hz | Notch Filter center frequency |
| `FILT1_NOTCH_Q` | — | 0.00 | — | Notch Filter quality factor |
| `FILT1_TYPE` | — | 0.00 | — | Filter Type |
| `FILT2_NOTCH_ATT` | `ATT_EN` | 0.33 | dB | Notch Filter attenuation |
| `FILT2_NOTCH_FREQ` | — | 0.00 | Hz | Notch Filter center frequency |
| `FILT2_NOTCH_Q` | — | 0.00 | — | Notch Filter quality factor |
| `FILT2_TYPE` | — | 0.00 | — | Filter Type |
| `FILT3_NOTCH_ATT` | `ATT_EN` | 0.33 | dB | Notch Filter attenuation |
| `FILT3_NOTCH_FREQ` | — | 0.00 | Hz | Notch Filter center frequency |
| `FILT3_NOTCH_Q` | — | 0.00 | — | Notch Filter quality factor |
| `FILT3_TYPE` | — | 0.00 | — | Filter Type |
| `FILT4_NOTCH_ATT` | `ATT_EN` | 0.33 | dB | Notch Filter attenuation |
| `FILT4_NOTCH_FREQ` | — | 0.00 | Hz | Notch Filter center frequency |
| `FILT4_NOTCH_Q` | — | 0.00 | — | Notch Filter quality factor |
| `FILT4_TYPE` | — | 0.00 | — | Filter Type |
| `FILT5_NOTCH_ATT` | `ATT_EN` | 0.33 | dB | Notch Filter attenuation |
| `FILT5_NOTCH_FREQ` | — | 0.00 | Hz | Notch Filter center frequency |
| `FILT5_NOTCH_Q` | — | 0.00 | — | Notch Filter quality factor |
| `FILT5_TYPE` | — | 0.00 | — | Filter Type |
| `FILT6_NOTCH_ATT` | `ATT_EN` | 0.33 | dB | Notch Filter attenuation |
| `FILT6_NOTCH_FREQ` | — | 0.00 | Hz | Notch Filter center frequency |
| `FILT6_NOTCH_Q` | — | 0.00 | — | Notch Filter quality factor |
| `FILT6_TYPE` | — | 0.00 | — | Filter Type |
| `FILT7_NOTCH_ATT` | `ATT_EN` | 0.33 | dB | Notch Filter attenuation |
| `FILT7_NOTCH_FREQ` | — | 0.00 | Hz | Notch Filter center frequency |
| `FILT7_NOTCH_Q` | — | 0.00 | — | Notch Filter quality factor |
| `FILT7_TYPE` | — | 0.00 | — | Filter Type |
| `FILT8_NOTCH_ATT` | `ATT_EN` | 0.33 | dB | Notch Filter attenuation |
| `FILT8_NOTCH_FREQ` | — | 0.00 | Hz | Notch Filter center frequency |
| `FILT8_NOTCH_Q` | — | 0.00 | — | Notch Filter quality factor |
| `FILT8_TYPE` | — | 0.00 | — | Filter Type |
| `FLIGHT_OPTIONS` | — | 0.00 | — | Flight mode options |
| `FLOW_ADDR` | — | 0.00 | — | Address on the bus |
| `FLOW_FXSCALER` | — | 0.00 | — | X axis optical flow scale factor correction |
| `FLOW_FYSCALER` | — | 0.00 | — | Y axis optical flow scale factor correction |
| `FLOW_HGT_OVR` | — | 0.00 | m | Height override of sensor above ground |
| `FLOW_ORIENT_YAW` | — | 0.00 | cdeg | Flow sensor yaw alignment |
| `FLOW_POS_X` | — | 0.00 | m | X position offset |
| `FLOW_POS_Y` | — | 0.00 | m | Y position offset |
| `FLOW_POS_Z` | — | 0.00 | m | Z position offset |
| `FLOW_TYPE` | — | 0.00 | — | Optical flow sensor type |
| `FLTMODE1` | — | 0.00 | — | Flight Mode 1 |
| `FLTMODE2` | — | 0.00 | — | Flight Mode 2 |
| `FLTMODE3` | — | 0.00 | — | Flight Mode 3 |
| `FLTMODE4` | — | 0.00 | — | Flight Mode 4 |
| `FLTMODE5` | — | 0.00 | — | Flight Mode 5 |
| `FLTMODE6` | — | 0.00 | — | Flight Mode 6 |
| `FLTMODE_CH` | — | 0.00 | — | Flightmode channel |
| `FOLL_ALT_TYPE` | — | 0.00 | — | Follow altitude type |
| `FOLL_DIST_MAX` | — | 0.00 | m | Follow distance maximum |
| `FOLL_ENABLE` | — | 0.00 | — | Follow enable/disable |
| `FOLL_OFS_TYPE` | — | 0.00 | — | Follow offset type |
| `FOLL_OFS_X` | — | 0.00 | m | Follow offsets in meters north/forward |
| `FOLL_OFS_Y` | — | 0.00 | m | Follow offsets in meters east/right |
| `FOLL_OFS_Z` | — | 0.00 | m | Follow offsets in meters down |
| `FOLL_OPTIONS` | — | 0.00 | — | Follow options |
| `FOLL_POS_P` | — | 0.00 | — | Follow position error P gain |
| `FOLL_SYSID` | — | 0.00 | — | Follow target's mavlink system id |
| `FOLL_YAW_BEHAVE` | — | 0.00 | — | Follow yaw behaviour |
| `FORMAT_VERSION` | — | 0.00 | — | Eeprom format version number |
| `FRAME_CLASS` | — | 0.00 | — | Frame Class |
| `FRAME_TYPE` | — | 0.00 | — | Frame Type (+, X, V, etc) |
| `FRSKY_DNLINK1_ID` | — | 0.00 | — | First downlink sensor id |
| `FRSKY_DNLINK2_ID` | — | 0.00 | — | Second downlink sensor id |
| `FRSKY_DNLINK_ID` | — | 0.00 | — | Default downlink sensor id |
| `FRSKY_OPTIONS` | — | 0.00 | — | FRSky Telemetry Options |
| `FRSKY_UPLINK_ID` | — | 0.00 | — | Uplink sensor id |
| `FS_CRASH_CHECK` | — | 0.00 | — | Crash check enable |
| `FS_DR_ENABLE` | — | 0.00 | — | DeadReckon Failsafe Action |
| `FS_DR_TIMEOUT` | — | 0.00 | — | DeadReckon Failsafe Timeout |
| `FS_EKF_ACTION` | `EKF2_EN` | 0.33 | — | EKF Failsafe Action |
| `FS_EKF_FILT` | `EKF2_EN` | 0.33 | Hz | EKF Failsafe filter cutoff |
| `FS_EKF_THRESH` | `EKF2_EN` | 0.33 | — | EKF failsafe variance threshold |
| `FS_GCS_ENABLE` | — | 0.00 | — | Ground Station Failsafe Enable |
| `FS_GCS_TIMEOUT` | — | 0.00 | s | GCS failsafe timeout |
| `FS_OPTIONS` | — | 0.00 | — | Failsafe options bitmask |
| `FS_THR_ENABLE` | — | 0.00 | — | Throttle Failsafe Enable |
| `FS_THR_VALUE` | — | 0.00 | PWM | Throttle Failsafe Value |
| `FS_VIBE_ENABLE` | — | 0.00 | — | Vibration Failsafe enable |
| `GCS_PID_MASK` | — | 0.00 | — | GCS PID tuning mask |
| `GEN_OPTIONS` | — | 0.00 | — | Generator Options |
| `GEN_TYPE` | — | 0.00 | — | Generator type |
| `GND_EFFECT_COMP` | — | 0.00 | — | Ground Effect Compensation Enable/Disable |
| `GPS1_CAN_NODEID` | `GPS_2_GNSS` | 0.35 | — | Detected CAN Node ID for GPS |
| `GPS1_CAN_OVRIDE` | `GPS_2_GNSS` | 0.35 | — | DroneCAN GPS NODE ID |
| `GPS1_COM_PORT` | `COM_ARM_WO_GPS` | 0.50 | — | GPS physical COM port |
| `GPS1_DELAY_MS` | `GPS_2_GNSS` | 0.35 | ms | GPS delay in milliseconds |
| `GPS1_GNSS_MODE` | `GPS_2_GNSS` | 0.77 | — | GNSS system configuration |
| `GPS1_MB_OFS_X` | `GPS_2_GNSS` | 0.30 | m | Base antenna X position offset |
| `GPS1_MB_OFS_Y` | `GPS_2_GNSS` | 0.30 | m | Base antenna Y position offset |
| `GPS1_MB_OFS_Z` | `GPS_2_GNSS` | 0.30 | m | Base antenna Z position offset |
| `GPS1_MB_TYPE` | `GPS_2_GNSS` | 0.43 | — | Moving base type |
| `GPS1_POS_X` | `GPS_2_GNSS` | 0.35 | m | Antenna X position offset |
| `GPS1_POS_Y` | `GPS_2_GNSS` | 0.35 | m | Antenna Y position offset |
| `GPS1_POS_Z` | `GPS_2_GNSS` | 0.35 | m | Antenna Z position offset |
| `GPS1_RATE_MS` | `GPS_UBX_RATE` | 0.60 | ms | GPS update rate in milliseconds |
| `GPS1_TYPE` | `GPS_2_GNSS` | 0.60 | — | GPS type |
| `GPS2_CAN_NODEID` | `GPS_2_GNSS` | 0.35 | — | Detected CAN Node ID for GPS |
| `GPS2_CAN_OVRIDE` | `GPS_2_GNSS` | 0.35 | — | DroneCAN GPS NODE ID |
| `GPS2_COM_PORT` | `COM_ARM_WO_GPS` | 0.50 | — | GPS physical COM port |
| `GPS2_DELAY_MS` | `GPS_2_GNSS` | 0.35 | ms | GPS delay in milliseconds |
| `GPS2_GNSS_MODE` | `GPS_2_GNSS` | 0.77 | — | GNSS system configuration |
| `GPS2_MB_OFS_X` | `GPS_2_GNSS` | 0.30 | m | Base antenna X position offset |
| `GPS2_MB_OFS_Y` | `GPS_2_GNSS` | 0.30 | m | Base antenna Y position offset |
| `GPS2_MB_OFS_Z` | `GPS_2_GNSS` | 0.30 | m | Base antenna Z position offset |
| `GPS2_MB_TYPE` | `GPS_2_GNSS` | 0.43 | — | Moving base type |
| `GPS2_POS_X` | `GPS_2_GNSS` | 0.35 | m | Antenna X position offset |
| `GPS2_POS_Y` | `GPS_2_GNSS` | 0.35 | m | Antenna Y position offset |
| `GPS2_POS_Z` | `GPS_2_GNSS` | 0.35 | m | Antenna Z position offset |
| `GPS2_RATE_MS` | `GPS_UBX_RATE` | 0.60 | ms | GPS update rate in milliseconds |
| `GPS2_TYPE` | `GPS_2_GNSS` | 0.60 | — | GPS type |
| `GPS_AUTO_CONFIG` | `GPS_2_CONFIG` | 0.89 | — | Automatic GPS configuration |
| `GPS_AUTO_SWITCH` | `GPS_2_GNSS` | 0.47 | — | Automatic Switchover Setting |
| `GPS_BLEND_MASK` | `GPS_2_GNSS` | 0.47 | — | Multi GPS Blending Mask |
| `GPS_CAN_NODEID1` | `GPS_2_GNSS` | 0.47 | — | GPS Node ID 1 |
| `GPS_CAN_NODEID2` | `GPS_2_GNSS` | 0.47 | — | GPS Node ID 2 |
| `GPS_COM_PORT` | `COM_ARM_WO_GPS` | 0.50 | — | GPS physical COM port |
| `GPS_COM_PORT2` | `COM_ARM_WO_GPS` | 0.50 | — | GPS physical COM port |
| `GPS_DELAY_MS` | `GPS_2_GNSS` | 0.47 | ms | GPS delay in milliseconds |
| `GPS_DELAY_MS2` | `GPS_2_GNSS` | 0.47 | ms | GPS 2 delay in milliseconds |
| `GPS_DRV_OPTIONS` | `GPS_2_GNSS` | 0.47 | — | driver options |
| `GPS_GNSS_MODE` | `GPS_2_GNSS` | 0.89 | — | GNSS system configuration |
| `GPS_GNSS_MODE2` | `GPS_2_GNSS` | 0.89 | — | GNSS system configuration. |
| `GPS_HDOP_GOOD` | `GPS_2_GNSS` | 0.47 | — | GPS Hdop Good |
| `GPS_INJECT_TO` | `GPS_UBX_DGNSS_TO` | 0.62 | — | Destination for GPS_INJECT_DATA MAVLink packets |
| `GPS_MB1_OFS_X` | `GPS_2_GNSS` | 0.42 | m | Base antenna X position offset |
| `GPS_MB1_OFS_Y` | `GPS_2_GNSS` | 0.42 | m | Base antenna Y position offset |
| `GPS_MB1_OFS_Z` | `GPS_2_GNSS` | 0.42 | m | Base antenna Z position offset |
| `GPS_MB1_TYPE` | `GPS_2_GNSS` | 0.55 | — | Moving base type |
| `GPS_MB2_OFS_X` | `GPS_2_GNSS` | 0.42 | m | Base antenna X position offset |
| `GPS_MB2_OFS_Y` | `GPS_2_GNSS` | 0.42 | m | Base antenna Y position offset |
| `GPS_MB2_OFS_Z` | `GPS_2_GNSS` | 0.42 | m | Base antenna Z position offset |
| `GPS_MB2_TYPE` | `GPS_2_GNSS` | 0.55 | — | Moving base type |
| `GPS_MIN_ELEV` | `GPS_UBX_MIN_ELEV` | 0.97 | deg | Minimum elevation |
| `GPS_NAVFILTER` | `GPS_2_GNSS` | 0.55 | — | Navigation filter setting |
| `GPS_POS1_X` | `GPS_2_GNSS` | 0.47 | m | Antenna X position offset |
| `GPS_POS1_Y` | `GPS_2_GNSS` | 0.47 | m | Antenna Y position offset |
| `GPS_POS1_Z` | `GPS_2_GNSS` | 0.47 | m | Antenna Z position offset |
| `GPS_POS2_X` | `GPS_2_GNSS` | 0.47 | m | Antenna X position offset |
| `GPS_POS2_Y` | `GPS_2_GNSS` | 0.47 | m | Antenna Y position offset |
| `GPS_POS2_Z` | `GPS_2_GNSS` | 0.47 | m | Antenna Z position offset |
| `GPS_PRIMARY` | `GPS_2_GNSS` | 0.55 | — | Primary GPS |
| `GPS_RATE_MS` | `GPS_UBX_RATE` | 0.72 | ms | GPS update rate in milliseconds |
| `GPS_RATE_MS2` | `GPS_UBX_RATE` | 0.72 | ms | GPS 2 update rate in milliseconds |
| `GPS_RAW_DATA` | `GPS_2_GNSS` | 0.47 | — | Raw data logging |
| `GPS_SAVE_CFG` | `GPS_CFG_WIPE` | 0.72 | — | Save GPS configuration |
| `GPS_SBAS_MODE` | `GPS_UBX_MODE` | 0.72 | — | SBAS Mode |
| `GPS_SBP_LOGMASK` | `GPS_2_GNSS` | 0.47 | — | Swift Binary Protocol Logging Mask |
| `GPS_TYPE` | `GPS_2_GNSS` | 0.72 | — | 1st GPS type |
| `GPS_TYPE2` | `GPS_2_GNSS` | 0.72 | — | 2nd GPS type.Renamed in 4.6 to GPS2_TYPE |
| `GRIP_AUTOCLOSE` | — | 0.00 | s | Gripper Autoclose time |
| `GRIP_CAN_ID` | — | 0.00 | — | EPM UAVCAN Hardpoint ID |
| `GRIP_ENABLE` | — | 0.00 | — | Gripper Enable/Disable |
| `GRIP_GRAB` | — | 0.00 | PWM | Gripper Grab PWM |
| `GRIP_NEUTRAL` | — | 0.00 | PWM | Neutral PWM |
| `GRIP_REGRAB` | — | 0.00 | s | EPM Gripper Regrab interval |
| `GRIP_RELEASE` | — | 0.00 | PWM | Gripper Release PWM |
| `GRIP_TYPE` | — | 0.00 | — | Gripper Type |
| `GUID_OPTIONS` | — | 0.00 | — | Guided mode options |
| `GUID_TIMEOUT` | — | 0.00 | s | Guided mode timeout |
| `H_COL2YAW` | — | 0.00 | — | Collective-Yaw Mixing |
| `H_COL2_MAX` | — | 0.00 | PWM | Swash 2 Maximum Collective Pitch |
| `H_COL2_MIN` | — | 0.00 | PWM | Swash 2 Minimum Collective Pitch |
| `H_COL_ANG_MAX` | — | 0.00 | deg | Collective Blade Pitch Angle Maximum |
| `H_COL_ANG_MIN` | — | 0.00 | deg | Collective Blade Pitch Angle Minimum |
| `H_COL_HOVER` | — | 0.00 | — | Collective Hover Value |
| `H_COL_LAND_MIN` | — | 0.00 | deg | Collective Blade Pitch Minimum when Landed |
| `H_COL_MAX` | — | 0.00 | PWM | Maximum Collective Pitch |
| `H_COL_MIN` | — | 0.00 | PWM | Minimum Collective Pitch |
| `H_COL_ZERO_THRST` | — | 0.00 | deg | Collective Blade Pitch at Zero Thrust |
| `H_CYC_MAX` | — | 0.00 | — | Maximum Cyclic Pitch Angle |
| `H_DCP_SCALER` | — | 0.00 | — | Differential-Collective-Pitch Scaler |
| `H_DCP_TRIM` | — | 0.00 | — | Differential Collective Pitch Trim |
| `H_DCP_YAW` | — | 0.00 | — | Differential-Collective-Pitch Yaw Mixing |
| `H_DDFP_BAT_IDX` | — | 0.00 | — | DDFP Tail Rotor Battery compensation index |
| `H_DDFP_BAT_V_MAX` | `BAT2_V_FILT` | 0.33 | V | Battery voltage compensation maximum voltage |
| `H_DDFP_BAT_V_MIN` | `BAT2_V_FILT` | 0.33 | V | Battery voltage compensation minimum voltage |
| `H_DDFP_SPIN_MAX` | — | 0.00 | — | DDFP Tail Rotor Motor Spin maximum |
| `H_DDFP_SPIN_MIN` | — | 0.00 | — | DDFP Tail Rotor Motor Spin minimum |
| `H_DDFP_THST_EXPO` | — | 0.00 | — | DDFP Tail Rotor Thrust Curve Expo |
| `H_DUAL_MODE` | — | 0.00 | — | Dual Mode |
| `H_FLYBAR_MODE` | — | 0.00 | — | Flybar Mode Selector |
| `H_GYR_GAIN` | — | 0.00 | PWM | External Gyro Gain |
| `H_GYR_GAIN_ACRO` | — | 0.00 | PWM | ACRO External Gyro Gain |
| `H_HOVER_LEARN` | — | 0.00 | — | Hover Value Learning |
| `H_OPTIONS` | — | 0.00 | — | Heli_Options |
| `H_RSC_AROT_ENBL` | — | 0.00 | — | Enable autorotation handling in RSC |
| `H_RSC_AROT_IDLE` | — | 0.00 | % | Idle throttle percentage during autorotation |
| `H_RSC_AROT_RAMP` | — | 0.00 | s | Time for in-flight power re-engagement when exiting autorotations |
| `H_RSC_AROT_RUNUP` | — | 0.00 | s | Time allowed for in-flight power re-engagement |
| `H_RSC_CLDWN_TIME` | — | 0.00 | s | Cooldown Time |
| `H_RSC_CRITICAL` | — | 0.00 | % | Critical Rotor Speed |
| `H_RSC_GOV_COMP` | — | 0.00 | % | Governor Torque Compensator |
| `H_RSC_GOV_DROOP` | — | 0.00 | % | Governor Droop Compensator |
| `H_RSC_GOV_FF` | — | 0.00 | % | Governor Feedforward |
| `H_RSC_GOV_RANGE` | — | 0.00 | RPM | Governor Operational Range |
| `H_RSC_GOV_RPM` | — | 0.00 | RPM | Rotor RPM Setting |
| `H_RSC_GOV_TORQUE` | — | 0.00 | % | Governor Torque Limiter |
| `H_RSC_IDLE` | — | 0.00 | % | Throttle Output at Idle |
| `H_RSC_MODE` | — | 0.00 | — | Rotor Speed Control Mode |
| `H_RSC_RAMP_TIME` | — | 0.00 | s | Throttle Ramp Time |
| `H_RSC_RUNUP_TIME` | — | 0.00 | s | Rotor Runup Time |
| `H_RSC_SETPOINT` | — | 0.00 | % | External Motor Governor Setpoint |
| `H_RSC_SLEWRATE` | — | 0.00 | — | Throttle Slew Rate |
| `H_RSC_THRCRV_0` | — | 0.00 | % | Throttle Curve at 0% Coll |
| `H_RSC_THRCRV_100` | — | 0.00 | % | Throttle Curve at 100% Coll |
| `H_RSC_THRCRV_25` | — | 0.00 | % | Throttle Curve at 25% Coll |
| `H_RSC_THRCRV_50` | — | 0.00 | % | Throttle Curve at 50% Coll |
| `H_RSC_THRCRV_75` | — | 0.00 | % | Throttle Curve at 75% Coll |
| `H_SV_MAN` | — | 0.00 | — | Manual Servo Mode |
| `H_SV_TEST` | — | 0.00 | — | Boot-up Servo Test Cycles |
| `H_SW2_COL_DIR` | — | 0.00 | — | Swash 2 Collective Direction |
| `H_SW2_H3_ENABLE` | — | 0.00 | — | Swash 2 H3 Generic Enable |
| `H_SW2_H3_PHANG` | — | 0.00 | deg | Swash 2 H3 Generic Phase Angle Comp |
| `H_SW2_H3_SV1_POS` | — | 0.00 | deg | Swash 2 H3 Generic Servo 1 Position |
| `H_SW2_H3_SV2_POS` | — | 0.00 | deg | Swash 2 H3 Generic Servo 2 Position |
| `H_SW2_H3_SV3_POS` | — | 0.00 | deg | Swash 2 H3 Generic Servo 3 Position |
| `H_SW2_LIN_SVO` | — | 0.00 | — | Linearize Swash 2 Servos |
| `H_SW2_TYPE` | — | 0.00 | — | Swash 2 Type |
| `H_SW_COL_DIR` | — | 0.00 | — | Swash 1 Collective Direction |
| `H_SW_H3_ENABLE` | — | 0.00 | — | Swash 1 H3 Generic Enable |
| `H_SW_H3_PHANG` | — | 0.00 | deg | Swash 1 H3 Generic Phase Angle Comp |
| `H_SW_H3_SV1_POS` | — | 0.00 | deg | Swash 1 H3 Generic Servo 1 Position |
| `H_SW_H3_SV2_POS` | — | 0.00 | deg | Swash 1 H3 Generic Servo 2 Position |
| `H_SW_H3_SV3_POS` | — | 0.00 | deg | Swash 1 H3 Generic Servo 3 Position |
| `H_SW_LIN_SVO` | — | 0.00 | — | Linearize Swash 1 Servos |
| `H_SW_TYPE` | — | 0.00 | — | Swash 1 Type |
| `H_TAIL_SPEED` | — | 0.00 | % | DDVP Tail ESC speed |
| `H_TAIL_TYPE` | — | 0.00 | — | Tail Type |
| `H_YAW_REV_EXPO` | — | 0.00 | — | Yaw reverser expo |
| `H_YAW_SCALER` | — | 0.00 | — | Scaler for yaw mixing |
| `H_YAW_TRIM` | `TRIM_YAW` | 0.67 | — | Tail Rotor Trim |
| `IM_ACRO_COL_EXP` | — | 0.00 | — | Acro Mode Collective Expo |
| `IM_STB_COL_1` | — | 0.00 | % | Stabilize Collective Low |
| `IM_STB_COL_2` | — | 0.00 | % | Stabilize Collective Mid-Low |
| `IM_STB_COL_3` | — | 0.00 | % | Stabilize Collective Mid-High |
| `IM_STB_COL_4` | — | 0.00 | % | Stabilize Collective High |
| `INITIAL_MODE` | — | 0.00 | — | Initial flight mode |
| `INS4_ACCOFFS_X` | — | 0.00 | m/s/s | Accelerometer offsets of X axis |
| `INS4_ACCOFFS_Y` | — | 0.00 | m/s/s | Accelerometer offsets of Y axis |
| `INS4_ACCOFFS_Z` | — | 0.00 | m/s/s | Accelerometer offsets of Z axis |
| `INS4_ACCSCAL_X` | — | 0.00 | — | Accelerometer scaling of X axis |
| `INS4_ACCSCAL_Y` | — | 0.00 | — | Accelerometer scaling of Y axis |
| `INS4_ACCSCAL_Z` | — | 0.00 | — | Accelerometer scaling of Z axis |
| `INS4_ACC_CALTEMP` | — | 0.00 | degC | Calibration temperature for accelerometer |
| `INS4_ACC_ID` | — | 0.00 | — | Accelerometer ID |
| `INS4_GYROFFS_X` | — | 0.00 | rad/s | Gyro offsets of X axis |
| `INS4_GYROFFS_Y` | — | 0.00 | rad/s | Gyro offsets of Y axis |
| `INS4_GYROFFS_Z` | — | 0.00 | rad/s | Gyro offsets of Z axis |
| `INS4_GYR_CALTEMP` | — | 0.00 | degC | Calibration temperature for gyroscope |
| `INS4_GYR_ID` | — | 0.00 | — | Gyro ID |
| `INS4_POS_X` | — | 0.00 | m | IMU accelerometer X position |
| `INS4_POS_Y` | — | 0.00 | m | IMU accelerometer Y position |
| `INS4_POS_Z` | — | 0.00 | m | IMU accelerometer Z position |
| `INS4_TCAL_ACC1_X` | — | 0.00 | — | Accelerometer 1st order temperature coefficient X axis |
| `INS4_TCAL_ACC1_Y` | — | 0.00 | — | Accelerometer 1st order temperature coefficient Y axis |
| `INS4_TCAL_ACC1_Z` | — | 0.00 | — | Accelerometer 1st order temperature coefficient Z axis |
| `INS4_TCAL_ACC2_X` | — | 0.00 | — | Accelerometer 2nd order temperature coefficient X axis |
| `INS4_TCAL_ACC2_Y` | — | 0.00 | — | Accelerometer 2nd order temperature coefficient Y axis |
| `INS4_TCAL_ACC2_Z` | — | 0.00 | — | Accelerometer 2nd order temperature coefficient Z axis |
| `INS4_TCAL_ACC3_X` | — | 0.00 | — | Accelerometer 3rd order temperature coefficient X axis |
| `INS4_TCAL_ACC3_Y` | — | 0.00 | — | Accelerometer 3rd order temperature coefficient Y axis |
| `INS4_TCAL_ACC3_Z` | — | 0.00 | — | Accelerometer 3rd order temperature coefficient Z axis |
| `INS4_TCAL_ENABLE` | — | 0.00 | — | Enable temperature calibration |
| `INS4_TCAL_GYR1_X` | — | 0.00 | — | Gyroscope 1st order temperature coefficient X axis |
| `INS4_TCAL_GYR1_Y` | — | 0.00 | — | Gyroscope 1st order temperature coefficient Y axis |
| `INS4_TCAL_GYR1_Z` | — | 0.00 | — | Gyroscope 1st order temperature coefficient Z axis |
| `INS4_TCAL_GYR2_X` | — | 0.00 | — | Gyroscope 2nd order temperature coefficient X axis |
| `INS4_TCAL_GYR2_Y` | — | 0.00 | — | Gyroscope 2nd order temperature coefficient Y axis |
| `INS4_TCAL_GYR2_Z` | — | 0.00 | — | Gyroscope 2nd order temperature coefficient Z axis |
| `INS4_TCAL_GYR3_X` | — | 0.00 | — | Gyroscope 3rd order temperature coefficient X axis |
| `INS4_TCAL_GYR3_Y` | — | 0.00 | — | Gyroscope 3rd order temperature coefficient Y axis |
| `INS4_TCAL_GYR3_Z` | — | 0.00 | — | Gyroscope 3rd order temperature coefficient Z axis |
| `INS4_TCAL_TMAX` | — | 0.00 | degC | Temperature calibration max |
| `INS4_TCAL_TMIN` | — | 0.00 | degC | Temperature calibration min |
| `INS4_USE` | — | 0.00 | — | Use first IMU for attitude, velocity and position estimates |
| `INS5_ACCOFFS_X` | — | 0.00 | m/s/s | Accelerometer offsets of X axis |
| `INS5_ACCOFFS_Y` | — | 0.00 | m/s/s | Accelerometer offsets of Y axis |
| `INS5_ACCOFFS_Z` | — | 0.00 | m/s/s | Accelerometer offsets of Z axis |
| `INS5_ACCSCAL_X` | — | 0.00 | — | Accelerometer scaling of X axis |
| `INS5_ACCSCAL_Y` | — | 0.00 | — | Accelerometer scaling of Y axis |
| `INS5_ACCSCAL_Z` | — | 0.00 | — | Accelerometer scaling of Z axis |
| `INS5_ACC_CALTEMP` | — | 0.00 | degC | Calibration temperature for accelerometer |
| `INS5_ACC_ID` | — | 0.00 | — | Accelerometer ID |
| `INS5_GYROFFS_X` | — | 0.00 | rad/s | Gyro offsets of X axis |
| `INS5_GYROFFS_Y` | — | 0.00 | rad/s | Gyro offsets of Y axis |
| `INS5_GYROFFS_Z` | — | 0.00 | rad/s | Gyro offsets of Z axis |
| `INS5_GYR_CALTEMP` | — | 0.00 | degC | Calibration temperature for gyroscope |
| `INS5_GYR_ID` | — | 0.00 | — | Gyro ID |
| `INS5_POS_X` | — | 0.00 | m | IMU accelerometer X position |
| `INS5_POS_Y` | — | 0.00 | m | IMU accelerometer Y position |
| `INS5_POS_Z` | — | 0.00 | m | IMU accelerometer Z position |
| `INS5_TCAL_ACC1_X` | — | 0.00 | — | Accelerometer 1st order temperature coefficient X axis |
| `INS5_TCAL_ACC1_Y` | — | 0.00 | — | Accelerometer 1st order temperature coefficient Y axis |
| `INS5_TCAL_ACC1_Z` | — | 0.00 | — | Accelerometer 1st order temperature coefficient Z axis |
| `INS5_TCAL_ACC2_X` | — | 0.00 | — | Accelerometer 2nd order temperature coefficient X axis |
| `INS5_TCAL_ACC2_Y` | — | 0.00 | — | Accelerometer 2nd order temperature coefficient Y axis |
| `INS5_TCAL_ACC2_Z` | — | 0.00 | — | Accelerometer 2nd order temperature coefficient Z axis |
| `INS5_TCAL_ACC3_X` | — | 0.00 | — | Accelerometer 3rd order temperature coefficient X axis |
| `INS5_TCAL_ACC3_Y` | — | 0.00 | — | Accelerometer 3rd order temperature coefficient Y axis |
| `INS5_TCAL_ACC3_Z` | — | 0.00 | — | Accelerometer 3rd order temperature coefficient Z axis |
| `INS5_TCAL_ENABLE` | — | 0.00 | — | Enable temperature calibration |
| `INS5_TCAL_GYR1_X` | — | 0.00 | — | Gyroscope 1st order temperature coefficient X axis |
| `INS5_TCAL_GYR1_Y` | — | 0.00 | — | Gyroscope 1st order temperature coefficient Y axis |
| `INS5_TCAL_GYR1_Z` | — | 0.00 | — | Gyroscope 1st order temperature coefficient Z axis |
| `INS5_TCAL_GYR2_X` | — | 0.00 | — | Gyroscope 2nd order temperature coefficient X axis |
| `INS5_TCAL_GYR2_Y` | — | 0.00 | — | Gyroscope 2nd order temperature coefficient Y axis |
| `INS5_TCAL_GYR2_Z` | — | 0.00 | — | Gyroscope 2nd order temperature coefficient Z axis |
| `INS5_TCAL_GYR3_X` | — | 0.00 | — | Gyroscope 3rd order temperature coefficient X axis |
| `INS5_TCAL_GYR3_Y` | — | 0.00 | — | Gyroscope 3rd order temperature coefficient Y axis |
| `INS5_TCAL_GYR3_Z` | — | 0.00 | — | Gyroscope 3rd order temperature coefficient Z axis |
| `INS5_TCAL_TMAX` | — | 0.00 | degC | Temperature calibration max |
| `INS5_TCAL_TMIN` | — | 0.00 | degC | Temperature calibration min |
| `INS5_USE` | — | 0.00 | — | Use first IMU for attitude, velocity and position estimates |
| `INS_ACC1_CALTEMP` | — | 0.00 | degC | Calibration temperature for 1st accelerometer |
| `INS_ACC2OFFS_X` | — | 0.00 | m/s/s | Accelerometer2 offsets of X axis |
| `INS_ACC2OFFS_Y` | — | 0.00 | m/s/s | Accelerometer2 offsets of Y axis |
| `INS_ACC2OFFS_Z` | — | 0.00 | m/s/s | Accelerometer2 offsets of Z axis |
| `INS_ACC2SCAL_X` | — | 0.00 | — | Accelerometer2 scaling of X axis |
| `INS_ACC2SCAL_Y` | — | 0.00 | — | Accelerometer2 scaling of Y axis |
| `INS_ACC2SCAL_Z` | — | 0.00 | — | Accelerometer2 scaling of Z axis |
| `INS_ACC2_CALTEMP` | — | 0.00 | degC | Calibration temperature for 2nd accelerometer |
| `INS_ACC2_ID` | — | 0.00 | — | Accelerometer2 ID |
| `INS_ACC3OFFS_X` | — | 0.00 | m/s/s | Accelerometer3 offsets of X axis |
| `INS_ACC3OFFS_Y` | — | 0.00 | m/s/s | Accelerometer3 offsets of Y axis |
| `INS_ACC3OFFS_Z` | — | 0.00 | m/s/s | Accelerometer3 offsets of Z axis |
| `INS_ACC3SCAL_X` | — | 0.00 | — | Accelerometer3 scaling of X axis |
| `INS_ACC3SCAL_Y` | — | 0.00 | — | Accelerometer3 scaling of Y axis |
| `INS_ACC3SCAL_Z` | — | 0.00 | — | Accelerometer3 scaling of Z axis |
| `INS_ACC3_CALTEMP` | — | 0.00 | degC | Calibration temperature for 3rd accelerometer |
| `INS_ACC3_ID` | — | 0.00 | — | Accelerometer3 ID |
| `INS_ACCEL_FILTER` | — | 0.00 | Hz | Accel filter cutoff frequency |
| `INS_ACCOFFS_X` | — | 0.00 | m/s/s | Accelerometer offsets of X axis |
| `INS_ACCOFFS_Y` | — | 0.00 | m/s/s | Accelerometer offsets of Y axis |
| `INS_ACCOFFS_Z` | — | 0.00 | m/s/s | Accelerometer offsets of Z axis |
| `INS_ACCSCAL_X` | — | 0.00 | — | Accelerometer scaling of X axis |
| `INS_ACCSCAL_Y` | — | 0.00 | — | Accelerometer scaling of Y axis |
| `INS_ACCSCAL_Z` | — | 0.00 | — | Accelerometer scaling of Z axis |
| `INS_ACC_BODYFIX` | — | 0.00 | — | Body-fixed accelerometer |
| `INS_ACC_ID` | — | 0.00 | — | Accelerometer ID |
| `INS_ENABLE_MASK` | — | 0.00 | — | IMU enable mask |
| `INS_FAST_SAMPLE` | — | 0.00 | — | Fast sampling mask |
| `INS_GYR1_CALTEMP` | — | 0.00 | degC | Calibration temperature for 1st gyroscope |
| `INS_GYR2OFFS_X` | — | 0.00 | rad/s | Gyro2 offsets of X axis |
| `INS_GYR2OFFS_Y` | — | 0.00 | rad/s | Gyro2 offsets of Y axis |
| `INS_GYR2OFFS_Z` | — | 0.00 | rad/s | Gyro2 offsets of Z axis |
| `INS_GYR2_CALTEMP` | — | 0.00 | degC | Calibration temperature for 2nd gyroscope |
| `INS_GYR2_ID` | — | 0.00 | — | Gyro2 ID |
| `INS_GYR3OFFS_X` | — | 0.00 | rad/s | Gyro3 offsets of X axis |
| `INS_GYR3OFFS_Y` | — | 0.00 | rad/s | Gyro3 offsets of Y axis |
| `INS_GYR3OFFS_Z` | — | 0.00 | rad/s | Gyro3 offsets of Z axis |
| `INS_GYR3_CALTEMP` | — | 0.00 | degC | Calibration temperature for 3rd gyroscope |
| `INS_GYR3_ID` | — | 0.00 | — | Gyro3 ID |
| `INS_GYROFFS_X` | — | 0.00 | rad/s | Gyro offsets of X axis |
| `INS_GYROFFS_Y` | — | 0.00 | rad/s | Gyro offsets of Y axis |
| `INS_GYROFFS_Z` | — | 0.00 | rad/s | Gyro offsets of Z axis |
| `INS_GYRO_FILTER` | — | 0.00 | Hz | Gyro filter cutoff frequency |
| `INS_GYRO_RATE` | — | 0.00 | — | Gyro rate for IMUs with Fast Sampling enabled |
| `INS_GYR_CAL` | — | 0.00 | — | Gyro Calibration scheme |
| `INS_GYR_ID` | — | 0.00 | — | Gyro ID |
| `INS_HNTC2_ATT` | `ATT_EN` | 0.33 | dB | Harmonic Notch Filter attenuation |
| `INS_HNTC2_BW` | — | 0.00 | Hz | Harmonic Notch Filter bandwidth |
| `INS_HNTC2_ENABLE` | — | 0.00 | — | Harmonic Notch Filter enable |
| `INS_HNTC2_FM_RAT` | — | 0.00 | — | Throttle notch min freqency ratio |
| `INS_HNTC2_FREQ` | — | 0.00 | Hz | Harmonic Notch Filter base frequency |
| `INS_HNTC2_HMNCS` | — | 0.00 | — | Harmonic Notch Filter harmonics |
| `INS_HNTC2_MODE` | — | 0.00 | — | Harmonic Notch Filter dynamic frequency tracking mode |
| `INS_HNTC2_OPTS` | — | 0.00 | — | Harmonic Notch Filter options |
| `INS_HNTC2_REF` | — | 0.00 | — | Harmonic Notch Filter reference value |
| `INS_HNTCH_ATT` | `ATT_EN` | 0.33 | dB | Harmonic Notch Filter attenuation |
| `INS_HNTCH_BW` | — | 0.00 | Hz | Harmonic Notch Filter bandwidth |
| `INS_HNTCH_ENABLE` | — | 0.00 | — | Harmonic Notch Filter enable |
| `INS_HNTCH_FM_RAT` | — | 0.00 | — | Throttle notch min freqency ratio |
| `INS_HNTCH_FREQ` | — | 0.00 | Hz | Harmonic Notch Filter base frequency |
| `INS_HNTCH_HMNCS` | — | 0.00 | — | Harmonic Notch Filter harmonics |
| `INS_HNTCH_MODE` | — | 0.00 | — | Harmonic Notch Filter dynamic frequency tracking mode |
| `INS_HNTCH_OPTS` | — | 0.00 | — | Harmonic Notch Filter options |
| `INS_HNTCH_REF` | — | 0.00 | — | Harmonic Notch Filter reference value |
| `INS_LOG_BAT_CNT` | — | 0.00 | — | sample count per batch |
| `INS_LOG_BAT_LGCT` | — | 0.00 | — | logging count |
| `INS_LOG_BAT_LGIN` | — | 0.00 | ms | logging interval |
| `INS_LOG_BAT_MASK` | — | 0.00 | — | Sensor Bitmask |
| `INS_LOG_BAT_OPT` | — | 0.00 | — | Batch Logging Options Mask |
| `INS_POS1_X` | — | 0.00 | m | IMU accelerometer X position |
| `INS_POS1_Y` | — | 0.00 | m | IMU accelerometer Y position |
| `INS_POS1_Z` | — | 0.00 | m | IMU accelerometer Z position |
| `INS_POS2_X` | — | 0.00 | m | IMU accelerometer X position |
| `INS_POS2_Y` | — | 0.00 | m | IMU accelerometer Y position |
| `INS_POS2_Z` | — | 0.00 | m | IMU accelerometer Z position |
| `INS_POS3_X` | — | 0.00 | m | IMU accelerometer X position |
| `INS_POS3_Y` | — | 0.00 | m | IMU accelerometer Y position |
| `INS_POS3_Z` | — | 0.00 | m | IMU accelerometer Z position |
| `INS_RAW_LOG_OPT` | — | 0.00 | — | Raw logging options |
| `INS_STILL_THRESH` | — | 0.00 | — | Stillness threshold for detecting if we are moving |
| `INS_TCAL1_ACC1_X` | — | 0.00 | — | Accelerometer 1st order temperature coefficient X axis |
| `INS_TCAL1_ACC1_Y` | — | 0.00 | — | Accelerometer 1st order temperature coefficient Y axis |
| `INS_TCAL1_ACC1_Z` | — | 0.00 | — | Accelerometer 1st order temperature coefficient Z axis |
| `INS_TCAL1_ACC2_X` | — | 0.00 | — | Accelerometer 2nd order temperature coefficient X axis |
| `INS_TCAL1_ACC2_Y` | — | 0.00 | — | Accelerometer 2nd order temperature coefficient Y axis |
| `INS_TCAL1_ACC2_Z` | — | 0.00 | — | Accelerometer 2nd order temperature coefficient Z axis |
| `INS_TCAL1_ACC3_X` | — | 0.00 | — | Accelerometer 3rd order temperature coefficient X axis |
| `INS_TCAL1_ACC3_Y` | — | 0.00 | — | Accelerometer 3rd order temperature coefficient Y axis |
| `INS_TCAL1_ACC3_Z` | — | 0.00 | — | Accelerometer 3rd order temperature coefficient Z axis |
| `INS_TCAL1_ENABLE` | — | 0.00 | — | Enable temperature calibration |
| `INS_TCAL1_GYR1_X` | — | 0.00 | — | Gyroscope 1st order temperature coefficient X axis |
| `INS_TCAL1_GYR1_Y` | — | 0.00 | — | Gyroscope 1st order temperature coefficient Y axis |
| `INS_TCAL1_GYR1_Z` | — | 0.00 | — | Gyroscope 1st order temperature coefficient Z axis |
| `INS_TCAL1_GYR2_X` | — | 0.00 | — | Gyroscope 2nd order temperature coefficient X axis |
| `INS_TCAL1_GYR2_Y` | — | 0.00 | — | Gyroscope 2nd order temperature coefficient Y axis |
| `INS_TCAL1_GYR2_Z` | — | 0.00 | — | Gyroscope 2nd order temperature coefficient Z axis |
| `INS_TCAL1_GYR3_X` | — | 0.00 | — | Gyroscope 3rd order temperature coefficient X axis |
| `INS_TCAL1_GYR3_Y` | — | 0.00 | — | Gyroscope 3rd order temperature coefficient Y axis |
| `INS_TCAL1_GYR3_Z` | — | 0.00 | — | Gyroscope 3rd order temperature coefficient Z axis |
| `INS_TCAL1_TMAX` | — | 0.00 | degC | Temperature calibration max |
| `INS_TCAL1_TMIN` | — | 0.00 | degC | Temperature calibration min |
| `INS_TCAL2_ACC1_X` | — | 0.00 | — | Accelerometer 1st order temperature coefficient X axis |
| `INS_TCAL2_ACC1_Y` | — | 0.00 | — | Accelerometer 1st order temperature coefficient Y axis |
| `INS_TCAL2_ACC1_Z` | — | 0.00 | — | Accelerometer 1st order temperature coefficient Z axis |
| `INS_TCAL2_ACC2_X` | — | 0.00 | — | Accelerometer 2nd order temperature coefficient X axis |
| `INS_TCAL2_ACC2_Y` | — | 0.00 | — | Accelerometer 2nd order temperature coefficient Y axis |
| `INS_TCAL2_ACC2_Z` | — | 0.00 | — | Accelerometer 2nd order temperature coefficient Z axis |
| `INS_TCAL2_ACC3_X` | — | 0.00 | — | Accelerometer 3rd order temperature coefficient X axis |
| `INS_TCAL2_ACC3_Y` | — | 0.00 | — | Accelerometer 3rd order temperature coefficient Y axis |
| `INS_TCAL2_ACC3_Z` | — | 0.00 | — | Accelerometer 3rd order temperature coefficient Z axis |
| `INS_TCAL2_ENABLE` | — | 0.00 | — | Enable temperature calibration |
| `INS_TCAL2_GYR1_X` | — | 0.00 | — | Gyroscope 1st order temperature coefficient X axis |
| `INS_TCAL2_GYR1_Y` | — | 0.00 | — | Gyroscope 1st order temperature coefficient Y axis |
| `INS_TCAL2_GYR1_Z` | — | 0.00 | — | Gyroscope 1st order temperature coefficient Z axis |
| `INS_TCAL2_GYR2_X` | — | 0.00 | — | Gyroscope 2nd order temperature coefficient X axis |
| `INS_TCAL2_GYR2_Y` | — | 0.00 | — | Gyroscope 2nd order temperature coefficient Y axis |
| `INS_TCAL2_GYR2_Z` | — | 0.00 | — | Gyroscope 2nd order temperature coefficient Z axis |
| `INS_TCAL2_GYR3_X` | — | 0.00 | — | Gyroscope 3rd order temperature coefficient X axis |
| `INS_TCAL2_GYR3_Y` | — | 0.00 | — | Gyroscope 3rd order temperature coefficient Y axis |
| `INS_TCAL2_GYR3_Z` | — | 0.00 | — | Gyroscope 3rd order temperature coefficient Z axis |
| `INS_TCAL2_TMAX` | — | 0.00 | degC | Temperature calibration max |
| `INS_TCAL2_TMIN` | — | 0.00 | degC | Temperature calibration min |
| `INS_TCAL3_ACC1_X` | — | 0.00 | — | Accelerometer 1st order temperature coefficient X axis |
| `INS_TCAL3_ACC1_Y` | — | 0.00 | — | Accelerometer 1st order temperature coefficient Y axis |
| `INS_TCAL3_ACC1_Z` | — | 0.00 | — | Accelerometer 1st order temperature coefficient Z axis |
| `INS_TCAL3_ACC2_X` | — | 0.00 | — | Accelerometer 2nd order temperature coefficient X axis |
| `INS_TCAL3_ACC2_Y` | — | 0.00 | — | Accelerometer 2nd order temperature coefficient Y axis |
| `INS_TCAL3_ACC2_Z` | — | 0.00 | — | Accelerometer 2nd order temperature coefficient Z axis |
| `INS_TCAL3_ACC3_X` | — | 0.00 | — | Accelerometer 3rd order temperature coefficient X axis |
| `INS_TCAL3_ACC3_Y` | — | 0.00 | — | Accelerometer 3rd order temperature coefficient Y axis |
| `INS_TCAL3_ACC3_Z` | — | 0.00 | — | Accelerometer 3rd order temperature coefficient Z axis |
| `INS_TCAL3_ENABLE` | — | 0.00 | — | Enable temperature calibration |
| `INS_TCAL3_GYR1_X` | — | 0.00 | — | Gyroscope 1st order temperature coefficient X axis |
| `INS_TCAL3_GYR1_Y` | — | 0.00 | — | Gyroscope 1st order temperature coefficient Y axis |
| `INS_TCAL3_GYR1_Z` | — | 0.00 | — | Gyroscope 1st order temperature coefficient Z axis |
| `INS_TCAL3_GYR2_X` | — | 0.00 | — | Gyroscope 2nd order temperature coefficient X axis |
| `INS_TCAL3_GYR2_Y` | — | 0.00 | — | Gyroscope 2nd order temperature coefficient Y axis |
| `INS_TCAL3_GYR2_Z` | — | 0.00 | — | Gyroscope 2nd order temperature coefficient Z axis |
| `INS_TCAL3_GYR3_X` | — | 0.00 | — | Gyroscope 3rd order temperature coefficient X axis |
| `INS_TCAL3_GYR3_Y` | — | 0.00 | — | Gyroscope 3rd order temperature coefficient Y axis |
| `INS_TCAL3_GYR3_Z` | — | 0.00 | — | Gyroscope 3rd order temperature coefficient Z axis |
| `INS_TCAL3_TMAX` | — | 0.00 | degC | Temperature calibration max |
| `INS_TCAL3_TMIN` | — | 0.00 | degC | Temperature calibration min |
| `INS_TCAL_OPTIONS` | — | 0.00 | — | Options for temperature calibration |
| `INS_TRIM_OPTION` | `TRIM_YAW` | 0.33 | — | Accel cal trim option |
| `INS_USE` | — | 0.00 | — | Use first IMU for attitude, velocity and position estimates |
| `INS_USE2` | — | 0.00 | — | Use second IMU for attitude, velocity and position estimates |
| `INS_USE3` | — | 0.00 | — | Use third IMU for attitude, velocity and position estimates |
| `KDE_NPOLE` | — | 0.00 | — | Number of motor poles |
| `LAND_ALT_LOW` | — | 0.00 | cm | Land alt low |
| `LAND_REPOSITION` | — | 0.00 | — | Land repositioning |
| `LAND_SPEED` | — | 0.00 | cm/s | Land speed |
| `LAND_SPEED_HIGH` | — | 0.00 | cm/s | Land speed high |
| `LGR_DEPLOY_ALT` | — | 0.00 | m | Landing gear deployment altitude |
| `LGR_DEPLOY_PIN` | — | 0.00 | — | Chassis deployment feedback pin |
| `LGR_DEPLOY_POL` | — | 0.00 | — | Chassis deployment feedback pin polarity |
| `LGR_ENABLE` | — | 0.00 | — | Enable landing gear |
| `LGR_OPTIONS` | — | 0.00 | — | Landing gear auto retract/deploy options |
| `LGR_RETRACT_ALT` | — | 0.00 | m | Landing gear retract altitude |
| `LGR_STARTUP` | — | 0.00 | — | Landing Gear Startup position |
| `LGR_WOW_PIN` | — | 0.00 | — | Weight on wheels feedback pin |
| `LGR_WOW_POL` | — | 0.00 | — | Weight on wheels feedback pin polarity |
| `LOG_BACKEND_TYPE` | — | 0.00 | — | AP_Logger Backend Storage type |
| `LOG_BITMASK` | — | 0.00 | — | Log bitmask |
| `LOG_BLK_RATEMAX` | — | 0.00 | Hz | Maximum logging rate for block backend |
| `LOG_DARM_RATEMAX` | — | 0.00 | Hz | Maximum logging rate when disarmed |
| `LOG_DISARMED` | — | 0.00 | — | Enable logging while disarmed |
| `LOG_FILE_BUFSIZE` | — | 0.00 | kB | Logging File and Block Backend buffer size max (in kilobytes) |
| `LOG_FILE_DSRMROT` | — | 0.00 | — | Stop logging to current file on disarm |
| `LOG_FILE_MB_FREE` | — | 0.00 | MB | Old logs on the SD card will be deleted to maintain this amount of free space |
| `LOG_FILE_RATEMAX` | — | 0.00 | Hz | Maximum logging rate for file backend |
| `LOG_FILE_TIMEOUT` | — | 0.00 | s | Timeout before giving up on file writes |
| `LOG_MAV_BUFSIZE` | `MAV_TYPE` | 0.33 | kB | Maximum AP_Logger MAVLink Backend buffer size |
| `LOG_MAV_RATEMAX` | `MAV_TYPE` | 0.33 | Hz | Maximum logging rate for mavlink backend |
| `LOG_MAX_FILES` | — | 0.00 | — | Maximum number of log files |
| `LOG_REPLAY` | — | 0.00 | — | Enable logging of information needed for Replay |
| `LOIT_ACC_MAX` | — | 0.00 | cm/s/s | Loiter maximum correction acceleration |
| `LOIT_ANG_MAX` | — | 0.00 | deg | Loiter pilot angle max |
| `LOIT_BRK_ACCEL` | — | 0.00 | cm/s/s | Loiter braking acceleration |
| `LOIT_BRK_DELAY` | — | 0.00 | s | Loiter brake start delay (in seconds) |
| `LOIT_BRK_JERK` | — | 0.00 | cm/s/s/s | Loiter braking jerk |
| `LOIT_SPEED` | — | 0.00 | cm/s | Loiter Horizontal Maximum Speed |
| `MIS_OPTIONS` | `MIS_YAW_ERR` | 0.37 | — | Mission options bitmask |
| `MIS_RESTART` | `MIS_YAW_ERR` | 0.37 | — | Mission Restart when entering Auto mode |
| `MIS_TOTAL` | `MIS_YAW_ERR` | 0.37 | — | Total mission commands |
| `MNT1_DEFLT_MODE` | `MNT_MODE_OUT` | 0.50 | — | Mount default operating mode |
| `MNT1_DEVID` | `MNT_TAU` | 0.33 | — | Mount Device ID |
| `MNT1_LEAD_PTCH` | — | 0.00 | s | Mount Pitch stabilization lead time |
| `MNT1_LEAD_RLL` | — | 0.00 | s | Mount Roll stabilization lead time |
| `MNT1_NEUTRAL_X` | — | 0.00 | deg | Mount roll angle when in neutral position |
| `MNT1_NEUTRAL_Y` | — | 0.00 | deg | Mount pitch angle when in neutral position |
| `MNT1_NEUTRAL_Z` | — | 0.00 | deg | Mount yaw angle when in neutral position |
| `MNT1_OPTIONS` | `MNT_TAU` | 0.33 | — | Mount options |
| `MNT1_PITCH_MAX` | `MNT_MAX_PITCH` | 1.00 | deg | Mount Pitch angle maximum |
| `MNT1_PITCH_MIN` | `MNT_MIN_PITCH` | 1.00 | deg | Mount Pitch angle minimum |
| `MNT1_RC_RATE` | `MNT_RATE_YAW` | 0.50 | deg/s | Mount RC Rate |
| `MNT1_RETRACT_X` | — | 0.00 | deg | Mount roll angle when in retracted position |
| `MNT1_RETRACT_Y` | — | 0.00 | deg | Mount pitch angle when in retracted position |
| `MNT1_RETRACT_Z` | — | 0.00 | deg | Mount yaw angle when in retracted position |
| `MNT1_ROLL_MAX` | `MNT_RANGE_ROLL` | 0.50 | deg | Mount Roll angle maximum |
| `MNT1_ROLL_MIN` | `MNT_RANGE_ROLL` | 0.50 | deg | Mount Roll angle minimum |
| `MNT1_SYSID_DFLT` | `MNT_MAV_SYSID` | 0.50 | — | Mount Target sysID |
| `MNT1_TYPE` | `MNT_TAU` | 0.50 | — | Mount Type |
| `MNT1_YAW_MAX` | `MNT_MAN_YAW` | 0.50 | deg | Mount Yaw angle maximum |
| `MNT1_YAW_MIN` | `MNT_MAN_YAW` | 0.50 | deg | Mount Yaw angle minimum |
| `MNT2_DEFLT_MODE` | `MNT_MODE_OUT` | 0.50 | — | Mount default operating mode |
| `MNT2_DEVID` | `MNT_TAU` | 0.33 | — | Mount Device ID |
| `MNT2_LEAD_PTCH` | — | 0.00 | s | Mount Pitch stabilization lead time |
| `MNT2_LEAD_RLL` | — | 0.00 | s | Mount Roll stabilization lead time |
| `MNT2_NEUTRAL_X` | — | 0.00 | deg | Mount roll angle when in neutral position |
| `MNT2_NEUTRAL_Y` | — | 0.00 | deg | Mount pitch angle when in neutral position |
| `MNT2_NEUTRAL_Z` | — | 0.00 | deg | Mount yaw angle when in neutral position |
| `MNT2_OPTIONS` | `MNT_TAU` | 0.33 | — | Mount options |
| `MNT2_PITCH_MAX` | `MNT_MAX_PITCH` | 1.00 | deg | Mount Pitch angle maximum |
| `MNT2_PITCH_MIN` | `MNT_MIN_PITCH` | 1.00 | deg | Mount Pitch angle minimum |
| `MNT2_RC_RATE` | `MNT_RATE_YAW` | 0.50 | deg/s | Mount RC Rate |
| `MNT2_RETRACT_X` | — | 0.00 | deg | Mount roll angle when in retracted position |
| `MNT2_RETRACT_Y` | — | 0.00 | deg | Mount pitch angle when in retracted position |
| `MNT2_RETRACT_Z` | — | 0.00 | deg | Mount yaw angle when in retracted position |
| `MNT2_ROLL_MAX` | `MNT_RANGE_ROLL` | 0.50 | deg | Mount Roll angle maximum |
| `MNT2_ROLL_MIN` | `MNT_RANGE_ROLL` | 0.50 | deg | Mount Roll angle minimum |
| `MNT2_SYSID_DFLT` | `MNT_MAV_SYSID` | 0.50 | — | Mount Target sysID |
| `MNT2_TYPE` | `MNT_TAU` | 0.50 | — | Mount Type |
| `MNT2_YAW_MAX` | `MNT_MAN_YAW` | 0.50 | deg | Mount Yaw angle maximum |
| `MNT2_YAW_MIN` | `MNT_MAN_YAW` | 0.50 | deg | Mount Yaw angle minimum |
| `MOT_BAT_CURR_MAX` | `BAT_AVRG_CURRENT` | 0.40 | A | Motor Current Max |
| `MOT_BAT_CURR_TC` | `BAT_AVRG_CURRENT` | 0.40 | s | Motor Current Max Time Constant |
| `MOT_BAT_IDX` | — | 0.00 | — | Battery compensation index |
| `MOT_BAT_VOLT_MAX` | — | 0.00 | V | Battery voltage compensation maximum voltage |
| `MOT_BAT_VOLT_MIN` | — | 0.00 | V | Battery voltage compensation minimum voltage |
| `MOT_BOOST_SCALE` | — | 0.00 | — | Motor boost scale |
| `MOT_HOVER_LEARN` | — | 0.00 | — | Hover Value Learning |
| `MOT_OPTIONS` | — | 0.00 | — | Motor options |
| `MOT_PWM_MAX` | `PWM_AUX_MAX9` | 0.50 | PWM | PWM output maximum |
| `MOT_PWM_MIN` | `PWM_AUX_MIN6` | 0.50 | PWM | PWM output minimum |
| `MOT_PWM_TYPE` | — | 0.00 | — | Output PWM type |
| `MOT_SAFE_DISARM` | — | 0.00 | — | Motor PWM output disabled when disarmed |
| `MOT_SAFE_TIME` | — | 0.00 | s | Time taken to disable and enable the motor PWM output when disarmed and armed. |
| `MOT_SLEW_DN_TIME` | — | 0.00 | s | Output slew time for decreasing throttle |
| `MOT_SLEW_UP_TIME` | — | 0.00 | s | Output slew time for increasing throttle |
| `MOT_SPIN_ARM` | — | 0.00 | — | Motor Spin armed |
| `MOT_SPIN_MAX` | — | 0.00 | — | Motor Spin maximum |
| `MOT_SPIN_MIN` | — | 0.00 | — | Motor Spin minimum |
| `MOT_SPOOL_TIME` | — | 0.00 | s | Spool up time |
| `MOT_SPOOL_TIM_DN` | — | 0.00 | s | Spool down time |
| `MOT_THST_EXPO` | — | 0.00 | — | Thrust Curve Expo |
| `MOT_THST_HOVER` | — | 0.00 | — | Thrust Hover Value |
| `MOT_YAW_HEADROOM` | — | 0.00 | PWM | Matrix Yaw Min |
| `MOT_YAW_SV_ANGLE` | — | 0.00 | deg | Yaw Servo Max Lean Angle |
| `MSP_OPTIONS` | `MSP_OSD_CONFIG` | 0.37 | — | MSP OSD Options |
| `MSP_OSD_NCELLS` | `MSP_OSD_CONFIG` | 0.62 | — | Cell count override |
| `NET_DHCP` | — | 0.00 | — | DHCP client |
| `NET_ENABLE` | — | 0.00 | — | Networking Enable |
| `NET_GWADDR0` | — | 0.00 | — | IPv4 Address 1st byte |
| `NET_GWADDR1` | — | 0.00 | — | IPv4 Address 2nd byte |
| `NET_GWADDR2` | — | 0.00 | — | IPv4 Address 3rd byte |
| `NET_GWADDR3` | — | 0.00 | — | IPv4 Address 4th byte |
| `NET_IPADDR0` | — | 0.00 | — | IPv4 Address 1st byte |
| `NET_IPADDR1` | — | 0.00 | — | IPv4 Address 2nd byte |
| `NET_IPADDR2` | — | 0.00 | — | IPv4 Address 3rd byte |
| `NET_IPADDR3` | — | 0.00 | — | IPv4 Address 4th byte |
| `NET_MACADDR0` | — | 0.00 | — | MAC Address 1st byte |
| `NET_MACADDR1` | — | 0.00 | — | MAC Address 2nd byte |
| `NET_MACADDR2` | — | 0.00 | — | MAC Address 3rd byte |
| `NET_MACADDR3` | — | 0.00 | — | MAC Address 4th byte |
| `NET_MACADDR4` | — | 0.00 | — | MAC Address 5th byte |
| `NET_MACADDR5` | — | 0.00 | — | MAC Address 6th byte |
| `NET_NETMASK` | — | 0.00 | — | IP Subnet mask |
| `NET_OPTIONS` | — | 0.00 | — | Networking options |
| `NET_P1_IP0` | — | 0.00 | — | IPv4 Address 1st byte |
| `NET_P1_IP1` | — | 0.00 | — | IPv4 Address 2nd byte |
| `NET_P1_IP2` | — | 0.00 | — | IPv4 Address 3rd byte |
| `NET_P1_IP3` | — | 0.00 | — | IPv4 Address 4th byte |
| `NET_P1_PORT` | — | 0.00 | — | Port number |
| `NET_P1_PROTOCOL` | — | 0.00 | — | Protocol |
| `NET_P1_TYPE` | — | 0.00 | — | Port type |
| `NET_P2_IP0` | — | 0.00 | — | IPv4 Address 1st byte |
| `NET_P2_IP1` | — | 0.00 | — | IPv4 Address 2nd byte |
| `NET_P2_IP2` | — | 0.00 | — | IPv4 Address 3rd byte |
| `NET_P2_IP3` | — | 0.00 | — | IPv4 Address 4th byte |
| `NET_P2_PORT` | — | 0.00 | — | Port number |
| `NET_P2_PROTOCOL` | — | 0.00 | — | Protocol |
| `NET_P2_TYPE` | — | 0.00 | — | Port type |
| `NET_P3_IP0` | — | 0.00 | — | IPv4 Address 1st byte |
| `NET_P3_IP1` | — | 0.00 | — | IPv4 Address 2nd byte |
| `NET_P3_IP2` | — | 0.00 | — | IPv4 Address 3rd byte |
| `NET_P3_IP3` | — | 0.00 | — | IPv4 Address 4th byte |
| `NET_P3_PORT` | — | 0.00 | — | Port number |
| `NET_P3_PROTOCOL` | — | 0.00 | — | Protocol |
| `NET_P3_TYPE` | — | 0.00 | — | Port type |
| `NET_P4_IP0` | — | 0.00 | — | IPv4 Address 1st byte |
| `NET_P4_IP1` | — | 0.00 | — | IPv4 Address 2nd byte |
| `NET_P4_IP2` | — | 0.00 | — | IPv4 Address 3rd byte |
| `NET_P4_IP3` | — | 0.00 | — | IPv4 Address 4th byte |
| `NET_P4_PORT` | — | 0.00 | — | Port number |
| `NET_P4_PROTOCOL` | — | 0.00 | — | Protocol |
| `NET_P4_TYPE` | — | 0.00 | — | Port type |
| `NET_REMPPP_IP0` | — | 0.00 | — | IPv4 Address 1st byte |
| `NET_REMPPP_IP1` | — | 0.00 | — | IPv4 Address 2nd byte |
| `NET_REMPPP_IP2` | — | 0.00 | — | IPv4 Address 3rd byte |
| `NET_REMPPP_IP3` | — | 0.00 | — | IPv4 Address 4th byte |
| `NET_TESTS` | — | 0.00 | — | Test enable flags |
| `NET_TEST_IP0` | — | 0.00 | — | IPv4 Address 1st byte |
| `NET_TEST_IP1` | — | 0.00 | — | IPv4 Address 2nd byte |
| `NET_TEST_IP2` | — | 0.00 | — | IPv4 Address 3rd byte |
| `NET_TEST_IP3` | — | 0.00 | — | IPv4 Address 4th byte |
| `NMEA_MSG_EN` | — | 0.00 | — | Messages Enable bitmask |
| `NMEA_RATE_MS` | `MS_FILT_RATE_HZ` | 0.40 | ms | NMEA Output rate |
| `NTF_BUZZ_ON_LVL` | — | 0.00 | — | Buzzer-on pin logic level |
| `NTF_BUZZ_PIN` | — | 0.00 | — | Buzzer pin |
| `NTF_BUZZ_TYPES` | — | 0.00 | — | Buzzer Driver Types |
| `NTF_BUZZ_VOLUME` | — | 0.00 | % | Buzzer volume |
| `NTF_DISPLAY_TYPE` | — | 0.00 | — | Type of on-board I2C display |
| `NTF_LED_BRIGHT` | — | 0.00 | — | LED Brightness |
| `NTF_LED_LEN` | — | 0.00 | — | Serial LED String Length |
| `NTF_LED_OVERRIDE` | — | 0.00 | — | Specifies colour source for the RGBLed |
| `NTF_LED_TYPES` | — | 0.00 | — | LED Driver Types |
| `NTF_OREO_THEME` | — | 0.00 | — | OreoLED Theme |
| `OA_BR_CONT_ANGLE` | — | 0.00 | — | BendyRuler's bearing change resistance threshold angle |
| `OA_BR_CONT_RATIO` | — | 0.00 | — | Obstacle Avoidance margin ratio for BendyRuler to change bearing significantly |
| `OA_BR_LOOKAHEAD` | — | 0.00 | m | Object Avoidance look ahead distance maximum |
| `OA_BR_TYPE` | — | 0.00 | — | Type of BendyRuler |
| `OA_DB_ALT_MIN` | — | 0.00 | m | OADatabase minimum altitude above home before storing obstacles |
| `OA_DB_BEAM_WIDTH` | — | 0.00 | deg | OADatabase beam width |
| `OA_DB_DIST_MAX` | — | 0.00 | m | OADatabase Distance Maximum |
| `OA_DB_EXPIRE` | — | 0.00 | s | OADatabase item timeout |
| `OA_DB_OUTPUT` | — | 0.00 | — | OADatabase output level |
| `OA_DB_QUEUE_SIZE` | — | 0.00 | — | OADatabase queue maximum number of points |
| `OA_DB_RADIUS_MIN` | — | 0.00 | m | OADatabase Minimum  radius |
| `OA_DB_SIZE` | — | 0.00 | — | OADatabase maximum number of points |
| `OA_MARGIN_MAX` | — | 0.00 | m | Object Avoidance wide margin distance |
| `OA_OPTIONS` | — | 0.00 | — | Options while recovering from Object Avoidance |
| `OA_TYPE` | — | 0.00 | — | Object Avoidance Path Planning algorithm to use |
| `OSD1_ACRVOLT_EN` | `OSD_SYMBOLS` | 0.33 | — | ACRVOLT_EN |
| `OSD1_ACRVOLT_X` | — | 0.00 | — | ACRVOLT_X |
| `OSD1_ACRVOLT_Y` | — | 0.00 | — | ACRVOLT_Y |
| `OSD1_ALTITUDE_EN` | `OSD_SYMBOLS` | 0.33 | — | ALTITUDE_EN |
| `OSD1_ALTITUDE_X` | — | 0.00 | — | ALTITUDE_X |
| `OSD1_ALTITUDE_Y` | — | 0.00 | — | ALTITUDE_Y |
| `OSD1_ARMING_EN` | `OSD_SYMBOLS` | 0.33 | — | ARMING_EN |
| `OSD1_ARMING_X` | — | 0.00 | — | ARMING_X |
| `OSD1_ARMING_Y` | — | 0.00 | — | ARMING_Y |
| `OSD1_ASPD1_EN` | `ASPD_PRIMARY` | 0.33 | — | ASPD1_EN |
| `OSD1_ASPD1_X` | — | 0.00 | — | ASPD1_X |
| `OSD1_ASPD1_Y` | — | 0.00 | — | ASPD1_Y |
| `OSD1_ASPD2_EN` | `ASPD_PRIMARY` | 0.33 | — | ASPD2_EN |
| `OSD1_ASPD2_X` | — | 0.00 | — | ASPD2_X |
| `OSD1_ASPD2_Y` | — | 0.00 | — | ASPD2_Y |
| `OSD1_ASPEED_EN` | `OSD_SYMBOLS` | 0.33 | — | ASPEED_EN |
| `OSD1_ASPEED_X` | — | 0.00 | — | ASPEED_X |
| `OSD1_ASPEED_Y` | — | 0.00 | — | ASPEED_Y |
| `OSD1_ATEMP_EN` | `OSD_SYMBOLS` | 0.33 | — | ATEMP_EN |
| `OSD1_ATEMP_X` | — | 0.00 | — | ATEMP_X |
| `OSD1_ATEMP_Y` | — | 0.00 | — | ATEMP_Y |
| `OSD1_AVGCELLV_EN` | `OSD_SYMBOLS` | 0.33 | — | AVGCELLV_EN |
| `OSD1_AVGCELLV_X` | — | 0.00 | — | AVGCELLV_X |
| `OSD1_AVGCELLV_Y` | — | 0.00 | — | AVGCELLV_Y |
| `OSD1_BAT2USED_EN` | `OSD_SYMBOLS` | 0.33 | — | BAT2USED_EN |
| `OSD1_BAT2USED_X` | — | 0.00 | — | BAT2USED_X |
| `OSD1_BAT2USED_Y` | — | 0.00 | — | BAT2USED_Y |
| `OSD1_BAT2_VLT_EN` | — | 0.00 | — | BAT2VLT_EN |
| `OSD1_BAT2_VLT_X` | — | 0.00 | — | BAT2VLT_X |
| `OSD1_BAT2_VLT_Y` | — | 0.00 | — | BAT2VLT_Y |
| `OSD1_BATTBAR_EN` | `OSD_SYMBOLS` | 0.33 | — | BATT_BAR_EN |
| `OSD1_BATTBAR_X` | — | 0.00 | — | BATT_BAR_X |
| `OSD1_BATTBAR_Y` | — | 0.00 | — | BATT_BAR_Y |
| `OSD1_BATUSED_EN` | `OSD_SYMBOLS` | 0.33 | — | BATUSED_EN |
| `OSD1_BATUSED_X` | — | 0.00 | — | BATUSED_X |
| `OSD1_BATUSED_Y` | — | 0.00 | — | BATUSED_Y |
| `OSD1_BAT_VOLT_EN` | — | 0.00 | — | BATVOLT_EN |
| `OSD1_BAT_VOLT_X` | — | 0.00 | — | BATVOLT_X |
| `OSD1_BAT_VOLT_Y` | — | 0.00 | — | BATVOLT_Y |
| `OSD1_BTEMP_EN` | `OSD_SYMBOLS` | 0.33 | — | BTEMP_EN |
| `OSD1_BTEMP_X` | — | 0.00 | — | BTEMP_X |
| `OSD1_BTEMP_Y` | — | 0.00 | — | BTEMP_Y |
| `OSD1_CALLSIGN_EN` | `OSD_SYMBOLS` | 0.33 | — | CALLSIGN_EN |
| `OSD1_CALLSIGN_X` | — | 0.00 | — | CALLSIGN_X |
| `OSD1_CALLSIGN_Y` | — | 0.00 | — | CALLSIGN_Y |
| `OSD1_CELLVOLT_EN` | `OSD_SYMBOLS` | 0.33 | — | CELL_VOLT_EN |
| `OSD1_CELLVOLT_X` | — | 0.00 | — | CELL_VOLT_X |
| `OSD1_CELLVOLT_Y` | — | 0.00 | — | CELL_VOLT_Y |
| `OSD1_CHAN_MAX` | — | 0.00 | — | Transmitter switch screen maximum pwm |
| `OSD1_CHAN_MIN` | — | 0.00 | — | Transmitter switch screen minimum pwm |
| `OSD1_CLIMBEFF_EN` | `OSD_SYMBOLS` | 0.33 | — | CLIMBEFF_EN |
| `OSD1_CLIMBEFF_X` | — | 0.00 | — | CLIMBEFF_X |
| `OSD1_CLIMBEFF_Y` | — | 0.00 | — | CLIMBEFF_Y |
| `OSD1_CLK_EN` | `OSD_SYMBOLS` | 0.33 | — | CLK_EN |
| `OSD1_CLK_X` | — | 0.00 | — | CLK_X |
| `OSD1_CLK_Y` | — | 0.00 | — | CLK_Y |
| `OSD1_COMPASS_EN` | `OSD_SYMBOLS` | 0.33 | — | COMPASS_EN |
| `OSD1_COMPASS_X` | — | 0.00 | — | COMPASS_X |
| `OSD1_COMPASS_Y` | — | 0.00 | — | COMPASS_Y |
| `OSD1_CRSSHAIR_EN` | `OSD_SYMBOLS` | 0.33 | — | CRSSHAIR_EN |
| `OSD1_CRSSHAIR_X` | — | 0.00 | — | CRSSHAIR_X |
| `OSD1_CRSSHAIR_Y` | — | 0.00 | — | CRSSHAIR_Y |
| `OSD1_CURRENT2_EN` | `OSD_SYMBOLS` | 0.33 | — | CURRENT2_EN |
| `OSD1_CURRENT2_X` | — | 0.00 | — | CURRENT2_X |
| `OSD1_CURRENT2_Y` | — | 0.00 | — | CURRENT2_Y |
| `OSD1_CURRENT_EN` | `OSD_SYMBOLS` | 0.33 | — | CURRENT_EN |
| `OSD1_CURRENT_X` | — | 0.00 | — | CURRENT_X |
| `OSD1_CURRENT_Y` | — | 0.00 | — | CURRENT_Y |
| `OSD1_DIST_EN` | `OSD_SYMBOLS` | 0.33 | — | DIST_EN |
| `OSD1_DIST_X` | — | 0.00 | — | DIST_X |
| `OSD1_DIST_Y` | — | 0.00 | — | DIST_Y |
| `OSD1_EFF_EN` | `OSD_SYMBOLS` | 0.33 | — | EFF_EN |
| `OSD1_EFF_X` | — | 0.00 | — | EFF_X |
| `OSD1_EFF_Y` | — | 0.00 | — | EFF_Y |
| `OSD1_ENABLE` | `OSD_SYMBOLS` | 0.50 | — | Enable screen |
| `OSD1_ESCAMPS_EN` | `OSD_SYMBOLS` | 0.33 | — | ESCAMPS_EN |
| `OSD1_ESCAMPS_X` | — | 0.00 | — | ESCAMPS_X |
| `OSD1_ESCAMPS_Y` | — | 0.00 | — | ESCAMPS_Y |
| `OSD1_ESCRPM_EN` | `OSD_SYMBOLS` | 0.33 | — | ESCRPM_EN |
| `OSD1_ESCRPM_X` | — | 0.00 | — | ESCRPM_X |
| `OSD1_ESCRPM_Y` | — | 0.00 | — | ESCRPM_Y |
| `OSD1_ESCTEMP_EN` | `OSD_SYMBOLS` | 0.33 | — | ESCTEMP_EN |
| `OSD1_ESCTEMP_X` | — | 0.00 | — | ESCTEMP_X |
| `OSD1_ESCTEMP_Y` | — | 0.00 | — | ESCTEMP_Y |
| `OSD1_ESC_IDX` | — | 0.00 | — | ESC_IDX |
| `OSD1_FENCE_EN` | `OSD_SYMBOLS` | 0.33 | — | FENCE_EN |
| `OSD1_FENCE_X` | — | 0.00 | — | FENCE_X |
| `OSD1_FENCE_Y` | — | 0.00 | — | FENCE_Y |
| `OSD1_FLTIME_EN` | `OSD_SYMBOLS` | 0.33 | — | FLTIME_EN |
| `OSD1_FLTIME_X` | — | 0.00 | — | FLTIME_X |
| `OSD1_FLTIME_Y` | — | 0.00 | — | FLTIME_Y |
| `OSD1_FLTMODE_EN` | `OSD_SYMBOLS` | 0.33 | — | FLTMODE_EN |
| `OSD1_FLTMODE_X` | — | 0.00 | — | FLTMODE_X |
| `OSD1_FLTMODE_Y` | — | 0.00 | — | FLTMODE_Y |
| `OSD1_FONT` | `OSD_SYMBOLS` | 0.33 | — | Sets the font index for this screen (MSP DisplayPort only) |
| `OSD1_GPSLAT_EN` | `OSD_SYMBOLS` | 0.33 | — | GPSLAT_EN |
| `OSD1_GPSLAT_X` | — | 0.00 | — | GPSLAT_X |
| `OSD1_GPSLAT_Y` | — | 0.00 | — | GPSLAT_Y |
| `OSD1_GPSLONG_EN` | `OSD_SYMBOLS` | 0.33 | — | GPSLONG_EN |
| `OSD1_GPSLONG_X` | — | 0.00 | — | GPSLONG_X |
| `OSD1_GPSLONG_Y` | — | 0.00 | — | GPSLONG_Y |
| `OSD1_GSPEED_EN` | `OSD_SYMBOLS` | 0.33 | — | GSPEED_EN |
| `OSD1_GSPEED_X` | — | 0.00 | — | GSPEED_X |
| `OSD1_GSPEED_Y` | — | 0.00 | — | GSPEED_Y |
| `OSD1_HDOP_EN` | `OSD_SYMBOLS` | 0.33 | — | HDOP_EN |
| `OSD1_HDOP_X` | — | 0.00 | — | HDOP_X |
| `OSD1_HDOP_Y` | — | 0.00 | — | HDOP_Y |
| `OSD1_HEADING_EN` | `OSD_SYMBOLS` | 0.33 | — | HEADING_EN |
| `OSD1_HEADING_X` | — | 0.00 | — | HEADING_X |
| `OSD1_HEADING_Y` | — | 0.00 | — | HEADING_Y |
| `OSD1_HOMEDIR_EN` | `OSD_SYMBOLS` | 0.33 | — | HOMEDIR_EN |
| `OSD1_HOMEDIR_X` | — | 0.00 | — | HOMEDIR_X |
| `OSD1_HOMEDIR_Y` | — | 0.00 | — | HOMEDIR_Y |
| `OSD1_HOMEDIST_EN` | `OSD_SYMBOLS` | 0.33 | — | HOMEDIST_EN |
| `OSD1_HOMEDIST_X` | — | 0.00 | — | HOMEDIST_X |
| `OSD1_HOMEDIST_Y` | — | 0.00 | — | HOMEDIST_Y |
| `OSD1_HOME_EN` | `OSD_SYMBOLS` | 0.33 | — | HOME_EN |
| `OSD1_HOME_X` | — | 0.00 | — | HOME_X |
| `OSD1_HOME_Y` | — | 0.00 | — | HOME_Y |
| `OSD1_HORIZON_EN` | `OSD_SYMBOLS` | 0.33 | — | HORIZON_EN |
| `OSD1_HORIZON_X` | — | 0.00 | — | HORIZON_X |
| `OSD1_HORIZON_Y` | — | 0.00 | — | HORIZON_Y |
| `OSD1_LINK_Q_EN` | — | 0.00 | — | LINK_Q_EN |
| `OSD1_LINK_Q_X` | — | 0.00 | — | LINK_Q_X |
| `OSD1_LINK_Q_Y` | — | 0.00 | — | LINK_Q_Y |
| `OSD1_MESSAGE_EN` | `OSD_SYMBOLS` | 0.33 | — | MESSAGE_EN |
| `OSD1_MESSAGE_X` | — | 0.00 | — | MESSAGE_X |
| `OSD1_MESSAGE_Y` | — | 0.00 | — | MESSAGE_Y |
| `OSD1_PITCH_EN` | `OSD_SYMBOLS` | 0.33 | — | PITCH_EN |
| `OSD1_PITCH_X` | — | 0.00 | — | PITCH_X |
| `OSD1_PITCH_Y` | — | 0.00 | — | PITCH_Y |
| `OSD1_PLUSCODE_EN` | `OSD_SYMBOLS` | 0.33 | — | PLUSCODE_EN |
| `OSD1_PLUSCODE_X` | — | 0.00 | — | PLUSCODE_X |
| `OSD1_PLUSCODE_Y` | — | 0.00 | — | PLUSCODE_Y |
| `OSD1_POWER_EN` | `OSD_SYMBOLS` | 0.33 | — | POWER_EN |
| `OSD1_POWER_X` | — | 0.00 | — | POWER_X |
| `OSD1_POWER_Y` | — | 0.00 | — | POWER_Y |
| `OSD1_RC_ANT_EN` | `OSD_RC_STICK` | 0.50 | — | RC_ANT_EN |
| `OSD1_RC_ANT_X` | `OSD_RC_STICK` | 0.40 | — | RC_ANT_X |
| `OSD1_RC_ANT_Y` | `OSD_RC_STICK` | 0.40 | — | RC_ANT_Y |
| `OSD1_RC_LQ_EN` | `OSD_RC_STICK` | 0.50 | — | RC_LQ_EN |
| `OSD1_RC_LQ_X` | `OSD_RC_STICK` | 0.40 | — | RC_LQ_X |
| `OSD1_RC_LQ_Y` | `OSD_RC_STICK` | 0.40 | — | RC_LQ_Y |
| `OSD1_RC_PWR_EN` | `OSD_RC_STICK` | 0.50 | — | RC_PWR_EN |
| `OSD1_RC_PWR_X` | `OSD_RC_STICK` | 0.40 | — | RC_PWR_X |
| `OSD1_RC_PWR_Y` | `OSD_RC_STICK` | 0.40 | — | RC_PWR_Y |
| `OSD1_RC_SNR_EN` | `OSD_RC_STICK` | 0.50 | — | RC_SNR_EN |
| `OSD1_RC_SNR_X` | `OSD_RC_STICK` | 0.40 | — | RC_SNR_X |
| `OSD1_RC_SNR_Y` | `OSD_RC_STICK` | 0.40 | — | RC_SNR_Y |
| `OSD1_RESTVOLT_EN` | `OSD_SYMBOLS` | 0.33 | — | RESTVOLT_EN |
| `OSD1_RESTVOLT_X` | — | 0.00 | — | RESTVOLT_X |
| `OSD1_RESTVOLT_Y` | — | 0.00 | — | RESTVOLT_Y |
| `OSD1_RNGF_EN` | `OSD_SYMBOLS` | 0.33 | — | RNGF_EN |
| `OSD1_RNGF_X` | — | 0.00 | — | RNGF_X |
| `OSD1_RNGF_Y` | — | 0.00 | — | RNGF_Y |
| `OSD1_ROLL_EN` | `OSD_SYMBOLS` | 0.33 | — | ROLL_EN |
| `OSD1_ROLL_X` | — | 0.00 | — | ROLL_X |
| `OSD1_ROLL_Y` | — | 0.00 | — | ROLL_Y |
| `OSD1_RPM_EN` | `RPM_CAP_ENABLE` | 0.33 | — | RPM_EN |
| `OSD1_RPM_X` | — | 0.00 | — | RPM_X |
| `OSD1_RPM_Y` | — | 0.00 | — | RPM_Y |
| `OSD1_RSSIDBM_EN` | `OSD_SYMBOLS` | 0.33 | — | RSSIDBM_EN |
| `OSD1_RSSIDBM_X` | — | 0.00 | — | RSSIDBM_X |
| `OSD1_RSSIDBM_Y` | — | 0.00 | — | RSSIDBM_Y |
| `OSD1_RSSI_EN` | `OSD_SYMBOLS` | 0.33 | — | RSSI_EN |
| `OSD1_RSSI_X` | — | 0.00 | — | RSSI_X |
| `OSD1_RSSI_Y` | — | 0.00 | — | RSSI_Y |
| `OSD1_SATS_EN` | `OSD_SYMBOLS` | 0.33 | — | SATS_EN |
| `OSD1_SATS_X` | — | 0.00 | — | SATS_X |
| `OSD1_SATS_Y` | — | 0.00 | — | SATS_Y |
| `OSD1_SIDEBARS_EN` | `OSD_SYMBOLS` | 0.33 | — | SIDEBARS_EN |
| `OSD1_SIDEBARS_X` | — | 0.00 | — | SIDEBARS_X |
| `OSD1_SIDEBARS_Y` | — | 0.00 | — | SIDEBARS_Y |
| `OSD1_STATS_EN` | `OSD_SYMBOLS` | 0.33 | — | STATS_EN |
| `OSD1_STATS_X` | — | 0.00 | — | STATS_X |
| `OSD1_STATS_Y` | — | 0.00 | — | STATS_Y |
| `OSD1_TEMP_EN` | `OSD_SYMBOLS` | 0.33 | — | TEMP_EN |
| `OSD1_TEMP_X` | — | 0.00 | — | TEMP_X |
| `OSD1_TEMP_Y` | — | 0.00 | — | TEMP_Y |
| `OSD1_TER_HGT_EN` | — | 0.00 | — | TER_HGT_EN |
| `OSD1_TER_HGT_X` | — | 0.00 | — | TER_HGT_X |
| `OSD1_TER_HGT_Y` | — | 0.00 | — | TER_HGT_Y |
| `OSD1_THROTTLE_EN` | `OSD_SYMBOLS` | 0.33 | — | THROTTLE_EN |
| `OSD1_THROTTLE_X` | — | 0.00 | — | THROTTLE_X |
| `OSD1_THROTTLE_Y` | — | 0.00 | — | THROTTLE_Y |
| `OSD1_TXT_RES` | — | 0.00 | — | Sets the overlay text resolution (MSP DisplayPort only) |
| `OSD1_VSPEED_EN` | `OSD_SYMBOLS` | 0.33 | — | VSPEED_EN |
| `OSD1_VSPEED_X` | — | 0.00 | — | VSPEED_X |
| `OSD1_VSPEED_Y` | — | 0.00 | — | VSPEED_Y |
| `OSD1_VTX_PWR_EN` | — | 0.00 | — | VTX_PWR_EN |
| `OSD1_VTX_PWR_X` | — | 0.00 | — | VTX_PWR_X |
| `OSD1_VTX_PWR_Y` | — | 0.00 | — | VTX_PWR_Y |
| `OSD1_WAYPOINT_EN` | `OSD_SYMBOLS` | 0.33 | — | WAYPOINT_EN |
| `OSD1_WAYPOINT_X` | — | 0.00 | — | WAYPOINT_X |
| `OSD1_WAYPOINT_Y` | — | 0.00 | — | WAYPOINT_Y |
| `OSD1_WIND_EN` | `OSD_SYMBOLS` | 0.33 | — | WIND_EN |
| `OSD1_WIND_X` | — | 0.00 | — | WIND_X |
| `OSD1_WIND_Y` | — | 0.00 | — | WIND_Y |
| `OSD1_XTRACK_EN` | `OSD_SYMBOLS` | 0.33 | — | XTRACK_EN |
| `OSD1_XTRACK_X` | — | 0.00 | — | XTRACK_X |
| `OSD1_XTRACK_Y` | — | 0.00 | — | XTRACK_Y |
| `OSD2_ACRVOLT_EN` | `OSD_SYMBOLS` | 0.33 | — | ACRVOLT_EN |
| `OSD2_ACRVOLT_X` | — | 0.00 | — | ACRVOLT_X |
| `OSD2_ACRVOLT_Y` | — | 0.00 | — | ACRVOLT_Y |
| `OSD2_ALTITUDE_EN` | `OSD_SYMBOLS` | 0.33 | — | ALTITUDE_EN |
| `OSD2_ALTITUDE_X` | — | 0.00 | — | ALTITUDE_X |
| `OSD2_ALTITUDE_Y` | — | 0.00 | — | ALTITUDE_Y |
| `OSD2_ARMING_EN` | `OSD_SYMBOLS` | 0.33 | — | ARMING_EN |
| `OSD2_ARMING_X` | — | 0.00 | — | ARMING_X |
| `OSD2_ARMING_Y` | — | 0.00 | — | ARMING_Y |
| `OSD2_ASPD1_EN` | `ASPD_PRIMARY` | 0.33 | — | ASPD1_EN |
| `OSD2_ASPD1_X` | — | 0.00 | — | ASPD1_X |
| `OSD2_ASPD1_Y` | — | 0.00 | — | ASPD1_Y |
| `OSD2_ASPD2_EN` | `ASPD_PRIMARY` | 0.33 | — | ASPD2_EN |
| `OSD2_ASPD2_X` | — | 0.00 | — | ASPD2_X |
| `OSD2_ASPD2_Y` | — | 0.00 | — | ASPD2_Y |
| `OSD2_ASPEED_EN` | `OSD_SYMBOLS` | 0.33 | — | ASPEED_EN |
| `OSD2_ASPEED_X` | — | 0.00 | — | ASPEED_X |
| `OSD2_ASPEED_Y` | — | 0.00 | — | ASPEED_Y |
| `OSD2_ATEMP_EN` | `OSD_SYMBOLS` | 0.33 | — | ATEMP_EN |
| `OSD2_ATEMP_X` | — | 0.00 | — | ATEMP_X |
| `OSD2_ATEMP_Y` | — | 0.00 | — | ATEMP_Y |
| `OSD2_AVGCELLV_EN` | `OSD_SYMBOLS` | 0.33 | — | AVGCELLV_EN |
| `OSD2_AVGCELLV_X` | — | 0.00 | — | AVGCELLV_X |
| `OSD2_AVGCELLV_Y` | — | 0.00 | — | AVGCELLV_Y |
| `OSD2_BAT2USED_EN` | `OSD_SYMBOLS` | 0.33 | — | BAT2USED_EN |
| `OSD2_BAT2USED_X` | — | 0.00 | — | BAT2USED_X |
| `OSD2_BAT2USED_Y` | — | 0.00 | — | BAT2USED_Y |
| `OSD2_BAT2_VLT_EN` | — | 0.00 | — | BAT2VLT_EN |
| `OSD2_BAT2_VLT_X` | — | 0.00 | — | BAT2VLT_X |
| `OSD2_BAT2_VLT_Y` | — | 0.00 | — | BAT2VLT_Y |
| `OSD2_BATTBAR_EN` | `OSD_SYMBOLS` | 0.33 | — | BATT_BAR_EN |
| `OSD2_BATTBAR_X` | — | 0.00 | — | BATT_BAR_X |
| `OSD2_BATTBAR_Y` | — | 0.00 | — | BATT_BAR_Y |
| `OSD2_BATUSED_EN` | `OSD_SYMBOLS` | 0.33 | — | BATUSED_EN |
| `OSD2_BATUSED_X` | — | 0.00 | — | BATUSED_X |
| `OSD2_BATUSED_Y` | — | 0.00 | — | BATUSED_Y |
| `OSD2_BAT_VOLT_EN` | — | 0.00 | — | BATVOLT_EN |
| `OSD2_BAT_VOLT_X` | — | 0.00 | — | BATVOLT_X |
| `OSD2_BAT_VOLT_Y` | — | 0.00 | — | BATVOLT_Y |
| `OSD2_BTEMP_EN` | `OSD_SYMBOLS` | 0.33 | — | BTEMP_EN |
| `OSD2_BTEMP_X` | — | 0.00 | — | BTEMP_X |
| `OSD2_BTEMP_Y` | — | 0.00 | — | BTEMP_Y |
| `OSD2_CALLSIGN_EN` | `OSD_SYMBOLS` | 0.33 | — | CALLSIGN_EN |
| `OSD2_CALLSIGN_X` | — | 0.00 | — | CALLSIGN_X |
| `OSD2_CALLSIGN_Y` | — | 0.00 | — | CALLSIGN_Y |
| `OSD2_CELLVOLT_EN` | `OSD_SYMBOLS` | 0.33 | — | CELL_VOLT_EN |
| `OSD2_CELLVOLT_X` | — | 0.00 | — | CELL_VOLT_X |
| `OSD2_CELLVOLT_Y` | — | 0.00 | — | CELL_VOLT_Y |
| `OSD2_CHAN_MAX` | — | 0.00 | — | Transmitter switch screen maximum pwm |
| `OSD2_CHAN_MIN` | — | 0.00 | — | Transmitter switch screen minimum pwm |
| `OSD2_CLIMBEFF_EN` | `OSD_SYMBOLS` | 0.33 | — | CLIMBEFF_EN |
| `OSD2_CLIMBEFF_X` | — | 0.00 | — | CLIMBEFF_X |
| `OSD2_CLIMBEFF_Y` | — | 0.00 | — | CLIMBEFF_Y |
| `OSD2_CLK_EN` | `OSD_SYMBOLS` | 0.33 | — | CLK_EN |
| `OSD2_CLK_X` | — | 0.00 | — | CLK_X |
| `OSD2_CLK_Y` | — | 0.00 | — | CLK_Y |
| `OSD2_COMPASS_EN` | `OSD_SYMBOLS` | 0.33 | — | COMPASS_EN |
| `OSD2_COMPASS_X` | — | 0.00 | — | COMPASS_X |
| `OSD2_COMPASS_Y` | — | 0.00 | — | COMPASS_Y |
| `OSD2_CRSSHAIR_EN` | `OSD_SYMBOLS` | 0.33 | — | CRSSHAIR_EN |
| `OSD2_CRSSHAIR_X` | — | 0.00 | — | CRSSHAIR_X |
| `OSD2_CRSSHAIR_Y` | — | 0.00 | — | CRSSHAIR_Y |
| `OSD2_CURRENT2_EN` | `OSD_SYMBOLS` | 0.33 | — | CURRENT2_EN |
| `OSD2_CURRENT2_X` | — | 0.00 | — | CURRENT2_X |
| `OSD2_CURRENT2_Y` | — | 0.00 | — | CURRENT2_Y |
| `OSD2_CURRENT_EN` | `OSD_SYMBOLS` | 0.33 | — | CURRENT_EN |
| `OSD2_CURRENT_X` | — | 0.00 | — | CURRENT_X |
| `OSD2_CURRENT_Y` | — | 0.00 | — | CURRENT_Y |
| `OSD2_DIST_EN` | `OSD_SYMBOLS` | 0.33 | — | DIST_EN |
| `OSD2_DIST_X` | — | 0.00 | — | DIST_X |
| `OSD2_DIST_Y` | — | 0.00 | — | DIST_Y |
| `OSD2_EFF_EN` | `OSD_SYMBOLS` | 0.33 | — | EFF_EN |
| `OSD2_EFF_X` | — | 0.00 | — | EFF_X |
| `OSD2_EFF_Y` | — | 0.00 | — | EFF_Y |
| `OSD2_ENABLE` | `OSD_SYMBOLS` | 0.50 | — | Enable screen |
| `OSD2_ESCAMPS_EN` | `OSD_SYMBOLS` | 0.33 | — | ESCAMPS_EN |
| `OSD2_ESCAMPS_X` | — | 0.00 | — | ESCAMPS_X |
| `OSD2_ESCAMPS_Y` | — | 0.00 | — | ESCAMPS_Y |
| `OSD2_ESCRPM_EN` | `OSD_SYMBOLS` | 0.33 | — | ESCRPM_EN |
| `OSD2_ESCRPM_X` | — | 0.00 | — | ESCRPM_X |
| `OSD2_ESCRPM_Y` | — | 0.00 | — | ESCRPM_Y |
| `OSD2_ESCTEMP_EN` | `OSD_SYMBOLS` | 0.33 | — | ESCTEMP_EN |
| `OSD2_ESCTEMP_X` | — | 0.00 | — | ESCTEMP_X |
| `OSD2_ESCTEMP_Y` | — | 0.00 | — | ESCTEMP_Y |
| `OSD2_ESC_IDX` | — | 0.00 | — | ESC_IDX |
| `OSD2_FENCE_EN` | `OSD_SYMBOLS` | 0.33 | — | FENCE_EN |
| `OSD2_FENCE_X` | — | 0.00 | — | FENCE_X |
| `OSD2_FENCE_Y` | — | 0.00 | — | FENCE_Y |
| `OSD2_FLTIME_EN` | `OSD_SYMBOLS` | 0.33 | — | FLTIME_EN |
| `OSD2_FLTIME_X` | — | 0.00 | — | FLTIME_X |
| `OSD2_FLTIME_Y` | — | 0.00 | — | FLTIME_Y |
| `OSD2_FLTMODE_EN` | `OSD_SYMBOLS` | 0.33 | — | FLTMODE_EN |
| `OSD2_FLTMODE_X` | — | 0.00 | — | FLTMODE_X |
| `OSD2_FLTMODE_Y` | — | 0.00 | — | FLTMODE_Y |
| `OSD2_FONT` | `OSD_SYMBOLS` | 0.33 | — | Sets the font index for this screen (MSP DisplayPort only) |
| `OSD2_GPSLAT_EN` | `OSD_SYMBOLS` | 0.33 | — | GPSLAT_EN |
| `OSD2_GPSLAT_X` | — | 0.00 | — | GPSLAT_X |
| `OSD2_GPSLAT_Y` | — | 0.00 | — | GPSLAT_Y |
| `OSD2_GPSLONG_EN` | `OSD_SYMBOLS` | 0.33 | — | GPSLONG_EN |
| `OSD2_GPSLONG_X` | — | 0.00 | — | GPSLONG_X |
| `OSD2_GPSLONG_Y` | — | 0.00 | — | GPSLONG_Y |
| `OSD2_GSPEED_EN` | `OSD_SYMBOLS` | 0.33 | — | GSPEED_EN |
| `OSD2_GSPEED_X` | — | 0.00 | — | GSPEED_X |
| `OSD2_GSPEED_Y` | — | 0.00 | — | GSPEED_Y |
| `OSD2_HDOP_EN` | `OSD_SYMBOLS` | 0.33 | — | HDOP_EN |
| `OSD2_HDOP_X` | — | 0.00 | — | HDOP_X |
| `OSD2_HDOP_Y` | — | 0.00 | — | HDOP_Y |
| `OSD2_HEADING_EN` | `OSD_SYMBOLS` | 0.33 | — | HEADING_EN |
| `OSD2_HEADING_X` | — | 0.00 | — | HEADING_X |
| `OSD2_HEADING_Y` | — | 0.00 | — | HEADING_Y |
| `OSD2_HOMEDIR_EN` | `OSD_SYMBOLS` | 0.33 | — | HOMEDIR_EN |
| `OSD2_HOMEDIR_X` | — | 0.00 | — | HOMEDIR_X |
| `OSD2_HOMEDIR_Y` | — | 0.00 | — | HOMEDIR_Y |
| `OSD2_HOMEDIST_EN` | `OSD_SYMBOLS` | 0.33 | — | HOMEDIST_EN |
| `OSD2_HOMEDIST_X` | — | 0.00 | — | HOMEDIST_X |
| `OSD2_HOMEDIST_Y` | — | 0.00 | — | HOMEDIST_Y |
| `OSD2_HOME_EN` | `OSD_SYMBOLS` | 0.33 | — | HOME_EN |
| `OSD2_HOME_X` | — | 0.00 | — | HOME_X |
| `OSD2_HOME_Y` | — | 0.00 | — | HOME_Y |
| `OSD2_HORIZON_EN` | `OSD_SYMBOLS` | 0.33 | — | HORIZON_EN |
| `OSD2_HORIZON_X` | — | 0.00 | — | HORIZON_X |
| `OSD2_HORIZON_Y` | — | 0.00 | — | HORIZON_Y |
| `OSD2_LINK_Q_EN` | — | 0.00 | — | LINK_Q_EN |
| `OSD2_LINK_Q_X` | — | 0.00 | — | LINK_Q_X |
| `OSD2_LINK_Q_Y` | — | 0.00 | — | LINK_Q_Y |
| `OSD2_MESSAGE_EN` | `OSD_SYMBOLS` | 0.33 | — | MESSAGE_EN |
| `OSD2_MESSAGE_X` | — | 0.00 | — | MESSAGE_X |
| `OSD2_MESSAGE_Y` | — | 0.00 | — | MESSAGE_Y |
| `OSD2_PITCH_EN` | `OSD_SYMBOLS` | 0.33 | — | PITCH_EN |
| `OSD2_PITCH_X` | — | 0.00 | — | PITCH_X |
| `OSD2_PITCH_Y` | — | 0.00 | — | PITCH_Y |
| `OSD2_PLUSCODE_EN` | `OSD_SYMBOLS` | 0.33 | — | PLUSCODE_EN |
| `OSD2_PLUSCODE_X` | — | 0.00 | — | PLUSCODE_X |
| `OSD2_PLUSCODE_Y` | — | 0.00 | — | PLUSCODE_Y |
| `OSD2_POWER_EN` | `OSD_SYMBOLS` | 0.33 | — | POWER_EN |
| `OSD2_POWER_X` | — | 0.00 | — | POWER_X |
| `OSD2_POWER_Y` | — | 0.00 | — | POWER_Y |
| `OSD2_RC_ANT_EN` | `OSD_RC_STICK` | 0.50 | — | RC_ANT_EN |
| `OSD2_RC_ANT_X` | `OSD_RC_STICK` | 0.40 | — | RC_ANT_X |
| `OSD2_RC_ANT_Y` | `OSD_RC_STICK` | 0.40 | — | RC_ANT_Y |
| `OSD2_RC_LQ_EN` | `OSD_RC_STICK` | 0.50 | — | RC_LQ_EN |
| `OSD2_RC_LQ_X` | `OSD_RC_STICK` | 0.40 | — | RC_LQ_X |
| `OSD2_RC_LQ_Y` | `OSD_RC_STICK` | 0.40 | — | RC_LQ_Y |
| `OSD2_RC_PWR_EN` | `OSD_RC_STICK` | 0.50 | — | RC_PWR_EN |
| `OSD2_RC_PWR_X` | `OSD_RC_STICK` | 0.40 | — | RC_PWR_X |
| `OSD2_RC_PWR_Y` | `OSD_RC_STICK` | 0.40 | — | RC_PWR_Y |
| `OSD2_RC_SNR_EN` | `OSD_RC_STICK` | 0.50 | — | RC_SNR_EN |
| `OSD2_RC_SNR_X` | `OSD_RC_STICK` | 0.40 | — | RC_SNR_X |
| `OSD2_RC_SNR_Y` | `OSD_RC_STICK` | 0.40 | — | RC_SNR_Y |
| `OSD2_RESTVOLT_EN` | `OSD_SYMBOLS` | 0.33 | — | RESTVOLT_EN |
| `OSD2_RESTVOLT_X` | — | 0.00 | — | RESTVOLT_X |
| `OSD2_RESTVOLT_Y` | — | 0.00 | — | RESTVOLT_Y |
| `OSD2_RNGF_EN` | `OSD_SYMBOLS` | 0.33 | — | RNGF_EN |
| `OSD2_RNGF_X` | — | 0.00 | — | RNGF_X |
| `OSD2_RNGF_Y` | — | 0.00 | — | RNGF_Y |
| `OSD2_ROLL_EN` | `OSD_SYMBOLS` | 0.33 | — | ROLL_EN |
| `OSD2_ROLL_X` | — | 0.00 | — | ROLL_X |
| `OSD2_ROLL_Y` | — | 0.00 | — | ROLL_Y |
| `OSD2_RPM_EN` | `RPM_CAP_ENABLE` | 0.33 | — | RPM_EN |
| `OSD2_RPM_X` | — | 0.00 | — | RPM_X |
| `OSD2_RPM_Y` | — | 0.00 | — | RPM_Y |
| `OSD2_RSSIDBM_EN` | `OSD_SYMBOLS` | 0.33 | — | RSSIDBM_EN |
| `OSD2_RSSIDBM_X` | — | 0.00 | — | RSSIDBM_X |
| `OSD2_RSSIDBM_Y` | — | 0.00 | — | RSSIDBM_Y |
| `OSD2_RSSI_EN` | `OSD_SYMBOLS` | 0.33 | — | RSSI_EN |
| `OSD2_RSSI_X` | — | 0.00 | — | RSSI_X |
| `OSD2_RSSI_Y` | — | 0.00 | — | RSSI_Y |
| `OSD2_SATS_EN` | `OSD_SYMBOLS` | 0.33 | — | SATS_EN |
| `OSD2_SATS_X` | — | 0.00 | — | SATS_X |
| `OSD2_SATS_Y` | — | 0.00 | — | SATS_Y |
| `OSD2_SIDEBARS_EN` | `OSD_SYMBOLS` | 0.33 | — | SIDEBARS_EN |
| `OSD2_SIDEBARS_X` | — | 0.00 | — | SIDEBARS_X |
| `OSD2_SIDEBARS_Y` | — | 0.00 | — | SIDEBARS_Y |
| `OSD2_STATS_EN` | `OSD_SYMBOLS` | 0.33 | — | STATS_EN |
| `OSD2_STATS_X` | — | 0.00 | — | STATS_X |
| `OSD2_STATS_Y` | — | 0.00 | — | STATS_Y |
| `OSD2_TEMP_EN` | `OSD_SYMBOLS` | 0.33 | — | TEMP_EN |
| `OSD2_TEMP_X` | — | 0.00 | — | TEMP_X |
| `OSD2_TEMP_Y` | — | 0.00 | — | TEMP_Y |
| `OSD2_TER_HGT_EN` | — | 0.00 | — | TER_HGT_EN |
| `OSD2_TER_HGT_X` | — | 0.00 | — | TER_HGT_X |
| `OSD2_TER_HGT_Y` | — | 0.00 | — | TER_HGT_Y |
| `OSD2_THROTTLE_EN` | `OSD_SYMBOLS` | 0.33 | — | THROTTLE_EN |
| `OSD2_THROTTLE_X` | — | 0.00 | — | THROTTLE_X |
| `OSD2_THROTTLE_Y` | — | 0.00 | — | THROTTLE_Y |
| `OSD2_TXT_RES` | — | 0.00 | — | Sets the overlay text resolution (MSP DisplayPort only) |
| `OSD2_VSPEED_EN` | `OSD_SYMBOLS` | 0.33 | — | VSPEED_EN |
| `OSD2_VSPEED_X` | — | 0.00 | — | VSPEED_X |
| `OSD2_VSPEED_Y` | — | 0.00 | — | VSPEED_Y |
| `OSD2_VTX_PWR_EN` | — | 0.00 | — | VTX_PWR_EN |
| `OSD2_VTX_PWR_X` | — | 0.00 | — | VTX_PWR_X |
| `OSD2_VTX_PWR_Y` | — | 0.00 | — | VTX_PWR_Y |
| `OSD2_WAYPOINT_EN` | `OSD_SYMBOLS` | 0.33 | — | WAYPOINT_EN |
| `OSD2_WAYPOINT_X` | — | 0.00 | — | WAYPOINT_X |
| `OSD2_WAYPOINT_Y` | — | 0.00 | — | WAYPOINT_Y |
| `OSD2_WIND_EN` | `OSD_SYMBOLS` | 0.33 | — | WIND_EN |
| `OSD2_WIND_X` | — | 0.00 | — | WIND_X |
| `OSD2_WIND_Y` | — | 0.00 | — | WIND_Y |
| `OSD2_XTRACK_EN` | `OSD_SYMBOLS` | 0.33 | — | XTRACK_EN |
| `OSD2_XTRACK_X` | — | 0.00 | — | XTRACK_X |
| `OSD2_XTRACK_Y` | — | 0.00 | — | XTRACK_Y |
| `OSD3_ACRVOLT_EN` | `OSD_SYMBOLS` | 0.33 | — | ACRVOLT_EN |
| `OSD3_ACRVOLT_X` | — | 0.00 | — | ACRVOLT_X |
| `OSD3_ACRVOLT_Y` | — | 0.00 | — | ACRVOLT_Y |
| `OSD3_ALTITUDE_EN` | `OSD_SYMBOLS` | 0.33 | — | ALTITUDE_EN |
| `OSD3_ALTITUDE_X` | — | 0.00 | — | ALTITUDE_X |
| `OSD3_ALTITUDE_Y` | — | 0.00 | — | ALTITUDE_Y |
| `OSD3_ARMING_EN` | `OSD_SYMBOLS` | 0.33 | — | ARMING_EN |
| `OSD3_ARMING_X` | — | 0.00 | — | ARMING_X |
| `OSD3_ARMING_Y` | — | 0.00 | — | ARMING_Y |
| `OSD3_ASPD1_EN` | `ASPD_PRIMARY` | 0.33 | — | ASPD1_EN |
| `OSD3_ASPD1_X` | — | 0.00 | — | ASPD1_X |
| `OSD3_ASPD1_Y` | — | 0.00 | — | ASPD1_Y |
| `OSD3_ASPD2_EN` | `ASPD_PRIMARY` | 0.33 | — | ASPD2_EN |
| `OSD3_ASPD2_X` | — | 0.00 | — | ASPD2_X |
| `OSD3_ASPD2_Y` | — | 0.00 | — | ASPD2_Y |
| `OSD3_ASPEED_EN` | `OSD_SYMBOLS` | 0.33 | — | ASPEED_EN |
| `OSD3_ASPEED_X` | — | 0.00 | — | ASPEED_X |
| `OSD3_ASPEED_Y` | — | 0.00 | — | ASPEED_Y |
| `OSD3_ATEMP_EN` | `OSD_SYMBOLS` | 0.33 | — | ATEMP_EN |
| `OSD3_ATEMP_X` | — | 0.00 | — | ATEMP_X |
| `OSD3_ATEMP_Y` | — | 0.00 | — | ATEMP_Y |
| `OSD3_AVGCELLV_EN` | `OSD_SYMBOLS` | 0.33 | — | AVGCELLV_EN |
| `OSD3_AVGCELLV_X` | — | 0.00 | — | AVGCELLV_X |
| `OSD3_AVGCELLV_Y` | — | 0.00 | — | AVGCELLV_Y |
| `OSD3_BAT2USED_EN` | `OSD_SYMBOLS` | 0.33 | — | BAT2USED_EN |
| `OSD3_BAT2USED_X` | — | 0.00 | — | BAT2USED_X |
| `OSD3_BAT2USED_Y` | — | 0.00 | — | BAT2USED_Y |
| `OSD3_BAT2_VLT_EN` | — | 0.00 | — | BAT2VLT_EN |
| `OSD3_BAT2_VLT_X` | — | 0.00 | — | BAT2VLT_X |
| `OSD3_BAT2_VLT_Y` | — | 0.00 | — | BAT2VLT_Y |
| `OSD3_BATTBAR_EN` | `OSD_SYMBOLS` | 0.33 | — | BATT_BAR_EN |
| `OSD3_BATTBAR_X` | — | 0.00 | — | BATT_BAR_X |
| `OSD3_BATTBAR_Y` | — | 0.00 | — | BATT_BAR_Y |
| `OSD3_BATUSED_EN` | `OSD_SYMBOLS` | 0.33 | — | BATUSED_EN |
| `OSD3_BATUSED_X` | — | 0.00 | — | BATUSED_X |
| `OSD3_BATUSED_Y` | — | 0.00 | — | BATUSED_Y |
| `OSD3_BAT_VOLT_EN` | — | 0.00 | — | BATVOLT_EN |
| `OSD3_BAT_VOLT_X` | — | 0.00 | — | BATVOLT_X |
| `OSD3_BAT_VOLT_Y` | — | 0.00 | — | BATVOLT_Y |
| `OSD3_BTEMP_EN` | `OSD_SYMBOLS` | 0.33 | — | BTEMP_EN |
| `OSD3_BTEMP_X` | — | 0.00 | — | BTEMP_X |
| `OSD3_BTEMP_Y` | — | 0.00 | — | BTEMP_Y |
| `OSD3_CALLSIGN_EN` | `OSD_SYMBOLS` | 0.33 | — | CALLSIGN_EN |
| `OSD3_CALLSIGN_X` | — | 0.00 | — | CALLSIGN_X |
| `OSD3_CALLSIGN_Y` | — | 0.00 | — | CALLSIGN_Y |
| `OSD3_CELLVOLT_EN` | `OSD_SYMBOLS` | 0.33 | — | CELL_VOLT_EN |
| `OSD3_CELLVOLT_X` | — | 0.00 | — | CELL_VOLT_X |
| `OSD3_CELLVOLT_Y` | — | 0.00 | — | CELL_VOLT_Y |
| `OSD3_CHAN_MAX` | — | 0.00 | — | Transmitter switch screen maximum pwm |
| `OSD3_CHAN_MIN` | — | 0.00 | — | Transmitter switch screen minimum pwm |
| `OSD3_CLIMBEFF_EN` | `OSD_SYMBOLS` | 0.33 | — | CLIMBEFF_EN |
| `OSD3_CLIMBEFF_X` | — | 0.00 | — | CLIMBEFF_X |
| `OSD3_CLIMBEFF_Y` | — | 0.00 | — | CLIMBEFF_Y |
| `OSD3_CLK_EN` | `OSD_SYMBOLS` | 0.33 | — | CLK_EN |
| `OSD3_CLK_X` | — | 0.00 | — | CLK_X |
| `OSD3_CLK_Y` | — | 0.00 | — | CLK_Y |
| `OSD3_COMPASS_EN` | `OSD_SYMBOLS` | 0.33 | — | COMPASS_EN |
| `OSD3_COMPASS_X` | — | 0.00 | — | COMPASS_X |
| `OSD3_COMPASS_Y` | — | 0.00 | — | COMPASS_Y |
| `OSD3_CRSSHAIR_EN` | `OSD_SYMBOLS` | 0.33 | — | CRSSHAIR_EN |
| `OSD3_CRSSHAIR_X` | — | 0.00 | — | CRSSHAIR_X |
| `OSD3_CRSSHAIR_Y` | — | 0.00 | — | CRSSHAIR_Y |
| `OSD3_CURRENT2_EN` | `OSD_SYMBOLS` | 0.33 | — | CURRENT2_EN |
| `OSD3_CURRENT2_X` | — | 0.00 | — | CURRENT2_X |
| `OSD3_CURRENT2_Y` | — | 0.00 | — | CURRENT2_Y |
| `OSD3_CURRENT_EN` | `OSD_SYMBOLS` | 0.33 | — | CURRENT_EN |
| `OSD3_CURRENT_X` | — | 0.00 | — | CURRENT_X |
| `OSD3_CURRENT_Y` | — | 0.00 | — | CURRENT_Y |
| `OSD3_DIST_EN` | `OSD_SYMBOLS` | 0.33 | — | DIST_EN |
| `OSD3_DIST_X` | — | 0.00 | — | DIST_X |
| `OSD3_DIST_Y` | — | 0.00 | — | DIST_Y |
| `OSD3_EFF_EN` | `OSD_SYMBOLS` | 0.33 | — | EFF_EN |
| `OSD3_EFF_X` | — | 0.00 | — | EFF_X |
| `OSD3_EFF_Y` | — | 0.00 | — | EFF_Y |
| `OSD3_ENABLE` | `OSD_SYMBOLS` | 0.50 | — | Enable screen |
| `OSD3_ESCAMPS_EN` | `OSD_SYMBOLS` | 0.33 | — | ESCAMPS_EN |
| `OSD3_ESCAMPS_X` | — | 0.00 | — | ESCAMPS_X |
| `OSD3_ESCAMPS_Y` | — | 0.00 | — | ESCAMPS_Y |
| `OSD3_ESCRPM_EN` | `OSD_SYMBOLS` | 0.33 | — | ESCRPM_EN |
| `OSD3_ESCRPM_X` | — | 0.00 | — | ESCRPM_X |
| `OSD3_ESCRPM_Y` | — | 0.00 | — | ESCRPM_Y |
| `OSD3_ESCTEMP_EN` | `OSD_SYMBOLS` | 0.33 | — | ESCTEMP_EN |
| `OSD3_ESCTEMP_X` | — | 0.00 | — | ESCTEMP_X |
| `OSD3_ESCTEMP_Y` | — | 0.00 | — | ESCTEMP_Y |
| `OSD3_ESC_IDX` | — | 0.00 | — | ESC_IDX |
| `OSD3_FENCE_EN` | `OSD_SYMBOLS` | 0.33 | — | FENCE_EN |
| `OSD3_FENCE_X` | — | 0.00 | — | FENCE_X |
| `OSD3_FENCE_Y` | — | 0.00 | — | FENCE_Y |
| `OSD3_FLTIME_EN` | `OSD_SYMBOLS` | 0.33 | — | FLTIME_EN |
| `OSD3_FLTIME_X` | — | 0.00 | — | FLTIME_X |
| `OSD3_FLTIME_Y` | — | 0.00 | — | FLTIME_Y |
| `OSD3_FLTMODE_EN` | `OSD_SYMBOLS` | 0.33 | — | FLTMODE_EN |
| `OSD3_FLTMODE_X` | — | 0.00 | — | FLTMODE_X |
| `OSD3_FLTMODE_Y` | — | 0.00 | — | FLTMODE_Y |
| `OSD3_FONT` | `OSD_SYMBOLS` | 0.33 | — | Sets the font index for this screen (MSP DisplayPort only) |
| `OSD3_GPSLAT_EN` | `OSD_SYMBOLS` | 0.33 | — | GPSLAT_EN |
| `OSD3_GPSLAT_X` | — | 0.00 | — | GPSLAT_X |
| `OSD3_GPSLAT_Y` | — | 0.00 | — | GPSLAT_Y |
| `OSD3_GPSLONG_EN` | `OSD_SYMBOLS` | 0.33 | — | GPSLONG_EN |
| `OSD3_GPSLONG_X` | — | 0.00 | — | GPSLONG_X |
| `OSD3_GPSLONG_Y` | — | 0.00 | — | GPSLONG_Y |
| `OSD3_GSPEED_EN` | `OSD_SYMBOLS` | 0.33 | — | GSPEED_EN |
| `OSD3_GSPEED_X` | — | 0.00 | — | GSPEED_X |
| `OSD3_GSPEED_Y` | — | 0.00 | — | GSPEED_Y |
| `OSD3_HDOP_EN` | `OSD_SYMBOLS` | 0.33 | — | HDOP_EN |
| `OSD3_HDOP_X` | — | 0.00 | — | HDOP_X |
| `OSD3_HDOP_Y` | — | 0.00 | — | HDOP_Y |
| `OSD3_HEADING_EN` | `OSD_SYMBOLS` | 0.33 | — | HEADING_EN |
| `OSD3_HEADING_X` | — | 0.00 | — | HEADING_X |
| `OSD3_HEADING_Y` | — | 0.00 | — | HEADING_Y |
| `OSD3_HOMEDIR_EN` | `OSD_SYMBOLS` | 0.33 | — | HOMEDIR_EN |
| `OSD3_HOMEDIR_X` | — | 0.00 | — | HOMEDIR_X |
| `OSD3_HOMEDIR_Y` | — | 0.00 | — | HOMEDIR_Y |
| `OSD3_HOMEDIST_EN` | `OSD_SYMBOLS` | 0.33 | — | HOMEDIST_EN |
| `OSD3_HOMEDIST_X` | — | 0.00 | — | HOMEDIST_X |
| `OSD3_HOMEDIST_Y` | — | 0.00 | — | HOMEDIST_Y |
| `OSD3_HOME_EN` | `OSD_SYMBOLS` | 0.33 | — | HOME_EN |
| `OSD3_HOME_X` | — | 0.00 | — | HOME_X |
| `OSD3_HOME_Y` | — | 0.00 | — | HOME_Y |
| `OSD3_HORIZON_EN` | `OSD_SYMBOLS` | 0.33 | — | HORIZON_EN |
| `OSD3_HORIZON_X` | — | 0.00 | — | HORIZON_X |
| `OSD3_HORIZON_Y` | — | 0.00 | — | HORIZON_Y |
| `OSD3_LINK_Q_EN` | — | 0.00 | — | LINK_Q_EN |
| `OSD3_LINK_Q_X` | — | 0.00 | — | LINK_Q_X |
| `OSD3_LINK_Q_Y` | — | 0.00 | — | LINK_Q_Y |
| `OSD3_MESSAGE_EN` | `OSD_SYMBOLS` | 0.33 | — | MESSAGE_EN |
| `OSD3_MESSAGE_X` | — | 0.00 | — | MESSAGE_X |
| `OSD3_MESSAGE_Y` | — | 0.00 | — | MESSAGE_Y |
| `OSD3_PITCH_EN` | `OSD_SYMBOLS` | 0.33 | — | PITCH_EN |
| `OSD3_PITCH_X` | — | 0.00 | — | PITCH_X |
| `OSD3_PITCH_Y` | — | 0.00 | — | PITCH_Y |
| `OSD3_PLUSCODE_EN` | `OSD_SYMBOLS` | 0.33 | — | PLUSCODE_EN |
| `OSD3_PLUSCODE_X` | — | 0.00 | — | PLUSCODE_X |
| `OSD3_PLUSCODE_Y` | — | 0.00 | — | PLUSCODE_Y |
| `OSD3_POWER_EN` | `OSD_SYMBOLS` | 0.33 | — | POWER_EN |
| `OSD3_POWER_X` | — | 0.00 | — | POWER_X |
| `OSD3_POWER_Y` | — | 0.00 | — | POWER_Y |
| `OSD3_RC_ANT_EN` | `OSD_RC_STICK` | 0.50 | — | RC_ANT_EN |
| `OSD3_RC_ANT_X` | `OSD_RC_STICK` | 0.40 | — | RC_ANT_X |
| `OSD3_RC_ANT_Y` | `OSD_RC_STICK` | 0.40 | — | RC_ANT_Y |
| `OSD3_RC_LQ_EN` | `OSD_RC_STICK` | 0.50 | — | RC_LQ_EN |
| `OSD3_RC_LQ_X` | `OSD_RC_STICK` | 0.40 | — | RC_LQ_X |
| `OSD3_RC_LQ_Y` | `OSD_RC_STICK` | 0.40 | — | RC_LQ_Y |
| `OSD3_RC_PWR_EN` | `OSD_RC_STICK` | 0.50 | — | RC_PWR_EN |
| `OSD3_RC_PWR_X` | `OSD_RC_STICK` | 0.40 | — | RC_PWR_X |
| `OSD3_RC_PWR_Y` | `OSD_RC_STICK` | 0.40 | — | RC_PWR_Y |
| `OSD3_RC_SNR_EN` | `OSD_RC_STICK` | 0.50 | — | RC_SNR_EN |
| `OSD3_RC_SNR_X` | `OSD_RC_STICK` | 0.40 | — | RC_SNR_X |
| `OSD3_RC_SNR_Y` | `OSD_RC_STICK` | 0.40 | — | RC_SNR_Y |
| `OSD3_RESTVOLT_EN` | `OSD_SYMBOLS` | 0.33 | — | RESTVOLT_EN |
| `OSD3_RESTVOLT_X` | — | 0.00 | — | RESTVOLT_X |
| `OSD3_RESTVOLT_Y` | — | 0.00 | — | RESTVOLT_Y |
| `OSD3_RNGF_EN` | `OSD_SYMBOLS` | 0.33 | — | RNGF_EN |
| `OSD3_RNGF_X` | — | 0.00 | — | RNGF_X |
| `OSD3_RNGF_Y` | — | 0.00 | — | RNGF_Y |
| `OSD3_ROLL_EN` | `OSD_SYMBOLS` | 0.33 | — | ROLL_EN |
| `OSD3_ROLL_X` | — | 0.00 | — | ROLL_X |
| `OSD3_ROLL_Y` | — | 0.00 | — | ROLL_Y |
| `OSD3_RPM_EN` | `RPM_CAP_ENABLE` | 0.33 | — | RPM_EN |
| `OSD3_RPM_X` | — | 0.00 | — | RPM_X |
| `OSD3_RPM_Y` | — | 0.00 | — | RPM_Y |
| `OSD3_RSSIDBM_EN` | `OSD_SYMBOLS` | 0.33 | — | RSSIDBM_EN |
| `OSD3_RSSIDBM_X` | — | 0.00 | — | RSSIDBM_X |
| `OSD3_RSSIDBM_Y` | — | 0.00 | — | RSSIDBM_Y |
| `OSD3_RSSI_EN` | `OSD_SYMBOLS` | 0.33 | — | RSSI_EN |
| `OSD3_RSSI_X` | — | 0.00 | — | RSSI_X |
| `OSD3_RSSI_Y` | — | 0.00 | — | RSSI_Y |
| `OSD3_SATS_EN` | `OSD_SYMBOLS` | 0.33 | — | SATS_EN |
| `OSD3_SATS_X` | — | 0.00 | — | SATS_X |
| `OSD3_SATS_Y` | — | 0.00 | — | SATS_Y |
| `OSD3_SIDEBARS_EN` | `OSD_SYMBOLS` | 0.33 | — | SIDEBARS_EN |
| `OSD3_SIDEBARS_X` | — | 0.00 | — | SIDEBARS_X |
| `OSD3_SIDEBARS_Y` | — | 0.00 | — | SIDEBARS_Y |
| `OSD3_STATS_EN` | `OSD_SYMBOLS` | 0.33 | — | STATS_EN |
| `OSD3_STATS_X` | — | 0.00 | — | STATS_X |
| `OSD3_STATS_Y` | — | 0.00 | — | STATS_Y |
| `OSD3_TEMP_EN` | `OSD_SYMBOLS` | 0.33 | — | TEMP_EN |
| `OSD3_TEMP_X` | — | 0.00 | — | TEMP_X |
| `OSD3_TEMP_Y` | — | 0.00 | — | TEMP_Y |
| `OSD3_TER_HGT_EN` | — | 0.00 | — | TER_HGT_EN |
| `OSD3_TER_HGT_X` | — | 0.00 | — | TER_HGT_X |
| `OSD3_TER_HGT_Y` | — | 0.00 | — | TER_HGT_Y |
| `OSD3_THROTTLE_EN` | `OSD_SYMBOLS` | 0.33 | — | THROTTLE_EN |
| `OSD3_THROTTLE_X` | — | 0.00 | — | THROTTLE_X |
| `OSD3_THROTTLE_Y` | — | 0.00 | — | THROTTLE_Y |
| `OSD3_TXT_RES` | — | 0.00 | — | Sets the overlay text resolution (MSP DisplayPort only) |
| `OSD3_VSPEED_EN` | `OSD_SYMBOLS` | 0.33 | — | VSPEED_EN |
| `OSD3_VSPEED_X` | — | 0.00 | — | VSPEED_X |
| `OSD3_VSPEED_Y` | — | 0.00 | — | VSPEED_Y |
| `OSD3_VTX_PWR_EN` | — | 0.00 | — | VTX_PWR_EN |
| `OSD3_VTX_PWR_X` | — | 0.00 | — | VTX_PWR_X |
| `OSD3_VTX_PWR_Y` | — | 0.00 | — | VTX_PWR_Y |
| `OSD3_WAYPOINT_EN` | `OSD_SYMBOLS` | 0.33 | — | WAYPOINT_EN |
| `OSD3_WAYPOINT_X` | — | 0.00 | — | WAYPOINT_X |
| `OSD3_WAYPOINT_Y` | — | 0.00 | — | WAYPOINT_Y |
| `OSD3_WIND_EN` | `OSD_SYMBOLS` | 0.33 | — | WIND_EN |
| `OSD3_WIND_X` | — | 0.00 | — | WIND_X |
| `OSD3_WIND_Y` | — | 0.00 | — | WIND_Y |
| `OSD3_XTRACK_EN` | `OSD_SYMBOLS` | 0.33 | — | XTRACK_EN |
| `OSD3_XTRACK_X` | — | 0.00 | — | XTRACK_X |
| `OSD3_XTRACK_Y` | — | 0.00 | — | XTRACK_Y |
| `OSD4_ACRVOLT_EN` | `OSD_SYMBOLS` | 0.33 | — | ACRVOLT_EN |
| `OSD4_ACRVOLT_X` | — | 0.00 | — | ACRVOLT_X |
| `OSD4_ACRVOLT_Y` | — | 0.00 | — | ACRVOLT_Y |
| `OSD4_ALTITUDE_EN` | `OSD_SYMBOLS` | 0.33 | — | ALTITUDE_EN |
| `OSD4_ALTITUDE_X` | — | 0.00 | — | ALTITUDE_X |
| `OSD4_ALTITUDE_Y` | — | 0.00 | — | ALTITUDE_Y |
| `OSD4_ARMING_EN` | `OSD_SYMBOLS` | 0.33 | — | ARMING_EN |
| `OSD4_ARMING_X` | — | 0.00 | — | ARMING_X |
| `OSD4_ARMING_Y` | — | 0.00 | — | ARMING_Y |
| `OSD4_ASPD1_EN` | `ASPD_PRIMARY` | 0.33 | — | ASPD1_EN |
| `OSD4_ASPD1_X` | — | 0.00 | — | ASPD1_X |
| `OSD4_ASPD1_Y` | — | 0.00 | — | ASPD1_Y |
| `OSD4_ASPD2_EN` | `ASPD_PRIMARY` | 0.33 | — | ASPD2_EN |
| `OSD4_ASPD2_X` | — | 0.00 | — | ASPD2_X |
| `OSD4_ASPD2_Y` | — | 0.00 | — | ASPD2_Y |
| `OSD4_ASPEED_EN` | `OSD_SYMBOLS` | 0.33 | — | ASPEED_EN |
| `OSD4_ASPEED_X` | — | 0.00 | — | ASPEED_X |
| `OSD4_ASPEED_Y` | — | 0.00 | — | ASPEED_Y |
| `OSD4_ATEMP_EN` | `OSD_SYMBOLS` | 0.33 | — | ATEMP_EN |
| `OSD4_ATEMP_X` | — | 0.00 | — | ATEMP_X |
| `OSD4_ATEMP_Y` | — | 0.00 | — | ATEMP_Y |
| `OSD4_AVGCELLV_EN` | `OSD_SYMBOLS` | 0.33 | — | AVGCELLV_EN |
| `OSD4_AVGCELLV_X` | — | 0.00 | — | AVGCELLV_X |
| `OSD4_AVGCELLV_Y` | — | 0.00 | — | AVGCELLV_Y |
| `OSD4_BAT2USED_EN` | `OSD_SYMBOLS` | 0.33 | — | BAT2USED_EN |
| `OSD4_BAT2USED_X` | — | 0.00 | — | BAT2USED_X |
| `OSD4_BAT2USED_Y` | — | 0.00 | — | BAT2USED_Y |
| `OSD4_BAT2_VLT_EN` | — | 0.00 | — | BAT2VLT_EN |
| `OSD4_BAT2_VLT_X` | — | 0.00 | — | BAT2VLT_X |
| `OSD4_BAT2_VLT_Y` | — | 0.00 | — | BAT2VLT_Y |
| `OSD4_BATTBAR_EN` | `OSD_SYMBOLS` | 0.33 | — | BATT_BAR_EN |
| `OSD4_BATTBAR_X` | — | 0.00 | — | BATT_BAR_X |
| `OSD4_BATTBAR_Y` | — | 0.00 | — | BATT_BAR_Y |
| `OSD4_BATUSED_EN` | `OSD_SYMBOLS` | 0.33 | — | BATUSED_EN |
| `OSD4_BATUSED_X` | — | 0.00 | — | BATUSED_X |
| `OSD4_BATUSED_Y` | — | 0.00 | — | BATUSED_Y |
| `OSD4_BAT_VOLT_EN` | — | 0.00 | — | BATVOLT_EN |
| `OSD4_BAT_VOLT_X` | — | 0.00 | — | BATVOLT_X |
| `OSD4_BAT_VOLT_Y` | — | 0.00 | — | BATVOLT_Y |
| `OSD4_BTEMP_EN` | `OSD_SYMBOLS` | 0.33 | — | BTEMP_EN |
| `OSD4_BTEMP_X` | — | 0.00 | — | BTEMP_X |
| `OSD4_BTEMP_Y` | — | 0.00 | — | BTEMP_Y |
| `OSD4_CALLSIGN_EN` | `OSD_SYMBOLS` | 0.33 | — | CALLSIGN_EN |
| `OSD4_CALLSIGN_X` | — | 0.00 | — | CALLSIGN_X |
| `OSD4_CALLSIGN_Y` | — | 0.00 | — | CALLSIGN_Y |
| `OSD4_CELLVOLT_EN` | `OSD_SYMBOLS` | 0.33 | — | CELL_VOLT_EN |
| `OSD4_CELLVOLT_X` | — | 0.00 | — | CELL_VOLT_X |
| `OSD4_CELLVOLT_Y` | — | 0.00 | — | CELL_VOLT_Y |
| `OSD4_CHAN_MAX` | — | 0.00 | — | Transmitter switch screen maximum pwm |
| `OSD4_CHAN_MIN` | — | 0.00 | — | Transmitter switch screen minimum pwm |
| `OSD4_CLIMBEFF_EN` | `OSD_SYMBOLS` | 0.33 | — | CLIMBEFF_EN |
| `OSD4_CLIMBEFF_X` | — | 0.00 | — | CLIMBEFF_X |
| `OSD4_CLIMBEFF_Y` | — | 0.00 | — | CLIMBEFF_Y |
| `OSD4_CLK_EN` | `OSD_SYMBOLS` | 0.33 | — | CLK_EN |
| `OSD4_CLK_X` | — | 0.00 | — | CLK_X |
| `OSD4_CLK_Y` | — | 0.00 | — | CLK_Y |
| `OSD4_COMPASS_EN` | `OSD_SYMBOLS` | 0.33 | — | COMPASS_EN |
| `OSD4_COMPASS_X` | — | 0.00 | — | COMPASS_X |
| `OSD4_COMPASS_Y` | — | 0.00 | — | COMPASS_Y |
| `OSD4_CRSSHAIR_EN` | `OSD_SYMBOLS` | 0.33 | — | CRSSHAIR_EN |
| `OSD4_CRSSHAIR_X` | — | 0.00 | — | CRSSHAIR_X |
| `OSD4_CRSSHAIR_Y` | — | 0.00 | — | CRSSHAIR_Y |
| `OSD4_CURRENT2_EN` | `OSD_SYMBOLS` | 0.33 | — | CURRENT2_EN |
| `OSD4_CURRENT2_X` | — | 0.00 | — | CURRENT2_X |
| `OSD4_CURRENT2_Y` | — | 0.00 | — | CURRENT2_Y |
| `OSD4_CURRENT_EN` | `OSD_SYMBOLS` | 0.33 | — | CURRENT_EN |
| `OSD4_CURRENT_X` | — | 0.00 | — | CURRENT_X |
| `OSD4_CURRENT_Y` | — | 0.00 | — | CURRENT_Y |
| `OSD4_DIST_EN` | `OSD_SYMBOLS` | 0.33 | — | DIST_EN |
| `OSD4_DIST_X` | — | 0.00 | — | DIST_X |
| `OSD4_DIST_Y` | — | 0.00 | — | DIST_Y |
| `OSD4_EFF_EN` | `OSD_SYMBOLS` | 0.33 | — | EFF_EN |
| `OSD4_EFF_X` | — | 0.00 | — | EFF_X |
| `OSD4_EFF_Y` | — | 0.00 | — | EFF_Y |
| `OSD4_ENABLE` | `OSD_SYMBOLS` | 0.50 | — | Enable screen |
| `OSD4_ESCAMPS_EN` | `OSD_SYMBOLS` | 0.33 | — | ESCAMPS_EN |
| `OSD4_ESCAMPS_X` | — | 0.00 | — | ESCAMPS_X |
| `OSD4_ESCAMPS_Y` | — | 0.00 | — | ESCAMPS_Y |
| `OSD4_ESCRPM_EN` | `OSD_SYMBOLS` | 0.33 | — | ESCRPM_EN |
| `OSD4_ESCRPM_X` | — | 0.00 | — | ESCRPM_X |
| `OSD4_ESCRPM_Y` | — | 0.00 | — | ESCRPM_Y |
| `OSD4_ESCTEMP_EN` | `OSD_SYMBOLS` | 0.33 | — | ESCTEMP_EN |
| `OSD4_ESCTEMP_X` | — | 0.00 | — | ESCTEMP_X |
| `OSD4_ESCTEMP_Y` | — | 0.00 | — | ESCTEMP_Y |
| `OSD4_ESC_IDX` | — | 0.00 | — | ESC_IDX |
| `OSD4_FENCE_EN` | `OSD_SYMBOLS` | 0.33 | — | FENCE_EN |
| `OSD4_FENCE_X` | — | 0.00 | — | FENCE_X |
| `OSD4_FENCE_Y` | — | 0.00 | — | FENCE_Y |
| `OSD4_FLTIME_EN` | `OSD_SYMBOLS` | 0.33 | — | FLTIME_EN |
| `OSD4_FLTIME_X` | — | 0.00 | — | FLTIME_X |
| `OSD4_FLTIME_Y` | — | 0.00 | — | FLTIME_Y |
| `OSD4_FLTMODE_EN` | `OSD_SYMBOLS` | 0.33 | — | FLTMODE_EN |
| `OSD4_FLTMODE_X` | — | 0.00 | — | FLTMODE_X |
| `OSD4_FLTMODE_Y` | — | 0.00 | — | FLTMODE_Y |
| `OSD4_FONT` | `OSD_SYMBOLS` | 0.33 | — | Sets the font index for this screen (MSP DisplayPort only) |
| `OSD4_GPSLAT_EN` | `OSD_SYMBOLS` | 0.33 | — | GPSLAT_EN |
| `OSD4_GPSLAT_X` | — | 0.00 | — | GPSLAT_X |
| `OSD4_GPSLAT_Y` | — | 0.00 | — | GPSLAT_Y |
| `OSD4_GPSLONG_EN` | `OSD_SYMBOLS` | 0.33 | — | GPSLONG_EN |
| `OSD4_GPSLONG_X` | — | 0.00 | — | GPSLONG_X |
| `OSD4_GPSLONG_Y` | — | 0.00 | — | GPSLONG_Y |
| `OSD4_GSPEED_EN` | `OSD_SYMBOLS` | 0.33 | — | GSPEED_EN |
| `OSD4_GSPEED_X` | — | 0.00 | — | GSPEED_X |
| `OSD4_GSPEED_Y` | — | 0.00 | — | GSPEED_Y |
| `OSD4_HDOP_EN` | `OSD_SYMBOLS` | 0.33 | — | HDOP_EN |
| `OSD4_HDOP_X` | — | 0.00 | — | HDOP_X |
| `OSD4_HDOP_Y` | — | 0.00 | — | HDOP_Y |
| `OSD4_HEADING_EN` | `OSD_SYMBOLS` | 0.33 | — | HEADING_EN |
| `OSD4_HEADING_X` | — | 0.00 | — | HEADING_X |
| `OSD4_HEADING_Y` | — | 0.00 | — | HEADING_Y |
| `OSD4_HOMEDIR_EN` | `OSD_SYMBOLS` | 0.33 | — | HOMEDIR_EN |
| `OSD4_HOMEDIR_X` | — | 0.00 | — | HOMEDIR_X |
| `OSD4_HOMEDIR_Y` | — | 0.00 | — | HOMEDIR_Y |
| `OSD4_HOMEDIST_EN` | `OSD_SYMBOLS` | 0.33 | — | HOMEDIST_EN |
| `OSD4_HOMEDIST_X` | — | 0.00 | — | HOMEDIST_X |
| `OSD4_HOMEDIST_Y` | — | 0.00 | — | HOMEDIST_Y |
| `OSD4_HOME_EN` | `OSD_SYMBOLS` | 0.33 | — | HOME_EN |
| `OSD4_HOME_X` | — | 0.00 | — | HOME_X |
| `OSD4_HOME_Y` | — | 0.00 | — | HOME_Y |
| `OSD4_HORIZON_EN` | `OSD_SYMBOLS` | 0.33 | — | HORIZON_EN |
| `OSD4_HORIZON_X` | — | 0.00 | — | HORIZON_X |
| `OSD4_HORIZON_Y` | — | 0.00 | — | HORIZON_Y |
| `OSD4_LINK_Q_EN` | — | 0.00 | — | LINK_Q_EN |
| `OSD4_LINK_Q_X` | — | 0.00 | — | LINK_Q_X |
| `OSD4_LINK_Q_Y` | — | 0.00 | — | LINK_Q_Y |
| `OSD4_MESSAGE_EN` | `OSD_SYMBOLS` | 0.33 | — | MESSAGE_EN |
| `OSD4_MESSAGE_X` | — | 0.00 | — | MESSAGE_X |
| `OSD4_MESSAGE_Y` | — | 0.00 | — | MESSAGE_Y |
| `OSD4_PITCH_EN` | `OSD_SYMBOLS` | 0.33 | — | PITCH_EN |
| `OSD4_PITCH_X` | — | 0.00 | — | PITCH_X |
| `OSD4_PITCH_Y` | — | 0.00 | — | PITCH_Y |
| `OSD4_PLUSCODE_EN` | `OSD_SYMBOLS` | 0.33 | — | PLUSCODE_EN |
| `OSD4_PLUSCODE_X` | — | 0.00 | — | PLUSCODE_X |
| `OSD4_PLUSCODE_Y` | — | 0.00 | — | PLUSCODE_Y |
| `OSD4_POWER_EN` | `OSD_SYMBOLS` | 0.33 | — | POWER_EN |
| `OSD4_POWER_X` | — | 0.00 | — | POWER_X |
| `OSD4_POWER_Y` | — | 0.00 | — | POWER_Y |
| `OSD4_RC_ANT_EN` | `OSD_RC_STICK` | 0.50 | — | RC_ANT_EN |
| `OSD4_RC_ANT_X` | `OSD_RC_STICK` | 0.40 | — | RC_ANT_X |
| `OSD4_RC_ANT_Y` | `OSD_RC_STICK` | 0.40 | — | RC_ANT_Y |
| `OSD4_RC_LQ_EN` | `OSD_RC_STICK` | 0.50 | — | RC_LQ_EN |
| `OSD4_RC_LQ_X` | `OSD_RC_STICK` | 0.40 | — | RC_LQ_X |
| `OSD4_RC_LQ_Y` | `OSD_RC_STICK` | 0.40 | — | RC_LQ_Y |
| `OSD4_RC_PWR_EN` | `OSD_RC_STICK` | 0.50 | — | RC_PWR_EN |
| `OSD4_RC_PWR_X` | `OSD_RC_STICK` | 0.40 | — | RC_PWR_X |
| `OSD4_RC_PWR_Y` | `OSD_RC_STICK` | 0.40 | — | RC_PWR_Y |
| `OSD4_RC_SNR_EN` | `OSD_RC_STICK` | 0.50 | — | RC_SNR_EN |
| `OSD4_RC_SNR_X` | `OSD_RC_STICK` | 0.40 | — | RC_SNR_X |
| `OSD4_RC_SNR_Y` | `OSD_RC_STICK` | 0.40 | — | RC_SNR_Y |
| `OSD4_RESTVOLT_EN` | `OSD_SYMBOLS` | 0.33 | — | RESTVOLT_EN |
| `OSD4_RESTVOLT_X` | — | 0.00 | — | RESTVOLT_X |
| `OSD4_RESTVOLT_Y` | — | 0.00 | — | RESTVOLT_Y |
| `OSD4_RNGF_EN` | `OSD_SYMBOLS` | 0.33 | — | RNGF_EN |
| `OSD4_RNGF_X` | — | 0.00 | — | RNGF_X |
| `OSD4_RNGF_Y` | — | 0.00 | — | RNGF_Y |
| `OSD4_ROLL_EN` | `OSD_SYMBOLS` | 0.33 | — | ROLL_EN |
| `OSD4_ROLL_X` | — | 0.00 | — | ROLL_X |
| `OSD4_ROLL_Y` | — | 0.00 | — | ROLL_Y |
| `OSD4_RPM_EN` | `RPM_CAP_ENABLE` | 0.33 | — | RPM_EN |
| `OSD4_RPM_X` | — | 0.00 | — | RPM_X |
| `OSD4_RPM_Y` | — | 0.00 | — | RPM_Y |
| `OSD4_RSSIDBM_EN` | `OSD_SYMBOLS` | 0.33 | — | RSSIDBM_EN |
| `OSD4_RSSIDBM_X` | — | 0.00 | — | RSSIDBM_X |
| `OSD4_RSSIDBM_Y` | — | 0.00 | — | RSSIDBM_Y |
| `OSD4_RSSI_EN` | `OSD_SYMBOLS` | 0.33 | — | RSSI_EN |
| `OSD4_RSSI_X` | — | 0.00 | — | RSSI_X |
| `OSD4_RSSI_Y` | — | 0.00 | — | RSSI_Y |
| `OSD4_SATS_EN` | `OSD_SYMBOLS` | 0.33 | — | SATS_EN |
| `OSD4_SATS_X` | — | 0.00 | — | SATS_X |
| `OSD4_SATS_Y` | — | 0.00 | — | SATS_Y |
| `OSD4_SIDEBARS_EN` | `OSD_SYMBOLS` | 0.33 | — | SIDEBARS_EN |
| `OSD4_SIDEBARS_X` | — | 0.00 | — | SIDEBARS_X |
| `OSD4_SIDEBARS_Y` | — | 0.00 | — | SIDEBARS_Y |
| `OSD4_STATS_EN` | `OSD_SYMBOLS` | 0.33 | — | STATS_EN |
| `OSD4_STATS_X` | — | 0.00 | — | STATS_X |
| `OSD4_STATS_Y` | — | 0.00 | — | STATS_Y |
| `OSD4_TEMP_EN` | `OSD_SYMBOLS` | 0.33 | — | TEMP_EN |
| `OSD4_TEMP_X` | — | 0.00 | — | TEMP_X |
| `OSD4_TEMP_Y` | — | 0.00 | — | TEMP_Y |
| `OSD4_TER_HGT_EN` | — | 0.00 | — | TER_HGT_EN |
| `OSD4_TER_HGT_X` | — | 0.00 | — | TER_HGT_X |
| `OSD4_TER_HGT_Y` | — | 0.00 | — | TER_HGT_Y |
| `OSD4_THROTTLE_EN` | `OSD_SYMBOLS` | 0.33 | — | THROTTLE_EN |
| `OSD4_THROTTLE_X` | — | 0.00 | — | THROTTLE_X |
| `OSD4_THROTTLE_Y` | — | 0.00 | — | THROTTLE_Y |
| `OSD4_TXT_RES` | — | 0.00 | — | Sets the overlay text resolution (MSP DisplayPort only) |
| `OSD4_VSPEED_EN` | `OSD_SYMBOLS` | 0.33 | — | VSPEED_EN |
| `OSD4_VSPEED_X` | — | 0.00 | — | VSPEED_X |
| `OSD4_VSPEED_Y` | — | 0.00 | — | VSPEED_Y |
| `OSD4_VTX_PWR_EN` | — | 0.00 | — | VTX_PWR_EN |
| `OSD4_VTX_PWR_X` | — | 0.00 | — | VTX_PWR_X |
| `OSD4_VTX_PWR_Y` | — | 0.00 | — | VTX_PWR_Y |
| `OSD4_WAYPOINT_EN` | `OSD_SYMBOLS` | 0.33 | — | WAYPOINT_EN |
| `OSD4_WAYPOINT_X` | — | 0.00 | — | WAYPOINT_X |
| `OSD4_WAYPOINT_Y` | — | 0.00 | — | WAYPOINT_Y |
| `OSD4_WIND_EN` | `OSD_SYMBOLS` | 0.33 | — | WIND_EN |
| `OSD4_WIND_X` | — | 0.00 | — | WIND_X |
| `OSD4_WIND_Y` | — | 0.00 | — | WIND_Y |
| `OSD4_XTRACK_EN` | `OSD_SYMBOLS` | 0.33 | — | XTRACK_EN |
| `OSD4_XTRACK_X` | — | 0.00 | — | XTRACK_X |
| `OSD4_XTRACK_Y` | — | 0.00 | — | XTRACK_Y |
| `OSD5_CHAN_MAX` | — | 0.00 | — | Transmitter switch screen maximum pwm |
| `OSD5_CHAN_MIN` | — | 0.00 | — | Transmitter switch screen minimum pwm |
| `OSD5_ENABLE` | `OSD_SYMBOLS` | 0.50 | — | Enable screen |
| `OSD5_PARAM1_EN` | `OSD_SYMBOLS` | 0.50 | — | Enable |
| `OSD5_PARAM1_GRP` | `OSD_SYMBOLS` | 0.33 | — | Parameter group |
| `OSD5_PARAM1_IDX` | `OSD_SYMBOLS` | 0.33 | — | Parameter index |
| `OSD5_PARAM1_INCR` | `OSD_SYMBOLS` | 0.33 | — | Parameter increment |
| `OSD5_PARAM1_KEY` | `OSD_SYMBOLS` | 0.33 | — | Parameter key |
| `OSD5_PARAM1_MAX` | `OSD_SYMBOLS` | 0.33 | — | Parameter maximum |
| `OSD5_PARAM1_MIN` | `OSD_SYMBOLS` | 0.33 | — | Parameter minimum |
| `OSD5_PARAM1_TYPE` | `OSD_SYMBOLS` | 0.50 | — | Parameter type |
| `OSD5_PARAM1_X` | `OSD_SYMBOLS` | 0.33 | — | X position |
| `OSD5_PARAM1_Y` | `OSD_SYMBOLS` | 0.33 | — | Y position |
| `OSD5_PARAM2_EN` | `OSD_SYMBOLS` | 0.50 | — | Enable |
| `OSD5_PARAM2_GRP` | `OSD_SYMBOLS` | 0.33 | — | Parameter group |
| `OSD5_PARAM2_IDX` | `OSD_SYMBOLS` | 0.33 | — | Parameter index |
| `OSD5_PARAM2_INCR` | `OSD_SYMBOLS` | 0.33 | — | Parameter increment |
| `OSD5_PARAM2_KEY` | `OSD_SYMBOLS` | 0.33 | — | Parameter key |
| `OSD5_PARAM2_MAX` | `OSD_SYMBOLS` | 0.33 | — | Parameter maximum |
| `OSD5_PARAM2_MIN` | `OSD_SYMBOLS` | 0.33 | — | Parameter minimum |
| `OSD5_PARAM2_TYPE` | `OSD_SYMBOLS` | 0.50 | — | Parameter type |
| `OSD5_PARAM2_X` | `OSD_SYMBOLS` | 0.33 | — | X position |
| `OSD5_PARAM2_Y` | `OSD_SYMBOLS` | 0.33 | — | Y position |
| `OSD5_PARAM3_EN` | `OSD_SYMBOLS` | 0.50 | — | Enable |
| `OSD5_PARAM3_GRP` | `OSD_SYMBOLS` | 0.33 | — | Parameter group |
| `OSD5_PARAM3_IDX` | `OSD_SYMBOLS` | 0.33 | — | Parameter index |
| `OSD5_PARAM3_INCR` | `OSD_SYMBOLS` | 0.33 | — | Parameter increment |
| `OSD5_PARAM3_KEY` | `OSD_SYMBOLS` | 0.33 | — | Parameter key |
| `OSD5_PARAM3_MAX` | `OSD_SYMBOLS` | 0.33 | — | Parameter maximum |
| `OSD5_PARAM3_MIN` | `OSD_SYMBOLS` | 0.33 | — | Parameter minimum |
| `OSD5_PARAM3_TYPE` | `OSD_SYMBOLS` | 0.50 | — | Parameter type |
| `OSD5_PARAM3_X` | `OSD_SYMBOLS` | 0.33 | — | X position |
| `OSD5_PARAM3_Y` | `OSD_SYMBOLS` | 0.33 | — | Y position |
| `OSD5_PARAM4_EN` | `OSD_SYMBOLS` | 0.50 | — | Enable |
| `OSD5_PARAM4_GRP` | `OSD_SYMBOLS` | 0.33 | — | Parameter group |
| `OSD5_PARAM4_IDX` | `OSD_SYMBOLS` | 0.33 | — | Parameter index |
| `OSD5_PARAM4_INCR` | `OSD_SYMBOLS` | 0.33 | — | Parameter increment |
| `OSD5_PARAM4_KEY` | `OSD_SYMBOLS` | 0.33 | — | Parameter key |
| `OSD5_PARAM4_MAX` | `OSD_SYMBOLS` | 0.33 | — | Parameter maximum |
| `OSD5_PARAM4_MIN` | `OSD_SYMBOLS` | 0.33 | — | Parameter minimum |
| `OSD5_PARAM4_TYPE` | `OSD_SYMBOLS` | 0.50 | — | Parameter type |
| `OSD5_PARAM4_X` | `OSD_SYMBOLS` | 0.33 | — | X position |
| `OSD5_PARAM4_Y` | `OSD_SYMBOLS` | 0.33 | — | Y position |
| `OSD5_PARAM5_EN` | `OSD_SYMBOLS` | 0.50 | — | Enable |
| `OSD5_PARAM5_GRP` | `OSD_SYMBOLS` | 0.33 | — | Parameter group |
| `OSD5_PARAM5_IDX` | `OSD_SYMBOLS` | 0.33 | — | Parameter index |
| `OSD5_PARAM5_INCR` | `OSD_SYMBOLS` | 0.33 | — | Parameter increment |
| `OSD5_PARAM5_KEY` | `OSD_SYMBOLS` | 0.33 | — | Parameter key |
| `OSD5_PARAM5_MAX` | `OSD_SYMBOLS` | 0.33 | — | Parameter maximum |
| `OSD5_PARAM5_MIN` | `OSD_SYMBOLS` | 0.33 | — | Parameter minimum |
| `OSD5_PARAM5_TYPE` | `OSD_SYMBOLS` | 0.50 | — | Parameter type |
| `OSD5_PARAM5_X` | `OSD_SYMBOLS` | 0.33 | — | X position |
| `OSD5_PARAM5_Y` | `OSD_SYMBOLS` | 0.33 | — | Y position |
| `OSD5_PARAM6_EN` | `OSD_SYMBOLS` | 0.50 | — | Enable |
| `OSD5_PARAM6_GRP` | `OSD_SYMBOLS` | 0.33 | — | Parameter group |
| `OSD5_PARAM6_IDX` | `OSD_SYMBOLS` | 0.33 | — | Parameter index |
| `OSD5_PARAM6_INCR` | `OSD_SYMBOLS` | 0.33 | — | Parameter increment |
| `OSD5_PARAM6_KEY` | `OSD_SYMBOLS` | 0.33 | — | Parameter key |
| `OSD5_PARAM6_MAX` | `OSD_SYMBOLS` | 0.33 | — | Parameter maximum |
| `OSD5_PARAM6_MIN` | `OSD_SYMBOLS` | 0.33 | — | Parameter minimum |
| `OSD5_PARAM6_TYPE` | `OSD_SYMBOLS` | 0.50 | — | Parameter type |
| `OSD5_PARAM6_X` | `OSD_SYMBOLS` | 0.33 | — | X position |
| `OSD5_PARAM6_Y` | `OSD_SYMBOLS` | 0.33 | — | Y position |
| `OSD5_PARAM7_EN` | `OSD_SYMBOLS` | 0.50 | — | Enable |
| `OSD5_PARAM7_GRP` | `OSD_SYMBOLS` | 0.33 | — | Parameter group |
| `OSD5_PARAM7_IDX` | `OSD_SYMBOLS` | 0.33 | — | Parameter index |
| `OSD5_PARAM7_INCR` | `OSD_SYMBOLS` | 0.33 | — | Parameter increment |
| `OSD5_PARAM7_KEY` | `OSD_SYMBOLS` | 0.33 | — | Parameter key |
| `OSD5_PARAM7_MAX` | `OSD_SYMBOLS` | 0.33 | — | Parameter maximum |
| `OSD5_PARAM7_MIN` | `OSD_SYMBOLS` | 0.33 | — | Parameter minimum |
| `OSD5_PARAM7_TYPE` | `OSD_SYMBOLS` | 0.50 | — | Parameter type |
| `OSD5_PARAM7_X` | `OSD_SYMBOLS` | 0.33 | — | X position |
| `OSD5_PARAM7_Y` | `OSD_SYMBOLS` | 0.33 | — | Y position |
| `OSD5_PARAM8_EN` | `OSD_SYMBOLS` | 0.50 | — | Enable |
| `OSD5_PARAM8_GRP` | `OSD_SYMBOLS` | 0.33 | — | Parameter group |
| `OSD5_PARAM8_IDX` | `OSD_SYMBOLS` | 0.33 | — | Parameter index |
| `OSD5_PARAM8_INCR` | `OSD_SYMBOLS` | 0.33 | — | Parameter increment |
| `OSD5_PARAM8_KEY` | `OSD_SYMBOLS` | 0.33 | — | Parameter key |
| `OSD5_PARAM8_MAX` | `OSD_SYMBOLS` | 0.33 | — | Parameter maximum |
| `OSD5_PARAM8_MIN` | `OSD_SYMBOLS` | 0.33 | — | Parameter minimum |
| `OSD5_PARAM8_TYPE` | `OSD_SYMBOLS` | 0.50 | — | Parameter type |
| `OSD5_PARAM8_X` | `OSD_SYMBOLS` | 0.33 | — | X position |
| `OSD5_PARAM8_Y` | `OSD_SYMBOLS` | 0.33 | — | Y position |
| `OSD5_PARAM9_EN` | `OSD_SYMBOLS` | 0.50 | — | Enable |
| `OSD5_PARAM9_GRP` | `OSD_SYMBOLS` | 0.33 | — | Parameter group |
| `OSD5_PARAM9_IDX` | `OSD_SYMBOLS` | 0.33 | — | Parameter index |
| `OSD5_PARAM9_INCR` | `OSD_SYMBOLS` | 0.33 | — | Parameter increment |
| `OSD5_PARAM9_KEY` | `OSD_SYMBOLS` | 0.33 | — | Parameter key |
| `OSD5_PARAM9_MAX` | `OSD_SYMBOLS` | 0.33 | — | Parameter maximum |
| `OSD5_PARAM9_MIN` | `OSD_SYMBOLS` | 0.33 | — | Parameter minimum |
| `OSD5_PARAM9_TYPE` | `OSD_SYMBOLS` | 0.50 | — | Parameter type |
| `OSD5_PARAM9_X` | `OSD_SYMBOLS` | 0.33 | — | X position |
| `OSD5_PARAM9_Y` | `OSD_SYMBOLS` | 0.33 | — | Y position |
| `OSD5_SAVE_X` | — | 0.00 | — | SAVE_X |
| `OSD5_SAVE_Y` | — | 0.00 | — | SAVE_Y |
| `OSD6_CHAN_MAX` | — | 0.00 | — | Transmitter switch screen maximum pwm |
| `OSD6_CHAN_MIN` | — | 0.00 | — | Transmitter switch screen minimum pwm |
| `OSD6_ENABLE` | `OSD_SYMBOLS` | 0.50 | — | Enable screen |
| `OSD6_PARAM1_EN` | `OSD_SYMBOLS` | 0.50 | — | Enable |
| `OSD6_PARAM1_GRP` | `OSD_SYMBOLS` | 0.33 | — | Parameter group |
| `OSD6_PARAM1_IDX` | `OSD_SYMBOLS` | 0.33 | — | Parameter index |
| `OSD6_PARAM1_INCR` | `OSD_SYMBOLS` | 0.33 | — | Parameter increment |
| `OSD6_PARAM1_KEY` | `OSD_SYMBOLS` | 0.33 | — | Parameter key |
| `OSD6_PARAM1_MAX` | `OSD_SYMBOLS` | 0.33 | — | Parameter maximum |
| `OSD6_PARAM1_MIN` | `OSD_SYMBOLS` | 0.33 | — | Parameter minimum |
| `OSD6_PARAM1_TYPE` | `OSD_SYMBOLS` | 0.50 | — | Parameter type |
| `OSD6_PARAM1_X` | `OSD_SYMBOLS` | 0.33 | — | X position |
| `OSD6_PARAM1_Y` | `OSD_SYMBOLS` | 0.33 | — | Y position |
| `OSD6_PARAM2_EN` | `OSD_SYMBOLS` | 0.50 | — | Enable |
| `OSD6_PARAM2_GRP` | `OSD_SYMBOLS` | 0.33 | — | Parameter group |
| `OSD6_PARAM2_IDX` | `OSD_SYMBOLS` | 0.33 | — | Parameter index |
| `OSD6_PARAM2_INCR` | `OSD_SYMBOLS` | 0.33 | — | Parameter increment |
| `OSD6_PARAM2_KEY` | `OSD_SYMBOLS` | 0.33 | — | Parameter key |
| `OSD6_PARAM2_MAX` | `OSD_SYMBOLS` | 0.33 | — | Parameter maximum |
| `OSD6_PARAM2_MIN` | `OSD_SYMBOLS` | 0.33 | — | Parameter minimum |
| `OSD6_PARAM2_TYPE` | `OSD_SYMBOLS` | 0.50 | — | Parameter type |
| `OSD6_PARAM2_X` | `OSD_SYMBOLS` | 0.33 | — | X position |
| `OSD6_PARAM2_Y` | `OSD_SYMBOLS` | 0.33 | — | Y position |
| `OSD6_PARAM3_EN` | `OSD_SYMBOLS` | 0.50 | — | Enable |
| `OSD6_PARAM3_GRP` | `OSD_SYMBOLS` | 0.33 | — | Parameter group |
| `OSD6_PARAM3_IDX` | `OSD_SYMBOLS` | 0.33 | — | Parameter index |
| `OSD6_PARAM3_INCR` | `OSD_SYMBOLS` | 0.33 | — | Parameter increment |
| `OSD6_PARAM3_KEY` | `OSD_SYMBOLS` | 0.33 | — | Parameter key |
| `OSD6_PARAM3_MAX` | `OSD_SYMBOLS` | 0.33 | — | Parameter maximum |
| `OSD6_PARAM3_MIN` | `OSD_SYMBOLS` | 0.33 | — | Parameter minimum |
| `OSD6_PARAM3_TYPE` | `OSD_SYMBOLS` | 0.50 | — | Parameter type |
| `OSD6_PARAM3_X` | `OSD_SYMBOLS` | 0.33 | — | X position |
| `OSD6_PARAM3_Y` | `OSD_SYMBOLS` | 0.33 | — | Y position |
| `OSD6_PARAM4_EN` | `OSD_SYMBOLS` | 0.50 | — | Enable |
| `OSD6_PARAM4_GRP` | `OSD_SYMBOLS` | 0.33 | — | Parameter group |
| `OSD6_PARAM4_IDX` | `OSD_SYMBOLS` | 0.33 | — | Parameter index |
| `OSD6_PARAM4_INCR` | `OSD_SYMBOLS` | 0.33 | — | Parameter increment |
| `OSD6_PARAM4_KEY` | `OSD_SYMBOLS` | 0.33 | — | Parameter key |
| `OSD6_PARAM4_MAX` | `OSD_SYMBOLS` | 0.33 | — | Parameter maximum |
| `OSD6_PARAM4_MIN` | `OSD_SYMBOLS` | 0.33 | — | Parameter minimum |
| `OSD6_PARAM4_TYPE` | `OSD_SYMBOLS` | 0.50 | — | Parameter type |
| `OSD6_PARAM4_X` | `OSD_SYMBOLS` | 0.33 | — | X position |
| `OSD6_PARAM4_Y` | `OSD_SYMBOLS` | 0.33 | — | Y position |
| `OSD6_PARAM5_EN` | `OSD_SYMBOLS` | 0.50 | — | Enable |
| `OSD6_PARAM5_GRP` | `OSD_SYMBOLS` | 0.33 | — | Parameter group |
| `OSD6_PARAM5_IDX` | `OSD_SYMBOLS` | 0.33 | — | Parameter index |
| `OSD6_PARAM5_INCR` | `OSD_SYMBOLS` | 0.33 | — | Parameter increment |
| `OSD6_PARAM5_KEY` | `OSD_SYMBOLS` | 0.33 | — | Parameter key |
| `OSD6_PARAM5_MAX` | `OSD_SYMBOLS` | 0.33 | — | Parameter maximum |
| `OSD6_PARAM5_MIN` | `OSD_SYMBOLS` | 0.33 | — | Parameter minimum |
| `OSD6_PARAM5_TYPE` | `OSD_SYMBOLS` | 0.50 | — | Parameter type |
| `OSD6_PARAM5_X` | `OSD_SYMBOLS` | 0.33 | — | X position |
| `OSD6_PARAM5_Y` | `OSD_SYMBOLS` | 0.33 | — | Y position |
| `OSD6_PARAM6_EN` | `OSD_SYMBOLS` | 0.50 | — | Enable |
| `OSD6_PARAM6_GRP` | `OSD_SYMBOLS` | 0.33 | — | Parameter group |
| `OSD6_PARAM6_IDX` | `OSD_SYMBOLS` | 0.33 | — | Parameter index |
| `OSD6_PARAM6_INCR` | `OSD_SYMBOLS` | 0.33 | — | Parameter increment |
| `OSD6_PARAM6_KEY` | `OSD_SYMBOLS` | 0.33 | — | Parameter key |
| `OSD6_PARAM6_MAX` | `OSD_SYMBOLS` | 0.33 | — | Parameter maximum |
| `OSD6_PARAM6_MIN` | `OSD_SYMBOLS` | 0.33 | — | Parameter minimum |
| `OSD6_PARAM6_TYPE` | `OSD_SYMBOLS` | 0.50 | — | Parameter type |
| `OSD6_PARAM6_X` | `OSD_SYMBOLS` | 0.33 | — | X position |
| `OSD6_PARAM6_Y` | `OSD_SYMBOLS` | 0.33 | — | Y position |
| `OSD6_PARAM7_EN` | `OSD_SYMBOLS` | 0.50 | — | Enable |
| `OSD6_PARAM7_GRP` | `OSD_SYMBOLS` | 0.33 | — | Parameter group |
| `OSD6_PARAM7_IDX` | `OSD_SYMBOLS` | 0.33 | — | Parameter index |
| `OSD6_PARAM7_INCR` | `OSD_SYMBOLS` | 0.33 | — | Parameter increment |
| `OSD6_PARAM7_KEY` | `OSD_SYMBOLS` | 0.33 | — | Parameter key |
| `OSD6_PARAM7_MAX` | `OSD_SYMBOLS` | 0.33 | — | Parameter maximum |
| `OSD6_PARAM7_MIN` | `OSD_SYMBOLS` | 0.33 | — | Parameter minimum |
| `OSD6_PARAM7_TYPE` | `OSD_SYMBOLS` | 0.50 | — | Parameter type |
| `OSD6_PARAM7_X` | `OSD_SYMBOLS` | 0.33 | — | X position |
| `OSD6_PARAM7_Y` | `OSD_SYMBOLS` | 0.33 | — | Y position |
| `OSD6_PARAM8_EN` | `OSD_SYMBOLS` | 0.50 | — | Enable |
| `OSD6_PARAM8_GRP` | `OSD_SYMBOLS` | 0.33 | — | Parameter group |
| `OSD6_PARAM8_IDX` | `OSD_SYMBOLS` | 0.33 | — | Parameter index |
| `OSD6_PARAM8_INCR` | `OSD_SYMBOLS` | 0.33 | — | Parameter increment |
| `OSD6_PARAM8_KEY` | `OSD_SYMBOLS` | 0.33 | — | Parameter key |
| `OSD6_PARAM8_MAX` | `OSD_SYMBOLS` | 0.33 | — | Parameter maximum |
| `OSD6_PARAM8_MIN` | `OSD_SYMBOLS` | 0.33 | — | Parameter minimum |
| `OSD6_PARAM8_TYPE` | `OSD_SYMBOLS` | 0.50 | — | Parameter type |
| `OSD6_PARAM8_X` | `OSD_SYMBOLS` | 0.33 | — | X position |
| `OSD6_PARAM8_Y` | `OSD_SYMBOLS` | 0.33 | — | Y position |
| `OSD6_PARAM9_EN` | `OSD_SYMBOLS` | 0.50 | — | Enable |
| `OSD6_PARAM9_GRP` | `OSD_SYMBOLS` | 0.33 | — | Parameter group |
| `OSD6_PARAM9_IDX` | `OSD_SYMBOLS` | 0.33 | — | Parameter index |
| `OSD6_PARAM9_INCR` | `OSD_SYMBOLS` | 0.33 | — | Parameter increment |
| `OSD6_PARAM9_KEY` | `OSD_SYMBOLS` | 0.33 | — | Parameter key |
| `OSD6_PARAM9_MAX` | `OSD_SYMBOLS` | 0.33 | — | Parameter maximum |
| `OSD6_PARAM9_MIN` | `OSD_SYMBOLS` | 0.33 | — | Parameter minimum |
| `OSD6_PARAM9_TYPE` | `OSD_SYMBOLS` | 0.50 | — | Parameter type |
| `OSD6_PARAM9_X` | `OSD_SYMBOLS` | 0.33 | — | X position |
| `OSD6_PARAM9_Y` | `OSD_SYMBOLS` | 0.33 | — | Y position |
| `OSD6_SAVE_X` | — | 0.00 | — | SAVE_X |
| `OSD6_SAVE_Y` | — | 0.00 | — | SAVE_Y |
| `OSD_ARM_SCR` | `OSD_SYMBOLS` | 0.37 | — | Arm screen |
| `OSD_BTN_DELAY` | `OSD_SYMBOLS` | 0.37 | — | Button delay |
| `OSD_CELL_COUNT` | `OSD_SYMBOLS` | 0.37 | — | Battery cell count |
| `OSD_CHAN` | `OSD_SYMBOLS` | 0.45 | — | Screen switch transmitter channel |
| `OSD_DSARM_SCR` | `OSD_SYMBOLS` | 0.37 | — | Disarm screen |
| `OSD_FONT` | `OSD_SYMBOLS` | 0.45 | — | OSD Font |
| `OSD_FS_SCR` | `OSD_SYMBOLS` | 0.37 | — | Failsafe screen |
| `OSD_H_OFFSET` | `OSD_SYMBOLS` | 0.37 | — | OSD horizontal offset |
| `OSD_MSG_TIME` | `OSD_DWELL_TIME` | 0.62 | — | Message display duration in seconds |
| `OSD_OPTIONS` | `OSD_SYMBOLS` | 0.45 | — | OSD Options |
| `OSD_SB_H_OFS` | `OSD_SYMBOLS` | 0.32 | — | Sidebar horizontal offset |
| `OSD_SB_V_EXT` | `OSD_SYMBOLS` | 0.32 | — | Sidebar vertical extension |
| `OSD_SW_METHOD` | `OSD_SYMBOLS` | 0.37 | — | Screen switch method |
| `OSD_TYPE` | `OSD_SYMBOLS` | 0.62 | — | OSD type |
| `OSD_TYPE2` | `OSD_SYMBOLS` | 0.62 | — | OSD type 2 |
| `OSD_UNITS` | `OSD_SYMBOLS` | 0.45 | — | Display Units |
| `OSD_V_OFFSET` | `OSD_SYMBOLS` | 0.37 | — | OSD vertical offset |
| `OSD_W_ACRVOLT` | `OSD_SYMBOLS` | 0.37 | — | Avg Cell Resting Volt warn level |
| `OSD_W_AVGCELLV` | `OSD_SYMBOLS` | 0.37 | — | AVGCELLV warn level |
| `OSD_W_BATVOLT` | `OSD_SYMBOLS` | 0.37 | — | BAT_VOLT warn level |
| `OSD_W_LQ` | `OSD_SYMBOLS` | 0.37 | — | RC link quality warn level (in %) |
| `OSD_W_NSAT` | `OSD_SYMBOLS` | 0.37 | — | NSAT warn level |
| `OSD_W_RESTVOLT` | `OSD_SYMBOLS` | 0.37 | — | RESTVOLT warn level |
| `OSD_W_RSSI` | `OSD_SYMBOLS` | 0.37 | — | RSSI warn level (in %) |
| `OSD_W_SNR` | `OSD_SYMBOLS` | 0.37 | — | RC link SNR warn level (in %) |
| `OSD_W_TERR` | `OSD_SYMBOLS` | 0.37 | m | Terrain warn level |
| `PHLD_BRAKE_ANGLE` | — | 0.00 | cdeg | PosHold braking angle max |
| `PHLD_BRAKE_RATE` | — | 0.00 | deg/s | PosHold braking rate |
| `PILOT_ACCEL_Z` | — | 0.00 | cm/s/s | Pilot vertical acceleration |
| `PILOT_SPEED_DN` | — | 0.00 | cm/s | Pilot maximum vertical speed descending |
| `PILOT_SPEED_UP` | — | 0.00 | cm/s | Pilot maximum vertical speed ascending |
| `PILOT_THR_BHV` | — | 0.00 | — | Throttle stick behavior |
| `PILOT_THR_FILT` | — | 0.00 | Hz | Throttle filter cutoff |
| `PILOT_TKOFF_ALT` | — | 0.00 | cm | Pilot takeoff altitude |
| `PILOT_Y_EXPO` | — | 0.00 | — | Pilot controlled yaw expo |
| `PILOT_Y_RATE` | — | 0.00 | deg/s | Pilot controlled yaw rate |
| `PILOT_Y_RATE_TC` | — | 0.00 | s | Pilot yaw rate control input time constant |
| `PLDP_DELAY` | — | 0.00 | s | Payload Place climb delay |
| `PLDP_RNG_MAX` | — | 0.00 | m | Payload Place maximum range finder altitude |
| `PLDP_SPEED_DN` | — | 0.00 | m/s | Payload Place decent speed |
| `PLDP_THRESH` | — | 0.00 | — | Payload Place thrust ratio threshold |
| `PLND_ACC_P_NSE` | — | 0.00 | — | Kalman Filter Accelerometer Noise |
| `PLND_ALT_CUTOFF` | — | 0.00 | m | Precland altitude cutoff |
| `PLND_ALT_MAX` | — | 0.00 | m | PrecLand maximum alt for retry |
| `PLND_ALT_MIN` | — | 0.00 | m | PrecLand minimum alt for retry |
| `PLND_BUS` | — | 0.00 | — | Sensor Bus |
| `PLND_CAM_POS_X` | — | 0.00 | m | Camera X position offset |
| `PLND_CAM_POS_Y` | — | 0.00 | m | Camera Y position offset |
| `PLND_CAM_POS_Z` | — | 0.00 | m | Camera Z position offset |
| `PLND_ENABLED` | — | 0.00 | — | Precision Land enabled/disabled |
| `PLND_EST_TYPE` | — | 0.00 | — | Precision Land Estimator Type |
| `PLND_LAG` | — | 0.00 | s | Precision Landing sensor lag |
| `PLND_LAND_OFS_X` | — | 0.00 | cm | Land offset forward |
| `PLND_LAND_OFS_Y` | — | 0.00 | cm | Land offset right |
| `PLND_OPTIONS` | — | 0.00 | — | Precision Landing Extra Options |
| `PLND_ORIENT` | — | 0.00 | — | Camera Orientation |
| `PLND_RET_BEHAVE` | — | 0.00 | — | PrecLand retry behaviour |
| `PLND_RET_MAX` | — | 0.00 | — | PrecLand Maximum number of retires for a failed landing |
| `PLND_STRICT` | — | 0.00 | — | PrecLand strictness |
| `PLND_TIMEOUT` | — | 0.00 | s | PrecLand retry timeout |
| `PLND_TYPE` | — | 0.00 | — | Precision Land Type |
| `PLND_XY_DIST_MAX` | — | 0.00 | m | Precision Landing maximum distance to target before descending |
| `PLND_YAW_ALIGN` | — | 0.00 | cdeg | Sensor yaw alignment |
| `POI_DIST_MAX` | — | 0.00 | — | Mount POI distance max |
| `PREV_ENABLE` | — | 0.00 | — | parameter reversion enable |
| `PREV_RC_FUNC` | — | 0.00 | — | param reversion RC function |
| `PRX1_ADDR` | — | 0.00 | — | Bus address of sensor |
| `PRX1_IGN_ANG1` | — | 0.00 | deg | Proximity sensor ignore angle 1 |
| `PRX1_IGN_ANG2` | — | 0.00 | deg | Proximity sensor ignore angle 2 |
| `PRX1_IGN_ANG3` | — | 0.00 | deg | Proximity sensor ignore angle 3 |
| `PRX1_IGN_ANG4` | — | 0.00 | deg | Proximity sensor ignore angle 4 |
| `PRX1_IGN_WID1` | — | 0.00 | deg | Proximity sensor ignore width 1 |
| `PRX1_IGN_WID2` | — | 0.00 | deg | Proximity sensor ignore width 2 |
| `PRX1_IGN_WID3` | — | 0.00 | deg | Proximity sensor ignore width 3 |
| `PRX1_IGN_WID4` | — | 0.00 | deg | Proximity sensor ignore width 4 |
| `PRX1_MAX` | — | 0.00 | m | Proximity maximum range |
| `PRX1_MIN` | — | 0.00 | m | Proximity minimum range |
| `PRX1_ORIENT` | — | 0.00 | — | Proximity sensor orientation |
| `PRX1_RECV_ID` | — | 0.00 | — | CAN receive ID |
| `PRX1_TYPE` | — | 0.00 | — | Proximity type |
| `PRX1_YAW_CORR` | — | 0.00 | deg | Proximity sensor yaw correction |
| `PRX2_ADDR` | — | 0.00 | — | Bus address of sensor |
| `PRX2_IGN_ANG1` | — | 0.00 | deg | Proximity sensor ignore angle 1 |
| `PRX2_IGN_ANG2` | — | 0.00 | deg | Proximity sensor ignore angle 2 |
| `PRX2_IGN_ANG3` | — | 0.00 | deg | Proximity sensor ignore angle 3 |
| `PRX2_IGN_ANG4` | — | 0.00 | deg | Proximity sensor ignore angle 4 |
| `PRX2_IGN_WID1` | — | 0.00 | deg | Proximity sensor ignore width 1 |
| `PRX2_IGN_WID2` | — | 0.00 | deg | Proximity sensor ignore width 2 |
| `PRX2_IGN_WID3` | — | 0.00 | deg | Proximity sensor ignore width 3 |
| `PRX2_IGN_WID4` | — | 0.00 | deg | Proximity sensor ignore width 4 |
| `PRX2_MAX` | — | 0.00 | m | Proximity maximum range |
| `PRX2_MIN` | — | 0.00 | m | Proximity minimum range |
| `PRX2_ORIENT` | — | 0.00 | — | Proximity sensor orientation |
| `PRX2_RECV_ID` | — | 0.00 | — | CAN receive ID |
| `PRX2_TYPE` | — | 0.00 | — | Proximity type |
| `PRX2_YAW_CORR` | — | 0.00 | deg | Proximity sensor yaw correction |
| `PRX3_ADDR` | — | 0.00 | — | Bus address of sensor |
| `PRX3_IGN_ANG1` | — | 0.00 | deg | Proximity sensor ignore angle 1 |
| `PRX3_IGN_ANG2` | — | 0.00 | deg | Proximity sensor ignore angle 2 |
| `PRX3_IGN_ANG3` | — | 0.00 | deg | Proximity sensor ignore angle 3 |
| `PRX3_IGN_ANG4` | — | 0.00 | deg | Proximity sensor ignore angle 4 |
| `PRX3_IGN_WID1` | — | 0.00 | deg | Proximity sensor ignore width 1 |
| `PRX3_IGN_WID2` | — | 0.00 | deg | Proximity sensor ignore width 2 |
| `PRX3_IGN_WID3` | — | 0.00 | deg | Proximity sensor ignore width 3 |
| `PRX3_IGN_WID4` | — | 0.00 | deg | Proximity sensor ignore width 4 |
| `PRX3_MAX` | — | 0.00 | m | Proximity maximum range |
| `PRX3_MIN` | — | 0.00 | m | Proximity minimum range |
| `PRX3_ORIENT` | — | 0.00 | — | Proximity sensor orientation |
| `PRX3_RECV_ID` | — | 0.00 | — | CAN receive ID |
| `PRX3_TYPE` | — | 0.00 | — | Proximity type |
| `PRX3_YAW_CORR` | — | 0.00 | deg | Proximity sensor yaw correction |
| `PRX4_ADDR` | — | 0.00 | — | Bus address of sensor |
| `PRX4_IGN_ANG1` | — | 0.00 | deg | Proximity sensor ignore angle 1 |
| `PRX4_IGN_ANG2` | — | 0.00 | deg | Proximity sensor ignore angle 2 |
| `PRX4_IGN_ANG3` | — | 0.00 | deg | Proximity sensor ignore angle 3 |
| `PRX4_IGN_ANG4` | — | 0.00 | deg | Proximity sensor ignore angle 4 |
| `PRX4_IGN_WID1` | — | 0.00 | deg | Proximity sensor ignore width 1 |
| `PRX4_IGN_WID2` | — | 0.00 | deg | Proximity sensor ignore width 2 |
| `PRX4_IGN_WID3` | — | 0.00 | deg | Proximity sensor ignore width 3 |
| `PRX4_IGN_WID4` | — | 0.00 | deg | Proximity sensor ignore width 4 |
| `PRX4_MAX` | — | 0.00 | m | Proximity maximum range |
| `PRX4_MIN` | — | 0.00 | m | Proximity minimum range |
| `PRX4_ORIENT` | — | 0.00 | — | Proximity sensor orientation |
| `PRX4_RECV_ID` | — | 0.00 | — | CAN receive ID |
| `PRX4_TYPE` | — | 0.00 | — | Proximity type |
| `PRX4_YAW_CORR` | — | 0.00 | deg | Proximity sensor yaw correction |
| `PRX5_ADDR` | — | 0.00 | — | Bus address of sensor |
| `PRX5_IGN_ANG1` | — | 0.00 | deg | Proximity sensor ignore angle 1 |
| `PRX5_IGN_ANG2` | — | 0.00 | deg | Proximity sensor ignore angle 2 |
| `PRX5_IGN_ANG3` | — | 0.00 | deg | Proximity sensor ignore angle 3 |
| `PRX5_IGN_ANG4` | — | 0.00 | deg | Proximity sensor ignore angle 4 |
| `PRX5_IGN_WID1` | — | 0.00 | deg | Proximity sensor ignore width 1 |
| `PRX5_IGN_WID2` | — | 0.00 | deg | Proximity sensor ignore width 2 |
| `PRX5_IGN_WID3` | — | 0.00 | deg | Proximity sensor ignore width 3 |
| `PRX5_IGN_WID4` | — | 0.00 | deg | Proximity sensor ignore width 4 |
| `PRX5_MAX` | — | 0.00 | m | Proximity maximum range |
| `PRX5_MIN` | — | 0.00 | m | Proximity minimum range |
| `PRX5_ORIENT` | — | 0.00 | — | Proximity sensor orientation |
| `PRX5_RECV_ID` | — | 0.00 | — | CAN receive ID |
| `PRX5_TYPE` | — | 0.00 | — | Proximity type |
| `PRX5_YAW_CORR` | — | 0.00 | deg | Proximity sensor yaw correction |
| `PRX_ALT_MIN` | — | 0.00 | m | Proximity lowest altitude. |
| `PRX_FILT` | — | 0.00 | Hz | Proximity filter cutoff frequency |
| `PRX_IGN_GND` | — | 0.00 | — | Proximity sensor land detection |
| `PRX_LOG_RAW` | — | 0.00 | — | Proximity raw distances log |
| `PSC_ACCZ_D` | — | 0.00 | — | Acceleration (vertical) controller D gain |
| `PSC_ACCZ_D_FF` | — | 0.00 | — | Accel (vertical) Derivative FeedForward Gain |
| `PSC_ACCZ_FF` | — | 0.00 | — | Acceleration (vertical) controller feed forward |
| `PSC_ACCZ_FLTD` | — | 0.00 | Hz | Acceleration (vertical) controller derivative frequency in Hz |
| `PSC_ACCZ_FLTE` | — | 0.00 | Hz | Acceleration (vertical) controller error frequency in Hz |
| `PSC_ACCZ_FLTT` | — | 0.00 | Hz | Acceleration (vertical) controller target frequency in Hz |
| `PSC_ACCZ_I` | — | 0.00 | — | Acceleration (vertical) controller I gain |
| `PSC_ACCZ_IMAX` | — | 0.00 | d% | Acceleration (vertical) controller I gain maximum |
| `PSC_ACCZ_NEF` | — | 0.00 | — | Accel (vertical) Error notch filter index |
| `PSC_ACCZ_NTF` | — | 0.00 | — | Accel (vertical) Target notch filter index |
| `PSC_ACCZ_P` | — | 0.00 | — | Acceleration (vertical) controller P gain |
| `PSC_ACCZ_PDMX` | — | 0.00 | d% | Acceleration (vertical) controller PD sum maximum |
| `PSC_ACCZ_SMAX` | — | 0.00 | — | Accel (vertical) slew rate limit |
| `PSC_ACC_XY_FILT` | — | 0.00 | Hz | XY Acceleration filter cutoff frequency |
| `PSC_ANGLE_MAX` | — | 0.00 | deg | Position Control Angle Max |
| `PSC_JERK_XY` | — | 0.00 | m/s/s/s | Jerk limit for the horizontal kinematic input shaping |
| `PSC_JERK_Z` | — | 0.00 | m/s/s/s | Jerk limit for the vertical kinematic input shaping |
| `PSC_POSXY_P` | — | 0.00 | — | Position (horizontal) controller P gain |
| `PSC_POSZ_P` | — | 0.00 | — | Position (vertical) controller P gain |
| `PSC_VELXY_D` | — | 0.00 | — | Velocity (horizontal) D gain |
| `PSC_VELXY_FF` | — | 0.00 | — | Velocity (horizontal) feed forward gain |
| `PSC_VELXY_FLTD` | — | 0.00 | Hz | Velocity (horizontal) input filter |
| `PSC_VELXY_FLTE` | — | 0.00 | Hz | Velocity (horizontal) input filter |
| `PSC_VELXY_I` | — | 0.00 | — | Velocity (horizontal) I gain |
| `PSC_VELXY_IMAX` | — | 0.00 | cm/s/s | Velocity (horizontal) integrator maximum |
| `PSC_VELXY_P` | — | 0.00 | — | Velocity (horizontal) P gain |
| `PSC_VELZ_D` | — | 0.00 | — | Velocity (vertical) controller D gain |
| `PSC_VELZ_FF` | — | 0.00 | — | Velocity (vertical) controller Feed Forward gain |
| `PSC_VELZ_FLTD` | — | 0.00 | Hz | Velocity (vertical) input filter for D term |
| `PSC_VELZ_FLTE` | — | 0.00 | Hz | Velocity (vertical) error filter |
| `PSC_VELZ_I` | — | 0.00 | — | Velocity (vertical) controller I gain |
| `PSC_VELZ_IMAX` | — | 0.00 | — | Velocity (vertical) controller I gain maximum |
| `PSC_VELZ_P` | — | 0.00 | — | Velocity (vertical) controller P gain |
| `QUIK_ANGLE_MAX` | — | 0.00 | deg | maximum angle error for tune abort |
| `QUIK_AUTO_FILTER` | — | 0.00 | — | Quicktune auto filter enable |
| `QUIK_AUTO_SAVE` | — | 0.00 | s | Quicktune auto save |
| `QUIK_AXES` | — | 0.00 | — | Quicktune axes |
| `QUIK_DOUBLE_TIME` | — | 0.00 | s | Quicktune doubling time |
| `QUIK_ENABLE` | — | 0.00 | — | Quicktune enable |
| `QUIK_GAIN_MARGIN` | — | 0.00 | % | Quicktune gain margin |
| `QUIK_MAX_REDUCE` | — | 0.00 | % | Quicktune maximum gain reduction |
| `QUIK_OPTIONS` | — | 0.00 | — | Quicktune options |
| `QUIK_OSC_SMAX` | — | 0.00 | — | Quicktune oscillation rate threshold |
| `QUIK_RC_FUNC` | — | 0.00 | — | Quicktune RC function |
| `QUIK_RP_PI_RATIO` | — | 0.00 | — | Quicktune roll/pitch PI ratio |
| `QUIK_YAW_D_MAX` | — | 0.00 | — | Quicktune Yaw D max |
| `QUIK_YAW_P_MAX` | — | 0.00 | — | Quicktune Yaw P max |
| `QUIK_Y_PI_RATIO` | — | 0.00 | — | Quicktune Yaw PI ratio |
| `RALLY_INCL_HOME` | — | 0.00 | — | Rally Include Home |
| `RALLY_LIMIT_KM` | — | 0.00 | km | Rally Limit |
| `RALLY_TOTAL` | — | 0.00 | — | Rally Total |
| `RC10_DZ` | `RC10_MIN` | 0.45 | PWM | RC dead-zone |
| `RC10_MAX` | `RC14_MAX` | 1.00 | PWM | RC max PWM |
| `RC10_MIN` | `RC10_MIN` | 1.00 | PWM | RC min PWM |
| `RC10_OPTION` | `RC10_MIN` | 0.62 | — | RC input option |
| `RC10_REVERSED` | `RC10_MIN` | 0.45 | — | RC reversed |
| `RC10_TRIM` | `RC18_TRIM` | 1.00 | PWM | RC trim PWM |
| `RC11_DZ` | `RC11_REV` | 0.45 | PWM | RC dead-zone |
| `RC11_MAX` | `RC14_MAX` | 1.00 | PWM | RC max PWM |
| `RC11_MIN` | `RC10_MIN` | 1.00 | PWM | RC min PWM |
| `RC11_OPTION` | `RC11_REV` | 0.62 | — | RC input option |
| `RC11_REVERSED` | `RC11_REV` | 0.45 | — | RC reversed |
| `RC11_TRIM` | `RC18_TRIM` | 1.00 | PWM | RC trim PWM |
| `RC12_DZ` | `RC12_MIN` | 0.45 | PWM | RC dead-zone |
| `RC12_MAX` | `RC14_MAX` | 1.00 | PWM | RC max PWM |
| `RC12_MIN` | `RC10_MIN` | 1.00 | PWM | RC min PWM |
| `RC12_OPTION` | `RC12_MIN` | 0.62 | — | RC input option |
| `RC12_REVERSED` | `RC12_MIN` | 0.45 | — | RC reversed |
| `RC12_TRIM` | `RC18_TRIM` | 1.00 | PWM | RC trim PWM |
| `RC13_DZ` | `RC13_MIN` | 0.45 | PWM | RC dead-zone |
| `RC13_MAX` | `RC14_MAX` | 1.00 | PWM | RC max PWM |
| `RC13_MIN` | `RC10_MIN` | 1.00 | PWM | RC min PWM |
| `RC13_OPTION` | `RC13_MIN` | 0.62 | — | RC input option |
| `RC13_REVERSED` | `RC13_MIN` | 0.45 | — | RC reversed |
| `RC13_TRIM` | `RC18_TRIM` | 1.00 | PWM | RC trim PWM |
| `RC14_DZ` | `RC14_MAX` | 0.45 | PWM | RC dead-zone |
| `RC14_MAX` | `RC14_MAX` | 1.00 | PWM | RC max PWM |
| `RC14_MIN` | `RC10_MIN` | 1.00 | PWM | RC min PWM |
| `RC14_OPTION` | `RC14_MAX` | 0.62 | — | RC input option |
| `RC14_REVERSED` | `RC14_MAX` | 0.45 | — | RC reversed |
| `RC14_TRIM` | `RC18_TRIM` | 1.00 | PWM | RC trim PWM |
| `RC15_DZ` | `RC15_MAX` | 0.45 | PWM | RC dead-zone |
| `RC15_MAX` | `RC14_MAX` | 1.00 | PWM | RC max PWM |
| `RC15_MIN` | `RC10_MIN` | 1.00 | PWM | RC min PWM |
| `RC15_OPTION` | `RC15_MAX` | 0.62 | — | RC input option |
| `RC15_REVERSED` | `RC15_MAX` | 0.45 | — | RC reversed |
| `RC15_TRIM` | `RC18_TRIM` | 1.00 | PWM | RC trim PWM |
| `RC16_DZ` | `RC16_MIN` | 0.45 | PWM | RC dead-zone |
| `RC16_MAX` | `RC14_MAX` | 1.00 | PWM | RC max PWM |
| `RC16_MIN` | `RC10_MIN` | 1.00 | PWM | RC min PWM |
| `RC16_OPTION` | `RC16_MIN` | 0.62 | — | RC input option |
| `RC16_REVERSED` | `RC16_MIN` | 0.45 | — | RC reversed |
| `RC16_TRIM` | `RC18_TRIM` | 1.00 | PWM | RC trim PWM |
| `RC1_DZ` | `RC1_REV` | 0.45 | PWM | RC dead-zone |
| `RC1_MAX` | `RC14_MAX` | 1.00 | PWM | RC max PWM |
| `RC1_MIN` | `RC10_MIN` | 1.00 | PWM | RC min PWM |
| `RC1_OPTION` | `RC1_REV` | 0.62 | — | RC input option |
| `RC1_REVERSED` | `RC1_REV` | 0.45 | — | RC reversed |
| `RC1_TRIM` | `RC18_TRIM` | 1.00 | PWM | RC trim PWM |
| `RC2_DZ` | `RC2_REV` | 0.45 | PWM | RC dead-zone |
| `RC2_MAX` | `RC14_MAX` | 1.00 | PWM | RC max PWM |
| `RC2_MIN` | `RC10_MIN` | 1.00 | PWM | RC min PWM |
| `RC2_OPTION` | `RC2_REV` | 0.62 | — | RC input option |
| `RC2_REVERSED` | `RC2_REV` | 0.45 | — | RC reversed |
| `RC2_TRIM` | `RC18_TRIM` | 1.00 | PWM | RC trim PWM |
| `RC3_DZ` | `RC3_MAX` | 0.45 | PWM | RC dead-zone |
| `RC3_MAX` | `RC14_MAX` | 1.00 | PWM | RC max PWM |
| `RC3_MIN` | `RC10_MIN` | 1.00 | PWM | RC min PWM |
| `RC3_OPTION` | `RC3_MAX` | 0.62 | — | RC input option |
| `RC3_REVERSED` | `RC3_MAX` | 0.45 | — | RC reversed |
| `RC3_TRIM` | `RC18_TRIM` | 1.00 | PWM | RC trim PWM |
| `RC4_DZ` | `RC4_TRIM` | 0.45 | PWM | RC dead-zone |
| `RC4_MAX` | `RC14_MAX` | 1.00 | PWM | RC max PWM |
| `RC4_MIN` | `RC10_MIN` | 1.00 | PWM | RC min PWM |
| `RC4_OPTION` | `RC4_TRIM` | 0.62 | — | RC input option |
| `RC4_REVERSED` | `RC4_TRIM` | 0.45 | — | RC reversed |
| `RC4_TRIM` | `RC18_TRIM` | 1.00 | PWM | RC trim PWM |
| `RC5_DZ` | `RC5_MAX` | 0.45 | PWM | RC dead-zone |
| `RC5_MAX` | `RC14_MAX` | 1.00 | PWM | RC max PWM |
| `RC5_MIN` | `RC10_MIN` | 1.00 | PWM | RC min PWM |
| `RC5_OPTION` | `RC5_MAX` | 0.62 | — | RC input option |
| `RC5_REVERSED` | `RC5_MAX` | 0.45 | — | RC reversed |
| `RC5_TRIM` | `RC18_TRIM` | 1.00 | PWM | RC trim PWM |
| `RC6_DZ` | `RC6_REV` | 0.45 | PWM | RC dead-zone |
| `RC6_MAX` | `RC14_MAX` | 1.00 | PWM | RC max PWM |
| `RC6_MIN` | `RC10_MIN` | 1.00 | PWM | RC min PWM |
| `RC6_OPTION` | `RC6_REV` | 0.62 | — | RC input option |
| `RC6_REVERSED` | `RC6_REV` | 0.45 | — | RC reversed |
| `RC6_TRIM` | `RC18_TRIM` | 1.00 | PWM | RC trim PWM |
| `RC7_DZ` | `RC7_MIN` | 0.45 | PWM | RC dead-zone |
| `RC7_MAX` | `RC14_MAX` | 1.00 | PWM | RC max PWM |
| `RC7_MIN` | `RC10_MIN` | 1.00 | PWM | RC min PWM |
| `RC7_OPTION` | `RC7_MIN` | 0.62 | — | RC input option |
| `RC7_REVERSED` | `RC7_MIN` | 0.45 | — | RC reversed |
| `RC7_TRIM` | `RC18_TRIM` | 1.00 | PWM | RC trim PWM |
| `RC8_DZ` | `RC8_REV` | 0.45 | PWM | RC dead-zone |
| `RC8_MAX` | `RC14_MAX` | 1.00 | PWM | RC max PWM |
| `RC8_MIN` | `RC10_MIN` | 1.00 | PWM | RC min PWM |
| `RC8_OPTION` | `RC8_REV` | 0.62 | — | RC input option |
| `RC8_REVERSED` | `RC8_REV` | 0.45 | — | RC reversed |
| `RC8_TRIM` | `RC18_TRIM` | 1.00 | PWM | RC trim PWM |
| `RC9_DZ` | `RC9_REV` | 0.45 | PWM | RC dead-zone |
| `RC9_MAX` | `RC14_MAX` | 1.00 | PWM | RC max PWM |
| `RC9_MIN` | `RC10_MIN` | 1.00 | PWM | RC min PWM |
| `RC9_OPTION` | `RC9_REV` | 0.62 | — | RC input option |
| `RC9_REVERSED` | `RC9_REV` | 0.45 | — | RC reversed |
| `RC9_TRIM` | `RC18_TRIM` | 1.00 | PWM | RC trim PWM |
| `RCK_DEBUG` | — | 0.00 | — | Display Rockblock debugging text |
| `RCK_ENABLE` | — | 0.00 | — | Enable Message transmission |
| `RCK_FORCEHL` | — | 0.00 | — | Force enable High Latency mode |
| `RCK_PERIOD` | — | 0.00 | s | Update rate |
| `RCMAP_PITCH` | — | 0.00 | — | Pitch channel |
| `RCMAP_ROLL` | — | 0.00 | — | Roll channel |
| `RCMAP_THROTTLE` | — | 0.00 | — | Throttle channel |
| `RCMAP_YAW` | — | 0.00 | — | Yaw channel |
| `RC_FS_TIMEOUT` | `RC_MAP_PARAM1` | 0.37 | s | RC Failsafe timeout |
| `RC_OPTIONS` | `RC_MAP_PARAM1` | 0.45 | — | RC options |
| `RC_OVERRIDE_TIME` | `RC_MAP_PARAM1` | 0.37 | s | RC override timeout |
| `RC_PROTOCOLS` | `RC_MAP_PARAM1` | 0.45 | — | RC protocols enabled |
| `RC_SPEED` | `RC_MAP_PARAM1` | 0.45 | Hz | ESC Update Speed |
| `RELAY10_DEFAULT` | — | 0.00 | — | Relay default state |
| `RELAY10_FUNCTION` | — | 0.00 | — | Relay function |
| `RELAY10_INVERTED` | — | 0.00 | — | Relay invert output signal |
| `RELAY10_PIN` | — | 0.00 | — | Relay pin |
| `RELAY11_DEFAULT` | — | 0.00 | — | Relay default state |
| `RELAY11_FUNCTION` | — | 0.00 | — | Relay function |
| `RELAY11_INVERTED` | — | 0.00 | — | Relay invert output signal |
| `RELAY11_PIN` | — | 0.00 | — | Relay pin |
| `RELAY12_DEFAULT` | — | 0.00 | — | Relay default state |
| `RELAY12_FUNCTION` | — | 0.00 | — | Relay function |
| `RELAY12_INVERTED` | — | 0.00 | — | Relay invert output signal |
| `RELAY12_PIN` | — | 0.00 | — | Relay pin |
| `RELAY13_DEFAULT` | — | 0.00 | — | Relay default state |
| `RELAY13_FUNCTION` | — | 0.00 | — | Relay function |
| `RELAY13_INVERTED` | — | 0.00 | — | Relay invert output signal |
| `RELAY13_PIN` | — | 0.00 | — | Relay pin |
| `RELAY14_DEFAULT` | — | 0.00 | — | Relay default state |
| `RELAY14_FUNCTION` | — | 0.00 | — | Relay function |
| `RELAY14_INVERTED` | — | 0.00 | — | Relay invert output signal |
| `RELAY14_PIN` | — | 0.00 | — | Relay pin |
| `RELAY15_DEFAULT` | — | 0.00 | — | Relay default state |
| `RELAY15_FUNCTION` | — | 0.00 | — | Relay function |
| `RELAY15_INVERTED` | — | 0.00 | — | Relay invert output signal |
| `RELAY15_PIN` | — | 0.00 | — | Relay pin |
| `RELAY16_DEFAULT` | — | 0.00 | — | Relay default state |
| `RELAY16_FUNCTION` | — | 0.00 | — | Relay function |
| `RELAY16_INVERTED` | — | 0.00 | — | Relay invert output signal |
| `RELAY16_PIN` | — | 0.00 | — | Relay pin |
| `RELAY1_DEFAULT` | — | 0.00 | — | Relay default state |
| `RELAY1_FUNCTION` | — | 0.00 | — | Relay function |
| `RELAY1_INVERTED` | — | 0.00 | — | Relay invert output signal |
| `RELAY1_PIN` | — | 0.00 | — | Relay pin |
| `RELAY2_DEFAULT` | — | 0.00 | — | Relay default state |
| `RELAY2_FUNCTION` | — | 0.00 | — | Relay function |
| `RELAY2_INVERTED` | — | 0.00 | — | Relay invert output signal |
| `RELAY2_PIN` | — | 0.00 | — | Relay pin |
| `RELAY3_DEFAULT` | — | 0.00 | — | Relay default state |
| `RELAY3_FUNCTION` | — | 0.00 | — | Relay function |
| `RELAY3_INVERTED` | — | 0.00 | — | Relay invert output signal |
| `RELAY3_PIN` | — | 0.00 | — | Relay pin |
| `RELAY4_DEFAULT` | — | 0.00 | — | Relay default state |
| `RELAY4_FUNCTION` | — | 0.00 | — | Relay function |
| `RELAY4_INVERTED` | — | 0.00 | — | Relay invert output signal |
| `RELAY4_PIN` | — | 0.00 | — | Relay pin |
| `RELAY5_DEFAULT` | — | 0.00 | — | Relay default state |
| `RELAY5_FUNCTION` | — | 0.00 | — | Relay function |
| `RELAY5_INVERTED` | — | 0.00 | — | Relay invert output signal |
| `RELAY5_PIN` | — | 0.00 | — | Relay pin |
| `RELAY6_DEFAULT` | — | 0.00 | — | Relay default state |
| `RELAY6_FUNCTION` | — | 0.00 | — | Relay function |
| `RELAY6_INVERTED` | — | 0.00 | — | Relay invert output signal |
| `RELAY6_PIN` | — | 0.00 | — | Relay pin |
| `RELAY7_DEFAULT` | — | 0.00 | — | Relay default state |
| `RELAY7_FUNCTION` | — | 0.00 | — | Relay function |
| `RELAY7_INVERTED` | — | 0.00 | — | Relay invert output signal |
| `RELAY7_PIN` | — | 0.00 | — | Relay pin |
| `RELAY8_DEFAULT` | — | 0.00 | — | Relay default state |
| `RELAY8_FUNCTION` | — | 0.00 | — | Relay function |
| `RELAY8_INVERTED` | — | 0.00 | — | Relay invert output signal |
| `RELAY8_PIN` | — | 0.00 | — | Relay pin |
| `RELAY9_DEFAULT` | — | 0.00 | — | Relay default state |
| `RELAY9_FUNCTION` | — | 0.00 | — | Relay function |
| `RELAY9_INVERTED` | — | 0.00 | — | Relay invert output signal |
| `RELAY9_PIN` | — | 0.00 | — | Relay pin |
| `RNGFND1_ADDR` | — | 0.00 | — | Bus address of sensor |
| `RNGFND1_FUNCTION` | — | 0.00 | — | Rangefinder function |
| `RNGFND1_GNDCLEAR` | — | 0.00 | cm | Distance (in cm) from the range finder to the ground |
| `RNGFND1_MAX_CM` | — | 0.00 | cm | Rangefinder maximum distance |
| `RNGFND1_MIN_CM` | — | 0.00 | cm | Rangefinder minimum distance |
| `RNGFND1_OFFSET` | — | 0.00 | V | rangefinder offset |
| `RNGFND1_ORIENT` | — | 0.00 | — | Rangefinder orientation |
| `RNGFND1_PIN` | — | 0.00 | — | Rangefinder pin |
| `RNGFND1_POS_X` | — | 0.00 | m | X position offset |
| `RNGFND1_POS_Y` | — | 0.00 | m | Y position offset |
| `RNGFND1_POS_Z` | — | 0.00 | m | Z position offset |
| `RNGFND1_PWRRNG` | — | 0.00 | m | Powersave range |
| `RNGFND1_RECV_ID` | — | 0.00 | — | RangeFinder CAN receive ID |
| `RNGFND1_RMETRIC` | — | 0.00 | — | Ratiometric |
| `RNGFND1_SCALING` | — | 0.00 | m/V | Rangefinder scaling |
| `RNGFND1_SNR_MIN` | — | 0.00 | — | RangeFinder Minimum signal strength |
| `RNGFND1_STOP_PIN` | — | 0.00 | — | Rangefinder stop pin |
| `RNGFND1_TYPE` | — | 0.00 | — | Rangefinder type |
| `RNGFND1_WSP_AVG` | — | 0.00 | — | Multi-pulse averages |
| `RNGFND1_WSP_BAUD` | — | 0.00 | — | Baud rate |
| `RNGFND1_WSP_FRQ` | — | 0.00 | — | Frequency |
| `RNGFND1_WSP_MAVG` | — | 0.00 | — | Moving Average Range |
| `RNGFND1_WSP_MEDF` | — | 0.00 | — | Moving Median Filter |
| `RNGFND1_WSP_THR` | — | 0.00 | — | Sensitivity threshold |
| `RNGFND2_ADDR` | — | 0.00 | — | Bus address of sensor |
| `RNGFND2_FUNCTION` | — | 0.00 | — | Rangefinder function |
| `RNGFND2_GNDCLEAR` | — | 0.00 | cm | Distance (in cm) from the range finder to the ground |
| `RNGFND2_MAX_CM` | — | 0.00 | cm | Rangefinder maximum distance |
| `RNGFND2_MIN_CM` | — | 0.00 | cm | Rangefinder minimum distance |
| `RNGFND2_OFFSET` | — | 0.00 | V | rangefinder offset |
| `RNGFND2_ORIENT` | — | 0.00 | — | Rangefinder orientation |
| `RNGFND2_PIN` | — | 0.00 | — | Rangefinder pin |
| `RNGFND2_POS_X` | — | 0.00 | m | X position offset |
| `RNGFND2_POS_Y` | — | 0.00 | m | Y position offset |
| `RNGFND2_POS_Z` | — | 0.00 | m | Z position offset |
| `RNGFND2_PWRRNG` | — | 0.00 | m | Powersave range |
| `RNGFND2_RECV_ID` | — | 0.00 | — | RangeFinder CAN receive ID |
| `RNGFND2_RMETRIC` | — | 0.00 | — | Ratiometric |
| `RNGFND2_SCALING` | — | 0.00 | m/V | Rangefinder scaling |
| `RNGFND2_SNR_MIN` | — | 0.00 | — | RangeFinder Minimum signal strength |
| `RNGFND2_STOP_PIN` | — | 0.00 | — | Rangefinder stop pin |
| `RNGFND2_TYPE` | — | 0.00 | — | Rangefinder type |
| `RNGFND2_WSP_AVG` | — | 0.00 | — | Multi-pulse averages |
| `RNGFND2_WSP_BAUD` | — | 0.00 | — | Baud rate |
| `RNGFND2_WSP_FRQ` | — | 0.00 | — | Frequency |
| `RNGFND2_WSP_MAVG` | — | 0.00 | — | Moving Average Range |
| `RNGFND2_WSP_MEDF` | — | 0.00 | — | Moving Median Filter |
| `RNGFND2_WSP_THR` | — | 0.00 | — | Sensitivity threshold |
| `RNGFND3_ADDR` | — | 0.00 | — | Bus address of sensor |
| `RNGFND3_FUNCTION` | — | 0.00 | — | Rangefinder function |
| `RNGFND3_GNDCLEAR` | — | 0.00 | cm | Distance (in cm) from the range finder to the ground |
| `RNGFND3_MAX_CM` | — | 0.00 | cm | Rangefinder maximum distance |
| `RNGFND3_MIN_CM` | — | 0.00 | cm | Rangefinder minimum distance |
| `RNGFND3_OFFSET` | — | 0.00 | V | rangefinder offset |
| `RNGFND3_ORIENT` | — | 0.00 | — | Rangefinder orientation |
| `RNGFND3_PIN` | — | 0.00 | — | Rangefinder pin |
| `RNGFND3_POS_X` | — | 0.00 | m | X position offset |
| `RNGFND3_POS_Y` | — | 0.00 | m | Y position offset |
| `RNGFND3_POS_Z` | — | 0.00 | m | Z position offset |
| `RNGFND3_PWRRNG` | — | 0.00 | m | Powersave range |
| `RNGFND3_RECV_ID` | — | 0.00 | — | RangeFinder CAN receive ID |
| `RNGFND3_RMETRIC` | — | 0.00 | — | Ratiometric |
| `RNGFND3_SCALING` | — | 0.00 | m/V | Rangefinder scaling |
| `RNGFND3_SNR_MIN` | — | 0.00 | — | RangeFinder Minimum signal strength |
| `RNGFND3_STOP_PIN` | — | 0.00 | — | Rangefinder stop pin |
| `RNGFND3_TYPE` | — | 0.00 | — | Rangefinder type |
| `RNGFND3_WSP_AVG` | — | 0.00 | — | Multi-pulse averages |
| `RNGFND3_WSP_BAUD` | — | 0.00 | — | Baud rate |
| `RNGFND3_WSP_FRQ` | — | 0.00 | — | Frequency |
| `RNGFND3_WSP_MAVG` | — | 0.00 | — | Moving Average Range |
| `RNGFND3_WSP_MEDF` | — | 0.00 | — | Moving Median Filter |
| `RNGFND3_WSP_THR` | — | 0.00 | — | Sensitivity threshold |
| `RNGFND4_ADDR` | — | 0.00 | — | Bus address of sensor |
| `RNGFND4_FUNCTION` | — | 0.00 | — | Rangefinder function |
| `RNGFND4_GNDCLEAR` | — | 0.00 | cm | Distance (in cm) from the range finder to the ground |
| `RNGFND4_MAX_CM` | — | 0.00 | cm | Rangefinder maximum distance |
| `RNGFND4_MIN_CM` | — | 0.00 | cm | Rangefinder minimum distance |
| `RNGFND4_OFFSET` | — | 0.00 | V | rangefinder offset |
| `RNGFND4_ORIENT` | — | 0.00 | — | Rangefinder orientation |
| `RNGFND4_PIN` | — | 0.00 | — | Rangefinder pin |
| `RNGFND4_POS_X` | — | 0.00 | m | X position offset |
| `RNGFND4_POS_Y` | — | 0.00 | m | Y position offset |
| `RNGFND4_POS_Z` | — | 0.00 | m | Z position offset |
| `RNGFND4_PWRRNG` | — | 0.00 | m | Powersave range |
| `RNGFND4_RECV_ID` | — | 0.00 | — | RangeFinder CAN receive ID |
| `RNGFND4_RMETRIC` | — | 0.00 | — | Ratiometric |
| `RNGFND4_SCALING` | — | 0.00 | m/V | Rangefinder scaling |
| `RNGFND4_SNR_MIN` | — | 0.00 | — | RangeFinder Minimum signal strength |
| `RNGFND4_STOP_PIN` | — | 0.00 | — | Rangefinder stop pin |
| `RNGFND4_TYPE` | — | 0.00 | — | Rangefinder type |
| `RNGFND4_WSP_AVG` | — | 0.00 | — | Multi-pulse averages |
| `RNGFND4_WSP_BAUD` | — | 0.00 | — | Baud rate |
| `RNGFND4_WSP_FRQ` | — | 0.00 | — | Frequency |
| `RNGFND4_WSP_MAVG` | — | 0.00 | — | Moving Average Range |
| `RNGFND4_WSP_MEDF` | — | 0.00 | — | Moving Median Filter |
| `RNGFND4_WSP_THR` | — | 0.00 | — | Sensitivity threshold |
| `RNGFND5_ADDR` | — | 0.00 | — | Bus address of sensor |
| `RNGFND5_FUNCTION` | — | 0.00 | — | Rangefinder function |
| `RNGFND5_GNDCLEAR` | — | 0.00 | cm | Distance (in cm) from the range finder to the ground |
| `RNGFND5_MAX_CM` | — | 0.00 | cm | Rangefinder maximum distance |
| `RNGFND5_MIN_CM` | — | 0.00 | cm | Rangefinder minimum distance |
| `RNGFND5_OFFSET` | — | 0.00 | V | rangefinder offset |
| `RNGFND5_ORIENT` | — | 0.00 | — | Rangefinder orientation |
| `RNGFND5_PIN` | — | 0.00 | — | Rangefinder pin |
| `RNGFND5_POS_X` | — | 0.00 | m | X position offset |
| `RNGFND5_POS_Y` | — | 0.00 | m | Y position offset |
| `RNGFND5_POS_Z` | — | 0.00 | m | Z position offset |
| `RNGFND5_PWRRNG` | — | 0.00 | m | Powersave range |
| `RNGFND5_RECV_ID` | — | 0.00 | — | RangeFinder CAN receive ID |
| `RNGFND5_RMETRIC` | — | 0.00 | — | Ratiometric |
| `RNGFND5_SCALING` | — | 0.00 | m/V | Rangefinder scaling |
| `RNGFND5_SNR_MIN` | — | 0.00 | — | RangeFinder Minimum signal strength |
| `RNGFND5_STOP_PIN` | — | 0.00 | — | Rangefinder stop pin |
| `RNGFND5_TYPE` | — | 0.00 | — | Rangefinder type |
| `RNGFND5_WSP_AVG` | — | 0.00 | — | Multi-pulse averages |
| `RNGFND5_WSP_BAUD` | — | 0.00 | — | Baud rate |
| `RNGFND5_WSP_FRQ` | — | 0.00 | — | Frequency |
| `RNGFND5_WSP_MAVG` | — | 0.00 | — | Moving Average Range |
| `RNGFND5_WSP_MEDF` | — | 0.00 | — | Moving Median Filter |
| `RNGFND5_WSP_THR` | — | 0.00 | — | Sensitivity threshold |
| `RNGFND6_ADDR` | — | 0.00 | — | Bus address of sensor |
| `RNGFND6_FUNCTION` | — | 0.00 | — | Rangefinder function |
| `RNGFND6_GNDCLEAR` | — | 0.00 | cm | Distance (in cm) from the range finder to the ground |
| `RNGFND6_MAX_CM` | — | 0.00 | cm | Rangefinder maximum distance |
| `RNGFND6_MIN_CM` | — | 0.00 | cm | Rangefinder minimum distance |
| `RNGFND6_OFFSET` | — | 0.00 | V | rangefinder offset |
| `RNGFND6_ORIENT` | — | 0.00 | — | Rangefinder orientation |
| `RNGFND6_PIN` | — | 0.00 | — | Rangefinder pin |
| `RNGFND6_POS_X` | — | 0.00 | m | X position offset |
| `RNGFND6_POS_Y` | — | 0.00 | m | Y position offset |
| `RNGFND6_POS_Z` | — | 0.00 | m | Z position offset |
| `RNGFND6_PWRRNG` | — | 0.00 | m | Powersave range |
| `RNGFND6_RECV_ID` | — | 0.00 | — | RangeFinder CAN receive ID |
| `RNGFND6_RMETRIC` | — | 0.00 | — | Ratiometric |
| `RNGFND6_SCALING` | — | 0.00 | m/V | Rangefinder scaling |
| `RNGFND6_SNR_MIN` | — | 0.00 | — | RangeFinder Minimum signal strength |
| `RNGFND6_STOP_PIN` | — | 0.00 | — | Rangefinder stop pin |
| `RNGFND6_TYPE` | — | 0.00 | — | Rangefinder type |
| `RNGFND6_WSP_AVG` | — | 0.00 | — | Multi-pulse averages |
| `RNGFND6_WSP_BAUD` | — | 0.00 | — | Baud rate |
| `RNGFND6_WSP_FRQ` | — | 0.00 | — | Frequency |
| `RNGFND6_WSP_MAVG` | — | 0.00 | — | Moving Average Range |
| `RNGFND6_WSP_MEDF` | — | 0.00 | — | Moving Median Filter |
| `RNGFND6_WSP_THR` | — | 0.00 | — | Sensitivity threshold |
| `RNGFND7_ADDR` | — | 0.00 | — | Bus address of sensor |
| `RNGFND7_FUNCTION` | — | 0.00 | — | Rangefinder function |
| `RNGFND7_GNDCLEAR` | — | 0.00 | cm | Distance (in cm) from the range finder to the ground |
| `RNGFND7_MAX_CM` | — | 0.00 | cm | Rangefinder maximum distance |
| `RNGFND7_MIN_CM` | — | 0.00 | cm | Rangefinder minimum distance |
| `RNGFND7_OFFSET` | — | 0.00 | V | rangefinder offset |
| `RNGFND7_ORIENT` | — | 0.00 | — | Rangefinder orientation |
| `RNGFND7_PIN` | — | 0.00 | — | Rangefinder pin |
| `RNGFND7_POS_X` | — | 0.00 | m | X position offset |
| `RNGFND7_POS_Y` | — | 0.00 | m | Y position offset |
| `RNGFND7_POS_Z` | — | 0.00 | m | Z position offset |
| `RNGFND7_PWRRNG` | — | 0.00 | m | Powersave range |
| `RNGFND7_RECV_ID` | — | 0.00 | — | RangeFinder CAN receive ID |
| `RNGFND7_RMETRIC` | — | 0.00 | — | Ratiometric |
| `RNGFND7_SCALING` | — | 0.00 | m/V | Rangefinder scaling |
| `RNGFND7_SNR_MIN` | — | 0.00 | — | RangeFinder Minimum signal strength |
| `RNGFND7_STOP_PIN` | — | 0.00 | — | Rangefinder stop pin |
| `RNGFND7_TYPE` | — | 0.00 | — | Rangefinder type |
| `RNGFND7_WSP_AVG` | — | 0.00 | — | Multi-pulse averages |
| `RNGFND7_WSP_BAUD` | — | 0.00 | — | Baud rate |
| `RNGFND7_WSP_FRQ` | — | 0.00 | — | Frequency |
| `RNGFND7_WSP_MAVG` | — | 0.00 | — | Moving Average Range |
| `RNGFND7_WSP_MEDF` | — | 0.00 | — | Moving Median Filter |
| `RNGFND7_WSP_THR` | — | 0.00 | — | Sensitivity threshold |
| `RNGFND8_ADDR` | — | 0.00 | — | Bus address of sensor |
| `RNGFND8_FUNCTION` | — | 0.00 | — | Rangefinder function |
| `RNGFND8_GNDCLEAR` | — | 0.00 | cm | Distance (in cm) from the range finder to the ground |
| `RNGFND8_MAX_CM` | — | 0.00 | cm | Rangefinder maximum distance |
| `RNGFND8_MIN_CM` | — | 0.00 | cm | Rangefinder minimum distance |
| `RNGFND8_OFFSET` | — | 0.00 | V | rangefinder offset |
| `RNGFND8_ORIENT` | — | 0.00 | — | Rangefinder orientation |
| `RNGFND8_PIN` | — | 0.00 | — | Rangefinder pin |
| `RNGFND8_POS_X` | — | 0.00 | m | X position offset |
| `RNGFND8_POS_Y` | — | 0.00 | m | Y position offset |
| `RNGFND8_POS_Z` | — | 0.00 | m | Z position offset |
| `RNGFND8_PWRRNG` | — | 0.00 | m | Powersave range |
| `RNGFND8_RECV_ID` | — | 0.00 | — | RangeFinder CAN receive ID |
| `RNGFND8_RMETRIC` | — | 0.00 | — | Ratiometric |
| `RNGFND8_SCALING` | — | 0.00 | m/V | Rangefinder scaling |
| `RNGFND8_SNR_MIN` | — | 0.00 | — | RangeFinder Minimum signal strength |
| `RNGFND8_STOP_PIN` | — | 0.00 | — | Rangefinder stop pin |
| `RNGFND8_TYPE` | — | 0.00 | — | Rangefinder type |
| `RNGFND8_WSP_AVG` | — | 0.00 | — | Multi-pulse averages |
| `RNGFND8_WSP_BAUD` | — | 0.00 | — | Baud rate |
| `RNGFND8_WSP_FRQ` | — | 0.00 | — | Frequency |
| `RNGFND8_WSP_MAVG` | — | 0.00 | — | Moving Average Range |
| `RNGFND8_WSP_MEDF` | — | 0.00 | — | Moving Median Filter |
| `RNGFND8_WSP_THR` | — | 0.00 | — | Sensitivity threshold |
| `RNGFND9_ADDR` | — | 0.00 | — | Bus address of sensor |
| `RNGFND9_FUNCTION` | — | 0.00 | — | Rangefinder function |
| `RNGFND9_GNDCLEAR` | — | 0.00 | cm | Distance (in cm) from the range finder to the ground |
| `RNGFND9_MAX_CM` | — | 0.00 | cm | Rangefinder maximum distance |
| `RNGFND9_MIN_CM` | — | 0.00 | cm | Rangefinder minimum distance |
| `RNGFND9_OFFSET` | — | 0.00 | V | rangefinder offset |
| `RNGFND9_ORIENT` | — | 0.00 | — | Rangefinder orientation |
| `RNGFND9_PIN` | — | 0.00 | — | Rangefinder pin |
| `RNGFND9_POS_X` | — | 0.00 | m | X position offset |
| `RNGFND9_POS_Y` | — | 0.00 | m | Y position offset |
| `RNGFND9_POS_Z` | — | 0.00 | m | Z position offset |
| `RNGFND9_PWRRNG` | — | 0.00 | m | Powersave range |
| `RNGFND9_RECV_ID` | — | 0.00 | — | RangeFinder CAN receive ID |
| `RNGFND9_RMETRIC` | — | 0.00 | — | Ratiometric |
| `RNGFND9_SCALING` | — | 0.00 | m/V | Rangefinder scaling |
| `RNGFND9_SNR_MIN` | — | 0.00 | — | RangeFinder Minimum signal strength |
| `RNGFND9_STOP_PIN` | — | 0.00 | — | Rangefinder stop pin |
| `RNGFND9_TYPE` | — | 0.00 | — | Rangefinder type |
| `RNGFND9_WSP_AVG` | — | 0.00 | — | Multi-pulse averages |
| `RNGFND9_WSP_BAUD` | — | 0.00 | — | Baud rate |
| `RNGFND9_WSP_FRQ` | — | 0.00 | — | Frequency |
| `RNGFND9_WSP_MAVG` | — | 0.00 | — | Moving Average Range |
| `RNGFND9_WSP_MEDF` | — | 0.00 | — | Moving Median Filter |
| `RNGFND9_WSP_THR` | — | 0.00 | — | Sensitivity threshold |
| `RNGFNDA_ADDR` | — | 0.00 | — | Bus address of sensor |
| `RNGFNDA_FUNCTION` | — | 0.00 | — | Rangefinder function |
| `RNGFNDA_GNDCLEAR` | — | 0.00 | cm | Distance (in cm) from the range finder to the ground |
| `RNGFNDA_MAX_CM` | — | 0.00 | cm | Rangefinder maximum distance |
| `RNGFNDA_MIN_CM` | — | 0.00 | cm | Rangefinder minimum distance |
| `RNGFNDA_OFFSET` | — | 0.00 | V | rangefinder offset |
| `RNGFNDA_ORIENT` | — | 0.00 | — | Rangefinder orientation |
| `RNGFNDA_PIN` | — | 0.00 | — | Rangefinder pin |
| `RNGFNDA_POS_X` | — | 0.00 | m | X position offset |
| `RNGFNDA_POS_Y` | — | 0.00 | m | Y position offset |
| `RNGFNDA_POS_Z` | — | 0.00 | m | Z position offset |
| `RNGFNDA_PWRRNG` | — | 0.00 | m | Powersave range |
| `RNGFNDA_RECV_ID` | — | 0.00 | — | RangeFinder CAN receive ID |
| `RNGFNDA_RMETRIC` | — | 0.00 | — | Ratiometric |
| `RNGFNDA_SCALING` | — | 0.00 | m/V | Rangefinder scaling |
| `RNGFNDA_SNR_MIN` | — | 0.00 | — | RangeFinder Minimum signal strength |
| `RNGFNDA_STOP_PIN` | — | 0.00 | — | Rangefinder stop pin |
| `RNGFNDA_TYPE` | — | 0.00 | — | Rangefinder type |
| `RNGFNDA_WSP_AVG` | — | 0.00 | — | Multi-pulse averages |
| `RNGFNDA_WSP_BAUD` | — | 0.00 | — | Baud rate |
| `RNGFNDA_WSP_FRQ` | — | 0.00 | — | Frequency |
| `RNGFNDA_WSP_MAVG` | — | 0.00 | — | Moving Average Range |
| `RNGFNDA_WSP_MEDF` | — | 0.00 | — | Moving Median Filter |
| `RNGFNDA_WSP_THR` | — | 0.00 | — | Sensitivity threshold |
| `RNGFND_FILT` | — | 0.00 | Hz | Rangefinder filter |
| `RPM1_DC_ID` | — | 0.00 | — | DroneCAN Sensor ID |
| `RPM1_ESC_INDEX` | — | 0.00 | — | ESC Telemetry Index to write RPM to |
| `RPM1_ESC_MASK` | — | 0.00 | — | Bitmask of ESC telemetry channels to average |
| `RPM1_MAX` | `RPM_CAP_ENABLE` | 0.33 | — | Maximum RPM |
| `RPM1_MIN` | `RPM_CAP_ENABLE` | 0.33 | — | Minimum RPM |
| `RPM1_MIN_QUAL` | — | 0.00 | — | Minimum Quality |
| `RPM1_PIN` | `RPM_CAP_ENABLE` | 0.33 | — | Input pin number |
| `RPM1_SCALING` | `RPM_CAP_ENABLE` | 0.33 | — | RPM scaling |
| `RPM1_TYPE` | `RPM_CAP_ENABLE` | 0.50 | — | RPM type |
| `RPM2_DC_ID` | — | 0.00 | — | DroneCAN Sensor ID |
| `RPM2_ESC_INDEX` | — | 0.00 | — | ESC Telemetry Index to write RPM to |
| `RPM2_ESC_MASK` | — | 0.00 | — | Bitmask of ESC telemetry channels to average |
| `RPM2_MAX` | `RPM_CAP_ENABLE` | 0.33 | — | Maximum RPM |
| `RPM2_MIN` | `RPM_CAP_ENABLE` | 0.33 | — | Minimum RPM |
| `RPM2_MIN_QUAL` | — | 0.00 | — | Minimum Quality |
| `RPM2_PIN` | `RPM_CAP_ENABLE` | 0.33 | — | Input pin number |
| `RPM2_SCALING` | `RPM_CAP_ENABLE` | 0.33 | — | RPM scaling |
| `RPM2_TYPE` | `RPM_CAP_ENABLE` | 0.50 | — | RPM type |
| `RPM3_DC_ID` | — | 0.00 | — | DroneCAN Sensor ID |
| `RPM3_ESC_INDEX` | — | 0.00 | — | ESC Telemetry Index to write RPM to |
| `RPM3_ESC_MASK` | — | 0.00 | — | Bitmask of ESC telemetry channels to average |
| `RPM3_MAX` | `RPM_CAP_ENABLE` | 0.33 | — | Maximum RPM |
| `RPM3_MIN` | `RPM_CAP_ENABLE` | 0.33 | — | Minimum RPM |
| `RPM3_MIN_QUAL` | — | 0.00 | — | Minimum Quality |
| `RPM3_PIN` | `RPM_CAP_ENABLE` | 0.33 | — | Input pin number |
| `RPM3_SCALING` | `RPM_CAP_ENABLE` | 0.33 | — | RPM scaling |
| `RPM3_TYPE` | `RPM_CAP_ENABLE` | 0.50 | — | RPM type |
| `RPM4_DC_ID` | — | 0.00 | — | DroneCAN Sensor ID |
| `RPM4_ESC_INDEX` | — | 0.00 | — | ESC Telemetry Index to write RPM to |
| `RPM4_ESC_MASK` | — | 0.00 | — | Bitmask of ESC telemetry channels to average |
| `RPM4_MAX` | `RPM_CAP_ENABLE` | 0.33 | — | Maximum RPM |
| `RPM4_MIN` | `RPM_CAP_ENABLE` | 0.33 | — | Minimum RPM |
| `RPM4_MIN_QUAL` | — | 0.00 | — | Minimum Quality |
| `RPM4_PIN` | `RPM_CAP_ENABLE` | 0.33 | — | Input pin number |
| `RPM4_SCALING` | `RPM_CAP_ENABLE` | 0.33 | — | RPM scaling |
| `RPM4_TYPE` | `RPM_CAP_ENABLE` | 0.50 | — | RPM type |
| `RSSI_ANA_PIN` | — | 0.00 | — | Receiver RSSI sensing pin |
| `RSSI_CHANNEL` | — | 0.00 | — | Receiver RSSI channel number |
| `RSSI_CHAN_HIGH` | — | 0.00 | PWM | Receiver RSSI PWM high value |
| `RSSI_CHAN_LOW` | — | 0.00 | PWM | RSSI PWM low value |
| `RSSI_PIN_HIGH` | — | 0.00 | V | RSSI pin's highest voltage |
| `RSSI_PIN_LOW` | — | 0.00 | V | RSSI pin's lowest voltage |
| `RSSI_TYPE` | — | 0.00 | — | RSSI Type |
| `RTL_ALT` | — | 0.00 | cm | RTL Altitude |
| `RTL_ALT_FINAL` | — | 0.00 | cm | RTL Final Altitude |
| `RTL_ALT_TYPE` | — | 0.00 | — | RTL mode altitude type |
| `RTL_CLIMB_MIN` | — | 0.00 | cm | RTL minimum climb |
| `RTL_CONE_SLOPE` | — | 0.00 | — | RTL cone slope |
| `RTL_LOIT_TIME` | — | 0.00 | ms | RTL loiter time |
| `RTL_OPTIONS` | — | 0.00 | — | RTL mode options |
| `RTL_SPEED` | — | 0.00 | cm/s | RTL speed |
| `RTUN_AUTO_FILTER` | — | 0.00 | — | Rover Quicktune auto filter enable |
| `RTUN_AUTO_SAVE` | — | 0.00 | s | Rover Quicktune auto save |
| `RTUN_AXES` | — | 0.00 | — | Rover Quicktune axes |
| `RTUN_ENABLE` | — | 0.00 | — | Rover Quicktune enable |
| `RTUN_RC_FUNC` | — | 0.00 | — | Rover Quicktune RC function |
| `RTUN_SPD_FFRATIO` | — | 0.00 | — | Rover Quicktune Speed FeedForward (equivalent) ratio |
| `RTUN_SPD_I_RATIO` | — | 0.00 | — | Rover Quicktune Speed FF to I ratio |
| `RTUN_SPD_P_RATIO` | — | 0.00 | — | Rover Quicktune Speed FF to P ratio |
| `RTUN_SPEED_MIN` | — | 0.00 | m/s | Rover Quicktune minimum speed for tuning |
| `RTUN_STR_FFRATIO` | — | 0.00 | — | Rover Quicktune Steering Rate FeedForward ratio |
| `RTUN_STR_I_RATIO` | — | 0.00 | — | Rover Quicktune Steering FF to I ratio |
| `RTUN_STR_P_RATIO` | — | 0.00 | — | Rover Quicktune Steering FF to P ratio |
| `SCHED_DEBUG` | — | 0.00 | — | Scheduler debug level |
| `SCHED_LOOP_RATE` | — | 0.00 | Hz | Scheduling main loop rate |
| `SCHED_OPTIONS` | — | 0.00 | — | Scheduling options |
| `SCR_DEBUG_OPTS` | — | 0.00 | — | Scripting Debug Level |
| `SCR_DIR_DISABLE` | — | 0.00 | — | Directory disable |
| `SCR_ENABLE` | — | 0.00 | — | Enable Scripting |
| `SCR_HEAP_SIZE` | — | 0.00 | — | Scripting Heap Size |
| `SCR_LD_CHECKSUM` | — | 0.00 | — | Loaded script checksum |
| `SCR_RUN_CHECKSUM` | — | 0.00 | — | Running script checksum |
| `SCR_SDEV1_PROTO` | — | 0.00 | — | Serial protocol of scripting serial device |
| `SCR_SDEV2_PROTO` | — | 0.00 | — | Serial protocol of scripting serial device |
| `SCR_SDEV3_PROTO` | — | 0.00 | — | Serial protocol of scripting serial device |
| `SCR_SDEV_EN` | — | 0.00 | — | Scripting serial device enable |
| `SCR_THD_PRIORITY` | — | 0.00 | — | Scripting thread priority |
| `SCR_USER1` | — | 0.00 | — | Scripting User Parameter1 |
| `SCR_USER2` | — | 0.00 | — | Scripting User Parameter2 |
| `SCR_USER3` | — | 0.00 | — | Scripting User Parameter3 |
| `SCR_USER4` | — | 0.00 | — | Scripting User Parameter4 |
| `SCR_USER5` | — | 0.00 | — | Scripting User Parameter5 |
| `SCR_USER6` | — | 0.00 | — | Scripting User Parameter6 |
| `SCR_VM_I_COUNT` | — | 0.00 | — | Scripting Virtual Machine Instruction Count |
| `SERIAL0_BAUD` | — | 0.00 | — | Serial0 baud rate |
| `SERIAL0_PROTOCOL` | — | 0.00 | — | Console protocol selection |
| `SERIAL1_BAUD` | — | 0.00 | — | Telem1 Baud Rate |
| `SERIAL1_OPTIONS` | — | 0.00 | — | Telem1 options |
| `SERIAL1_PROTOCOL` | — | 0.00 | — | Telem1 protocol selection |
| `SERIAL2_BAUD` | — | 0.00 | — | Telemetry 2 Baud Rate |
| `SERIAL2_OPTIONS` | — | 0.00 | — | Telem2 options |
| `SERIAL2_PROTOCOL` | — | 0.00 | — | Telemetry 2 protocol selection |
| `SERIAL3_BAUD` | — | 0.00 | — | Serial 3 (GPS) Baud Rate |
| `SERIAL3_OPTIONS` | — | 0.00 | — | Serial3 options |
| `SERIAL3_PROTOCOL` | — | 0.00 | — | Serial 3 (GPS) protocol selection |
| `SERIAL4_BAUD` | — | 0.00 | — | Serial 4 Baud Rate |
| `SERIAL4_OPTIONS` | — | 0.00 | — | Serial4 options |
| `SERIAL4_PROTOCOL` | — | 0.00 | — | Serial4 protocol selection |
| `SERIAL5_BAUD` | — | 0.00 | — | Serial 5 Baud Rate |
| `SERIAL5_OPTIONS` | — | 0.00 | — | Serial5 options |
| `SERIAL5_PROTOCOL` | — | 0.00 | — | Serial5 protocol selection |
| `SERIAL6_BAUD` | — | 0.00 | — | Serial 6 Baud Rate |
| `SERIAL6_OPTIONS` | — | 0.00 | — | Serial6 options |
| `SERIAL6_PROTOCOL` | — | 0.00 | — | Serial6 protocol selection |
| `SERIAL7_BAUD` | — | 0.00 | — | Serial 7 Baud Rate |
| `SERIAL7_OPTIONS` | — | 0.00 | — | Serial7 options |
| `SERIAL7_PROTOCOL` | — | 0.00 | — | Serial7 protocol selection |
| `SERIAL8_BAUD` | — | 0.00 | — | Serial 8 Baud Rate |
| `SERIAL8_OPTIONS` | — | 0.00 | — | Serial8 options |
| `SERIAL8_PROTOCOL` | — | 0.00 | — | Serial8 protocol selection |
| `SERIAL9_BAUD` | — | 0.00 | — | Serial 9 Baud Rate |
| `SERIAL9_OPTIONS` | — | 0.00 | — | Serial9 options |
| `SERIAL9_PROTOCOL` | — | 0.00 | — | Serial9 protocol selection |
| `SERIAL_PASS1` | — | 0.00 | — | Serial passthru first port |
| `SERIAL_PASS2` | — | 0.00 | — | Serial passthru second port |
| `SERIAL_PASSTIMO` | — | 0.00 | s | Serial passthru timeout |
| `SERVO10_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO10_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO10_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO10_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO10_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO11_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO11_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO11_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO11_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO11_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO12_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO12_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO12_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO12_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO12_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO13_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO13_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO13_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO13_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO13_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO14_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO14_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO14_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO14_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO14_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO15_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO15_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO15_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO15_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO15_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO16_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO16_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO16_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO16_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO16_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO17_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO17_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO17_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO17_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO17_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO18_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO18_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO18_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO18_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO18_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO19_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO19_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO19_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO19_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO19_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO1_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO1_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO1_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO1_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO1_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO20_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO20_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO20_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO20_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO20_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO21_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO21_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO21_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO21_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO21_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO22_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO22_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO22_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO22_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO22_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO23_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO23_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO23_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO23_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO23_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO24_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO24_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO24_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO24_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO24_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO25_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO25_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO25_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO25_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO25_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO26_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO26_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO26_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO26_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO26_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO27_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO27_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO27_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO27_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO27_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO28_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO28_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO28_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO28_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO28_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO29_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO29_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO29_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO29_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO29_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO2_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO2_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO2_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO2_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO2_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO30_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO30_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO30_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO30_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO30_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO31_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO31_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO31_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO31_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO31_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO32_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO32_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO32_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO32_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO32_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO3_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO3_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO3_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO3_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO3_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO4_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO4_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO4_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO4_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO4_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO5_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO5_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO5_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO5_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO5_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO6_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO6_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO6_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO6_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO6_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO7_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO7_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO7_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO7_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO7_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO8_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO8_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO8_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO8_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO8_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO9_FUNCTION` | — | 0.00 | — | Servo output function |
| `SERVO9_MAX` | — | 0.00 | PWM | Maximum PWM |
| `SERVO9_MIN` | — | 0.00 | PWM | Minimum PWM |
| `SERVO9_REVERSED` | — | 0.00 | — | Servo reverse |
| `SERVO9_TRIM` | `TRIM_YAW` | 0.33 | PWM | Trim PWM |
| `SERVO_32_ENABLE` | — | 0.00 | — | Enable outputs 17 to 31 |
| `SERVO_BLH_3DMASK` | — | 0.00 | — | BLHeli bitmask of 3D channels |
| `SERVO_BLH_AUTO` | — | 0.00 | — | BLHeli pass-thru auto-enable for multicopter motors |
| `SERVO_BLH_BDMASK` | — | 0.00 | — | BLHeli bitmask of bi-directional dshot channels |
| `SERVO_BLH_DEBUG` | — | 0.00 | — | BLHeli debug level |
| `SERVO_BLH_MASK` | — | 0.00 | — | BLHeli Channel Bitmask |
| `SERVO_BLH_OTYPE` | — | 0.00 | — | BLHeli output type override |
| `SERVO_BLH_POLES` | — | 0.00 | — | BLHeli Motor Poles |
| `SERVO_BLH_PORT` | — | 0.00 | — | Control port |
| `SERVO_BLH_RVMASK` | — | 0.00 | — | BLHeli bitmask of reversed channels |
| `SERVO_BLH_TEST` | — | 0.00 | — | BLHeli internal interface test |
| `SERVO_BLH_TMOUT` | — | 0.00 | s | BLHeli protocol timeout |
| `SERVO_BLH_TRATE` | — | 0.00 | Hz | BLHeli telemetry rate |
| `SERVO_DSHOT_ESC` | `DSHOT_ESC_TYPE` | 0.67 | — | Servo DShot ESC type |
| `SERVO_DSHOT_RATE` | — | 0.00 | — | Servo DShot output rate |
| `SERVO_FTW_MASK` | — | 0.00 | — | Servo channel output bitmask |
| `SERVO_FTW_POLES` | — | 0.00 | — | Nr. electrical poles |
| `SERVO_FTW_RVMASK` | — | 0.00 | — | Servo channel reverse rotation bitmask |
| `SERVO_GPIO_MASK` | — | 0.00 | — | Servo GPIO mask |
| `SERVO_RATE` | — | 0.00 | Hz | Servo default output rate |
| `SERVO_RC_FS_MSK` | — | 0.00 | — | Servo RC Failsafe Mask |
| `SERVO_ROB_POSMAX` | — | 0.00 | — | Robotis servo position max |
| `SERVO_ROB_POSMIN` | — | 0.00 | — | Robotis servo position min |
| `SERVO_SBUS_RATE` | — | 0.00 | Hz | SBUS default output rate |
| `SERVO_VOLZ_MASK` | — | 0.00 | — | Channel Bitmask |
| `SERVO_VOLZ_RANGE` | — | 0.00 | deg | Range of travel |
| `SHIP_AUTO_OFS` | — | 0.00 | — | Ship automatic offset trigger |
| `SHIP_ENABLE` | — | 0.00 | — | Ship landing enable |
| `SHIP_LAND_ANGLE` | — | 0.00 | deg | Ship landing angle |
| `SID_AXIS` | — | 0.00 | — | System identification axis |
| `SID_F_START_HZ` | — | 0.00 | Hz | System identification Start Frequency |
| `SID_F_STOP_HZ` | — | 0.00 | Hz | System identification Stop Frequency |
| `SID_MAGNITUDE` | — | 0.00 | — | System identification Chirp Magnitude |
| `SID_T_FADE_IN` | — | 0.00 | s | System identification Fade in time |
| `SID_T_FADE_OUT` | — | 0.00 | s | System identification Fade out time |
| `SID_T_REC` | — | 0.00 | s | System identification Total Sweep length |
| `SIMPLE` | — | 0.00 | — | Simple mode bitmask |
| `SIM_ACC1_BIAS_X` | `SIM_MAG_OFFSET_X` | 0.45 | — | Accel 1 bias |
| `SIM_ACC1_BIAS_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | — | Accel 1 bias |
| `SIM_ACC1_BIAS_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | — | Accel 1 bias |
| `SIM_ACC1_RND` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Accel 1 motor noise factor |
| `SIM_ACC1_SCAL_X` | `SIM_MAG_OFFSET_X` | 0.45 | — | Accel 1 scaling factor |
| `SIM_ACC1_SCAL_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | — | Accel 1 scaling factor |
| `SIM_ACC1_SCAL_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | — | Accel 1 scaling factor |
| `SIM_ACC2_BIAS_X` | `SIM_MAG_OFFSET_X` | 0.45 | — | Accel 2 bias |
| `SIM_ACC2_BIAS_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | — | Accel 2 bias |
| `SIM_ACC2_BIAS_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | — | Accel 2 bias |
| `SIM_ACC2_RND` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Accel 2 motor noise factor |
| `SIM_ACC2_SCAL_X` | `SIM_MAG_OFFSET_X` | 0.45 | — | Accel 2 scaling factor |
| `SIM_ACC2_SCAL_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | — | Accel 2 scaling factor |
| `SIM_ACC2_SCAL_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | — | Accel 2 scaling factor |
| `SIM_ACC3_BIAS_X` | `SIM_MAG_OFFSET_X` | 0.45 | — | Accel 3 bias |
| `SIM_ACC3_BIAS_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | — | Accel 3 bias |
| `SIM_ACC3_BIAS_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | — | Accel 3 bias |
| `SIM_ACC3_RND` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Accel 3 motor noise factor |
| `SIM_ACC3_SCAL_X` | `SIM_MAG_OFFSET_X` | 0.45 | — | Accel 3 scaling factor |
| `SIM_ACC3_SCAL_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | — | Accel 3 scaling factor |
| `SIM_ACC3_SCAL_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | — | Accel 3 scaling factor |
| `SIM_ACC4_BIAS_X` | `SIM_MAG_OFFSET_X` | 0.45 | — | Accel 4 bias |
| `SIM_ACC4_BIAS_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | — | Accel 4 bias |
| `SIM_ACC4_BIAS_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | — | Accel 4 bias |
| `SIM_ACC4_RND` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Accel 4 motor noise factor |
| `SIM_ACC4_SCAL_X` | `SIM_MAG_OFFSET_X` | 0.45 | — | Accel 4 scaling factor |
| `SIM_ACC4_SCAL_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | — | Accel 4 scaling factor |
| `SIM_ACC4_SCAL_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | — | Accel 4 scaling factor |
| `SIM_ACC5_BIAS_X` | `SIM_MAG_OFFSET_X` | 0.45 | — | Accel 5 bias |
| `SIM_ACC5_BIAS_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | — | Accel 5 bias |
| `SIM_ACC5_BIAS_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | — | Accel 5 bias |
| `SIM_ACC5_RND` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Accel 5 motor noise factor |
| `SIM_ACC5_SCAL_X` | `SIM_MAG_OFFSET_X` | 0.45 | — | Accel 4 scaling factor |
| `SIM_ACC5_SCAL_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | — | Accel 4 scaling factor |
| `SIM_ACC5_SCAL_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | — | Accel 4 scaling factor |
| `SIM_ACCEL1_FAIL` | `SIM_ARSPD_FAIL` | 0.62 | — | ACCEL1 Failure |
| `SIM_ACCEL2_FAIL` | `SIM_ARSPD_FAIL` | 0.62 | — | ACCEL2 Failure |
| `SIM_ACCEL3_FAIL` | `SIM_ARSPD_FAIL` | 0.62 | — | ACCEL3 Failure |
| `SIM_ACCEL4_FAIL` | `SIM_ARSPD_FAIL` | 0.62 | — | ACCEL4 Failure |
| `SIM_ACCEL5_FAIL` | `SIM_ARSPD_FAIL` | 0.62 | — | ACCEL5 Failure |
| `SIM_ACC_FAIL_MSK` | `SIM_ARSPD_FAIL` | 0.52 | — | Accelerometer Failure Mask |
| `SIM_ACC_FILE_RW` | — | 0.00 | — | Accelerometer data to/from files |
| `SIM_ADSB_ALT` | `SIM_GZ_EN_LIDAR` | 0.32 | m | ADSB altitude of another aircraft |
| `SIM_ADSB_COUNT` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Number of ADSB aircrafts |
| `SIM_ADSB_RADIUS` | `SIM_GZ_EN_LIDAR` | 0.32 | m | ADSB radius stddev of another aircraft |
| `SIM_ADSB_TX` | `SIM_GZ_EN_LIDAR` | 0.32 | — | ADSB transmit enable |
| `SIM_ADSB_TYPES` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Simulated ADSB Type mask |
| `SIM_ARSPD2_FAIL` | `SIM_ARSPD_FAIL` | 1.00 | — | Airspeed sensor failure |
| `SIM_ARSPD2_FAILP` | `SIM_ARSPD_FAIL` | 0.62 | Pa | Airspeed sensor failure pressure |
| `SIM_ARSPD2_PITOT` | `SIM_ARSPD_FAIL` | 0.62 | Pa | Airspeed pitot tube failure pressure |
| `SIM_ARSPD2_RATIO` | `SIM_ARSPD_FAIL` | 0.62 | — | Airspeed ratios |
| `SIM_ARSPD2_SIGN` | `SIM_ARSPD_FAIL` | 0.62 | — | Airspeed signflip |
| `SIM_ARSPD_FAIL` | `SIM_ARSPD_FAIL` | 1.00 | — | Airspeed sensor failure |
| `SIM_ARSPD_FAILP` | `SIM_ARSPD_FAIL` | 0.62 | Pa | Airspeed sensor failure pressure |
| `SIM_ARSPD_PITOT` | `SIM_ARSPD_FAIL` | 0.62 | Pa | Airspeed pitot tube failure pressure |
| `SIM_ARSPD_RATIO` | `SIM_ARSPD_FAIL` | 0.62 | — | Airspeed ratios |
| `SIM_ARSPD_SIGN` | `SIM_ARSPD_FAIL` | 0.62 | — | Airspeed signflip |
| `SIM_BAR2_DELAY` | `SIM_GZ_EN_LIDAR` | 0.32 | ms | Barometer delay |
| `SIM_BAR2_DISABLE` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Barometer disable |
| `SIM_BAR2_DRIFT` | `SIM_GZ_EN_LIDAR` | 0.32 | m/s | Barometer altitude drift |
| `SIM_BAR2_FREEZE` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Barometer freeze |
| `SIM_BAR2_GLITCH` | `SIM_GZ_EN_LIDAR` | 0.32 | m | Barometer glitch |
| `SIM_BAR2_RND` | `SIM_GZ_EN_LIDAR` | 0.32 | m | Barometer noise |
| `SIM_BAR2_WCF_BAK` | — | 0.00 | — | Wind coefficient backward |
| `SIM_BAR2_WCF_DN` | — | 0.00 | — | Wind coefficient down |
| `SIM_BAR2_WCF_FWD` | — | 0.00 | — | Wind coefficient forward |
| `SIM_BAR2_WCF_LFT` | — | 0.00 | — | Wind coefficient left |
| `SIM_BAR2_WCF_RGT` | — | 0.00 | — | Wind coefficient right |
| `SIM_BAR2_WCF_UP` | — | 0.00 | — | Wind coefficient up |
| `SIM_BAR3_DELAY` | `SIM_GZ_EN_LIDAR` | 0.32 | ms | Barometer delay |
| `SIM_BAR3_DISABLE` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Barometer disable |
| `SIM_BAR3_DRIFT` | `SIM_GZ_EN_LIDAR` | 0.32 | m/s | Barometer altitude drift |
| `SIM_BAR3_FREEZE` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Barometer freeze |
| `SIM_BAR3_GLITCH` | `SIM_GZ_EN_LIDAR` | 0.32 | m | Barometer glitch |
| `SIM_BAR3_RND` | `SIM_GZ_EN_LIDAR` | 0.32 | m | Barometer noise |
| `SIM_BAR3_WCF_BAK` | — | 0.00 | — | Wind coefficient backward |
| `SIM_BAR3_WCF_DN` | — | 0.00 | — | Wind coefficient down |
| `SIM_BAR3_WCF_FWD` | — | 0.00 | — | Wind coefficient forward |
| `SIM_BAR3_WCF_LFT` | — | 0.00 | — | Wind coefficient left |
| `SIM_BAR3_WCF_RGT` | — | 0.00 | — | Wind coefficient right |
| `SIM_BAR3_WCF_UP` | — | 0.00 | — | Wind coefficient up |
| `SIM_BARO_COUNT` | `SIM_GZ_EN_BARO` | 0.62 | — | Baro count |
| `SIM_BARO_DELAY` | `SIM_GZ_EN_BARO` | 0.62 | ms | Barometer delay |
| `SIM_BARO_DISABLE` | `SIM_GZ_EN_BARO` | 0.62 | — | Barometer disable |
| `SIM_BARO_DRIFT` | `SIM_GZ_EN_BARO` | 0.62 | m/s | Barometer altitude drift |
| `SIM_BARO_FREEZE` | `SIM_GZ_EN_BARO` | 0.62 | — | Barometer freeze |
| `SIM_BARO_GLITCH` | `SIM_GZ_EN_BARO` | 0.62 | m | Barometer glitch |
| `SIM_BARO_RND` | `SIM_GZ_EN_BARO` | 0.62 | m | Barometer noise |
| `SIM_BARO_WCF_BAK` | `SIM_GZ_EN_BARO` | 0.52 | — | Wind coefficient backward |
| `SIM_BARO_WCF_DN` | `SIM_GZ_EN_BARO` | 0.52 | — | Wind coefficient down |
| `SIM_BARO_WCF_FWD` | `SIM_GZ_EN_BARO` | 0.52 | — | Wind coefficient forward |
| `SIM_BARO_WCF_LFT` | `SIM_GZ_EN_BARO` | 0.52 | — | Wind coefficient left |
| `SIM_BARO_WCF_RGT` | `SIM_GZ_EN_BARO` | 0.52 | — | Wind coefficient right |
| `SIM_BARO_WCF_UP` | `SIM_GZ_EN_BARO` | 0.52 | — | Wind coefficient up |
| `SIM_BATT_CAP_AH` | `SIM_BAT_DRAIN` | 0.52 | Ah | Simulated battery capacity |
| `SIM_BATT_VOLTAGE` | `SIM_BAT_DRAIN` | 0.62 | V | Simulated battery voltage |
| `SIM_BAUDLIMIT_EN` | `SIM_GZ_EN_LIDAR` | 0.37 | — | Telemetry bandwidth limitting |
| `SIM_CAN_SRV_MSK` | — | 0.00 | — | Mask of CAN servos/ESCs |
| `SIM_CAN_TYPE1` | `SIM_GZ_EN_LIDAR` | 0.37 | — | transport type for first CAN interface |
| `SIM_CAN_TYPE2` | `SIM_GZ_EN_LIDAR` | 0.37 | — | transport type for second CAN interface |
| `SIM_CLAMP_CH` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Simulated Clamp Channel |
| `SIM_DRIFT_SPEED` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Gyro drift speed |
| `SIM_DRIFT_TIME` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Gyro drift time |
| `SIM_EFI_TYPE` | `SIM_GZ_EN_LIDAR` | 0.37 | — | Type of Electronic Fuel Injection |
| `SIM_ENGINE_FAIL` | `SIM_ARSPD_FAIL` | 0.62 | — | Engine Fail Mask |
| `SIM_ENGINE_MUL` | `SIM_GZ_EN_LIDAR` | 0.32 | ms | Engine failure thrust scaler |
| `SIM_ESC_ARM_RPM` | — | 0.00 | — | ESC RPM when armed |
| `SIM_ESC_TELEM` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Simulated ESC Telemetry |
| `SIM_FLOAT_EXCEPT` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Generate floating point exceptions |
| `SIM_FLOW_DELAY` | `SIM_GZ_EN_FLOW` | 0.62 | ms | Opflow Delay |
| `SIM_FLOW_ENABLE` | `SIM_GZ_EN_FLOW` | 0.79 | — | Opflow Enable |
| `SIM_FLOW_POS_X` | `SIM_GZ_EN_FLOW` | 0.52 | m | Opflow Pos |
| `SIM_FLOW_POS_Y` | `SIM_GZ_EN_FLOW` | 0.52 | m | Opflow Pos |
| `SIM_FLOW_POS_Z` | `SIM_GZ_EN_FLOW` | 0.52 | m | Opflow Pos |
| `SIM_FLOW_RATE` | `SIM_GZ_EN_FLOW` | 0.62 | Hz | Opflow Rate |
| `SIM_FLOW_RND` | `SIM_GZ_EN_FLOW` | 0.62 | rad/s | Opflow noise |
| `SIM_GLD_BLN_BRST` | — | 0.00 | m | balloon burst height |
| `SIM_GLD_BLN_RATE` | — | 0.00 | m/s | balloon climb rate |
| `SIM_GND_BEHAV` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Ground behavior |
| `SIM_GPS2_ACC` | `SIM_GPS_USED` | 0.72 | — | GPS 2 Accuracy |
| `SIM_GPS2_ALT_OFS` | `SIM_GPS_USED` | 0.62 | m | GPS 2 Altitude Offset |
| `SIM_GPS2_BYTELOS` | `SIM_GPS_USED` | 0.72 | % | GPS 2 Byteloss |
| `SIM_GPS2_DISABLE` | `SIM_GPS_USED` | 0.72 | — | GPS 2 disable |
| `SIM_GPS2_DRFTALT` | `SIM_GPS_USED` | 0.72 | m | GPS 2 Altitude Drift |
| `SIM_GPS2_GLTCH_X` | `SIM_GPS_USED` | 0.62 | — | GPS 2 Glitch |
| `SIM_GPS2_GLTCH_Y` | `SIM_GPS_USED` | 0.62 | — | GPS 2 Glitch |
| `SIM_GPS2_GLTCH_Z` | `SIM_GPS_USED` | 0.62 | — | GPS 2 Glitch |
| `SIM_GPS2_HDG` | `SIM_GPS_USED` | 0.72 | — | GPS 2 Heading |
| `SIM_GPS2_HZ` | `SIM_GPS_USED` | 0.72 | Hz | GPS 2 Hz |
| `SIM_GPS2_JAM` | `SIM_GPS_USED` | 0.72 | — | GPS jamming enable |
| `SIM_GPS2_LAG_MS` | `SIM_GPS_USED` | 0.62 | ms | GPS 2 Lag |
| `SIM_GPS2_LCKTIME` | `SIM_GPS_USED` | 0.72 | s | GPS 2 Lock Time |
| `SIM_GPS2_NOISE` | `SIM_GPS_USED` | 0.72 | m | GPS 2 Noise |
| `SIM_GPS2_NUMSATS` | `SIM_GPS_USED` | 0.72 | — | GPS 2 Num Satellites |
| `SIM_GPS2_POS_X` | `SIM_GPS_USED` | 0.62 | m | GPS 2 Position |
| `SIM_GPS2_POS_Y` | `SIM_GPS_USED` | 0.62 | m | GPS 2 Position |
| `SIM_GPS2_POS_Z` | `SIM_GPS_USED` | 0.62 | m | GPS 2 Position |
| `SIM_GPS2_TYPE` | `SIM_GPS_USED` | 0.89 | — | GPS 2 type |
| `SIM_GPS2_VERR_X` | `SIM_GPS_USED` | 0.62 | — | GPS 2 Velocity Error |
| `SIM_GPS2_VERR_Y` | `SIM_GPS_USED` | 0.62 | — | GPS 2 Velocity Error |
| `SIM_GPS2_VERR_Z` | `SIM_GPS_USED` | 0.62 | — | GPS 2 Velocity Error |
| `SIM_GPS_ACC` | `SIM_GPS_USED` | 0.72 | — | GPS 1 Accuracy |
| `SIM_GPS_ALT_OFS` | `SIM_GPS_USED` | 0.62 | m | GPS 1 Altitude Offset |
| `SIM_GPS_BYTELOSS` | `SIM_GPS_USED` | 0.72 | % | GPS Byteloss |
| `SIM_GPS_DISABLE` | `SIM_GPS_USED` | 0.72 | — | GPS 1 disable |
| `SIM_GPS_DRIFTALT` | `SIM_GPS_USED` | 0.72 | m | GPS 1 Altitude Drift |
| `SIM_GPS_GLITCH_X` | `SIM_GPS_USED` | 0.62 | — | GPS 1 Glitch |
| `SIM_GPS_GLITCH_Y` | `SIM_GPS_USED` | 0.62 | — | GPS 1 Glitch |
| `SIM_GPS_GLITCH_Z` | `SIM_GPS_USED` | 0.62 | — | GPS 1 Glitch |
| `SIM_GPS_HDG` | `SIM_GPS_USED` | 0.72 | — | GPS 1 Heading |
| `SIM_GPS_HZ` | `SIM_GPS_USED` | 0.72 | Hz | GPS 1 Hz |
| `SIM_GPS_JAM` | `SIM_GPS_USED` | 0.72 | — | GPS jamming enable |
| `SIM_GPS_LAG_MS` | `SIM_GPS_USED` | 0.62 | ms | GPS 1 Lag |
| `SIM_GPS_LOCKTIME` | `SIM_GPS_USED` | 0.72 | s | GPS 1 Lock Time |
| `SIM_GPS_LOG_NUM` | `SIM_GPS_USED` | 0.62 | — | GPS Log Number |
| `SIM_GPS_NOISE` | `SIM_GPS_USED` | 0.72 | m | GPS 1 Noise |
| `SIM_GPS_NUMSATS` | `SIM_GPS_USED` | 0.72 | — | GPS 1 Num Satellites |
| `SIM_GPS_POS_X` | `SIM_GPS_USED` | 0.62 | m | GPS 1 Position |
| `SIM_GPS_POS_Y` | `SIM_GPS_USED` | 0.62 | m | GPS 1 Position |
| `SIM_GPS_POS_Z` | `SIM_GPS_USED` | 0.62 | m | GPS 1 Position |
| `SIM_GPS_TYPE` | `SIM_GPS_USED` | 0.89 | — | GPS 1 type |
| `SIM_GPS_VERR_X` | `SIM_GPS_USED` | 0.62 | — | GPS 1 Velocity Error |
| `SIM_GPS_VERR_Y` | `SIM_GPS_USED` | 0.62 | — | GPS 1 Velocity Error |
| `SIM_GPS_VERR_Z` | `SIM_GPS_USED` | 0.62 | — | GPS 1 Velocity Error |
| `SIM_GRPE_ENABLE` | `SIM_GZ_EN_LIDAR` | 0.37 | — | Gripper servo Sim enable/disable |
| `SIM_GRPE_PIN` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Gripper emp pin |
| `SIM_GRPS_ENABLE` | `SIM_GZ_EN_LIDAR` | 0.37 | — | Gripper servo Sim enable/disable |
| `SIM_GRPS_GRAB` | `SIM_GZ_EN_LIDAR` | 0.32 | PWM | Gripper Grab PWM |
| `SIM_GRPS_PIN` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Gripper servo pin |
| `SIM_GRPS_RELEASE` | `SIM_GZ_EN_LIDAR` | 0.32 | PWM | Gripper Release PWM |
| `SIM_GRPS_REVERSE` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Gripper close direction |
| `SIM_GYR1_BIAS_X` | `SIM_MAG_OFFSET_X` | 0.45 | rad/s | First Gyro bias on X axis |
| `SIM_GYR1_BIAS_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | rad/s | First Gyro bias on Y axis |
| `SIM_GYR1_BIAS_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | rad/s | First Gyro bias on Z axis |
| `SIM_GYR1_RND` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Gyro 1 motor noise factor |
| `SIM_GYR1_SCALE_X` | `SIM_MAG_OFFSET_X` | 0.45 | — | Gyro 1 scaling factor |
| `SIM_GYR1_SCALE_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | — | Gyro 1 scaling factor |
| `SIM_GYR1_SCALE_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | — | Gyro 1 scaling factor |
| `SIM_GYR2_BIAS_X` | `SIM_MAG_OFFSET_X` | 0.45 | rad/s | Second Gyro bias on X axis |
| `SIM_GYR2_BIAS_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | rad/s | Second Gyro bias on Y axis |
| `SIM_GYR2_BIAS_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | rad/s | Second Gyro bias on Z axis |
| `SIM_GYR2_RND` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Gyro 2 motor noise factor |
| `SIM_GYR2_SCALE_X` | `SIM_MAG_OFFSET_X` | 0.45 | — | Gyro 2 scaling factor |
| `SIM_GYR2_SCALE_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | — | Gyro 2 scaling factor |
| `SIM_GYR2_SCALE_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | — | Gyro 2 scaling factor |
| `SIM_GYR3_BIAS_X` | `SIM_MAG_OFFSET_X` | 0.45 | rad/s | Third Gyro bias on X axis |
| `SIM_GYR3_BIAS_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | rad/s | Third Gyro bias on Y axis |
| `SIM_GYR3_BIAS_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | rad/s | Third Gyro bias on Z axis |
| `SIM_GYR3_RND` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Gyro 3 motor noise factor |
| `SIM_GYR3_SCALE_X` | `SIM_MAG_OFFSET_X` | 0.45 | — | Gyro 3 scaling factor |
| `SIM_GYR3_SCALE_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | — | Gyro 3 scaling factor |
| `SIM_GYR3_SCALE_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | — | Gyro 3 scaling factor |
| `SIM_GYR4_BIAS_X` | `SIM_MAG_OFFSET_X` | 0.45 | rad/s | Fourth Gyro bias on X axis |
| `SIM_GYR4_BIAS_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | rad/s | Fourth Gyro bias on Y axis |
| `SIM_GYR4_BIAS_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | rad/s | Fourth Gyro bias on Z axis |
| `SIM_GYR4_RND` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Gyro 4 motor noise factor |
| `SIM_GYR4_SCALE_X` | `SIM_MAG_OFFSET_X` | 0.45 | — | Gyro 4 scaling factor |
| `SIM_GYR4_SCALE_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | — | Gyro 4 scaling factor |
| `SIM_GYR4_SCALE_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | — | Gyro 4 scaling factor |
| `SIM_GYR5_BIAS_X` | `SIM_MAG_OFFSET_X` | 0.45 | rad/s | Fifth Gyro bias on X axis |
| `SIM_GYR5_BIAS_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | rad/s | Fifth Gyro bias on Y axis |
| `SIM_GYR5_BIAS_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | rad/s | Fifth Gyro bias on Z axis |
| `SIM_GYR5_RND` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Gyro 5 motor noise factor |
| `SIM_GYR5_SCALE_X` | `SIM_MAG_OFFSET_X` | 0.45 | — | Gyro 5 scaling factor |
| `SIM_GYR5_SCALE_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | — | Gyro 5 scaling factor |
| `SIM_GYR5_SCALE_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | — | Gyro 5 scaling factor |
| `SIM_GYR_FAIL_MSK` | `SIM_ARSPD_FAIL` | 0.52 | — | Gyro Failure Mask |
| `SIM_GYR_FILE_RW` | — | 0.00 | — | Gyro data to/from files |
| `SIM_IMUT_END` | `SIM_GZ_EN_LIDAR` | 0.32 | — | IMU temperature end |
| `SIM_IMUT_FIXED` | `SIM_GZ_EN_LIDAR` | 0.32 | — | IMU fixed temperature |
| `SIM_IMUT_START` | `SIM_GZ_EN_LIDAR` | 0.32 | — | IMU temperature start |
| `SIM_IMUT_TCONST` | `SIM_GZ_EN_LIDAR` | 0.32 | — | IMU temperature time constant |
| `SIM_IMU_COUNT` | `SIM_GZ_EN_LIDAR` | 0.32 | — | IMU count |
| `SIM_IMU_ORIENT` | `SIM_GZ_EN_LIDAR` | 0.32 | — | IMU orientation |
| `SIM_IMU_POS_X` | `SIM_MAG_OFFSET_X` | 0.45 | m | IMU Offsets |
| `SIM_IMU_POS_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | m | IMU Offsets |
| `SIM_IMU_POS_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | m | IMU Offsets |
| `SIM_INIT_ALT_OFS` | — | 0.00 | — | Initial Altitude Offset |
| `SIM_INIT_LAT_OFS` | — | 0.00 | — | Initial Latitude Offset |
| `SIM_INIT_LON_OFS` | — | 0.00 | — | Initial Longitude Offset |
| `SIM_INS_THR_MIN` | `SIM_GZ_EC_MIN10` | 0.45 | — | Minimum throttle INS noise |
| `SIM_JSON_MASTER` | `SIM_GZ_EN_LIDAR` | 0.32 | — | JSON master instance |
| `SIM_LED_LAYOUT` | `SIM_GZ_EN_LIDAR` | 0.32 | — | LED layout |
| `SIM_LOOP_DELAY` | `SIM_GZ_EN_LIDAR` | 0.32 | us | Extra delay per main loop |
| `SIM_MAG1_DEVID` | `SIM_MAG_OFFSET_X` | 0.52 | — | MAG1 Device ID |
| `SIM_MAG1_FAIL` | `SIM_ARSPD_FAIL` | 0.62 | — | MAG1 Failure |
| `SIM_MAG1_ORIENT` | `SIM_MAG_OFFSET_X` | 0.52 | — | MAG1 Orientation |
| `SIM_MAG1_SCALING` | `SIM_MAG_OFFSET_X` | 0.52 | — | MAG1 Scaling factor |
| `SIM_MAG2_DEVID` | `SIM_MAG_OFFSET_X` | 0.52 | — | MAG2 Device ID |
| `SIM_MAG2_FAIL` | `SIM_ARSPD_FAIL` | 0.62 | — | MAG2 Failure |
| `SIM_MAG2_ORIENT` | `SIM_MAG_OFFSET_X` | 0.52 | — | MAG2 Orientation |
| `SIM_MAG2_SCALING` | `SIM_MAG_OFFSET_X` | 0.52 | — | MAG2 Scaling factor |
| `SIM_MAG3_DEVID` | `SIM_MAG_OFFSET_X` | 0.52 | — | MAG3 Device ID |
| `SIM_MAG3_FAIL` | `SIM_ARSPD_FAIL` | 0.62 | — | MAG3 Failure |
| `SIM_MAG3_ORIENT` | `SIM_MAG_OFFSET_X` | 0.52 | — | MAG3 Orientation |
| `SIM_MAG3_SCALING` | `SIM_MAG_OFFSET_X` | 0.52 | — | MAG3 Scaling factor |
| `SIM_MAG4_DEVID` | `SIM_MAG_OFFSET_X` | 0.52 | — | MAG2 Device ID |
| `SIM_MAG5_DEVID` | `SIM_MAG_OFFSET_X` | 0.52 | — | MAG5 Device ID |
| `SIM_MAG6_DEVID` | `SIM_MAG_OFFSET_X` | 0.52 | — | MAG6 Device ID |
| `SIM_MAG7_DEVID` | `SIM_MAG_OFFSET_X` | 0.52 | — | MAG7 Device ID |
| `SIM_MAG8_DEVID` | `SIM_MAG_OFFSET_X` | 0.52 | — | MAG8 Device ID |
| `SIM_MAG_ALY_HGT` | `SIM_MAG_OFFSET_X` | 0.45 | m | Magnetic anomaly height |
| `SIM_MAG_DELAY` | `SIM_MAG_OFFSET_X` | 0.52 | ms | Mag measurement delay |
| `SIM_MAG_RND` | `SIM_MAG_OFFSET_X` | 0.52 | — | Mag motor noise factor |
| `SIM_MAG_SAVE_IDS` | `SIM_MAG_OFFSET_X` | 0.45 | — | Save MAG devids on startup |
| `SIM_ODOM_ENABLE` | `SIM_GZ_EN_ODOM` | 0.79 | — | Odometry enable |
| `SIM_OH_MASK` | `SIM_GZ_EN_LIDAR` | 0.32 | — | SIM-on_hardware Output Enable Mask |
| `SIM_OH_RELAY_MSK` | — | 0.00 | — | SIM-on_hardware Relay Enable Mask |
| `SIM_OPOS_ALT` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Original Position (Altitude) |
| `SIM_OPOS_HDG` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Original Position (Heading) |
| `SIM_OPOS_LAT` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Original Position (Latitude) |
| `SIM_OPOS_LNG` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Original Position (Longitude) |
| `SIM_OSD_COLUMNS` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Simulated OSD number of text columns |
| `SIM_OSD_ROWS` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Simulated OSD number of text rows |
| `SIM_PIN_MASK` | `SIM_GZ_EN_LIDAR` | 0.32 | — | GPIO emulation |
| `SIM_PLD_ALT_LIMIT` | `PLD_SRCH_ALT` | 0.40 | m | Precland device alt range |
| `SIM_PLD_DIST_LIMIT` | — | 0.00 | m | Precland device lateral range |
| `SIM_PLD_ENABLE` | `SIM_GZ_EN_LIDAR` | 0.37 | — | Preland device Sim enable/disable |
| `SIM_PLD_HEIGHT` | `SIM_GZ_EN_LIDAR` | 0.32 | m | Precland device center's height SITL origin |
| `SIM_PLD_LAT` | `SIM_GZ_EN_LIDAR` | 0.32 | deg | Precland device center's latitude |
| `SIM_PLD_LON` | `SIM_GZ_EN_LIDAR` | 0.32 | deg | Precland device center's longitude |
| `SIM_PLD_OPTIONS` | `SIM_GZ_EN_LIDAR` | 0.32 | — | SIM_Precland extra options |
| `SIM_PLD_ORIENT` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Precland device orientation |
| `SIM_PLD_RATE` | `SIM_GZ_EN_LIDAR` | 0.32 | Hz | Precland device update rate |
| `SIM_PLD_SHIP` | `SIM_GZ_EN_LIDAR` | 0.32 | — | SIM_Precland follow ship |
| `SIM_PLD_TYPE` | `SIM_GZ_EN_LIDAR` | 0.37 | — | Precland device radiance type |
| `SIM_PLD_YAW` | `SIM_GZ_EN_LIDAR` | 0.32 | deg | Precland device systems rotation from north |
| `SIM_RATE_HZ` | `SIM_GZ_EN_LIDAR` | 0.32 | Hz | Loop rate |
| `SIM_RC_CHANCOUNT` | `SIM_GZ_EN_LIDAR` | 0.32 | — | RC channel count |
| `SIM_RC_FAIL` | `SIM_ARSPD_FAIL` | 0.62 | — | Simulated RC signal failure |
| `SIM_RFL_OPTS` | `SIM_GZ_EN_LIDAR` | 0.32 | — | FlightAxis options |
| `SIM_SB_ALT_TARG` | — | 0.00 | m | altitude target |
| `SIM_SB_ARM_LEN` | — | 0.00 | m | arm length |
| `SIM_SB_CLMB_RT` | — | 0.00 | m/s | target climb rate |
| `SIM_SB_COL` | `SIM_GZ_EN_LIDAR` | 0.32 | m | center of lift |
| `SIM_SB_DRAG_FWD` | — | 0.00 | — | drag in forward direction |
| `SIM_SB_DRAG_SIDE` | — | 0.00 | — | drag in sidewards direction |
| `SIM_SB_DRAG_UP` | — | 0.00 | — | drag in upward direction |
| `SIM_SB_FLR` | `SIM_GZ_EN_LIDAR` | 0.32 | — | free lift rate |
| `SIM_SB_HMASS` | `SIM_GZ_EN_LIDAR` | 0.32 | kg | helium mass |
| `SIM_SB_MASS` | `SIM_GZ_EN_LIDAR` | 0.32 | kg | mass |
| `SIM_SB_MOI_PITCH` | — | 0.00 | — | moment of inertia in pitch |
| `SIM_SB_MOI_ROLL` | — | 0.00 | — | moment of inertia in roll |
| `SIM_SB_MOI_YAW` | — | 0.00 | — | moment of inertia in yaw |
| `SIM_SB_MOT_ANG` | — | 0.00 | deg | motor angle |
| `SIM_SB_MOT_THST` | — | 0.00 | N | motor thrust |
| `SIM_SB_WVANE` | `SIM_GZ_EN_LIDAR` | 0.32 | m | weathervaning offset |
| `SIM_SB_YAW_RT` | — | 0.00 | deg/s | yaw rate |
| `SIM_SERVO_DELAY` | `SIM_GZ_EN_LIDAR` | 0.32 | s | servo delay |
| `SIM_SERVO_FILTER` | `SIM_GZ_EN_LIDAR` | 0.32 | Hz | servo filter |
| `SIM_SERVO_SPEED` | `SIM_GZ_EN_LIDAR` | 0.32 | s | servo speed |
| `SIM_SHOVE_TIME` | `SIM_GZ_EN_LIDAR` | 0.32 | ms | Time length for shove |
| `SIM_SHOVE_X` | `SIM_MAG_OFFSET_X` | 0.52 | m/s/s | Acceleration of shove x |
| `SIM_SHOVE_Y` | `SIM_MAG_OFFSET_Y` | 0.52 | m/s/s | Acceleration of shove y |
| `SIM_SHOVE_Z` | `SIM_MAG_OFFSET_Z` | 0.52 | m/s/s | Acceleration of shove z |
| `SIM_SLUP_DRAG` | `SIM_GZ_EN_LIDAR` | 0.32 | m | Slung Payload drag coefficient |
| `SIM_SLUP_ENABLE` | `SIM_GZ_EN_LIDAR` | 0.37 | — | Slung Payload Sim enable/disable |
| `SIM_SLUP_LINELEN` | `SIM_GZ_EN_LIDAR` | 0.32 | m | Slung Payload line length |
| `SIM_SLUP_SYSID` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Slung Payload MAVLink system ID |
| `SIM_SLUP_WEIGHT` | `SIM_GZ_EN_LIDAR` | 0.32 | kg | Slung Payload weight |
| `SIM_SONAR_GLITCH` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Sonar glitch probablility |
| `SIM_SONAR_RND` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Sonar noise factor |
| `SIM_SONAR_ROT` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Sonar rotation |
| `SIM_SONAR_SCALE` | `SIM_GZ_EN_LIDAR` | 0.32 | m/V | Sonar conversion scale |
| `SIM_SPEEDUP` | `SIM_GZ_EN_LIDAR` | 0.37 | — | Sim Speedup |
| `SIM_SPR_ENABLE` | `SIM_GZ_EN_LIDAR` | 0.37 | — | Sprayer Sim enable/disable |
| `SIM_SPR_PUMP` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Sprayer pump pin |
| `SIM_SPR_SPIN` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Sprayer spinner servo pin |
| `SIM_TEMP_BFACTOR` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Baro temperature factor |
| `SIM_TEMP_BRD_OFF` | `SIM_BARO_OFF_T` | 0.45 | degC | Baro temperature offset |
| `SIM_TEMP_START` | `SIM_GZ_EN_LIDAR` | 0.32 | degC | Start temperature |
| `SIM_TEMP_TCONST` | `SIM_GZ_EN_LIDAR` | 0.32 | degC | Warmup time constant |
| `SIM_TERRAIN` | `SIM_GZ_EN_LIDAR` | 0.37 | — | Terrain Enable |
| `SIM_THML_SCENARI` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Thermal scenarios |
| `SIM_TIDE_DIR` | `SIM_GZ_EN_LIDAR` | 0.32 | deg | Tide direction |
| `SIM_TIDE_SPEED` | `SIM_GZ_EN_LIDAR` | 0.32 | m/s | Tide speed |
| `SIM_TIME_JITTER` | `SIM_GZ_EN_LIDAR` | 0.32 | us | Loop time jitter |
| `SIM_TWIST_TIME` | `SIM_GZ_EN_LIDAR` | 0.32 | ms | Twist time |
| `SIM_TWIST_X` | `SIM_MAG_OFFSET_X` | 0.52 | rad/s/s | Twist x |
| `SIM_TWIST_Y` | `SIM_MAG_OFFSET_Y` | 0.52 | rad/s/s | Twist y |
| `SIM_TWIST_Z` | `SIM_MAG_OFFSET_Z` | 0.52 | rad/s/s | Twist z |
| `SIM_UART_LOSS` | `SIM_GZ_EN_LIDAR` | 0.32 | % | UART byte loss percentage |
| `SIM_VIB_MOT_HMNC` | — | 0.00 | — | Motor harmonics |
| `SIM_VIB_MOT_MASK` | — | 0.00 | — | Motor mask |
| `SIM_VIB_MOT_MAX` | `SIM_GZ_EC_MAX13` | 0.45 | Hz | Max motor vibration frequency |
| `SIM_VIB_MOT_MULT` | — | 0.00 | — | Vibration motor scale |
| `SIM_VICON_FAIL` | `SIM_ARSPD_FAIL` | 0.62 | — | SITL vicon failure |
| `SIM_VICON_GLIT_X` | `SIM_MAG_OFFSET_X` | 0.45 | m | SITL vicon position glitch North |
| `SIM_VICON_GLIT_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | m | SITL vicon position glitch East |
| `SIM_VICON_GLIT_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | m | SITL vicon position glitch Down |
| `SIM_VICON_POS_X` | `SIM_MAG_OFFSET_X` | 0.45 | m | SITL vicon position on vehicle in Forward direction |
| `SIM_VICON_POS_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | m | SITL vicon position on vehicle in Right direction |
| `SIM_VICON_POS_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | m | SITL vicon position on vehicle in Down direction |
| `SIM_VICON_TMASK` | `SIM_GZ_EN_LIDAR` | 0.32 | — | SITL vicon type mask |
| `SIM_VICON_VGLI_X` | `SIM_MAG_OFFSET_X` | 0.45 | m/s | SITL vicon velocity glitch North |
| `SIM_VICON_VGLI_Y` | `SIM_MAG_OFFSET_Y` | 0.45 | m/s | SITL vicon velocity glitch East |
| `SIM_VICON_VGLI_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | m/s | SITL vicon velocity glitch Down |
| `SIM_VICON_YAW` | `SIM_GZ_EN_LIDAR` | 0.32 | deg | SITL vicon yaw angle in earth frame |
| `SIM_VICON_YAWERR` | `SIM_GZ_EN_LIDAR` | 0.32 | deg | SITL vicon yaw error |
| `SIM_WAVE_AMP` | `SIM_GZ_EN_LIDAR` | 0.32 | m | Wave amplitude |
| `SIM_WAVE_DIR` | `SIM_GZ_EN_LIDAR` | 0.32 | deg | Wave direction |
| `SIM_WAVE_ENABLE` | `SIM_GZ_EN_LIDAR` | 0.37 | — | Wave enable |
| `SIM_WAVE_LENGTH` | `SIM_GZ_EN_LIDAR` | 0.32 | m | Wave length |
| `SIM_WAVE_SPEED` | `SIM_GZ_EN_LIDAR` | 0.32 | m/s | Wave speed |
| `SIM_WIND_DIR` | `SIM_GZ_EN_LIDAR` | 0.32 | deg | Direction simulated wind is coming from |
| `SIM_WIND_DIR_Z` | `SIM_MAG_OFFSET_Z` | 0.45 | deg | Simulated wind vertical direction |
| `SIM_WIND_SPD` | `SIM_GZ_EN_LIDAR` | 0.32 | m/s | Simulated Wind speed |
| `SIM_WIND_T` | `SIM_BARO_OFF_T` | 0.52 | — | Wind Profile Type |
| `SIM_WIND_TC` | `SIM_GZ_EN_LIDAR` | 0.32 | s | Wind variation time constant |
| `SIM_WIND_TURB` | `SIM_GZ_EN_LIDAR` | 0.32 | m/s | Simulated Wind variation |
| `SIM_WIND_T_ALT` | `SIM_BARO_OFF_T` | 0.45 | m | Full Wind Altitude |
| `SIM_WIND_T_COEF` | `SIM_BARO_OFF_T` | 0.45 | — | Linear Wind Curve Coeff |
| `SIM_WOW_PIN` | `SIM_GZ_EN_LIDAR` | 0.32 | — | Weight on Wheels Pin |
| `SLUP_DEBUG` | — | 0.00 | — | Slung Payload debug output |
| `SLUP_DIST_MAX` | — | 0.00 | — | Slung Payload horizontal distance max |
| `SLUP_ENABLE` | — | 0.00 | — | Slung Payload enable |
| `SLUP_RESTOFS_TC` | — | 0.00 | — | Slung Payload resting offset estimate filter time constant |
| `SLUP_SYSID` | — | 0.00 | — | Slung Payload mavlink system id |
| `SLUP_VEL_P` | — | 0.00 | — | Slung Payload Velocity P gain |
| `SLUP_WP_POS_P` | — | 0.00 | — | Slung Payload return to WP position P gain |
| `SPRAY_ENABLE` | — | 0.00 | — | Sprayer enable/disable |
| `SPRAY_PUMP_MIN` | — | 0.00 | % | Pump speed minimum |
| `SPRAY_PUMP_RATE` | — | 0.00 | % | Pump speed |
| `SPRAY_SPEED_MIN` | — | 0.00 | cm/s | Speed minimum |
| `SPRAY_SPINNER` | — | 0.00 | ms | Spinner rotation speed |
| `SR0_ADSB` | `ADSB_EMIT_TYPE` | 0.33 | Hz | ADSB stream rate |
| `SR0_EXTRA1` | — | 0.00 | — | Extra data type 1 stream rate |
| `SR0_EXTRA2` | — | 0.00 | Hz | Extra data type 2 stream rate |
| `SR0_EXTRA3` | — | 0.00 | — | Extra data type 3 stream rate |
| `SR0_EXT_STAT` | — | 0.00 | Hz | Extended status stream rate |
| `SR0_PARAMS` | — | 0.00 | Hz | Parameter stream rate |
| `SR0_POSITION` | — | 0.00 | Hz | Position stream rate |
| `SR0_RAW_CTRL` | — | 0.00 | Hz | Unused |
| `SR0_RAW_SENS` | `SENS_EN_SR05` | 0.67 | Hz | Raw sensor stream rate |
| `SR0_RC_CHAN` | `RC_CHAN_CNT` | 0.50 | Hz | RC Channel stream rate |
| `SR1_ADSB` | `ADSB_EMIT_TYPE` | 0.33 | Hz | ADSB stream rate |
| `SR1_EXTRA1` | — | 0.00 | — | Extra data type 1 stream rate |
| `SR1_EXTRA2` | — | 0.00 | Hz | Extra data type 2 stream rate |
| `SR1_EXTRA3` | — | 0.00 | — | Extra data type 3 stream rate |
| `SR1_EXT_STAT` | — | 0.00 | Hz | Extended status stream rate |
| `SR1_PARAMS` | — | 0.00 | Hz | Parameter stream rate |
| `SR1_POSITION` | — | 0.00 | Hz | Position stream rate |
| `SR1_RAW_CTRL` | — | 0.00 | Hz | Unused |
| `SR1_RAW_SENS` | `SENS_EN_SR05` | 0.67 | Hz | Raw sensor stream rate |
| `SR1_RC_CHAN` | `RC_CHAN_CNT` | 0.50 | Hz | RC Channel stream rate |
| `SR2_ADSB` | `ADSB_EMIT_TYPE` | 0.33 | Hz | ADSB stream rate |
| `SR2_EXTRA1` | — | 0.00 | — | Extra data type 1 stream rate |
| `SR2_EXTRA2` | — | 0.00 | Hz | Extra data type 2 stream rate |
| `SR2_EXTRA3` | — | 0.00 | — | Extra data type 3 stream rate |
| `SR2_EXT_STAT` | — | 0.00 | Hz | Extended status stream rate |
| `SR2_PARAMS` | — | 0.00 | Hz | Parameter stream rate |
| `SR2_POSITION` | — | 0.00 | Hz | Position stream rate |
| `SR2_RAW_CTRL` | — | 0.00 | Hz | Unused |
| `SR2_RAW_SENS` | `SENS_EN_SR05` | 0.67 | Hz | Raw sensor stream rate |
| `SR2_RC_CHAN` | `RC_CHAN_CNT` | 0.50 | Hz | RC Channel stream rate |
| `SR3_ADSB` | `ADSB_EMIT_TYPE` | 0.33 | Hz | ADSB stream rate |
| `SR3_EXTRA1` | — | 0.00 | — | Extra data type 1 stream rate |
| `SR3_EXTRA2` | — | 0.00 | Hz | Extra data type 2 stream rate |
| `SR3_EXTRA3` | — | 0.00 | — | Extra data type 3 stream rate |
| `SR3_EXT_STAT` | — | 0.00 | Hz | Extended status stream rate |
| `SR3_PARAMS` | — | 0.00 | Hz | Parameter stream rate |
| `SR3_POSITION` | — | 0.00 | Hz | Position stream rate |
| `SR3_RAW_CTRL` | — | 0.00 | Hz | Unused |
| `SR3_RAW_SENS` | `SENS_EN_SR05` | 0.67 | Hz | Raw sensor stream rate |
| `SR3_RC_CHAN` | `RC_CHAN_CNT` | 0.50 | Hz | RC Channel stream rate |
| `SR4_ADSB` | `ADSB_EMIT_TYPE` | 0.33 | Hz | ADSB stream rate |
| `SR4_EXTRA1` | — | 0.00 | — | Extra data type 1 stream rate |
| `SR4_EXTRA2` | — | 0.00 | Hz | Extra data type 2 stream rate |
| `SR4_EXTRA3` | — | 0.00 | — | Extra data type 3 stream rate |
| `SR4_EXT_STAT` | — | 0.00 | Hz | Extended status stream rate |
| `SR4_PARAMS` | — | 0.00 | Hz | Parameter stream rate |
| `SR4_POSITION` | — | 0.00 | Hz | Position stream rate |
| `SR4_RAW_CTRL` | — | 0.00 | Hz | Unused |
| `SR4_RAW_SENS` | `SENS_EN_SR05` | 0.67 | Hz | Raw sensor stream rate |
| `SR4_RC_CHAN` | `RC_CHAN_CNT` | 0.50 | Hz | RC Channel stream rate |
| `SR5_ADSB` | `ADSB_EMIT_TYPE` | 0.33 | Hz | ADSB stream rate |
| `SR5_EXTRA1` | — | 0.00 | — | Extra data type 1 stream rate |
| `SR5_EXTRA2` | — | 0.00 | Hz | Extra data type 2 stream rate |
| `SR5_EXTRA3` | — | 0.00 | — | Extra data type 3 stream rate |
| `SR5_EXT_STAT` | — | 0.00 | Hz | Extended status stream rate |
| `SR5_PARAMS` | — | 0.00 | Hz | Parameter stream rate |
| `SR5_POSITION` | — | 0.00 | Hz | Position stream rate |
| `SR5_RAW_CTRL` | — | 0.00 | Hz | Unused |
| `SR5_RAW_SENS` | `SENS_EN_SR05` | 0.67 | Hz | Raw sensor stream rate |
| `SR5_RC_CHAN` | `RC_CHAN_CNT` | 0.50 | Hz | RC Channel stream rate |
| `SR6_ADSB` | `ADSB_EMIT_TYPE` | 0.33 | Hz | ADSB stream rate |
| `SR6_EXTRA1` | — | 0.00 | — | Extra data type 1 stream rate |
| `SR6_EXTRA2` | — | 0.00 | Hz | Extra data type 2 stream rate |
| `SR6_EXTRA3` | — | 0.00 | — | Extra data type 3 stream rate |
| `SR6_EXT_STAT` | — | 0.00 | Hz | Extended status stream rate |
| `SR6_PARAMS` | — | 0.00 | Hz | Parameter stream rate |
| `SR6_POSITION` | — | 0.00 | Hz | Position stream rate |
| `SR6_RAW_CTRL` | — | 0.00 | Hz | Unused |
| `SR6_RAW_SENS` | `SENS_EN_SR05` | 0.67 | Hz | Raw sensor stream rate |
| `SR6_RC_CHAN` | `RC_CHAN_CNT` | 0.50 | Hz | RC Channel stream rate |
| `SRTL_ACCURACY` | — | 0.00 | m | SmartRTL accuracy |
| `SRTL_OPTIONS` | — | 0.00 | — | SmartRTL options |
| `SRTL_POINTS` | — | 0.00 | — | SmartRTL maximum number of points on path |
| `STAT_BOOTCNT` | — | 0.00 | — | Boot Count |
| `STAT_FLTTIME` | — | 0.00 | s | Total FlightTime |
| `STAT_RESET` | — | 0.00 | s | Statistics Reset Time |
| `STAT_RUNTIME` | — | 0.00 | s | Total RunTime |
| `SUPER_SIMPLE` | — | 0.00 | — | Super Simple Mode |
| `SURFTRAK_MODE` | — | 0.00 | — | Surface Tracking Mode |
| `SURFTRAK_TC` | `TC_A_ENABLE` | 0.33 | s | Surface Tracking Filter Time Constant |
| `SYSID_ENFORCE` | — | 0.00 | — | GCS sysid enforcement |
| `SYSID_MYGCS` | — | 0.00 | — | My ground station number |
| `SYSID_THISMAV` | — | 0.00 | — | MAVLink system ID of this vehicle |
| `TCAL_BARO_EXP` | — | 0.00 | — | Temperature Calibration barometer exponent |
| `TCAL_ENABLED` | — | 0.00 | — | Temperature calibration enable |
| `TCAL_TEMP_MAX` | — | 0.00 | degC | Temperature calibration max learned temperature |
| `TCAL_TEMP_MIN` | — | 0.00 | degC | Temperature calibration min learned temperature |
| `TELEM_DELAY` | — | 0.00 | s | Telemetry startup delay |
| `TEMP1_A0` | — | 0.00 | — | Temperature sensor analog 0th polynomial coefficient |
| `TEMP1_A1` | — | 0.00 | — | Temperature sensor analog 1st polynomial coefficient |
| `TEMP1_A2` | — | 0.00 | — | Temperature sensor analog 2nd polynomial coefficient |
| `TEMP1_A3` | — | 0.00 | — | Temperature sensor analog 3rd polynomial coefficient |
| `TEMP1_A4` | — | 0.00 | — | Temperature sensor analog 4th polynomial coefficient |
| `TEMP1_A5` | — | 0.00 | — | Temperature sensor analog 5th polynomial coefficient |
| `TEMP1_ADDR` | — | 0.00 | — | Temperature sensor address |
| `TEMP1_BUS` | — | 0.00 | — | Temperature sensor bus |
| `TEMP1_PIN` | — | 0.00 | — | Temperature sensor analog voltage sensing pin |
| `TEMP1_SRC` | — | 0.00 | — | Sensor Source |
| `TEMP1_SRC_ID` | — | 0.00 | — | Sensor Source Identification |
| `TEMP1_TYPE` | — | 0.00 | — | Temperature Sensor Type |
| `TEMP2_A0` | — | 0.00 | — | Temperature sensor analog 0th polynomial coefficient |
| `TEMP2_A1` | — | 0.00 | — | Temperature sensor analog 1st polynomial coefficient |
| `TEMP2_A2` | — | 0.00 | — | Temperature sensor analog 2nd polynomial coefficient |
| `TEMP2_A3` | — | 0.00 | — | Temperature sensor analog 3rd polynomial coefficient |
| `TEMP2_A4` | — | 0.00 | — | Temperature sensor analog 4th polynomial coefficient |
| `TEMP2_A5` | — | 0.00 | — | Temperature sensor analog 5th polynomial coefficient |
| `TEMP2_ADDR` | — | 0.00 | — | Temperature sensor address |
| `TEMP2_BUS` | — | 0.00 | — | Temperature sensor bus |
| `TEMP2_PIN` | — | 0.00 | — | Temperature sensor analog voltage sensing pin |
| `TEMP2_SRC` | — | 0.00 | — | Sensor Source |
| `TEMP2_SRC_ID` | — | 0.00 | — | Sensor Source Identification |
| `TEMP2_TYPE` | — | 0.00 | — | Temperature Sensor Type |
| `TEMP3_A0` | — | 0.00 | — | Temperature sensor analog 0th polynomial coefficient |
| `TEMP3_A1` | — | 0.00 | — | Temperature sensor analog 1st polynomial coefficient |
| `TEMP3_A2` | — | 0.00 | — | Temperature sensor analog 2nd polynomial coefficient |
| `TEMP3_A3` | — | 0.00 | — | Temperature sensor analog 3rd polynomial coefficient |
| `TEMP3_A4` | — | 0.00 | — | Temperature sensor analog 4th polynomial coefficient |
| `TEMP3_A5` | — | 0.00 | — | Temperature sensor analog 5th polynomial coefficient |
| `TEMP3_ADDR` | — | 0.00 | — | Temperature sensor address |
| `TEMP3_BUS` | — | 0.00 | — | Temperature sensor bus |
| `TEMP3_PIN` | — | 0.00 | — | Temperature sensor analog voltage sensing pin |
| `TEMP3_SRC` | — | 0.00 | — | Sensor Source |
| `TEMP3_SRC_ID` | — | 0.00 | — | Sensor Source Identification |
| `TEMP3_TYPE` | — | 0.00 | — | Temperature Sensor Type |
| `TEMP4_A0` | — | 0.00 | — | Temperature sensor analog 0th polynomial coefficient |
| `TEMP4_A1` | — | 0.00 | — | Temperature sensor analog 1st polynomial coefficient |
| `TEMP4_A2` | — | 0.00 | — | Temperature sensor analog 2nd polynomial coefficient |
| `TEMP4_A3` | — | 0.00 | — | Temperature sensor analog 3rd polynomial coefficient |
| `TEMP4_A4` | — | 0.00 | — | Temperature sensor analog 4th polynomial coefficient |
| `TEMP4_A5` | — | 0.00 | — | Temperature sensor analog 5th polynomial coefficient |
| `TEMP4_ADDR` | — | 0.00 | — | Temperature sensor address |
| `TEMP4_BUS` | — | 0.00 | — | Temperature sensor bus |
| `TEMP4_PIN` | — | 0.00 | — | Temperature sensor analog voltage sensing pin |
| `TEMP4_SRC` | — | 0.00 | — | Sensor Source |
| `TEMP4_SRC_ID` | — | 0.00 | — | Sensor Source Identification |
| `TEMP4_TYPE` | — | 0.00 | — | Temperature Sensor Type |
| `TEMP5_A0` | — | 0.00 | — | Temperature sensor analog 0th polynomial coefficient |
| `TEMP5_A1` | — | 0.00 | — | Temperature sensor analog 1st polynomial coefficient |
| `TEMP5_A2` | — | 0.00 | — | Temperature sensor analog 2nd polynomial coefficient |
| `TEMP5_A3` | — | 0.00 | — | Temperature sensor analog 3rd polynomial coefficient |
| `TEMP5_A4` | — | 0.00 | — | Temperature sensor analog 4th polynomial coefficient |
| `TEMP5_A5` | — | 0.00 | — | Temperature sensor analog 5th polynomial coefficient |
| `TEMP5_ADDR` | — | 0.00 | — | Temperature sensor address |
| `TEMP5_BUS` | — | 0.00 | — | Temperature sensor bus |
| `TEMP5_PIN` | — | 0.00 | — | Temperature sensor analog voltage sensing pin |
| `TEMP5_SRC` | — | 0.00 | — | Sensor Source |
| `TEMP5_SRC_ID` | — | 0.00 | — | Sensor Source Identification |
| `TEMP5_TYPE` | — | 0.00 | — | Temperature Sensor Type |
| `TEMP6_A0` | — | 0.00 | — | Temperature sensor analog 0th polynomial coefficient |
| `TEMP6_A1` | — | 0.00 | — | Temperature sensor analog 1st polynomial coefficient |
| `TEMP6_A2` | — | 0.00 | — | Temperature sensor analog 2nd polynomial coefficient |
| `TEMP6_A3` | — | 0.00 | — | Temperature sensor analog 3rd polynomial coefficient |
| `TEMP6_A4` | — | 0.00 | — | Temperature sensor analog 4th polynomial coefficient |
| `TEMP6_A5` | — | 0.00 | — | Temperature sensor analog 5th polynomial coefficient |
| `TEMP6_ADDR` | — | 0.00 | — | Temperature sensor address |
| `TEMP6_BUS` | — | 0.00 | — | Temperature sensor bus |
| `TEMP6_PIN` | — | 0.00 | — | Temperature sensor analog voltage sensing pin |
| `TEMP6_SRC` | — | 0.00 | — | Sensor Source |
| `TEMP6_SRC_ID` | — | 0.00 | — | Sensor Source Identification |
| `TEMP6_TYPE` | — | 0.00 | — | Temperature Sensor Type |
| `TEMP7_A0` | — | 0.00 | — | Temperature sensor analog 0th polynomial coefficient |
| `TEMP7_A1` | — | 0.00 | — | Temperature sensor analog 1st polynomial coefficient |
| `TEMP7_A2` | — | 0.00 | — | Temperature sensor analog 2nd polynomial coefficient |
| `TEMP7_A3` | — | 0.00 | — | Temperature sensor analog 3rd polynomial coefficient |
| `TEMP7_A4` | — | 0.00 | — | Temperature sensor analog 4th polynomial coefficient |
| `TEMP7_A5` | — | 0.00 | — | Temperature sensor analog 5th polynomial coefficient |
| `TEMP7_ADDR` | — | 0.00 | — | Temperature sensor address |
| `TEMP7_BUS` | — | 0.00 | — | Temperature sensor bus |
| `TEMP7_PIN` | — | 0.00 | — | Temperature sensor analog voltage sensing pin |
| `TEMP7_SRC` | — | 0.00 | — | Sensor Source |
| `TEMP7_SRC_ID` | — | 0.00 | — | Sensor Source Identification |
| `TEMP7_TYPE` | — | 0.00 | — | Temperature Sensor Type |
| `TEMP8_A0` | — | 0.00 | — | Temperature sensor analog 0th polynomial coefficient |
| `TEMP8_A1` | — | 0.00 | — | Temperature sensor analog 1st polynomial coefficient |
| `TEMP8_A2` | — | 0.00 | — | Temperature sensor analog 2nd polynomial coefficient |
| `TEMP8_A3` | — | 0.00 | — | Temperature sensor analog 3rd polynomial coefficient |
| `TEMP8_A4` | — | 0.00 | — | Temperature sensor analog 4th polynomial coefficient |
| `TEMP8_A5` | — | 0.00 | — | Temperature sensor analog 5th polynomial coefficient |
| `TEMP8_ADDR` | — | 0.00 | — | Temperature sensor address |
| `TEMP8_BUS` | — | 0.00 | — | Temperature sensor bus |
| `TEMP8_PIN` | — | 0.00 | — | Temperature sensor analog voltage sensing pin |
| `TEMP8_SRC` | — | 0.00 | — | Sensor Source |
| `TEMP8_SRC_ID` | — | 0.00 | — | Sensor Source Identification |
| `TEMP8_TYPE` | — | 0.00 | — | Temperature Sensor Type |
| `TEMP9_A0` | — | 0.00 | — | Temperature sensor analog 0th polynomial coefficient |
| `TEMP9_A1` | — | 0.00 | — | Temperature sensor analog 1st polynomial coefficient |
| `TEMP9_A2` | — | 0.00 | — | Temperature sensor analog 2nd polynomial coefficient |
| `TEMP9_A3` | — | 0.00 | — | Temperature sensor analog 3rd polynomial coefficient |
| `TEMP9_A4` | — | 0.00 | — | Temperature sensor analog 4th polynomial coefficient |
| `TEMP9_A5` | — | 0.00 | — | Temperature sensor analog 5th polynomial coefficient |
| `TEMP9_ADDR` | — | 0.00 | — | Temperature sensor address |
| `TEMP9_BUS` | — | 0.00 | — | Temperature sensor bus |
| `TEMP9_PIN` | — | 0.00 | — | Temperature sensor analog voltage sensing pin |
| `TEMP9_SRC` | — | 0.00 | — | Sensor Source |
| `TEMP9_SRC_ID` | — | 0.00 | — | Sensor Source Identification |
| `TEMP9_TYPE` | — | 0.00 | — | Temperature Sensor Type |
| `TEMP_LOG` | — | 0.00 | — | Logging |
| `TERRAIN_CACHE_SZ` | — | 0.00 | — | Terrain cache size |
| `TERRAIN_ENABLE` | — | 0.00 | — | Terrain data enable |
| `TERRAIN_MARGIN` | — | 0.00 | m | Acceptance margin |
| `TERRAIN_OFS_MAX` | — | 0.00 | m | Terrain reference offset maximum |
| `TERRAIN_OPTIONS` | — | 0.00 | — | Terrain options |
| `TERRAIN_SPACING` | — | 0.00 | m | Terrain grid spacing |
| `TERR_BRK_ALT` | — | 0.00 | m | terrain brake altitude |
| `TERR_BRK_ENABLE` | — | 0.00 | — | terrain brake enable |
| `TERR_BRK_HDIST` | — | 0.00 | m | terrain brake home distance |
| `TERR_BRK_SPD` | — | 0.00 | m/s | terrain brake speed threshold |
| `THROW_ALT_MAX` | — | 0.00 | m | Throw mode maximum altitude |
| `THROW_ALT_MIN` | — | 0.00 | m | Throw mode minimum altitude |
| `THROW_MOT_START` | — | 0.00 | — | Start motors before throwing is detected |
| `THROW_NEXTMODE` | — | 0.00 | — | Throw mode's follow up mode |
| `THROW_TYPE` | — | 0.00 | — | Type of Type |
| `THR_DZ` | `THR_MDL_FAC` | 0.37 | PWM | Throttle deadzone |
| `TKOFF_RPM_MAX` | — | 0.00 | — | Takeoff Check RPM maximum |
| `TKOFF_RPM_MIN` | — | 0.00 | — | Takeoff Check RPM minimum |
| `TKOFF_SLEW_TIME` | — | 0.00 | s | Slew time of throttle during take-off |
| `TKOFF_THR_MAX` | — | 0.00 | — | Takeoff maximum throttle during take-off ramp up |
| `TMODE_ACTION1` | — | 0.00 | — | Tmode action 1 |
| `TMODE_ACTION2` | — | 0.00 | — | Tmode action 2 |
| `TMODE_ACTION3` | — | 0.00 | — | Tmode action 3 |
| `TMODE_ACTION4` | — | 0.00 | — | Tmode action 4 |
| `TMODE_ACTION5` | — | 0.00 | — | Tmode action 5 |
| `TMODE_ACTION6` | — | 0.00 | — | Tmode action 6 |
| `TMODE_ENABLE` | — | 0.00 | — | tmode enable |
| `TMODE_FLAGS` | — | 0.00 | — | Tmode flags |
| `TMODE_LEFT` | — | 0.00 | — | Tmode left action |
| `TMODE_LEFT_LONG` | — | 0.00 | — | Tmode left long action |
| `TMODE_LOAD_FILT` | — | 0.00 | — | Load test filter |
| `TMODE_LOAD_MUL` | — | 0.00 | — | Load test multiplier |
| `TMODE_LOAD_TYPE` | — | 0.00 | — | Load test type |
| `TMODE_MODE1` | — | 0.00 | — | Tmode first mode |
| `TMODE_MODE2` | — | 0.00 | — | Tmode second mode |
| `TMODE_RIGHT` | — | 0.00 | — | Tmode right action |
| `TMODE_TMAX` | — | 0.00 | — | Max thrust multiplier |
| `TMODE_TMIN` | — | 0.00 | — | Min thrust multiplier |
| `TMODE_TRIM_AUTO` | — | 0.00 | — | Stick auto trim limit |
| `TMODE_VMAX` | — | 0.00 | — | Max voltage for output limiting |
| `TMODE_VMIN` | — | 0.00 | — | Min voltage for output limiting |
| `TOFSENSE_ID1` | — | 0.00 | — | TOFSENSE-M First ID |
| `TOFSENSE_ID2` | — | 0.00 | — | TOFSENSE-M Second ID |
| `TOFSENSE_ID3` | — | 0.00 | — | TOFSENSE-M Thir ID |
| `TOFSENSE_INST1` | — | 0.00 | — | TOFSENSE-M First Instance |
| `TOFSENSE_INST2` | — | 0.00 | — | TOFSENSE-M Second Instance |
| `TOFSENSE_INST3` | — | 0.00 | — | TOFSENSE-M Third Instance |
| `TOFSENSE_MODE` | — | 0.00 | — | TOFSENSE-M mode to be used |
| `TOFSENSE_NO` | — | 0.00 | — | TOFSENSE-M Connected |
| `TOFSENSE_PRX` | — | 0.00 | — | TOFSENSE-M to be used as Proximity sensor |
| `TOFSENSE_S1_BR` | — | 0.00 | — | TOFSENSE-M serial port baudrate |
| `TOFSENSE_S1_PRX` | — | 0.00 | — | TOFSENSE-M to be used as Proximity sensor |
| `TOFSENSE_S1_SP` | — | 0.00 | — | TOFSENSE-M serial port config |
| `TRIK_ACT_FN` | — | 0.00 | — | Trik Action Scripting Function |
| `TRIK_COUNT` | — | 0.00 | — | Trik Count |
| `TRIK_ENABLE` | — | 0.00 | — | Tricks on Switch Enable |
| `TRIK_SEL_FN` | — | 0.00 | — | Trik Selection Scripting Function |
| `TUNE` | — | 0.00 | — | Channel 6 Tuning |
| `TUNE_MAX` | — | 0.00 | — | Tuning maximum |
| `TUNE_MIN` | — | 0.00 | — | Tuning minimum |
| `UM_CANDRV` | — | 0.00 | — | Set CAN driver |
| `UM_OPTIONS` | — | 0.00 | — | Optional settings |
| `UM_RATE_HZ` | — | 0.00 | Hz | Update rate for UltraMotion servos |
| `UM_SERVO_MASK` | — | 0.00 | — | Mask of UltraMotion servos |
| `VID1_BITRATE` | — | 0.00 | — | Camera1 Video Stream Bitrate |
| `VID1_CAMMODEL` | — | 0.00 | — | Camera1 Video Stream Camera Model |
| `VID1_ENCODING` | — | 0.00 | — | Camera1 Video Stream Encoding |
| `VID1_FLAG` | — | 0.00 | — | Camera1 Video Stream Flags |
| `VID1_FRAME_RATE` | — | 0.00 | — | Camera1 Video Stream Frame Rate |
| `VID1_HFOV` | — | 0.00 | — | Camera1 Video Stream Horizontal FOV |
| `VID1_HRES` | — | 0.00 | — | Camera1 Video Stream Horizontal Resolution |
| `VID1_ID` | — | 0.00 | — | Camera1 Video Stream Id |
| `VID1_IPADDR0` | — | 0.00 | — | Camera1 Video Stream IP Address 0 |
| `VID1_IPADDR1` | — | 0.00 | — | Camera1 Video Stream IP Address 1 |
| `VID1_IPADDR2` | — | 0.00 | — | Camera1 Video Stream IP Address 2 |
| `VID1_IPADDR3` | — | 0.00 | — | Camera1 Video Stream IP Address 3 |
| `VID1_IPPORT` | — | 0.00 | — | Camera1 Video Stream IP Address Port |
| `VID1_TYPE` | — | 0.00 | — | Camera1 Video Stream Type |
| `VID1_VRES` | — | 0.00 | — | Camera1 Video Stream Vertical Resolution |
| `VIEP_CAM_SWHIGH` | — | 0.00 | — | ViewPro Camera For Switch High |
| `VIEP_CAM_SWLOW` | — | 0.00 | — | ViewPro Camera For Switch Low |
| `VIEP_CAM_SWMID` | — | 0.00 | — | ViewPro Camera For Switch Mid |
| `VIEP_DEBUG` | — | 0.00 | — | ViewPro debug |
| `VIEP_ZOOM_MAX` | — | 0.00 | — | ViewPro Zoom Times Max |
| `VIEP_ZOOM_SPEED` | — | 0.00 | — | ViewPro Zoom Speed |
| `VISO_DELAY_MS` | — | 0.00 | ms | Visual odometry sensor delay |
| `VISO_ORIENT` | — | 0.00 | — | Visual odometery camera orientation |
| `VISO_POS_M_NSE` | — | 0.00 | m | Visual odometry position measurement noise |
| `VISO_POS_X` | — | 0.00 | m | Visual odometry camera X position offset |
| `VISO_POS_Y` | — | 0.00 | m | Visual odometry camera Y position offset |
| `VISO_POS_Z` | — | 0.00 | m | Visual odometry camera Z position offset |
| `VISO_QUAL_MIN` | — | 0.00 | % | Visual odometry minimum quality |
| `VISO_SCALE` | — | 0.00 | — | Visual odometry scaling factor |
| `VISO_TYPE` | — | 0.00 | — | Visual odometry camera connection type |
| `VISO_VEL_M_NSE` | — | 0.00 | m/s | Visual odometry velocity measurement noise |
| `VISO_YAW_M_NSE` | — | 0.00 | rad | Visual odometry yaw measurement noise |
| `VTX_BAND` | — | 0.00 | — | Video Transmitter Band |
| `VTX_CHANNEL` | — | 0.00 | — | Video Transmitter Channel |
| `VTX_ENABLE` | — | 0.00 | — | Is the Video Transmitter enabled or not |
| `VTX_FREQ` | — | 0.00 | — | Video Transmitter Frequency |
| `VTX_MAX_POWER` | — | 0.00 | — | Video Transmitter Max Power Level |
| `VTX_OPTIONS` | — | 0.00 | — | Video Transmitter Options |
| `VTX_POWER` | — | 0.00 | — | Video Transmitter Power Level |
| `WEB_BIND_PORT` | — | 0.00 | — | web server TCP port |
| `WEB_BLOCK_SIZE` | — | 0.00 | — | web server block size |
| `WEB_DEBUG` | — | 0.00 | — | web server debugging |
| `WEB_ENABLE` | — | 0.00 | — | enable web server |
| `WEB_SENDFILE_MIN` | — | 0.00 | — | web server minimum file size for sendfile |
| `WEB_TIMEOUT` | — | 0.00 | s | web server timeout |
| `WINCH_OPTIONS` | — | 0.00 | — | Winch options |
| `WINCH_POS_P` | — | 0.00 | — | Winch control position error P gain |
| `WINCH_RATE_DN` | — | 0.00 | — | WinchControl Rate Down |
| `WINCH_RATE_MAX` | — | 0.00 | m/s | Winch deploy or retract rate maximum |
| `WINCH_RATE_UP` | — | 0.00 | — | WinchControl Rate Up |
| `WINCH_RC_FUNC` | — | 0.00 | — | Winch Rate Control RC function |
| `WINCH_TYPE` | — | 0.00 | — | Winch Type |
| `WPNAV_ACCEL` | — | 0.00 | cm/s/s | Waypoint Acceleration |
| `WPNAV_ACCEL_C` | — | 0.00 | cm/s/s | Waypoint Cornering Acceleration |
| `WPNAV_ACCEL_Z` | — | 0.00 | cm/s/s | Waypoint Vertical Acceleration |
| `WPNAV_JERK` | — | 0.00 | m/s/s/s | Waypoint Jerk |
| `WPNAV_RADIUS` | — | 0.00 | cm | Waypoint Radius |
| `WPNAV_RFND_USE` | — | 0.00 | — | Waypoint missions use rangefinder for terrain following |
| `WPNAV_SPEED` | — | 0.00 | cm/s | Waypoint Horizontal Speed Target |
| `WPNAV_SPEED_DN` | — | 0.00 | cm/s | Waypoint Descent Speed Target |
| `WPNAV_SPEED_UP` | — | 0.00 | cm/s | Waypoint Climb Speed Target |
| `WPNAV_TER_MARGIN` | — | 0.00 | m | Waypoint Terrain following altitude margin |
| `WP_NAVALT_MIN` | — | 0.00 | — | Minimum navigation altitude |
| `WP_YAW_BEHAVIOR` | — | 0.00 | — | Yaw behaviour during missions |
| `WVANE_ANG_MIN` | — | 0.00 | deg | Weathervaning min angle |
| `WVANE_ENABLE` | — | 0.00 | — | Enable |
| `WVANE_GAIN` | — | 0.00 | — | Weathervaning gain |
| `WVANE_HGT_MIN` | — | 0.00 | m | Weathervaning min height |
| `WVANE_LAND` | — | 0.00 | — | Landing override |
| `WVANE_OPTIONS` | — | 0.00 | — | Weathervaning options |
| `WVANE_SPD_MAX` | — | 0.00 | m/s | Weathervaning max ground speed |
| `WVANE_TAKEOFF` | — | 0.00 | — | Takeoff override |
| `WVANE_VELZ_MAX` | — | 0.00 | m/s | Weathervaning max vertical speed |
| `ZIGZ_AUTO_ENABLE` | — | 0.00 | — | ZigZag auto enable/disable |
| `ZIGZ_DIRECTION` | — | 0.00 | — | Sideways direction in ZigZag auto |
| `ZIGZ_LINE_NUM` | — | 0.00 | — | Total number of lines |
| `ZIGZ_SIDE_DIST` | — | 0.00 | m | Sideways distance in ZigZag auto |
| `ZIGZ_SPRAYER` | — | 0.00 | — | Auto sprayer in ZigZag |
| `ZIGZ_WP_DELAY` | — | 0.00 | s | The delay for zigzag waypoint |

## Full PX4 Parameter List

| PX4 Param |
|---|
| `ADC_ADS1115_EN` |
| `ADC_ADS7953_EN` |
| `ADC_ADS7953_REFV` |
| `ADC_TLA2528_EN` |
| `ADC_TLA2528_REFV` |
| `ADSB_CALLSIGN_1` |
| `ADSB_CALLSIGN_2` |
| `ADSB_EMERGC` |
| `ADSB_EMIT_TYPE` |
| `ADSB_GPS_OFF_LAT` |
| `ADSB_GPS_OFF_LON` |
| `ADSB_ICAO_ID` |
| `ADSB_ICAO_SPECL` |
| `ADSB_IDENT` |
| `ADSB_LEN_WIDTH` |
| `ADSB_LIST_MAX` |
| `ADSB_MAX_SPEED` |
| `ADSB_SQUAWK` |
| `ASPD_BETA_GATE` |
| `ASPD_BETA_NOISE` |
| `ASPD_DO_CHECKS` |
| `ASPD_FALLBACK` |
| `ASPD_FP_T_WINDOW` |
| `ASPD_FS_INNOV` |
| `ASPD_FS_INTEG` |
| `ASPD_FS_T_START` |
| `ASPD_FS_T_STOP` |
| `ASPD_PRIMARY` |
| `ASPD_SCALE_1` |
| `ASPD_SCALE_2` |
| `ASPD_SCALE_3` |
| `ASPD_SCALE_APPLY` |
| `ASPD_SCALE_NSD` |
| `ASPD_TAS_GATE` |
| `ASPD_TAS_NOISE` |
| `ASPD_WERR_THR` |
| `ASPD_WIND_NSD` |
| `ATT_ACC_COMP` |
| `ATT_BIAS_MAX` |
| `ATT_EN` |
| `ATT_EXT_HDG_M` |
| `ATT_MAG_DECL` |
| `ATT_MAG_DECL_A` |
| `ATT_W_ACC` |
| `ATT_W_EXT_HDG` |
| `ATT_W_GYRO_BIAS` |
| `ATT_W_MAG` |
| `BAT1_A_PER_V` |
| `BAT1_CAPACITY` |
| `BAT1_C_MULT` |
| `BAT1_I_FILT` |
| `BAT1_I_OVERWRITE` |
| `BAT1_N_CELLS` |
| `BAT1_R_INTERNAL` |
| `BAT1_SMBUS_MODEL` |
| `BAT1_SOURCE` |
| `BAT1_V_CHANNEL` |
| `BAT1_V_CHARGED` |
| `BAT1_V_DIV` |
| `BAT1_V_EMPTY` |
| `BAT1_V_FILT` |
| `BAT2_A_PER_V` |
| `BAT2_CAPACITY` |
| `BAT2_I_FILT` |
| `BAT2_I_OVERWRITE` |
| `BAT2_N_CELLS` |
| `BAT2_R_INTERNAL` |
| `BAT2_SOURCE` |
| `BAT2_V_CHANNEL` |
| `BAT2_V_CHARGED` |
| `BAT2_V_DIV` |
| `BAT2_V_EMPTY` |
| `BAT2_V_FILT` |
| `BAT3_CAPACITY` |
| `BAT3_I_OVERWRITE` |
| `BAT3_N_CELLS` |
| `BAT3_R_INTERNAL` |
| `BAT3_SOURCE` |
| `BAT3_V_CHARGED` |
| `BAT3_V_EMPTY` |
| `BATMON_ADDR_DFLT` |
| `BATMON_DRIVER_EN` |
| `BAT_AVRG_CURRENT` |
| `BAT_CRIT_THR` |
| `BAT_EMERGEN_THR` |
| `BAT_LOW_THR` |
| `BAT_V_OFFS_CURR` |
| `BMM350_AVG` |
| `BMM350_DRIVE` |
| `BMM350_ODR` |
| `CAL_ACC0_ID` |
| `CAL_ACC0_PRIO` |
| `CAL_ACC0_ROT` |
| `CAL_ACC0_XOFF` |
| `CAL_ACC0_XSCALE` |
| `CAL_ACC0_YOFF` |
| `CAL_ACC0_YSCALE` |
| `CAL_ACC0_ZOFF` |
| `CAL_ACC0_ZSCALE` |
| `CAL_ACC1_ID` |
| `CAL_ACC1_PRIO` |
| `CAL_ACC1_ROT` |
| `CAL_ACC1_XOFF` |
| `CAL_ACC1_XSCALE` |
| `CAL_ACC1_YOFF` |
| `CAL_ACC1_YSCALE` |
| `CAL_ACC1_ZOFF` |
| `CAL_ACC1_ZSCALE` |
| `CAL_ACC2_ID` |
| `CAL_ACC2_PRIO` |
| `CAL_ACC2_ROT` |
| `CAL_ACC2_XOFF` |
| `CAL_ACC2_XSCALE` |
| `CAL_ACC2_YOFF` |
| `CAL_ACC2_YSCALE` |
| `CAL_ACC2_ZOFF` |
| `CAL_ACC2_ZSCALE` |
| `CAL_ACC3_ID` |
| `CAL_ACC3_PRIO` |
| `CAL_ACC3_ROT` |
| `CAL_ACC3_XOFF` |
| `CAL_ACC3_XSCALE` |
| `CAL_ACC3_YOFF` |
| `CAL_ACC3_YSCALE` |
| `CAL_ACC3_ZOFF` |
| `CAL_ACC3_ZSCALE` |
| `CAL_AIR_CMODEL` |
| `CAL_AIR_TUBED_MM` |
| `CAL_AIR_TUBELEN` |
| `CAL_BARO0_ID` |
| `CAL_BARO0_OFF` |
| `CAL_BARO0_PRIO` |
| `CAL_BARO1_ID` |
| `CAL_BARO1_OFF` |
| `CAL_BARO1_PRIO` |
| `CAL_BARO2_ID` |
| `CAL_BARO2_OFF` |
| `CAL_BARO2_PRIO` |
| `CAL_BARO3_ID` |
| `CAL_BARO3_OFF` |
| `CAL_BARO3_PRIO` |
| `CAL_GYRO0_ID` |
| `CAL_GYRO0_PRIO` |
| `CAL_GYRO0_ROT` |
| `CAL_GYRO0_XOFF` |
| `CAL_GYRO0_YOFF` |
| `CAL_GYRO0_ZOFF` |
| `CAL_GYRO1_ID` |
| `CAL_GYRO1_PRIO` |
| `CAL_GYRO1_ROT` |
| `CAL_GYRO1_XOFF` |
| `CAL_GYRO1_YOFF` |
| `CAL_GYRO1_ZOFF` |
| `CAL_GYRO2_ID` |
| `CAL_GYRO2_PRIO` |
| `CAL_GYRO2_ROT` |
| `CAL_GYRO2_XOFF` |
| `CAL_GYRO2_YOFF` |
| `CAL_GYRO2_ZOFF` |
| `CAL_GYRO3_ID` |
| `CAL_GYRO3_PRIO` |
| `CAL_GYRO3_ROT` |
| `CAL_GYRO3_XOFF` |
| `CAL_GYRO3_YOFF` |
| `CAL_GYRO3_ZOFF` |
| `CAL_MAG0_ID` |
| `CAL_MAG0_PITCH` |
| `CAL_MAG0_PRIO` |
| `CAL_MAG0_ROLL` |
| `CAL_MAG0_ROT` |
| `CAL_MAG0_XCOMP` |
| `CAL_MAG0_XODIAG` |
| `CAL_MAG0_XOFF` |
| `CAL_MAG0_XSCALE` |
| `CAL_MAG0_YAW` |
| `CAL_MAG0_YCOMP` |
| `CAL_MAG0_YODIAG` |
| `CAL_MAG0_YOFF` |
| `CAL_MAG0_YSCALE` |
| `CAL_MAG0_ZCOMP` |
| `CAL_MAG0_ZODIAG` |
| `CAL_MAG0_ZOFF` |
| `CAL_MAG0_ZSCALE` |
| `CAL_MAG1_ID` |
| `CAL_MAG1_PITCH` |
| `CAL_MAG1_PRIO` |
| `CAL_MAG1_ROLL` |
| `CAL_MAG1_ROT` |
| `CAL_MAG1_XCOMP` |
| `CAL_MAG1_XODIAG` |
| `CAL_MAG1_XOFF` |
| `CAL_MAG1_XSCALE` |
| `CAL_MAG1_YAW` |
| `CAL_MAG1_YCOMP` |
| `CAL_MAG1_YODIAG` |
| `CAL_MAG1_YOFF` |
| `CAL_MAG1_YSCALE` |
| `CAL_MAG1_ZCOMP` |
| `CAL_MAG1_ZODIAG` |
| `CAL_MAG1_ZOFF` |
| `CAL_MAG1_ZSCALE` |
| `CAL_MAG2_ID` |
| `CAL_MAG2_PITCH` |
| `CAL_MAG2_PRIO` |
| `CAL_MAG2_ROLL` |
| `CAL_MAG2_ROT` |
| `CAL_MAG2_XCOMP` |
| `CAL_MAG2_XODIAG` |
| `CAL_MAG2_XOFF` |
| `CAL_MAG2_XSCALE` |
| `CAL_MAG2_YAW` |
| `CAL_MAG2_YCOMP` |
| `CAL_MAG2_YODIAG` |
| `CAL_MAG2_YOFF` |
| `CAL_MAG2_YSCALE` |
| `CAL_MAG2_ZCOMP` |
| `CAL_MAG2_ZODIAG` |
| `CAL_MAG2_ZOFF` |
| `CAL_MAG2_ZSCALE` |
| `CAL_MAG3_ID` |
| `CAL_MAG3_PITCH` |
| `CAL_MAG3_PRIO` |
| `CAL_MAG3_ROLL` |
| `CAL_MAG3_ROT` |
| `CAL_MAG3_XCOMP` |
| `CAL_MAG3_XODIAG` |
| `CAL_MAG3_XOFF` |
| `CAL_MAG3_XSCALE` |
| `CAL_MAG3_YAW` |
| `CAL_MAG3_YCOMP` |
| `CAL_MAG3_YODIAG` |
| `CAL_MAG3_YOFF` |
| `CAL_MAG3_YSCALE` |
| `CAL_MAG3_ZCOMP` |
| `CAL_MAG3_ZODIAG` |
| `CAL_MAG3_ZOFF` |
| `CAL_MAG3_ZSCALE` |
| `CAL_MAG_COMP_TYP` |
| `CAL_MAG_SIDES` |
| `CAM_CAP_DELAY` |
| `CAM_CAP_EDGE` |
| `CAM_CAP_FBACK` |
| `CAM_CAP_MODE` |
| `CA_AIRFRAME` |
| `CA_CS_LAUN_LK` |
| `CA_FAILURE_MODE` |
| `CA_HELI_PITCH_C0` |
| `CA_HELI_PITCH_C1` |
| `CA_HELI_PITCH_C2` |
| `CA_HELI_PITCH_C3` |
| `CA_HELI_PITCH_C4` |
| `CA_HELI_RPM_I` |
| `CA_HELI_RPM_P` |
| `CA_HELI_RPM_SP` |
| `CA_HELI_THR_C0` |
| `CA_HELI_THR_C1` |
| `CA_HELI_THR_C2` |
| `CA_HELI_THR_C3` |
| `CA_HELI_THR_C4` |
| `CA_HELI_YAW_CCW` |
| `CA_HELI_YAW_CP_O` |
| `CA_HELI_YAW_CP_S` |
| `CA_HELI_YAW_TH_S` |
| `CA_ICE_PERIOD` |
| `CA_MAX_SVO_THROW` |
| `CA_METHOD` |
| `CA_R0_SLEW` |
| `CA_R10_SLEW` |
| `CA_R11_SLEW` |
| `CA_R1_SLEW` |
| `CA_R2_SLEW` |
| `CA_R3_SLEW` |
| `CA_R4_SLEW` |
| `CA_R5_SLEW` |
| `CA_R6_SLEW` |
| `CA_R7_SLEW` |
| `CA_R8_SLEW` |
| `CA_R9_SLEW` |
| `CA_ROTOR0_AX` |
| `CA_ROTOR0_AY` |
| `CA_ROTOR0_AZ` |
| `CA_ROTOR0_CT` |
| `CA_ROTOR0_KM` |
| `CA_ROTOR0_PX` |
| `CA_ROTOR0_PY` |
| `CA_ROTOR0_PZ` |
| `CA_ROTOR0_TILT` |
| `CA_ROTOR10_AX` |
| `CA_ROTOR10_AY` |
| `CA_ROTOR10_AZ` |
| `CA_ROTOR10_CT` |
| `CA_ROTOR10_KM` |
| `CA_ROTOR10_PX` |
| `CA_ROTOR10_PY` |
| `CA_ROTOR10_PZ` |
| `CA_ROTOR10_TILT` |
| `CA_ROTOR11_AX` |
| `CA_ROTOR11_AY` |
| `CA_ROTOR11_AZ` |
| `CA_ROTOR11_CT` |
| `CA_ROTOR11_KM` |
| `CA_ROTOR11_PX` |
| `CA_ROTOR11_PY` |
| `CA_ROTOR11_PZ` |
| `CA_ROTOR11_TILT` |
| `CA_ROTOR1_AX` |
| `CA_ROTOR1_AY` |
| `CA_ROTOR1_AZ` |
| `CA_ROTOR1_CT` |
| `CA_ROTOR1_KM` |
| `CA_ROTOR1_PX` |
| `CA_ROTOR1_PY` |
| `CA_ROTOR1_PZ` |
| `CA_ROTOR1_TILT` |
| `CA_ROTOR2_AX` |
| `CA_ROTOR2_AY` |
| `CA_ROTOR2_AZ` |
| `CA_ROTOR2_CT` |
| `CA_ROTOR2_KM` |
| `CA_ROTOR2_PX` |
| `CA_ROTOR2_PY` |
| `CA_ROTOR2_PZ` |
| `CA_ROTOR2_TILT` |
| `CA_ROTOR3_AX` |
| `CA_ROTOR3_AY` |
| `CA_ROTOR3_AZ` |
| `CA_ROTOR3_CT` |
| `CA_ROTOR3_KM` |
| `CA_ROTOR3_PX` |
| `CA_ROTOR3_PY` |
| `CA_ROTOR3_PZ` |
| `CA_ROTOR3_TILT` |
| `CA_ROTOR4_AX` |
| `CA_ROTOR4_AY` |
| `CA_ROTOR4_AZ` |
| `CA_ROTOR4_CT` |
| `CA_ROTOR4_KM` |
| `CA_ROTOR4_PX` |
| `CA_ROTOR4_PY` |
| `CA_ROTOR4_PZ` |
| `CA_ROTOR4_TILT` |
| `CA_ROTOR5_AX` |
| `CA_ROTOR5_AY` |
| `CA_ROTOR5_AZ` |
| `CA_ROTOR5_CT` |
| `CA_ROTOR5_KM` |
| `CA_ROTOR5_PX` |
| `CA_ROTOR5_PY` |
| `CA_ROTOR5_PZ` |
| `CA_ROTOR5_TILT` |
| `CA_ROTOR6_AX` |
| `CA_ROTOR6_AY` |
| `CA_ROTOR6_AZ` |
| `CA_ROTOR6_CT` |
| `CA_ROTOR6_KM` |
| `CA_ROTOR6_PX` |
| `CA_ROTOR6_PY` |
| `CA_ROTOR6_PZ` |
| `CA_ROTOR6_TILT` |
| `CA_ROTOR7_AX` |
| `CA_ROTOR7_AY` |
| `CA_ROTOR7_AZ` |
| `CA_ROTOR7_CT` |
| `CA_ROTOR7_KM` |
| `CA_ROTOR7_PX` |
| `CA_ROTOR7_PY` |
| `CA_ROTOR7_PZ` |
| `CA_ROTOR7_TILT` |
| `CA_ROTOR8_AX` |
| `CA_ROTOR8_AY` |
| `CA_ROTOR8_AZ` |
| `CA_ROTOR8_CT` |
| `CA_ROTOR8_KM` |
| `CA_ROTOR8_PX` |
| `CA_ROTOR8_PY` |
| `CA_ROTOR8_PZ` |
| `CA_ROTOR8_TILT` |
| `CA_ROTOR9_AX` |
| `CA_ROTOR9_AY` |
| `CA_ROTOR9_AZ` |
| `CA_ROTOR9_CT` |
| `CA_ROTOR9_KM` |
| `CA_ROTOR9_PX` |
| `CA_ROTOR9_PY` |
| `CA_ROTOR9_PZ` |
| `CA_ROTOR9_TILT` |
| `CA_ROTOR_COUNT` |
| `CA_R_REV` |
| `CA_SP0_ANG0` |
| `CA_SP0_ANG1` |
| `CA_SP0_ANG2` |
| `CA_SP0_ANG3` |
| `CA_SP0_ARM_L0` |
| `CA_SP0_ARM_L1` |
| `CA_SP0_ARM_L2` |
| `CA_SP0_ARM_L3` |
| `CA_SP0_COUNT` |
| `CA_SV0_SLEW` |
| `CA_SV1_SLEW` |
| `CA_SV2_SLEW` |
| `CA_SV3_SLEW` |
| `CA_SV4_SLEW` |
| `CA_SV5_SLEW` |
| `CA_SV6_SLEW` |
| `CA_SV7_SLEW` |
| `CA_SV_CS0_FLAP` |
| `CA_SV_CS0_SPOIL` |
| `CA_SV_CS0_TRIM` |
| `CA_SV_CS0_TRQ_P` |
| `CA_SV_CS0_TRQ_R` |
| `CA_SV_CS0_TRQ_Y` |
| `CA_SV_CS0_TYPE` |
| `CA_SV_CS1_FLAP` |
| `CA_SV_CS1_SPOIL` |
| `CA_SV_CS1_TRIM` |
| `CA_SV_CS1_TRQ_P` |
| `CA_SV_CS1_TRQ_R` |
| `CA_SV_CS1_TRQ_Y` |
| `CA_SV_CS1_TYPE` |
| `CA_SV_CS2_FLAP` |
| `CA_SV_CS2_SPOIL` |
| `CA_SV_CS2_TRIM` |
| `CA_SV_CS2_TRQ_P` |
| `CA_SV_CS2_TRQ_R` |
| `CA_SV_CS2_TRQ_Y` |
| `CA_SV_CS2_TYPE` |
| `CA_SV_CS3_FLAP` |
| `CA_SV_CS3_SPOIL` |
| `CA_SV_CS3_TRIM` |
| `CA_SV_CS3_TRQ_P` |
| `CA_SV_CS3_TRQ_R` |
| `CA_SV_CS3_TRQ_Y` |
| `CA_SV_CS3_TYPE` |
| `CA_SV_CS4_FLAP` |
| `CA_SV_CS4_SPOIL` |
| `CA_SV_CS4_TRIM` |
| `CA_SV_CS4_TRQ_P` |
| `CA_SV_CS4_TRQ_R` |
| `CA_SV_CS4_TRQ_Y` |
| `CA_SV_CS4_TYPE` |
| `CA_SV_CS5_FLAP` |
| `CA_SV_CS5_SPOIL` |
| `CA_SV_CS5_TRIM` |
| `CA_SV_CS5_TRQ_P` |
| `CA_SV_CS5_TRQ_R` |
| `CA_SV_CS5_TRQ_Y` |
| `CA_SV_CS5_TYPE` |
| `CA_SV_CS6_FLAP` |
| `CA_SV_CS6_SPOIL` |
| `CA_SV_CS6_TRIM` |
| `CA_SV_CS6_TRQ_P` |
| `CA_SV_CS6_TRQ_R` |
| `CA_SV_CS6_TRQ_Y` |
| `CA_SV_CS6_TYPE` |
| `CA_SV_CS7_FLAP` |
| `CA_SV_CS7_SPOIL` |
| `CA_SV_CS7_TRIM` |
| `CA_SV_CS7_TRQ_P` |
| `CA_SV_CS7_TRQ_R` |
| `CA_SV_CS7_TRQ_Y` |
| `CA_SV_CS7_TYPE` |
| `CA_SV_CS_COUNT` |
| `CA_SV_FLAP_SLEW` |
| `CA_SV_TL0_CT` |
| `CA_SV_TL0_MAXA` |
| `CA_SV_TL0_MINA` |
| `CA_SV_TL0_TD` |
| `CA_SV_TL1_CT` |
| `CA_SV_TL1_MAXA` |
| `CA_SV_TL1_MINA` |
| `CA_SV_TL1_TD` |
| `CA_SV_TL2_CT` |
| `CA_SV_TL2_MAXA` |
| `CA_SV_TL2_MINA` |
| `CA_SV_TL2_TD` |
| `CA_SV_TL3_CT` |
| `CA_SV_TL3_MAXA` |
| `CA_SV_TL3_MINA` |
| `CA_SV_TL3_TD` |
| `CA_SV_TL_COUNT` |
| `CBRK_BUZZER` |
| `CBRK_FLIGHTTERM` |
| `CBRK_IO_SAFETY` |
| `CBRK_SUPPLY_CHK` |
| `CBRK_USB_CHK` |
| `CBRK_VTOLARMING` |
| `COM_ACT_FAIL_ACT` |
| `COM_ARMABLE` |
| `COM_ARM_AUTH_ID` |
| `COM_ARM_AUTH_MET` |
| `COM_ARM_AUTH_REQ` |
| `COM_ARM_AUTH_TO` |
| `COM_ARM_BAT_MIN` |
| `COM_ARM_CHK_ESCS` |
| `COM_ARM_HFLT_CHK` |
| `COM_ARM_IMU_ACC` |
| `COM_ARM_IMU_GYR` |
| `COM_ARM_MAG_ANG` |
| `COM_ARM_MAG_STR` |
| `COM_ARM_MIS_REQ` |
| `COM_ARM_ODID` |
| `COM_ARM_ON_BOOT` |
| `COM_ARM_SDCARD` |
| `COM_ARM_SWISBTN` |
| `COM_ARM_TRAFF` |
| `COM_ARM_WO_GPS` |
| `COM_CPU_MAX` |
| `COM_DISARM_LAND` |
| `COM_DISARM_MAN` |
| `COM_DISARM_PRFLT` |
| `COM_DLL_EXCEPT` |
| `COM_DL_LOSS_T` |
| `COM_FAIL_ACT_T` |
| `COM_FLIGHT_UUID` |
| `COM_FLTMODE1` |
| `COM_FLTMODE2` |
| `COM_FLTMODE3` |
| `COM_FLTMODE4` |
| `COM_FLTMODE5` |
| `COM_FLTMODE6` |
| `COM_FLTT_LOW_ACT` |
| `COM_FLT_TIME_MAX` |
| `COM_FORCE_SAFETY` |
| `COM_HLDL_LOSS_T` |
| `COM_HOME_EN` |
| `COM_HOME_IN_AIR` |
| `COM_IMB_PROP_ACT` |
| `COM_LKDOWN_TKO` |
| `COM_LOW_BAT_ACT` |
| `COM_MODE0_HASH` |
| `COM_MODE1_HASH` |
| `COM_MODE2_HASH` |
| `COM_MODE3_HASH` |
| `COM_MODE4_HASH` |
| `COM_MODE5_HASH` |
| `COM_MODE6_HASH` |
| `COM_MODE7_HASH` |
| `COM_MODE_ARM_CHK` |
| `COM_OBC_LOSS_T` |
| `COM_OBL_RC_ACT` |
| `COM_OF_LOSS_T` |
| `COM_PARACHUTE` |
| `COM_POS_FS_EPH` |
| `COM_POS_LOW_ACT` |
| `COM_POS_LOW_EPH` |
| `COM_POWER_COUNT` |
| `COM_PREARM_MODE` |
| `COM_QC_ACT` |
| `COM_RAM_MAX` |
| `COM_RCL_EXCEPT` |
| `COM_RC_IN_MODE` |
| `COM_RC_LOSS_T` |
| `COM_RC_OVERRIDE` |
| `COM_RC_STICK_OV` |
| `COM_SPOOLUP_TIME` |
| `COM_TAKEOFF_ACT` |
| `COM_THROW_EN` |
| `COM_THROW_SPEED` |
| `COM_VEL_FS_EVH` |
| `COM_WIND_MAX` |
| `COM_WIND_MAX_ACT` |
| `COM_WIND_WARN` |
| `CP_DELAY` |
| `CP_DIST` |
| `CP_GO_NO_DATA` |
| `CP_GUIDE_ANG` |
| `CYPHAL_BAUD` |
| `CYPHAL_ENABLE` |
| `CYPHAL_ID` |
| `DSHOT_3D_DEAD_H` |
| `DSHOT_3D_DEAD_L` |
| `DSHOT_3D_ENABLE` |
| `DSHOT_BIDIR_EDT` |
| `DSHOT_ESC_TYPE` |
| `DSHOT_MIN` |
| `DSHOT_MOT_POL1` |
| `DSHOT_MOT_POL10` |
| `DSHOT_MOT_POL11` |
| `DSHOT_MOT_POL12` |
| `DSHOT_MOT_POL2` |
| `DSHOT_MOT_POL3` |
| `DSHOT_MOT_POL4` |
| `DSHOT_MOT_POL5` |
| `DSHOT_MOT_POL6` |
| `DSHOT_MOT_POL7` |
| `DSHOT_MOT_POL8` |
| `DSHOT_MOT_POL9` |
| `DSHOT_TEL_CFG` |
| `EKF2_ABIAS_INIT` |
| `EKF2_ABL_ACCLIM` |
| `EKF2_ABL_GYRLIM` |
| `EKF2_ABL_LIM` |
| `EKF2_ABL_TAU` |
| `EKF2_ACC_B_NOISE` |
| `EKF2_ACC_NOISE` |
| `EKF2_AGP0_CTRL` |
| `EKF2_AGP0_DELAY` |
| `EKF2_AGP0_GATE` |
| `EKF2_AGP0_ID` |
| `EKF2_AGP0_MODE` |
| `EKF2_AGP0_NOISE` |
| `EKF2_AGP1_CTRL` |
| `EKF2_AGP1_DELAY` |
| `EKF2_AGP1_GATE` |
| `EKF2_AGP1_ID` |
| `EKF2_AGP1_MODE` |
| `EKF2_AGP1_NOISE` |
| `EKF2_AGP2_CTRL` |
| `EKF2_AGP2_DELAY` |
| `EKF2_AGP2_GATE` |
| `EKF2_AGP2_ID` |
| `EKF2_AGP2_MODE` |
| `EKF2_AGP2_NOISE` |
| `EKF2_AGP3_CTRL` |
| `EKF2_AGP3_DELAY` |
| `EKF2_AGP3_GATE` |
| `EKF2_AGP3_ID` |
| `EKF2_AGP3_MODE` |
| `EKF2_AGP3_NOISE` |
| `EKF2_ANGERR_INIT` |
| `EKF2_ARSP_THR` |
| `EKF2_ASPD_MAX` |
| `EKF2_ASP_DELAY` |
| `EKF2_AVEL_DELAY` |
| `EKF2_BARO_CTRL` |
| `EKF2_BARO_DELAY` |
| `EKF2_BARO_GATE` |
| `EKF2_BARO_NOISE` |
| `EKF2_BCOEF_X` |
| `EKF2_BCOEF_Y` |
| `EKF2_BETA_GATE` |
| `EKF2_BETA_NOISE` |
| `EKF2_DECL_TYPE` |
| `EKF2_DELAY_MAX` |
| `EKF2_DRAG_CTRL` |
| `EKF2_DRAG_NOISE` |
| `EKF2_EAS_NOISE` |
| `EKF2_EN` |
| `EKF2_EVA_NOISE` |
| `EKF2_EVP_GATE` |
| `EKF2_EVP_NOISE` |
| `EKF2_EVV_GATE` |
| `EKF2_EVV_NOISE` |
| `EKF2_EV_CTRL` |
| `EKF2_EV_DELAY` |
| `EKF2_EV_NOISE_MD` |
| `EKF2_EV_POS_X` |
| `EKF2_EV_POS_Y` |
| `EKF2_EV_POS_Z` |
| `EKF2_EV_QMIN` |
| `EKF2_FUSE_BETA` |
| `EKF2_GBIAS_INIT` |
| `EKF2_GND_EFF_DZ` |
| `EKF2_GND_MAX_HGT` |
| `EKF2_GPS_CHECK` |
| `EKF2_GPS_CTRL` |
| `EKF2_GPS_MODE` |
| `EKF2_GPS_P_GATE` |
| `EKF2_GPS_P_NOISE` |
| `EKF2_GPS_V_GATE` |
| `EKF2_GPS_V_NOISE` |
| `EKF2_GPS_YAW_OFF` |
| `EKF2_GRAV_NOISE` |
| `EKF2_GSF_TAS` |
| `EKF2_GYR_B_LIM` |
| `EKF2_GYR_B_NOISE` |
| `EKF2_GYR_NOISE` |
| `EKF2_HDG_GATE` |
| `EKF2_HEAD_NOISE` |
| `EKF2_HGT_REF` |
| `EKF2_IMU_CTRL` |
| `EKF2_IMU_POS_X` |
| `EKF2_IMU_POS_Y` |
| `EKF2_IMU_POS_Z` |
| `EKF2_LOG_VERBOSE` |
| `EKF2_MAG_ACCLIM` |
| `EKF2_MAG_B_NOISE` |
| `EKF2_MAG_CHECK` |
| `EKF2_MAG_CHK_INC` |
| `EKF2_MAG_CHK_STR` |
| `EKF2_MAG_DECL` |
| `EKF2_MAG_DELAY` |
| `EKF2_MAG_E_NOISE` |
| `EKF2_MAG_GATE` |
| `EKF2_MAG_NOISE` |
| `EKF2_MAG_TYPE` |
| `EKF2_MCOEF` |
| `EKF2_MIN_RNG` |
| `EKF2_MULTI_IMU` |
| `EKF2_MULTI_MAG` |
| `EKF2_NOAID_NOISE` |
| `EKF2_NOAID_TOUT` |
| `EKF2_OF_CTRL` |
| `EKF2_OF_DELAY` |
| `EKF2_OF_GATE` |
| `EKF2_OF_GYR_SRC` |
| `EKF2_OF_N_MAX` |
| `EKF2_OF_N_MIN` |
| `EKF2_OF_POS_X` |
| `EKF2_OF_POS_Y` |
| `EKF2_OF_POS_Z` |
| `EKF2_OF_QMIN` |
| `EKF2_OF_QMIN_GND` |
| `EKF2_PCOEF_XN` |
| `EKF2_PCOEF_XP` |
| `EKF2_PCOEF_YN` |
| `EKF2_PCOEF_YP` |
| `EKF2_PCOEF_Z` |
| `EKF2_POS_LOCK` |
| `EKF2_PREDICT_US` |
| `EKF2_REQ_EPH` |
| `EKF2_REQ_EPV` |
| `EKF2_REQ_FIX` |
| `EKF2_REQ_GPS_H` |
| `EKF2_REQ_HDRIFT` |
| `EKF2_REQ_NSATS` |
| `EKF2_REQ_PDOP` |
| `EKF2_REQ_SACC` |
| `EKF2_REQ_VDRIFT` |
| `EKF2_RNGBC_CTRL` |
| `EKF2_RNGBC_DELAY` |
| `EKF2_RNGBC_GATE` |
| `EKF2_RNGBC_NOISE` |
| `EKF2_RNG_A_HMAX` |
| `EKF2_RNG_A_VMAX` |
| `EKF2_RNG_CTRL` |
| `EKF2_RNG_DELAY` |
| `EKF2_RNG_FOG` |
| `EKF2_RNG_GATE` |
| `EKF2_RNG_K_GATE` |
| `EKF2_RNG_NOISE` |
| `EKF2_RNG_PITCH` |
| `EKF2_RNG_POS_X` |
| `EKF2_RNG_POS_Y` |
| `EKF2_RNG_POS_Z` |
| `EKF2_RNG_QLTY_T` |
| `EKF2_RNG_SFE` |
| `EKF2_SEL_ERR_RED` |
| `EKF2_SEL_IMU_ACC` |
| `EKF2_SEL_IMU_ANG` |
| `EKF2_SEL_IMU_RAT` |
| `EKF2_SEL_IMU_VEL` |
| `EKF2_SENS_EN` |
| `EKF2_SYNT_MAG_Z` |
| `EKF2_TAS_GATE` |
| `EKF2_TAU_POS` |
| `EKF2_TAU_VEL` |
| `EKF2_TERR_GRAD` |
| `EKF2_TERR_NOISE` |
| `EKF2_VEL_LIM` |
| `EKF2_WIND_NSD` |
| `ESC_BL_VER` |
| `ESC_FW_VER` |
| `ESC_HW_VER` |
| `EV_TSK_RC_LOSS` |
| `EV_TSK_STAT_DIS` |
| `FD_ACT_EN` |
| `FD_ALT_LOSS` |
| `FD_ALT_LOSS_T` |
| `FD_EXT_ATS_EN` |
| `FD_EXT_ATS_TRIG` |
| `FD_FAIL_P` |
| `FD_FAIL_P_TTRI` |
| `FD_FAIL_R` |
| `FD_FAIL_R_TTRI` |
| `FD_IMB_PROP_THR` |
| `FLW_TGT_ALT_M` |
| `FLW_TGT_DST` |
| `FLW_TGT_FA` |
| `FLW_TGT_HT` |
| `FLW_TGT_MAX_VEL` |
| `FLW_TGT_RS` |
| `FW_ACRO_X_MAX` |
| `FW_ACRO_YAW_EN` |
| `FW_ACRO_Y_MAX` |
| `FW_ACRO_Z_MAX` |
| `FW_AIRSPD_FLP_SC` |
| `FW_AIRSPD_MAX` |
| `FW_AIRSPD_MIN` |
| `FW_AIRSPD_STALL` |
| `FW_AIRSPD_TRIM` |
| `FW_ARSP_SCALE_EN` |
| `FW_AT_APPLY` |
| `FW_AT_AXES` |
| `FW_AT_MAN_AUX` |
| `FW_AT_SYSID_F0` |
| `FW_AT_SYSID_F1` |
| `FW_AT_SYSID_TIME` |
| `FW_AT_SYSID_TYPE` |
| `FW_BAT_SCALE_EN` |
| `FW_DTRIM_P_VMAX` |
| `FW_DTRIM_P_VMIN` |
| `FW_DTRIM_R_VMAX` |
| `FW_DTRIM_R_VMIN` |
| `FW_DTRIM_Y_VMAX` |
| `FW_DTRIM_Y_VMIN` |
| `FW_FLAPS_LND_SCL` |
| `FW_FLAPS_MAN` |
| `FW_FLAPS_TO_SCL` |
| `FW_GC_EN` |
| `FW_GC_GAIN_MIN` |
| `FW_GND_SPD_MIN` |
| `FW_GPSF_LT` |
| `FW_GPSF_R` |
| `FW_LAUN_AC_T` |
| `FW_LAUN_AC_THLD` |
| `FW_LAUN_CS_LK_DY` |
| `FW_LAUN_DETCN_ON` |
| `FW_LAUN_MOT_DEL` |
| `FW_LND_ABORT` |
| `FW_LND_AIRSPD` |
| `FW_LND_ANG` |
| `FW_LND_EARLYCFG` |
| `FW_LND_FLALT` |
| `FW_LND_FL_PMAX` |
| `FW_LND_FL_PMIN` |
| `FW_LND_FL_SINK` |
| `FW_LND_FL_TIME` |
| `FW_LND_NUDGE` |
| `FW_LND_TD_OFF` |
| `FW_LND_TD_TIME` |
| `FW_LND_THRTC_SC` |
| `FW_LND_USETER` |
| `FW_MAN_P_MAX` |
| `FW_MAN_P_SC` |
| `FW_MAN_R_MAX` |
| `FW_MAN_R_SC` |
| `FW_MAN_YR_MAX` |
| `FW_MAN_Y_SC` |
| `FW_PN_R_SLEW_MAX` |
| `FW_POS_STK_CONF` |
| `FW_PR_D` |
| `FW_PR_FF` |
| `FW_PR_I` |
| `FW_PR_IMAX` |
| `FW_PR_P` |
| `FW_PSP_OFF` |
| `FW_P_LIM_MAX` |
| `FW_P_LIM_MIN` |
| `FW_P_RMAX_NEG` |
| `FW_P_RMAX_POS` |
| `FW_P_TC` |
| `FW_RLL_TO_YAW_FF` |
| `FW_RR_D` |
| `FW_RR_FF` |
| `FW_RR_I` |
| `FW_RR_IMAX` |
| `FW_RR_P` |
| `FW_R_LIM` |
| `FW_R_RMAX` |
| `FW_R_TC` |
| `FW_SERVICE_CEIL` |
| `FW_SPOILERS_LND` |
| `FW_SPOILERS_MAN` |
| `FW_THR_ASPD_MAX` |
| `FW_THR_ASPD_MIN` |
| `FW_THR_IDLE` |
| `FW_THR_MAX` |
| `FW_THR_MIN` |
| `FW_THR_SLEW_MAX` |
| `FW_THR_TRIM` |
| `FW_TKO_AIRSPD` |
| `FW_TKO_PITCH_MIN` |
| `FW_T_ALT_TC` |
| `FW_T_CLMB_MAX` |
| `FW_T_CLMB_R_SP` |
| `FW_T_F_ALT_ERR` |
| `FW_T_HRATE_FF` |
| `FW_T_I_GAIN_PIT` |
| `FW_T_PTCH_DAMP` |
| `FW_T_RLL2THR` |
| `FW_T_SEB_R_FF` |
| `FW_T_SINK_MAX` |
| `FW_T_SINK_MIN` |
| `FW_T_SINK_R_SP` |
| `FW_T_SPDWEIGHT` |
| `FW_T_SPD_DEV_STD` |
| `FW_T_SPD_PRC_STD` |
| `FW_T_SPD_STD` |
| `FW_T_STE_R_TC` |
| `FW_T_TAS_TC` |
| `FW_T_THR_DAMPING` |
| `FW_T_THR_INTEG` |
| `FW_T_THR_LOW_HGT` |
| `FW_T_VERT_ACC` |
| `FW_USE_AIRSPD` |
| `FW_WIND_ARSP_SC` |
| `FW_WING_HEIGHT` |
| `FW_WING_SPAN` |
| `FW_WR_FF` |
| `FW_WR_I` |
| `FW_WR_IMAX` |
| `FW_WR_P` |
| `FW_W_EN` |
| `FW_W_RMAX` |
| `FW_YR_D` |
| `FW_YR_FF` |
| `FW_YR_I` |
| `FW_YR_IMAX` |
| `FW_YR_P` |
| `FW_Y_RMAX` |
| `GF_ACTION` |
| `GF_MAX_HOR_DIST` |
| `GF_MAX_VER_DIST` |
| `GF_PREDICT` |
| `GF_SOURCE` |
| `GPS_1_CONFIG` |
| `GPS_1_GNSS` |
| `GPS_1_PROTOCOL` |
| `GPS_2_CONFIG` |
| `GPS_2_GNSS` |
| `GPS_2_PROTOCOL` |
| `GPS_CFG_WIPE` |
| `GPS_DUMP_COMM` |
| `GPS_SAT_INFO` |
| `GPS_UBX_BAUD2` |
| `GPS_UBX_CFG_INTF` |
| `GPS_UBX_DGNSS_TO` |
| `GPS_UBX_DYNMODEL` |
| `GPS_UBX_JAM_DET` |
| `GPS_UBX_MIN_CNO` |
| `GPS_UBX_MIN_ELEV` |
| `GPS_UBX_MODE` |
| `GPS_UBX_PPK` |
| `GPS_UBX_RATE` |
| `GPS_YAW_OFFSET` |
| `GRF_RATE_CFG` |
| `GRF_SENS_MODEL` |
| `HEATER1_IMU_ID` |
| `HEATER1_TEMP` |
| `HEATER1_TEMP_FF` |
| `HEATER1_TEMP_I` |
| `HEATER1_TEMP_P` |
| `HEATER2_IMU_ID` |
| `HEATER2_TEMP` |
| `HEATER2_TEMP_FF` |
| `HEATER2_TEMP_I` |
| `HEATER2_TEMP_P` |
| `HEATER3_IMU_ID` |
| `HEATER3_TEMP` |
| `HEATER3_TEMP_FF` |
| `HEATER3_TEMP_I` |
| `HEATER3_TEMP_P` |
| `HTE_ACC_GATE` |
| `HTE_HT_ERR_INIT` |
| `HTE_HT_NOISE` |
| `HTE_THR_RANGE` |
| `HTE_VXY_THR` |
| `HTE_VZ_THR` |
| `ICE_CHOKE_ST_DUR` |
| `ICE_EN` |
| `ICE_IGN_DELAY` |
| `ICE_MIN_RUN_RPM` |
| `ICE_ON_SOURCE` |
| `ICE_RUN_FAULT_D` |
| `ICE_STOP_CHOKE` |
| `ICE_STRT_ATTEMPT` |
| `ICE_STRT_DUR` |
| `ICE_STRT_THR` |
| `ICE_THR_SLEW` |
| `ILABS_MODE` |
| `IMU_ACCEL_CUTOFF` |
| `IMU_DGYRO_CUTOFF` |
| `IMU_GYRO_CAL_EN` |
| `IMU_GYRO_CUTOFF` |
| `IMU_GYRO_DNF_BW` |
| `IMU_GYRO_DNF_EN` |
| `IMU_GYRO_DNF_HMC` |
| `IMU_GYRO_DNF_MIN` |
| `IMU_GYRO_FFT_EN` |
| `IMU_GYRO_FFT_LEN` |
| `IMU_GYRO_FFT_MAX` |
| `IMU_GYRO_FFT_MIN` |
| `IMU_GYRO_FFT_SNR` |
| `IMU_GYRO_NF0_BW` |
| `IMU_GYRO_NF0_FRQ` |
| `IMU_GYRO_NF1_BW` |
| `IMU_GYRO_NF1_FRQ` |
| `IMU_GYRO_RATEMAX` |
| `IMU_INTEG_RATE` |
| `INA220_CONFIG` |
| `INA220_CUR_BAT` |
| `INA220_CUR_REG` |
| `INA220_SHUNT_BAT` |
| `INA220_SHUNT_REG` |
| `INA226_CONFIG` |
| `INA226_CURRENT` |
| `INA226_SHUNT` |
| `INA228_CONFIG` |
| `INA228_CURRENT` |
| `INA228_SHUNT` |
| `INA238_CURRENT` |
| `INA238_SHUNT` |
| `ISBD_CONFIG` |
| `ISBD_READ_INT` |
| `ISBD_SBD_TIMEOUT` |
| `ISBD_STACK_TIME` |
| `LNDFW_AIRSPD_MAX` |
| `LNDFW_ROT_MAX` |
| `LNDFW_TRIG_TIME` |
| `LNDFW_VEL_XY_MAX` |
| `LNDFW_VEL_Z_MAX` |
| `LNDFW_XYACC_MAX` |
| `LNDMC_ALT_GND` |
| `LNDMC_ROT_MAX` |
| `LNDMC_XY_VEL_MAX` |
| `LNDMC_Z_VEL_MAX` |
| `LND_FLIGHT_T_HI` |
| `LND_FLIGHT_T_LO` |
| `LPE_ACC_XY` |
| `LPE_ACC_Z` |
| `LPE_BAR_Z` |
| `LPE_EN` |
| `LPE_EPH_MAX` |
| `LPE_EPV_MAX` |
| `LPE_FAKE_ORIGIN` |
| `LPE_FGYRO_HP` |
| `LPE_FLW_OFF_Z` |
| `LPE_FLW_QMIN` |
| `LPE_FLW_R` |
| `LPE_FLW_RR` |
| `LPE_FLW_SCALE` |
| `LPE_FUSION` |
| `LPE_GPS_DELAY` |
| `LPE_GPS_VXY` |
| `LPE_GPS_VZ` |
| `LPE_GPS_XY` |
| `LPE_GPS_Z` |
| `LPE_LAND_VXY` |
| `LPE_LAND_Z` |
| `LPE_LAT` |
| `LPE_LDR_OFF_Z` |
| `LPE_LDR_Z` |
| `LPE_LON` |
| `LPE_LT_COV` |
| `LPE_PN_B` |
| `LPE_PN_P` |
| `LPE_PN_T` |
| `LPE_PN_V` |
| `LPE_SNR_OFF_Z` |
| `LPE_SNR_Z` |
| `LPE_T_MAX_GRADE` |
| `LPE_VIC_P` |
| `LPE_VIS_DELAY` |
| `LPE_VIS_XY` |
| `LPE_VIS_Z` |
| `LPE_VXY_PUB` |
| `LPE_X_LP` |
| `LPE_Z_PUB` |
| `LTEST_ACC_UNC` |
| `LTEST_MEAS_UNC` |
| `LTEST_MODE` |
| `LTEST_POS_UNC_IN` |
| `LTEST_SCALE_X` |
| `LTEST_SCALE_Y` |
| `LTEST_SENS_POS_X` |
| `LTEST_SENS_POS_Y` |
| `LTEST_SENS_POS_Z` |
| `LTEST_SENS_ROT` |
| `LTEST_VEL_UNC_IN` |
| `MAN_ARM_GESTURE` |
| `MAN_DEADZONE` |
| `MAN_KILL_GEST_T` |
| `MAV_0_BROADCAST` |
| `MAV_0_CONFIG` |
| `MAV_0_FLOW_CTRL` |
| `MAV_0_FORWARD` |
| `MAV_0_HL_FREQ` |
| `MAV_0_MODE` |
| `MAV_0_RADIO_CTL` |
| `MAV_0_RATE` |
| `MAV_0_REMOTE_PRT` |
| `MAV_0_UDP_PRT` |
| `MAV_1_BROADCAST` |
| `MAV_1_CONFIG` |
| `MAV_1_FLOW_CTRL` |
| `MAV_1_FORWARD` |
| `MAV_1_HL_FREQ` |
| `MAV_1_MODE` |
| `MAV_1_RADIO_CTL` |
| `MAV_1_RATE` |
| `MAV_1_REMOTE_PRT` |
| `MAV_1_UDP_PRT` |
| `MAV_2_BROADCAST` |
| `MAV_2_CONFIG` |
| `MAV_2_FLOW_CTRL` |
| `MAV_2_FORWARD` |
| `MAV_2_HL_FREQ` |
| `MAV_2_MODE` |
| `MAV_2_RADIO_CTL` |
| `MAV_2_RATE` |
| `MAV_2_REMOTE_PRT` |
| `MAV_2_UDP_PRT` |
| `MAV_COMP_ID` |
| `MAV_FWDEXTSP` |
| `MAV_HASH_CHK_EN` |
| `MAV_HB_FORW_EN` |
| `MAV_PROTO_VER` |
| `MAV_RADIO_TOUT` |
| `MAV_SIK_RADIO_ID` |
| `MAV_SYS_ID` |
| `MAV_S_FORWARD` |
| `MAV_S_MODE` |
| `MAV_TYPE` |
| `MAV_USEHILGPS` |
| `MBE_ENABLE` |
| `MBE_LEARN_GAIN` |
| `MC_ACRO_EXPO` |
| `MC_ACRO_EXPO_Y` |
| `MC_ACRO_P_MAX` |
| `MC_ACRO_R_MAX` |
| `MC_ACRO_SUPEXPO` |
| `MC_ACRO_SUPEXPOY` |
| `MC_ACRO_Y_MAX` |
| `MC_AIRMODE` |
| `MC_AT_APPLY` |
| `MC_AT_EN` |
| `MC_AT_RISE_TIME` |
| `MC_AT_SYSID_AMP` |
| `MC_BAT_SCALE_EN` |
| `MC_MAN_TILT_TAU` |
| `MC_NN_EN` |
| `MC_NN_MANL_CTRL` |
| `MC_NN_MAX_RPM` |
| `MC_NN_MIN_RPM` |
| `MC_NN_THRST_COEF` |
| `MC_ORBIT_RAD_MAX` |
| `MC_ORBIT_YAW_MOD` |
| `MC_PITCHRATE_D` |
| `MC_PITCHRATE_FF` |
| `MC_PITCHRATE_I` |
| `MC_PITCHRATE_K` |
| `MC_PITCHRATE_MAX` |
| `MC_PITCHRATE_P` |
| `MC_PITCH_P` |
| `MC_PR_INT_LIM` |
| `MC_RAPTOR_ENABLE` |
| `MC_RAPTOR_INTREF` |
| `MC_RAPTOR_OFFB` |
| `MC_RAPTOR_VERBOS` |
| `MC_ROLLRATE_D` |
| `MC_ROLLRATE_FF` |
| `MC_ROLLRATE_I` |
| `MC_ROLLRATE_K` |
| `MC_ROLLRATE_MAX` |
| `MC_ROLLRATE_P` |
| `MC_ROLL_P` |
| `MC_RR_INT_LIM` |
| `MC_SLOW_DEF_HVEL` |
| `MC_SLOW_DEF_VVEL` |
| `MC_SLOW_DEF_YAWR` |
| `MC_SLOW_MAP_HVEL` |
| `MC_SLOW_MAP_PTCH` |
| `MC_SLOW_MAP_VVEL` |
| `MC_SLOW_MAP_YAWR` |
| `MC_SLOW_MIN_HVEL` |
| `MC_SLOW_MIN_VVEL` |
| `MC_SLOW_MIN_YAWR` |
| `MC_YAWRATE_D` |
| `MC_YAWRATE_FF` |
| `MC_YAWRATE_I` |
| `MC_YAWRATE_K` |
| `MC_YAWRATE_MAX` |
| `MC_YAWRATE_P` |
| `MC_YAW_P` |
| `MC_YAW_TQ_CUTOFF` |
| `MC_YAW_WEIGHT` |
| `MC_YR_INT_LIM` |
| `MIS_COMMAND_TOUT` |
| `MIS_DIST_1WP` |
| `MIS_LND_ABRT_ALT` |
| `MIS_MNT_YAW_CTL` |
| `MIS_TAKEOFF_ALT` |
| `MIS_TKO_LAND_REQ` |
| `MIS_YAW_ERR` |
| `MIS_YAW_TMT` |
| `MNT_DO_STAB` |
| `MNT_LND_P_MAX` |
| `MNT_LND_P_MIN` |
| `MNT_MAN_PITCH` |
| `MNT_MAN_ROLL` |
| `MNT_MAN_YAW` |
| `MNT_MAV_COMPID` |
| `MNT_MAV_SYSID` |
| `MNT_MAX_PITCH` |
| `MNT_MIN_PITCH` |
| `MNT_MODE_IN` |
| `MNT_MODE_OUT` |
| `MNT_RANGE_ROLL` |
| `MNT_RANGE_YAW` |
| `MNT_RATE_PITCH` |
| `MNT_RATE_YAW` |
| `MNT_RC_IN_MODE` |
| `MNT_TAU` |
| `MODALAI_CONFIG` |
| `MOTFAIL_C2T` |
| `MOTFAIL_HIGH_OFF` |
| `MOTFAIL_LOW_OFF` |
| `MOTFAIL_TIME` |
| `MPC_ACC_DECOUPLE` |
| `MPC_ACC_DOWN_MAX` |
| `MPC_ACC_HOR` |
| `MPC_ACC_HOR_MAX` |
| `MPC_ACC_UP_MAX` |
| `MPC_ALT_MODE` |
| `MPC_HOLD_MAX_XY` |
| `MPC_HOLD_MAX_Z` |
| `MPC_JERK_AUTO` |
| `MPC_JERK_MAX` |
| `MPC_LAND_ALT1` |
| `MPC_LAND_ALT2` |
| `MPC_LAND_ALT3` |
| `MPC_LAND_CRWL` |
| `MPC_LAND_RADIUS` |
| `MPC_LAND_RC_HELP` |
| `MPC_LAND_SPEED` |
| `MPC_MANTHR_MIN` |
| `MPC_MAN_TILT_MAX` |
| `MPC_MAN_Y_MAX` |
| `MPC_MAN_Y_TAU` |
| `MPC_POS_MODE` |
| `MPC_THR_CURVE` |
| `MPC_THR_HOVER` |
| `MPC_THR_MAX` |
| `MPC_THR_MIN` |
| `MPC_THR_XY_MARG` |
| `MPC_TILTMAX_AIR` |
| `MPC_TILTMAX_LND` |
| `MPC_TKO_RAMP_T` |
| `MPC_TKO_SPEED` |
| `MPC_VELD_LP` |
| `MPC_VEL_LP` |
| `MPC_VEL_MANUAL` |
| `MPC_VEL_MAN_BACK` |
| `MPC_VEL_MAN_SIDE` |
| `MPC_VEL_NF_BW` |
| `MPC_VEL_NF_FRQ` |
| `MPC_XY_CRUISE` |
| `MPC_XY_ERR_MAX` |
| `MPC_XY_P` |
| `MPC_XY_TRAJ_P` |
| `MPC_XY_VEL_ALL` |
| `MPC_XY_VEL_D_ACC` |
| `MPC_XY_VEL_I_ACC` |
| `MPC_XY_VEL_MAX` |
| `MPC_XY_VEL_P_ACC` |
| `MPC_YAWRAUTO_ACC` |
| `MPC_YAWRAUTO_MAX` |
| `MPC_YAW_MODE` |
| `MPC_Z_P` |
| `MPC_Z_VEL_ALL` |
| `MPC_Z_VEL_D_ACC` |
| `MPC_Z_VEL_I_ACC` |
| `MPC_Z_VEL_MAX_DN` |
| `MPC_Z_VEL_MAX_UP` |
| `MPC_Z_VEL_P_ACC` |
| `MPC_Z_V_AUTO_DN` |
| `MPC_Z_V_AUTO_UP` |
| `MSP_OSD_CONFIG` |
| `MS_ACCEL_RANGE` |
| `MS_ALIGNMENT` |
| `MS_BARO_RATE_HZ` |
| `MS_EHEAD_YAW` |
| `MS_EMAG_PTCH` |
| `MS_EMAG_ROLL` |
| `MS_EMAG_UNCERT` |
| `MS_EMAG_YAW` |
| `MS_EXT_HEAD_EN` |
| `MS_EXT_MAG_EN` |
| `MS_FILT_RATE_HZ` |
| `MS_GNSS_AID_SRC` |
| `MS_GNSS_OFF1_X` |
| `MS_GNSS_OFF1_Y` |
| `MS_GNSS_OFF1_Z` |
| `MS_GNSS_OFF2_X` |
| `MS_GNSS_OFF2_Y` |
| `MS_GNSS_OFF2_Z` |
| `MS_GNSS_RATE_HZ` |
| `MS_GYRO_RANGE` |
| `MS_IMU_RATE_HZ` |
| `MS_INT_HEAD_EN` |
| `MS_INT_MAG_EN` |
| `MS_MAG_RATE_HZ` |
| `MS_MODE` |
| `MS_OFLW_OFF_X` |
| `MS_OFLW_OFF_Y` |
| `MS_OFLW_OFF_Z` |
| `MS_OFLW_UNCERT` |
| `MS_OPT_FLOW_EN` |
| `MS_SENSOR_PTCH` |
| `MS_SENSOR_ROLL` |
| `MS_SENSOR_YAW` |
| `MS_SVT_EN` |
| `NAV_ACC_RAD` |
| `NAV_DLL_ACT` |
| `NAV_FORCE_VT` |
| `NAV_FW_ALTL_RAD` |
| `NAV_FW_ALT_RAD` |
| `NAV_LOITER_RAD` |
| `NAV_LTR_LAST_DL` |
| `NAV_MC_ALT_RAD` |
| `NAV_MIN_GND_DIST` |
| `NAV_MIN_LTR_ALT` |
| `NAV_RCL_ACT` |
| `NAV_TRAFF_AVOID` |
| `NAV_TRAFF_A_HOR` |
| `NAV_TRAFF_A_VER` |
| `NAV_TRAFF_COLL_T` |
| `NPFG_DAMPING` |
| `NPFG_LB_PERIOD` |
| `NPFG_PERIOD` |
| `NPFG_PERIOD_SF` |
| `NPFG_ROLL_TC` |
| `NPFG_SW_DST_MLT` |
| `NPFG_UB_PERIOD` |
| `OSD_ATXXXX_CFG` |
| `OSD_CH_HEIGHT` |
| `OSD_DWELL_TIME` |
| `OSD_LOG_LEVEL` |
| `OSD_RC_STICK` |
| `OSD_SCROLL_RATE` |
| `OSD_SYMBOLS` |
| `PCA9685_CENT1` |
| `PCA9685_CENT10` |
| `PCA9685_CENT11` |
| `PCA9685_CENT12` |
| `PCA9685_CENT13` |
| `PCA9685_CENT14` |
| `PCA9685_CENT15` |
| `PCA9685_CENT16` |
| `PCA9685_CENT2` |
| `PCA9685_CENT3` |
| `PCA9685_CENT4` |
| `PCA9685_CENT5` |
| `PCA9685_CENT6` |
| `PCA9685_CENT7` |
| `PCA9685_CENT8` |
| `PCA9685_CENT9` |
| `PCA9685_DIS1` |
| `PCA9685_DIS10` |
| `PCA9685_DIS11` |
| `PCA9685_DIS12` |
| `PCA9685_DIS13` |
| `PCA9685_DIS14` |
| `PCA9685_DIS15` |
| `PCA9685_DIS16` |
| `PCA9685_DIS2` |
| `PCA9685_DIS3` |
| `PCA9685_DIS4` |
| `PCA9685_DIS5` |
| `PCA9685_DIS6` |
| `PCA9685_DIS7` |
| `PCA9685_DIS8` |
| `PCA9685_DIS9` |
| `PCA9685_DUTY_EN` |
| `PCA9685_EN_BUS` |
| `PCA9685_FAIL1` |
| `PCA9685_FAIL10` |
| `PCA9685_FAIL11` |
| `PCA9685_FAIL12` |
| `PCA9685_FAIL13` |
| `PCA9685_FAIL14` |
| `PCA9685_FAIL15` |
| `PCA9685_FAIL16` |
| `PCA9685_FAIL2` |
| `PCA9685_FAIL3` |
| `PCA9685_FAIL4` |
| `PCA9685_FAIL5` |
| `PCA9685_FAIL6` |
| `PCA9685_FAIL7` |
| `PCA9685_FAIL8` |
| `PCA9685_FAIL9` |
| `PCA9685_FUNC1` |
| `PCA9685_FUNC10` |
| `PCA9685_FUNC11` |
| `PCA9685_FUNC12` |
| `PCA9685_FUNC13` |
| `PCA9685_FUNC14` |
| `PCA9685_FUNC15` |
| `PCA9685_FUNC16` |
| `PCA9685_FUNC2` |
| `PCA9685_FUNC3` |
| `PCA9685_FUNC4` |
| `PCA9685_FUNC5` |
| `PCA9685_FUNC6` |
| `PCA9685_FUNC7` |
| `PCA9685_FUNC8` |
| `PCA9685_FUNC9` |
| `PCA9685_I2C_ADDR` |
| `PCA9685_MAX1` |
| `PCA9685_MAX10` |
| `PCA9685_MAX11` |
| `PCA9685_MAX12` |
| `PCA9685_MAX13` |
| `PCA9685_MAX14` |
| `PCA9685_MAX15` |
| `PCA9685_MAX16` |
| `PCA9685_MAX2` |
| `PCA9685_MAX3` |
| `PCA9685_MAX4` |
| `PCA9685_MAX5` |
| `PCA9685_MAX6` |
| `PCA9685_MAX7` |
| `PCA9685_MAX8` |
| `PCA9685_MAX9` |
| `PCA9685_MIN1` |
| `PCA9685_MIN10` |
| `PCA9685_MIN11` |
| `PCA9685_MIN12` |
| `PCA9685_MIN13` |
| `PCA9685_MIN14` |
| `PCA9685_MIN15` |
| `PCA9685_MIN16` |
| `PCA9685_MIN2` |
| `PCA9685_MIN3` |
| `PCA9685_MIN4` |
| `PCA9685_MIN5` |
| `PCA9685_MIN6` |
| `PCA9685_MIN7` |
| `PCA9685_MIN8` |
| `PCA9685_MIN9` |
| `PCA9685_PWM_FREQ` |
| `PCA9685_REV` |
| `PCA9685_SCHD_HZ` |
| `PCF8583_MAGNET` |
| `PCF8583_POOL` |
| `PCF8583_RESET` |
| `PD_GRIPPER_TO` |
| `PD_GRIPPER_TYPE` |
| `PLD_BTOUT` |
| `PLD_FAPPR_ALT` |
| `PLD_HACC_RAD` |
| `PLD_MAX_SRCH` |
| `PLD_SRCH_ALT` |
| `PLD_SRCH_TOUT` |
| `PPS_CAP_ENABLE` |
| `PPS_CAP_GPS_ID` |
| `PP_LOOKAHD_GAIN` |
| `PP_LOOKAHD_MAX` |
| `PP_LOOKAHD_MIN` |
| `PWM_AUX_CENT1` |
| `PWM_AUX_CENT10` |
| `PWM_AUX_CENT11` |
| `PWM_AUX_CENT2` |
| `PWM_AUX_CENT3` |
| `PWM_AUX_CENT4` |
| `PWM_AUX_CENT5` |
| `PWM_AUX_CENT6` |
| `PWM_AUX_CENT7` |
| `PWM_AUX_CENT8` |
| `PWM_AUX_CENT9` |
| `PWM_AUX_DIS1` |
| `PWM_AUX_DIS10` |
| `PWM_AUX_DIS11` |
| `PWM_AUX_DIS2` |
| `PWM_AUX_DIS3` |
| `PWM_AUX_DIS4` |
| `PWM_AUX_DIS5` |
| `PWM_AUX_DIS6` |
| `PWM_AUX_DIS7` |
| `PWM_AUX_DIS8` |
| `PWM_AUX_DIS9` |
| `PWM_AUX_FAIL1` |
| `PWM_AUX_FAIL10` |
| `PWM_AUX_FAIL11` |
| `PWM_AUX_FAIL2` |
| `PWM_AUX_FAIL3` |
| `PWM_AUX_FAIL4` |
| `PWM_AUX_FAIL5` |
| `PWM_AUX_FAIL6` |
| `PWM_AUX_FAIL7` |
| `PWM_AUX_FAIL8` |
| `PWM_AUX_FAIL9` |
| `PWM_AUX_FUNC1` |
| `PWM_AUX_FUNC10` |
| `PWM_AUX_FUNC11` |
| `PWM_AUX_FUNC2` |
| `PWM_AUX_FUNC3` |
| `PWM_AUX_FUNC4` |
| `PWM_AUX_FUNC5` |
| `PWM_AUX_FUNC6` |
| `PWM_AUX_FUNC7` |
| `PWM_AUX_FUNC8` |
| `PWM_AUX_FUNC9` |
| `PWM_AUX_MAX1` |
| `PWM_AUX_MAX10` |
| `PWM_AUX_MAX11` |
| `PWM_AUX_MAX2` |
| `PWM_AUX_MAX3` |
| `PWM_AUX_MAX4` |
| `PWM_AUX_MAX5` |
| `PWM_AUX_MAX6` |
| `PWM_AUX_MAX7` |
| `PWM_AUX_MAX8` |
| `PWM_AUX_MAX9` |
| `PWM_AUX_MIN1` |
| `PWM_AUX_MIN10` |
| `PWM_AUX_MIN11` |
| `PWM_AUX_MIN2` |
| `PWM_AUX_MIN3` |
| `PWM_AUX_MIN4` |
| `PWM_AUX_MIN5` |
| `PWM_AUX_MIN6` |
| `PWM_AUX_MIN7` |
| `PWM_AUX_MIN8` |
| `PWM_AUX_MIN9` |
| `PWM_AUX_REV` |
| `PWM_AUX_TIM0` |
| `PWM_AUX_TIM1` |
| `PWM_AUX_TIM2` |
| `PWM_AUX_TIM3` |
| `PWM_MAIN_CENT1` |
| `PWM_MAIN_CENT2` |
| `PWM_MAIN_CENT3` |
| `PWM_MAIN_CENT4` |
| `PWM_MAIN_CENT5` |
| `PWM_MAIN_CENT6` |
| `PWM_MAIN_CENT7` |
| `PWM_MAIN_CENT8` |
| `PWM_MAIN_DIS1` |
| `PWM_MAIN_DIS2` |
| `PWM_MAIN_DIS3` |
| `PWM_MAIN_DIS4` |
| `PWM_MAIN_DIS5` |
| `PWM_MAIN_DIS6` |
| `PWM_MAIN_DIS7` |
| `PWM_MAIN_DIS8` |
| `PWM_MAIN_FAIL1` |
| `PWM_MAIN_FAIL2` |
| `PWM_MAIN_FAIL3` |
| `PWM_MAIN_FAIL4` |
| `PWM_MAIN_FAIL5` |
| `PWM_MAIN_FAIL6` |
| `PWM_MAIN_FAIL7` |
| `PWM_MAIN_FAIL8` |
| `PWM_MAIN_FUNC1` |
| `PWM_MAIN_FUNC2` |
| `PWM_MAIN_FUNC3` |
| `PWM_MAIN_FUNC4` |
| `PWM_MAIN_FUNC5` |
| `PWM_MAIN_FUNC6` |
| `PWM_MAIN_FUNC7` |
| `PWM_MAIN_FUNC8` |
| `PWM_MAIN_MAX1` |
| `PWM_MAIN_MAX2` |
| `PWM_MAIN_MAX3` |
| `PWM_MAIN_MAX4` |
| `PWM_MAIN_MAX5` |
| `PWM_MAIN_MAX6` |
| `PWM_MAIN_MAX7` |
| `PWM_MAIN_MAX8` |
| `PWM_MAIN_MIN1` |
| `PWM_MAIN_MIN2` |
| `PWM_MAIN_MIN3` |
| `PWM_MAIN_MIN4` |
| `PWM_MAIN_MIN5` |
| `PWM_MAIN_MIN6` |
| `PWM_MAIN_MIN7` |
| `PWM_MAIN_MIN8` |
| `PWM_MAIN_REV` |
| `PWM_MAIN_TIM0` |
| `PWM_MAIN_TIM1` |
| `PWM_MAIN_TIM2` |
| `PWM_SBUS_MODE` |
| `RA_ACC_RAD_MAX` |
| `RA_MAX_STR_ANG` |
| `RA_STR_RATE_LIM` |
| `RA_WHEEL_BASE` |
| `RBCLW_DIS1` |
| `RBCLW_DIS2` |
| `RBCLW_FAIL1` |
| `RBCLW_FAIL2` |
| `RBCLW_FUNC1` |
| `RBCLW_FUNC2` |
| `RBCLW_MAX1` |
| `RBCLW_MAX2` |
| `RBCLW_MIN1` |
| `RBCLW_MIN2` |
| `RBCLW_REV` |
| `RC10_MAX` |
| `RC10_MIN` |
| `RC10_REV` |
| `RC10_TRIM` |
| `RC11_MAX` |
| `RC11_MIN` |
| `RC11_REV` |
| `RC11_TRIM` |
| `RC12_MAX` |
| `RC12_MIN` |
| `RC12_REV` |
| `RC12_TRIM` |
| `RC13_MAX` |
| `RC13_MIN` |
| `RC13_REV` |
| `RC13_TRIM` |
| `RC14_MAX` |
| `RC14_MIN` |
| `RC14_REV` |
| `RC14_TRIM` |
| `RC15_MAX` |
| `RC15_MIN` |
| `RC15_REV` |
| `RC15_TRIM` |
| `RC16_MAX` |
| `RC16_MIN` |
| `RC16_REV` |
| `RC16_TRIM` |
| `RC17_MAX` |
| `RC17_MIN` |
| `RC17_REV` |
| `RC17_TRIM` |
| `RC18_MAX` |
| `RC18_MIN` |
| `RC18_REV` |
| `RC18_TRIM` |
| `RC1_MAX` |
| `RC1_MIN` |
| `RC1_REV` |
| `RC1_TRIM` |
| `RC2_MAX` |
| `RC2_MIN` |
| `RC2_REV` |
| `RC2_TRIM` |
| `RC3_MAX` |
| `RC3_MIN` |
| `RC3_REV` |
| `RC3_TRIM` |
| `RC4_MAX` |
| `RC4_MIN` |
| `RC4_REV` |
| `RC4_TRIM` |
| `RC5_MAX` |
| `RC5_MIN` |
| `RC5_REV` |
| `RC5_TRIM` |
| `RC6_MAX` |
| `RC6_MIN` |
| `RC6_REV` |
| `RC6_TRIM` |
| `RC7_MAX` |
| `RC7_MIN` |
| `RC7_REV` |
| `RC7_TRIM` |
| `RC8_MAX` |
| `RC8_MIN` |
| `RC8_REV` |
| `RC8_TRIM` |
| `RC9_MAX` |
| `RC9_MIN` |
| `RC9_REV` |
| `RC9_TRIM` |
| `RC_ARMSWITCH_TH` |
| `RC_CHAN_CNT` |
| `RC_CRSF_PRT_CFG` |
| `RC_CRSF_TEL_EN` |
| `RC_DSM_PRT_CFG` |
| `RC_FAILS_THR` |
| `RC_GHST_PRT_CFG` |
| `RC_GHST_TEL_EN` |
| `RC_INPUT_PROTO` |
| `RC_MAP_AUX1` |
| `RC_MAP_AUX2` |
| `RC_MAP_AUX3` |
| `RC_MAP_AUX4` |
| `RC_MAP_AUX5` |
| `RC_MAP_AUX6` |
| `RC_MAP_ENG_MOT` |
| `RC_MAP_FAILSAFE` |
| `RC_MAP_PARAM1` |
| `RC_MAP_PARAM2` |
| `RC_MAP_PARAM3` |
| `RC_MAP_PITCH` |
| `RC_MAP_ROLL` |
| `RC_MAP_THROTTLE` |
| `RC_MAP_YAW` |
| `RC_PORT_CONFIG` |
| `RC_RSSI_PWM_CHAN` |
| `RC_RSSI_PWM_MAX` |
| `RC_RSSI_PWM_MIN` |
| `RC_SBUS_PRT_CFG` |
| `RD_TRANS_DRV_TRN` |
| `RD_TRANS_TRN_DRV` |
| `RD_WHEEL_TRACK` |
| `RD_YAW_STK_GAIN` |
| `RM_COURSE_CTL_TH` |
| `RM_WHEEL_TRACK` |
| `RM_YAW_STK_GAIN` |
| `RO_ACCEL_LIM` |
| `RO_DECEL_LIM` |
| `RO_JERK_LIM` |
| `RO_MAX_THR_SPEED` |
| `RO_SPEED_I` |
| `RO_SPEED_LIM` |
| `RO_SPEED_P` |
| `RO_SPEED_RED` |
| `RO_SPEED_TH` |
| `RO_YAW_ACCEL_LIM` |
| `RO_YAW_DECEL_LIM` |
| `RO_YAW_EXPO` |
| `RO_YAW_P` |
| `RO_YAW_RATE_CORR` |
| `RO_YAW_RATE_I` |
| `RO_YAW_RATE_LIM` |
| `RO_YAW_RATE_P` |
| `RO_YAW_RATE_TH` |
| `RO_YAW_STICK_DZ` |
| `RO_YAW_SUPEXPO` |
| `RPM_CAP_ENABLE` |
| `RPM_PULS_PER_REV` |
| `RWTO_MAX_THR` |
| `RWTO_NUDGE` |
| `RWTO_PSP` |
| `RWTO_RAMP_TIME` |
| `RWTO_ROT_AIRSPD` |
| `RWTO_ROT_TIME` |
| `RWTO_TKOFF` |
| `SBG_BAUDRATE` |
| `SBG_CONFIGURE_EN` |
| `SBG_MODE` |
| `SDLOG_ALGORITHM` |
| `SDLOG_BACKEND` |
| `SDLOG_BOOT_BAT` |
| `SDLOG_DIRS_MAX` |
| `SDLOG_EXCH_KEY` |
| `SDLOG_KEY` |
| `SDLOG_MISSION` |
| `SDLOG_MODE` |
| `SDLOG_PROFILE` |
| `SDLOG_UTC_OFFSET` |
| `SDLOG_UUID` |
| `SENS_AFBR_HYSTER` |
| `SENS_AFBR_L_RATE` |
| `SENS_AFBR_MODE` |
| `SENS_AFBR_S_RATE` |
| `SENS_AFBR_THRESH` |
| `SENS_BAHRS_CFG` |
| `SENS_BARO_QNH` |
| `SENS_BARO_RATE` |
| `SENS_BAR_AUTOCAL` |
| `SENS_BOARD_ROT` |
| `SENS_BOARD_X_OFF` |
| `SENS_BOARD_Y_OFF` |
| `SENS_BOARD_Z_OFF` |
| `SENS_CM8JL65_CFG` |
| `SENS_CM8JL65_R_0` |
| `SENS_DPRES_ANSC` |
| `SENS_DPRES_OFF` |
| `SENS_DPRES_REV` |
| `SENS_EN_ADIS164X` |
| `SENS_EN_ADIS165X` |
| `SENS_EN_AGPSIM` |
| `SENS_EN_ARSPDSIM` |
| `SENS_EN_ASP5033` |
| `SENS_EN_AUAVX` |
| `SENS_EN_BAROSIM` |
| `SENS_EN_BATT` |
| `SENS_EN_ETSASPD` |
| `SENS_EN_GPSSIM` |
| `SENS_EN_GRF_CFG` |
| `SENS_EN_INA220` |
| `SENS_EN_INA226` |
| `SENS_EN_INA228` |
| `SENS_EN_INA238` |
| `SENS_EN_IRLOCK` |
| `SENS_EN_LL40LS` |
| `SENS_EN_MAGSIM` |
| `SENS_EN_MB12XX` |
| `SENS_EN_MCP9808` |
| `SENS_EN_MPDT` |
| `SENS_EN_MS4515` |
| `SENS_EN_MS4525DO` |
| `SENS_EN_MS5525DS` |
| `SENS_EN_PAA3905` |
| `SENS_EN_PAW3902` |
| `SENS_EN_PCF8583` |
| `SENS_EN_PGA460` |
| `SENS_EN_PMW3901` |
| `SENS_EN_PX4FLOW` |
| `SENS_EN_SCH16T` |
| `SENS_EN_SDP3X` |
| `SENS_EN_SF0X` |
| `SENS_EN_SF1XX` |
| `SENS_EN_SF45_CFG` |
| `SENS_EN_SHT3X` |
| `SENS_EN_SPA06` |
| `SENS_EN_SPL06` |
| `SENS_EN_SR05` |
| `SENS_EN_TF02PRO` |
| `SENS_EN_THERMAL` |
| `SENS_EN_TMP102` |
| `SENS_EN_TRANGER` |
| `SENS_EN_VL53L0X` |
| `SENS_EN_VL53L1X` |
| `SENS_EXT_I2C_PRB` |
| `SENS_FLOW_MAXHGT` |
| `SENS_FLOW_MAXR` |
| `SENS_FLOW_MINHGT` |
| `SENS_FLOW_RATE` |
| `SENS_FLOW_ROT` |
| `SENS_FLOW_SCALE` |
| `SENS_FTX_CFG` |
| `SENS_GPS0_DELAY` |
| `SENS_GPS0_ID` |
| `SENS_GPS0_OFFX` |
| `SENS_GPS0_OFFY` |
| `SENS_GPS0_OFFZ` |
| `SENS_GPS1_DELAY` |
| `SENS_GPS1_ID` |
| `SENS_GPS1_OFFX` |
| `SENS_GPS1_OFFY` |
| `SENS_GPS1_OFFZ` |
| `SENS_GPS_MASK` |
| `SENS_GPS_PRIME` |
| `SENS_GPS_TAU` |
| `SENS_ILABS_CFG` |
| `SENS_IMU_AUTOCAL` |
| `SENS_IMU_CLPNOTI` |
| `SENS_IMU_MODE` |
| `SENS_INT_BARO_EN` |
| `SENS_LEDDAR1_CFG` |
| `SENS_MAG_AUTOCAL` |
| `SENS_MAG_AUTOROT` |
| `SENS_MAG_MODE` |
| `SENS_MAG_RATE` |
| `SENS_MAG_SIDES` |
| `SENS_MB12_0_ROT` |
| `SENS_MB12_10_ROT` |
| `SENS_MB12_11_ROT` |
| `SENS_MB12_1_ROT` |
| `SENS_MB12_2_ROT` |
| `SENS_MB12_3_ROT` |
| `SENS_MB12_4_ROT` |
| `SENS_MB12_5_ROT` |
| `SENS_MB12_6_ROT` |
| `SENS_MB12_7_ROT` |
| `SENS_MB12_8_ROT` |
| `SENS_MB12_9_ROT` |
| `SENS_MPDT0_ROT` |
| `SENS_MPDT10_ROT` |
| `SENS_MPDT11_ROT` |
| `SENS_MPDT1_ROT` |
| `SENS_MPDT2_ROT` |
| `SENS_MPDT3_ROT` |
| `SENS_MPDT4_ROT` |
| `SENS_MPDT5_ROT` |
| `SENS_MPDT6_ROT` |
| `SENS_MPDT7_ROT` |
| `SENS_MPDT8_ROT` |
| `SENS_MPDT9_ROT` |
| `SENS_MS_CFG` |
| `SENS_OR_ADIS164X` |
| `SENS_SBG_CFG` |
| `SENS_SF0X_CFG` |
| `SENS_TFLOW_CFG` |
| `SENS_TFMINI_CFG` |
| `SENS_TFMINI_HW` |
| `SENS_ULAND_CFG` |
| `SENS_VN_CFG` |
| `SEP_AUTO_CONFIG` |
| `SEP_CONST_USAGE` |
| `SEP_DUMP_COMM` |
| `SEP_HARDW_SETUP` |
| `SEP_LOG_FORCE` |
| `SEP_LOG_HZ` |
| `SEP_LOG_LEVEL` |
| `SEP_OUTP_HZ` |
| `SEP_PITCH_OFFS` |
| `SEP_PORT1_CFG` |
| `SEP_PORT2_CFG` |
| `SEP_SAT_INFO` |
| `SEP_STREAM_LOG` |
| `SEP_STREAM_MAIN` |
| `SEP_YAW_OFFS` |
| `SER_EXT2_BAUD` |
| `SER_GPS1_BAUD` |
| `SER_GPS2_BAUD` |
| `SER_GPS3_BAUD` |
| `SER_MXS_BAUD` |
| `SER_RC_BAUD` |
| `SER_TEL1_BAUD` |
| `SER_TEL2_BAUD` |
| `SER_TEL3_BAUD` |
| `SER_TEL4_BAUD` |
| `SER_URT6_BAUD` |
| `SER_WIFI_BAUD` |
| `SF1XX_ROT` |
| `SF45_ORIENT_CFG` |
| `SF45_UPDATE_CFG` |
| `SF45_YAW_CFG` |
| `SIH_DISTSNSR_MAX` |
| `SIH_DISTSNSR_MIN` |
| `SIH_DISTSNSR_OVR` |
| `SIH_F_CP0` |
| `SIH_F_CP1` |
| `SIH_F_CP2` |
| `SIH_F_CT0` |
| `SIH_F_CT1` |
| `SIH_F_CT2` |
| `SIH_F_DIA_INCH` |
| `SIH_F_Q_MAX` |
| `SIH_F_RPM_MAX` |
| `SIH_F_T_MAX` |
| `SIH_IXX` |
| `SIH_IXY` |
| `SIH_IXZ` |
| `SIH_IYY` |
| `SIH_IYZ` |
| `SIH_IZZ` |
| `SIH_KDV` |
| `SIH_KDW` |
| `SIH_LOC_H0` |
| `SIH_LOC_LAT0` |
| `SIH_LOC_LON0` |
| `SIH_L_PITCH` |
| `SIH_L_ROLL` |
| `SIH_MASS` |
| `SIH_Q_MAX` |
| `SIH_RNGBC_NOISE` |
| `SIH_T_MAX` |
| `SIH_T_TAU` |
| `SIH_VEHICLE_TYPE` |
| `SIH_WIND_E` |
| `SIH_WIND_N` |
| `SIM_AGP_FAIL` |
| `SIM_ARSPD_FAIL` |
| `SIM_BARO_OFF_P` |
| `SIM_BARO_OFF_T` |
| `SIM_BAT_DRAIN` |
| `SIM_BAT_MIN_PCT` |
| `SIM_GPS_USED` |
| `SIM_GZ_EC_DIS1` |
| `SIM_GZ_EC_DIS10` |
| `SIM_GZ_EC_DIS11` |
| `SIM_GZ_EC_DIS12` |
| `SIM_GZ_EC_DIS13` |
| `SIM_GZ_EC_DIS14` |
| `SIM_GZ_EC_DIS15` |
| `SIM_GZ_EC_DIS16` |
| `SIM_GZ_EC_DIS2` |
| `SIM_GZ_EC_DIS3` |
| `SIM_GZ_EC_DIS4` |
| `SIM_GZ_EC_DIS5` |
| `SIM_GZ_EC_DIS6` |
| `SIM_GZ_EC_DIS7` |
| `SIM_GZ_EC_DIS8` |
| `SIM_GZ_EC_DIS9` |
| `SIM_GZ_EC_FAIL1` |
| `SIM_GZ_EC_FAIL10` |
| `SIM_GZ_EC_FAIL11` |
| `SIM_GZ_EC_FAIL12` |
| `SIM_GZ_EC_FAIL13` |
| `SIM_GZ_EC_FAIL14` |
| `SIM_GZ_EC_FAIL15` |
| `SIM_GZ_EC_FAIL16` |
| `SIM_GZ_EC_FAIL2` |
| `SIM_GZ_EC_FAIL3` |
| `SIM_GZ_EC_FAIL4` |
| `SIM_GZ_EC_FAIL5` |
| `SIM_GZ_EC_FAIL6` |
| `SIM_GZ_EC_FAIL7` |
| `SIM_GZ_EC_FAIL8` |
| `SIM_GZ_EC_FAIL9` |
| `SIM_GZ_EC_FUNC1` |
| `SIM_GZ_EC_FUNC10` |
| `SIM_GZ_EC_FUNC11` |
| `SIM_GZ_EC_FUNC12` |
| `SIM_GZ_EC_FUNC13` |
| `SIM_GZ_EC_FUNC14` |
| `SIM_GZ_EC_FUNC15` |
| `SIM_GZ_EC_FUNC16` |
| `SIM_GZ_EC_FUNC2` |
| `SIM_GZ_EC_FUNC3` |
| `SIM_GZ_EC_FUNC4` |
| `SIM_GZ_EC_FUNC5` |
| `SIM_GZ_EC_FUNC6` |
| `SIM_GZ_EC_FUNC7` |
| `SIM_GZ_EC_FUNC8` |
| `SIM_GZ_EC_FUNC9` |
| `SIM_GZ_EC_MAX1` |
| `SIM_GZ_EC_MAX10` |
| `SIM_GZ_EC_MAX11` |
| `SIM_GZ_EC_MAX12` |
| `SIM_GZ_EC_MAX13` |
| `SIM_GZ_EC_MAX14` |
| `SIM_GZ_EC_MAX15` |
| `SIM_GZ_EC_MAX16` |
| `SIM_GZ_EC_MAX2` |
| `SIM_GZ_EC_MAX3` |
| `SIM_GZ_EC_MAX4` |
| `SIM_GZ_EC_MAX5` |
| `SIM_GZ_EC_MAX6` |
| `SIM_GZ_EC_MAX7` |
| `SIM_GZ_EC_MAX8` |
| `SIM_GZ_EC_MAX9` |
| `SIM_GZ_EC_MIN1` |
| `SIM_GZ_EC_MIN10` |
| `SIM_GZ_EC_MIN11` |
| `SIM_GZ_EC_MIN12` |
| `SIM_GZ_EC_MIN13` |
| `SIM_GZ_EC_MIN14` |
| `SIM_GZ_EC_MIN15` |
| `SIM_GZ_EC_MIN16` |
| `SIM_GZ_EC_MIN2` |
| `SIM_GZ_EC_MIN3` |
| `SIM_GZ_EC_MIN4` |
| `SIM_GZ_EC_MIN5` |
| `SIM_GZ_EC_MIN6` |
| `SIM_GZ_EC_MIN7` |
| `SIM_GZ_EC_MIN8` |
| `SIM_GZ_EC_MIN9` |
| `SIM_GZ_EC_REV` |
| `SIM_GZ_EN_ASPD` |
| `SIM_GZ_EN_BARO` |
| `SIM_GZ_EN_FLOW` |
| `SIM_GZ_EN_GPS` |
| `SIM_GZ_EN_LIDAR` |
| `SIM_GZ_EN_ODOM` |
| `SIM_GZ_SV_DIS1` |
| `SIM_GZ_SV_DIS2` |
| `SIM_GZ_SV_DIS3` |
| `SIM_GZ_SV_DIS4` |
| `SIM_GZ_SV_DIS5` |
| `SIM_GZ_SV_DIS6` |
| `SIM_GZ_SV_DIS7` |
| `SIM_GZ_SV_DIS8` |
| `SIM_GZ_SV_FAIL1` |
| `SIM_GZ_SV_FAIL2` |
| `SIM_GZ_SV_FAIL3` |
| `SIM_GZ_SV_FAIL4` |
| `SIM_GZ_SV_FAIL5` |
| `SIM_GZ_SV_FAIL6` |
| `SIM_GZ_SV_FAIL7` |
| `SIM_GZ_SV_FAIL8` |
| `SIM_GZ_SV_FUNC1` |
| `SIM_GZ_SV_FUNC2` |
| `SIM_GZ_SV_FUNC3` |
| `SIM_GZ_SV_FUNC4` |
| `SIM_GZ_SV_FUNC5` |
| `SIM_GZ_SV_FUNC6` |
| `SIM_GZ_SV_FUNC7` |
| `SIM_GZ_SV_FUNC8` |
| `SIM_GZ_SV_MAX1` |
| `SIM_GZ_SV_MAX2` |
| `SIM_GZ_SV_MAX3` |
| `SIM_GZ_SV_MAX4` |
| `SIM_GZ_SV_MAX5` |
| `SIM_GZ_SV_MAX6` |
| `SIM_GZ_SV_MAX7` |
| `SIM_GZ_SV_MAX8` |
| `SIM_GZ_SV_MAXA1` |
| `SIM_GZ_SV_MAXA2` |
| `SIM_GZ_SV_MAXA3` |
| `SIM_GZ_SV_MAXA4` |
| `SIM_GZ_SV_MAXA5` |
| `SIM_GZ_SV_MAXA6` |
| `SIM_GZ_SV_MAXA7` |
| `SIM_GZ_SV_MAXA8` |
| `SIM_GZ_SV_MIN1` |
| `SIM_GZ_SV_MIN2` |
| `SIM_GZ_SV_MIN3` |
| `SIM_GZ_SV_MIN4` |
| `SIM_GZ_SV_MIN5` |
| `SIM_GZ_SV_MIN6` |
| `SIM_GZ_SV_MIN7` |
| `SIM_GZ_SV_MIN8` |
| `SIM_GZ_SV_MINA1` |
| `SIM_GZ_SV_MINA2` |
| `SIM_GZ_SV_MINA3` |
| `SIM_GZ_SV_MINA4` |
| `SIM_GZ_SV_MINA5` |
| `SIM_GZ_SV_MINA6` |
| `SIM_GZ_SV_MINA7` |
| `SIM_GZ_SV_MINA8` |
| `SIM_GZ_SV_REV` |
| `SIM_GZ_WH_DIS1` |
| `SIM_GZ_WH_DIS2` |
| `SIM_GZ_WH_DIS3` |
| `SIM_GZ_WH_DIS4` |
| `SIM_GZ_WH_FAIL1` |
| `SIM_GZ_WH_FAIL2` |
| `SIM_GZ_WH_FAIL3` |
| `SIM_GZ_WH_FAIL4` |
| `SIM_GZ_WH_FUNC1` |
| `SIM_GZ_WH_FUNC2` |
| `SIM_GZ_WH_FUNC3` |
| `SIM_GZ_WH_FUNC4` |
| `SIM_GZ_WH_MAX1` |
| `SIM_GZ_WH_MAX2` |
| `SIM_GZ_WH_MAX3` |
| `SIM_GZ_WH_MAX4` |
| `SIM_GZ_WH_MIN1` |
| `SIM_GZ_WH_MIN2` |
| `SIM_GZ_WH_MIN3` |
| `SIM_GZ_WH_MIN4` |
| `SIM_GZ_WH_REV` |
| `SIM_MAG_OFFSET_X` |
| `SIM_MAG_OFFSET_Y` |
| `SIM_MAG_OFFSET_Z` |
| `SYS_AUTOCONFIG` |
| `SYS_AUTOSTART` |
| `SYS_BL_UPDATE` |
| `SYS_CAL_ACCEL` |
| `SYS_CAL_BARO` |
| `SYS_CAL_GYRO` |
| `SYS_CAL_TDEL` |
| `SYS_CAL_TMAX` |
| `SYS_CAL_TMIN` |
| `SYS_DM_BACKEND` |
| `SYS_FAC_CAL_MODE` |
| `SYS_FAILURE_EN` |
| `SYS_HAS_BARO` |
| `SYS_HAS_GPS` |
| `SYS_HAS_MAG` |
| `SYS_HAS_NUM_ASPD` |
| `SYS_HAS_NUM_DIST` |
| `SYS_HAS_NUM_OF` |
| `SYS_HF_MAV` |
| `SYS_HITL` |
| `SYS_PARAM_VER` |
| `SYS_RGB_MAXBRT` |
| `SYS_STCK_EN` |
| `SYS_USB_AUTO` |
| `SYS_VEHICLE_RESP` |
| `TAP_ESC_FUNC1` |
| `TAP_ESC_FUNC2` |
| `TAP_ESC_FUNC3` |
| `TAP_ESC_FUNC4` |
| `TAP_ESC_FUNC5` |
| `TAP_ESC_FUNC6` |
| `TAP_ESC_FUNC7` |
| `TAP_ESC_FUNC8` |
| `TAP_ESC_REV` |
| `TC_A0_ID` |
| `TC_A0_TMAX` |
| `TC_A0_TMIN` |
| `TC_A0_TREF` |
| `TC_A0_X0_0` |
| `TC_A0_X0_1` |
| `TC_A0_X0_2` |
| `TC_A0_X1_0` |
| `TC_A0_X1_1` |
| `TC_A0_X1_2` |
| `TC_A0_X2_0` |
| `TC_A0_X2_1` |
| `TC_A0_X2_2` |
| `TC_A0_X3_0` |
| `TC_A0_X3_1` |
| `TC_A0_X3_2` |
| `TC_A1_ID` |
| `TC_A1_TMAX` |
| `TC_A1_TMIN` |
| `TC_A1_TREF` |
| `TC_A1_X0_0` |
| `TC_A1_X0_1` |
| `TC_A1_X0_2` |
| `TC_A1_X1_0` |
| `TC_A1_X1_1` |
| `TC_A1_X1_2` |
| `TC_A1_X2_0` |
| `TC_A1_X2_1` |
| `TC_A1_X2_2` |
| `TC_A1_X3_0` |
| `TC_A1_X3_1` |
| `TC_A1_X3_2` |
| `TC_A2_ID` |
| `TC_A2_TMAX` |
| `TC_A2_TMIN` |
| `TC_A2_TREF` |
| `TC_A2_X0_0` |
| `TC_A2_X0_1` |
| `TC_A2_X0_2` |
| `TC_A2_X1_0` |
| `TC_A2_X1_1` |
| `TC_A2_X1_2` |
| `TC_A2_X2_0` |
| `TC_A2_X2_1` |
| `TC_A2_X2_2` |
| `TC_A2_X3_0` |
| `TC_A2_X3_1` |
| `TC_A2_X3_2` |
| `TC_A3_ID` |
| `TC_A3_TMAX` |
| `TC_A3_TMIN` |
| `TC_A3_TREF` |
| `TC_A3_X0_0` |
| `TC_A3_X0_1` |
| `TC_A3_X0_2` |
| `TC_A3_X1_0` |
| `TC_A3_X1_1` |
| `TC_A3_X1_2` |
| `TC_A3_X2_0` |
| `TC_A3_X2_1` |
| `TC_A3_X2_2` |
| `TC_A3_X3_0` |
| `TC_A3_X3_1` |
| `TC_A3_X3_2` |
| `TC_A_ENABLE` |
| `TC_B0_ID` |
| `TC_B0_TMAX` |
| `TC_B0_TMIN` |
| `TC_B0_TREF` |
| `TC_B0_X0` |
| `TC_B0_X1` |
| `TC_B0_X2` |
| `TC_B0_X3` |
| `TC_B0_X4` |
| `TC_B0_X5` |
| `TC_B1_ID` |
| `TC_B1_TMAX` |
| `TC_B1_TMIN` |
| `TC_B1_TREF` |
| `TC_B1_X0` |
| `TC_B1_X1` |
| `TC_B1_X2` |
| `TC_B1_X3` |
| `TC_B1_X4` |
| `TC_B1_X5` |
| `TC_B2_ID` |
| `TC_B2_TMAX` |
| `TC_B2_TMIN` |
| `TC_B2_TREF` |
| `TC_B2_X0` |
| `TC_B2_X1` |
| `TC_B2_X2` |
| `TC_B2_X3` |
| `TC_B2_X4` |
| `TC_B2_X5` |
| `TC_B3_ID` |
| `TEL_BST_EN` |
| `TEL_FRSKY_CONFIG` |
| `TEL_HOTT_CONFIG` |
| `TEST_D` |
| `TEST_DEV` |
| `TEST_D_LP` |
| `TEST_HP` |
| `TEST_I` |
| `TEST_I_MAX` |
| `TEST_LP` |
| `TEST_MAX` |
| `TEST_MEAN` |
| `TEST_MIN` |
| `TEST_P` |
| `TEST_TRIM` |
| `THR_MDL_FAC` |
| `TRIG_ACT_TIME` |
| `TRIG_DISTANCE` |
| `TRIG_INTERFACE` |
| `TRIG_INTERVAL` |
| `TRIG_MIN_INTERVA` |
| `TRIG_MODE` |
| `TRIG_POLARITY` |
| `TRIG_PWM_NEUTRAL` |
| `TRIG_PWM_SHOOT` |
| `TRIM_PITCH` |
| `TRIM_ROLL` |
| `TRIM_YAW` |
| `UAVCAN_EC_FAIL1` |
| `UAVCAN_EC_FAIL10` |
| `UAVCAN_EC_FAIL11` |
| `UAVCAN_EC_FAIL12` |
| `UAVCAN_EC_FAIL2` |
| `UAVCAN_EC_FAIL3` |
| `UAVCAN_EC_FAIL4` |
| `UAVCAN_EC_FAIL5` |
| `UAVCAN_EC_FAIL6` |
| `UAVCAN_EC_FAIL7` |
| `UAVCAN_EC_FAIL8` |
| `UAVCAN_EC_FAIL9` |
| `UAVCAN_EC_FUNC1` |
| `UAVCAN_EC_FUNC10` |
| `UAVCAN_EC_FUNC11` |
| `UAVCAN_EC_FUNC12` |
| `UAVCAN_EC_FUNC2` |
| `UAVCAN_EC_FUNC3` |
| `UAVCAN_EC_FUNC4` |
| `UAVCAN_EC_FUNC5` |
| `UAVCAN_EC_FUNC6` |
| `UAVCAN_EC_FUNC7` |
| `UAVCAN_EC_FUNC8` |
| `UAVCAN_EC_FUNC9` |
| `UAVCAN_EC_MAX1` |
| `UAVCAN_EC_MAX10` |
| `UAVCAN_EC_MAX11` |
| `UAVCAN_EC_MAX12` |
| `UAVCAN_EC_MAX2` |
| `UAVCAN_EC_MAX3` |
| `UAVCAN_EC_MAX4` |
| `UAVCAN_EC_MAX5` |
| `UAVCAN_EC_MAX6` |
| `UAVCAN_EC_MAX7` |
| `UAVCAN_EC_MAX8` |
| `UAVCAN_EC_MAX9` |
| `UAVCAN_EC_MIN1` |
| `UAVCAN_EC_MIN10` |
| `UAVCAN_EC_MIN11` |
| `UAVCAN_EC_MIN12` |
| `UAVCAN_EC_MIN2` |
| `UAVCAN_EC_MIN3` |
| `UAVCAN_EC_MIN4` |
| `UAVCAN_EC_MIN5` |
| `UAVCAN_EC_MIN6` |
| `UAVCAN_EC_MIN7` |
| `UAVCAN_EC_MIN8` |
| `UAVCAN_EC_MIN9` |
| `UAVCAN_EC_REV` |
| `UAVCAN_SV_DIS1` |
| `UAVCAN_SV_DIS2` |
| `UAVCAN_SV_DIS3` |
| `UAVCAN_SV_DIS4` |
| `UAVCAN_SV_DIS5` |
| `UAVCAN_SV_DIS6` |
| `UAVCAN_SV_DIS7` |
| `UAVCAN_SV_DIS8` |
| `UAVCAN_SV_FAIL1` |
| `UAVCAN_SV_FAIL2` |
| `UAVCAN_SV_FAIL3` |
| `UAVCAN_SV_FAIL4` |
| `UAVCAN_SV_FAIL5` |
| `UAVCAN_SV_FAIL6` |
| `UAVCAN_SV_FAIL7` |
| `UAVCAN_SV_FAIL8` |
| `UAVCAN_SV_FUNC1` |
| `UAVCAN_SV_FUNC2` |
| `UAVCAN_SV_FUNC3` |
| `UAVCAN_SV_FUNC4` |
| `UAVCAN_SV_FUNC5` |
| `UAVCAN_SV_FUNC6` |
| `UAVCAN_SV_FUNC7` |
| `UAVCAN_SV_FUNC8` |
| `UAVCAN_SV_MAX1` |
| `UAVCAN_SV_MAX2` |
| `UAVCAN_SV_MAX3` |
| `UAVCAN_SV_MAX4` |
| `UAVCAN_SV_MAX5` |
| `UAVCAN_SV_MAX6` |
| `UAVCAN_SV_MAX7` |
| `UAVCAN_SV_MAX8` |
| `UAVCAN_SV_MIN1` |
| `UAVCAN_SV_MIN2` |
| `UAVCAN_SV_MIN3` |
| `UAVCAN_SV_MIN4` |
| `UAVCAN_SV_MIN5` |
| `UAVCAN_SV_MIN6` |
| `UAVCAN_SV_MIN7` |
| `UAVCAN_SV_MIN8` |
| `UAVCAN_SV_REV` |
| `UCAN1_ACTR_PUB` |
| `UCAN1_BMS_BP_SUB` |
| `UCAN1_BMS_BS_SUB` |
| `UCAN1_BMS_ES_SUB` |
| `UCAN1_ESC0_SUB` |
| `UCAN1_ESC_FAIL1` |
| `UCAN1_ESC_FAIL10` |
| `UCAN1_ESC_FAIL11` |
| `UCAN1_ESC_FAIL12` |
| `UCAN1_ESC_FAIL13` |
| `UCAN1_ESC_FAIL14` |
| `UCAN1_ESC_FAIL15` |
| `UCAN1_ESC_FAIL16` |
| `UCAN1_ESC_FAIL2` |
| `UCAN1_ESC_FAIL3` |
| `UCAN1_ESC_FAIL4` |
| `UCAN1_ESC_FAIL5` |
| `UCAN1_ESC_FAIL6` |
| `UCAN1_ESC_FAIL7` |
| `UCAN1_ESC_FAIL8` |
| `UCAN1_ESC_FAIL9` |
| `UCAN1_ESC_FUNC1` |
| `UCAN1_ESC_FUNC10` |
| `UCAN1_ESC_FUNC11` |
| `UCAN1_ESC_FUNC12` |
| `UCAN1_ESC_FUNC13` |
| `UCAN1_ESC_FUNC14` |
| `UCAN1_ESC_FUNC15` |
| `UCAN1_ESC_FUNC16` |
| `UCAN1_ESC_FUNC2` |
| `UCAN1_ESC_FUNC3` |
| `UCAN1_ESC_FUNC4` |
| `UCAN1_ESC_FUNC5` |
| `UCAN1_ESC_FUNC6` |
| `UCAN1_ESC_FUNC7` |
| `UCAN1_ESC_FUNC8` |
| `UCAN1_ESC_FUNC9` |
| `UCAN1_ESC_MAX1` |
| `UCAN1_ESC_MAX10` |
| `UCAN1_ESC_MAX11` |
| `UCAN1_ESC_MAX12` |
| `UCAN1_ESC_MAX13` |
| `UCAN1_ESC_MAX14` |
| `UCAN1_ESC_MAX15` |
| `UCAN1_ESC_MAX16` |
| `UCAN1_ESC_MAX2` |
| `UCAN1_ESC_MAX3` |
| `UCAN1_ESC_MAX4` |
| `UCAN1_ESC_MAX5` |
| `UCAN1_ESC_MAX6` |
| `UCAN1_ESC_MAX7` |
| `UCAN1_ESC_MAX8` |
| `UCAN1_ESC_MAX9` |
| `UCAN1_ESC_MIN1` |
| `UCAN1_ESC_MIN10` |
| `UCAN1_ESC_MIN11` |
| `UCAN1_ESC_MIN12` |
| `UCAN1_ESC_MIN13` |
| `UCAN1_ESC_MIN14` |
| `UCAN1_ESC_MIN15` |
| `UCAN1_ESC_MIN16` |
| `UCAN1_ESC_MIN2` |
| `UCAN1_ESC_MIN3` |
| `UCAN1_ESC_MIN4` |
| `UCAN1_ESC_MIN5` |
| `UCAN1_ESC_MIN6` |
| `UCAN1_ESC_MIN7` |
| `UCAN1_ESC_MIN8` |
| `UCAN1_ESC_MIN9` |
| `UCAN1_ESC_PUB` |
| `UCAN1_ESC_REV` |
| `UCAN1_FB0_SUB` |
| `UCAN1_FB1_SUB` |
| `UCAN1_FB2_SUB` |
| `UCAN1_FB3_SUB` |
| `UCAN1_FB4_SUB` |
| `UCAN1_FB5_SUB` |
| `UCAN1_FB6_SUB` |
| `UCAN1_FB7_SUB` |
| `UCAN1_GPS0_SUB` |
| `UCAN1_GPS1_SUB` |
| `UCAN1_GPS_PUB` |
| `UCAN1_LG_BMS_SUB` |
| `UCAN1_READ_PUB` |
| `UCAN1_SERVO_PUB` |
| `UCAN1_UORB_GPS` |
| `UCAN1_UORB_GPS_P` |
| `USB_MAV_MODE` |
| `VN_MODE` |
| `VOXL2_IO_FUNC1` |
| `VOXL2_IO_FUNC2` |
| `VOXL2_IO_FUNC3` |
| `VOXL2_IO_FUNC4` |
| `VOXL2_IO_FUNC5` |
| `VOXL2_IO_FUNC6` |
| `VOXL2_IO_FUNC7` |
| `VOXL2_IO_FUNC8` |
| `VOXL2_IO_REV` |
| `VOXLPM_SHUNT_BAT` |
| `VOXLPM_SHUNT_REG` |
| `VOXL_ESC_FUNC1` |
| `VOXL_ESC_FUNC2` |
| `VOXL_ESC_FUNC3` |
| `VOXL_ESC_FUNC4` |
| `VOXL_ESC_REV` |
| `VTQ_IO_DIS0` |
| `VTQ_IO_DIS1` |
| `VTQ_IO_DIS10` |
| `VTQ_IO_DIS11` |
| `VTQ_IO_DIS12` |
| `VTQ_IO_DIS13` |
| `VTQ_IO_DIS14` |
| `VTQ_IO_DIS15` |
| `VTQ_IO_DIS2` |
| `VTQ_IO_DIS3` |
| `VTQ_IO_DIS4` |
| `VTQ_IO_DIS5` |
| `VTQ_IO_DIS6` |
| `VTQ_IO_DIS7` |
| `VTQ_IO_DIS8` |
| `VTQ_IO_DIS9` |
| `VTQ_IO_FAIL0` |
| `VTQ_IO_FAIL1` |
| `VTQ_IO_FAIL10` |
| `VTQ_IO_FAIL11` |
| `VTQ_IO_FAIL12` |
| `VTQ_IO_FAIL13` |
| `VTQ_IO_FAIL14` |
| `VTQ_IO_FAIL15` |
| `VTQ_IO_FAIL2` |
| `VTQ_IO_FAIL3` |
| `VTQ_IO_FAIL4` |
| `VTQ_IO_FAIL5` |
| `VTQ_IO_FAIL6` |
| `VTQ_IO_FAIL7` |
| `VTQ_IO_FAIL8` |
| `VTQ_IO_FAIL9` |
| `VTQ_IO_FUNC0` |
| `VTQ_IO_FUNC1` |
| `VTQ_IO_FUNC10` |
| `VTQ_IO_FUNC11` |
| `VTQ_IO_FUNC12` |
| `VTQ_IO_FUNC13` |
| `VTQ_IO_FUNC14` |
| `VTQ_IO_FUNC15` |
| `VTQ_IO_FUNC2` |
| `VTQ_IO_FUNC3` |
| `VTQ_IO_FUNC4` |
| `VTQ_IO_FUNC5` |
| `VTQ_IO_FUNC6` |
| `VTQ_IO_FUNC7` |
| `VTQ_IO_FUNC8` |
| `VTQ_IO_FUNC9` |
| `VTQ_IO_MAX0` |
| `VTQ_IO_MAX1` |
| `VTQ_IO_MAX10` |
| `VTQ_IO_MAX11` |
| `VTQ_IO_MAX12` |
| `VTQ_IO_MAX13` |
| `VTQ_IO_MAX14` |
| `VTQ_IO_MAX15` |
| `VTQ_IO_MAX2` |
| `VTQ_IO_MAX3` |
| `VTQ_IO_MAX4` |
| `VTQ_IO_MAX5` |
| `VTQ_IO_MAX6` |
| `VTQ_IO_MAX7` |
| `VTQ_IO_MAX8` |
| `VTQ_IO_MAX9` |
| `VTQ_IO_MIN0` |
| `VTQ_IO_MIN1` |
| `VTQ_IO_MIN10` |
| `VTQ_IO_MIN11` |
| `VTQ_IO_MIN12` |
| `VTQ_IO_MIN13` |
| `VTQ_IO_MIN14` |
| `VTQ_IO_MIN15` |
| `VTQ_IO_MIN2` |
| `VTQ_IO_MIN3` |
| `VTQ_IO_MIN4` |
| `VTQ_IO_MIN5` |
| `VTQ_IO_MIN6` |
| `VTQ_IO_MIN7` |
| `VTQ_IO_MIN8` |
| `VTQ_IO_MIN9` |
| `VTQ_IO_REV` |
| `WEIGHT_BASE` |
| `WEIGHT_GROSS` |
| `WV_EN` |
| `WV_ROLL_MIN` |
| `WV_YRATE_MAX` |
