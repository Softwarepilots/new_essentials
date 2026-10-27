#!/usr/bin/env python3
"""
Point both Flutter apps (otp_phone_auth + guest_app) at a backend:

    python switch_backend.py local            # http://localhost:8001 (Chrome on this PC)
    python switch_backend.py lan 192.168.1.6  # this PC's Wi-Fi IP:8001 (phones on the same Wi-Fi)
    python switch_backend.py server           # http://187.127.164.22:8000 (live server)

Only the backend host is rewritten, so uncommitted edits in the same files
are left alone. Every mode first converts back to the server form, so any
mode can be switched to from any other.
"""
import ipaddress
import pathlib
import re
import sys

SERVER_API = 'http://187.127.164.22:8000'
SERVER_MEDIA = 'http://187.127.164.22'
# Media/file URLs on the server have no port (served on :80), while the local
# Django dev server serves everything on one port. They get a different local
# host spelling so switching back to the server stays unambiguous.
# Port 8001, not 8000: another local project on this PC already uses 8000.
LOCAL_PORT = 8001
LOCAL_API = f'http://localhost:{LOCAL_PORT}'
LOCAL_MEDIA = f'http://127.0.0.1:{LOCAL_PORT}'
ROOTS = ['otp_phone_auth/lib', 'guest_app/lib']

# In LAN mode API and media share one host, so a LAN URL is told apart by
# what follows it: media URLs are followed by a '$' interpolation or live on
# the mediaBaseUrl line; API URLs are followed by '/api' or are a bare base.
_LAN_URL = re.compile(
    r'http://(?!127\.0\.0\.1)\d{1,3}(?:\.\d{1,3}){3}:' + str(LOCAL_PORT) + r'(?=(.?))'
)


def _lan_line_to_server(line: str) -> str:
    def repl(m):
        is_media = m.group(1) == '$' or 'mediaBaseUrl' in line
        return SERVER_MEDIA if is_media else SERVER_API
    return _LAN_URL.sub(repl, line)


def to_server(text: str) -> str:
    text = text.replace(LOCAL_API, SERVER_API).replace(LOCAL_MEDIA, SERVER_MEDIA)
    return ''.join(_lan_line_to_server(l) for l in text.splitlines(keepends=True))


def from_server(text: str, api_host: str, media_host: str) -> str:
    text = text.replace(SERVER_API, api_host)
    return re.sub(re.escape(SERVER_MEDIA) + r'(?!:)', media_host, text)


def main():
    args = sys.argv[1:]
    if not args or args[0] not in ('local', 'lan', 'server') or \
            (args[0] == 'lan') != (len(args) == 2) or len(args) > 2:
        sys.exit(__doc__)
    mode = args[0]
    if mode == 'lan':
        try:
            ip = ipaddress.IPv4Address(args[1])
        except ValueError:
            sys.exit(f'Not an IPv4 address: {args[1]}')
        if ip.is_loopback:
            sys.exit('Use "local" for this PC; "lan" needs the Wi-Fi IP phones can reach.')
        hosts = (f'http://{ip}:{LOCAL_PORT}',) * 2
    elif mode == 'local':
        hosts = (LOCAL_API, LOCAL_MEDIA)
    else:
        hosts = None

    base = pathlib.Path(__file__).parent
    changed = 0
    for root in ROOTS:
        for path in (base / root).rglob('*.dart'):
            # newline='' on read and write keeps CRLF/LF exactly as checked out
            with open(path, encoding='utf-8', newline='') as f:
                text = f.read()
            new = to_server(text)
            if hosts:
                new = from_server(new, *hosts)
            if new != text:
                with open(path, 'w', encoding='utf-8', newline='') as f:
                    f.write(new)
                changed += 1
                print(f'  updated {path.relative_to(base)}')
    target = f'{mode} ({args[1]})' if mode == 'lan' else mode
    print(f'{changed} file(s) now point at the {target} backend.')


if __name__ == '__main__':
    main()
