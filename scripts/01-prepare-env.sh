#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.." 2>/dev/null || true
# Prefer the application repo as working directory; this file belongs in repo/scripts/
if [[ ! -f database/init.sh || ! -d k8s ]]; then echo 'ERROR: run from repository root: bash scripts/01-prepare-env.sh' >&2; exit 1; fi
umask 077
python3 - <<'PY'
from pathlib import Path
from urllib.parse import quote
import secrets,base64,re
p=Path('.env.k8s')
items={}
if p.exists():
 for raw in p.read_text().splitlines():
  if not raw or raw.lstrip().startswith('#'): continue
  if '=' not in raw: raise SystemExit('Malformed .env.k8s line')
  k,v=raw.split('=',1);items[k]=v
else:
 keys=['MYSQL_ROOT_PASSWORD','JWT_SECRET','DEMO_ADMIN_PASSWORD','DEMO_STUDENT_PASSWORD','AUTH_DB_PASSWORD','STUDENT_DB_PASSWORD','ATTENDANCE_DB_PASSWORD','MARKS_DB_PASSWORD']
 for k in keys: items[k]=secrets.token_hex(32) if k not in ('DEMO_ADMIN_PASSWORD','DEMO_STUDENT_PASSWORD') else secrets.token_urlsafe(24)
 items['PASSWORD_ENCRYPTION_KEY']=base64.urlsafe_b64encode(secrets.token_bytes(32)).decode()
required=['MYSQL_ROOT_PASSWORD','JWT_SECRET','DEMO_ADMIN_PASSWORD','DEMO_STUDENT_PASSWORD','AUTH_DB_PASSWORD','STUDENT_DB_PASSWORD','ATTENDANCE_DB_PASSWORD','MARKS_DB_PASSWORD','PASSWORD_ENCRYPTION_KEY']
missing=[k for k in required if not items.get(k)]
if missing: raise SystemExit('Missing required existing secrets: '+', '.join(missing)+'. Not changing passwords.')
for name,user,password,database in [('AUTH','auth_user','AUTH_DB_PASSWORD','auth_db'),('STUDENTS','student_user','STUDENT_DB_PASSWORD','student_db'),('ATTENDANCE','attendance_user','ATTENDANCE_DB_PASSWORD','attendance_db'),('MARKS','marks_user','MARKS_DB_PASSWORD','marks_db')]:
 items[name+'_DATABASE_URL']=f'mysql+pymysql://{user}:{quote(items[password],safe="")}@database:3306/{database}'
init=Path('database/init.sh').read_text()
for name in ('auth_db','student_db','attendance_db','marks_db','auth_user','student_user','attendance_user','marks_user'):
 if name not in init: raise SystemExit(f'WARNING: {name} not found in database/init.sh; verify database grants before proceeding. No credentials were written.')
p.write_text(''.join(f'{k}={v}\n' for k,v in items.items()));p.chmod(0o600)
print('Prepared .env.k8s with 13 required variables. Values hidden. Existing passwords preserved.')
PY
if [[ -d .git ]]; then printf '\n.env.k8s\n' >> .git/info/exclude; fi
