"""
Same-day corrections to labour and material entries by any supervisor at a site.

When a site has several supervisors, any of them can fix a wrong count that
another (or they themselves) entered — but only on the day it was entered
(IST). After that the entry is locked and the accountant change-request flow
applies as before.

    POST /api/construction/entries/<labour|material>/<id>/edit/
         body: {"value": <new count / quantity used>, "reason": "optional"}

Every change is recorded in audit_logs_enhanced (old value, new value, who,
when, why), and admins get a push notification.

Material entries live in material_usage; stock (material_balance_view) is
computed from it, so changing the quantity used updates stock automatically.
"""
import threading
import uuid
from datetime import datetime
from decimal import Decimal, InvalidOperation

import pytz
from django.views.decorators.csrf import csrf_exempt
from rest_framework import status
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .authentication import JWTAuthentication
from .database import get_db_connection
from .fcm_service import send_push_to_admins

IST = pytz.timezone('Asia/Kolkata')
SUPERVISOR_ROLE = 'Supervisor'
MAX_LABOUR_COUNT = 500

_TABLES = {'labour': 'labour_entries', 'material': 'material_usage'}
_FIELDS = {'labour': 'labour_count', 'material': 'quantity_used'}


def today_ist():
    return datetime.now(IST).date()


def _fmt(value) -> str:
    """5.000 -> '5', 2.50 -> '2.5'"""
    text = str(value)
    if '.' in text:
        text = text.rstrip('0').rstrip('.')
    return text


# ---------------------------------------------------------------------------
# Read side: extra data for the supervisor site screen (get_entries_by_date)
# ---------------------------------------------------------------------------

def edit_history(cur, record_ids) -> dict:
    """Latest edit per entry: {id: {edited_by_name, edited_at, original_value}}."""
    if not record_ids:
        return {}
    cur.execute("""
        SELECT a.record_id,
               COALESCE(NULLIF(u.full_name, ''), u.username) AS edited_by,
               a.changed_at,
               first_value(a.old_value) OVER (PARTITION BY a.record_id ORDER BY a.changed_at)
                   AS original_value,
               row_number() OVER (PARTITION BY a.record_id ORDER BY a.changed_at DESC) AS rn
        FROM audit_logs_enhanced a
        LEFT JOIN users u ON u.id = a.changed_by
        WHERE a.record_id = ANY(%s::uuid[])
          AND a.table_name IN ('labour_entries', 'material_usage')
    """, ([str(i) for i in record_ids],))
    history = {}
    for record_id, edited_by, changed_at, original_value, rn in cur.fetchall():
        if rn == 1:
            history[str(record_id)] = {
                'edited_by_name': edited_by or 'Unknown',
                'edited_at': changed_at.isoformat() if changed_at else None,
                'original_value': original_value,
            }
    return history


