"""
Supervisor live location, shared with admins during working hours only.

    POST /api/location/update/                 supervisor: report current position
    POST /api/location/status/                 supervisor: sharing on/off (GPS off, permission removed, logged out)
    GET  /api/admin/supervisor-locations/      admin: every supervisor + last position + sharing state

Only the latest position per supervisor is stored (no history). Updates sent
outside working hours are refused and nothing is stored, so the working-hours
promise made to supervisors holds even if a phone misbehaves.

Sharing is mandatory during working hours; supervisors can't switch it off in
the app, and admins get a push notification when a phone reports it stopped.

Tables: supervisor_locations (migrations/supervisor_locations.sql),
supervisor_location_status (migrations/supervisor_location_status.sql)
"""
import threading
from datetime import datetime, timedelta

import pytz
from django.views.decorators.csrf import csrf_exempt
from rest_framework import status
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .authentication import JWTAuthentication
from .database import get_db_connection
from .fcm_service import send_push_to_admins

ADMIN_ROLE_ID = 1
SUPERVISOR_ROLE_ID = 2

# Keep in sync with otp_phone_auth/lib/services/location_tracking_service.dart
IST = pytz.timezone('Asia/Kolkata')
WORK_DAYS = {0, 1, 2, 3, 4, 5}      # Monday–Saturday
WORK_START_HOUR = 8                 # 08:00
WORK_END_HOUR = 19                  # 19:00

# A position older than this is shown to the admin as "last seen", not live
LIVE_WINDOW = timedelta(minutes=15)


def is_working_hours(when: datetime) -> bool:
    local = when.astimezone(IST)
    return local.weekday() in WORK_DAYS and WORK_START_HOUR <= local.hour < WORK_END_HOUR


def _role_id(cursor, user_id):
    cursor.execute('SELECT role_id FROM users WHERE id = %s', (user_id,))
    row = cursor.fetchone()
    return row[0] if row else None


# Phone-reported sharing states (supervisor_location_status.state)
STATE_OK = 'ok'
OFF_STATES = {
    'gps_off': 'turned off GPS',
    'permission_denied': 'removed the location permission',
    'logged_out': 'logged out of the app',
}


def _set_state(cursor, user_id, state):
    """Record the sharing state. Returns the previous state (None if never set)."""
    cursor.execute('SELECT state FROM supervisor_location_status WHERE user_id = %s', (user_id,))
    row = cursor.fetchone()
    previous = row[0] if row else None
    if previous != state:
        cursor.execute("""
            INSERT INTO supervisor_location_status (user_id, state, changed_at)
            VALUES (%s, %s, NOW())
            ON CONFLICT (user_id) DO UPDATE SET state = EXCLUDED.state, changed_at = NOW()
        """, (user_id, state))
    return previous


def _notify_admins_of_change(cursor, user_id, previous, state):
    """Push to admins when sharing stops, or resumes after having stopped."""
    if previous == state:
        return
    cursor.execute('SELECT COALESCE(full_name, username) FROM users WHERE id = %s', (user_id,))
    row = cursor.fetchone()
    name = row[0] if row else 'A supervisor'
    if state in OFF_STATES:
        title = '⚠️ Supervisor location off'
        body = f'{name} {OFF_STATES[state]} during work hours.'
    elif state == STATE_OK and previous in OFF_STATES:
        title = '✅ Supervisor location back on'
        body = f'{name} is sharing their location again.'
    else:
        return
    # FCM can take 10+ s; don't make the phone wait for it
    threading.Thread(
        target=send_push_to_admins,
        kwargs=dict(title=title, body=body,
                    data={'type': 'supervisor_location', 'user_id': str(user_id), 'state': state}),
        daemon=True,
    ).start()


