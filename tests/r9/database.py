"""Create a disposable, unexposed PostgreSQL container; never accepts a remote URL."""
from pathlib import Path
import subprocess
import time
import uuid
import re

ROOT = Path(__file__).resolve().parents[2]
IMAGE = 'postgres:17.6@sha256:00bc86618629af00d2937fdc5a5d63db3ff8450acf52f0636ec813c7f4902929'
name = 'history-r9-' + uuid.uuid4().hex[:12]


def docker(*args, **kwargs):
    return subprocess.run(['docker', *args], check=True, **kwargs)


def sql(file):
    # psql include paths resolve inside the read-only repository mount.
    result = docker('exec', name, 'psql', '-X', '-h', '127.0.0.1', '-U', 'postgres', '-d', 'postgres',
                    '-v', 'ON_ERROR_STOP=1', '-f', '/repo/' + str(file.relative_to(ROOT)),
                    capture_output=True, text=True)
    for line in result.stderr.splitlines():
        if 'NOTICE:  PASS:' in line:
            print(line.split('NOTICE:  ', 1)[1])


try:
    docker('run', '--detach', '--rm', '--name', name, '--network', 'none',
           '--mount', f'type=bind,source={ROOT},target=/repo,readonly',
           '--tmpfs', '/var/lib/postgresql/data', '-e', 'POSTGRES_HOST_AUTH_METHOD=trust',
           IMAGE, stdout=subprocess.DEVNULL)
    for _ in range(60):
        ready = subprocess.run(['docker', 'exec', name, 'pg_isready', '-h', '127.0.0.1', '-U', 'postgres'],
                               capture_output=True).returncode == 0
        if ready:
            break
        time.sleep(1)
    else:
        raise RuntimeError('Disposable database did not become ready')
    for file in [ROOT / 'tests/r9/bootstrap.sql',
                 *sorted((ROOT / 'supabase/migrations').glob('*.sql')),
                 ROOT / 'supabase/seed.sql', ROOT / 'tests/r9/access.sql',
                 ROOT / 'tests/r9/quiz.sql', ROOT / 'tests/r10/access-id.sql']:
        print('Checking ' + str(file.relative_to(ROOT)), flush=True)
        sql(file)
    print('PASS: migration rebuild, access and quiz integrity suites')
except subprocess.CalledProcessError as error:
    # Emit the error category only; never SQL context or credential values.
    for line in (error.stderr or '').splitlines():
        if 'ERROR:' in line:
            message = line.split('ERROR:', 1)[1]
            message = re.sub(r"[0-9a-fA-F-]{32,}|[A-HJ-NP-Z2-9]{12}", '[redacted]', message)
            print('Database diagnostic:' + message)
    print('FAIL: database command; details suppressed (exit ' + str(error.returncode) + ')')
    raise SystemExit(1) from None
finally:
    subprocess.run(['docker', 'rm', '--force', name], capture_output=True)
