from guardian.views import (
    calibrate,
    devices,
    mission_contingencies,
    mission_create,
    mission_edit,
    mission_end,
    mission_live,
    mission_plan,
    overview,
    position,
)

PAGES = {
    "overview": overview,
    "devices": devices,
    "calibrate": calibrate,
    "position": position,
    "mission_create": mission_create,
    "mission_edit": mission_edit,
    "mission_plan": mission_plan,
    "mission_contingencies": mission_contingencies,
    "mission_live": mission_live,
    "mission_end": mission_end,
}
