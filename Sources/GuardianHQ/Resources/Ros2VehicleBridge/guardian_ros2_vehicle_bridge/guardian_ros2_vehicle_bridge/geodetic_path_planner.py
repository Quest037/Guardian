"""Geodesic path sampling for Training map preview (Nav2 fallback / milestone)."""

from __future__ import annotations

import math
from typing import Any


def _interpolate_angle_deg(from_deg: float, to_deg: float, fraction: float) -> float:
    delta = ((to_deg - from_deg + 540.0) % 360.0) - 180.0
    return (from_deg + delta * fraction) % 360.0


def plan_geodetic_path(
    start_lat: float,
    start_lon: float,
    start_heading_deg: float,
    goal_lat: float,
    goal_lon: float,
    goal_heading_deg: float,
    *,
    step_m: float = 2.0,
) -> list[dict[str, float]]:
    """
  Sample a straight-line ground path from start to goal in WGS84.

  Used when Nav2 is not running; sufficient for Training Leaflet overlay milestone.
  """
    step_m = max(0.5, step_m)
    # Flat-earth distance for step count (adequate at training-field scale).
    r = 6_378_137.0
    dlat = math.radians(goal_lat - start_lat)
    dlon = math.radians(goal_lon - start_lon)
    north_m = dlat * r
    east_m = dlon * r * math.cos(math.radians((start_lat + goal_lat) * 0.5))
    dist_m = math.hypot(north_m, east_m)
    steps = max(1, int(math.ceil(dist_m / step_m)))
    points: list[dict[str, float]] = []
    for i in range(steps + 1):
        frac = i / steps
        lat = start_lat + (goal_lat - start_lat) * frac
        lon = start_lon + (goal_lon - start_lon) * frac
        hdg = _interpolate_angle_deg(start_heading_deg, goal_heading_deg, frac)
        points.append(
            {
                "lat": lat,
                "lon": lon,
                "heading_deg": hdg,
            }
        )
    return points


def path_to_route_coordinates(path: list[dict[str, Any]]) -> list[dict[str, float]]:
    """Normalize to {lat, lon} only for Guardian map polylines."""
    out: list[dict[str, float]] = []
    for pt in path:
        out.append({"lat": float(pt["lat"]), "lon": float(pt["lon"])})
    return out
