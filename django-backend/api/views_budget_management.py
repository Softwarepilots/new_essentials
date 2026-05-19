"""
Budget Management System APIs
- Budget Allocation
- Labour Salary Rates
- Material Cost Tracking
- Budget Utilization
"""
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework import status
from .authentication import JWTAuthentication
from .database import fetch_all, fetch_one, execute_query
from datetime import datetime
import uuid

# ============================================
# BUDGET ALLOCATION APIs
# ============================================

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def allocate_budget(request):
    """
    Admin: Allocate budget for a site (creates new budget allocation)
    POST /api/budget/allocate/
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        if user_role != 'Admin':
            return Response({'error': 'Only Admin can allocate budget'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        site_id = request.data.get('site_id')
        total_budget = request.data.get('total_budget')
        material_budget = request.data.get('material_budget')
        labour_budget = request.data.get('labour_budget')
        other_budget = request.data.get('other_budget')
        client_balance = request.data.get('client_balance')
        notes = request.data.get('notes', '')
        
        if not all([site_id, total_budget]):
            return Response({'error': 'site_id and total_budget are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # If client_balance not provided, default to total_budget
        if client_balance is None:
            client_balance = total_budget
        
        # Check if budget already exists
        existing = fetch_one("""
            SELECT id FROM site_budget_allocation
            WHERE site_id = %s AND status = 'ACTIVE'
        """, (site_id,))
        
        if existing:
            return Response({'error': 'Budget already exists for this site. Use PUT /api/budget/update/ to update it.'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Create new budget allocation
        budget_id = str(uuid.uuid4())
        execute_query("""
            INSERT INTO site_budget_allocation
            (id, site_id, allocated_by, total_budget, material_budget, labour_budget, 
             other_budget, client_balance, notes)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        """, (budget_id, site_id, user_id, total_budget, material_budget, labour_budget, 
              other_budget, client_balance, notes))
        
        return Response({
            'message': 'Budget allocated successfully',
            'budget_id': budget_id
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['PUT'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def update_budget(request):
    """
    Admin: Update existing budget allocation
    PUT /api/budget/update/
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        if user_role != 'Admin':
            return Response({'error': 'Only Admin can update budget'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        site_id = request.data.get('site_id')
        total_budget = request.data.get('total_budget')
        material_budget = request.data.get('material_budget')
        labour_budget = request.data.get('labour_budget')
        other_budget = request.data.get('other_budget')
        client_balance = request.data.get('client_balance')
        notes = request.data.get('notes', '')
        
        if not all([site_id, total_budget]):
            return Response({'error': 'site_id and total_budget are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # If client_balance not provided, default to total_budget
        if client_balance is None:
            client_balance = total_budget
        
        # Get existing active budget
        existing = fetch_one("""
            SELECT id FROM site_budget_allocation
            WHERE site_id = %s AND status = 'ACTIVE'
        """, (site_id,))
        
        if not existing:
            return Response({'error': 'No active budget found for this site. Use POST /api/budget/allocate/ to create one.'}, 
                          status=status.HTTP_404_NOT_FOUND)
        
        # Update the existing budget directly (no history tracking)
        execute_query("""
            UPDATE site_budget_allocation
            SET total_budget = %s,
                material_budget = %s,
                labour_budget = %s,
                other_budget = %s,
                client_balance = %s,
                notes = %s,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = %s
        """, (total_budget, material_budget, labour_budget, other_budget, 
              client_balance, notes, existing['id']))
        
        return Response({
            'message': 'Budget updated successfully',
            'budget_id': str(existing['id'])
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        print(f"❌ Error updating budget: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# Keep old allocate_budget for backward compatibility but make it smart
@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def allocate_or_update_budget(request):
    """
    Admin: Allocate or update budget for a site (smart endpoint)
    POST /api/budget/allocate-or-update/
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        if user_role != 'Admin':
            return Response({'error': 'Only Admin can allocate budget'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        site_id = request.data.get('site_id')
        total_budget = request.data.get('total_budget')
        material_budget = request.data.get('material_budget')
        labour_budget = request.data.get('labour_budget')
        other_budget = request.data.get('other_budget')
        client_balance = request.data.get('client_balance')
        notes = request.data.get('notes', '')
        
        if not all([site_id, total_budget]):
            return Response({'error': 'site_id and total_budget are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # If client_balance not provided, default to total_budget
        if client_balance is None:
            client_balance = total_budget
        
        # Check if budget already exists
        existing = fetch_one("""
            SELECT id FROM site_budget_allocation
            WHERE site_id = %s AND status = 'ACTIVE'
        """, (site_id,))
        
        if existing:
            # Update existing budget
            execute_query("""
                UPDATE site_budget_allocation
                SET total_budget = %s,
                    material_budget = %s,
                    labour_budget = %s,
                    other_budget = %s,
                    client_balance = %s,
                    notes = %s,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
            """, (total_budget, material_budget, labour_budget, other_budget, 
                  client_balance, notes, existing['id']))
            
            return Response({
                'message': 'Budget updated successfully',
                'budget_id': str(existing['id'])
            }, status=status.HTTP_200_OK)
        else:
            # Create new budget
            budget_id = str(uuid.uuid4())
            execute_query("""
                INSERT INTO site_budget_allocation
                (id, site_id, allocated_by, total_budget, material_budget, labour_budget, 
                 other_budget, client_balance, notes)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (budget_id, site_id, user_id, total_budget, material_budget, labour_budget, 
                  other_budget, client_balance, notes))
            
            return Response({
                'message': 'Budget allocated successfully',
                'budget_id': budget_id
            }, status=status.HTTP_201_CREATED)
        
        return Response({
            'message': 'Budget allocated successfully',
            'budget_id': budget_id
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_budget_allocation(request, site_id):
    """
    Get current budget allocation for a site
    GET /api/budget/allocation/{site_id}/
    """
    try:
        budget = fetch_one("""
            SELECT 
                sba.*,
                u.full_name as allocated_by_name
            FROM site_budget_allocation sba
            JOIN users u ON sba.allocated_by = u.id
            WHERE sba.site_id = %s AND sba.status = 'ACTIVE'
        """, (site_id,))
        
        if not budget:
            return Response({'error': 'No active budget found for this site'}, 
                          status=status.HTTP_404_NOT_FOUND)
        
        return Response({
            'budget': {
                'id': str(budget['id']),
                'total_budget': float(budget['total_budget']),
                'material_budget': float(budget['material_budget']) if budget['material_budget'] else None,
                'labour_budget': float(budget['labour_budget']) if budget['labour_budget'] else None,
                'other_budget': float(budget['other_budget']) if budget['other_budget'] else None,
                'status': budget['status'],
                'notes': budget['notes'],
                'allocated_by': budget['allocated_by_name'],
                'allocated_date': budget['allocated_date'].isoformat() if budget['allocated_date'] else None,
            }
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ============================================
# LABOUR SALARY RATES APIs
# ============================================

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def set_labour_rate(request):
    """
    Admin: Set daily salary rate for labour type
    POST /api/budget/labour-rate/
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        if user_role != 'Admin':
            return Response({'error': 'Only Admin can set labour rates'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        raw_site_id = request.data.get('site_id')
        labour_type = request.data.get('labour_type')
        daily_rate = request.data.get('daily_rate')
        effective_from = request.data.get('effective_from', datetime.now().date())
        notes = request.data.get('notes', '')

        # 'global' means NULL site_id (applies to all sites)
        site_id = None if raw_site_id in (None, '', 'global') else raw_site_id

        if not all([labour_type, daily_rate]):
            return Response({'error': 'labour_type and daily_rate are required'},
                          status=status.HTTP_400_BAD_REQUEST)

        # Deactivate existing rate for this labour type
        if site_id is None:
            execute_query("""
                UPDATE labour_salary_rates
                SET is_active = FALSE, effective_to = CURRENT_DATE, updated_at = CURRENT_TIMESTAMP
                WHERE site_id IS NULL AND labour_type = %s AND is_active = TRUE
            """, (labour_type,))
        else:
            execute_query("""
                UPDATE labour_salary_rates
                SET is_active = FALSE, effective_to = CURRENT_DATE, updated_at = CURRENT_TIMESTAMP
                WHERE site_id = %s AND labour_type = %s AND is_active = TRUE
            """, (site_id, labour_type))

        # Create new rate
        rate_id = str(uuid.uuid4())
        execute_query("""
            INSERT INTO labour_salary_rates
            (id, site_id, labour_type, daily_rate, effective_from, set_by, notes)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
        """, (rate_id, site_id, labour_type, daily_rate, effective_from, user_id, notes))
        
        return Response({
            'success': True,
            'message': 'Labour rate set successfully',
            'rate_id': rate_id
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# Canonical default rates — single source of truth used by all screens
CANONICAL_DEFAULT_RATES = {
    'General': 600,
    'Mason': 800,
    'Helper': 500,
    'Carpenter': 750,
    'Plumber': 700,
    'Electrician': 750,
    'Painter': 650,
    'Tile Layer': 700,
    'Tile Layerhelper': 700,
    'Kambi Fitter': 900,
    'Concrete Kot': 950,
    'Pile Labour': 800,
}

@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_labour_rates(request, site_id):
    """
    Get all active labour rates.
    For site_id='global': returns all labour types — canonical defaults + custom types added by admin.
    This is the single source of truth for all screens.
    GET /api/budget/labour-rates/{site_id}/
    """
    try:
        if site_id == 'global':
            # Fetch only admin-set global rates
            db_rates = fetch_all("""
                SELECT
                    lsr.*,
                    u.full_name as set_by_name
                FROM labour_salary_rates lsr
                JOIN users u ON lsr.set_by = u.id
                WHERE lsr.site_id IS NULL AND lsr.is_active = TRUE
                ORDER BY lsr.labour_type
            """)
            # Index by labour_type
            db_map = {r['labour_type']: r for r in db_rates}

            # Return all canonical types, using DB rate where admin has set one
            result = []
            for labour_type, default_rate in CANONICAL_DEFAULT_RATES.items():
                if labour_type in db_map:
                    r = db_map[labour_type]
                    result.append({
                        'id': str(r['id']),
                        'labour_type': labour_type,
                        'daily_rate': float(r['daily_rate']),
                        'effective_from': r['effective_from'].isoformat() if r['effective_from'] else None,
                        'set_by': r['set_by_name'],
                        'notes': r['notes'],
                        'is_admin_set': True,
                    })
                else:
                    result.append({
                        'id': None,
                        'labour_type': labour_type,
                        'daily_rate': float(default_rate),
                        'effective_from': None,
                        'set_by': None,
                        'notes': '',
                        'is_admin_set': False,
                    })
            
            # Add custom labour types not in canonical list
            for labour_type, r in db_map.items():
                if labour_type not in CANONICAL_DEFAULT_RATES:
                    result.append({
                        'id': str(r['id']),
                        'labour_type': labour_type,
                        'daily_rate': float(r['daily_rate']),
                        'effective_from': r['effective_from'].isoformat() if r['effective_from'] else None,
                        'set_by': r['set_by_name'],
                        'notes': r['notes'],
                        'is_admin_set': True,
                    })
            
            return Response({'rates': result}, status=status.HTTP_200_OK)
        else:
            rates = fetch_all("""
                SELECT
                    lsr.*,
                    u.full_name as set_by_name
                FROM labour_salary_rates lsr
                JOIN users u ON lsr.set_by = u.id
                WHERE lsr.site_id = %s AND lsr.is_active = TRUE
                ORDER BY lsr.labour_type
            """, (site_id,))
            return Response({
                'rates': [
                    {
                        'id': str(r['id']),
                        'labour_type': r['labour_type'],
                        'daily_rate': float(r['daily_rate']),
                        'effective_from': r['effective_from'].isoformat() if r['effective_from'] else None,
                        'set_by': r['set_by_name'],
                        'notes': r['notes'],
                        'is_admin_set': True,
                    }
                    for r in rates
                ]
            }, status=status.HTTP_200_OK)

    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ============================================
# BUDGET UTILIZATION APIs
# ============================================

@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_budget_utilization(request, site_id):
    """
    Get complete budget utilization summary for a site
    GET /api/budget/utilization/{site_id}/?date=YYYY-MM-DD&filter=material|labour|other (optional)
    
    IMPORTANT: Labour costs are now read from cash_entries table (accountant-confirmed entries)
    instead of labour_cost_calculation table (raw supervisor/engineer entries)
    
    Optional parameters:
    - date: Filter labour entries by specific date
    - filter: Filter by cost type (material, labour, other, or empty for all)
    """
    try:
        # Get optional filters
        filter_date = request.query_params.get('date')
        filter_type = request.query_params.get('filter', '').lower()  # material, labour, other
        
        # Get summary from view
        summary = fetch_one("""
            SELECT * FROM budget_utilization_summary
            WHERE site_id = %s
        """, (site_id,))
        
        if not summary:
            return Response({'error': 'No budget allocation found for this site'}, 
                          status=status.HTTP_404_NOT_FOUND)
        
        # Initialize costs
        material_costs = []
        labour_costs = []
        total_material_cost = 0
        total_labour_cost = 0
        total_vendor_cost = 0
        
        # Get material costs (if not filtering or filtering for material)
        if not filter_type or filter_type == 'material':
            material_costs = fetch_all("""
                SELECT 
                    material_type,
                    SUM(total_cost) as total_cost,
                    SUM(quantity) as total_quantity,
                    unit
                FROM material_cost_tracking
                WHERE site_id = %s
                GROUP BY material_type, unit
                ORDER BY total_cost DESC
            """, (site_id,))
            total_material_cost = sum(float(m['total_cost']) for m in material_costs)
        
        # Get labour costs from cash_entries table (if not filtering or filtering for labour)
        if not filter_type or filter_type == 'labour':
            # Apply date filter if provided
            if filter_date:
                labour_costs = fetch_all("""
                    SELECT 
                        labour_type,
                        SUM(labour_count) as total_count,
                        AVG(daily_rate) as avg_rate,
                        SUM(total_cost) as total_cost
                    FROM cash_entries
                    WHERE site_id = %s AND entry_date = %s
                    GROUP BY labour_type
                    ORDER BY total_cost DESC
                """, (site_id, filter_date))
            else:
                labour_costs = fetch_all("""
                    SELECT 
                        labour_type,
                        SUM(labour_count) as total_count,
                        AVG(daily_rate) as avg_rate,
                        SUM(total_cost) as total_cost
                    FROM cash_entries
                    WHERE site_id = %s
                    GROUP BY labour_type
                    ORDER BY total_cost DESC
                """, (site_id,))
            total_labour_cost = sum(float(l['total_cost']) for l in labour_costs)
        
        # Get vendor costs (if not filtering or filtering for other)
        if not filter_type or filter_type == 'other':
            vendor_costs = fetch_all("""
                SELECT 
                    vendor_type,
                    service_type,
                    SUM(final_amount) as total_cost
                FROM vendor_bills
                WHERE site_id = %s AND is_active = TRUE
                GROUP BY vendor_type, service_type
                ORDER BY total_cost DESC
            """, (site_id,))
            total_vendor_cost = sum(float(v['total_cost']) for v in vendor_costs)
        else:
            vendor_costs = []
        
        # Calculate total spent based on filter
        if filter_type == 'material':
            total_spent_corrected = total_material_cost
        elif filter_type == 'labour':
            total_spent_corrected = total_labour_cost
        elif filter_type == 'other':
            total_spent_corrected = total_vendor_cost
        else:
            # No filter - show all
            total_spent_corrected = total_material_cost + total_labour_cost + total_vendor_cost
        
        # Recalculate remaining budget
        remaining_budget_corrected = float(summary['total_budget']) - total_spent_corrected
        
        # Recalculate utilization percentage
        utilization_percentage_corrected = (
            (total_spent_corrected / float(summary['total_budget']) * 100) 
            if float(summary['total_budget']) > 0 else 0
        )
        
        return Response({
            'summary': {
                'total_budget': float(summary['total_budget']),
                'material_budget': float(summary['material_budget']) if summary['material_budget'] else None,
                'labour_budget': float(summary['labour_budget']) if summary['labour_budget'] else None,
                'other_budget': float(summary['other_budget']) if summary['other_budget'] else None,
                'total_material_cost': total_material_cost,
                'total_labour_cost': total_labour_cost,
                'total_vendor_cost': total_vendor_cost,
                'total_spent': total_spent_corrected,
                'remaining_budget': remaining_budget_corrected,
                'utilization_percentage': utilization_percentage_corrected,
                'status': summary['status'],
                'filter_active': filter_type or filter_date,
                'filter_type': filter_type if filter_type else 'all',
                'filter_date': filter_date,
            },
            'material_breakdown': [
                {
                    'material_type': m['material_type'],
                    'total_cost': float(m['total_cost']),
                    'total_quantity': float(m['total_quantity']),
                    'unit': m['unit'],
                }
                for m in material_costs
            ],
            'labour_breakdown': [
                {
                    'labour_type': l['labour_type'],
                    'total_count': int(l['total_count']),
                    'avg_rate': float(l['avg_rate']),
                    'total_cost': float(l['total_cost']),
                }
                for l in labour_costs
            ],
            'other_breakdown': [
                {
                    'vendor_type': v['vendor_type'],
                    'service_type': v['service_type'],
                    'total_cost': float(v['total_cost']),
                }
                for v in vendor_costs
            ]
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_labour_cost_details(request, site_id):
    """
    Get detailed labour cost calculations for a site
    GET /api/budget/labour-costs/{site_id}/
    
    IMPORTANT: Now reads from cash_entries table (accountant-confirmed entries)
    """
    try:
        costs = fetch_all("""
            SELECT 
                ce.id,
                ce.labour_type,
                ce.labour_count,
                ce.daily_rate,
                ce.total_cost,
                ce.entry_date,
                ce.source_type,
                ce.submitted_by_name,
                ce.notes,
                ce.created_at
            FROM cash_entries ce
            WHERE ce.site_id = %s
            ORDER BY ce.entry_date DESC, ce.created_at DESC
            LIMIT 100
        """, (site_id,))
        
        return Response({
            'costs': [
                {
                    'id': str(c['id']),
                    'labour_type': c['labour_type'],
                    'labour_count': c['labour_count'],
                    'daily_rate': float(c['daily_rate']),
                    'total_cost': float(c['total_cost']),
                    'entry_date': c['entry_date'].isoformat() if c['entry_date'] else None,
                    'source_type': c['source_type'],
                    'submitted_by': c['submitted_by_name'],
                    'notes': c.get('notes', ''),
                    'created_at': c['created_at'].isoformat() if c.get('created_at') else None,
                }
                for c in costs
            ]
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def delete_labour_type(request):
    """
    Admin: Delete a labour type (only custom types, not canonical defaults)
    POST /api/budget/delete-labour-type/
    """
    try:
        user_role = request.user.get('role', '')
        
        if user_role != 'Admin':
            return Response({'error': 'Only Admin can delete labour types'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        labour_type = request.data.get('labour_type')
        
        if not labour_type:
            return Response({'error': 'labour_type is required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Prevent deletion of canonical defaults
        if labour_type in CANONICAL_DEFAULT_RATES:
            return Response({
                'error': f'Cannot delete canonical labour type: {labour_type}',
                'message': 'Canonical labour types cannot be deleted for system integrity'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Check if labour type exists
        existing = fetch_one("""
            SELECT COUNT(*) as count
            FROM labour_salary_rates
            WHERE labour_type = %s AND is_active = TRUE
        """, (labour_type,))
        
        if not existing or existing['count'] == 0:
            return Response({
                'error': f'Labour type "{labour_type}" not found'
            }, status=status.HTTP_404_NOT_FOUND)
        
        # Soft delete - deactivate all rates for this labour type
        execute_query("""
            UPDATE labour_salary_rates
            SET is_active = FALSE, 
                effective_to = CURRENT_DATE,
                updated_at = CURRENT_TIMESTAMP
            WHERE labour_type = %s AND is_active = TRUE
        """, (labour_type,))
        
        return Response({
            'success': True,
            'message': f'Labour type "{labour_type}" deleted successfully'
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        print(f"❌ Error deleting labour type: {str(e)}")
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ============================================
# LOCAL LABOUR RATES APIs (Area-specific)
# ============================================

@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_local_labour_rates(request, area):
    """
    Get local labour rates for a specific area
    GET /api/budget/local-labour-rates/<area>/
    """
    try:
        user_role = request.user.get('role', '')
        
        if user_role != 'Admin':
            return Response({'error': 'Only Admin can view local rates'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        # Get local rates for the area
        rates = fetch_all("""
            SELECT labour_type, daily_rate, effective_from, notes
            FROM labour_salary_rates
            WHERE area = %s AND is_active = TRUE
            ORDER BY labour_type
        """, (area,))
        
        return Response({
            'area': area,
            'rates': [
                {
                    'labour_type': r['labour_type'],
                    'daily_rate': float(r['daily_rate']),
                    'effective_from': r['effective_from'].isoformat() if r.get('effective_from') else None,
                    'notes': r.get('notes', '')
                }
                for r in rates
            ]
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        print(f"❌ Error fetching local labour rates: {str(e)}")
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def set_local_labour_rate(request):
    """
    Admin: Set local labour rate for a specific area
    POST /api/budget/local-labour-rate/
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        if user_role != 'Admin':
            return Response({'error': 'Only Admin can set local rates'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        area = request.data.get('area')
        labour_type = request.data.get('labour_type')
        daily_rate = request.data.get('daily_rate')
        notes = request.data.get('notes', '')
        
        if not all([area, labour_type, daily_rate]):
            return Response({'error': 'area, labour_type, and daily_rate are required'}, 
                          status=status.HTTP_400_BAD_REQUEST)
        
        # Deactivate any existing active rate for this area and labour type
        execute_query("""
            UPDATE labour_salary_rates
            SET is_active = FALSE
            WHERE area = %s AND labour_type = %s AND is_active = TRUE
        """, (area, labour_type))
        
        # Insert new local rate
        rate_id = str(uuid.uuid4())
        execute_query("""
            INSERT INTO labour_salary_rates 
            (id, area, labour_type, daily_rate, effective_from, is_active, notes, set_by, created_at)
            VALUES (%s, %s, %s, %s, CURRENT_DATE, TRUE, %s, %s, CURRENT_TIMESTAMP)
        """, (rate_id, area, labour_type, daily_rate, notes, user_id))
        
        return Response({
            'success': True,
            'message': f'Local rate set for {labour_type} in {area}',
            'rate_id': rate_id,
            'area': area,
            'labour_type': labour_type,
            'daily_rate': daily_rate
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        print(f"❌ Error setting local labour rate: {str(e)}")
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ============================================
# MATERIAL & OTHER COST ENTRY APIs
# ============================================

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def add_material_cost(request):
    """
    Admin: Add material cost entry
    POST /api/budget/add-material-cost/
    Body: {
        "site_id": "uuid",
        "material_type": "Cement",
        "quantity": 50,
        "unit": "bags",
        "unit_cost": 400,
        "total_cost": 20000,
        "entry_date": "2026-05-08",
        "notes": "optional"
    }
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        if user_role != 'Admin':
            return Response({'error': 'Only Admin can add material costs'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        site_id = request.data.get('site_id')
        material_type = request.data.get('material_type')
        quantity = request.data.get('quantity')
        unit = request.data.get('unit')
        unit_cost = request.data.get('unit_cost')
        total_cost = request.data.get('total_cost')
        entry_date = request.data.get('entry_date', datetime.now().date())
        notes = request.data.get('notes', '')
        
        if not all([site_id, material_type, quantity, unit, unit_cost, total_cost]):
            return Response({
                'error': 'site_id, material_type, quantity, unit, unit_cost, and total_cost are required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Insert material cost
        cost_id = str(uuid.uuid4())
        execute_query("""
            INSERT INTO material_cost_tracking
            (id, site_id, material_type, quantity, unit, unit_cost, total_cost, 
             recorded_by, recorded_date, notes, created_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
        """, (cost_id, site_id, material_type, quantity, unit, unit_cost, 
              total_cost, user_id, entry_date, notes))
        
        return Response({
            'success': True,
            'message': 'Material cost added successfully',
            'cost_id': cost_id
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        print(f"❌ Error adding material cost: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def add_other_cost(request):
    """
    Admin: Add other cost entry (vendor bills, services, etc.)
    POST /api/budget/add-other-cost/
    Body: {
        "site_id": "uuid",
        "cost_type": "Transport",
        "description": "Material transport from warehouse",
        "amount": 5000,
        "entry_date": "2026-05-08",
        "notes": "optional"
    }
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        if user_role != 'Admin':
            return Response({'error': 'Only Admin can add other costs'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        site_id = request.data.get('site_id')
        cost_type = request.data.get('cost_type')
        description = request.data.get('description', '')
        amount = request.data.get('amount')
        entry_date = request.data.get('entry_date', datetime.now().date())
        notes = request.data.get('notes', '')
        
        if not all([site_id, cost_type, amount]):
            return Response({
                'error': 'site_id, cost_type, and amount are required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Get day of week
        from datetime import datetime as dt
        if isinstance(entry_date, str):
            date_obj = dt.strptime(entry_date, '%Y-%m-%d')
        else:
            date_obj = entry_date
        day_of_week = date_obj.strftime('%A').upper()
        
        # Insert vendor bill (other cost)
        bill_id = str(uuid.uuid4())
        bill_number = f"OTHER-{datetime.now().strftime('%Y%m%d%H%M%S')}"
        
        execute_query("""
            INSERT INTO vendor_bills
            (id, site_id, uploaded_by, bill_number, bill_date, vendor_name, vendor_type,
             service_type, service_description, amount, tax_amount, discount_amount, 
             final_amount, payment_status, file_url, file_name, notes, upload_date, 
             day_of_week, is_active, created_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
        """, (bill_id, site_id, user_id, bill_number, entry_date, 'Admin Entry', 'Other',
              cost_type, description, amount, 0, 0, amount, 'PAID', 
              'manual_entry', 'manual_entry.txt', notes, entry_date, day_of_week, True))
        
        return Response({
            'success': True,
            'message': 'Other cost added successfully',
            'bill_id': bill_id
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        print(f"❌ Error adding other cost: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ============================================
# PHASE PAYMENT MANAGEMENT APIs
# ============================================

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def record_phase_payment(request):
    """
    Admin: Record a phase payment from client
    POST /api/budget/record-phase-payment/
    Body: {
        "site_id": "uuid",
        "phase_number": 1,
        "phase_amount": 1000000,
        "payment_date": "2026-05-08",
        "notes": "optional"
    }
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        if user_role != 'Admin':
            return Response({'error': 'Only Admin can record phase payments'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        site_id = request.data.get('site_id')
        phase_number = request.data.get('phase_number')
        phase_amount = request.data.get('phase_amount')
        payment_date = request.data.get('payment_date', datetime.now().date())
        notes = request.data.get('notes', '')
        
        if not all([site_id, phase_number, phase_amount]):
            return Response({
                'error': 'site_id, phase_number, and phase_amount are required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        if phase_number < 1 or phase_number > 10:
            return Response({
                'error': 'phase_number must be between 1 and 10'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Get active budget allocation
        budget = fetch_one("""
            SELECT id, total_budget, client_balance
            FROM site_budget_allocation
            WHERE site_id = %s AND status = 'ACTIVE'
        """, (site_id,))
        
        if not budget:
            return Response({
                'error': 'No active budget allocation found for this site'
            }, status=status.HTTP_404_NOT_FOUND)
        
        budget_id = budget['id']
        current_balance = float(budget['client_balance'] or budget['total_budget'])
        
        # Check if phase already exists
        existing_phase = fetch_one("""
            SELECT id, phase_amount FROM budget_phase_payments
            WHERE budget_allocation_id = %s AND phase_number = %s
        """, (budget_id, phase_number))
        
        if existing_phase:
            return Response({
                'error': f'Phase {phase_number} payment already recorded'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Check if amount exceeds balance
        if float(phase_amount) > current_balance:
            return Response({
                'error': f'Phase amount (₹{phase_amount}) exceeds client balance (₹{current_balance})'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Insert phase payment
        payment_id = str(uuid.uuid4())
        execute_query("""
            INSERT INTO budget_phase_payments
            (id, site_id, budget_allocation_id, phase_number, phase_amount, 
             payment_date, recorded_by, notes)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """, (payment_id, site_id, budget_id, phase_number, phase_amount, 
              payment_date, user_id, notes))
        
        # Update client balance
        new_balance = current_balance - float(phase_amount)
        execute_query("""
            UPDATE site_budget_allocation
            SET client_balance = %s, updated_at = CURRENT_TIMESTAMP
            WHERE id = %s
        """, (new_balance, budget_id))
        
        return Response({
            'success': True,
            'message': f'Phase {phase_number} payment recorded successfully',
            'payment_id': payment_id,
            'new_balance': new_balance
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        print(f"❌ Error recording phase payment: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_phase_payments(request, site_id):
    """
    Get all phase payments for a site
    GET /api/budget/phase-payments/<site_id>/
    """
    try:
        # Get active budget
        budget = fetch_one("""
            SELECT id, total_budget, client_balance
            FROM site_budget_allocation
            WHERE site_id = %s AND status = 'ACTIVE'
        """, (site_id,))
        
        if not budget:
            return Response({
                'total_budget': 0,
                'client_balance': 0,
                'total_received': 0,
                'phases': []
            }, status=status.HTTP_200_OK)
        
        # Get all phase payments
        phases = fetch_all("""
            SELECT 
                pp.id,
                pp.phase_number,
                pp.phase_amount,
                pp.payment_date,
                pp.notes,
                pp.created_at,
                u.full_name as recorded_by_name
            FROM budget_phase_payments pp
            JOIN users u ON pp.recorded_by = u.id
            WHERE pp.budget_allocation_id = %s
            ORDER BY pp.phase_number ASC
        """, (budget['id'],))
        
        total_received = sum(float(p['phase_amount']) for p in phases)
        
        return Response({
            'total_budget': float(budget['total_budget']),
            'client_balance': float(budget['client_balance'] or budget['total_budget']),
            'total_received': total_received,
            'phases': [
                {
                    'id': str(p['id']),
                    'phase_number': p['phase_number'],
                    'phase_amount': float(p['phase_amount']),
                    'payment_date': p['payment_date'].isoformat() if p['payment_date'] else None,
                    'notes': p['notes'],
                    'recorded_by': p['recorded_by_name'],
                    'created_at': p['created_at'].isoformat() if p['created_at'] else None,
                }
                for p in phases
            ]
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        print(f"❌ Error fetching phase payments: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['PUT'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def update_phase_payment(request):
    """
    Admin: Update a phase payment amount
    PUT /api/budget/update-phase-payment/
    Body: {
        "site_id": "uuid",
        "phase_number": 1,
        "phase_amount": 1000000,
        "payment_date": "2026-05-08",
        "notes": "optional"
    }
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')

        if user_role != 'Admin':
            return Response({'error': 'Only Admin can update phase payments'},
                          status=status.HTTP_403_FORBIDDEN)

        site_id = request.data.get('site_id')
        phase_number = request.data.get('phase_number')
        phase_amount = request.data.get('phase_amount')
        payment_date = request.data.get('payment_date')
        notes = request.data.get('notes', '')

        if not all([site_id, phase_number, phase_amount]):
            return Response({
                'error': 'site_id, phase_number, and phase_amount are required'
            }, status=status.HTTP_400_BAD_REQUEST)

        if phase_number < 1 or phase_number > 10:
            return Response({
                'error': 'phase_number must be between 1 and 10'
            }, status=status.HTTP_400_BAD_REQUEST)

        # Get active budget allocation
        budget = fetch_one("""
            SELECT id, total_budget, client_balance
            FROM site_budget_allocation
            WHERE site_id = %s AND status = 'ACTIVE'
        """, (site_id,))

        if not budget:
            return Response({
                'error': 'No active budget allocation found for this site'
            }, status=status.HTTP_404_NOT_FOUND)

        budget_id = budget['id']
        current_balance = float(budget['client_balance'] or budget['total_budget'])

        # Get existing phase payment
        existing_phase = fetch_one("""
            SELECT id, phase_amount FROM budget_phase_payments
            WHERE budget_allocation_id = %s AND phase_number = %s
        """, (budget_id, phase_number))

        if not existing_phase:
            return Response({
                'error': f'Phase {phase_number} payment not found'
            }, status=status.HTTP_404_NOT_FOUND)

        old_amount = float(existing_phase['phase_amount'])
        new_amount = float(phase_amount)
        amount_difference = new_amount - old_amount

        # Check if new amount would exceed total budget when adjusting balance
        new_balance = current_balance - amount_difference
        if new_balance < 0:
            return Response({
                'error': f'New phase amount would exceed available balance'
            }, status=status.HTTP_400_BAD_REQUEST)

        # Update phase payment
        execute_query("""
            UPDATE budget_phase_payments
            SET phase_amount = %s, payment_date = %s, notes = %s, updated_at = CURRENT_TIMESTAMP
            WHERE budget_allocation_id = %s AND phase_number = %s
        """, (new_amount, payment_date or datetime.now().date(), notes, budget_id, phase_number))

        # Update client balance with the difference
        execute_query("""
            UPDATE site_budget_allocation
            SET client_balance = %s, updated_at = CURRENT_TIMESTAMP
            WHERE id = %s
        """, (new_balance, budget_id))

        return Response({
            'success': True,
            'message': f'Phase {phase_number} payment updated successfully',
            'new_balance': new_balance
        }, status=status.HTTP_200_OK)

    except Exception as e:
        print(f"❌ Error updating phase payment: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
