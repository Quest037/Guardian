"""Starts Guardian's minimal Nav2 stack for fleet path planning (subprocess launch)."""

from __future__ import annotations

import os
import subprocess
import threading
import time

from guardian_ros2_vehicle_bridge.json_emit import emit, log_err

_TRAINING_SERVICE_CANDIDATES = (
    "/planner_server/compute_path_to_pose",
    "/compute_path_to_pose",
)

_DEFAULT_READY_TIMEOUT_S = 120.0
_DEFAULT_MAX_START_ATTEMPTS = 3
_DEFAULT_RETRY_DELAY_S = 6.0


def _ready_timeout_s() -> float:
    raw = os.environ.get("GUARDIAN_NAV2_READY_TIMEOUT_S", "").strip()
    if not raw:
        return _DEFAULT_READY_TIMEOUT_S
    try:
        return max(30.0, float(raw))
    except ValueError:
        return _DEFAULT_READY_TIMEOUT_S


def _max_start_attempts() -> int:
    raw = os.environ.get("GUARDIAN_NAV2_MAX_START_ATTEMPTS", "").strip()
    if not raw:
        return _DEFAULT_MAX_START_ATTEMPTS
    try:
        return max(1, int(raw))
    except ValueError:
        return _DEFAULT_MAX_START_ATTEMPTS


def _retry_delay_s() -> float:
    raw = os.environ.get("GUARDIAN_NAV2_RETRY_DELAY_S", "").strip()
    if not raw:
        return _DEFAULT_RETRY_DELAY_S
    try:
        return max(1.0, float(raw))
    except ValueError:
        return _DEFAULT_RETRY_DELAY_S


