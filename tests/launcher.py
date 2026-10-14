"""Fake Claude integration through the real Fish/Lua launcher, including PTYs."""
import json
import os
from pathlib import Path
import pty
import shlex
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
ROLES = ['text.primary', 'text.secondary', 'text.accent', 'accent.primary',
         'accent.secondary', 'border.subtle', 'status.success', 'status.warning',
         'status.error', 'status.info']

with tempfile.TemporaryDirectory(prefix="claude launcher 'quoted' ") as directory:
    temp = Path(directory).resolve()
    plugin = temp / "hue root/packages/claude-code-plugin"
    for child in ('.claude-plugin', 'themes', 'statusline'):
        (plugin / child).mkdir(parents=True)
    (plugin / '.claude-plugin/plugin.json').write_text('{"name":"hue-theme"}')
    config = {'segments': ['model', 'directory', 'branch', 'context'],
              'palette': {role: '#123456' for role in ROLES}}
    for mood in ('mua', 'huong', 'cung'):
        (plugin / f'themes/hue-{mood}.json').write_text('{}')
        (plugin / f'statusline/hue-{mood}.json').write_text(json.dumps(config))
    record = temp / 'record.json'
    cli = temp / 'claude'
    cli.write_text(
        '#!/usr/bin/env python3\n'
        'import os,json,signal,sys\n'
        'with open(os.environ["RECORD"],"w") as f:\n'
        ' json.dump({"argv":sys.argv[1:],"pid":os.getpid(),'
        '"tty":[os.isatty(fd) for fd in (0,1,2)]},f)\n'
        'if os.environ.get("WAIT_FOR_SIGNAL"):\n'
        ' while True: signal.pause()\n'
        'sys.exit(37)\n')
    cli.chmod(0o755)
    launcher = temp / 'symlink launcher'
    launcher.symlink_to(ROOT / 'bin/claude-statusline')
    env = dict(os.environ, PATH=f'{temp}:{os.environ["PATH"]}', RECORD=str(record),
               HUE_THEME_ROOT=str(temp / 'hue root'))

    def verify(arguments, mood='mua', remaining=None):
        child = subprocess.run([str(launcher), *arguments], cwd=temp, env=env,
                               capture_output=True, timeout=10)
        assert child.returncode == 37, child.stderr
        data = json.loads(record.read_text())
        args = data['argv']
        assert args[:3] == ['--plugin-dir', str(plugin), '--settings']
        settings = json.loads(args[3])
        assert settings['theme'] == f'custom:hue-theme:hue-{mood}'
        assert args[4:] == (arguments if remaining is None else remaining)
        command = shlex.split(settings['statusLine']['command'])
        assert command == ['nvim', '-l', str(ROOT / 'bin/statusline.lua'),
                           '--config', str(plugin / f'statusline/hue-{mood}.json')]
        rendered = subprocess.run(command, input='{}', text=True, capture_output=True,
                                  env=env, timeout=10)
        assert rendered.returncode == 0 and 'unknown' in rendered.stdout, rendered.stderr

    verify([])
    verify(['--', "quote ' spaces", '', 'line\nbreak'], remaining=["quote ' spaces", '', 'line\nbreak'])
    verify(['--mood', 'huong', '--', 'resume', 'session'], 'huong', ['resume', 'session'])
    verify(['--mood=cung', '-p', 'prompt'], 'cung', ['-p', 'prompt'])
    env['HUE_THEME_ROOT'] = 'hue root'
    verify(['--mood=huong'], 'huong', [])
    env['HUE_THEME_ROOT'] = str(temp / 'hue root')
    for arguments, overrides in ((['--mood'], {}), (['--mood=bad'], {}), (['--mood='], {}),
                                 ([], {'HUE_THEME_ROOT': ''}),
                                 ([], {'HUE_THEME_ROOT': str(temp / 'missing')})):
        record.unlink(missing_ok=True)
        child = subprocess.run([str(launcher), *arguments], env=dict(env, **overrides),
                               capture_output=True, timeout=10)
        assert child.returncode != 0 and child.stderr
        assert not record.exists()
    path = plugin / 'statusline/hue-mua.json'
    path.write_text('{broken')
    child = subprocess.run([str(launcher)], env=env, capture_output=True, timeout=10)
    assert child.returncode != 0 and b'config' in child.stderr
    path.write_text(json.dumps(config))
    for arguments in ([], ['mua'], ['mua', 'entry', str(path), 'extra']):
        child = subprocess.run(['nvim', '-l', str(ROOT / 'bin/session.lua'), *arguments],
                               env=env, capture_output=True, timeout=10)
        assert child.returncode != 0 and b'usage:' in child.stderr

    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        record.unlink(missing_ok=True)
        master, slave = pty.openpty()
        child = subprocess.Popen([str(launcher), '--mood=huong'], cwd=temp,
                                 env=dict(env, WAIT_FOR_SIGNAL='1'),
                                 stdin=slave, stdout=slave, stderr=slave)
        try:
            deadline = time.monotonic() + 10
            while True:
                try:
                    data = json.loads(record.read_text())
                    break
                except (FileNotFoundError, json.JSONDecodeError):
                    assert time.monotonic() < deadline
                    time.sleep(0.01)
            assert data['pid'] == child.pid and data['tty'] == [True, True, True]
            child.send_signal(signum)
            assert child.wait(timeout=5) == -signum
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()
            os.close(master)
            os.close(slave)

print('Claude launcher assertions passed')
