"""
Walkie-talkie: short push-to-talk voice messages between admins and staff.

    GET  /api/walkie/messages/              latest messages the user can hear + unheard count
    POST /api/walkie/messages/              send one (multipart: 'audio' file, 'duration_ms')
    POST /api/walkie/messages/<id>/heard/   mark a message as listened to

An admin's message goes to all staff (supervisors, site engineers,
accountants, architects); other admins see it too. A staff member's message
is a reply to the admins only, so staff never hear each other.

Recipients get a push notification; the app plays the message straight away
when it's open.

Tables: walkie_messages, walkie_message_heard (migrations/walkie_talkie.sql)
"""
import os
import threading
import uuid

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.views.decorators.csrf import csrf_exempt
from rest_framework import status
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .authentication import JWTAuthentication
from .database import get_db_connection
from .fcm_service import send_push_to_tokens

ADMIN_ROLE_ID = 1
# Supervisor, Site Engineer, Accountant, Architect
STAFF_ROLE_IDS = (2, 3, 4, 5)

AUDIENCE_ALL_STAFF = 'all_staff'
AUDIENCE_ADMINS = 'admins'

_ALLOWED_AUDIO_EXTS = {'.m4a', '.aac', '.mp4', '.wav', '.webm', '.ogg', '.mp3'}
_MAX_AUDIO_BYTES = 5 * 1024 * 1024
MAX_DURATION_MS = 60_000
_HISTORY_LIMIT = 50


def _sender_info(cursor, user_id):
    """(role_id, display name) of a user, or (None, None) if unknown."""
    cursor.execute(
        'SELECT role_id, COALESCE(NULLIF(full_name, \'\'), username) FROM users WHERE id = %s',
        (user_id,),
    )
    row = cursor.fetchone()
    return (row[0], row[1]) if row else (None, None)


def _can_use(role_id) -> bool:
    return role_id == ADMIN_ROLE_ID or role_id in STAFF_ROLE_IDS


def _format_duration(ms: int) -> str:
    seconds = max(1, round(ms / 1000))
    return f'{seconds // 60}:{seconds % 60:02d}'


def _audience_sizes(cursor) -> dict:
    """How many people each audience reaches, for 'heard by N of M'."""
    cursor.execute("""
        SELECT
            COUNT(*) FILTER (WHERE role_id = ANY(%s)),
            COUNT(*) FILTER (WHERE role_id = %s)
        FROM users
        WHERE is_active IS NOT FALSE
    """, (list(STAFF_ROLE_IDS), ADMIN_ROLE_ID))
    staff, admins = cursor.fetchone()
    return {AUDIENCE_ALL_STAFF: staff, AUDIENCE_ADMINS: admins}


def _serialize(request, row, user_id, audience_sizes) -> dict:
    (msg_id, sender_id, audience, audio_url, duration_ms, created_at,
     sender_name, sender_role_id, sender_role, heard_by_me, heard_count) = row
    is_mine = str(sender_id) == str(user_id)
    message = {
        'id': str(msg_id),
        'sender_id': str(sender_id),
        'sender_name': sender_name or 'Unknown',
        'sender_role': sender_role or '',
        'from_admin': sender_role_id == ADMIN_ROLE_ID,
        'is_mine': is_mine,
        'audience': audience,
        'audio_url': request.build_absolute_uri(audio_url),
        'duration_ms': duration_ms,
        'created_at': created_at.isoformat(),
        'heard': is_mine or heard_by_me,
    }
    if is_mine:
        size = audience_sizes.get(audience, 0)
        if audience == AUDIENCE_ALL_STAFF:
            # Other admins hear broadcasts too; the sending admin doesn't count
            size += audience_sizes.get(AUDIENCE_ADMINS, 0) - 1
        message['heard_count'] = heard_count
        message['audience_size'] = max(size, 0)
    return message