def supervisor_site_extras(site_id, entry_date, user_id, own_labour_ids, own_material_ids) -> dict:
    """
    For the supervisor site screen: other supervisors' entries for this site
    and date (shown and editable, but kept out of 'labour_entries' so the
    screen's own-entry logic is unchanged), plus edit info for every entry.
    """
    can_edit = entry_date == today_ist()
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT l.id, l.supervisor_id, l.labour_type, l.labour_count, l.entry_date,
                   l.entry_time, l.entry_type,
                   COALESCE(NULLIF(u.full_name, ''), u.phone) AS supervisor_name
            FROM labour_entries l
            LEFT JOIN users u ON u.id = l.supervisor_id
            WHERE l.site_id = %s AND l.entry_date = %s
              AND l.supervisor_id <> %s
              AND l.submitted_by_role = %s
            ORDER BY l.entry_time DESC
        """, (site_id, entry_date, user_id, SUPERVISOR_ROLE))
        other_labour = [
            {
                'id': str(r[0]),
                'supervisor_id': str(r[1]),
                'labour_type': r[2],
                'labour_count': r[3],
                'entry_date': r[4].isoformat() if r[4] else None,
                'entry_time': r[5].isoformat() if r[5] else None,
                'entry_type': r[6] or 'morning',
                'supervisor_name': r[7] or '',
            }
            for r in cur.fetchall()
        ]

        cur.execute("""
            SELECT m.id, m.supervisor_id, m.material_type, m.quantity_used, m.unit,
                   m.usage_date, m.created_at,
                   COALESCE(NULLIF(u.full_name, ''), u.phone) AS supervisor_name
            FROM material_usage m
            LEFT JOIN users u ON u.id = m.supervisor_id
            WHERE m.site_id = %s AND m.usage_date = %s AND m.supervisor_id <> %s
            ORDER BY m.created_at DESC
        """, (site_id, entry_date, user_id))
        other_material = [
            {
                'id': str(r[0]),
                'supervisor_id': str(r[1]) if r[1] else None,
                'material_type': r[2],
                'quantity': float(r[3]),
                'unit': r[4],
                'entry_date': r[5].isoformat() if r[5] else None,
                'updated_at': r[6].isoformat() if r[6] else None,
                'supervisor_name': r[7] or '',
            }
            for r in cur.fetchall()
        ]

        all_ids = (list(own_labour_ids) + list(own_material_ids)
                   + [e['id'] for e in other_labour] + [e['id'] for e in other_material])
        history = edit_history(cur, all_ids)
    finally:
        conn.close()

    for entry in other_labour + other_material:
        entry['can_edit'] = can_edit
        entry['entered_by_me'] = False
    return {
        'other_labour_entries': other_labour,
        'other_material_entries': other_material,
        'edit_history': history,
        'can_edit': can_edit,
    }


# ---------------------------------------------------------------------------
# Write side
# ---------------------------------------------------------------------------

class _Refused(Exception):
    def __init__(self, message, code=status.HTTP_400_BAD_REQUEST):
        super().__init__(message)
        self.code = code


def _parse_value(kind, raw):
    if raw is None or str(raw).strip() == '':
        raise _Refused('value is required')
    if kind == 'labour':
        try:
            value = int(str(raw).strip())
        except ValueError:
            raise _Refused('Labour count must be a whole number')
        if not 0 <= value <= MAX_LABOUR_COUNT:
            raise _Refused(f'Labour count must be between 0 and {MAX_LABOUR_COUNT}')
        return value
    try:
        value = Decimal(str(raw).strip())
    except InvalidOperation:
        raise _Refused('Quantity must be a number')
    if value < 0:
        raise _Refused('Quantity cannot be negative')
    return value


def _load_entry(cur, kind, entry_id):
    if kind == 'labour':
        cur.execute("""
            SELECT l.site_id, l.entry_date, l.labour_count, l.labour_type,
                   l.submitted_by_role, l.entry_type, s.site_name, NULL
            FROM labour_entries l JOIN sites s ON s.id = l.site_id
            WHERE l.id = %s
            FOR UPDATE OF l
        """, (entry_id,))
    else:
        cur.execute("""
            SELECT m.site_id, m.usage_date, m.quantity_used, m.material_type,
                   r.role_name, NULL, s.site_name, m.unit
            FROM material_usage m
            JOIN sites s ON s.id = m.site_id
            LEFT JOIN users u ON u.id = m.supervisor_id
            LEFT JOIN roles r ON r.id = u.role_id
            WHERE m.id = %s
            FOR UPDATE OF m
        """, (entry_id,))
    row = cur.fetchone()
    if not row:
        raise _Refused('Entry not found', status.HTTP_404_NOT_FOUND)
    keys = ('site_id', 'entry_date', 'old_value', 'item', 'entered_by_role',
            'session', 'site_name', 'unit')
    return dict(zip(keys, row))


def _check_material_stock(cur, entry, new_value):
    """The new quantity used can't be more than was in stock for the day."""
    cur.execute("""
        SELECT current_balance FROM material_balance_view
        WHERE site_id = %s AND material_type = %s
    """, (entry['site_id'], entry['item']))
    row = cur.fetchone()
    if row is None:
        return  # no stock record for this material: nothing to check against
    available = Decimal(row[0]) + Decimal(entry['old_value'])
    if new_value > available:
        raise _Refused(f"Only {_fmt(available)} {entry['unit'] or ''} of {entry['item']} "
                       f"was in stock".strip())


