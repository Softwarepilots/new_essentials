"""
Guest catalogue — items the admin publishes for guests, like a WhatsApp
Business catalogue. Each item has up to 10 photos; the first is the cover.

    GET    /api/catalogue/                  public: active items (guest app)
    GET    /api/admin/catalogue/            admin: all items
    POST   /api/admin/catalogue/            admin: create (multipart, 'images' files)
    PUT    /api/admin/catalogue/<id>/       admin: update (multipart, see below)
    DELETE /api/admin/catalogue/<id>/       admin: delete

Updating photos: send 'keep_images' (JSON list of the item's current image
URLs to keep, in display order) plus any new 'images' files, which are added
after the kept ones. Without 'keep_images' the current photos are kept.

Tables: catalogue_items (migrations/guest_catalogue.sql,
migrations/guest_catalogue_images.sql)
"""
import json
import os
import uuid
from decimal import Decimal, InvalidOperation
from urllib.parse import urlparse

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.views.decorators.csrf import csrf_exempt
from psycopg.types.json import Jsonb
from rest_framework import status
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from .authentication import JWTAuthentication
from .database import get_db_connection

_COLUMNS = ('id, name, description, price, image_urls, is_active, sort_order, '
            'created_at, updated_at')
_ALLOWED_IMAGE_EXTS = {'.jpg', '.jpeg', '.png', '.webp', '.gif'}
_MAX_IMAGE_BYTES = 5 * 1024 * 1024
MAX_IMAGES = 10


class _BadRequest(Exception):
    pass


def _is_admin(cursor, user_id) -> bool:
    cursor.execute("SELECT role_id FROM users WHERE id = %s", (user_id,))
    row = cursor.fetchone()
    return bool(row and row[0] == 1)


def _serialize(request, row) -> dict:
    item = dict(zip([c.strip() for c in _COLUMNS.split(',')], row))
    # Absolute so both apps can load them without knowing the media host
    images = [request.build_absolute_uri(u) for u in (item['image_urls'] or [])]
    return {
        'id': str(item['id']),
        'name': item['name'],
        'description': item['description'] or '',
        'price': float(item['price']) if item['price'] is not None else None,
        'images': images,
        'image_url': images[0] if images else None,  # cover
        'is_active': item['is_active'],
        'sort_order': item['sort_order'],
        'created_at': item['created_at'].isoformat() if item['created_at'] else None,
        'updated_at': item['updated_at'].isoformat() if item['updated_at'] else None,
    }


def _parse_fields(data, partial=False) -> dict:
    """Validate form fields; raises _BadRequest."""
    fields = {}

    if 'name' in data or not partial:
        name = (data.get('name') or '').strip()
        if not name:
            raise _BadRequest('name is required')
        fields['name'] = name[:200]

    if 'description' in data:
        fields['description'] = (data.get('description') or '').strip() or None

    if 'price' in data:
        raw = (data.get('price') or '').strip().replace(',', '')
        if raw:
            try:
                price = Decimal(raw)
            except InvalidOperation:
                raise _BadRequest('price must be a number')
            if price < 0:
                raise _BadRequest('price cannot be negative')
            fields['price'] = price
        else:
            fields['price'] = None

    if 'is_active' in data:
        fields['is_active'] = str(data.get('is_active')).lower() in ('1', 'true', 'yes', 'on')

    if 'sort_order' in data:
        try:
            fields['sort_order'] = int(data.get('sort_order') or 0)
        except ValueError:
            raise _BadRequest('sort_order must be a whole number')

    return fields


def _validate_uploads(uploads):
    for upload in uploads:
        ext = os.path.splitext(upload.name)[1].lower()
        if ext not in _ALLOWED_IMAGE_EXTS:
            raise _BadRequest(f'{upload.name}: images must be JPG, PNG, WEBP or GIF')
        if upload.size > _MAX_IMAGE_BYTES:
            raise _BadRequest(f'{upload.name}: each image must be 5 MB or smaller')


def _save_images(uploads) -> list:
    """Store uploaded images; returns their relative /media/... URLs."""
    urls = []
    for upload in uploads:
        ext = os.path.splitext(upload.name)[1].lower()
        path = default_storage.save(f'catalogue/{uuid.uuid4()}{ext}', ContentFile(upload.read()))
        urls.append(f'/media/{path}')
    return urls


def _delete_images(image_urls):
    for image_url in image_urls:
        if image_url and image_url.startswith('/media/'):
            try:
                default_storage.delete(image_url[len('/media/'):])
            except Exception as e:
                print(f'[CATALOGUE] could not delete image {image_url}: {e}')


def _kept_images(data, current) -> list:
    """Current images the client wants to keep, in the client's order."""
    raw = data.get('keep_images')
    if raw is None:
        return list(current)
    try:
        wanted = json.loads(raw) if isinstance(raw, str) else list(raw)
    except (ValueError, TypeError):
        raise _BadRequest('keep_images must be a JSON list')
    kept = []
    for url in wanted:
        # Clients send back the absolute URLs they were given
        path = urlparse(str(url)).path
        if path in current and path not in kept:
            kept.append(path)
    return kept


