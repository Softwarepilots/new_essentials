from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.response import Response
from rest_framework import status
import json
import threading
from datetime import datetime
from .database import get_db_connection
from .authentication import JWTAuthentication
from .fcm_service import send_push_to_admins
import uuid


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _is_admin(cursor, user_id: str) -> bool:
    cursor.execute("SELECT role_id FROM users WHERE id = %s", (user_id,))
    row = cursor.fetchone()
    return bool(row and row[0] == 1)


# ---------------------------------------------------------------------------
# 1. Late-entry notification (supervisor / site-engineer → admin)
#    Existing endpoint — now also fires an FCM push.
# ---------------------------------------------------------------------------

@csrf_exempt
@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def create_late_entry_notification(request):
    """Create a DB notification for a late entry and push it to admin devices."""
    try:
        data = request.data if hasattr(request, 'data') else json.loads(request.body)
        site_id    = data.get('site_id')
        entry_type = data.get('entry_type')
        message    = data.get('message')
        actual_time = data.get('actual_time')

        if not all([site_id, entry_type, message, actual_time]):
            return Response({'error': 'Missing required fields'},
                            status=status.HTTP_400_BAD_REQUEST)

        supervisor_id = request.user.get('user_id')

        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("SELECT full_name FROM users WHERE id = %s", (supervisor_id,))
        row = cursor.fetchone()
        supervisor_name = row[0] if row else 'Unknown'

        cursor.execute("SELECT site_name FROM sites WHERE id = %s", (site_id,))
        row = cursor.fetchone()
        site_name = row[0] if row else 'Unknown Site'

        notification_id = str(uuid.uuid4())
        cursor.execute("""
            INSERT INTO notifications (
                id, site_id, entry_type, message, actual_time,
                supervisor_id, supervisor_name, site_name
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id, created_at
        """, (
            notification_id, site_id, entry_type, message, actual_time,
            supervisor_id, supervisor_name, site_name,
        ))
        result = cursor.fetchone()
        conn.commit()

        cursor.execute("SELECT id FROM users WHERE role_id = 1")
        admin_ids = [str(r[0]) for r in cursor.fetchall()]

        cursor.close()
        conn.close()

        # ── FCM push to all admin devices ──────────────────────────────────
        entry_label = {
            'labour':        'Labour Entry',
            'material':      'Material Update',
            'morning_photo': 'Morning Photo',
            'evening_photo': 'Evening Photo',
        }.get(entry_type, entry_type.replace('_', ' ').title())

        send_push_to_admins(
            title=f'📋 {entry_label} — {site_name}',
            body=f'{supervisor_name}: {message}',
            data={'type': entry_type, 'site_id': str(site_id),
                  'notification_id': notification_id},
        )

        return Response({
            'success': True,
            'notification_id': str(result[0]),
            'created_at': result[1].isoformat(),
            'sent_to': admin_ids,
        }, status=status.HTTP_201_CREATED)

    except Exception as e:
        print(f'Error creating notification: {e}')
        return Response({'error': str(e)},
                        status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ---------------------------------------------------------------------------
# 2. Register device FCM token (admin only)
# ---------------------------------------------------------------------------

@csrf_exempt
@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def register_device_token(request):
    """
    Save or update an FCM device token for the authenticated user.
    Called by the Flutter app (admin dashboard) on every launch.

    Body: { "fcm_token": "...", "platform": "android" | "ios" }
    """
    try:
        data = request.data if hasattr(request, 'data') else json.loads(request.body)
        fcm_token = (data.get('fcm_token') or '').strip()
        platform  = (data.get('platform') or 'android').strip()

        if not fcm_token:
            return Response({'error': 'fcm_token is required'},
                            status=status.HTTP_400_BAD_REQUEST)

        user_id = request.user.get('user_id')

        conn = get_db_connection()
        cursor = conn.cursor()

        # Upsert — one row per (user_id, fcm_token); update timestamp on conflict
        cursor.execute("""
            INSERT INTO device_tokens (user_id, fcm_token, platform)
            VALUES (%s, %s, %s)
            ON CONFLICT (user_id, fcm_token)
            DO UPDATE SET platform    = EXCLUDED.platform,
                          updated_at  = NOW()
            RETURNING id
        """, (user_id, fcm_token, platform))

        token_id = cursor.fetchone()[0]
        conn.commit()
        cursor.close()
        conn.close()

        return Response({'success': True, 'token_id': str(token_id)},
                        status=status.HTTP_200_OK)

    except Exception as e:
        print(f'Error registering device token: {e}')
        return Response({'error': str(e)},
                        status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ---------------------------------------------------------------------------
# 3. Guest check-in push (public — no auth)
# ---------------------------------------------------------------------------

@csrf_exempt
@api_view(['POST'])
@authentication_classes([])
@permission_classes([AllowAny])
def guest_checkin_notification(request):
    """
    Called by the guest registration screen after a visitor checks in.
    Saves the check-in to the database and pushes a notification to all
    registered admin devices.

    Body: { "guest_name": "...", "guest_phone": "...", "ref": "..." }
    No authentication required — guests are not logged in.
    """
    try:
        data = request.data if hasattr(request, 'data') else json.loads(request.body)
        guest_name  = (data.get('guest_name') or '').strip()
        guest_phone = (data.get('guest_phone') or '').strip()
        ref         = (data.get('ref') or '').strip()
        purpose     = (data.get('purpose') or '').strip() or None

        if not guest_name or not guest_phone:
            return Response({'error': 'guest_name and guest_phone are required'},
                            status=status.HTTP_400_BAD_REQUEST)

        # Persist to guest_checkins table
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            INSERT INTO guest_checkins (guest_name, guest_phone, ref, purpose)
            VALUES (%s, %s, %s, %s)
            RETURNING id, checkin_time
        """, (guest_name, guest_phone, ref or f'GV{uuid.uuid4().hex[:4].upper()}', purpose))

        row = cursor.fetchone()
        conn.commit()
        cursor.close()
        conn.close()

        # ── FCM push to all admin devices ──────────────────────────────────
        # In a background thread: the check-in is already saved, and an FCM
        # round trip (plus stale-token cleanup) can take 10–30 s, which made
        # the guest app time out.
        threading.Thread(
            target=send_push_to_admins,
            kwargs=dict(
                title='🔔 New Guest Check-In',
                body=f'{guest_name} ({guest_phone}) just checked in — Ref: {ref}',
                data={'type': 'guest_checkin', 'guest_name': guest_name,
                      'guest_phone': guest_phone, 'ref': ref},
            ),
            daemon=True,
        ).start()

        return Response({
            'success': True,
            'checkin_id': str(row[0]),
            'checkin_time': row[1].isoformat(),
        }, status=status.HTTP_201_CREATED)

    except Exception as e:
        print(f'Error processing guest checkin: {e}')
        return Response({'error': str(e)},
                        status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ---------------------------------------------------------------------------
# 4. Get guest checkins (admin only)
# ---------------------------------------------------------------------------

@csrf_exempt
@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_guest_checkins(request):
    """Return recent guest checkins for the admin dashboard."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        user_id = request.user.get('user_id')
        if not _is_admin(cursor, user_id):
            cursor.close()
            conn.close()
            return Response({'error': 'Unauthorized. Admin access required.'},
                            status=status.HTTP_403_FORBIDDEN)

        limit  = int(request.GET.get('limit', 100))
        offset = int(request.GET.get('offset', 0))

        cursor.execute("""
            SELECT id, guest_name, guest_phone, ref, purpose, checkin_time
            FROM guest_checkins
            ORDER BY checkin_time DESC
            LIMIT %s OFFSET %s
        """, (limit, offset))
        rows = cursor.fetchall()

        cursor.execute("SELECT COUNT(*) FROM guest_checkins")
        total = cursor.fetchone()[0]

        cursor.close()
        conn.close()

        checkins = [
            {
                'id':           str(r[0]),
                'guest_name':   r[1],
                'guest_phone':  r[2],
                'ref':          r[3],
                'purpose':      r[4],
                'checkin_time': r[5].isoformat() if r[5] else None,
            }
            for r in rows
        ]

        return Response({'success': True, 'checkins': checkins, 'total': total})

    except Exception as e:
        print(f'Error fetching guest checkins: {e}')
        return Response({'error': str(e)},
                        status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ---------------------------------------------------------------------------
# 5. Get notifications (admin only)
# ---------------------------------------------------------------------------

@csrf_exempt
@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_notifications(request):
    """Get all notifications for admin."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        user_id = request.user.get('user_id')
        if not _is_admin(cursor, user_id):
            cursor.close()
            conn.close()
            return Response({'error': 'Unauthorized. Admin access required.'},
                            status=status.HTTP_403_FORBIDDEN)

        is_read = request.GET.get('is_read')
        limit   = int(request.GET.get('limit', 50))
        offset  = int(request.GET.get('offset', 0))

        query = """
            SELECT
                n.id, n.site_id, n.entry_type, n.message, n.actual_time,
                n.created_at, n.is_read, n.read_at,
                n.supervisor_id, n.supervisor_name, n.site_name
            FROM notifications n
            WHERE 1=1
        """
        params = []

        if is_read is not None:
            query += " AND n.is_read = %s"
            params.append(is_read == 'true')

        query += " ORDER BY n.created_at DESC LIMIT %s OFFSET %s"
        params.extend([limit, offset])

        cursor.execute(query, params)
        notifications = cursor.fetchall()

        count_query  = "SELECT COUNT(*) FROM notifications WHERE 1=1"
        count_params = []
        if is_read is not None:
            count_query  += " AND is_read = %s"
            count_params.append(is_read == 'true')

        cursor.execute(count_query, count_params)
        total_count = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM notifications WHERE is_read = FALSE")
        unread_count = cursor.fetchone()[0]

        cursor.close()
        conn.close()

        notifications_list = [
            {
                'id':              str(n[0]),
                'site_id':         str(n[1]),
                'entry_type':      n[2],
                'message':         n[3],
                'actual_time':     n[4].isoformat() if n[4] else None,
                'created_at':      n[5].isoformat() if n[5] else None,
                'is_read':         n[6],
                'read_at':         n[7].isoformat() if n[7] else None,
                'supervisor_id':   str(n[8]) if n[8] else None,
                'supervisor_name': n[9],
                'site_name':       n[10],
            }
            for n in notifications
        ]

        return Response({
            'success':      True,
            'notifications': notifications_list,
            'total':         total_count,
            'unread_count':  unread_count,
        })

    except Exception as e:
        print(f'Error fetching notifications: {e}')
        return Response({'error': str(e)},
                        status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ---------------------------------------------------------------------------
# 5. Mark one notification as read
# ---------------------------------------------------------------------------

@csrf_exempt
@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def mark_notification_read(request, notification_id):
    """Mark a single notification as read."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        user_id = request.user.get('user_id')
        if not _is_admin(cursor, user_id):
            cursor.close()
            conn.close()
            return Response({'error': 'Unauthorized. Admin access required.'},
                            status=status.HTTP_403_FORBIDDEN)

        cursor.execute("""
            UPDATE notifications
            SET is_read = TRUE, read_at = CURRENT_TIMESTAMP
            WHERE id = %s
            RETURNING id
        """, (notification_id,))

        result = cursor.fetchone()
        conn.commit()
        cursor.close()
        conn.close()

        if not result:
            return Response({'error': 'Notification not found'},
                            status=status.HTTP_404_NOT_FOUND)

        return Response({'success': True, 'message': 'Notification marked as read'})

    except Exception as e:
        print(f'Error marking notification as read: {e}')
        return Response({'error': str(e)},
                        status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ---------------------------------------------------------------------------
# 6. Mark all notifications as read
# ---------------------------------------------------------------------------

@csrf_exempt
@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def mark_all_notifications_read(request):
    """Mark every unread notification as read."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        user_id = request.user.get('user_id')
        if not _is_admin(cursor, user_id):
            cursor.close()
            conn.close()
            return Response({'error': 'Unauthorized. Admin access required.'},
                            status=status.HTTP_403_FORBIDDEN)

        cursor.execute("""
            UPDATE notifications
            SET is_read = TRUE, read_at = CURRENT_TIMESTAMP
            WHERE is_read = FALSE
        """)

        updated_count = cursor.rowcount
        conn.commit()
        cursor.close()
        conn.close()

        return Response({
            'success': True,
            'message': f'{updated_count} notifications marked as read',
        })

    except Exception as e:
        print(f'Error marking all notifications as read: {e}')
        return Response({'error': str(e)},
                        status=status.HTTP_500_INTERNAL_SERVER_ERROR)