class Nav2TrainingStack:
    """Singleton subprocess hosting map_server + planner_server for Guardian fleet planning."""

    _instance: Nav2TrainingStack | None = None
    _lock = threading.Lock()

    def __init__(self) -> None:
        self._proc: subprocess.Popen[bytes] | None = None
        self._desired_active = False
        self._ready = False
        self._starting = False
        self._state_lock = threading.Lock()
        self._worker_thread: threading.Thread | None = None

    @classmethod
    def shared(cls) -> Nav2TrainingStack:
        with cls._lock:
            if cls._instance is None:
                cls._instance = Nav2TrainingStack()
            return cls._instance

    @property
    def is_ready(self) -> bool:
        with self._state_lock:
            return self._ready

    def ensure_running_async(self) -> None:
        """Start Nav2 in a background thread (never blocks the bridge main loop)."""
        with self._state_lock:
            self._desired_active = True
            if self._ready:
                return
            if self._starting:
                return
            self._starting = True
        if os.environ.get("GUARDIAN_NAV2_LAUNCH_DISABLED") == "1":
            thread = threading.Thread(target=self._poll_only_worker, name="guardian-nav2-poll", daemon=True)
        else:
            thread = threading.Thread(target=self._start_worker, name="guardian-nav2-training", daemon=True)
        self._worker_thread = thread
        thread.start()

    def _poll_only_worker(self) -> None:
        """Swift owns ``ros2 launch``; bridge only mirrors readiness on stdout."""
        try:
            if _compute_path_service_available(env=os.environ.copy()):
                with self._state_lock:
                    self._ready = True
                emit({"type": "ros2_nav2_training_stack", "status": "ready"})
                return
            # Swift ``FleetNav2StackRunner`` owns operator-facing "starting" / timeout — do not emit "starting" here.
            deadline = time.monotonic() + _ready_timeout_s()
            while time.monotonic() < deadline:
                with self._state_lock:
                    if not self._desired_active:
                        return
                if _compute_path_service_available(env=os.environ.copy()):
                    with self._state_lock:
                        self._ready = True
                    emit({"type": "ros2_nav2_training_stack", "status": "ready"})
                    return
                time.sleep(0.4)
            emit(
                {
                    "type": "ros2_nav2_training_stack",
                    "status": "timeout",
                    "message": "compute_path_to_pose_unavailable",
                }
            )
        finally:
            with self._state_lock:
                self._starting = False

    def set_desired_active(self, active: bool) -> None:
        """Retain API for tests; production defers launch to ``ensure_running_async``."""
        if active:
            self.ensure_running_async()
        else:
            self.force_stop()

    def force_stop(self) -> None:
        with self._state_lock:
            self._desired_active = False
            self._starting = False
        self._stop()

    def health_snapshot(self) -> dict[str, object]:
        with self._state_lock:
            starting = self._starting
            ready = self._ready
        running = self._proc is not None and self._proc.poll() is None
        return {
            "training_stack": "nav2_minimal",
            "running": running,
            "starting": starting,
            "ready": ready,
            "service": _TRAINING_SERVICE_CANDIDATES[0] if ready else None,
        }

    def _start_worker(self) -> None:
        try:
            attempt = 0
            while True:
                with self._state_lock:
                    if not self._desired_active:
                        return
                attempt += 1
                if attempt > 1:
                    emit(
                        {
                            "type": "ros2_nav2_training_stack",
                            "status": "restarting",
                            "message": f"attempt_{attempt}",
                        }
                    )
                permanent = self._start_once()
                with self._state_lock:
                    if self._ready:
                        return
                    if not self._desired_active:
                        return
                if permanent:
                    return
                if attempt >= _max_start_attempts():
                    return
                delay = _retry_delay_s()
                log_err(f"nav2 training: retrying in {delay:.0f}s (attempt {attempt}/{_max_start_attempts()})")
                time.sleep(delay)
        finally:
            with self._state_lock:
                self._starting = False

    def _start_once(self) -> bool:
        """Launch stack once. Returns True when failure is permanent (no in-app retry)."""
        env = os.environ.copy()
        if _compute_path_service_available(env=env):
            with self._state_lock:
                self._ready = True
            emit({"type": "ros2_nav2_training_stack", "status": "ready"})
            return False

        if not _nav2_launch_available():
            log_err("nav2 training: nav2_planner not in ROS environment")
            emit(
                {
                    "type": "ros2_nav2_training_stack",
                    "status": "unavailable",
                    "message": "nav2_packages_missing",
                }
            )
            return True

        cmd = [
            "ros2",
            "launch",
            "guardian_ros2_vehicle_bridge",
            "nav2_training.launch.py",
        ]
        try:
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                env=env,
            )
        except OSError as exc:
            log_err(f"nav2 training launch failed: {exc}")
            emit(
                {
                    "type": "ros2_nav2_training_stack",
                    "status": "error",
                    "message": str(exc),
                }
            )
            return False

        with self._state_lock:
            self._proc = proc
            self._ready = False

        emit({"type": "ros2_nav2_training_stack", "status": "starting"})
        ready = _wait_for_compute_path_service(env=env, timeout_s=_ready_timeout_s())
        with self._state_lock:
            self._ready = ready
            if self._proc and self._proc.poll() is not None:
                self._ready = False

        if ready:
            emit({"type": "ros2_nav2_training_stack", "status": "ready"})
            return False

        err_tail = ""
        if self._proc and self._proc.stderr:
            try:
                err_tail = self._proc.stderr.read(4096).decode("utf-8", errors="ignore")
            except OSError:
                pass
        log_err(f"nav2 training stack not ready within timeout. stderr={err_tail[:500]}")
        emit(
            {
                "type": "ros2_nav2_training_stack",
                "status": "timeout",
                "message": "compute_path_to_pose_unavailable",
            }
        )
        self._stop()
        return False

    def _stop(self) -> None:
        with self._state_lock:
            proc = self._proc
            self._proc = None
            self._ready = False
        if proc is None:
            return
        proc.terminate()
        try:
            proc.wait(timeout=8.0)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3.0)
        emit({"type": "ros2_nav2_training_stack", "status": "stopped"})


def _nav2_launch_available() -> bool:
    try:
        probe = subprocess.run(
            ["ros2", "pkg", "prefix", "nav2_planner"],
            capture_output=True,
            timeout=15.0,
            env=os.environ.copy(),
        )
        return probe.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def _wait_for_compute_path_service(*, env: dict[str, str], timeout_s: float) -> bool:
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if _compute_path_service_available(env=env):
            return True
        time.sleep(0.4)
    return False


def _compute_path_service_available(*, env: dict[str, str]) -> bool:
    try:
        result = subprocess.run(
            ["ros2", "service", "list"],
            capture_output=True,
            text=True,
            timeout=8.0,
            env=env,
        )
        if result.returncode != 0:
            return False
        lines = {line.strip() for line in result.stdout.splitlines()}
        return any(c in lines for c in _TRAINING_SERVICE_CANDIDATES)
    except (OSError, subprocess.TimeoutExpired):
        return False


def training_plan_namespace(_vehicle_namespace: str) -> str:
    """Training overlay uses one global open-field stack (not per-vehicle PX4 namespaces)."""
    return ""
