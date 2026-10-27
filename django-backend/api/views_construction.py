"""
Construction Management System - Role-Based APIs
Complete implementation for all roles
"""
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from datetime import datetime, time
from .authentication import JWTAuthentication
from .database import execute_query, fetch_one, fetch_all
import uuid
import pytz


# TEST ENDPOINT - NO AUTHENTICATION to isolate the issue
@api_view(['POST'])
def test_material_balance(request):
    """Test endpoint without authentication"""
    print(f'✅ [TEST] Test endpoint called!')
    site_id = request.data.get('site_id')
    materials = request.data.get('materials', [])
    print(f'✅ [TEST] site_id: {site_id}, materials count: {len(materials)}')
    return Response({'message': 'Test endpoint works!', 'received_site_id': site_id, 'received_materials': materials}, status=status.HTTP_200_OK)


# ============================================
# COMMON APIS (ALL ROLES)
# ============================================

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def create_site(request):
    """
    Accountant/Admin: Create a new site
    POST /api/construction/create-site/
    """
    try:
        user_role = request.user.get('role', '')
        
        # Only Accountant and Admin can create sites
        if user_role not in ['Accountant', 'Admin']:
            return Response({'error': 'Only Accountant and Admin can create sites'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        site_name = request.data.get('site_name')
        customer_name = request.data.get('customer_name')
        area = request.data.get('area')
        street = request.data.get('street')
        
        if not all([site_name, customer_name, area, street]):
            return Response({'error': 'site_name, customer_name, area, and street are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Create site
        site_id = str(uuid.uuid4())
        display_name = f"{customer_name} {site_name}"
        
        execute_query("""
            INSERT INTO sites 
            (id, site_name, customer_name, area, street, created_at)
            VALUES (%s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
        """, (site_id, site_name, customer_name, area, street))
        
        return Response({
            'message': 'Site created successfully',
            'site_id': site_id,
            'site': {
                'id': site_id,
                'site_name': site_name,
                'customer_name': customer_name,
                'display_name': display_name,
                'area': area,
                'street': street
            }
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_areas(request):
    """Get all areas"""
    try:
        areas = fetch_all("SELECT DISTINCT area FROM sites WHERE area != '' ORDER BY area")
        return Response({
            'areas': [a['area'] for a in areas]
        }, status=status.HTTP_200_OK)
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_streets(request, area):
    """Get streets by area"""
    try:
        if not area:
            return Response({'error': 'Area is required'}, status=status.HTTP_400_BAD_REQUEST)
        
        streets = fetch_all(
            "SELECT DISTINCT street FROM sites WHERE area = %s AND street != '' ORDER BY street",
            (area,)
        )
        return Response({
            'streets': [s['street'] for s in streets]
        }, status=status.HTTP_200_OK)
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_sites(request):
    """Get sites by area and street"""
    try:
        area = request.query_params.get('area')
        street = request.query_params.get('street')
        
        query = "SELECT id, site_name, customer_name, area, street FROM sites WHERE 1=1"
        params = []
        
        if area:
            query += " AND area = %s"
            params.append(area)
        if street:
            query += " AND street = %s"
            params.append(street)
        
        query += " AND site_name != '' ORDER BY customer_name, site_name"
        
        sites = fetch_all(query, tuple(params) if params else None)
        return Response({
            'sites': [
                {
                    'id': str(s['id']),
                    'site_name': s['site_name'],
                    'customer_name': s['customer_name'],
                    'area': s.get('area', ''),
                    'street': s.get('street', ''),
                    'display_name': f"{s['customer_name']} {s['site_name']}"
                }
                for s in sites
            ]
        }, status=status.HTTP_200_OK)
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_materials(request):
    """
    Get all materials from material_master table
    GET /api/construction/materials/
    """
    try:
        print("🔍 [MATERIALS API] Fetching materials...")
        materials = fetch_all("""
            SELECT id, material_name, created_at
            FROM material_master
            ORDER BY material_name ASC
        """)
        
        print(f"🔍 [MATERIALS API] Found {len(materials)} materials in database")
        for m in materials:
            print(f"  - {m['material_name']} (ID: {m['id']})")
        
        response_data = {
            'materials': [
                {
                    'id': str(m['id']),
                    'name': m['material_name'],
                    'created_at': m['created_at'].isoformat() if m.get('created_at') else None
                }
                for m in materials
            ]
        }
        
        print(f"✅ [MATERIALS API] Returning {len(response_data['materials'])} materials")
        return Response(response_data, status=status.HTTP_200_OK)
    except Exception as e:
        print(f"❌ Error fetching materials: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e), 'materials': []}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def add_material(request):
    """
    Add a new material to material_master table
    POST /api/construction/materials/add/
    """
    try:
        user_id = request.user['user_id']
        material_name = request.data.get('material_name', '').strip()
        
        if not material_name:
            return Response({'error': 'material_name is required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Check if material already exists
        existing = fetch_one("""
            SELECT id FROM material_master
            WHERE LOWER(material_name) = LOWER(%s)
        """, (material_name,))
        
        if existing:
            return Response({
                'error': 'Material already exists',
                'material_id': str(existing['id'])
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Insert new material
        material_id = str(uuid.uuid4())
        execute_query("""
            INSERT INTO material_master (id, material_name, created_by, created_at)
            VALUES (%s, %s, %s, %s)
        """, (material_id, material_name, user_id, timezone.now()))
        
        return Response({
            'message': 'Material added successfully',
            'material_id': material_id,
            'material_name': material_name
        }, status=status.HTTP_201_CREATED)
    except Exception as e:
        print(f"❌ Error adding material: {str(e)}")
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ============================================
# SUPERVISOR APIS
# ============================================

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def submit_labour_count(request):
    """
    Submit a labour count entry for a site.
    Accepts an optional custom_datetime (ISO-8601, with or without Z/offset)
    from the client so the device's local IST time is honoured.
    Morning entries  = before 12:00 IST
    Evening entries  = 12:00 IST and later
    Lock rule        = one entry per (site, date, entry_type, labour_type)
    """
    from .time_utils import get_day_of_week
    from django.db import transaction, IntegrityError

    IST = pytz.timezone('Asia/Kolkata')

    _DEFAULT_RATES = {
        'General': 600, 'Mason': 800, 'Helper': 500, 'Carpenter': 750,
        'Plumber': 700, 'Electrician': 750, 'Painter': 650, 'Tile Layer': 700,
        'Tile Layerhelper': 700, 'Kambi Fitter': 900, 'Concrete Kot': 950,
        'Pile Labour': 800,
    }

    try:
        import logging
        logger = logging.getLogger('django')

        user_id   = request.user['user_id']
        user_role = request.user.get('role')

        if not user_role:
            logger.error(f"[LABOUR AUTH CRITICAL] user_id={user_id} has no role in JWT token!")
            return Response({
                'error': 'User role not found in authentication token. Please log out and log in again.',
            }, status=status.HTTP_401_UNAUTHORIZED)

        print(f"[LABOUR AUTH] user_id={user_id}, jwt_role={user_role}")
        logger.warning(f"[LABOUR AUTH] user_id={user_id}, jwt_role={user_role}")

        site_id     = request.data.get('site_id', '').strip()
        labour_type = request.data.get('labour_type', 'General').strip()
        notes       = request.data.get('notes', '').strip()
        extra_cost_notes = request.data.get('extra_cost_notes', '').strip()

        try:
            labour_count = int(request.data.get('labour_count', 0))
        except (TypeError, ValueError):
            return Response({'error': 'labour_count must be a whole number'},
                            status=status.HTTP_400_BAD_REQUEST)

        try:
            extra_cost = float(request.data.get('extra_cost', 0) or 0)
        except (TypeError, ValueError):
            extra_cost = 0.0

        if not site_id:
            return Response({'error': 'site_id is required'},
                            status=status.HTTP_400_BAD_REQUEST)
        if labour_count <= 0:
            return Response({'error': 'labour_count must be greater than 0'},
                            status=status.HTTP_400_BAD_REQUEST)

        # ── Resolve IST datetime ──────────────────────────────────────────
        custom_datetime_str = request.data.get('custom_datetime', '').strip()

        if custom_datetime_str:
            try:
                # Handle both "2026-05-14T10:39:00Z" and "2026-05-14T16:09:00"
                ist_dt = datetime.fromisoformat(
                    custom_datetime_str.replace('Z', '+00:00')
                )
                if ist_dt.tzinfo is None:
                    ist_dt = IST.localize(ist_dt)
                else:
                    ist_dt = ist_dt.astimezone(IST)
                print(f"[LABOUR] Custom datetime parsed → IST: {ist_dt}")
            except Exception as parse_err:
                print(f"[LABOUR] custom_datetime parse failed ({parse_err}), using server IST now")
                ist_dt = datetime.now(IST)
        else:
            ist_dt = datetime.now(IST)

        entry_date   = ist_dt.date()                  # date object, pure IST calendar date
        entry_time   = ist_dt.replace(tzinfo=None)    # naive datetime for TIMESTAMP WITHOUT TZ column
        entry_hour   = ist_dt.hour                    # IST hour — determines morning vs evening
        entry_type   = 'morning' if entry_hour < 12 else 'evening'
        day_of_week  = get_day_of_week(ist_dt)

        logger.warning(f"[LABOUR] site={site_id} date={entry_date} type={entry_type} "
                      f"labour_type={labour_type} count={labour_count} role={user_role}")

        # ── Duplicate / lock check ────────────────────────────────────────
        # One entry per (site, date, entry_type, labour_type, submitted_by_role) per user.
        # This allows supervisor and site engineer to submit same labour type separately.
        print(f"[LABOUR] Duplicate check: site={site_id}, date={entry_date}, "
              f"type={entry_type}, labour={labour_type}, role={user_role}")
        logger.warning(f"[LABOUR] Duplicate check: site={site_id}, date={entry_date}, "
                      f"type={entry_type}, labour={labour_type}, role={user_role}")

        existing = fetch_one("""
            SELECT le.id,
                   le.supervisor_id,
                   le.entry_time,
                   le.submitted_by_role,
                   COALESCE(u.full_name, u.phone) AS supervisor_name
            FROM   labour_entries le
            LEFT JOIN users u ON u.id = le.supervisor_id
            WHERE  le.site_id         = %s
              AND  le.entry_date      = %s
              AND  le.entry_type      = %s
              AND  le.labour_type     = %s
              AND  le.submitted_by_role = %s
            LIMIT 1
        """, (site_id, entry_date, entry_type, labour_type, user_role))

        print(f"[LABOUR] Result: {'FOUND' if existing else 'NOT FOUND'}")
        logger.warning(f"[LABOUR] Result: {'FOUND' if existing else 'NOT FOUND'}")
        if existing:
            print(f"[LABOUR] Existing: id={existing['id']}, role={existing['submitted_by_role']}, "
                  f"supervisor={existing['supervisor_id']}")
            logger.warning(f"[LABOUR] Existing: id={existing['id']}, role={existing['submitted_by_role']}, "
                          f"supervisor={existing['supervisor_id']}")
            print(f"[LABOUR] Role Match Debug: seeking_role={user_role}, found_role={existing['submitted_by_role']}, "
                  f"roles_match={user_role == existing['submitted_by_role']}")
            logger.warning(f"[LABOUR] Role Match Debug: seeking_role={user_role}, found_role={existing['submitted_by_role']}, "
                          f"roles_match={user_role == existing['submitted_by_role']}")

        if existing:
            if str(existing['supervisor_id']) == str(user_id):
                return Response({
                    'error': (f'You already submitted {labour_type} for the '
                              f'{entry_type} on {entry_date}. '
                              f'Each labour type can only be entered once per session.'),
                    'can_edit': False,
                    'existing_entry_id': str(existing['id']),
                }, status=status.HTTP_409_CONFLICT)
            else:
                locked_at = (existing['entry_time'].strftime('%I:%M %p')
                             if existing.get('entry_time') else 'earlier')
                return Response({
                    'error': (f'{labour_type} ({entry_type}) already entered by '
                              f'{existing["supervisor_name"]} ({existing["submitted_by_role"]}) at {locked_at}'),
                    'locked_by': existing['supervisor_name'],
                    'locked_at': locked_at,
                    'entry_type': entry_type,
                    'can_edit': False,
                }, status=status.HTTP_423_LOCKED)

        # ── Insert ────────────────────────────────────────────────────────
        entry_id = str(uuid.uuid4())

        try:
            with transaction.atomic():
                execute_query("""
                    INSERT INTO labour_entries
                        (id, site_id, supervisor_id, labour_count, labour_type,
                         entry_date, entry_time, entry_type, day_of_week,
                         notes, extra_cost, extra_cost_notes, submitted_by_role)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, (entry_id, site_id, user_id, labour_count, labour_type,
                      entry_date, entry_time, entry_type, day_of_week,
                      notes, extra_cost, extra_cost_notes, user_role))

                # Resolve daily rate (admin-configured > built-in default)
                rate_row = fetch_one("""
                    SELECT daily_rate FROM labour_salary_rates
                    WHERE  site_id IS NULL
                      AND  labour_type = %s
                      AND  is_active = TRUE
                    ORDER BY effective_from DESC
                    LIMIT 1
                """, (labour_type,))
                daily_rate = (float(rate_row['daily_rate'])
                              if rate_row and rate_row.get('daily_rate')
                              else _DEFAULT_RATES.get(labour_type, 900))
                total_cost = daily_rate * labour_count

                execute_query("""
                    INSERT INTO labour_cost_calculation
                        (id, site_id, labour_entry_id, labour_type, labour_count,
                         daily_rate, total_cost, entry_date, day_of_week)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (labour_entry_id) DO UPDATE
                        SET daily_rate = EXCLUDED.daily_rate,
                            total_cost = EXCLUDED.total_cost
                """, (str(uuid.uuid4()), site_id, entry_id, labour_type,
                      labour_count, daily_rate, total_cost, entry_date, day_of_week))

                print(f"[LABOUR] ✅ Inserted entry_id={entry_id} "
                      f"entry_date={entry_date} entry_type={entry_type}")

                return Response({
                    'success': True,
                    'message': 'Labour count submitted successfully',
                    'entry_id': entry_id,
                    'entry_date': entry_date.strftime('%Y-%m-%d'),
                    'entry_time': entry_time.strftime('%H:%M:%S'),
                    'entry_type': entry_type,
                    'day_of_week': day_of_week,
                    'labour_type': labour_type,
                    'labour_count': labour_count,
                    'daily_rate': daily_rate,
                    'total_cost': total_cost,
                    'extra_cost': extra_cost,
                }, status=status.HTTP_201_CREATED)

        except IntegrityError as e:
            print(f"[LABOUR] ❌ IntegrityError: {e}")
            if 'idx_labour_entry_lock' in str(e) or 'unique' in str(e).lower():
                return Response({
                    'error': 'Entry already exists — another supervisor submitted simultaneously.',
                    'retry': True,
                }, status=status.HTTP_409_CONFLICT)
            raise

    except Exception as e:
        print(f"[LABOUR] ❌ Unhandled error: {e}")
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def check_entry_lock(request):
    """
    Check if a site entry is locked by another supervisor
    Query params: site_id, entry_date (optional, defaults to today)
    """
    try:
        from datetime import datetime, date
        
        user_id = request.user['user_id']
        site_id = request.GET.get('site_id')
        entry_date_str = request.GET.get('entry_date')
        
        if not site_id:
            return Response({'error': 'site_id is required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Use provided date or default to today
        if entry_date_str:
            try:
                entry_date = datetime.strptime(entry_date_str, '%Y-%m-%d').date()
            except ValueError:
                return Response({'error': 'Invalid date format. Use YYYY-MM-DD'}, 
                              status=status.HTTP_400_BAD_REQUEST)
        else:
            entry_date = date.today()
        
        # Determine entry type based on current time
        current_hour = datetime.now().hour
        entry_type = 'morning' if current_hour < 12 else 'evening'
        
        user_role = request.user.get('role')
        print(f"[ENTRY_LOCK_CHECK] Checking lock for site={site_id}, date={entry_date}, type={entry_type}, user={user_id}, role={user_role}")

        if not user_role:
            return Response({'error': 'User role not found in token'},
                          status=status.HTTP_401_UNAUTHORIZED)

        # Check if any entries exist for this site/date from DIFFERENT ROLES
        # We only care about locks from other roles, not other users in the same role
        entries = fetch_all("""
            SELECT
                le.id,
                le.supervisor_id,
                COALESCE(u.full_name, u.phone) as supervisor_name,
                le.entry_time,
                le.labour_type,
                le.labour_count,
                le.entry_type,
                le.submitted_by_role
            FROM labour_entries le
            LEFT JOIN users u ON le.supervisor_id = u.id
            WHERE le.site_id = %s
              AND le.entry_date = %s
            ORDER BY le.entry_time DESC
        """, (site_id, entry_date))
        
        if not entries:
            # No entries - site is available
            print(f"[ENTRY_LOCK_CHECK] No entries found - site available")
            return Response({
                'is_locked': False,
                'can_enter': True,
                'entries': []
            }, status=status.HTTP_200_OK)

        # Check for entries from SAME ROLE vs DIFFERENT ROLES
        # Lock if SAME role already submitted (only one role per site/date)
        # Allow if only DIFFERENT role submitted
        role_entries = [e for e in entries if e.get('submitted_by_role') == user_role]
        different_role_entries = [e for e in entries if e.get('submitted_by_role') and e.get('submitted_by_role') != user_role]

        print(f"[ENTRY_LOCK_CHECK] Found {len(entries)} entries: {len(role_entries)} from same role={user_role}, {len(different_role_entries)} from different roles")
        for e in entries:
            print(f"  - Entry: labour_type={e['labour_type']}, submitted_by_role={e.get('submitted_by_role')}, supervisor_id={e['supervisor_id']}")

        # If same role has already entered data - LOCK (prevent another user of same role)
        if role_entries:
            first_entry = role_entries[0]
            entry_time_str = first_entry['entry_time'].strftime("%I:%M %p") if first_entry.get('entry_time') else 'earlier'
            print(f"[ENTRY_LOCK_CHECK] LOCKED - Same role {user_role} already has entries")
            return Response({
                'is_locked': True,
                'locked_by': first_entry.get('supervisor_name', 'Another ' + user_role),
                'locked_at': entry_time_str,
                'can_enter': False,
                'can_view': True,
                'entries': [
                    {
                        'labour_type': e['labour_type'],
                        'labour_count': e['labour_count'],
                        'entry_type': e.get('entry_type', 'unknown'),
                        'submitted_by_role': e.get('submitted_by_role')
                    }
                    for e in role_entries
                ]
            }, status=status.HTTP_200_OK)

        # Different role entries exist but same role hasn't - allow this role to submit
        if different_role_entries:
            print(f"[ENTRY_LOCK_CHECK] ALLOWED - Different role has entries, but {user_role} can submit separately")
            return Response({
                'is_locked': False,
                'can_enter': True,
                'entries': [
                    {
                        'labour_type': e['labour_type'],
                        'labour_count': e['labour_count'],
                        'entry_type': e.get('entry_type', 'unknown'),
                        'submitted_by_role': e.get('submitted_by_role')
                    }
                    for e in different_role_entries
                ]
            }, status=status.HTTP_200_OK)

        # No entries at all - allow
        print(f"[ENTRY_LOCK_CHECK] ALLOWED - No entries found")
        return Response({
            'is_locked': False,
            'can_enter': True,
            'entries': []
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        print(f"[ENTRY_LOCK_CHECK] ❌ Error: {e}")
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@csrf_exempt
@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def submit_material_balance(request):
    """
    Supervisor: Submit material balance with custom local time
    Accepts custom_datetime from client to use local device time
    """
    print(f'🔵 [MATERIAL] View called successfully')

    try:
        # Import time utilities
        from .time_utils import is_within_entry_hours, get_entry_metadata, get_entry_time_status, get_day_of_week
        from datetime import datetime
        import pytz
        import sys

        # Ensure stdout uses UTF-8 encoding
        if sys.stdout.encoding != 'utf-8':
            sys.stdout.reconfigure(encoding='utf-8')

        user_id = request.user.user_data.get('user_id')
        site_id = request.data.get('site_id')
        materials = request.data.get('materials', [])  # List of {material_type, quantity, unit}
        extra_cost = request.data.get('extra_cost', 0)
        extra_cost_notes = request.data.get('extra_cost_notes', '')

        # Get custom date/time from client (local device time)
        custom_datetime_str = request.data.get('custom_datetime')

        print(f'📦 [MATERIAL] site_id: {site_id}')
        print(f'📦 [MATERIAL] materials: {materials}')
        print(f'📦 [MATERIAL] materials type: {type(materials)}')
        print(f'📦 [MATERIAL] materials is empty: {not materials}')

        if not site_id or not materials:
            print(f'❌ [MATERIAL] Validation failed - site_id: {bool(site_id)}, materials: {bool(materials)}')
            return Response({'error': 'site_id and materials are required'}, status=status.HTTP_400_BAD_REQUEST)
        
        # Use custom date/time if provided, otherwise use current IST time
        if custom_datetime_str:
            try:
                # Parse the ISO datetime string from client
                custom_dt = datetime.fromisoformat(custom_datetime_str.replace('Z', '+00:00'))
                # Convert to IST if it's not already
                ist_tz = pytz.timezone('Asia/Kolkata')
                if custom_dt.tzinfo is None:
                    # Assume it's local time, convert to IST
                    custom_dt = ist_tz.localize(custom_dt)
                else:
                    custom_dt = custom_dt.astimezone(ist_tz)
                
                entry_date = custom_dt.date()
                entry_time = custom_dt
                day_of_week = get_day_of_week(custom_dt)
                
                print(f"Using custom datetime for materials: {custom_dt} (IST)")
                print(f"Entry date: {entry_date}, Day: {day_of_week}")
                
            except Exception as e:
                print(f"Error parsing custom datetime: {e}")
                # Fall back to current time
                entry_meta = get_entry_metadata()
                entry_date = entry_meta['entry_date']
                entry_time = entry_meta['timestamp_ist']
                day_of_week = entry_meta['day_of_week']
        else:
            # Use current IST time
            entry_meta = get_entry_metadata()
            entry_date = entry_meta['entry_date']
            entry_time = entry_meta['timestamp_ist']
            day_of_week = entry_meta['day_of_week']
        
        # DAILY RESTRICTION: Check if already submitted today for this site (any supervisor)
        existing_entry = fetch_one("""
            SELECT id FROM material_usage
            WHERE site_id = %s AND usage_date = %s
            LIMIT 1
        """, (site_id, entry_date))
        
        if existing_entry:
            return Response({
                'error': f'Material balance already submitted for {entry_date} for this site. It can only be submitted once per day per site.'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Insert material usage records with custom or current time
        for material in materials:
            material_id = str(uuid.uuid4())
            
            # Ensure UTF-8 encoding for material type and notes
            material_type = str(material['material_type'])
            unit = str(material.get('unit', 'units'))
            notes = str(extra_cost_notes) if extra_cost_notes else None
            
            # Clean any special characters that might cause encoding issues
            material_type = material_type.encode('utf-8', errors='ignore').decode('utf-8')
            unit = unit.encode('utf-8', errors='ignore').decode('utf-8')
            if notes:
                notes = notes.encode('utf-8', errors='ignore').decode('utf-8')
            
            execute_query("""
                INSERT INTO material_usage 
                (id, site_id, supervisor_id, material_type, quantity_used, unit, usage_date, notes, created_at)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (material_id, site_id, user_id, material_type, material['quantity'], 
                  unit, entry_date, notes, entry_time))
        
        return Response({
            'message': 'Material balance submitted successfully',
            'day_of_week': day_of_week,
            'entry_date': entry_date.strftime('%Y-%m-%d'),
            'entry_time': entry_time.strftime('%H:%M:%S'),
            'materials_count': len(materials),
            'extra_cost': extra_cost,
            'used_custom_time': custom_datetime_str is not None
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        # Ensure error message is safe to encode
        import traceback
        error_msg = str(e).encode('utf-8', errors='replace').decode('utf-8')
        print(f"❌ [MATERIAL] Error in submit_material_balance: {error_msg}")
        print(f"❌ [MATERIAL] Traceback: {traceback.format_exc()}")
        return Response({'error': error_msg}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def upload_site_images(request):
    """Supervisor: Upload site work images (evening)"""
    try:
        user_id = request.user['user_id']
        site_id = request.data.get('site_id')
        image_urls = request.data.get('image_urls', [])  # List of image URLs
        description = request.data.get('description', '')
        
        if not site_id or not image_urls:
            return Response({'error': 'site_id and image_urls are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        today = datetime.now().date()
        
        # Insert work updates
        for image_url in image_urls:
            update_id = str(uuid.uuid4())
            execute_query("""
                INSERT INTO work_updates 
                (id, site_id, engineer_id, update_type, image_url, description, update_date, visible_to_client)
                VALUES (%s, %s, %s, 'PROGRESS', %s, %s, %s, FALSE)
            """, (update_id, site_id, user_id, image_url, description, today))
        
        return Response({
            'message': 'Images uploaded successfully'
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_today_entries(request):
    """Supervisor: Get today's entries (read-only)"""
    try:
        user_id = request.user['user_id']
        site_id = request.query_params.get('site_id')
        today = datetime.now().date()
        
        # Get labour entry
        labour = fetch_one("""
            SELECT labour_count, labour_type, entry_time, notes
            FROM labour_entries
            WHERE supervisor_id = %s AND site_id = %s AND entry_date = %s
        """, (user_id, site_id, today))
        
        # Get material usage entries
        materials = fetch_all("""
            SELECT material_type, quantity_used as quantity, unit, created_at as updated_at
            FROM material_usage
            WHERE supervisor_id = %s AND site_id = %s AND usage_date = %s
        """, (user_id, site_id, today))
        
        return Response({
            'labour': labour,
            'materials': materials
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ============================================
# SITE ENGINEER APIS
# ============================================

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def upload_work_started(request):
    """Site Engineer: Upload 'Work Started' update (before 1 PM)"""
    try:
        user_id = request.user['user_id']
        site_id = request.data.get('site_id')
        image_url = request.data.get('image_url')
        description = request.data.get('description', '')
        
        if not all([site_id, image_url]):
            return Response({'error': 'site_id and image_url are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Check if before 1 PM
        current_time = datetime.now().time()
        if current_time > time(13, 0):  # 1 PM
            return Response({'error': 'Work started update must be uploaded before 1 PM'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        today = datetime.now().date()
        update_id = str(uuid.uuid4())
        
        execute_query("""
            INSERT INTO work_updates 
            (id, site_id, engineer_id, update_type, image_url, description, update_date)
            VALUES (%s, %s, %s, 'STARTED', %s, %s, %s)
        """, (update_id, site_id, user_id, image_url, description, today))
        
        return Response({
            'message': 'Work started update uploaded successfully',
            'update_id': update_id
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def upload_work_finished(request):
    """Site Engineer: Upload 'Work Finished' images (evening)"""
    try:
        user_id = request.user['user_id']
        site_id = request.data.get('site_id')
        image_urls = request.data.get('image_urls', [])
        description = request.data.get('description', '')
        
        if not site_id or not image_urls:
            return Response({'error': 'site_id and image_urls are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        today = datetime.now().date()
        
        for image_url in image_urls:
            update_id = str(uuid.uuid4())
            execute_query("""
                INSERT INTO work_updates 
                (id, site_id, engineer_id, update_type, image_url, description, update_date)
                VALUES (%s, %s, %s, 'FINISHED', %s, %s, %s)
            """, (update_id, site_id, user_id, image_url, description, today))
        
        return Response({
            'message': 'Work finished images uploaded successfully'
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_my_complaints(request):
    """Site Engineer: Get complaints assigned to me"""
    try:
        user_id = request.user['user_id']
        
        complaints = fetch_all("""
            SELECT c.id, c.title, c.description, c.status, c.priority, c.created_at,
                   s.site_name, s.customer_name,
                   u.full_name as raised_by_name
            FROM complaints c
            JOIN sites s ON c.site_id = s.id
            LEFT JOIN users u ON c.raised_by = u.id
            WHERE c.assigned_to = %s
            ORDER BY c.created_at DESC
        """, (user_id,))
        
        return Response({
            'complaints': [
                {
                    'id': str(c['id']),
                    'title': c['title'],
                    'description': c['description'],
                    'status': c['status'],
                    'priority': c['priority'],
                    'site_name': c['site_name'],
                    'customer_name': c['customer_name'],
                    'raised_by': c['raised_by_name'],
                    'created_at': c['created_at'].isoformat() if c['created_at'] else None
                }
                for c in complaints
            ]
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def upload_rectification_proof(request):
    """Site Engineer: Upload rectification proof for complaint"""
    try:
        complaint_id = request.data.get('complaint_id')
        image_url = request.data.get('image_url')
        resolution_notes = request.data.get('resolution_notes', '')
        
        if not all([complaint_id, image_url]):
            return Response({'error': 'complaint_id and image_url are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Update complaint
        execute_query("""
            UPDATE complaints 
            SET status = 'RESOLVED', 
                resolved_at = %s, 
                proof_image_url = %s,
                resolution_notes = %s
            WHERE id = %s
        """, (timezone.now(), image_url, resolution_notes, complaint_id))
        
        return Response({
            'message': 'Rectification proof uploaded successfully'
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ============================================
# ACCOUNTANT APIS
# ============================================

@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_labour_entries_for_verification(request):
    """Accountant: Get labour entries for verification"""
    try:
        date = request.query_params.get('date', datetime.now().date())
        
        entries = fetch_all("""
            SELECT le.id, le.labour_count, le.labour_type, le.entry_time, le.notes,
                   le.is_modified, le.modification_reason,
                   s.site_name, s.customer_name,
                   u.full_name as supervisor_name
            FROM labour_entries le
            JOIN sites s ON le.site_id = s.id
            JOIN users u ON le.supervisor_id = u.id
            WHERE le.entry_date = %s
            ORDER BY s.site_name
        """, (date,))
        
        return Response({
            'entries': [
                {
                    'id': str(e['id']),
                    'labour_count': e['labour_count'],
                    'labour_type': e['labour_type'],
                    'site_name': e['site_name'],
                    'customer_name': e['customer_name'],
                    'supervisor_name': e['supervisor_name'],
                    'is_modified': e['is_modified'],
                    'modification_reason': e['modification_reason'],
                    'entry_time': e['entry_time'].isoformat() if e['entry_time'] else None
                }
                for e in entries
            ]
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['PUT'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def modify_labour_count(request, entry_id):
    """Accountant: Modify labour count (only accountant can do this)"""
    try:
        user_id = request.user['user_id']
        new_count = request.data.get('labour_count')
        reason = request.data.get('reason', '')
        
        if new_count is None:
            return Response({'error': 'labour_count is required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Update labour entry
        execute_query("""
            UPDATE labour_entries 
            SET labour_count = %s, 
                is_modified = TRUE,
                modified_by = %s,
                modified_at = %s,
                modification_reason = %s
            WHERE id = %s
        """, (new_count, user_id, timezone.now(), reason, entry_id))
        
        # Log the modification
        log_id = str(uuid.uuid4())
        execute_query("""
            INSERT INTO audit_logs 
            (id, action, table_name, record_id, performed_by, new_values)
            VALUES (%s, 'MODIFY_LABOUR_COUNT', 'labour_entries', %s, %s, %s)
        """, (log_id, entry_id, user_id, f'{{"new_count": {new_count}, "reason": "{reason}"}}'))
        
        return Response({
            'message': 'Labour count modified successfully'
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def upload_material_bill(request):
    """Accountant: Upload material bill"""
    try:
        user_id = request.user['user_id']
        site_id = request.data.get('site_id')
        material_type = request.data.get('material_type')
        quantity = request.data.get('quantity')
        unit = request.data.get('unit', 'units')
        price_per_unit = request.data.get('price_per_unit')
        total_amount = request.data.get('total_amount')
        bill_number = request.data.get('bill_number', '')
        bill_url = request.data.get('bill_url', '')
        vendor_name = request.data.get('vendor_name', '')
        bill_date = request.data.get('bill_date', datetime.now().date())
        
        if not all([site_id, material_type, quantity, total_amount]):
            return Response({'error': 'Required fields missing'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        bill_id = str(uuid.uuid4())
        execute_query("""
            INSERT INTO bills 
            (id, site_id, material_type, quantity, unit, price_per_unit, total_amount,
             bill_number, bill_url, vendor_name, uploaded_by, bill_date)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """, (bill_id, site_id, material_type, quantity, unit, price_per_unit, 
              total_amount, bill_number, bill_url, vendor_name, user_id, bill_date))
        
        return Response({
            'message': 'Material bill uploaded successfully',
            'bill_id': bill_id
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def upload_extra_work(request):
    """Accountant: Upload extra work bill"""
    try:
        user_id = request.user['user_id']
        site_id = request.data.get('site_id')
        description = request.data.get('description')
        amount = request.data.get('amount')
        bill_url = request.data.get('bill_url', '')
        due_date = request.data.get('due_date')
        
        if not all([site_id, description, amount]):
            return Response({'error': 'Required fields missing'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        work_id = str(uuid.uuid4())
        execute_query("""
            INSERT INTO extra_works 
            (id, site_id, description, amount, bill_url, due_date, uploaded_by)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
        """, (work_id, site_id, description, amount, bill_url, due_date, user_id))
        
        return Response({
            'message': 'Extra work uploaded successfully',
            'work_id': work_id
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# Continue in next part...


# ============================================
# CHANGE REQUEST SYSTEM
# ============================================

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def request_change(request):
    """
    Supervisor: Request a change for an entry
    POST /api/construction/request-change/
    """
    try:
        user_id = request.user['user_id']
        entry_id = request.data.get('entry_id')
        entry_type = request.data.get('entry_type')  # 'LABOUR' or 'MATERIAL'
        request_message = request.data.get('request_message')
        
        if not all([entry_id, entry_type, request_message]):
            return Response({'error': 'entry_id, entry_type, and request_message are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Ensure entry_type is uppercase to match database constraint
        entry_type = entry_type.upper()
        
        # Create change request
        change_request_id = str(uuid.uuid4())
        execute_query("""
            INSERT INTO change_requests 
            (id, entry_type, entry_id, requested_by, request_note, status)
            VALUES (%s, %s, %s, %s, %s, 'PENDING')
        """, (change_request_id, entry_type, entry_id, user_id, request_message))
        
        return Response({
            'message': 'Change request submitted successfully',
            'request_id': change_request_id
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_my_change_requests(request):
    """
    Supervisor: Get my change requests
    GET /api/construction/my-change-requests/
    """
    try:
        user_id = request.user['user_id']
        
        requests_data = fetch_all("""
            SELECT 
                cr.id,
                cr.entry_id,
                cr.entry_type,
                cr.request_note,
                cr.status,
                cr.created_at,
                cr.accountant_notes,
                cr.reviewed_at,
                u.full_name as handled_by_name
            FROM change_requests cr
            LEFT JOIN users u ON cr.reviewed_by = u.id
            WHERE cr.requested_by = %s
            ORDER BY cr.created_at DESC
        """, (user_id,))
        
        return Response({
            'change_requests': [
                {
                    'id': str(r['id']),
                    'entry_id': str(r['entry_id']),
                    'entry_type': r['entry_type'],
                    'request_message': r['request_note'],
                    'status': r['status'],
                    'created_at': r['created_at'].isoformat() if r['created_at'] else None,
                    'response_message': r['accountant_notes'],
                    'handled_at': r['reviewed_at'].isoformat() if r['reviewed_at'] else None,
                    'handled_by_name': r['handled_by_name'],
                }
                for r in requests_data
            ]
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_pending_change_requests(request):
    """
    Accountant: Get all pending change requests with site information
    GET /api/construction/pending-change-requests/
    Optional query param: site_id (filter by specific site)
    """
    try:
        site_id = request.query_params.get('site_id')
        
        requests_data = fetch_all("""
            SELECT 
                cr.id,
                cr.entry_id,
                cr.entry_type,
                cr.request_note,
                cr.status,
                cr.created_at,
                u.full_name as requested_by_name,
                u.username as requested_by_username,
                r.role_name as requested_by_role
            FROM change_requests cr
            JOIN users u ON cr.requested_by = u.id
            JOIN roles r ON u.role_id = r.id
            WHERE cr.status = 'PENDING'
            ORDER BY cr.created_at DESC
        """)
        
        # Get entry details for each request
        result = []
        for req in requests_data:
            entry_details = None
            entry_site_id = None
            
            if req['entry_type'] == 'LABOUR':
                entry_details = fetch_one("""
                    SELECT l.labour_type, l.labour_count, l.entry_date, l.site_id,
                           s.site_name, s.area, s.street
                    FROM labour_entries l
                    JOIN sites s ON l.site_id = s.id
                    WHERE l.id = %s
                """, (req['entry_id'],))
                if entry_details:
                    entry_site_id = str(entry_details['site_id'])
            else:  # MATERIAL
                entry_details = fetch_one("""
                    SELECT m.material_type, m.quantity, m.unit, m.entry_date, m.site_id,
                           s.site_name, s.area, s.street
                    FROM material_balances m
                    JOIN sites s ON m.site_id = s.id
                    WHERE m.id = %s
                """, (req['entry_id'],))
                if entry_details:
                    entry_site_id = str(entry_details['site_id'])
            
            # Filter by site_id if provided
            if site_id and entry_site_id != site_id:
                continue
            
            result.append({
                'id': str(req['id']),
                'entry_id': str(req['entry_id']),
                'entry_type': req['entry_type'],
                'request_message': req['request_note'],
                'status': req['status'],
                'created_at': req['created_at'].isoformat() if req['created_at'] else None,
                'requested_by_name': req['requested_by_name'],
                'requested_by_username': req['requested_by_username'],
                'requested_by_role': req['requested_by_role'],
                'site_id': entry_site_id,
                'entry_details': entry_details if entry_details else {}
            })
        
        return Response({
            'change_requests': result
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def handle_change_request(request, request_id):
    """
    Accountant: Handle a change request (modify the entry)
    POST /api/construction/handle-change-request/<request_id>/
    """
    try:
        user_id = request.user['user_id']
        new_value = request.data.get('new_value')  # New count/quantity
        response_message = request.data.get('response_message', '')
        
        if new_value is None:
            return Response({'error': 'new_value is required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Get change request details
        change_req = fetch_one("""
            SELECT entry_id, entry_type FROM change_requests WHERE id = %s
        """, (request_id,))
        
        if not change_req:
            return Response({'error': 'Change request not found'}, 
                          status=status.HTTP_404_NOT_FOUND)
        
        # Update the entry
        if change_req['entry_type'] == 'LABOUR':
            execute_query("""
                UPDATE labour_entries 
                SET labour_count = %s,
                    is_modified = TRUE,
                    modified_by = %s,
                    modified_at = %s,
                    modification_reason = %s
                WHERE id = %s
            """, (new_value, user_id, timezone.now(), response_message, change_req['entry_id']))
        else:  # MATERIAL
            execute_query("""
                UPDATE material_balances 
                SET quantity = %s,
                    is_modified = TRUE,
                    modified_by = %s,
                    modified_at = %s,
                    modification_reason = %s
                WHERE id = %s
            """, (new_value, user_id, timezone.now(), response_message, change_req['entry_id']))
        
        # Update change request status
        execute_query("""
            UPDATE change_requests 
            SET status = 'COMPLETED',
                reviewed_by = %s,
                reviewed_at = %s,
                accountant_notes = %s
            WHERE id = %s
        """, (user_id, timezone.now(), response_message, request_id))
        
        return Response({
            'message': 'Change request handled successfully'
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_modified_entries(request):
    """
    Get modified entries (for both supervisor and accountant)
    GET /api/construction/modified-entries/
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        # For supervisors, show only their modified entries
        # For accountants, show all modified entries
        if user_role == 'Supervisor':
            labour_query = """
                SELECT 
                    l.id, l.labour_type, l.labour_count, l.entry_date, l.entry_time,
                    l.is_modified, l.modified_at, l.modification_reason,
                    s.site_name, s.area, s.street,
                    u.full_name as modified_by_name
                FROM labour_entries l
                JOIN sites s ON l.site_id = s.id
                LEFT JOIN users u ON l.modified_by = u.id
                WHERE l.supervisor_id = %s AND l.is_modified = TRUE
                ORDER BY l.modified_at DESC
            """
            labour_params = (user_id,)
            
            material_query = """
                SELECT 
                    m.id, m.material_type, m.quantity, m.unit, m.entry_date, m.updated_at,
                    m.is_modified, m.modified_at, m.modification_reason,
                    s.site_name, s.area, s.street,
                    u.full_name as modified_by_name
                FROM material_balances m
                JOIN sites s ON m.site_id = s.id
                LEFT JOIN users u ON m.modified_by = u.id
                WHERE m.supervisor_id = %s AND m.is_modified = TRUE
                ORDER BY m.modified_at DESC
            """
            material_params = (user_id,)
        else:  # Accountant
            labour_query = """
                SELECT 
                    l.id, l.labour_type, l.labour_count, l.entry_date, l.entry_time,
                    l.is_modified, l.modified_at, l.modification_reason,
                    s.site_name, s.area, s.street,
                    u.full_name as modified_by_name,
                    u2.full_name as supervisor_name
                FROM labour_entries l
                JOIN sites s ON l.site_id = s.id
                LEFT JOIN users u ON l.modified_by = u.id
                LEFT JOIN users u2 ON l.supervisor_id = u2.id
                WHERE l.is_modified = TRUE
                ORDER BY l.modified_at DESC
            """
            labour_params = None
            
            material_query = """
                SELECT 
                    m.id, m.material_type, m.quantity, m.unit, m.entry_date, m.updated_at,
                    m.is_modified, m.modified_at, m.modification_reason,
                    s.site_name, s.area, s.street,
                    u.full_name as modified_by_name,
                    u2.full_name as supervisor_name
                FROM material_balances m
                JOIN sites s ON m.site_id = s.id
                LEFT JOIN users u ON m.modified_by = u.id
                LEFT JOIN users u2 ON m.supervisor_id = u2.id
                WHERE m.is_modified = TRUE
                ORDER BY m.modified_at DESC
            """
            material_params = None
        
        labour_entries = fetch_all(labour_query, labour_params)
        material_entries = fetch_all(material_query, material_params)
        
        return Response({
            'labour_entries': [
                {
                    'id': str(e['id']),
                    'labour_type': e['labour_type'],
                    'labour_count': e['labour_count'],
                    'entry_date': e['entry_time'].isoformat() if e['entry_time'] else None,
                    'site_name': e['site_name'],
                    'area': e['area'],
                    'street': e['street'],
                    'is_modified': e['is_modified'],
                    'modified_at': e['modified_at'].isoformat() if e['modified_at'] else None,
                    'modification_reason': e['modification_reason'],
                    'modified_by_name': e['modified_by_name'],
                    'supervisor_name': e.get('supervisor_name'),
                }
                for e in labour_entries
            ],
            'material_entries': [
                {
                    'id': str(e['id']),
                    'material_type': e['material_type'],
                    'quantity': float(e['quantity']),
                    'unit': e['unit'],
                    'entry_date': e['updated_at'].isoformat() if e['updated_at'] else None,
                    'site_name': e['site_name'],
                    'area': e['area'],
                    'street': e['street'],
                    'is_modified': e['is_modified'],
                    'modified_at': e['modified_at'].isoformat() if e['modified_at'] else None,
                    'modification_reason': e['modification_reason'],
                    'modified_by_name': e['modified_by_name'],
                    'supervisor_name': e.get('supervisor_name'),
                }
                for e in material_entries
            ]
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ============================================
# HISTORY APIS
# ============================================

@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_supervisor_history(request):
    """Get ALL entry history from ALL supervisors and site engineers (UNMODIFIED entries only) - optionally filtered by site"""
    try:
        user_role = request.user.get('role', '')
        
        # Allow supervisors, site engineers, and accountants to access this endpoint
        if user_role not in ['Supervisor', 'Site Engineer', 'Accountant']:
            return Response({'error': 'Only supervisors, site engineers, and accountants can access history'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        site_id = request.GET.get('site_id')  # Optional site filter
        user_id = request.user.get('user_id')
        
        # Base query conditions
        base_conditions = "WHERE (l.is_modified = FALSE OR l.is_modified IS NULL)"
        params = []
        
        # All roles (Supervisor, Site Engineer, Accountant) see ALL entries for the site
        # No user_id filter — history is shared across all supervisors/engineers
        
        # Add site filter if provided
        if site_id:
            base_conditions += " AND l.site_id = %s"
            params.append(site_id)
        
        # Get labour entries (only unmodified) with timestamps, extra costs and admin-set rates
        # Use CASE to fall back to canonical defaults when no admin rate is set
        labour_query = f"""
            SELECT
                l.id,
                l.site_id,
                l.labour_type,
                l.labour_count,
                l.entry_date,
                l.entry_time,
                l.notes,
                l.extra_cost,
                l.extra_cost_notes,
                l.submitted_by_role,
                s.site_name,
                s.customer_name,
                s.area,
                s.street,
                u.full_name as supervisor_name,
                r.role_name as user_role,
                COALESCE(lsr.daily_rate,
                    CASE l.labour_type
                        WHEN 'General' THEN 600
                        WHEN 'Mason' THEN 800
                        WHEN 'Helper' THEN 500
                        WHEN 'Carpenter' THEN 750
                        WHEN 'Plumber' THEN 700
                        WHEN 'Electrician' THEN 750
                        WHEN 'Painter' THEN 650
                        WHEN 'Tile Layer' THEN 700
                        WHEN 'Tile Layerhelper' THEN 700
                        WHEN 'Kambi Fitter' THEN 900
                        WHEN 'Concrete Kot' THEN 950
                        WHEN 'Pile Labour' THEN 800
                        ELSE 900
                    END
                ) AS daily_rate,
                (l.labour_count * COALESCE(lsr.daily_rate,
                    CASE l.labour_type
                        WHEN 'General' THEN 600
                        WHEN 'Mason' THEN 800
                        WHEN 'Helper' THEN 500
                        WHEN 'Carpenter' THEN 750
                        WHEN 'Plumber' THEN 700
                        WHEN 'Electrician' THEN 750
                        WHEN 'Painter' THEN 650
                        WHEN 'Tile Layer' THEN 700
                        WHEN 'Tile Layerhelper' THEN 700
                        WHEN 'Kambi Fitter' THEN 900
                        WHEN 'Concrete Kot' THEN 950
                        WHEN 'Pile Labour' THEN 800
                        ELSE 900
                    END
                )) AS total_cost
            FROM labour_entries l
            JOIN sites s ON l.site_id = s.id
            JOIN users u ON l.supervisor_id = u.id
            LEFT JOIN roles r ON u.role_id = r.id
            LEFT JOIN (
                SELECT DISTINCT ON (labour_type) labour_type, daily_rate
                FROM labour_salary_rates
                WHERE site_id IS NULL AND is_active = TRUE
                ORDER BY labour_type, effective_from DESC
            ) lsr ON lsr.labour_type = l.labour_type
            {base_conditions}
            ORDER BY l.entry_time DESC
            LIMIT 200
        """
        labour_entries = fetch_all(labour_query, params)
        
        # Get material entries (only unmodified) with timestamps and extra costs
        material_base_conditions = "WHERE 1=1"
        material_params = []
        
        # Material history is visible to ALL supervisors of the site — no user_id filter
        # (any supervisor can see all material entries for the site)
        
        if site_id:
            material_base_conditions += " AND m.site_id = %s"
            material_params.append(site_id)
        
        material_query = f"""
            SELECT 
                m.id,
                m.site_id,
                m.material_type,
                m.quantity_used as quantity,
                m.unit,
                m.usage_date as entry_date,
                m.created_at as updated_at,
                0 as extra_cost,
                m.notes as extra_cost_notes,
                s.site_name,
                s.customer_name,
                s.area,
                s.street,
                u.full_name as supervisor_name
            FROM material_usage m
            JOIN sites s ON m.site_id = s.id
            JOIN users u ON m.supervisor_id = u.id
            {material_base_conditions}
            ORDER BY m.created_at DESC
            LIMIT 200
        """
        material_entries = fetch_all(material_query, material_params)
        
        return Response({
            'labour_entries': [
                {
                    'id': str(e['id']),
                    'site_id': str(e['site_id']),
                    'labour_type': e['labour_type'],
                    'labour_count': e['labour_count'],
                    'entry_date': e['entry_date'].isoformat() if e['entry_date'] else None,
                    'entry_time': pytz.utc.localize(e['entry_time']).astimezone(pytz.timezone('Asia/Kolkata')).isoformat() if e['entry_time'] else None,
                    'extra_cost': float(e['extra_cost']) if e.get('extra_cost') else 0,
                    'extra_cost_notes': e.get('extra_cost_notes', ''),
                    'site_name': e['site_name'],
                    'customer_name': e['customer_name'],
                    'area': e['area'],
                    'street': e['street'],
                    'supervisor_name': e['supervisor_name'],
                    'user_role': e.get('user_role', ''),
                    'submitted_by_role': e.get('submitted_by_role', e.get('user_role', 'Supervisor')),
                    'daily_rate': float(e['daily_rate']) if e.get('daily_rate') else None,
                    'total_cost': float(e['total_cost']) if e.get('total_cost') else None,
                    'notes': e.get('notes', ''),
                }
                for e in labour_entries
            ],
            'material_entries': [
                {
                    'id': str(e['id']),
                    'site_id': str(e['site_id']),
                    'material_type': e['material_type'],
                    'quantity': float(e['quantity']),
                    'unit': e['unit'],
                    'entry_date': e['entry_date'].isoformat() if e['entry_date'] else None,
                    'updated_at': pytz.utc.localize(e['updated_at']).astimezone(pytz.timezone('Asia/Kolkata')).isoformat() if e['updated_at'] else None,
                    'timestamp': pytz.utc.localize(e['updated_at']).astimezone(pytz.timezone('Asia/Kolkata')).isoformat() if e['updated_at'] else None,  # For compatibility
                    'extra_cost': float(e['extra_cost']) if e.get('extra_cost') else 0,
                    'extra_cost_notes': e.get('extra_cost_notes', ''),
                    'site_name': e['site_name'],
                    'customer_name': e['customer_name'],
                    'area': e['area'],
                    'street': e['street'],
                    'supervisor_name': e['supervisor_name'],
                    'notes': e.get('notes', ''),
                }
                for e in material_entries
            ],
            'site_filter': site_id,
            'total_labour_entries': len(labour_entries),
            'total_material_entries': len(material_entries),
            'message': 'Showing entries from ALL supervisors and sites'
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_all_entries_for_accountant(request):
    """Get all entries with supervisor names and roles for accountant"""
    try:
        user_role = request.user.get('role', '')
        
        # Only accountants and admins can access this endpoint (but allow supervisors for testing)
        if user_role not in ['Accountant', 'Supervisor', 'Admin']:
            return Response({'error': 'Only accountants and admins can access this data'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        # Get labour entries directly from CASH_ENTRIES table (approved entries only)
        # Cash entries are the source of truth for what the accountant has confirmed
        labour_query = """
            SELECT
                ce.id,
                ce.site_id,
                ce.labour_type,
                ce.labour_count,
                ce.entry_date,
                ce.created_at as entry_time,
                '' as notes,
                0 as extra_cost,
                '' as extra_cost_notes,
                ce.source_type as submitted_by_role,
                s.site_name,
                s.customer_name,
                s.area,
                s.street,
                COALESCE(u.full_name, u.phone) as supervisor_name,
                u.username as supervisor_username,
                r.role_name as user_role,
                ce.daily_rate,
                ce.total_cost
            FROM cash_entries ce
            JOIN sites s ON ce.site_id = s.id
            LEFT JOIN users u ON ce.accountant_id = u.id
            LEFT JOIN roles r ON u.role_id = r.id
            ORDER BY ce.created_at DESC
            LIMIT 200
        """
        try:
            from .database import get_db_connection
            with get_db_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute(labour_query)
                    rows = cur.fetchall()
                    if rows:
                        columns = [desc[0] for desc in cur.description]
                        labour_entries = [dict(zip(columns, row)) for row in rows]
                    else:
                        labour_entries = []
            print(f"✅ [ACCOUNTANT DIRECT] Got {len(labour_entries)} labour rows")
        except Exception as db_err:
            print(f"❌ [ACCOUNTANT DIRECT] Labour query failed: {db_err}")
            import traceback; traceback.print_exc()
            return Response({'error': f'Labour query failed: {str(db_err)}'}, status=500)
        
        # Get material entries with supervisor names, roles, timestamps, extra costs, and submitted_by_role
        material_query = """
            SELECT
                m.id,
                m.site_id,
                m.material_type,
                m.quantity_used as quantity,
                m.unit,
                m.usage_date as entry_date,
                m.created_at as updated_at,
                0 as extra_cost,
                m.notes as extra_cost_notes,
                'Supervisor' as submitted_by_role,
                s.site_name,
                s.customer_name,
                s.area,
                s.street,
                COALESCE(u.full_name, 'Unknown') as supervisor_name,
                COALESCE(u.username, '') as supervisor_username,
                COALESCE(r.role_name, 'Unknown') as user_role
            FROM material_usage m
            JOIN sites s ON m.site_id = s.id
            LEFT JOIN users u ON m.supervisor_id = u.id
            LEFT JOIN roles r ON u.role_id = r.id
            ORDER BY m.created_at DESC
            LIMIT 200
        """
        material_entries = fetch_all(material_query)

        # Get extra costs for all sites
        extra_costs_query = """
            SELECT
                e.id,
                e.site_id,
                e.description,
                e.amount,
                e.uploaded_at as entry_date,
                u.full_name as submitted_by_name,
                u.username as submitted_by_username,
                r.role_name as submitted_by_role,
                s.site_name,
                s.customer_name,
                s.area,
                s.street
            FROM extra_works e
            JOIN users u ON e.uploaded_by = u.id
            JOIN roles r ON u.role_id = r.id
            JOIN sites s ON e.site_id = s.id
            ORDER BY e.uploaded_at DESC
            LIMIT 200
        """
        extra_costs = fetch_all(extra_costs_query)

        # Sum labour_count from cash_entries table (total workers approved)
        approved_count_result = fetch_one("""
            SELECT COALESCE(SUM(labour_count), 0) as count
            FROM cash_entries
        """)
        approved_entries_count = approved_count_result['count'] if approved_count_result else 0

        # Debug logging BEFORE creating response
        print(f"📊 [ACCOUNTANT API] Returning {len(labour_entries)} labour entries, {len(material_entries)} material entries, {len(extra_costs)} extra costs")
        print(f"📊 [ACCOUNTANT API] Total labour count from cash_entries: {approved_entries_count}")
        total_salary = sum(float(e.get('total_cost', 0) or 0) for e in labour_entries)
        print(f"💰 [ACCOUNTANT API] Total salary: ₹{total_salary}")

        response_data = {
            'labour_entries': [
                {
                    'id': str(e['id']),
                    'site_id': str(e['site_id']),
                    'labour_type': e['labour_type'],
                    'labour_count': e['labour_count'],
                    'entry_date': e['entry_date'].isoformat() if e['entry_date'] else None,
                    'entry_time': e['entry_time'].isoformat() if e['entry_time'] else None,
                    'extra_cost': float(e['extra_cost']) if e.get('extra_cost') else 0,
                    'extra_cost_notes': e.get('extra_cost_notes', ''),
                    'submitted_by_role': e.get('submitted_by_role', 'Supervisor'),
                    'site_name': e['site_name'],
                    'customer_name': e['customer_name'],
                    'area': e['area'],
                    'street': e['street'],
                    'supervisor_name': e['supervisor_name'],
                    'user_role': e['user_role'],
                    'notes': e.get('notes', ''),
                    'daily_rate': float(e['daily_rate']) if e.get('daily_rate') else None,
                    'total_cost': float(e['total_cost']) if e.get('total_cost') else None,
                }
                for e in labour_entries
            ],
            'material_entries': [
                {
                    'id': str(e['id']),
                    'site_id': str(e['site_id']),
                    'material_type': e['material_type'],
                    'quantity': float(e['quantity']),
                    'unit': e['unit'],
                    'entry_date': e['entry_date'].isoformat() if e['entry_date'] else None,
                    'updated_at': e['updated_at'].isoformat() if e['updated_at'] else None,
                    'extra_cost': float(e['extra_cost']) if e.get('extra_cost') else 0,
                    'extra_cost_notes': e.get('extra_cost_notes', ''),
                    'submitted_by_role': e.get('submitted_by_role', 'Supervisor'),
                    'site_name': e['site_name'],
                    'customer_name': e['customer_name'],
                    'area': e['area'],
                    'street': e['street'],
                    'supervisor_name': e['supervisor_name'],
                    'user_role': e['user_role'],
                    'notes': e.get('notes', ''),
                }
                for e in material_entries
            ],
            'extra_costs': [
                {
                    'id': str(e['id']),
                    'site_id': str(e['site_id']),
                    'description': e['description'],
                    'amount': float(e['amount']) if e.get('amount') else 0,
                    'entry_date': e['entry_date'].isoformat() if e.get('entry_date') else None,
                    'submitted_by_name': e.get('submitted_by_name', ''),
                    'submitted_by_role': e.get('submitted_by_role', ''),
                    'site_name': e['site_name'],
                    'customer_name': e['customer_name'],
                    'area': e['area'],
                    'street': e['street'],
                }
                for e in extra_costs
            ],
            'total_labour_entries': approved_entries_count,  # Count of distinct approved entries
            'total_material_entries': len(material_entries),
            'total_extra_costs': len(extra_costs),
            'message': 'Showing approved entries from ALL supervisors and sites for accountant'
        }
        
        return Response(response_data, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)



@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_entries_by_date_and_role(request):
    """
    Accountant: Get labour entries by date and role for comparison
    GET /api/construction/entries-by-date-role/?date=YYYY-MM-DD&role=Supervisor
    """
    try:
        user_role = request.user.get('role', '')
        
        if user_role != 'Accountant':
            return Response({'error': 'Only Accountant can access this endpoint'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        date_str = request.query_params.get('date')
        role = request.query_params.get('role')  # 'Supervisor' or 'Site Engineer'
        
        print(f"🔍 [BACKEND] get_entries_by_date_and_role called - date: {date_str}, role: {role}")
        
        if not date_str:
            return Response({'error': 'date is required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Parse date
        try:
            entry_date = datetime.strptime(date_str, '%Y-%m-%d').date()
        except ValueError:
            return Response({'error': 'Invalid date format. Use YYYY-MM-DD'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Build query based on role
        if role == 'Supervisor':
            # Get supervisor entries (where submitted_by_role is 'Supervisor' or NULL - default to Supervisor)
            query = """
                SELECT
                    l.id,
                    l.site_id,
                    s.site_name,
                    s.customer_name,
                    l.supervisor_id,
                    u.full_name as submitted_by,
                    l.labour_type,
                    l.labour_count,
                    l.entry_date,
                    l.entry_time,
                    l.entry_time as submitted_at
                FROM labour_entries l
                JOIN sites s ON l.site_id = s.id
                JOIN users u ON l.supervisor_id = u.id
                WHERE l.entry_date = %s
                  AND (l.submitted_by_role = 'Supervisor' OR l.submitted_by_role IS NULL)
                  AND NOT EXISTS (
                    SELECT 1 FROM cash_entries ce
                    WHERE ce.site_id = l.site_id AND ce.entry_date = l.entry_date
                  )
                ORDER BY l.site_id, l.entry_time DESC
            """
        elif role == 'Site Engineer':
            # Get site engineer entries from labour_entries table (submitted_by_role = 'Site Engineer')
            query = """
                SELECT
                    l.id,
                    l.site_id,
                    s.site_name,
                    s.customer_name,
                    l.supervisor_id as engineer_id,
                    u.full_name as submitted_by,
                    l.labour_type,
                    l.labour_count,
                    l.entry_date,
                    l.entry_time,
                    l.entry_time as submitted_at
                FROM labour_entries l
                JOIN sites s ON l.site_id = s.id
                JOIN users u ON l.supervisor_id = u.id
                WHERE l.entry_date = %s AND l.submitted_by_role = 'Site Engineer'
                  AND NOT EXISTS (
                    SELECT 1 FROM cash_entries ce
                    WHERE ce.site_id = l.site_id AND ce.entry_date = l.entry_date
                  )
                ORDER BY l.site_id, l.entry_time DESC
            """
        elif role == 'Accountant':
            # Get accountant (custom) entries from labour_entries table (submitted_by_role = 'Accountant')
            query = """
                SELECT
                    l.id,
                    l.site_id,
                    s.site_name,
                    s.customer_name,
                    l.submitted_by_id,
                    u.full_name as submitted_by,
                    l.labour_type,
                    l.labour_count,
                    l.entry_date,
                    l.created_at as entry_time,
                    l.created_at as submitted_at
                FROM labour_entries l
                JOIN sites s ON l.site_id = s.id
                LEFT JOIN users u ON l.submitted_by_id = u.id
                WHERE l.entry_date = %s AND l.submitted_by_role = 'Accountant'
                  AND NOT EXISTS (
                    SELECT 1 FROM cash_entries ce
                    WHERE ce.site_id = l.site_id AND ce.entry_date = l.entry_date
                  )
                ORDER BY l.site_id, l.created_at DESC
            """
        else:
            # Get both
            query = """
                SELECT
                    l.id,
                    l.site_id,
                    s.site_name,
                    s.customer_name,
                    'Supervisor' as role,
                    u.full_name as submitted_by,
                    l.labour_type,
                    l.labour_count,
                    l.entry_date,
                    l.entry_time as submitted_at
                FROM labour_entries l
                JOIN sites s ON l.site_id = s.id
                JOIN users u ON l.supervisor_id = u.id
                WHERE l.entry_date = %s
                  AND (l.submitted_by_role = 'Supervisor' OR l.submitted_by_role IS NULL)
                  AND NOT EXISTS (
                    SELECT 1 FROM cash_entries ce
                    WHERE ce.site_id = l.site_id AND ce.entry_date = l.entry_date
                  )

                UNION ALL

                SELECT
                    l.id,
                    l.site_id,
                    s.site_name,
                    s.customer_name,
                    'Site Engineer' as role,
                    u.full_name as submitted_by,
                    l.labour_type,
                    l.labour_count,
                    l.entry_date,
                    l.entry_time as submitted_at
                FROM labour_entries l
                JOIN sites s ON l.site_id = s.id
                JOIN users u ON l.supervisor_id = u.id
                WHERE l.entry_date = %s AND l.submitted_by_role = 'Site Engineer'
                  AND NOT EXISTS (
                    SELECT 1 FROM cash_entries ce
                    WHERE ce.site_id = l.site_id AND ce.entry_date = l.entry_date
                  )

                ORDER BY site_id, submitted_at DESC
            """
            entries = fetch_all(query, (entry_date, entry_date))
        
        if role in ['Supervisor', 'Site Engineer']:
            entries = fetch_all(query, (entry_date,))
        
        print(f"📊 [BACKEND] Found {len(entries)} raw entries")
        
        # Group by site
        sites_data = {}
        for entry in entries:
            site_id = str(entry['site_id'])
            if site_id not in sites_data:
                customer_name = entry.get('customer_name', '')
                site_name = entry.get('site_name', '')
                display_name = f"{customer_name} {site_name}" if customer_name else site_name
                
                sites_data[site_id] = {
                    'site_id': site_id,
                    'site_name': display_name,
                    'submitted_by': entry['submitted_by'],
                    'submitted_at': entry['submitted_at'].isoformat() if entry.get('submitted_at') else None,
                    'labour_entries': []
                }
            
            sites_data[site_id]['labour_entries'].append({
                'labour_type': entry['labour_type'],
                'labour_count': entry['labour_count'],
            })
        
        result = list(sites_data.values())
        print(f"✅ [BACKEND] Returning {len(result)} sites with entries")
        if result:
            print(f"📊 [BACKEND] First site: {result[0]}")
        
        return Response(result, status=status.HTTP_200_OK)
        
    except Exception as e:
        print(f"❌ [BACKEND] Error fetching entries by date and role: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_approved_entries(request):
    """
    Accountant: Get approved entries grouped by site and date
    GET /api/construction/approved-entries/?date=YYYY-MM-DD
    """
    try:
        user_role = request.user.get('role', '')

        if user_role != 'Accountant':
            return Response({'error': 'Only Accountant can access this endpoint'},
                          status=status.HTTP_403_FORBIDDEN)

        date_str = request.query_params.get('date')

        if not date_str:
            return Response({'error': 'date is required'},
                          status=status.HTTP_400_BAD_REQUEST)

        try:
            entry_date = datetime.strptime(date_str, '%Y-%m-%d').date()
        except ValueError:
            return Response({'error': 'Invalid date format. Use YYYY-MM-DD'},
                          status=status.HTTP_500_INTERNAL_SERVER_ERROR)

        from collections import defaultdict
        print(f"🔍 [APPROVED ENTRIES] Loading for date: {entry_date}")

        # Debug: Check if cash_entries table has any data for this date
        debug_check = fetch_all("SELECT COUNT(*) as count FROM cash_entries WHERE entry_date = %s", (entry_date,))
        print(f"🔍 [DEBUG] Total cash_entries for {entry_date}: {debug_check[0]['count'] if debug_check else 0}")

        # Step 1: Get unique approved sites+dates from cash_entries
        # First, get just the unique combinations without aggregation
        unique_combinations = fetch_all("""
            SELECT DISTINCT
                ce.site_id,
                ce.entry_date,
                ce.source_type
            FROM cash_entries ce
            WHERE ce.entry_date = %s
            ORDER BY ce.site_id
        """, (entry_date,))

        print(f"✅ [APPROVED ENTRIES] Found {len(unique_combinations)} unique site+date+source combinations")

        # Now enrich with site and user info
        approved_meta = []
        for combo in unique_combinations:
            site_id = combo['site_id']
            combo_date = combo['entry_date']
            source_type = combo['source_type']

            # Get site info including area and street
            site_info = fetch_one("""
                SELECT CONCAT(customer_name, ' ', site_name) as site_name, area, street
                FROM sites
                WHERE id = %s
            """, (site_id,))

            # Get accountant info (from first entry for this site+date)
            acc_info = fetch_one("""
                SELECT ce.accountant_id, COALESCE(u.full_name, u.phone) as approved_by, ce.created_at
                FROM cash_entries ce
                LEFT JOIN users u ON ce.accountant_id = u.id
                WHERE ce.site_id = %s AND ce.entry_date = %s
                LIMIT 1
            """, (site_id, combo_date))

            print(f"🔍 [APPROVED] acc_info for site {site_id}: {acc_info}")

            if site_info:
                approved_by_name = 'Unknown'
                if acc_info:
                    approved_by_name = acc_info.get('approved_by') or acc_info.get('accountant_id') or 'Unknown'
                    print(f"  accountant_id: {acc_info.get('accountant_id')}, approved_by: {acc_info.get('approved_by')}")

                approved_meta.append({
                    'site_id': site_id,
                    'site_name': site_info['site_name'],
                    'area': site_info.get('area', ''),
                    'street': site_info.get('street', ''),
                    'entry_date': combo_date,
                    'source_type': source_type,
                    'approved_at': acc_info['created_at'] if acc_info else None,
                    'approved_by': approved_by_name,
                })

        print(f"✅ [APPROVED ENTRIES] Enriched with site info: {len(approved_meta)} entries")

        print(f"✅ [APPROVED ENTRIES] Found {len(approved_meta)} approved sites")

        if not approved_meta:
            print(f"ℹ️ [APPROVED ENTRIES] No entries found for {entry_date}")
            return Response({'approved_entries': []}, status=status.HTTP_200_OK)

        # Step 2: Get approved (confirmed) labour rows from cash_entries
        selected_rows = fetch_all("""
            SELECT site_id, entry_date, source_type,
                   labour_type, labour_count, daily_rate, total_cost
            FROM cash_entries
            WHERE entry_date = %s
            ORDER BY site_id
        """, (entry_date,))

        print(f"✅ [APPROVED ENTRIES] Found {len(selected_rows)} labour rows in cash_entries")
        if selected_rows:
            print(f"   Sample: {selected_rows[0]}")

        # Step 3: Get original labour_entries for all approved sites (both roles)
        site_ids = tuple(a['site_id'] for a in approved_meta)
        print(f"🔍 [APPROVED ENTRIES] Site IDs to fetch: {site_ids}")

        if site_ids:
            # Use individual site queries if ANY() doesn't work
            original_entries = []
            for sid in site_ids:
                entries = fetch_all("""
                    SELECT site_id, entry_date, labour_type, labour_count, submitted_by_role
                    FROM labour_entries
                    WHERE site_id = %s AND entry_date = %s
                    ORDER BY submitted_by_role
                """, (sid, entry_date))
                original_entries.extend(entries)
        else:
            original_entries = []

        print(f"✅ [APPROVED ENTRIES] Found {len(original_entries)} original labour entries")

        # Group cash entry labour rows by site_id
        from collections import defaultdict
        selected_by_site = defaultdict(list)
        for row in selected_rows:
            site_id_str = str(row['site_id'])
            selected_by_site[site_id_str].append({
                'labour_type': row['labour_type'],
                'labour_count': row['labour_count'],
                'daily_rate': float(row['daily_rate']) if row['daily_rate'] else None,
                'total_cost': float(row['total_cost']) if row['total_cost'] else None,
            })

        # Group original entries by site_id + role
        supervisor_by_site = defaultdict(list)
        engineer_by_site = defaultdict(list)
        accountant_by_site = defaultdict(list)
        for e in original_entries:
            site_id_str = str(e['site_id'])
            role = (e.get('submitted_by_role') or '').lower()
            entry_item = {
                'labour_type': e['labour_type'],
                'labour_count': e['labour_count'],
            }
            if 'accountant' in role:
                accountant_by_site[site_id_str].append(entry_item)
            elif 'engineer' in role:
                engineer_by_site[site_id_str].append(entry_item)
            else:
                supervisor_by_site[site_id_str].append(entry_item)

        # Build final list
        result = []
        for meta in approved_meta:
            sid = str(meta['site_id'])
            result.append({
                'site_id': sid,
                'site_name': meta['site_name'],
                'area': meta.get('area', ''),
                'street': meta.get('street', ''),
                'entry_date': meta['entry_date'].isoformat() if meta['entry_date'] else None,
                'source_type': meta['source_type'],
                'approved_at': meta['approved_at'].isoformat() if meta['approved_at'] else None,
                'approved_by': meta['approved_by'],
                'selected_entries': selected_by_site[sid],
                'supervisor_entries': supervisor_by_site[sid],
                'site_engineer_entries': engineer_by_site[sid],
                'accountant_entries': accountant_by_site[sid],
            })

        return Response({'approved_entries': result}, status=status.HTTP_200_OK)

    except Exception as e:
        print(f"❌ [APPROVED] Error: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_entries_by_date(request):
    """Get entries for a specific site and date"""
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        site_id = request.query_params.get('site_id')
        date_str = request.query_params.get('date')
        
        if not site_id or not date_str:
            return Response({'error': 'site_id and date are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Parse date
        try:
            entry_date = datetime.strptime(date_str, '%Y-%m-%d').date()
        except ValueError:
            return Response({'error': 'Invalid date format. Use YYYY-MM-DD'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Build WHERE clause based on user role
        # Only show entries submitted by the current user
        user_filter = " AND l.supervisor_id = %s"
        labour_params = (site_id, entry_date, user_id)
        print(f"🔍 [ENTRIES_BY_DATE] Loading entries for site, user={user_id} (role: {user_role})")
        
        # Get labour entries for this site and date
        labour_query = f"""
            SELECT
                l.id,
                l.supervisor_id,
                l.labour_type,
                l.labour_count,
                l.entry_date,
                l.entry_time,
                l.notes,
                l.extra_cost,
                l.extra_cost_notes,
                l.submitted_by_role,
                COALESCE(u.full_name, u.phone) as supervisor_name,
                lsr.daily_rate,
                (l.labour_count * COALESCE(lsr.daily_rate, 0)) AS total_cost
            FROM labour_entries l
            LEFT JOIN users u ON l.supervisor_id = u.id
            LEFT JOIN (
                SELECT DISTINCT ON (labour_type) labour_type, daily_rate
                FROM labour_salary_rates
                WHERE site_id IS NULL AND is_active = TRUE
                ORDER BY labour_type, effective_from DESC
            ) lsr ON lsr.labour_type = l.labour_type
            WHERE l.site_id = %s AND l.entry_date = %s {user_filter}
            ORDER BY l.entry_time DESC
        """
        print(f"🔍 [ENTRIES_BY_DATE] Query params: {labour_params}")
        labour_entries = fetch_all(labour_query, labour_params)
        print(f"🔍 [ENTRIES_BY_DATE] Returned {len(labour_entries)} labour entries")
        
        # Get material entries for this site and date for current supervisor only
        material_query = """
            SELECT
                m.id,
                m.material_type,
                m.quantity_used as quantity,
                m.unit,
                m.usage_date as entry_date,
                m.created_at as updated_at,
                0 as extra_cost,
                m.notes as extra_cost_notes
            FROM material_usage m
            WHERE m.site_id = %s AND m.usage_date = %s AND m.supervisor_id = %s
            ORDER BY m.created_at DESC
        """
        material_entries = fetch_all(material_query, (site_id, entry_date, user_id))
        
        # Check if current supervisor already submitted material today for this site
        material_submitted_today = len(material_entries) > 0
        
        # Get photo count for this site, date, and supervisor
        photo_count_result = fetch_one("""
            SELECT COUNT(*) as count
            FROM site_photos
            WHERE site_id = %s AND upload_date = %s AND uploaded_by = %s
        """, (site_id, entry_date, user_id))
        photo_count = photo_count_result['count'] if photo_count_result else 0
        
        # Check if any site engineer submitted entries for this site today
        # (separate from current user's entries, for lock detection)
        site_engineer_check = fetch_one("""
            SELECT DISTINCT
                COALESCE(u.full_name, u.phone) as supervisor_name
            FROM labour_entries le
            LEFT JOIN users u ON le.supervisor_id = u.id
            WHERE le.site_id = %s AND le.entry_date = %s AND le.submitted_by_role = 'Site Engineer'
            LIMIT 1
        """, (site_id, entry_date))
        has_site_engineer_entry = site_engineer_check is not None
        site_engineer_name = site_engineer_check['supervisor_name'] if site_engineer_check else None
        
        return Response({
            'labour_entries': [
                {
                    'id': str(e['id']),
                    'supervisor_id': str(e['supervisor_id']) if e.get('supervisor_id') else None,
                    'labour_type': e['labour_type'],
                    'labour_count': e['labour_count'],
                    'entry_date': e['entry_date'].isoformat() if e['entry_date'] else None,
                    'entry_time': e['entry_time'].isoformat() if e['entry_time'] else None,
                    'notes': e.get('notes', ''),
                    'extra_cost': float(e['extra_cost']) if e.get('extra_cost') else 0,
                    'extra_cost_notes': e.get('extra_cost_notes', ''),
                    'daily_rate': float(e['daily_rate']) if e.get('daily_rate') else None,
                    'total_cost': float(e['total_cost']) if e.get('total_cost') else None,
                    'entry_type': e.get('entry_type', 'morning'),
                    'submitted_by_role': e.get('submitted_by_role', ''),
                    'supervisor_name': e.get('supervisor_name', ''),
                }
                for e in labour_entries
            ],
            'material_entries': [
                {
                    'id': str(e['id']),
                    'material_type': e['material_type'],
                    'quantity': float(e['quantity']),
                    'unit': e['unit'],
                    'entry_date': e['entry_date'].isoformat() if e['entry_date'] else None,
                    'updated_at': e['updated_at'].isoformat() if e['updated_at'] else None,
                    'extra_cost': float(e['extra_cost']) if e.get('extra_cost') else 0,
                    'extra_cost_notes': e.get('extra_cost_notes', ''),
                }
                for e in material_entries
            ],
            'photo_count': photo_count,
            'material_submitted_today': material_submitted_today,
            'has_site_engineer_entry': has_site_engineer_entry,
            'site_engineer_name': site_engineer_name,
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_today_entries_for_supervisor(request):
    """
    Get today's entries for supervisor with IST timezone
    GET /api/construction/today-entries/
    Query params: site_id (optional - if provided, filter by site)
    """
    try:
        user_id = request.user['user_id']
        site_id = request.query_params.get('site_id')
        
        # Get current IST date
        from django.utils import timezone
        import pytz
        ist = pytz.timezone('Asia/Kolkata')
        now_ist = timezone.now().astimezone(ist)
        today = now_ist.date()
        
        # Build base queries
        labour_query = """
            SELECT
                l.id,
                l.site_id,
                l.labour_type,
                l.labour_count,
                l.entry_date,
                l.entry_time,
                l.notes,
                l.extra_cost,
                l.extra_cost_notes,
                s.site_name,
                s.area,
                s.street,
                lsr.daily_rate,
                (l.labour_count * COALESCE(lsr.daily_rate, 0)) AS total_cost
            FROM labour_entries l
            JOIN sites s ON l.site_id = s.id
            LEFT JOIN (
                SELECT DISTINCT ON (labour_type) labour_type, daily_rate
                FROM labour_salary_rates
                WHERE site_id IS NULL AND is_active = TRUE
                ORDER BY labour_type, effective_from DESC
            ) lsr ON lsr.labour_type = l.labour_type
            WHERE l.supervisor_id = %s AND l.entry_date = %s
        """
        
        material_query = """
            SELECT 
                m.id,
                m.site_id,
                m.material_type,
                m.quantity,
                m.unit,
                m.entry_date,
                m.updated_at,
                m.extra_cost,
                m.extra_cost_notes,
                s.site_name,
                s.area,
                s.street
            FROM material_balances m
            JOIN sites s ON m.site_id = s.id
            WHERE m.supervisor_id = %s AND m.entry_date = %s
        """
        
        params = [user_id, today]
        
        # Add site filter if provided
        if site_id:
            labour_query += " AND l.site_id = %s"
            material_query += " AND m.site_id = %s"
            params.append(site_id)
        
        labour_query += " ORDER BY l.entry_time DESC"
        material_query += " ORDER BY m.updated_at DESC"
        
        labour_entries = fetch_all(labour_query, tuple(params))
        material_entries = fetch_all(material_query, tuple(params))
        
        return Response({
            'date': today.isoformat(),
            'current_ist_time': now_ist.strftime('%I:%M %p'),
            'labour_entries': [
                {
                    'id': str(e['id']),
                    'site_id': str(e['site_id']),
                    'labour_type': e['labour_type'],
                    'labour_count': e['labour_count'],
                    'entry_date': e['entry_date'].isoformat() if e['entry_date'] else None,
                    'entry_time': e['entry_time'].strftime('%I:%M %p') if e['entry_time'] else None,
                    'notes': e.get('notes', ''),
                    'extra_cost': float(e['extra_cost']) if e.get('extra_cost') else 0,
                    'extra_cost_notes': e.get('extra_cost_notes', ''),
                    'site_name': e['site_name'],
                    'area': e['area'],
                    'street': e['street'],
                    'daily_rate': float(e['daily_rate']) if e.get('daily_rate') else None,
                    'total_cost': float(e['total_cost']) if e.get('total_cost') else None,
                }
                for e in labour_entries
            ],
            'material_entries': [
                {
                    'id': str(e['id']),
                    'site_id': str(e['site_id']),
                    'material_type': e['material_type'],
                    'quantity': float(e['quantity']),
                    'unit': e['unit'],
                    'entry_date': e['entry_date'].isoformat() if e['entry_date'] else None,
                    'updated_at': e['updated_at'].strftime('%I:%M %p') if e['updated_at'] else None,
                    'extra_cost': float(e['extra_cost']) if e.get('extra_cost') else 0,
                    'extra_cost_notes': e.get('extra_cost_notes', ''),
                    'site_name': e['site_name'],
                    'area': e['area'],
                    'street': e['street'],
                }
                for e in material_entries
            ]
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_aggregated_today_entries(request):
    """
    Get today's aggregated labour entries with time_of_day (morning/evening)
    GET /api/construction/aggregated-today-entries/
    Query params: site_id (optional - if provided, filter by site)
    
    Returns entries grouped by time_of_day with aggregated labour data
    """
    try:
        user_id = request.user['user_id']
        site_id = request.query_params.get('site_id')
        
        # Get current IST date
        import pytz
        ist = pytz.timezone('Asia/Kolkata')
        now_ist = timezone.now().astimezone(ist)
        today = now_ist.date()
        
        # Query to get all labour entries for today
        query = """
            SELECT
                l.id,
                l.site_id,
                l.labour_type,
                l.labour_count,
                l.entry_date,
                l.entry_time,
                l.notes,
                l.extra_cost,
                l.extra_cost_notes,
                s.site_name,
                s.customer_name,
                s.area,
                s.street,
                lsr.daily_rate
            FROM labour_entries l
            JOIN sites s ON l.site_id = s.id
            LEFT JOIN (
                SELECT DISTINCT ON (labour_type) labour_type, daily_rate
                FROM labour_salary_rates
                WHERE site_id IS NULL AND is_active = TRUE
                ORDER BY labour_type, effective_from DESC
            ) lsr ON lsr.labour_type = l.labour_type
            WHERE l.supervisor_id = %s AND l.entry_date = %s
        """

        params = [user_id, today]

        if site_id:
            query += " AND l.site_id = %s"
            params.append(site_id)
        
        query += " ORDER BY l.entry_time ASC"
        
        labour_entries = fetch_all(query, tuple(params))
        
        # Group entries by site and time_of_day
        # Morning: before 2 PM (14:00), Evening: 2 PM and after
        aggregated_entries = {}
        
        for entry in labour_entries:
            site_key = str(entry['site_id'])
            
            # Determine time_of_day based on entry_time
            entry_time = entry['entry_time']
            if entry_time.hour < 14:
                time_of_day = 'morning'
            else:
                time_of_day = 'evening'
            
            # Create unique key for site + time_of_day
            key = f"{site_key}_{time_of_day}"
            
            if key not in aggregated_entries:
                aggregated_entries[key] = {
                    'site_id': site_key,
                    'site_name': entry['site_name'],
                    'customer_name': entry['customer_name'],
                    'area': entry['area'],
                    'street': entry['street'],
                    'time_of_day': time_of_day,
                    'entry_time': entry['entry_time'],
                    'entry_date': entry['entry_date'],
                    'labour_data': {},
                    'total_workers': 0,
                    'total_salary': 0.0,
                    'extra_cost': 0.0,
                    'extra_cost_notes': ''
                }
            
            # Add labour count to aggregated data
            labour_type = entry['labour_type']
            labour_count = entry['labour_count']
            daily_rate = float(entry['daily_rate']) if entry.get('daily_rate') else 0.0
            
            aggregated_entries[key]['labour_data'][labour_type] = labour_count
            aggregated_entries[key]['total_workers'] += labour_count
            aggregated_entries[key]['total_salary'] += labour_count * daily_rate
            
            # Aggregate extra costs
            if entry.get('extra_cost'):
                aggregated_entries[key]['extra_cost'] += float(entry['extra_cost'])
            if entry.get('extra_cost_notes'):
                if aggregated_entries[key]['extra_cost_notes']:
                    aggregated_entries[key]['extra_cost_notes'] += '; ' + entry['extra_cost_notes']
                else:
                    aggregated_entries[key]['extra_cost_notes'] = entry['extra_cost_notes']
        
        # Convert to list and format response
        entries_list = []
        for entry_data in aggregated_entries.values():
            entries_list.append({
                'site_id': entry_data['site_id'],
                'site_name': entry_data['site_name'],
                'customer_name': entry_data['customer_name'],
                'area': entry_data['area'],
                'street': entry_data['street'],
                'time_of_day': entry_data['time_of_day'],
                'entry_time': entry_data['entry_time'].isoformat() if entry_data['entry_time'] else None,
                'entry_date': entry_data['entry_date'].isoformat() if entry_data['entry_date'] else None,
                'labour_data': entry_data['labour_data'],
                'total_workers': entry_data['total_workers'],
                'total_salary': entry_data['total_salary'],
                'extra_cost': entry_data['extra_cost'],
                'extra_cost_notes': entry_data['extra_cost_notes']
            })
        
        return Response({
            'success': True,
            'date': today.isoformat(),
            'current_ist_time': now_ist.strftime('%I:%M %p'),
            'entries': entries_list
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        print(f"Error in get_aggregated_today_entries: {str(e)}")
        return Response({
            'success': False,
            'error': str(e)
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ============================================
# SITE ENGINEER PHOTO UPLOAD APIS
# ============================================

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def upload_site_photo(request):
    """
    Site Engineer: Upload work photo (morning or evening)
    POST /api/construction/upload-site-photo/
    """
    try:
        from django.core.files.storage import default_storage
        from django.conf import settings
        import os
        
        user_id = request.user['user_id']
        site_id = request.data.get('site_id')
        update_type = request.data.get('update_type')  # 'STARTED' or 'FINISHED'
        description = request.data.get('description', '')
        photo = request.FILES.get('photo')
        
        if not all([site_id, update_type, photo]):
            return Response({'error': 'site_id, update_type, and photo are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Validate update type
        if update_type not in ['STARTED', 'FINISHED']:
            return Response({'error': 'update_type must be STARTED or FINISHED'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        today = datetime.now().date()
        
        # Check if already uploaded today
        existing = fetch_one("""
            SELECT id FROM work_updates
            WHERE site_id = %s AND engineer_id = %s 
            AND update_type = %s AND update_date = %s
        """, (site_id, user_id, update_type, today))
        
        if existing:
            return Response({'error': f'{update_type} photo already uploaded today'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Create media directory if it doesn't exist
        media_dir = os.path.join(settings.MEDIA_ROOT, 'site_photos')
        os.makedirs(media_dir, exist_ok=True)
        
        # Generate unique filename
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        ext = os.path.splitext(photo.name)[1]
        filename = f"{site_id}_{update_type}_{timestamp}{ext}"
        filepath = os.path.join('site_photos', filename)
        
        # Save file
        saved_path = default_storage.save(filepath, photo)
        image_url = f"{settings.MEDIA_URL}{saved_path}"
        
        # Insert into database
        update_id = str(uuid.uuid4())
        execute_query("""
            INSERT INTO work_updates 
            (id, site_id, engineer_id, update_type, image_url, description, update_date)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
        """, (update_id, site_id, user_id, update_type, image_url, description, today))
        
        return Response({
            'message': f'{update_type} photo uploaded successfully',
            'update_id': update_id,
            'image_url': image_url
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_site_photos(request, site_id):
    """
    Get all photos for a specific site
    GET /api/construction/site-photos/<site_id>/
    """
    try:
        photos = fetch_all("""
            SELECT 
                w.id,
                w.update_type,
                w.image_url,
                w.description,
                w.update_date,
                w.uploaded_at,
                u.full_name as uploaded_by,
                r.role_name as uploaded_by_role
            FROM work_updates w
            JOIN users u ON w.engineer_id = u.id
            JOIN roles r ON u.role_id = r.id
            WHERE w.site_id = %s
            ORDER BY w.uploaded_at DESC
        """, (site_id,))
        
        return Response({
            'photos': [
                {
                    'id': str(p['id']),
                    'update_type': p['update_type'],
                    'image_url': p['image_url'],
                    'description': p['description'],
                    'update_date': p['update_date'].isoformat() if p['update_date'] else None,
                    'created_at': p['uploaded_at'].isoformat() if p['uploaded_at'] else None,
                    'uploaded_by': p['uploaded_by'],
                    'uploaded_by_role': p['uploaded_by_role'],
                }
                for p in photos
            ]
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_all_site_photos_for_accountant(request):
    """
    Accountant: Get all photos from all sites with site information
    GET /api/construction/accountant/all-photos/
    """
    try:
        user_role = request.user.get('role', '')
        
        # Only accountants and admins can access this endpoint
        if user_role not in ['Accountant', 'Supervisor', 'Admin']:  # Allow supervisors for testing
            return Response({'error': 'Only accountants and admins can access this data'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        # Get optional filters
        site_id = request.query_params.get('site_id')
        update_type = request.query_params.get('update_type')  # 'STARTED', 'FINISHED', 'PROGRESS'
        date_from = request.query_params.get('date_from')
        date_to = request.query_params.get('date_to')
        
        # Build query with filters
        query = """
            SELECT 
                w.id,
                w.site_id,
                w.update_type,
                w.image_url,
                w.description,
                w.update_date,
                w.uploaded_at,
                s.site_name,
                s.customer_name,
                s.area,
                s.street,
                u.full_name as uploaded_by,
                r.role_name as uploaded_by_role
            FROM work_updates w
            JOIN sites s ON w.site_id = s.id
            JOIN users u ON w.engineer_id = u.id
            JOIN roles r ON u.role_id = r.id
            WHERE 1=1
        """
        params = []
        
        # Add filters
        if site_id:
            query += " AND w.site_id = %s"
            params.append(site_id)
        
        if update_type:
            query += " AND w.update_type = %s"
            params.append(update_type)
        
        if date_from:
            query += " AND w.update_date >= %s"
            params.append(date_from)
        
        if date_to:
            query += " AND w.update_date <= %s"
            params.append(date_to)
        
        query += " ORDER BY w.uploaded_at DESC LIMIT 200"
        
        photos = fetch_all(query, tuple(params) if params else None)
        
        return Response({
            'photos': [
                {
                    'id': str(p['id']),
                    'site_id': str(p['site_id']),
                    'site_name': p['site_name'],
                    'customer_name': p['customer_name'],
                    'full_site_name': f"{p['customer_name']} {p['site_name']}".strip(),
                    'area': p['area'],
                    'street': p['street'],
                    'update_type': p['update_type'],
                    'image_url': p['image_url'],
                    'description': p['description'],
                    'update_date': p['update_date'].isoformat() if p['update_date'] else None,
                    'uploaded_at': p['uploaded_at'].isoformat() if p['uploaded_at'] else None,
                    'uploaded_by': p['uploaded_by'],
                    'uploaded_by_role': p['uploaded_by_role'],
                }
                for p in photos
            ],
            'total_photos': len(photos),
            'filters_applied': {
                'site_id': site_id,
                'update_type': update_type,
                'date_from': date_from,
                'date_to': date_to,
            }
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_today_upload_status(request, site_id):
    """
    Check if morning/evening photos uploaded today
    GET /api/construction/today-upload-status/<site_id>/
    """
    try:
        user_id = request.user['user_id']
        today = datetime.now().date()
        
        # Check morning upload
        morning = fetch_one("""
            SELECT id FROM work_updates
            WHERE site_id = %s AND engineer_id = %s 
            AND update_type = 'STARTED' AND update_date = %s
        """, (site_id, user_id, today))
        
        # Check evening upload
        evening = fetch_one("""
            SELECT id FROM work_updates
            WHERE site_id = %s AND engineer_id = %s 
            AND update_type = 'FINISHED' AND update_date = %s
        """, (site_id, user_id, today))
        
        return Response({
            'morning_uploaded': morning is not None,
            'evening_uploaded': evening is not None,
            'date': today.isoformat()
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ============================================
# ARCHITECT APIs
# ============================================

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def upload_architect_document(request):
    """
    Architect: Upload documents (plans, designs, drawings)
    POST /api/construction/upload-architect-document/
    """
    try:
        from django.core.files.storage import default_storage
        from django.conf import settings
        from .time_utils import get_day_of_week
        import os
        
        user_id = request.user['user_id']
        site_id = request.data.get('site_id')
        document_type = request.data.get('document_type')  # 'Floor Plan', 'Elevation', 'Structure Drawing', 'Design', 'Other'
        title = request.data.get('title', '')
        description = request.data.get('description', '')
        file = request.FILES.get('file')
        
        if not all([site_id, document_type, title, file]):
            return Response({'error': 'site_id, document_type, title, and file are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Validate document type
        valid_types = ['Floor Plan', 'Elevation', 'Structure Drawing', 'Design', 'Other']
        if document_type not in valid_types:
            return Response({'error': f'document_type must be one of: {", ".join(valid_types)}'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Create media directory if it doesn't exist
        media_dir = os.path.join(settings.MEDIA_ROOT, 'architect_documents')
        os.makedirs(media_dir, exist_ok=True)
        
        # Generate unique filename
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        ext = os.path.splitext(file.name)[1]
        filename = f"{site_id}_{document_type.replace(' ', '_')}_{timestamp}{ext}"
        filepath = os.path.join('architect_documents', filename)
        
        # Save file
        saved_path = default_storage.save(filepath, file)
        file_url = f"{settings.MEDIA_URL}{saved_path}"
        
        # Get current date and day of week
        today = datetime.now().date()
        day_of_week = get_day_of_week(datetime.now())
        
        # Insert into database
        document_id = str(uuid.uuid4())
        execute_query("""
            INSERT INTO architect_documents 
            (id, site_id, architect_id, document_type, title, description, file_url, file_name, file_size, upload_date, day_of_week)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """, (document_id, site_id, user_id, document_type, title, description, file_url, file.name, file.size, today, day_of_week))
        
        return Response({
            'message': f'{document_type} uploaded successfully',
            'document_id': document_id,
            'file_url': file_url,
            'upload_date': today.isoformat(),
            'day_of_week': day_of_week
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def upload_architect_complaint(request):
    """
    Architect: Upload complaints
    POST /api/construction/upload-architect-complaint/
    """
    try:
        from .time_utils import get_day_of_week
        
        user_id = request.user['user_id']
        site_id = request.data.get('site_id')
        title = request.data.get('title')
        description = request.data.get('description')
        priority = request.data.get('priority', 'MEDIUM')  # 'LOW', 'MEDIUM', 'HIGH', 'URGENT'
        
        if not all([site_id, title, description]):
            return Response({'error': 'site_id, title, and description are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Validate priority
        valid_priorities = ['LOW', 'MEDIUM', 'HIGH', 'URGENT']
        if priority not in valid_priorities:
            return Response({'error': f'priority must be one of: {", ".join(valid_priorities)}'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Get current date and day of week
        today = datetime.now().date()
        day_of_week = get_day_of_week(datetime.now())
        
        # Get site engineer for this site (for assignment)
        site_engineer = fetch_one("""
            SELECT u.id FROM users u
            JOIN roles r ON u.role_id = r.id
            WHERE r.role_name = 'Site Engineer'
            LIMIT 1
        """)
        
        # Insert complaint
        complaint_id = str(uuid.uuid4())
        execute_query("""
            INSERT INTO architect_complaints 
            (id, site_id, architect_id, title, description, priority, assigned_to, upload_date, day_of_week)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        """, (complaint_id, site_id, user_id, title, description, priority, 
              site_engineer['id'] if site_engineer else None, today, day_of_week))
        
        return Response({
            'message': 'Complaint submitted successfully',
            'complaint_id': complaint_id,
            'upload_date': today.isoformat(),
            'day_of_week': day_of_week,
            'assigned_to': 'Site Engineer' if site_engineer else 'Unassigned'
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_architect_documents(request):
    """
    Get architect documents with optional filters
    GET /api/construction/architect-documents/
    Query params: site_id, document_type, date_from, date_to
    """
    try:
        user_role = request.user.get('role', '')
        
        # Allow architects, accountants, and supervisors to access this endpoint
        if user_role not in ['Architect', 'Accountant', 'Supervisor']:
            return Response({'error': 'Only architects, accountants, and supervisors can access this data'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        # Get optional filters
        site_id = request.query_params.get('site_id')
        document_type = request.query_params.get('document_type')
        date_from = request.query_params.get('date_from')
        date_to = request.query_params.get('date_to')
        
        # Build query with filters
        query = """
            SELECT 
                ad.id,
                ad.site_id,
                ad.document_type,
                ad.title,
                ad.description,
                ad.file_url,
                ad.file_name,
                ad.file_size,
                ad.upload_date,
                ad.day_of_week,
                ad.uploaded_at,
                s.site_name,
                s.customer_name,
                s.area,
                s.street,
                u.full_name as architect_name
            FROM architect_documents ad
            JOIN sites s ON ad.site_id = s.id
            JOIN users u ON ad.architect_id = u.id
            WHERE ad.is_active = TRUE
        """
        params = []
        
        # Add filters
        if site_id:
            query += " AND ad.site_id = %s"
            params.append(site_id)
        
        if document_type:
            query += " AND ad.document_type = %s"
            params.append(document_type)
        
        if date_from:
            query += " AND ad.upload_date >= %s"
            params.append(date_from)
        
        if date_to:
            query += " AND ad.upload_date <= %s"
            params.append(date_to)
        
        query += " ORDER BY ad.uploaded_at DESC LIMIT 200"
        
        documents = fetch_all(query, tuple(params) if params else None)
        
        return Response({
            'documents': [
                {
                    'id': str(d['id']),
                    'site_id': str(d['site_id']),
                    'site_name': d['site_name'],
                    'customer_name': d['customer_name'],
                    'full_site_name': f"{d['customer_name']} {d['site_name']}".strip(),
                    'area': d['area'],
                    'street': d['street'],
                    'document_type': d['document_type'],
                    'title': d['title'],
                    'description': d['description'],
                    'file_url': d['file_url'],
                    'file_name': d['file_name'],
                    'file_size': d['file_size'],
                    'upload_date': d['upload_date'].isoformat() if d['upload_date'] else None,
                    'day_of_week': d['day_of_week'],
                    'uploaded_at': d['uploaded_at'].isoformat() if d['uploaded_at'] else None,
                    'architect_name': d['architect_name'],
                }
                for d in documents
            ],
            'total_documents': len(documents),
            'filters_applied': {
                'site_id': site_id,
                'document_type': document_type,
                'date_from': date_from,
                'date_to': date_to,
            }
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_architect_complaints(request):
    """
    Get architect complaints with optional filters
    GET /api/construction/architect-complaints/
    Query params: site_id, status, priority, date_from, date_to
    """
    try:
        user_role = request.user.get('role', '')
        
        # Allow architects, accountants, site engineers, and supervisors to access this endpoint
        if user_role not in ['Architect', 'Accountant', 'Site Engineer', 'Supervisor']:
            return Response({'error': 'Only architects, accountants, site engineers, and supervisors can access this data'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        # Get optional filters
        site_id = request.query_params.get('site_id')
        complaint_status = request.query_params.get('status')
        priority = request.query_params.get('priority')
        date_from = request.query_params.get('date_from')
        date_to = request.query_params.get('date_to')
        
        # Build query with filters
        query = """
            SELECT 
                ac.id,
                ac.site_id,
                ac.title,
                ac.description,
                ac.priority,
                ac.status,
                ac.resolution_notes,
                ac.resolved_at,
                ac.upload_date,
                ac.day_of_week,
                ac.uploaded_at,
                s.site_name,
                s.customer_name,
                s.area,
                s.street,
                u1.full_name as architect_name,
                u2.full_name as assigned_to_name
            FROM architect_complaints ac
            JOIN sites s ON ac.site_id = s.id
            JOIN users u1 ON ac.architect_id = u1.id
            LEFT JOIN users u2 ON ac.assigned_to = u2.id
            WHERE 1=1
        """
        params = []
        
        # Add filters
        if site_id:
            query += " AND ac.site_id = %s"
            params.append(site_id)
        
        if complaint_status:
            query += " AND ac.status = %s"
            params.append(complaint_status)
        
        if priority:
            query += " AND ac.priority = %s"
            params.append(priority)
        
        if date_from:
            query += " AND ac.upload_date >= %s"
            params.append(date_from)
        
        if date_to:
            query += " AND ac.upload_date <= %s"
            params.append(date_to)
        
        query += " ORDER BY ac.uploaded_at DESC LIMIT 200"
        
        complaints = fetch_all(query, tuple(params) if params else None)
        
        return Response({
            'complaints': [
                {
                    'id': str(c['id']),
                    'site_id': str(c['site_id']),
                    'site_name': c['site_name'],
                    'customer_name': c['customer_name'],
                    'full_site_name': f"{c['customer_name']} {c['site_name']}".strip(),
                    'area': c['area'],
                    'street': c['street'],
                    'title': c['title'],
                    'description': c['description'],
                    'priority': c['priority'],
                    'status': c['status'],
                    'resolution_notes': c['resolution_notes'],
                    'resolved_at': c['resolved_at'].isoformat() if c['resolved_at'] else None,
                    'upload_date': c['upload_date'].isoformat() if c['upload_date'] else None,
                    'day_of_week': c['day_of_week'],
                    'uploaded_at': c['uploaded_at'].isoformat() if c['uploaded_at'] else None,
                    'architect_name': c['architect_name'],
                    'assigned_to_name': c['assigned_to_name'],
                }
                for c in complaints
            ],
            'total_complaints': len(complaints),
            'filters_applied': {
                'site_id': site_id,
                'status': complaint_status,
                'priority': priority,
                'date_from': date_from,
                'date_to': date_to,
            }
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_architect_history(request):
    """
    Get architect history (documents and complaints) grouped by date with dropdown functionality
    GET /api/construction/architect-history/
    Query params: site_id (optional)
    """
    try:
        user_role = request.user.get('role', '')
        
        # Allow architects and accountants to access this endpoint
        if user_role not in ['Architect', 'Accountant']:
            return Response({'error': 'Only architects and accountants can access this data'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        site_id = request.query_params.get('site_id')
        
        # Get documents
        doc_query = """
            SELECT 
                ad.id,
                ad.site_id,
                ad.document_type,
                ad.title,
                ad.description,
                ad.file_url,
                ad.upload_date,
                ad.day_of_week,
                ad.uploaded_at,
                s.site_name,
                s.customer_name,
                u.full_name as architect_name,
                'DOCUMENT' as entry_type
            FROM architect_documents ad
            JOIN sites s ON ad.site_id = s.id
            JOIN users u ON ad.architect_id = u.id
            WHERE ad.is_active = TRUE
        """
        doc_params = []
        
        if site_id:
            doc_query += " AND ad.site_id = %s"
            doc_params.append(site_id)
        
        # Get complaints
        complaint_query = """
            SELECT 
                ac.id,
                ac.site_id,
                ac.title,
                ac.description,
                ac.priority,
                ac.status,
                ac.upload_date,
                ac.day_of_week,
                ac.uploaded_at,
                s.site_name,
                s.customer_name,
                u.full_name as architect_name,
                'COMPLAINT' as entry_type
            FROM architect_complaints ac
            JOIN sites s ON ac.site_id = s.id
            JOIN users u ON ac.architect_id = u.id
            WHERE 1=1
        """
        complaint_params = []
        
        if site_id:
            complaint_query += " AND ac.site_id = %s"
            complaint_params.append(site_id)
        
        documents = fetch_all(doc_query, tuple(doc_params) if doc_params else None)
        complaints = fetch_all(complaint_query, tuple(complaint_params) if complaint_params else None)
        
        return Response({
            'documents': [
                {
                    'id': str(d['id']),
                    'site_id': str(d['site_id']),
                    'site_name': d['site_name'],
                    'customer_name': d['customer_name'],
                    'full_site_name': f"{d['customer_name']} {d['site_name']}".strip(),
                    'document_type': d['document_type'],
                    'title': d['title'],
                    'description': d['description'],
                    'file_url': d['file_url'],
                    'upload_date': d['upload_date'].isoformat() if d['upload_date'] else None,
                    'day_of_week': d['day_of_week'],
                    'uploaded_at': d['uploaded_at'].isoformat() if d['uploaded_at'] else None,
                    'architect_name': d['architect_name'],
                    'entry_type': 'DOCUMENT',
                }
                for d in documents
            ],
            'complaints': [
                {
                    'id': str(c['id']),
                    'site_id': str(c['site_id']),
                    'site_name': c['site_name'],
                    'customer_name': c['customer_name'],
                    'full_site_name': f"{c['customer_name']} {c['site_name']}".strip(),
                    'title': c['title'],
                    'description': c['description'],
                    'priority': c['priority'],
                    'status': c['status'],
                    'upload_date': c['upload_date'].isoformat() if c['upload_date'] else None,
                    'day_of_week': c['day_of_week'],
                    'uploaded_at': c['uploaded_at'].isoformat() if c['uploaded_at'] else None,
                    'architect_name': c['architect_name'],
                    'entry_type': 'COMPLAINT',
                }
                for c in complaints
            ],
            'site_filter': site_id,
            'total_documents': len(documents),
            'total_complaints': len(complaints),
            'message': 'Architect history loaded successfully'
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def upload_project_file(request):
    """
    Architect: Upload project files (estimation, plans, floor plans)
    POST /api/construction/upload-project-file/
    """
    try:
        from django.core.files.storage import default_storage
        from django.conf import settings
        import os
        
        user_id = request.user['user_id']
        site_id = request.data.get('site_id')
        file_type = request.data.get('file_type')  # 'ESTIMATION', 'FLOOR_PLAN', 'ELEVATION', 'STRUCTURE', 'DESIGN', 'OTHER'
        title = request.data.get('title', '')
        description = request.data.get('description', '')
        file = request.FILES.get('file')
        
        # For estimation
        amount = request.data.get('amount')
        is_plan_extended = request.data.get('is_plan_extended', False)
        
        if not all([site_id, file_type, file]):
            return Response({'error': 'site_id, file_type, and file are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Create media directory if it doesn't exist
        media_dir = os.path.join(settings.MEDIA_ROOT, 'project_files')
        os.makedirs(media_dir, exist_ok=True)
        
        # Generate unique filename
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        ext = os.path.splitext(file.name)[1]
        filename = f"{site_id}_{file_type}_{timestamp}{ext}"
        filepath = os.path.join('project_files', filename)
        
        # Save file
        saved_path = default_storage.save(filepath, file)
        file_url = f"{settings.MEDIA_URL}{saved_path}"
        
        # Insert into database
        file_id = str(uuid.uuid4())
        execute_query("""
            INSERT INTO project_files 
            (id, site_id, uploaded_by, file_type, file_url, title, description, amount, is_plan_extended, uploaded_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
        """, (file_id, site_id, user_id, file_type, file_url, title, description, amount, is_plan_extended))
        
        return Response({
            'message': f'{file_type} file uploaded successfully',
            'file_id': file_id,
            'file_url': file_url
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_project_files(request, site_id):
    """
    Get all project files for a specific site
    GET /api/construction/project-files/<site_id>/
    """
    try:
        file_type = request.query_params.get('file_type')  # Optional filter
        
        query = """
            SELECT 
                pf.id,
                pf.file_type,
                pf.file_url,
                pf.title,
                pf.description,
                pf.amount,
                pf.is_plan_extended,
                pf.uploaded_at,
                u.full_name as uploaded_by,
                r.role_name as uploaded_by_role
            FROM project_files pf
            JOIN users u ON pf.uploaded_by = u.id
            JOIN roles r ON u.role_id = r.id
            WHERE pf.site_id = %s
        """
        params = [site_id]
        
        if file_type:
            query += " AND pf.file_type = %s"
            params.append(file_type)
        
        query += " ORDER BY pf.uploaded_at DESC"
        
        files = fetch_all(query, tuple(params))
        
        return Response({
            'files': [
                {
                    'id': str(f['id']),
                    'file_type': f['file_type'],
                    'file_url': f['file_url'],
                    'title': f['title'],
                    'description': f['description'],
                    'amount': float(f['amount']) if f['amount'] else None,
                    'is_plan_extended': f['is_plan_extended'],
                    'uploaded_at': f['uploaded_at'].isoformat() if f['uploaded_at'] else None,
                    'uploaded_by': f['uploaded_by'],
                    'uploaded_by_role': f['uploaded_by_role'],
                }
                for f in files
            ]
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def raise_complaint(request):
    """
    Architect/Owner: Raise a complaint
    POST /api/construction/raise-complaint/
    """
    try:
        user_id = request.user['user_id']
        site_id = request.data.get('site_id')
        title = request.data.get('title')
        description = request.data.get('description')
        priority = request.data.get('priority', 'MEDIUM')  # LOW, MEDIUM, HIGH, URGENT
        
        if not all([site_id, title, description]):
            return Response({'error': 'site_id, title, and description are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Get site engineer for this site (for notification)
        site_engineer = fetch_one("""
            SELECT u.id, u.full_name, u.email
            FROM users u
            JOIN roles r ON u.role_id = r.id
            JOIN sites s ON s.id = %s
            WHERE r.role_name = 'Site Engineer'
            LIMIT 1
        """, (site_id,))
        
        # Create complaint
        complaint_id = str(uuid.uuid4())
        execute_query("""
            INSERT INTO complaints 
            (id, site_id, raised_by, assigned_to, title, description, priority, status, created_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, 'OPEN', CURRENT_TIMESTAMP)
        """, (complaint_id, site_id, user_id, site_engineer['id'] if site_engineer else None, 
              title, description, priority))
        
        # Create notification for site engineer
        if site_engineer:
            notification_id = str(uuid.uuid4())
            execute_query("""
                INSERT INTO notifications 
                (id, user_id, title, message, type, related_id, created_at, is_read)
                VALUES (%s, %s, %s, %s, 'COMPLAINT', %s, CURRENT_TIMESTAMP, FALSE)
            """, (notification_id, site_engineer['id'], 
                  f'New {priority} Priority Complaint',
                  f'{title} - {description[:100]}',
                  complaint_id))
        
        return Response({
            'message': 'Complaint raised successfully',
            'complaint_id': complaint_id,
            'assigned_to': site_engineer['full_name'] if site_engineer else 'Unassigned'
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_complaints(request):
    """
    Get complaints (filtered by role)
    GET /api/construction/complaints/
    Optional params: site_id, status
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        site_id = request.query_params.get('site_id')
        complaint_status = request.query_params.get('status')
        
        query = """
            SELECT 
                c.id,
                c.title,
                c.description,
                c.priority,
                c.status,
                c.created_at,
                c.resolved_at,
                c.resolution_notes,
                c.proof_image_url,
                s.site_name,
                s.area,
                s.street,
                u1.full_name as raised_by_name,
                r1.role_name as raised_by_role,
                u2.full_name as assigned_to_name
            FROM complaints c
            JOIN sites s ON c.site_id = s.id
            JOIN users u1 ON c.raised_by = u1.id
            JOIN roles r1 ON u1.role_id = r1.id
            LEFT JOIN users u2 ON c.assigned_to = u2.id
            WHERE 1=1
        """
        params = []
        
        # Filter by role
        if user_role == 'Site Engineer':
            query += " AND c.assigned_to = %s"
            params.append(user_id)
        elif user_role == 'Architect':
            query += " AND c.raised_by = %s"
            params.append(user_id)
        
        # Filter by site
        if site_id:
            query += " AND c.site_id = %s"
            params.append(site_id)
        
        # Filter by status
        if complaint_status:
            query += " AND c.status = %s"
            params.append(complaint_status)
        
        query += " ORDER BY c.created_at DESC"
        
        complaints = fetch_all(query, tuple(params) if params else None)
        
        return Response({
            'complaints': [
                {
                    'id': str(c['id']),
                    'title': c['title'],
                    'description': c['description'],
                    'priority': c['priority'],
                    'status': c['status'],
                    'site_name': c['site_name'],
                    'area': c['area'],
                    'street': c['street'],
                    'raised_by_name': c['raised_by_name'],
                    'raised_by_role': c['raised_by_role'],
                    'assigned_to_name': c['assigned_to_name'],
                    'created_at': c['created_at'].isoformat() if c['created_at'] else None,
                    'resolved_at': c['resolved_at'].isoformat() if c['resolved_at'] else None,
                    'resolution_notes': c['resolution_notes'],
                    'proof_image_url': c['proof_image_url'],
                }
                for c in complaints
            ]
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ============================================
# EXTRA COST APIs (SITE ENGINEER)
# ============================================

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def submit_extra_cost(request):
    """
    Site Engineer: Submit extra cost
    POST /api/construction/submit-extra-cost/
    """
    try:
        import logging
        logger = logging.getLogger(__name__)
        logger.info(f'📦 [EXTRA_COST] VIEW EXECUTED - Request data: {request.data}')
        print(f'📦 [EXTRA_COST] REQUEST DATA: {request.data}', flush=True)

        user_id = request.user['user_id']
        site_id = request.data.get('site_id')
        amount = request.data.get('amount')
        description = request.data.get('description', '')

        print(f'📦 [EXTRA_COST] Parsed: user_id={user_id}, site_id={site_id}, amount={amount}, description={description}')

        if not all([site_id, amount]):
            print(f'📦 [EXTRA_COST] Validation failed: site_id={site_id}, amount={amount}')
            return Response({'error': 'site_id and amount are required'},
                          status=status.HTTP_400_BAD_REQUEST)

        # Validate amount
        try:
            amount = float(amount)
            if amount <= 0:
                return Response({'error': 'Amount must be greater than 0'},
                              status=status.HTTP_400_BAD_REQUEST)
        except ValueError:
            return Response({'error': 'Invalid amount format'},
                          status=status.HTTP_400_BAD_REQUEST)

        # Insert extra cost
        extra_cost_id = str(uuid.uuid4())
        print(f'📦 [EXTRA_COST] Inserting: id={extra_cost_id}, site_id={site_id}, description={description}, amount={amount}, uploaded_by={user_id}')

        result = execute_query("""
            INSERT INTO extra_works
            (id, site_id, description, amount, uploaded_by)
            VALUES (%s, %s, %s, %s, %s)
        """, (extra_cost_id, site_id, description, amount, user_id))

        print(f'📦 [EXTRA_COST] Insert result: {result}')

        if not result:
            print(f'📦 [EXTRA_COST] Insert failed, returning 500 error')
            return Response({
                'error': 'Failed to submit extra cost - database error'
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

        print(f'📦 [EXTRA_COST] Insert succeeded, returning 201', flush=True)
        response = Response({
            'message': 'Extra cost submitted successfully',
            'extra_cost_id': extra_cost_id,
            'amount': amount,
            'debug': {
                'site_id': str(site_id),
                'description': description,
                'amount': amount
            }
        }, status=status.HTTP_201_CREATED)
        response['X-Debug-Header'] = 'View-Executed'
        return response

    except Exception as e:
        print(f'📦 [EXTRA_COST] Exception: {str(e)}')
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_extra_costs(request, site_id):
    """
    Get all extra costs for a specific site added by users with same role
    GET /api/construction/extra-costs/<site_id>/
    """
    try:
        import logging
        logger = logging.getLogger(__name__)

        user_role = request.user.get('role', '')
        print(f'📦 [EXTRA_COST] GET - Fetching for site_id={site_id}, user_role={user_role}', flush=True)
        logger.info(f'📦 [EXTRA_COST] GET - Fetching for site_id={site_id}, user_role={user_role}')

        extra_costs = fetch_all("""
            SELECT
                e.id,
                e.site_id,
                e.description,
                e.amount
            FROM extra_works e
            JOIN users u ON e.uploaded_by = u.id
            JOIN roles r ON u.role_id = r.id
            WHERE e.site_id = %s AND r.role_name = %s
            ORDER BY e.id DESC
        """, (site_id, user_role))

        print(f'📦 [EXTRA_COST] GET - Found {len(extra_costs) if extra_costs else 0} extra costs', flush=True)
        logger.info(f'📦 [EXTRA_COST] GET - Found {len(extra_costs) if extra_costs else 0} extra costs')
        if extra_costs:
            for ec in extra_costs:
                print(f'📦 [EXTRA_COST] Row: {ec}', flush=True)

        return Response({
            'extra_costs': [
                {
                    'id': str(ec['id']),
                    'site_id': str(ec['site_id']),
                    'description': ec['description'],
                    'amount': float(ec['amount']) if ec['amount'] else 0,
                }
                for ec in extra_costs or []
            ]
        }, status=status.HTTP_200_OK)

    except Exception as e:
        print(f'❌ [EXTRA_COST] GET ERROR: {str(e)}', flush=True)
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ============================================
# DAY-BASED HISTORY API
# ============================================

@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_history_by_day(request):
    """
    Get labour and material history grouped by day of week
    GET /api/construction/history-by-day/?site_id=xxx
    
    Returns entries grouped by day (Monday, Tuesday, etc.)
    """
    try:
        site_id = request.GET.get('site_id')
        user_role = request.user.get('role', '')
        user_id = request.user['user_id']
        
        if not site_id:
            return Response({'error': 'site_id is required'}, status=status.HTTP_400_BAD_REQUEST)
        
        # Define day order for sorting
        day_order = {
            'Monday': 1, 'Tuesday': 2, 'Wednesday': 3, 'Thursday': 4,
            'Friday': 5, 'Saturday': 6, 'Sunday': 7
        }
        
        # Get labour entries grouped by day
        labour_query = """
            SELECT 
                l.id, l.labour_type, l.labour_count, l.entry_date, l.entry_time,
                l.day_of_week, l.notes, l.extra_cost, l.extra_cost_notes,
                l.is_modified, l.modified_at, l.modification_reason,
                s.site_name, s.area, s.street,
                u.full_name as supervisor_name
            FROM labour_entries l
            JOIN sites s ON l.site_id = s.id
            JOIN users u ON l.supervisor_id = u.id
            WHERE l.site_id = %s
        """
        
        # Add role-based filtering
        if user_role == 'Supervisor':
            labour_query += " AND l.supervisor_id = %s"
            labour_entries = fetch_all(labour_query + " ORDER BY l.entry_date DESC, l.entry_time DESC", (site_id, user_id))
        else:
            labour_entries = fetch_all(labour_query + " ORDER BY l.entry_date DESC, l.entry_time DESC", (site_id,))
        
        # Get material entries grouped by day
        material_query = """
            SELECT 
                m.id, m.material_type, m.quantity_used as quantity, m.unit, m.usage_date as entry_date, m.created_at as updated_at,
                'Unknown' as day_of_week, 0 as extra_cost, m.notes as extra_cost_notes,
                s.site_name, s.area, s.street,
                u.full_name as supervisor_name
            FROM material_usage m
            JOIN sites s ON m.site_id = s.id
            JOIN users u ON m.supervisor_id = u.id
            WHERE m.site_id = %s
        """
        
        if user_role == 'Supervisor':
            material_query += " AND m.supervisor_id = %s"
            material_entries = fetch_all(material_query + " ORDER BY m.usage_date DESC, m.created_at DESC", (site_id, user_id))
        else:
            material_entries = fetch_all(material_query + " ORDER BY m.usage_date DESC, m.created_at DESC", (site_id,))
        
        # Group by day_of_week
        labour_by_day = {}
        for entry in labour_entries:
            day = entry['day_of_week'] or 'Unknown'
            if day not in labour_by_day:
                labour_by_day[day] = []
            labour_by_day[day].append({
                'id': str(entry['id']),
                'labour_type': entry['labour_type'],
                'labour_count': entry['labour_count'],
                'entry_date': entry['entry_date'].isoformat() if entry['entry_date'] else None,
                'entry_time': entry['entry_time'].isoformat() if entry['entry_time'] else None,
                'notes': entry.get('notes', ''),
                'extra_cost': float(entry['extra_cost']) if entry.get('extra_cost') else 0,
                'extra_cost_notes': entry.get('extra_cost_notes', ''),
                'is_modified': entry.get('is_modified', False),
                'modified_at': entry['modified_at'].isoformat() if entry.get('modified_at') else None,
                'modification_reason': entry.get('modification_reason', ''),
                'site_name': entry['site_name'],
                'area': entry['area'],
                'street': entry['street'],
                'supervisor_name': entry['supervisor_name']
            })
        
        material_by_day = {}
        for entry in material_entries:
            day = entry['day_of_week'] or 'Unknown'
            if day not in material_by_day:
                material_by_day[day] = []
            material_by_day[day].append({
                'id': str(entry['id']),
                'material_type': entry['material_type'],
                'quantity': float(entry['quantity']),
                'unit': entry['unit'],
                'entry_date': entry['entry_date'].isoformat() if entry['entry_date'] else None,
                'updated_at': entry['updated_at'].isoformat() if entry['updated_at'] else None,
                'extra_cost': float(entry['extra_cost']) if entry.get('extra_cost') else 0,
                'extra_cost_notes': entry.get('extra_cost_notes', ''),
                'site_name': entry['site_name'],
                'area': entry['area'],
                'street': entry['street'],
                'supervisor_name': entry['supervisor_name']
            })
        
        # Sort days
        sorted_labour_days = sorted(labour_by_day.keys(), key=lambda x: day_order.get(x, 99))
        sorted_material_days = sorted(material_by_day.keys(), key=lambda x: day_order.get(x, 99))
        
        return Response({
            'success': True,
            'site_id': site_id,
            'labour_by_day': {day: labour_by_day[day] for day in sorted_labour_days},
            'material_by_day': {day: material_by_day[day] for day in sorted_material_days},
            'total_labour_entries': len(labour_entries),
            'total_material_entries': len(material_entries)
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ============================================
# SITE ENGINEER DOCUMENT UPLOAD APIs
# ============================================

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def upload_site_engineer_document(request):
    """
    Site Engineer: Upload documents (site plans, floor designs, etc.)
    POST /api/construction/upload-site-engineer-document/
    """
    try:
        from django.core.files.storage import default_storage
        from django.conf import settings
        from .time_utils import get_day_of_week
        import os
        
        user_id = request.user['user_id']
        site_id = request.data.get('site_id')
        document_type = request.data.get('document_type')  # 'Site Plan', 'Floor Design', etc.
        title = request.data.get('title', '')
        description = request.data.get('description', '')
        file = request.FILES.get('file')
        
        if not all([site_id, document_type, title, file]):
            return Response({'error': 'site_id, document_type, title, and file are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Validate document type
        valid_types = ['Site Plan', 'Floor Design', 'Structural Plan', 'Electrical Plan', 'Plumbing Plan', 'HVAC Plan', 'Other']
        if document_type not in valid_types:
            return Response({'error': f'document_type must be one of: {", ".join(valid_types)}'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Validate file type (PDF only)
        if not file.name.lower().endswith('.pdf'):
            return Response({'error': 'Only PDF files are allowed'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Create media directory if it doesn't exist
        media_dir = os.path.join(settings.MEDIA_ROOT, 'site_engineer_documents')
        os.makedirs(media_dir, exist_ok=True)
        
        # Generate unique filename
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        ext = os.path.splitext(file.name)[1]
        filename = f"{site_id}_{document_type.replace(' ', '_')}_{timestamp}{ext}"
        filepath = os.path.join('site_engineer_documents', filename)
        
        # Save file
        saved_path = default_storage.save(filepath, file)
        file_url = f"{settings.MEDIA_URL}{saved_path}"
        
        # Get current date and day of week
        today = datetime.now().date()
        day_of_week = get_day_of_week(datetime.now())
        
        # Insert into database
        document_id = str(uuid.uuid4())
        execute_query("""
            INSERT INTO site_engineer_documents 
            (id, site_id, site_engineer_id, document_type, title, description, file_url, file_name, file_size, upload_date, day_of_week)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """, (document_id, site_id, user_id, document_type, title, description, file_url, file.name, file.size, today, day_of_week))
        
        return Response({
            'message': f'{document_type} uploaded successfully',
            'document_id': document_id,
            'file_url': file_url,
            'upload_date': today.isoformat(),
            'day_of_week': day_of_week
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_site_engineer_documents(request):
    """
    Get Site Engineer documents with optional filters
    GET /api/construction/site-engineer-documents/
    Query params: site_id, document_type, date_from, date_to
    """
    try:
        # Get optional filters
        site_id = request.query_params.get('site_id')
        document_type = request.query_params.get('document_type')
        date_from = request.query_params.get('date_from')
        date_to = request.query_params.get('date_to')
        
        # Build query
        query = """
            SELECT 
                sed.id,
                sed.site_id,
                sed.document_type,
                sed.title,
                sed.description,
                sed.file_url,
                sed.file_name,
                sed.file_size,
                sed.upload_date,
                sed.uploaded_at,
                sed.day_of_week,
                s.site_name,
                s.area,
                s.street,
                u.full_name as engineer_name
            FROM site_engineer_documents sed
            JOIN sites s ON sed.site_id = s.id
            JOIN users u ON sed.site_engineer_id = u.id
            WHERE sed.is_active = TRUE
        """
        
        params = []
        
        if site_id:
            query += " AND sed.site_id = %s"
            params.append(site_id)
        
        if document_type:
            query += " AND sed.document_type = %s"
            params.append(document_type)
        
        if date_from:
            query += " AND sed.upload_date >= %s"
            params.append(date_from)
        
        if date_to:
            query += " AND sed.upload_date <= %s"
            params.append(date_to)
        
        query += " ORDER BY sed.uploaded_at DESC LIMIT 200"
        
        documents = fetch_all(query, tuple(params) if params else None)
        
        return Response({
            'documents': [
                {
                    'id': str(d['id']),
                    'site_id': str(d['site_id']),
                    'site_name': d['site_name'],
                    'area': d['area'],
                    'street': d['street'],
                    'document_type': d['document_type'],
                    'title': d['title'],
                    'description': d['description'],
                    'file_url': d['file_url'],
                    'file_name': d['file_name'],
                    'file_size': d['file_size'],
                    'upload_date': d['upload_date'].isoformat() if d['upload_date'] else None,
                    'uploaded_at': d['uploaded_at'].isoformat() if d['uploaded_at'] else None,
                    'day_of_week': d['day_of_week'],
                    'engineer_name': d['engineer_name'],
                }
                for d in documents
            ],
            'total_documents': len(documents),
            'filters_applied': {
                'site_id': site_id,
                'document_type': document_type,
                'date_from': date_from,
                'date_to': date_to,
            }
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_all_documents_for_accountant(request):
    """
    Accountant: Get all documents (Site Engineer + Architect) for a site
    GET /api/construction/all-documents/
    Query params: site_id (required), role (optional: 'site_engineer', 'architect', 'all')
    """
    try:
        site_id = request.query_params.get('site_id')
        role = request.query_params.get('role', 'all')  # 'site_engineer', 'architect', 'all'
        
        if not site_id:
            return Response({'error': 'site_id is required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        result = {
            'site_engineer_documents': [],
            'architect_documents': [],
            'total_documents': 0
        }
        
        # Get Site Engineer documents
        if role in ['site_engineer', 'all']:
            se_docs = fetch_all("""
                SELECT 
                    sed.id,
                    sed.site_id,
                    sed.document_type,
                    sed.title,
                    sed.description,
                    sed.file_url,
                    sed.file_name,
                    sed.file_size,
                    sed.upload_date,
                    sed.uploaded_at,
                    sed.day_of_week,
                    u.full_name as uploaded_by,
                    'Site Engineer' as role
                FROM site_engineer_documents sed
                JOIN users u ON sed.site_engineer_id = u.id
                WHERE sed.site_id = %s AND sed.is_active = TRUE
                ORDER BY sed.uploaded_at DESC
            """, (site_id,))
            
            result['site_engineer_documents'] = [
                {
                    'id': str(d['id']),
                    'site_id': str(d['site_id']),
                    'document_type': d['document_type'],
                    'title': d['title'],
                    'description': d['description'],
                    'file_url': d['file_url'],
                    'file_name': d['file_name'],
                    'file_size': d['file_size'],
                    'upload_date': d['upload_date'].isoformat() if d['upload_date'] else None,
                    'uploaded_at': d['uploaded_at'].isoformat() if d['uploaded_at'] else None,
                    'day_of_week': d['day_of_week'],
                    'uploaded_by': d['uploaded_by'],
                    'role': d['role'],
                }
                for d in se_docs
            ]
        
        # Get Architect documents
        if role in ['architect', 'all']:
            arch_docs = fetch_all("""
                SELECT 
                    ad.id,
                    ad.site_id,
                    ad.document_type,
                    ad.title,
                    ad.description,
                    ad.file_url,
                    ad.file_name,
                    ad.file_size,
                    ad.upload_date,
                    ad.uploaded_at,
                    ad.day_of_week,
                    u.full_name as uploaded_by,
                    'Architect' as role
                FROM architect_documents ad
                JOIN users u ON ad.architect_id = u.id
                WHERE ad.site_id = %s AND ad.is_active = TRUE
                ORDER BY ad.uploaded_at DESC
            """, (site_id,))
            
            result['architect_documents'] = [
                {
                    'id': str(d['id']),
                    'site_id': str(d['site_id']),
                    'document_type': d['document_type'],
                    'title': d['title'],
                    'description': d['description'],
                    'file_url': d['file_url'],
                    'file_name': d['file_name'],
                    'file_size': d['file_size'],
                    'upload_date': d['upload_date'].isoformat() if d['upload_date'] else None,
                    'uploaded_at': d['uploaded_at'].isoformat() if d['uploaded_at'] else None,
                    'day_of_week': d['day_of_week'],
                    'uploaded_by': d['uploaded_by'],
                    'role': d['role'],
                }
                for d in arch_docs
            ]
        
        result['total_documents'] = len(result['site_engineer_documents']) + len(result['architect_documents'])
        
        return Response(result, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)



# ============================================
# ADMIN SITE CREATION ENDPOINTS
# ============================================

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def create_area(request):
    """
    Create a new area (available to all roles)
    POST /api/construction/create-area/
    Body: {"area": "Area Name"}
    """
    try:
        area_name = request.data.get('area')
        
        if not area_name:
            return Response({'error': 'area is required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Check if area already exists
        existing = fetch_one("""
            SELECT COUNT(*) as count FROM sites WHERE area = %s
        """, (area_name,))
        
        if existing and existing['count'] > 0:
            return Response({
                'message': 'Area already exists',
                'area': area_name
            }, status=status.HTTP_200_OK)
        
        # Create a placeholder site for this area
        site_id = str(uuid.uuid4())
        execute_query("""
            INSERT INTO sites 
            (id, site_name, customer_name, area, street, created_at)
            VALUES (%s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
        """, (site_id, '', '', area_name, ''))
        
        return Response({
            'message': 'Area created successfully',
            'area': area_name
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def create_street(request):
    """
    Create a new street in an area (available to all roles)
    POST /api/construction/create-street/
    Body: {"area": "Area Name", "street": "Street Name"}
    """
    try:
        area_name = request.data.get('area')
        street_name = request.data.get('street')
        
        if not all([area_name, street_name]):
            return Response({'error': 'area and street are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Check if street already exists in this area
        existing = fetch_one("""
            SELECT COUNT(*) as count FROM sites 
            WHERE area = %s AND street = %s
        """, (area_name, street_name))
        
        if existing and existing['count'] > 0:
            return Response({
                'message': 'Street already exists in this area',
                'area': area_name,
                'street': street_name
            }, status=status.HTTP_200_OK)
        
        # Create a placeholder site for this street
        site_id = str(uuid.uuid4())
        execute_query("""
            INSERT INTO sites 
            (id, site_name, customer_name, area, street, created_at)
            VALUES (%s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
        """, (site_id, '', '', area_name, street_name))
        
        return Response({
            'message': 'Street created successfully',
            'area': area_name,
            'street': street_name
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)



@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def supervisor_upload_photos(request):
    """
    Supervisor: Upload site photos (morning or evening)
    POST /api/construction/supervisor-upload-photos/
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        # Only supervisors can upload photos
        if user_role != 'Supervisor':
            return Response({
                'error': 'Only supervisors can upload photos'
            }, status=status.HTTP_403_FORBIDDEN)
        
        site_id = request.data.get('site_id')
        time_of_day = request.data.get('time_of_day')  # 'morning' or 'evening'
        photos = request.FILES.getlist('photos')
        
        if not site_id or not time_of_day:
            return Response({
                'error': 'site_id and time_of_day are required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        if time_of_day not in ['morning', 'evening']:
            return Response({
                'error': 'time_of_day must be either "morning" or "evening"'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        if not photos:
            return Response({
                'error': 'At least one photo is required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Verify site exists
        site = fetch_one("""
            SELECT id, site_name FROM sites WHERE id = %s
        """, (site_id,))
        
        if not site:
            return Response({
                'error': 'Site not found'
            }, status=status.HTTP_404_NOT_FOUND)
        
        # Get current date and time
        from .time_utils import get_entry_metadata
        entry_meta = get_entry_metadata()
        upload_date = entry_meta['entry_date']
        upload_time = entry_meta['timestamp_ist']
        
        # Save photos to database
        uploaded_count = 0
        photo_ids = []
        
        for photo in photos:
            # Save photo file
            from django.core.files.storage import default_storage
            from django.core.files.base import ContentFile
            import os
            
            # Generate unique filename
            ext = os.path.splitext(photo.name)[1]
            filename = f"supervisor_photos/{site_id}/{time_of_day}/{uuid.uuid4()}{ext}"
            
            # Save file
            file_path = default_storage.save(filename, ContentFile(photo.read()))
            
            # Insert into database
            photo_id = str(uuid.uuid4())
            execute_query("""
                INSERT INTO site_photos 
                (id, site_id, uploaded_by, image_url, upload_date, time_of_day, description)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
            """, (
                photo_id,
                site_id,
                user_id,
                f'/media/{file_path}',
                upload_date,
                time_of_day,
                f'{time_of_day.capitalize()} photo uploaded by supervisor'
            ))
            
            photo_ids.append(photo_id)
            uploaded_count += 1
        
        return Response({
            'message': f'{uploaded_count} photo(s) uploaded successfully',
            'photo_count': uploaded_count,
            'photo_ids': photo_ids,
            'time_of_day': time_of_day,
            'upload_date': upload_date.strftime('%Y-%m-%d'),
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        print(f"Error uploading photos: {e}")
        return Response({
            'error': f'Error uploading photos: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_supervisor_photos(request):
    """
    Get supervisor uploaded photos for a site
    GET /api/construction/supervisor-photos/?site_id=xxx
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        site_id = request.GET.get('site_id')
        
        if not site_id:
            return Response({
                'error': 'site_id is required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Only supervisors can view their own photos
        if user_role != 'Supervisor':
            return Response({
                'error': 'Only supervisors can view photos'
            }, status=status.HTTP_403_FORBIDDEN)
        
        # Get photos uploaded by this supervisor for this site
        photos = fetch_all("""
            SELECT 
                id,
                site_id,
                image_url,
                upload_date,
                time_of_day,
                description
            FROM site_photos
            WHERE site_id = %s AND uploaded_by = %s
            ORDER BY upload_date DESC, time_of_day DESC
        """, (site_id, user_id))
        
        # Format photos
        formatted_photos = []
        for photo in photos:
            formatted_photos.append({
                'id': photo['id'],
                'site_id': photo['site_id'],
                'image_url': photo['image_url'],
                'upload_date': photo['upload_date'].strftime('%Y-%m-%d') if photo['upload_date'] else None,
                'time_of_day': photo['time_of_day'],
                'description': photo['description'],
            })
        
        return Response({
            'success': True,
            'photos': formatted_photos,
            'count': len(formatted_photos),
        })
        
    except Exception as e:
        print(f"Error fetching photos: {e}")
        return Response({
            'error': f'Error fetching photos: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_supervisor_photos_for_accountant(request):
    """
    Accountant: Get all supervisor uploaded photos for a site
    GET /api/construction/supervisor-photos-for-accountant/?site_id=xxx
    """
    try:
        user_role = request.user.get('role', '')
        site_id = request.GET.get('site_id')
        
        if not site_id:
            return Response({
                'error': 'site_id is required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Only accountants and admins can view all supervisor photos
        if user_role not in ['Accountant', 'Admin']:
            return Response({
                'error': 'Only accountants and admins can view all supervisor photos'
            }, status=status.HTTP_403_FORBIDDEN)
        
        # Get all photos for this site uploaded by supervisors
        photos = fetch_all("""
            SELECT 
                sp.id,
                sp.site_id,
                sp.image_url,
                sp.upload_date,
                sp.time_of_day,
                sp.description,
                u.full_name as supervisor_name
            FROM site_photos sp
            LEFT JOIN users u ON sp.uploaded_by = u.id
            WHERE sp.site_id = %s
            ORDER BY sp.upload_date DESC, sp.time_of_day DESC
        """, (site_id,))
        
        # Format photos
        formatted_photos = []
        for photo in photos:
            formatted_photos.append({
                'id': str(photo['id']),
                'site_id': str(photo['site_id']),
                'image_url': photo['image_url'],
                'upload_date': photo['upload_date'].strftime('%Y-%m-%d') if photo['upload_date'] else None,
                'time_of_day': photo['time_of_day'],
                'description': photo['description'] or '',
                'supervisor_name': photo.get('supervisor_name') or 'Unknown',
            })
        
        return Response({
            'success': True,
            'photos': formatted_photos,
            'count': len(formatted_photos),
        })
        
    except Exception as e:
        print(f"Error fetching supervisor photos for accountant: {e}")
        return Response({
            'error': f'Error fetching photos: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def assign_working_sites(request):
    """
    Accountant: Assign working sites to ALL supervisors
    POST /api/construction/assign-working-sites/
    
    Daily Reset Logic:
    - Every day at 6 AM IST, all working sites are automatically reset (is_active = FALSE)
    - Accountant can select working sites anytime during the day
    - Next day at 6 AM, sites reset again
    
    Body: {
        "sites": [
            {"site_id": "uuid", "description": "optional text"},
            ...
        ]
    }
    """
    try:
        from datetime import datetime, time
        import pytz
        
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        # Only accountants can assign sites
        if user_role != 'Accountant':
            return Response({
                'error': 'Only accountants can assign working sites'
            }, status=status.HTTP_403_FORBIDDEN)
        
        # Check if daily reset is needed (6 AM IST)
        ist_tz = pytz.timezone('Asia/Kolkata')
        now_ist = datetime.now(ist_tz)
        today_date = now_ist.date()
        
        # Check last reset date
        last_reset = fetch_one("""
            SELECT MAX(last_reset_date) as last_reset
            FROM working_sites
        """)
        
        last_reset_date = last_reset['last_reset'] if last_reset and last_reset['last_reset'] else None
        
        # If last reset was before today, or if it's a new day and past 6 AM, reset all sites
        if last_reset_date is None or last_reset_date < today_date:
            print(f"🔄 Daily reset triggered: Last reset was {last_reset_date}, today is {today_date}")
            
            # Deactivate all working sites (daily reset)
            execute_query("""
                UPDATE working_sites
                SET is_active = FALSE,
                    last_reset_date = %s,
                    updated_at = CURRENT_TIMESTAMP
            """, (today_date,))
            
            print(f"✅ All working sites reset for {today_date}")
        
        sites = request.data.get('sites', [])
        
        if not sites:
            return Response({
                'error': 'sites are required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Get all supervisors (active or with is_active not set)
        # Note: role_id 2 = 'Supervisor' from roles table
        supervisors = fetch_all("""
            SELECT u.id, u.username, u.full_name 
            FROM users u
            JOIN roles r ON u.role_id = r.id
            WHERE r.role_name = 'Supervisor' 
            AND (u.is_active = TRUE OR u.is_active IS NULL)
        """)
        
        if not supervisors:
            # If still no supervisors, get ALL supervisors regardless of is_active
            supervisors = fetch_all("""
                SELECT u.id, u.username, u.full_name 
                FROM users u
                JOIN roles r ON u.role_id = r.id
                WHERE r.role_name = 'Supervisor'
            """)
        
        if not supervisors:
            return Response({
                'error': 'No supervisors found in the system. Please create supervisor accounts first.',
                'suggestion': 'Create supervisor users before assigning sites'
            }, status=status.HTTP_404_NOT_FOUND)
        
        # Assign sites to ALL supervisors
        assigned_count = 0
        for supervisor in supervisors:
            supervisor_id = supervisor['id']
            
            for site_data in sites:
                site_id = site_data.get('site_id')
                description = site_data.get('description', '')
                
                if not site_id:
                    continue
                
                # Check if assignment already exists
                existing = fetch_one("""
                    SELECT id FROM working_sites
                    WHERE supervisor_id = %s AND site_id = %s
                """, (supervisor_id, site_id))
                
                if existing:
                    # Update existing assignment
                    execute_query("""
                        UPDATE working_sites
                        SET description = %s,
                            is_active = TRUE,
                            updated_at = CURRENT_TIMESTAMP,
                            accountant_id = %s,
                            last_reset_date = %s
                        WHERE id = %s
                    """, (description, user_id, today_date, existing['id']))
                else:
                    # Create new assignment
                    assignment_id = str(uuid.uuid4())
                    execute_query("""
                        INSERT INTO working_sites
                        (id, accountant_id, supervisor_id, site_id, description, last_reset_date)
                        VALUES (%s, %s, %s, %s, %s, %s)
                    """, (assignment_id, user_id, supervisor_id, site_id, description, today_date))
                
                assigned_count += 1
        
        return Response({
            'message': f'{len(sites)} site(s) assigned to {len(supervisors)} supervisor(s) successfully',
            'assigned_count': assigned_count,
            'sites_count': len(sites),
            'supervisors_count': len(supervisors),
            'reset_performed': last_reset_date != today_date,
            'assignment_date': today_date.strftime('%Y-%m-%d')
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        print(f"Error assigning sites: {e}")
        import traceback
        traceback.print_exc()
        return Response({
            'error': f'Error assigning sites: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_working_sites(request):
    """
    Supervisor: Get assigned working sites
    GET /api/construction/working-sites/
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        # Only supervisors can view their working sites
        if user_role != 'Supervisor':
            return Response({
                'error': 'Only supervisors can view working sites'
            }, status=status.HTTP_403_FORBIDDEN)
        
        # Get assigned sites for this supervisor
        sites = fetch_all("""
            SELECT
                ws.id as assignment_id,
                ws.site_id,
                ws.description,
                ws.assigned_date,
                s.site_name,
                s.customer_name,
                s.area,
                s.street,
                s.status
            FROM working_sites ws
            JOIN sites s ON ws.site_id = s.id
            WHERE ws.supervisor_id = %s AND ws.is_active = TRUE
            ORDER BY ws.assigned_date DESC
        """, (user_id,))

        # Auto-provision new supervisors: if no sites found, copy currently active
        # accountant assignments so any supervisor logging in for the first time
        # automatically sees the sites the accountant has selected.
        if not sites:
            active_assignments = fetch_all("""
                SELECT DISTINCT ON (ws.site_id)
                    ws.site_id,
                    ws.description,
                    ws.accountant_id,
                    ws.last_reset_date
                FROM working_sites ws
                WHERE ws.is_active = TRUE
                ORDER BY ws.site_id, ws.assigned_date DESC
            """)
            if active_assignments:
                print(f"🆕 [WORKING_SITES] Auto-provisioning {len(active_assignments)} sites for new supervisor {user_id}")
                for assignment in active_assignments:
                    assignment_id = str(uuid.uuid4())
                    execute_query("""
                        INSERT INTO working_sites
                            (id, accountant_id, supervisor_id, site_id, description, last_reset_date)
                        VALUES (%s, %s, %s, %s, %s, %s)
                        ON CONFLICT (supervisor_id, site_id) DO UPDATE
                            SET is_active = TRUE,
                                last_reset_date = EXCLUDED.last_reset_date,
                                updated_at = CURRENT_TIMESTAMP
                    """, (assignment_id, assignment['accountant_id'], user_id,
                          assignment['site_id'], assignment.get('description', ''),
                          assignment['last_reset_date']))
                # Re-fetch after provisioning
                sites = fetch_all("""
                    SELECT
                        ws.id as assignment_id,
                        ws.site_id,
                        ws.description,
                        ws.assigned_date,
                        s.site_name,
                        s.customer_name,
                        s.area,
                        s.street,
                        s.status
                    FROM working_sites ws
                    JOIN sites s ON ws.site_id = s.id
                    WHERE ws.supervisor_id = %s AND ws.is_active = TRUE
                    ORDER BY ws.assigned_date DESC
                """, (user_id,))
        
        # Format sites
        formatted_sites = []
        for site in sites:
            formatted_sites.append({
                'assignment_id': site['assignment_id'],
                'id': site['site_id'],
                'site_name': site['site_name'],
                'customer_name': site['customer_name'],
                'area': site['area'],
                'street': site['street'],
                'status': site['status'],
                'description': site['description'],
                'assigned_date': site['assigned_date'].strftime('%Y-%m-%d') if site['assigned_date'] else None,
                'display_name': f"{site['site_name']} - {site['customer_name']}" if site['customer_name'] else site['site_name'],
            })
        
        return Response({
            'success': True,
            'sites': formatted_sites,
            'count': len(formatted_sites),
        })
        
    except Exception as e:
        print(f"Error fetching working sites: {e}")
        return Response({
            'error': f'Error fetching working sites: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def clear_working_sites(request):
    """
    Accountant: Clear/Remove all current working sites
    POST /api/construction/clear-working-sites/
    
    This deactivates all working sites so accountant can re-select them.
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        # Only accountants can clear working sites
        if user_role != 'Accountant':
            return Response({
                'error': 'Only accountants can clear working sites'
            }, status=status.HTTP_403_FORBIDDEN)
        
        # Get count of active working sites before clearing
        active_sites = fetch_one("""
            SELECT COUNT(*) as count
            FROM working_sites
            WHERE is_active = TRUE
        """)
        
        active_count = active_sites['count'] if active_sites else 0
        
        # Deactivate all working sites
        execute_query("""
            UPDATE working_sites
            SET is_active = FALSE,
                updated_at = CURRENT_TIMESTAMP
            WHERE is_active = TRUE
        """)
        
        print(f"🗑️ Cleared {active_count} working sites by accountant {user_id}")
        
        return Response({
            'success': True,
            'message': f'Successfully cleared {active_count} working site(s)',
            'cleared_count': active_count
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        print(f"Error clearing working sites: {e}")
        import traceback
        traceback.print_exc()
        return Response({
            'error': f'Error clearing working sites: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_accountant_working_sites_count(request):
    """
    Accountant: Get count of unique sites assigned by this accountant
    GET /api/construction/accountant-working-sites-count/
    
    Returns the number of unique sites this accountant has assigned to supervisors.
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        # Only accountants can access this
        if user_role != 'Accountant':
            return Response({
                'error': 'Only accountants can access this endpoint'
            }, status=status.HTTP_403_FORBIDDEN)
        
        # Get count of unique sites assigned by this accountant
        result = fetch_one("""
            SELECT COUNT(DISTINCT site_id) as count
            FROM working_sites
            WHERE accountant_id = %s AND is_active = TRUE
        """, (user_id,))
        
        sites_count = result['count'] if result else 0
        
        print(f"📊 [WORKING SITES] Accountant {user_id} has {sites_count} working sites")
        
        return Response({
            'success': True,
            'working_sites_count': sites_count
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        print(f"Error getting working sites count: {e}")
        import traceback
        traceback.print_exc()
        return Response({
            'error': f'Error getting working sites count: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_today_sites_with_data(request):
    """
    Supervisor: Get sites where data was entered today
    GET /api/construction/today-sites-with-data/
    """
    try:
        user_id = request.user['user_id']
        today = datetime.now().date()
        
        # Get sites with labour entries today
        labour_sites = fetch_all("""
            SELECT DISTINCT
                s.id as site_id,
                s.site_name,
                s.customer_name,
                s.area,
                s.street,
                TRUE as has_labour,
                FALSE as has_material,
                FALSE as has_photos
            FROM labour_entries le
            JOIN sites s ON le.site_id = s.id
            WHERE le.supervisor_id = %s 
            AND le.entry_date = %s
        """, (user_id, today))
        
        # Get sites with material entries today
        material_sites = fetch_all("""
            SELECT DISTINCT
                s.id as site_id,
                s.site_name,
                s.customer_name,
                s.area,
                s.street,
                FALSE as has_labour,
                TRUE as has_material,
                FALSE as has_photos
            FROM material_usage mu
            JOIN sites s ON mu.site_id = s.id
            WHERE mu.supervisor_id = %s 
            AND mu.usage_date = %s
        """, (user_id, today))
        
        # Get sites with photos uploaded today
        photo_sites = fetch_all("""
            SELECT DISTINCT
                s.id as site_id,
                s.site_name,
                s.customer_name,
                s.area,
                s.street,
                FALSE as has_labour,
                FALSE as has_material,
                TRUE as has_photos
            FROM work_updates wu
            JOIN sites s ON wu.site_id = s.id
            WHERE wu.engineer_id = %s 
            AND DATE(wu.upload_date) = %s
        """, (user_id, today))
        
        # Merge all sites
        sites_dict = {}
        
        for site in labour_sites:
            site_id = site['site_id']
            if site_id not in sites_dict:
                sites_dict[site_id] = {
                    'id': site_id,
                    'site_name': site['site_name'],
                    'customer_name': site['customer_name'],
                    'area': site['area'],
                    'street': site['street'],
                    'has_labour': False,
                    'has_material': False,
                    'has_photos': False,
                }
            sites_dict[site_id]['has_labour'] = True
        
        for site in material_sites:
            site_id = site['site_id']
            if site_id not in sites_dict:
                sites_dict[site_id] = {
                    'id': site_id,
                    'site_name': site['site_name'],
                    'customer_name': site['customer_name'],
                    'area': site['area'],
                    'street': site['street'],
                    'has_labour': False,
                    'has_material': False,
                    'has_photos': False,
                }
            sites_dict[site_id]['has_material'] = True
        
        for site in photo_sites:
            site_id = site['site_id']
            if site_id not in sites_dict:
                sites_dict[site_id] = {
                    'id': site_id,
                    'site_name': site['site_name'],
                    'customer_name': site['customer_name'],
                    'area': site['area'],
                    'street': site['street'],
                    'has_labour': False,
                    'has_material': False,
                    'has_photos': False,
                }
            sites_dict[site_id]['has_photos'] = True
        
        # Convert to list
        formatted_sites = list(sites_dict.values())
        
        return Response({
            'success': True,
            'sites': formatted_sites,
            'count': len(formatted_sites),
            'date': today.strftime('%Y-%m-%d'),
        })
        
    except Exception as e:
        print(f"Error fetching today sites with data: {e}")
        return Response({
            'error': f'Error fetching today sites with data: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_total_counts(request):
    """
    Get total counts of areas, streets, and sites in the system
    GET /api/construction/total-counts/
    """
    try:
        # Get total areas
        total_areas = fetch_one("""
            SELECT COUNT(DISTINCT area) as count
            FROM sites
            WHERE area IS NOT NULL AND area != ''
        """)
        
        # Get total streets
        total_streets = fetch_one("""
            SELECT COUNT(DISTINCT street) as count
            FROM sites
            WHERE street IS NOT NULL AND street != ''
        """)
        
        # Get total sites
        total_sites = fetch_one("""
            SELECT COUNT(*) as count
            FROM sites
        """)
        
        return Response({
            'success': True,
            'total_areas': total_areas['count'] if total_areas else 0,
            'total_streets': total_streets['count'] if total_streets else 0,
            'total_sites': total_sites['count'] if total_sites else 0,
        })
        
    except Exception as e:
        print(f"Error fetching total counts: {e}")
        return Response({
            'error': f'Error fetching total counts: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_supervisors_list(request):
    """
    Accountant: Get list of supervisors to assign sites
    GET /api/construction/supervisors-list/
    """
    try:
        user_role = request.user.get('role', '')
        
        # Only accountants can view supervisors list
        if user_role != 'Accountant':
            return Response({
                'error': 'Only accountants can view supervisors list'
            }, status=status.HTTP_403_FORBIDDEN)
        
        # Get all supervisors (active or with is_active not set)
        supervisors = fetch_all("""
            SELECT 
                u.id,
                u.username,
                u.full_name,
                u.phone
            FROM users u
            JOIN roles r ON u.role_id = r.id
            WHERE r.role_name = 'Supervisor' 
            AND (u.is_active = TRUE OR u.is_active IS NULL)
            ORDER BY u.full_name
        """)
        
        if not supervisors:
            # If still no supervisors, get ALL supervisors regardless of is_active
            supervisors = fetch_all("""
                SELECT 
                    u.id,
                    u.username,
                    u.full_name,
                    u.phone
                FROM users u
                JOIN roles r ON u.role_id = r.id
                WHERE r.role_name = 'Supervisor'
                ORDER BY u.full_name
            """)
        
        # Format supervisors
        formatted_supervisors = []
        for supervisor in supervisors:
            formatted_supervisors.append({
                'id': supervisor['id'],
                'username': supervisor['username'],
                'full_name': supervisor['full_name'],
                'phone_number': supervisor.get('phone', ''),
                'display_name': f"{supervisor['full_name']} ({supervisor['username']})",
            })
        
        return Response({
            'success': True,
            'supervisors': formatted_supervisors,
            'count': len(formatted_supervisors),
        })
        
    except Exception as e:
        print(f"Error fetching supervisors: {e}")
        return Response({
            'error': f'Error fetching supervisors: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)



@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_all_sites(request):
    """
    Get all sites (for accountant to assign to supervisors)
    GET /api/construction/all-sites/
    """
    try:
        # Get all sites - only fetch necessary fields for better performance
        sites = fetch_all("""
            SELECT 
                id,
                site_name,
                customer_name
            FROM sites
            WHERE status != 'DELETED' OR status IS NULL
            ORDER BY customer_name, site_name
            LIMIT 1000
        """)
        
        # Format sites
        formatted_sites = []
        for site in sites:
            site_name = site.get('site_name') or ''
            customer_name = site.get('customer_name') or ''
            
            # Create display name
            if customer_name and site_name:
                display_name = f"{customer_name} {site_name}"
            elif customer_name:
                display_name = customer_name
            elif site_name:
                display_name = site_name
            else:
                display_name = f"Site {str(site['id'])[:8]}"
            
            formatted_sites.append({
                'id': str(site['id']),
                'site_name': site_name,
                'customer_name': customer_name,
                'display_name': display_name,
            })
        
        return Response({
            'success': True,
            'sites': formatted_sites,
            'count': len(formatted_sites),
        })
        
    except Exception as e:
        print(f"Error fetching sites: {e}")
        return Response({
            'error': f'Error fetching sites: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ============================================
# ACCOUNTANT - CLIENT REQUIREMENTS
# ============================================

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def add_client_requirement(request):
    """
    Accountant: Add extra requirement for client
    POST /api/accountant/add-client-requirement/
    Body: {
        "site_id": "uuid",
        "description": "Extra requirement description",
        "amount": 50000
    }
    """
    try:
        user_role = request.user.get('role', '')
        user_id = request.user.get('user_id')

        # Allow Accountant, Supervisor, and Site Engineer to add client requirements
        if user_role not in ['Accountant', 'Supervisor', 'Site Engineer']:
            return Response({'error': 'Only Accountant, Supervisor, or Site Engineer can add client requirements'},
                          status=status.HTTP_403_FORBIDDEN)

        site_id = request.data.get('site_id')
        description = request.data.get('description')
        amount = request.data.get('amount')

        if not site_id or not description or amount is None:
            return Response({'error': 'site_id, description and amount are required'},
                          status=status.HTTP_400_BAD_REQUEST)

        # Get site name and user name for notification
        site_info = fetch_one("""
            SELECT site_name FROM sites WHERE id = %s
        """, (site_id,))

        user_info = fetch_one("""
            SELECT full_name FROM users WHERE id = %s
        """, (user_id,))

        site_name = site_info['site_name'] if site_info else 'Unknown Site'
        user_name = user_info['full_name'] if user_info else 'Unknown User'

        # Insert client requirement
        requirement_id = str(uuid.uuid4())
        insert_query = """
            INSERT INTO client_requirements
            (requirement_id, site_id, description, amount, added_by, added_date, status)
            VALUES (%s, %s, %s, %s, %s, NOW(), 'Pending')
        """

        execute_query(insert_query, (requirement_id, site_id, description, amount, user_id))

        # Create notification for admin
        notification_id = str(uuid.uuid4())
        notification_message = f"{user_name} added a new site requirement: {description} (₹{amount})"

        notification_query = """
            INSERT INTO notifications
            (id, site_id, entry_type, message, actual_time, supervisor_id, supervisor_name, site_name)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """

        execute_query(notification_query, (
            notification_id,
            site_id,
            'Site Requirement',
            notification_message,
            None,
            user_id,
            user_name,
            site_name
        ))

        return Response({
            'message': 'Client requirement added successfully',
            'requirement_id': requirement_id,
            'notification_id': notification_id
        }, status=status.HTTP_201_CREATED)

    except Exception as e:
        print(f"❌ Error adding client requirement: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_client_requirements(request):
    """
    Admin: Get client requirements for a site
    GET /api/admin/client-requirements/?site_id=xxx
    """
    try:
        user_role = request.user.get('role', '')
        
        print(f"🔍 get_client_requirements called by user role: {user_role}")
        
        # Allow Admin and Accountant to view client requirements
        if user_role not in ['Admin', 'Accountant']:
            print(f"❌ Access denied for role: {user_role}")
            return Response({'error': 'Only Admin or Accountant can view client requirements'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        site_id = request.GET.get('site_id')
        print(f"📍 Requested site_id: {site_id}")
        
        if not site_id:
            print("❌ No site_id provided")
            return Response({'error': 'site_id is required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Get client requirements
        query = """
            SELECT 
                cr.requirement_id,
                cr.description,
                cr.amount,
                cr.added_date,
                cr.status,
                u.username as added_by_name,
                s.site_name,
                s.customer_name,
                CONCAT(s.customer_name, ' ', s.site_name) as full_site_name
            FROM client_requirements cr
            LEFT JOIN users u ON cr.added_by = u.id
            LEFT JOIN sites s ON cr.site_id = s.id
            WHERE cr.site_id = %s
            ORDER BY cr.added_date DESC
        """
        
        requirements = fetch_all(query, (site_id,))
        print(f"✅ Found {len(requirements)} requirements for site {site_id}")
        
        return Response({
            'requirements': requirements
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        print(f"❌ Error fetching client requirements: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['PUT'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def update_client_requirement(request, requirement_id):
    """
    Supervisor/Site Engineer: Update client requirement
    PUT /api/accountant/update-client-requirement/<requirement_id>/
    Body: {
        "description": "Updated description",
        "amount": 60000
    }
    """
    try:
        user_role = request.user.get('role', '')
        user_id = request.user.get('user_id')

        # Allow Accountant, Supervisor, and Site Engineer to update client requirements
        if user_role not in ['Accountant', 'Supervisor', 'Site Engineer']:
            return Response({'error': 'Only Accountant, Supervisor, or Site Engineer can update client requirements'},
                          status=status.HTTP_403_FORBIDDEN)

        description = request.data.get('description')
        amount = request.data.get('amount')

        if not description and amount is None:
            return Response({'error': 'At least description or amount must be provided'},
                          status=status.HTTP_400_BAD_REQUEST)

        # Get current requirement details
        requirement = fetch_one("""
            SELECT site_id, description, amount FROM client_requirements
            WHERE requirement_id = %s
        """, (requirement_id,))

        if not requirement:
            return Response({'error': 'Requirement not found'},
                          status=status.HTTP_404_NOT_FOUND)

        site_id = requirement['site_id']

        # Update the requirement
        update_query = """
            UPDATE client_requirements
            SET description = %s, amount = %s, updated_at = NOW()
            WHERE requirement_id = %s
        """

        execute_query(update_query, (
            description or requirement['description'],
            amount if amount is not None else requirement['amount'],
            requirement_id
        ))

        # Get updated values and user info for notification
        user_info = fetch_one("""
            SELECT full_name FROM users WHERE id = %s
        """, (user_id,))

        site_info = fetch_one("""
            SELECT site_name FROM sites WHERE id = %s
        """, (site_id,))

        user_name = user_info['full_name'] if user_info else 'Unknown User'
        site_name = site_info['site_name'] if site_info else 'Unknown Site'
        final_amount = amount if amount is not None else requirement['amount']

        # Create notification for admin
        notification_id = str(uuid.uuid4())
        notification_message = f"{user_name} updated a site requirement: {description or requirement['description']} (₹{final_amount})"

        notification_query = """
            INSERT INTO notifications
            (id, site_id, entry_type, message, actual_time, supervisor_id, supervisor_name, site_name)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """

        execute_query(notification_query, (
            notification_id,
            site_id,
            'Site Requirement',
            notification_message,
            None,
            user_id,
            user_name,
            site_name
        ))

        return Response({
            'message': 'Client requirement updated successfully',
            'requirement_id': requirement_id,
            'notification_id': notification_id
        }, status=status.HTTP_200_OK)

    except Exception as e:
        print(f"❌ Error updating client requirement: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_client_complaints_for_architect(request):
    """
    Get client complaints assigned to architect or for architect's sites
    GET /api/construction/client-complaints/
    
    Query params:
    - site_id (optional): Filter by specific site
    - status (optional): Filter by status (OPEN, IN_PROGRESS, RESOLVED, CLOSED)
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        # Allow architects and admins
        if user_role not in ['Architect', 'Admin']:
            return Response({
                'error': 'Only architects and admins can access this endpoint'
            }, status=status.HTTP_403_FORBIDDEN)
        
        site_id = request.GET.get('site_id')
        status_filter = request.GET.get('status')
        
        # Build query - Filter for complaints raised by clients (role_id = 8)
        query = """
            SELECT 
                c.id,
                c.site_id,
                s.site_name,
                s.customer_name,
                c.raised_by,
                u_client.full_name as client_name,
                u_client.username as client_username,
                c.title,
                c.description,
                c.status,
                c.priority,
                c.created_at,
                c.resolved_at,
                c.resolution_notes,
                c.proof_image_url,
                c.assigned_to,
                u_assigned.full_name as assigned_to_name
            FROM complaints c
            LEFT JOIN sites s ON c.site_id = s.id
            LEFT JOIN users u_client ON c.raised_by = u_client.id
            LEFT JOIN users u_assigned ON c.assigned_to = u_assigned.id
            WHERE u_client.role_id = 8
        """
        
        params = []
        
        # For architects, show only complaints assigned to them or for their sites
        if user_role == 'Architect':
            query += " AND (c.assigned_to = %s OR c.site_id IN (SELECT DISTINCT site_id FROM architect_documents WHERE architect_id = %s))"
            params.extend([user_id, user_id])
        
        # Filter by site if provided
        if site_id:
            query += " AND c.site_id = %s"
            params.append(site_id)
        
        # Filter by status if provided
        if status_filter:
            query += " AND c.status = %s"
            params.append(status_filter.upper())
        
        query += " ORDER BY c.created_at DESC"
        
        complaints = fetch_all(query, tuple(params) if params else None)
        
        # Format response
        complaints_list = []
        for complaint in complaints:
            # Handle image URL
            image_url = complaint.get('proof_image_url')
            if image_url:
                if not image_url.startswith(('http', '/media/', '/')):
                    image_url = f"{settings.MEDIA_URL}{image_url}"
            
            # Get message count
            msg_count_result = fetch_one("""
                SELECT COUNT(*) as count FROM complaint_messages
                WHERE complaint_id = %s
            """, (complaint['id'],))
            message_count = msg_count_result['count'] if msg_count_result else 0
            
            complaints_list.append({
                'id': str(complaint['id']),
                'site_id': str(complaint['site_id']),
                'site_name': complaint['site_name'],
                'customer_name': complaint.get('customer_name'),
                'client': {
                    'id': str(complaint['raised_by']),
                    'name': complaint['client_name'],
                    'username': complaint['client_username'],
                },
                'title': complaint['title'],
                'description': complaint.get('description') or '',
                'status': complaint['status'],
                'priority': complaint['priority'],
                'created_at': complaint['created_at'].isoformat() if complaint.get('created_at') else None,
                'resolved_at': complaint['resolved_at'].isoformat() if complaint.get('resolved_at') else None,
                'resolution_notes': complaint.get('resolution_notes') or '',
                'proof_image_url': image_url,
                'assigned_to': {
                    'id': str(complaint['assigned_to']) if complaint.get('assigned_to') else None,
                    'name': complaint.get('assigned_to_name'),
                },
                'message_count': message_count,
            })
        
        return Response({
            'success': True,
            'complaints': complaints_list,
            'total_count': len(complaints_list)
        })
        
    except Exception as e:
        print(f"❌ Error in get_client_complaints_for_architect: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({
            'error': f'Failed to fetch complaints: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_complaint_messages_architect(request, complaint_id):
    """
    Get all messages for a specific complaint (for architects/admins)
    GET /api/construction/complaints/<complaint_id>/messages/
    """
    try:
        user_role = request.user.get('role', '')
        
        # Allow architects and admins
        if user_role not in ['Architect', 'Admin']:
            return Response({
                'error': 'Only architects and admins can access this endpoint'
            }, status=status.HTTP_403_FORBIDDEN)
        
        # Get complaint details
        complaint = fetch_one("""
            SELECT c.id, c.title, c.site_id, s.site_name
            FROM complaints c
            LEFT JOIN sites s ON c.site_id = s.id
            WHERE c.id = %s
        """, (complaint_id,))
        
        if not complaint:
            return Response({
                'error': 'Complaint not found'
            }, status=status.HTTP_404_NOT_FOUND)
        
        # Get all messages for this complaint
        messages = fetch_all("""
            SELECT 
                cm.id,
                cm.message,
                cm.created_at,
                cm.is_read,
                u.id as sender_id,
                u.full_name as sender_name,
                u.role_id as sender_role_id,
                r.role_name as sender_role
            FROM complaint_messages cm
            LEFT JOIN users u ON cm.sender_id = u.id
            LEFT JOIN roles r ON u.role_id = r.id
            WHERE cm.complaint_id = %s
            ORDER BY cm.created_at ASC
        """, (complaint_id,))
        
        # Format messages
        user_id = request.user['user_id']
        messages_list = []
        for msg in messages:
            messages_list.append({
                'id': str(msg['id']),
                'message': msg['message'],
                'created_at': msg['created_at'].isoformat() if msg.get('created_at') else None,
                'is_read': msg.get('is_read', False),
                'sender': {
                    'id': str(msg['sender_id']),
                    'name': msg['sender_name'],
                    'role': msg['sender_role'],
                    'role_id': msg['sender_role_id'],
                },
                'is_own_message': str(msg['sender_id']) == str(user_id)
            })
        
        return Response({
            'success': True,
            'complaint': {
                'id': str(complaint['id']),
                'title': complaint['title'],
                'site_name': complaint['site_name'],
            },
            'messages': messages_list,
            'total_count': len(messages_list)
        })
        
    except Exception as e:
        print(f"❌ Error in get_complaint_messages_architect: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({
            'error': f'Failed to fetch messages: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def send_complaint_message_architect(request, complaint_id):
    """
    Send a message/response to a client complaint (for architects/admins)
    POST /api/construction/complaints/<complaint_id>/messages/
    
    Body:
    - message (required): The message text
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        # Allow architects and admins
        if user_role not in ['Architect', 'Admin']:
            return Response({
                'error': 'Only architects and admins can access this endpoint'
            }, status=status.HTTP_403_FORBIDDEN)
        
        # Get message from request
        message = request.data.get('message', '').strip()
        
        if not message:
            return Response({
                'error': 'message is required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Verify complaint exists
        complaint = fetch_one("""
            SELECT c.id, c.site_id
            FROM complaints c
            WHERE c.id = %s
        """, (complaint_id,))
        
        if not complaint:
            return Response({
                'error': 'Complaint not found'
            }, status=status.HTTP_404_NOT_FOUND)
        
        # Insert message
        new_message = fetch_one("""
            INSERT INTO complaint_messages (
                complaint_id,
                sender_id,
                message,
                created_at,
                is_read
            ) VALUES (%s, %s, %s, CURRENT_TIMESTAMP, FALSE)
            RETURNING id, created_at
        """, (complaint_id, user_id, message))
        
        return Response({
            'success': True,
            'message': {
                'id': str(new_message['id']),
                'complaint_id': complaint_id,
                'message': message,
                'created_at': new_message['created_at'].isoformat(),
                'is_own_message': True
            }
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        print(f"❌ Error in send_complaint_message_architect: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({
            'error': f'Failed to send message: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ============================================
# MATERIAL REQUIREMENTS SYSTEM
# ============================================

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def submit_material_requirement(request):
    """
    Supervisor: Submit material requirement for a site
    POST /api/construction/material-requirements/
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        # Allow supervisors and site engineers to submit material requirements
        if user_role not in ['Supervisor', 'Site Engineer']:
            return Response({
                'error': 'Only supervisors and site engineers can submit material requirements'
            }, status=status.HTTP_403_FORBIDDEN)
        
        site_id = request.data.get('site_id')
        material_name = request.data.get('material_name')
        quantity = request.data.get('quantity')
        unit = request.data.get('unit')
        priority = request.data.get('priority', 'normal')
        notes = request.data.get('notes', '')
        
        if not all([site_id, material_name, quantity, unit]):
            return Response({
                'error': 'site_id, material_name, quantity, and unit are required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Validate priority
        if priority not in ['urgent', 'normal', 'low']:
            priority = 'normal'
        
        # Insert material requirement
        requirement_id = str(uuid.uuid4())
        execute_query("""
            INSERT INTO material_requirements 
            (id, site_id, supervisor_id, material_name, quantity, unit, priority, notes, status)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'pending')
        """, (requirement_id, site_id, user_id, material_name, quantity, unit, priority, notes))
        
        return Response({
            'success': True,
            'message': 'Material requirement submitted successfully',
            'requirement_id': requirement_id
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        print(f"Error submitting material requirement: {e}")
        return Response({
            'error': f'Error submitting material requirement: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_material_requirements(request):
    """
    Admin/Accountant: Get all material requirements
    Supervisor: Get their own material requirements
    GET /api/construction/material-requirements/
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        # Build query based on role
        if user_role in ['Admin', 'Accountant']:
            # Admin/Accountant can see all requirements
            requirements = fetch_all("""
                SELECT 
                    mr.id,
                    mr.site_id,
                    mr.material_name,
                    mr.quantity,
                    mr.unit,
                    mr.priority,
                    mr.notes,
                    mr.status,
                    mr.created_at,
                    s.site_name,
                    s.customer_name,
                    s.area,
                    s.street,
                    u.full_name as supervisor_name,
                    u.phone as supervisor_phone
                FROM material_requirements mr
                JOIN sites s ON mr.site_id = s.id
                JOIN users u ON mr.supervisor_id = u.id
                ORDER BY 
                    CASE mr.priority 
                        WHEN 'urgent' THEN 1
                        WHEN 'normal' THEN 2
                        WHEN 'low' THEN 3
                    END,
                    mr.created_at DESC
            """)
        elif user_role == 'Supervisor':
            # Supervisor can only see their own requirements
            requirements = fetch_all("""
                SELECT 
                    mr.id,
                    mr.site_id,
                    mr.material_name,
                    mr.quantity,
                    mr.unit,
                    mr.priority,
                    mr.notes,
                    mr.status,
                    mr.created_at,
                    s.site_name,
                    s.customer_name,
                    s.area,
                    s.street
                FROM material_requirements mr
                JOIN sites s ON mr.site_id = s.id
                WHERE mr.supervisor_id = %s
                ORDER BY mr.created_at DESC
            """, (user_id,))
        else:
            return Response({
                'error': 'Unauthorized'
            }, status=status.HTTP_403_FORBIDDEN)
        
        # Format requirements
        formatted_requirements = []
        for req in requirements:
            formatted_req = {
                'id': req['id'],
                'site_id': req['site_id'],
                'site_name': req['site_name'],
                'customer_name': req['customer_name'],
                'area': req['area'],
                'street': req['street'],
                'material_name': req['material_name'],
                'quantity': float(req['quantity']),
                'unit': req['unit'],
                'priority': req['priority'],
                'notes': req['notes'],
                'status': req['status'],
                'created_at': req['created_at'].strftime('%Y-%m-%d %H:%M:%S') if req['created_at'] else None,
            }
            
            # Add supervisor info for admin/accountant
            if user_role in ['Admin', 'Accountant']:
                formatted_req['supervisor_name'] = req.get('supervisor_name')
                formatted_req['supervisor_phone'] = req.get('supervisor_phone')
            
            formatted_requirements.append(formatted_req)
        
        return Response({
            'success': True,
            'requirements': formatted_requirements,
            'count': len(formatted_requirements)
        })
        
    except Exception as e:
        print(f"Error fetching material requirements: {e}")
        return Response({
            'error': f'Error fetching material requirements: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['PUT'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def update_material_requirement_status(request, requirement_id):
    """
    Admin/Accountant: Update material requirement status
    PUT /api/construction/material-requirements/<requirement_id>/status/
    """
    try:
        user_role = request.user.get('role', '')
        
        # Only Admin/Accountant can update status
        if user_role not in ['Admin', 'Accountant']:
            return Response({
                'error': 'Only Admin/Accountant can update requirement status'
            }, status=status.HTTP_403_FORBIDDEN)
        
        new_status = request.data.get('status')
        
        if not new_status:
            return Response({
                'error': 'status is required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Validate status
        if new_status not in ['pending', 'approved', 'ordered', 'delivered']:
            return Response({
                'error': 'Invalid status. Must be: pending, approved, ordered, or delivered'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Update status
        execute_query("""
            UPDATE material_requirements 
            SET status = %s, updated_at = CURRENT_TIMESTAMP
            WHERE id = %s
        """, (new_status, requirement_id))
        
        return Response({
            'success': True,
            'message': f'Status updated to {new_status}'
        })
        
    except Exception as e:
        print(f"Error updating material requirement status: {e}")
        return Response({
            'error': f'Error updating status: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['DELETE'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def delete_material_requirement(request, requirement_id):
    """
    Supervisor: Delete their own material requirement (if pending)
    Admin/Accountant: Delete any material requirement
    DELETE /api/construction/material-requirements/<requirement_id>/
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        # Check if requirement exists
        requirement = fetch_one("""
            SELECT supervisor_id, status 
            FROM material_requirements 
            WHERE id = %s
        """, (requirement_id,))
        
        if not requirement:
            return Response({
                'error': 'Material requirement not found'
            }, status=status.HTTP_404_NOT_FOUND)
        
        # Supervisors can only delete their own pending requirements
        if user_role == 'Supervisor':
            if requirement['supervisor_id'] != user_id:
                return Response({
                    'error': 'You can only delete your own requirements'
                }, status=status.HTTP_403_FORBIDDEN)
            
            if requirement['status'] != 'pending':
                return Response({
                    'error': 'You can only delete pending requirements'
                }, status=status.HTTP_400_BAD_REQUEST)
        
        # Admin/Accountant can delete any requirement
        elif user_role not in ['Admin', 'Accountant']:
            return Response({
                'error': 'Unauthorized'
            }, status=status.HTTP_403_FORBIDDEN)
        
        # Delete requirement
        execute_query("""
            DELETE FROM material_requirements WHERE id = %s
        """, (requirement_id,))
        
        return Response({
            'success': True,
            'message': 'Material requirement deleted successfully'
        })
        
    except Exception as e:
        print(f"Error deleting material requirement: {e}")
        return Response({
            'error': f'Error deleting requirement: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_all_working_sites(request):
    """
    Admin: Get all active working sites assigned by accountants
    GET /api/construction/admin/all-working-sites/
    
    Returns sites from working_sites table (sites assigned by accountants to supervisors)
    with counts of labour entries, material bills, and photos
    """
    try:
        user_role = request.user.get('role', '')
        
        # Only Admin can view all working sites
        if user_role != 'Admin':
            return Response({
                'error': 'Only Admin can view all working sites'
            }, status=status.HTTP_403_FORBIDDEN)
        
        # Get all active working sites from working_sites table
        sites = fetch_all("""
            SELECT 
                s.id as site_id,
                s.site_name,
                s.customer_name,
                s.area,
                s.street,
                MAX(ws.assigned_date) as assigned_date,
                MAX(ws.description) as description,
                (
                    SELECT COUNT(*) 
                    FROM labour_entries le 
                    WHERE le.site_id = s.id
                ) as labour_count,
                (
                    SELECT COUNT(*) 
                    FROM material_bills mb 
                    WHERE mb.site_id = s.id
                ) as material_count,
                (
                    SELECT COUNT(*) 
                    FROM work_updates wu 
                    WHERE wu.site_id = s.id
                ) as photo_count,
                (
                    SELECT MAX(le.entry_date)
                    FROM labour_entries le
                    WHERE le.site_id = s.id
                ) as last_labour_date,
                (
                    SELECT MAX(mb.created_at)
                    FROM material_bills mb
                    WHERE mb.site_id = s.id
                ) as last_material_update,
                (
                    SELECT MAX(wu.uploaded_at)
                    FROM work_updates wu
                    WHERE wu.site_id = s.id
                ) as last_photo_update
            FROM working_sites ws
            JOIN sites s ON ws.site_id = s.id
            WHERE ws.is_active = TRUE
            GROUP BY s.id, s.site_name, s.customer_name, s.area, s.street
            ORDER BY MAX(ws.assigned_date) DESC
        """)
        
        # Format sites
        formatted_sites = []
        for site in sites:
            # Find the most recent update from all sources
            last_updates = []
            
            # Add labour date if exists (this is a date object)
            if site.get('last_labour_date'):
                from datetime import datetime
                labour_date = site['last_labour_date']
                # Convert date to datetime for comparison
                if not isinstance(labour_date, datetime):
                    labour_date = datetime.combine(labour_date, datetime.min.time())
                # Remove timezone if present
                if labour_date.tzinfo is not None:
                    labour_date = labour_date.replace(tzinfo=None)
                last_updates.append(labour_date)
            
            # Add material and photo updates (these are datetime objects)
            for key in ['last_material_update', 'last_photo_update']:
                if site.get(key):
                    update_val = site[key]
                    # Ensure it's a datetime object
                    if isinstance(update_val, str):
                        update_val = datetime.fromisoformat(update_val)
                    # Remove timezone if present
                    if hasattr(update_val, 'tzinfo') and update_val.tzinfo is not None:
                        update_val = update_val.replace(tzinfo=None)
                    last_updates.append(update_val)
            
            last_update = max(last_updates) if last_updates else None
            
            if last_update:
                # Format as relative time
                from datetime import datetime, timedelta
                now = datetime.now()
                
                diff = now - last_update
                if diff.days == 0:
                    if diff.seconds < 3600:
                        last_update_str = f"{diff.seconds // 60} min ago"
                    else:
                        last_update_str = f"{diff.seconds // 3600} hours ago"
                elif diff.days == 1:
                    last_update_str = "Yesterday"
                elif diff.days < 7:
                    last_update_str = f"{diff.days} days ago"
                else:
                    last_update_str = last_update.strftime('%b %d, %Y')
            else:
                last_update_str = ""
            
            # Create display name
            display_name = f"{site['customer_name']} {site['site_name']}" if site['customer_name'] else site['site_name']
            
            formatted_sites.append({
                'id': str(site['site_id']),
                'site_name': site['site_name'],
                'customer_name': site['customer_name'],
                'display_name': display_name,
                'area': site['area'],
                'street': site['street'],
                'labour_count': site['labour_count'] or 0,
                'material_count': site['material_count'] or 0,
                'photo_count': site['photo_count'] or 0,
                'last_update': last_update_str,
            })
        
        return Response({
            'success': True,
            'sites': formatted_sites,
            'count': len(formatted_sites),
        })
        
    except Exception as e:
        print(f"Error fetching all working sites: {e}")
        import traceback
        traceback.print_exc()
        return Response({
            'error': f'Error fetching working sites: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)



# ============================================
# CASH ENTRIES APIS (ACCOUNTANT)
# ============================================

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def confirm_cash_entry(request):
    """
    Accountant: Confirm a supervisor/engineer entry and save to cash_entries
    POST /api/construction/confirm-cash-entry/
    Body: {
        "site_id": "uuid",
        "entry_date": "YYYY-MM-DD",
        "source_type": "supervisor" or "site_engineer",
        "source_entry_id": "uuid",
        "labour_entries": [{"labour_type": "...", "labour_count": 1, "daily_rate": 600}]
    }
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        if user_role != 'Accountant':
            return Response({'error': 'Only Accountant can confirm cash entries'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        site_id = request.data.get('site_id')
        entry_date_str = request.data.get('entry_date')
        source_type = request.data.get('source_type')  # 'supervisor' or 'site_engineer'
        source_entry_id = request.data.get('source_entry_id')
        labour_entries = request.data.get('labour_entries', [])
        
        print(f"🔍 [CASH ENTRY] Confirming entry - site: {site_id}, date: {entry_date_str}, source: {source_type}")
        
        if not all([site_id, entry_date_str, source_type, labour_entries]):
            return Response({'error': 'site_id, entry_date, source_type, and labour_entries are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Parse date
        try:
            entry_date = datetime.strptime(entry_date_str, '%Y-%m-%d').date()
        except ValueError:
            return Response({'error': 'Invalid date format. Use YYYY-MM-DD'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Check if cash entry already exists for this site and date (any labour type)
        existing = fetch_one("""
            SELECT COUNT(*) as count FROM cash_entries
            WHERE site_id = %s AND entry_date = %s
        """, (site_id, entry_date))
        
        if existing and existing['count'] > 0:
            return Response({
                'error': 'Cash entry already exists for this site and date. Only one entry per site per day is allowed.'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Get submitted_by name from source entry
        submitted_by_name = None
        if source_entry_id:
            source_entry = fetch_one("""
                SELECT u.full_name
                FROM labour_entries l
                JOIN users u ON l.supervisor_id = u.id
                WHERE l.id = %s
            """, (source_entry_id,))
            if source_entry:
                submitted_by_name = source_entry['full_name']
        
        # Insert cash entries for each labour type
        for labour in labour_entries:
            labour_type = labour.get('labour_type')
            labour_count = labour.get('labour_count', 0)
            daily_rate = labour.get('daily_rate', 0)
            total_cost = labour_count * daily_rate
            
            cash_entry_id = str(uuid.uuid4())
            execute_query("""
                INSERT INTO cash_entries
                (id, site_id, accountant_id, entry_date, source_type, source_entry_id,
                 labour_type, labour_count, daily_rate, total_cost, submitted_by_name, created_at)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (cash_entry_id, site_id, user_id, entry_date, source_type, source_entry_id,
                  labour_type, labour_count, daily_rate, total_cost, submitted_by_name, timezone.now()))
        
        print(f"✅ [CASH ENTRY] Created {len(labour_entries)} cash entries")
        
        return Response({
            'message': 'Cash entry confirmed successfully',
            'entries_count': len(labour_entries),
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        print(f"❌ [CASH ENTRY] Error: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def create_custom_cash_entry(request):
    """
    Accountant: Create a custom cash entry (not from supervisor/engineer)
    POST /api/construction/create-custom-cash-entry/
    Body: {
        "site_id": "uuid",
        "entry_date": "YYYY-MM-DD",
        "labour_entries": [{"labour_type": "...", "labour_count": 1, "daily_rate": 600}],
        "notes": "optional notes"
    }
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        if user_role != 'Accountant':
            return Response({'error': 'Only Accountant can create custom cash entries'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        site_id = request.data.get('site_id')
        entry_date_str = request.data.get('entry_date')
        labour_entries = request.data.get('labour_entries', [])
        notes = request.data.get('notes', '')
        
        print(f"🔍 [CUSTOM CASH ENTRY] Creating custom entry - site: {site_id}, date: {entry_date_str}")
        
        if not all([site_id, entry_date_str, labour_entries]):
            return Response({'error': 'site_id, entry_date, and labour_entries are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Parse date
        try:
            entry_date = datetime.strptime(entry_date_str, '%Y-%m-%d').date()
        except ValueError:
            return Response({'error': 'Invalid date format. Use YYYY-MM-DD'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Check if cash entry already exists for this site and date (any labour type)
        existing = fetch_one("""
            SELECT COUNT(*) as count FROM cash_entries
            WHERE site_id = %s AND entry_date = %s
        """, (site_id, entry_date))

        if existing and existing['count'] > 0:
            return Response({
                'error': 'Cash entry already exists for this site and date. Only one entry per site per day is allowed.'
            }, status=status.HTTP_400_BAD_REQUEST)

        # Insert labour entries (not cash entries yet) so accountant can confirm
        labour_entry_ids = []
        for labour in labour_entries:
            labour_type = labour.get('labour_type')
            labour_count = labour.get('labour_count', 0)

            labour_entry_id = str(uuid.uuid4())
            labour_entry_ids.append(labour_entry_id)

            execute_query("""
                INSERT INTO labour_entries
                (id, site_id, entry_date, labour_type, labour_count,
                 submitted_by_id, submitted_by_role, notes, created_at)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (labour_entry_id, site_id, entry_date, labour_type, labour_count,
                  user_id, 'Accountant', notes, timezone.now()))

        # Fetch the created entry with site info so it can be shown in compare screen
        entry_data = fetch_one("""
            SELECT
                l.id, l.site_id, s.customer_name, s.site_name,
                COALESCE(u.full_name, u.phone) as submitted_by,
                l.submitted_by_role, l.created_at as submitted_at
            FROM labour_entries l
            JOIN sites s ON l.site_id = s.id
            LEFT JOIN users u ON l.submitted_by_id = u.id
            WHERE l.site_id = %s AND l.entry_date = %s AND l.submitted_by_role = 'Accountant'
            ORDER BY l.created_at DESC
            LIMIT 1
        """, (site_id, entry_date))

        # Get labour entries for this site+date+accountant
        labour_list = fetch_all("""
            SELECT labour_type, labour_count
            FROM labour_entries
            WHERE site_id = %s AND entry_date = %s AND submitted_by_role = 'Accountant'
        """, (site_id, entry_date))

        print(f"✅ [CUSTOM ENTRY] Created {len(labour_entries)} labour entries for accountant confirmation")

        return Response({
            'message': 'Custom entry created. Please confirm selection.',
            'entry': {
                'id': entry_data['id'] if entry_data else None,
                'site_id': site_id,
                'site_name': f"{entry_data['customer_name']} {entry_data['site_name']}" if entry_data else 'Unknown',
                'submitted_by': entry_data['submitted_by'] if entry_data else 'Accountant',
                'submitted_by_role': 'Accountant',
                'submitted_at': entry_data['submitted_at'].isoformat() if entry_data and entry_data['submitted_at'] else None,
                'labour_entries': labour_list,
            }
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        print(f"❌ [CUSTOM CASH ENTRY] Error: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def check_cash_entry_exists(request):
    """
    Check if a cash entry already exists for a site and date
    GET /api/construction/check-cash-entry/?site_id=xxx&date=YYYY-MM-DD
    """
    try:
        site_id = request.query_params.get('site_id')
        date_str = request.query_params.get('date')
        
        if not site_id or not date_str:
            return Response({'error': 'site_id and date are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        existing = fetch_one("""
            SELECT ce.id, ce.source_type, ce.created_at, u.full_name as accountant_name
            FROM cash_entries ce
            LEFT JOIN users u ON ce.accountant_id = u.id
            WHERE ce.site_id = %s AND ce.entry_date = %s
            LIMIT 1
        """, (site_id, date_str))
        
        return Response({
            'exists': existing is not None,
            'entry': {
                'id': str(existing['id']),
                'source_type': existing['source_type'],
                'created_at': existing['created_at'].isoformat(),
                'accountant_name': existing.get('accountant_name', 'An accountant'),
            } if existing else None
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