@csrf_exempt
@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def update_location(request):
    """
    Body: { "latitude": 13.08, "longitude": 80.27, "accuracy": 12.5,
            "recorded_at": "2026-10-26T10:15:00+05:30" }
    """
    now = datetime.now(pytz.UTC)
    if not is_working_hours(now):
        return Response({'stored': False, 'reason': 'outside_working_hours'},
                        status=status.HTTP_200_OK)

    try:
        latitude = float(request.data.get('latitude'))
        longitude = float(request.data.get('longitude'))
    except (TypeError, ValueError):
        return Response({'error': 'latitude and longitude are required numbers'},
                        status=status.HTTP_400_BAD_REQUEST)
    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        return Response({'error': 'latitude/longitude out of range'},
                        status=status.HTTP_400_BAD_REQUEST)

    accuracy = request.data.get('accuracy')
    try:
        accuracy = float(accuracy) if accuracy is not None else None
    except (TypeError, ValueError):
        accuracy = None

    recorded_at = now
    raw_time = request.data.get('recorded_at')
    if raw_time:
        try:
            parsed = datetime.fromisoformat(str(raw_time).replace('Z', '+00:00'))
            if parsed.tzinfo is None:
                parsed = pytz.UTC.localize(parsed)
            # Ignore clocks set in the future; keep old fixes only if within working hours
            if parsed <= now + timedelta(minutes=2) and is_working_hours(parsed):
                recorded_at = parsed
        except ValueError:
            pass

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        user_id = request.user.get('user_id')
        if _role_id(cursor, user_id) != SUPERVISOR_ROLE_ID:
            return Response({'error': 'Only supervisors share location'},
                            status=status.HTTP_403_FORBIDDEN)

        # Never overwrite a newer fix with an older one (offline queue, retries)
        cursor.execute("""
            INSERT INTO supervisor_locations
                (user_id, latitude, longitude, accuracy_m, recorded_at, updated_at)
            VALUES (%s, %s, %s, %s, %s, NOW())
            ON CONFLICT (user_id) DO UPDATE SET
                latitude = EXCLUDED.latitude,
                longitude = EXCLUDED.longitude,
                accuracy_m = EXCLUDED.accuracy_m,
                recorded_at = EXCLUDED.recorded_at,
                updated_at = NOW()
            WHERE supervisor_locations.recorded_at <= EXCLUDED.recorded_at
        """, (user_id, latitude, longitude, accuracy, recorded_at))
        previous = _set_state(cursor, user_id, STATE_OK)  # a fix proves sharing works
        conn.commit()
        _notify_admins_of_change(cursor, user_id, previous, STATE_OK)
        return Response({'stored': True})
    except Exception as e:
        print(f'Error storing supervisor location: {e}')
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
    finally:
        if conn:
            conn.close()


@csrf_exempt
@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def report_sharing_status(request):
    """
    Supervisor's phone reports that sharing stopped or works again.
    Body: { "state": "gps_off" | "permission_denied" | "logged_out" | "ok" }
    Ignored outside working hours (sharing is meant to be off then).
    """
    state = str(request.data.get('state') or '').strip()
    if state != STATE_OK and state not in OFF_STATES:
        return Response({'error': f'state must be one of: ok, {", ".join(OFF_STATES)}'},
                        status=status.HTTP_400_BAD_REQUEST)
    if not is_working_hours(datetime.now(pytz.UTC)):
        return Response({'stored': False, 'reason': 'outside_working_hours'})

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        user_id = request.user.get('user_id')
        if _role_id(cursor, user_id) != SUPERVISOR_ROLE_ID:
            return Response({'error': 'Only supervisors share location'},
                            status=status.HTTP_403_FORBIDDEN)
        previous = _set_state(cursor, user_id, state)
        conn.commit()
        _notify_admins_of_change(cursor, user_id, previous, state)
        return Response({'stored': True})
    except Exception as e:
        print(f'Error storing sharing status: {e}')
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
    finally:
        if conn:
            conn.close()


@csrf_exempt
@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def admin_supervisor_locations(request):
    """Every active supervisor with their latest position (or none)."""
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        if _role_id(cursor, request.user.get('user_id')) != ADMIN_ROLE_ID:
            return Response({'error': 'Unauthorized. Admin access required.'},
                            status=status.HTTP_403_FORBIDDEN)

        cursor.execute("""
            SELECT u.id, u.full_name, u.username, u.phone,
                   l.latitude, l.longitude, l.accuracy_m, l.recorded_at,
                   s.state, s.changed_at
            FROM users u
            LEFT JOIN supervisor_locations l ON l.user_id = u.id
            LEFT JOIN supervisor_location_status s ON s.user_id = u.id
            WHERE u.role_id = %s AND COALESCE(u.is_active, TRUE)
            ORDER BY l.recorded_at DESC NULLS LAST, u.full_name
        """, (SUPERVISOR_ROLE_ID,))
        now = datetime.now(pytz.UTC)
        supervisors = []
        for (uid, full_name, username, phone, lat, lng, acc, recorded_at,
             sharing_state, changed_at) in cursor.fetchall():
            # Phone said sharing stopped, after its last fix
            turned_off = (sharing_state in OFF_STATES and changed_at is not None
                          and (recorded_at is None or changed_at >= recorded_at))
            if turned_off:
                state = 'off'
            elif recorded_at is None:
                state = 'none'
            elif now - recorded_at <= LIVE_WINDOW:
                state = 'live'
            else:
                state = 'stale'
            supervisors.append({
                'user_id': str(uid),
                'name': full_name or username,
                'phone': phone,
                'latitude': lat,
                'longitude': lng,
                'accuracy_m': acc,
                'recorded_at': recorded_at.isoformat() if recorded_at else None,
                'status': state,
                'off_reason': OFF_STATES[sharing_state] if turned_off else None,
                'off_since': changed_at.isoformat() if turned_off else None,
            })

        return Response({
            'success': True,
            'supervisors': supervisors,
            'working_hours_now': is_working_hours(now),
            'working_hours': f'Mon–Sat {WORK_START_HOUR:02d}:00–{WORK_END_HOUR:02d}:00 IST',
            'live_window_minutes': int(LIVE_WINDOW.total_seconds() // 60),
        })
    except Exception as e:
        print(f'Error listing supervisor locations: {e}')
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
    finally:
        if conn:
            conn.close()