@csrf_exempt
@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def edit_entry(request, kind, entry_id):
    """Correct a same-day labour count or material quantity used."""
    if kind not in _TABLES:
        return Response({'error': 'Unknown entry type'}, status=status.HTTP_404_NOT_FOUND)
    user_id = request.user.get('user_id')
    if request.user.get('role') != SUPERVISOR_ROLE:
        return Response({'error': 'Only supervisors can edit entries here.'},
                        status=status.HTTP_403_FORBIDDEN)

    conn = None
    try:
        new_value = _parse_value(kind, request.data.get('value'))
        reason = (request.data.get('reason') or '').strip()[:500] or None

        conn = get_db_connection()
        cur = conn.cursor()
        entry = _load_entry(cur, kind, str(entry_id))

        if entry['entered_by_role'] != SUPERVISOR_ROLE:
            raise _Refused("Only supervisors' entries can be edited here.", status.HTTP_403_FORBIDDEN)
        if entry['entry_date'] != today_ist():
            raise _Refused('Entries can only be changed on the day they were made. '
                           'Ask the accountant for a change request.', status.HTTP_403_FORBIDDEN)

        old_value = entry['old_value']
        if Decimal(str(old_value)) == Decimal(str(new_value)):
            return Response({'success': True, 'changed': False})

        if kind == 'labour':
            cur.execute("""
                UPDATE labour_entries
                SET labour_count = %s, is_modified = TRUE, modified_by = %s,
                    modified_at = NOW(), modification_reason = %s
                WHERE id = %s
            """, (new_value, user_id, reason, str(entry_id)))
            # Keep the day's labour cost in step with the count
            cur.execute("""
                UPDATE labour_cost_calculation
                SET labour_count = %s, total_cost = daily_rate * %s
                WHERE labour_entry_id = %s
            """, (new_value, new_value, str(entry_id)))
        else:
            _check_material_stock(cur, entry, new_value)
            cur.execute('UPDATE material_usage SET quantity_used = %s WHERE id = %s',
                        (new_value, str(entry_id)))

        cur.execute("""
            INSERT INTO audit_logs_enhanced
                (audit_id, site_id, table_name, record_id, field_name, old_value, new_value,
                 change_type, changed_by, changed_by_role, changed_at, reason)
            VALUES (%s, %s, %s, %s, %s, %s, %s, 'UPDATE', %s, %s, NOW(), %s)
        """, (str(uuid.uuid4()), entry['site_id'], _TABLES[kind], str(entry_id), _FIELDS[kind],
              _fmt(old_value), _fmt(new_value), user_id, SUPERVISOR_ROLE, reason))

        cur.execute("SELECT COALESCE(NULLIF(full_name, ''), username) FROM users WHERE id = %s",
                    (user_id,))
        editor = (cur.fetchone() or ['A supervisor'])[0]
        conn.commit()

        what = entry['item'] + (f" ({entry['session']})" if entry['session'] else '')
        unit = f" {entry['unit']}" if entry['unit'] else ''
        body = (f"{editor} changed {what} at {entry['site_name']}: "
                f"{_fmt(old_value)} → {_fmt(new_value)}{unit}")
        if reason:
            body += f' — "{reason}"'
        # FCM can take 10+ s; don't make the supervisor wait for it
        threading.Thread(
            target=send_push_to_admins,
            kwargs=dict(title='✏️ Entry corrected', body=body,
                        data={'type': 'entry_edit', 'site_id': str(entry['site_id'])}),
            daemon=True,
        ).start()

        return Response({'success': True, 'changed': True,
                         'old_value': float(old_value), 'new_value': float(new_value)})

    except _Refused as e:
        if conn:
            conn.rollback()
        return Response({'error': str(e)}, status=e.code)
    except Exception as e:
        if conn:
            conn.rollback()
        print(f'Error in edit_entry: {e}')
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
    finally:
        if conn:
            conn.close()
