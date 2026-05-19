import psycopg
from django.conf import settings

def get_db_connection():
    """Get database connection to Supabase PostgreSQL with UTF-8 encoding"""
    conn = psycopg.connect(
        host=settings.DATABASES['default']['HOST'],
        port=settings.DATABASES['default']['PORT'],
        dbname=settings.DATABASES['default']['NAME'],
        user=settings.DATABASES['default']['USER'],
        password=settings.DATABASES['default']['PASSWORD'],
        sslmode='require',
        client_encoding='UTF8'
    )
    # Set connection encoding to UTF-8
    conn.execute("SET CLIENT_ENCODING TO 'UTF8'")
    return conn

def get_user_by_uid(user_uid):
    """
    Get user from database by Firebase UID
    
    Args:
        user_uid (str): Firebase UID
        
    Returns:
        dict: User data or None if not found
    """
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT user_id, user_uid, full_name, email, phone, role_id, role_locked, is_active
                    FROM users
                    WHERE user_uid = %s
                """, (user_uid,))
                
                row = cur.fetchone()
                if row:
                    return {
                        'user_id': row[0],
                        'user_uid': row[1],
                        'full_name': row[2],
                        'email': row[3],
                        'phone': row[4],
                        'role_id': row[5],
                        'role_locked': row[6],
                        'is_active': row[7]
                    }
                return None
    except Exception as e:
        print(f"[DB ERROR] {str(e)}")
        return None

def create_user(user_uid, email, full_name):
    """
    Create new user in database
    
    Args:
        user_uid (str): Firebase UID
        email (str): User email
        full_name (str): User full name
        
    Returns:
        dict: Created user data or None if failed
    """
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO users (user_uid, email, full_name, phone, role_id, role_locked, is_active)
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                    RETURNING user_id, user_uid, full_name, email, phone, role_id, role_locked, is_active
                """, (user_uid, email, full_name, '', 2, False, True))  # role_id=2 is Supervisor
                
                conn.commit()
                row = cur.fetchone()
                
                if row:
                    return {
                        'user_id': row[0],
                        'user_uid': row[1],
                        'full_name': row[2],
                        'email': row[3],
                        'phone': row[4],
                        'role_id': row[5],
                        'role_locked': row[6],
                        'is_active': row[7]
                    }
                return None
    except Exception as e:
        print(f"[DB ERROR] creating user: {str(e)}")
        return None

def update_user_profile(user_uid, full_name=None, phone=None):
    """
    Update user profile
    
    Args:
        user_uid (str): Firebase UID
        full_name (str, optional): New full name
        phone (str, optional): New phone number
        
    Returns:
        bool: True if successful, False otherwise
    """
    try:
        updates = []
        params = []
        
        if full_name is not None:
            updates.append("full_name = %s")
            params.append(full_name)
        
        if phone is not None:
            updates.append("phone = %s")
            params.append(phone)
        
        if not updates:
            return True
        
        params.append(user_uid)
        
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                query = f"UPDATE users SET {', '.join(updates)} WHERE user_uid = %s"
                cur.execute(query, params)
                conn.commit()
                return cur.rowcount > 0
    except Exception as e:
        print(f"[DB ERROR] updating user: {str(e)}")
        return False

def update_user_profile_by_email(email, full_name=None, phone=None):
    """Update user profile using email as identifier (fallback for old JWT tokens)."""
    try:
        updates = []
        params = []
        if full_name is not None:
            updates.append("full_name = %s")
            params.append(full_name)
        if phone is not None:
            updates.append("phone = %s")
            params.append(phone)
        if not updates:
            return True
        params.append(email)
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                query = f"UPDATE users SET {', '.join(updates)} WHERE email = %s"
                cur.execute(query, params)
                conn.commit()
                return cur.rowcount > 0
    except Exception as e:
        print(f"[DB ERROR] updating user by email: {str(e)}")
        return False


def get_role_name(role_id):
    """Get role name from role_id"""
    role_map = {
        1: 'Admin',
        2: 'Supervisor',
        3: 'Site Engineer',
        4: 'Junior Accountant'
    }
    return role_map.get(role_id, 'Unknown')


# Generic database helper functions for new auth system
def execute_query(query, params=None):
    """Execute a query that doesn't return results (INSERT, UPDATE, DELETE)"""
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, params or ())
                rowcount = cur.rowcount
                print(f"[DB QUERY] Executed query, affected rows: {rowcount}")
                conn.commit()
                print(f"[DB QUERY] Transaction committed successfully")
                return rowcount > 0 if rowcount >= 0 else True
    except Exception as e:
        print(f"[DB ERROR] {str(e)}")
        import traceback
        traceback.print_exc()
        return False

def fetch_one(query, params=None):
    """Fetch one row from database"""
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, params or ())
                row = cur.fetchone()
                if row:
                    # Get column names
                    columns = [desc[0] for desc in cur.description]
                    # Return as dictionary
                    return dict(zip(columns, row))
                return None
    except Exception as e:
        print(f"[DB ERROR] {str(e)}")
        return None

def fetch_all(query, params=None):
    """Fetch all rows from database"""
    try:
        print(f"[DB FETCH] Executing query with params: {params}", flush=True)
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, params or ())
                rows = cur.fetchall()
                print(f"[DB FETCH] Fetched {len(rows) if rows else 0} rows", flush=True)
                if rows:
                    # Get column names
                    columns = [desc[0] for desc in cur.description]
                    result = [dict(zip(columns, row)) for row in rows]
                    print(f"[DB FETCH] Returning {len(result)} rows as dicts", flush=True)
                    return result
                print(f"[DB FETCH] No rows found, returning empty list", flush=True)
                return []
    except Exception as e:
        print(f"[DB ERROR] {str(e)}", flush=True)
        import traceback
        traceback.print_exc()
        return []
