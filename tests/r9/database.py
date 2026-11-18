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


def concurrent_quiz_requests():
    def benchmark(script, clients, transactions, *options):
        return subprocess.Popen([
            'docker', 'exec', name, 'pgbench', '-n', '-h', '127.0.0.1', '-U', 'postgres',
            '-c', str(clients), '-j', str(min(clients, 8)), '-t', str(transactions),
            *options, '-f', '/repo/tests/r9/' + script, 'postgres',
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    with benchmark('quiz-manager-observer.sql', 1, 100, '--rate=50') as observer:
        with benchmark('quiz-manager-pressure.sql', 100, 1) as pressure:
            for process, expected in ((pressure, 100), (observer, 100)):
                output, _ = process.communicate()
                if process.returncode or f'number of transactions actually processed: {expected}/{expected}' not in output:
                    raise RuntimeError('Disposable concurrency check did not complete all requests')
    print('PASS: 100 concurrent same-address requests and 100 unrelated valid requests completed')


try:
    docker('run', '--detach', '--rm', '--name', name, '--network', 'none',
           '--mount', f'type=bind,source={ROOT},target=/repo,readonly',
           '--tmpfs', '/var/lib/postgresql/data', '-e', 'POSTGRES_HOST_AUTH_METHOD=trust',
           IMAGE, '-c', 'max_connections=120', stdout=subprocess.DEVNULL)
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
                 ROOT / 'tests/r9/quiz.sql', ROOT / 'tests/r9/quiz-manager.sql', ROOT / 'tests/r10/access-id.sql']:
        print('Checking ' + str(file.relative_to(ROOT)), flush=True)
        sql(file)
    concurrent_quiz_requests()
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
