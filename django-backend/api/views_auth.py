"""
Authentication Views - Custom Form-Based Auth
NO Firebase - Pure Django + JWT
"""
from rest_framework.decorators import api_view, permission_classes, authentication_classes
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from django.contrib.auth.hashers import make_password, check_password
from django.utils import timezone
from .authentication import JWTAuthentication
from .jwt_utils import generate_access_token
from .database import execute_query, fetch_one, fetch_all
import uuid


@api_view(['POST'])
@permission_classes([AllowAny])
def register(request):
    """
    User Registration
    
    POST /api/auth/register/
    
    Request body:
    {
        "username": "ravi_kumar",
        "email": "ravi@gmail.com",
        "phone": "9876543210",
        "password": "SecurePass123",
        "full_name": "Ravi Kumar",
        "role": "Supervisor"  // Supervisor, Site Engineer, Accountant, Architect, Owner
    }
    
    Response:
    {
        "message": "Registration successful. Please wait for admin approval.",
        "user_id": "uuid",
        "status": "PENDING"
    }
    """
    try:
        # Get data from request
        username = request.data.get('username')
        email = request.data.get('email')
        phone = request.data.get('phone')
        password = request.data.get('password')
        full_name = request.data.get('full_name')
        role_name = request.data.get('role')
        
        # Validate required fields
        if not all([username, email, phone, password, role_name]):
            return Response({
                'error': 'All fields are required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Check if username already exists
        existing_user = fetch_one(
            "SELECT id FROM users WHERE username = %s OR email = %s",
            (username, email)
        )
        
        if existing_user:
            return Response({
                'error': 'Username or email already exists'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Get role_id
        role = fetch_one("SELECT id FROM roles WHERE role_name = %s", (role_name,))
        if not role:
            return Response({
                'error': 'Invalid role'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Hash password
        password_hash = make_password(password)
        
        # Generate UUID
        user_id = str(uuid.uuid4())
        
        # Insert user
        execute_query("""
            INSERT INTO users (id, username, email, phone, password_hash, full_name, role_id, status)
            VALUES (%s, %s, %s, %s, %s, %s, %s, 'PENDING')
        """, (user_id, username, email, phone, password_hash, full_name, role['id']))
        
        return Response({
            'message': 'Registration successful. Please wait for admin approval.',
            'user_id': user_id,
            'status': 'PENDING'
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        return Response({
            'error': f'Registration failed: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@permission_classes([AllowAny])
def login(request):
    """
    User Login
    
    POST /api/auth/login/
    
    Request body:
    {
        "username": "ravi_kumar",
        "password": "SecurePass123"
    }
    
    Response:
    {
        "access_token": "jwt_token",
        "user": {
            "id": "uuid",
            "username": "ravi_kumar",
            "email": "ravi@gmail.com",
            "full_name": "Ravi Kumar",
            "role": "Supervisor",
            "status": "APPROVED"
        }
    }
    """
    try:
        username = request.data.get('username')
        password = request.data.get('password')
        
        print(f"[LOGIN] Attempting login for username: {username}")
        
        if not username or not password:
            print("[LOGIN] Missing username or password")
            return Response({
                'error': 'Username and password are required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Get user from database
        user = fetch_one("""
            SELECT u.id, u.username, u.email, u.phone, u.password_hash, u.full_name, 
                   u.status, u.is_active, r.role_name
            FROM users u
            LEFT JOIN roles r ON u.role_id = r.id
            WHERE u.username = %s
        """, (username,))
        
        if not user:
            print(f"[LOGIN] User not found: {username}")
            return Response({
                'error': 'Invalid username or password'
            }, status=status.HTTP_401_UNAUTHORIZED)
        
        print(f"[LOGIN] User found: {username}, status: {user['status']}, active: {user['is_active']}")
        
        # Check password
        password_valid = check_password(password, user['password_hash'])
        print(f"[LOGIN] Password valid: {password_valid}")
        
        if not password_valid:
            print(f"[LOGIN] Invalid password for user: {username}")
            return Response({
                'error': 'Invalid username or password'
            }, status=status.HTTP_401_UNAUTHORIZED)
        
        # Check if user is active
        if not user['is_active']:
            return Response({
                'error': 'Account is deactivated'
            }, status=status.HTTP_403_FORBIDDEN)
        
        # Check approval status
        if user['status'] == 'PENDING':
            return Response({
                'error': 'Your account is pending admin approval',
                'status': 'PENDING'
            }, status=status.HTTP_403_FORBIDDEN)
        
        if user['status'] == 'REJECTED':
            return Response({
                'error': 'Your account has been rejected'
            }, status=status.HTTP_403_FORBIDDEN)
        
        # Update last login
        execute_query(
            "UPDATE users SET last_login = %s WHERE id = %s",
            (timezone.now(), user['id'])
        )
        
        # Generate JWT token
        role_name = user.get('role_name')
        if not role_name:
            print(f"[LOGIN] ⚠️ WARNING: User {username} has no role assigned. role_id={user.get('role_id')}")
            role_name = 'Supervisor'  # Default to Supervisor if no role found

        access_token = generate_access_token({
            'user_id': str(user['id']),
            'username': user['username'],
            'email': user['email'],
            'role': role_name
        })
        
        return Response({
            'access_token': access_token,
            'user': {
                'id': str(user['id']),
                'username': user['username'],
                'email': user['email'],
                'phone': user['phone'],
                'full_name': user['full_name'],
                'role': user['role_name'],
                'status': user['status']
            }
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({
            'error': f'Login failed: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@permission_classes([AllowAny])
def check_approval_status(request):
    """
    Check user approval status
    
    GET /api/auth/status/?username=ravi_kumar
    
    Response:
    {
        "status": "PENDING" | "APPROVED" | "REJECTED",
        "message": "..."
    }
    """
    try:
        username = request.query_params.get('username')
        
        if not username:
            return Response({
                'error': 'Username is required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        user = fetch_one(
            "SELECT status FROM users WHERE username = %s",
            (username,)
        )
        
        if not user:
            return Response({
                'error': 'User not found'
            }, status=status.HTTP_404_NOT_FOUND)
        
        messages = {
            'PENDING': 'Your account is pending admin approval',
            'APPROVED': 'Your account has been approved. You can now login.',
            'REJECTED': 'Your account has been rejected'
        }
        
        return Response({
            'status': user['status'],
            'message': messages.get(user['status'], 'Unknown status')
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({
            'error': f'Failed to check status: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
def get_roles(request):
    """
    Get all available roles
    
    GET /api/auth/roles/
    
    Response:
    {
        "roles": ["Supervisor", "Site Engineer", "Accountant", "Architect", "Owner"]
    }
    """
    try:
        roles = fetch_all("SELECT role_name FROM roles WHERE role_name != 'Admin' ORDER BY role_name")
        return Response({
            'roles': [r['role_name'] for r in roles]
        }, status=status.HTTP_200_OK)
    except Exception as e:
        return Response({
            'error': f'Failed to fetch roles: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ============================================
# ADMIN ENDPOINTS
# ============================================

@api_view(['GET'])
def get_pending_users(request):
    """
    Get all pending user approvals (Admin only)
    
    GET /api/admin/pending-users/
    
    Response:
    {
        "users": [
            {
                "id": "uuid",
                "username": "ravi_kumar",
                "email": "ravi@gmail.com",
                "phone": "9876543210",
                "full_name": "Ravi Kumar",
                "role": "Supervisor",
                "created_at": "2025-12-20T10:30:00Z"
            }
        ]
    }
    """
    try:
        # TODO: Add admin role check
        
        users = fetch_all("""
            SELECT u.id, u.username, u.email, u.phone, u.full_name, 
                   r.role_name, u.created_at
            FROM users u
            LEFT JOIN roles r ON u.role_id = r.id
            WHERE u.status = 'PENDING'
            ORDER BY u.created_at DESC
        """)
        
        return Response({
            'users': [
                {
                    'id': str(u['id']),
                    'username': u['username'],
                    'email': u['email'],
                    'phone': u['phone'],
                    'full_name': u['full_name'],
                    'role': u['role_name'],
                    'created_at': u['created_at'].isoformat() if u['created_at'] else None
                }
                for u in users
            ]
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({
            'error': f'Failed to fetch pending users: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
def get_all_users(request):
    """
    Get all users (Admin only)
    
    GET /api/admin/all-users/
    
    Response:
    {
        "users": [...]
    }
    """
    try:
        # TODO: Add admin role check
        
        users = fetch_all("""
            SELECT u.id, u.username, u.email, u.phone, u.full_name, 
                   r.role_name, u.status, u.is_active, u.created_at, u.last_login
            FROM users u
            LEFT JOIN roles r ON u.role_id = r.id
            ORDER BY u.created_at DESC
        """)
        
        return Response({
            'users': [
                {
                    'id': str(u['id']),
                    'username': u['username'],
                    'email': u['email'],
                    'phone': u['phone'],
                    'full_name': u['full_name'],
                    'role': u['role_name'],
                    'status': u['status'],
                    'is_active': u['is_active'],
                    'created_at': u['created_at'].isoformat() if u['created_at'] else None,
                    'last_login': u['last_login'].isoformat() if u['last_login'] else None
                }
                for u in users
            ]
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({
            'error': f'Failed to fetch users: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
def approve_user(request, user_id):
    """
    Approve a pending user (Admin only)
    
    POST /api/admin/approve-user/<user_id>/
    
    Response:
    {
        "message": "User approved successfully"
    }
    """
    try:
        # TODO: Add admin role check
        # admin_id = request.user['user_id']
        
        execute_query("""
            UPDATE users 
            SET status = 'APPROVED', approved_at = %s
            WHERE id = %s AND status = 'PENDING'
        """, (timezone.now(), user_id))
        
        return Response({
            'message': 'User approved successfully'
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({
            'error': f'Failed to approve user: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
def reject_user(request, user_id):
    """
    Reject a pending user (Admin only)
    
    POST /api/admin/reject-user/<user_id>/
    
    Response:
    {
        "message": "User rejected successfully"
    }
    """
    try:
        # TODO: Add admin role check
        
        execute_query("""
            UPDATE users 
            SET status = 'REJECTED'
            WHERE id = %s AND status = 'PENDING'
        """, (user_id,))
        
        return Response({
            'message': 'User rejected successfully'
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response({
            'error': f'Failed to reject user: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
def admin_create_user(request):
    """
    Admin creates a user directly with APPROVED status.
    POST /api/admin/create-user/
    Body: { username, email, phone, full_name, password, role, site_ids (optional for Client role) }
    """
    try:
        username  = request.data.get('username', '').strip()
        email     = request.data.get('email', '').strip()
        phone     = request.data.get('phone', '').strip()
        full_name = request.data.get('full_name', '').strip()
        password  = request.data.get('password', '').strip()
        role_name = request.data.get('role', '').strip()
        site_ids  = request.data.get('site_ids', [])  # For Client role

        if not all([username, email, phone, password, role_name]):
            return Response({'error': 'username, email, phone, password and role are required'},
                            status=status.HTTP_400_BAD_REQUEST)

        existing = fetch_one(
            "SELECT id FROM users WHERE username = %s OR email = %s",
            (username, email)
        )
        if existing:
            return Response({'error': 'Username or email already exists'},
                            status=status.HTTP_400_BAD_REQUEST)

        role = fetch_one("SELECT id FROM roles WHERE role_name = %s", (role_name,))
        if not role:
            return Response({'error': f'Role "{role_name}" not found'},
                            status=status.HTTP_400_BAD_REQUEST)

        # Validate site_ids for Client role
        if role_name.lower() == 'client' and not site_ids:
            return Response({'error': 'Client role requires at least one site assignment'},
                            status=status.HTTP_400_BAD_REQUEST)

        user_id = str(uuid.uuid4())
        password_hash = make_password(password)

        execute_query("""
            INSERT INTO users (id, username, email, phone, password_hash, full_name, role_id, status, is_active)
            VALUES (%s, %s, %s, %s, %s, %s, %s, 'APPROVED', true)
        """, (user_id, username, email, phone, password_hash, full_name, role['id']))

        # Assign sites to client
        if role_name.lower() == 'client' and site_ids:
            admin_id = request.user.get('user_id')
            for site_id in site_ids:
                # Create client_sites table entry if not exists
                execute_query("""
                    INSERT INTO client_sites (id, client_id, site_id, assigned_by)
                    VALUES (%s, %s, %s, %s)
                    ON CONFLICT (client_id, site_id) DO NOTHING
                """, (str(uuid.uuid4()), user_id, site_id, admin_id))

        return Response({
            'message': f'User "{username}" created successfully' + 
                      (f' with {len(site_ids)} site(s) assigned' if site_ids else ''),
            'user_id': user_id
        }, status=status.HTTP_201_CREATED)

    except Exception as e:
        return Response({'error': f'Failed to create user: {str(e)}'},
                        status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
def admin_create_admin(request):
    """
    Admin creates another admin account.
    POST /api/admin/create-admin/
    Body: { username, email, phone, full_name, password }
    """
    try:
        username  = request.data.get('username', '').strip()
        email     = request.data.get('email', '').strip()
        phone     = request.data.get('phone', '').strip()
        full_name = request.data.get('full_name', '').strip()
        password  = request.data.get('password', '').strip()

        if not all([username, email, phone, password]):
            return Response({'error': 'username, email, phone and password are required'},
                            status=status.HTTP_400_BAD_REQUEST)

        existing = fetch_one(
            "SELECT id FROM users WHERE username = %s OR email = %s",
            (username, email)
        )
        if existing:
            return Response({'error': 'Username or email already exists'},
                            status=status.HTTP_400_BAD_REQUEST)

        role = fetch_one("SELECT id FROM roles WHERE role_name = 'Admin'")
        if not role:
            return Response({'error': 'Admin role not found in database'},
                            status=status.HTTP_500_INTERNAL_SERVER_ERROR)

        user_id = str(uuid.uuid4())
        password_hash = make_password(password)

        execute_query("""
            INSERT INTO users (id, username, email, phone, password_hash, full_name, role_id, status, is_active)
            VALUES (%s, %s, %s, %s, %s, %s, %s, 'APPROVED', true)
        """, (user_id, username, email, phone, password_hash, full_name, role['id']))

        return Response({
            'message': f'Admin "{username}" created successfully',
            'user_id': user_id
        }, status=status.HTTP_201_CREATED)

    except Exception as e:
        return Response({'error': f'Failed to create admin: {str(e)}'},
                        status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
def admin_create_role(request):
    """
    Admin creates a new role.
    POST /api/admin/create-role/
    Body: { role_name }
    """
    try:
        role_name = request.data.get('role_name', '').strip()

        if not role_name:
            return Response({'error': 'role_name is required'},
                            status=status.HTTP_400_BAD_REQUEST)

        existing = fetch_one("SELECT id FROM roles WHERE role_name = %s", (role_name,))
        if existing:
            return Response({'error': f'Role "{role_name}" already exists'},
                            status=status.HTTP_400_BAD_REQUEST)

        execute_query(
            "INSERT INTO roles (role_name) VALUES (%s)",
            (role_name,)
        )

        return Response({'message': f'Role "{role_name}" created successfully'},
                        status=status.HTTP_201_CREATED)

    except Exception as e:
        return Response({'error': f'Failed to create role: {str(e)}'},
                        status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
def get_all_roles(request):
    """
    Get all roles including Admin.
    GET /api/admin/roles/
    """
    try:
        roles = fetch_all("SELECT id, role_name FROM roles ORDER BY role_name")
        return Response({
            'roles': [{'id': r['id'], 'role_name': r['role_name']} for r in roles]
        }, status=status.HTTP_200_OK)
    except Exception as e:
        return Response({'error': f'Failed to fetch roles: {str(e)}'},
                        status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_client_sites(request):
    """
    Get sites assigned to the logged-in client.
    GET /api/client/sites/
    """
    try:
        user_id = request.user['user_id']
        user_role = request.user.get('role', '')
        
        # Only clients can access this endpoint
        if user_role.lower() != 'client':
            return Response({
                'error': 'This endpoint is only for clients'
            }, status=status.HTTP_403_FORBIDDEN)
        
        # Get assigned sites
        sites = fetch_all("""
            SELECT 
                cs.id as assignment_id,
                cs.site_id,
                cs.assigned_date,
                s.site_name,
                s.customer_name,
                s.area,
                s.street,
                s.status
            FROM client_sites cs
            JOIN sites s ON cs.site_id = s.id
            WHERE cs.client_id = %s AND cs.is_active = TRUE
            ORDER BY cs.assigned_date DESC
        """, (user_id,))
        
        # Format sites
        formatted_sites = []
        for site in sites:
            site_name = site.get('site_name') or ''
            customer_name = site.get('customer_name') or ''
            
            if customer_name and site_name:
                display_name = f"{customer_name} {site_name}"
            elif customer_name:
                display_name = customer_name
            elif site_name:
                display_name = site_name
            else:
                display_name = f"Site {str(site['site_id'])[:8]}"
            
            formatted_sites.append({
                'assignment_id': str(site['assignment_id']),
                'id': str(site['site_id']),
                'site_name': site_name,
                'customer_name': customer_name,
                'area': site.get('area') or '',
                'street': site.get('street') or '',
                'status': site.get('status') or 'ACTIVE',
                'assigned_date': site['assigned_date'].strftime('%Y-%m-%d') if site.get('assigned_date') else None,
                'display_name': display_name,
            })
        
        return Response({
            'success': True,
            'sites': formatted_sites,
            'count': len(formatted_sites),
        })
        
    except Exception as e:
        print(f"Error fetching client sites: {e}")
        return Response({
            'error': f'Error fetching sites: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