def _push_to_recipients(audience, sender_id, sender_name, message_id, audio_url, duration_ms):
    """Notify everyone the message is for (except the sender). Runs in a thread."""
    role_ids = list(STAFF_ROLE_IDS) if audience == AUDIENCE_ALL_STAFF else [ADMIN_ROLE_ID]
    if audience == AUDIENCE_ALL_STAFF:
        role_ids.append(ADMIN_ROLE_ID)  # other admins hear broadcasts too
    try:
        conn = get_db_connection()
        try:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT dt.fcm_token
                FROM device_tokens dt
                JOIN users u ON u.id = dt.user_id
                WHERE u.role_id = ANY(%s)
                  AND u.id <> %s
                  AND u.is_active IS NOT FALSE
                  AND dt.fcm_token IS NOT NULL
                  AND dt.fcm_token <> ''
            """, (role_ids, sender_id))
            tokens = [r[0] for r in cursor.fetchall()]
        finally:
            conn.close()
        result = send_push_to_tokens(
            tokens,
            title=f'🎙️ {sender_name}',
            body=f'Voice message · {_format_duration(duration_ms)}',
            data={
                'type': 'walkie',
                'message_id': message_id,
                'audio_url': audio_url,
                'sender_name': sender_name,
            },
        )
        print(f'[WALKIE] push for {message_id}: {result}')
    except Exception as e:
        print(f'[WALKIE] push failed for {message_id}: {e}')


@csrf_exempt
@api_view(['GET', 'POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def walkie_messages(request):
    """GET: message history + unheard count. POST: send a voice message."""
    user_id = request.user.get('user_id')
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        role_id, name = _sender_info(cursor, user_id)
        if not _can_use(role_id):
            return Response({'error': 'Walkie-talkie is for admins and staff only.'},
                            status=status.HTTP_403_FORBIDDEN)
        is_admin = role_id == ADMIN_ROLE_ID

        if request.method == 'POST':
            return _send(request, conn, cursor, user_id, name, is_admin)

        # Admins hear everything; staff hear admin broadcasts and their own replies
        visible = 'TRUE' if is_admin else '(m.audience = %(all_staff)s OR m.sender_id = %(me)s)'
        params = {'me': user_id, 'all_staff': AUDIENCE_ALL_STAFF, 'limit': _HISTORY_LIMIT}
        cursor.execute(f"""
            SELECT m.id, m.sender_id, m.audience, m.audio_url, m.duration_ms, m.created_at,
                   COALESCE(NULLIF(u.full_name, ''), u.username), u.role_id, r.role_name,
                   EXISTS (SELECT 1 FROM walkie_message_heard h
                           WHERE h.message_id = m.id AND h.user_id = %(me)s),
                   (SELECT COUNT(*) FROM walkie_message_heard h
                    WHERE h.message_id = m.id AND h.user_id <> m.sender_id)
            FROM walkie_messages m
            JOIN users u ON u.id = m.sender_id
            LEFT JOIN roles r ON r.id = u.role_id
            WHERE {visible}
            ORDER BY m.created_at DESC
            LIMIT %(limit)s
        """, params)
        rows = cursor.fetchall()
        sizes = _audience_sizes(cursor)
        messages = [_serialize(request, r, user_id, sizes) for r in reversed(rows)]
        unheard = sum(1 for m in messages if not m['heard'])
        return Response({'success': True, 'messages': messages, 'unheard_count': unheard})

    except Exception as e:
        print(f'Error in walkie_messages: {e}')
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
    finally:
        if conn:
            conn.close()


def _send(request, conn, cursor, user_id, name, is_admin):
    upload = request.FILES.get('audio')
    if not upload:
        return Response({'error': 'audio file is required'}, status=status.HTTP_400_BAD_REQUEST)
    ext = os.path.splitext(upload.name)[1].lower()
    if ext not in _ALLOWED_AUDIO_EXTS:
        return Response({'error': 'Unsupported audio format'}, status=status.HTTP_400_BAD_REQUEST)
    if upload.size > _MAX_AUDIO_BYTES:
        return Response({'error': 'Voice message is too large (max 5 MB)'},
                        status=status.HTTP_400_BAD_REQUEST)
    try:
        duration_ms = int(request.data.get('duration_ms') or 0)
    except ValueError:
        return Response({'error': 'duration_ms must be a whole number'},
                        status=status.HTTP_400_BAD_REQUEST)
    # Small allowance over the limit for the time it takes to stop recording
    duration_ms = min(max(duration_ms, 0), MAX_DURATION_MS + 5_000)

    audience = AUDIENCE_ALL_STAFF if is_admin else AUDIENCE_ADMINS
    path = default_storage.save(f'walkie/{uuid.uuid4()}{ext}', ContentFile(upload.read()))
    audio_url = f'/media/{path}'
    try:
        cursor.execute("""
            INSERT INTO walkie_messages (sender_id, audience, audio_url, duration_ms)
            VALUES (%s, %s, %s, %s)
            RETURNING id
        """, (user_id, audience, audio_url, duration_ms))
        message_id = str(cursor.fetchone()[0])
        conn.commit()
    except Exception:
        default_storage.delete(path)
        raise

    absolute_url = request.build_absolute_uri(audio_url)
    # FCM can take 10+ s; don't make the sender wait for it
    threading.Thread(
        target=_push_to_recipients,
        args=(audience, user_id, name or 'Essential Homes', message_id, absolute_url, duration_ms),
        daemon=True,
    ).start()
    return Response({'success': True, 'id': message_id, 'audience': audience},
                    status=status.HTTP_201_CREATED)


@csrf_exempt
@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def walkie_mark_heard(request, message_id):
    user_id = request.user.get('user_id')
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO walkie_message_heard (message_id, user_id)
            SELECT id, %s FROM walkie_messages WHERE id = %s
            ON CONFLICT DO NOTHING
        """, (user_id, str(message_id)))
        conn.commit()
        return Response({'success': True})
    except Exception as e:
        print(f'Error in walkie_mark_heard: {e}')
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
    finally:
        if conn:
            conn.close()
