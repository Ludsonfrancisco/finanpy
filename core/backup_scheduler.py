from dataclasses import dataclass
from datetime import UTC, datetime, time, timedelta
from zoneinfo import ZoneInfo


@dataclass(frozen=True)
class LastAttempt:
    at: datetime
    succeeded: bool


@dataclass(frozen=True)
class SchedulerDecision:
    run_now: bool
    sleep_seconds: float


def decide_next_action(
    now: datetime,
    schedule_time: time,
    time_zone: ZoneInfo,
    retry_seconds: int,
    last_attempt: LastAttempt | None,
) -> SchedulerDecision:
    _require_aware(now)
    local_now = now.astimezone(time_zone)
    scheduled_today = _scheduled_at(local_now.date(), schedule_time, time_zone)
    now_instant = local_now.astimezone(UTC)

    if last_attempt is not None:
        _require_aware(last_attempt.at)
        local_attempt = last_attempt.at.astimezone(time_zone)
        if local_attempt.date() == local_now.date():
            if last_attempt.succeeded:
                next_schedule = _scheduled_at(
                    local_now.date() + timedelta(days=1),
                    schedule_time,
                    time_zone,
                )
                return _sleep_until(local_now, next_schedule)

            retry_at = (
                last_attempt.at.astimezone(UTC) + timedelta(seconds=retry_seconds)
            )
            if now_instant < retry_at:
                return _sleep_until(local_now, retry_at.astimezone(time_zone))

    if now_instant < scheduled_today.astimezone(UTC):
        return _sleep_until(local_now, scheduled_today)
    return SchedulerDecision(run_now=True, sleep_seconds=0)


def _scheduled_at(schedule_date, schedule_time: time, time_zone: ZoneInfo) -> datetime:
    scheduled = datetime.combine(schedule_date, schedule_time, tzinfo=time_zone)
    normalized = scheduled.astimezone(UTC).astimezone(time_zone)
    if normalized.date() != schedule_date or normalized.time() != schedule_time:
        return normalized
    return scheduled


def _sleep_until(now: datetime, wake_at: datetime) -> SchedulerDecision:
    return SchedulerDecision(
        run_now=False,
        sleep_seconds=max(
            0,
            (wake_at.astimezone(UTC) - now.astimezone(UTC)).total_seconds(),
        ),
    )


def _require_aware(value: datetime) -> None:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError('Scheduler datetimes must be timezone-aware.')