# ---------------------------------------------------------------------------
# Public — guest app
# ---------------------------------------------------------------------------

@csrf_exempt
@api_view(['GET'])
@authentication_classes([])
@permission_classes([AllowAny])
def list_catalogue(request):
    """Active catalogue items for the guest app. No authentication."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(f"""
            SELECT {_COLUMNS} FROM catalogue_items
            WHERE is_active = TRUE
            ORDER BY sort_order, created_at DESC
        """)
        rows = cursor.fetchall()
        cursor.close()
        conn.close()
        return Response({'success': True, 'items': [_serialize(request, r) for r in rows]})
    except Exception as e:
        print(f'Error listing catalogue: {e}')
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ---------------------------------------------------------------------------
# Admin — staff app
# ---------------------------------------------------------------------------

@csrf_exempt
@api_view(['GET', 'POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def admin_catalogue(request):
    """GET: all items (incl. hidden). POST: create an item."""
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        if not _is_admin(cursor, request.user.get('user_id')):
            return Response({'error': 'Unauthorized. Admin access required.'},
                            status=status.HTTP_403_FORBIDDEN)

        if request.method == 'GET':
            cursor.execute(f"""
                SELECT {_COLUMNS} FROM catalogue_items
                ORDER BY sort_order, created_at DESC
            """)
            items = [_serialize(request, r) for r in cursor.fetchall()]
            return Response({'success': True, 'items': items})

        fields = _parse_fields(request.data)
        uploads = request.FILES.getlist('images')
        if len(uploads) > MAX_IMAGES:
            raise _BadRequest(f'An item can have at most {MAX_IMAGES} photos')
        _validate_uploads(uploads)
        image_urls = _save_images(uploads)
        fields['image_urls'] = Jsonb(image_urls)
        fields['image_url'] = image_urls[0] if image_urls else None

        columns = ', '.join(fields)
        placeholders = ', '.join(['%s'] * len(fields))
        try:
            cursor.execute(
                f'INSERT INTO catalogue_items ({columns}) VALUES ({placeholders}) '
                f'RETURNING {_COLUMNS}',
                list(fields.values()),
            )
            row = cursor.fetchone()
            conn.commit()
        except Exception:
            _delete_images(image_urls)
            raise
        return Response({'success': True, 'item': _serialize(request, row)},
                        status=status.HTTP_201_CREATED)

    except _BadRequest as e:
        return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)
    except Exception as e:
        print(f'Error in admin_catalogue: {e}')
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
    finally:
        if conn:
            conn.close()


@csrf_exempt
@api_view(['PUT', 'PATCH', 'DELETE'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def admin_catalogue_item(request, item_id):
    """PUT/PATCH: update an item (any subset of fields and photos). DELETE: remove it."""
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        if not _is_admin(cursor, request.user.get('user_id')):
            return Response({'error': 'Unauthorized. Admin access required.'},
                            status=status.HTTP_403_FORBIDDEN)

        cursor.execute('SELECT image_urls FROM catalogue_items WHERE id = %s', (str(item_id),))
        existing = cursor.fetchone()
        if not existing:
            return Response({'error': 'Item not found'}, status=status.HTTP_404_NOT_FOUND)
        current = list(existing[0] or [])

        if request.method == 'DELETE':
            cursor.execute('DELETE FROM catalogue_items WHERE id = %s', (str(item_id),))
            conn.commit()
            _delete_images(current)
            return Response({'success': True})

        fields = _parse_fields(request.data, partial=True)

        uploads = request.FILES.getlist('images')
        photos_changed = 'keep_images' in request.data or bool(uploads)
        new_urls = []
        if photos_changed:
            kept = _kept_images(request.data, current)
            if len(kept) + len(uploads) > MAX_IMAGES:
                raise _BadRequest(f'An item can have at most {MAX_IMAGES} photos')
            _validate_uploads(uploads)
            new_urls = _save_images(uploads)
            image_urls = kept + new_urls
            fields['image_urls'] = Jsonb(image_urls)
            fields['image_url'] = image_urls[0] if image_urls else None

        if not fields:
            raise _BadRequest('Nothing to update')

        assignments = ', '.join(f'{col} = %s' for col in fields)
        try:
            cursor.execute(
                f'UPDATE catalogue_items SET {assignments}, updated_at = NOW() '
                f'WHERE id = %s RETURNING {_COLUMNS}',
                list(fields.values()) + [str(item_id)],
            )
            row = cursor.fetchone()
            conn.commit()
        except Exception:
            _delete_images(new_urls)
            raise
        if photos_changed:
            _delete_images([u for u in current if u not in image_urls])
        return Response({'success': True, 'item': _serialize(request, row)})

    except _BadRequest as e:
        return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)
    except Exception as e:
        print(f'Error in admin_catalogue_item: {e}')
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
    finally:
        if conn:
            conn.close()
