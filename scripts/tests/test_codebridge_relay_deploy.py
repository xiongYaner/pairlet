"""Personal relay deployment failures use an isolated filesystem and fake service manager."""
import hashlib
import json
import os
import pathlib
import sqlite3
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[2] / 'deploy/codebridge/apply-relay.sh'
PREPARE = pathlib.Path(__file__).resolve().parents[2] / 'scripts/deploy-codebridge-relay.sh'
FAKE = r'''#!/usr/bin/env python3
import os,pathlib,signal,sqlite3,subprocess,sys
base=pathlib.Path(os.environ['CODEBRIDGE_FIXTURE']); root=base/'installed'
name=pathlib.Path(sys.argv[0]).name; args=sys.argv[1:]; mode=os.environ.get('CODEBRIDGE_FAILURE','')
with (base/'commands').open('a') as log: log.write(name+' '+' '.join(args)+'\n')
def version():
 try:return (root/'lib/version').read_text()
 except OSError:return 'missing'
if name=='systemctl':
 if args[0]=='cat':print('fixture-only service');sys.exit(0)
 if args[0]=='is-active':sys.exit(0 if (base/'active').exists() else 1)
 if args[0]=='stop':(base/'active').unlink(missing_ok=True)
 if args[0]=='start':
  if mode=='new_start' and version()=='new':
   with sqlite3.connect(base/'relay.db') as db:db.execute('insert into markers values (2)')
   sys.exit(1)
  if mode=='rollback_start':sys.exit(1)
  (base/'active').touch()
elif name=='curl':
 if mode=='new_health' and version()=='new':sys.exit(1)
 sys.exit(0 if (base/'active').exists() else 1)
elif name=='cp':
 if mode=='prepare_copy' and str(base/'stage/bin') in args:sys.exit(1)
 sys.exit(subprocess.run(['/bin/cp']+args).returncode)
elif name=='mv':
 if mode=='swap_hup' and any('/.incoming-' in a and a.endswith('/lib') for a in args):
  os.kill(os.getppid(),signal.SIGHUP);sys.exit(1)
 sys.exit(subprocess.run(['/bin/mv']+args).returncode)
'''


class PersonalRelayDeployTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='codebridge-relay-fixture-')
        self.addCleanup(self.temp.cleanup)
        self.base = pathlib.Path(self.temp.name)
        self.root, self.stage = self.base/'installed', self.base/'stage'
        for folder, version in ((self.root, 'old'), (self.stage, 'new')):
            (folder/'bin').mkdir(parents=True); (folder/'lib').mkdir()
            (folder/'bin/cc-pocket-relay').write_text('#!/bin/sh\nexit 0\n')
            (folder/'lib/version').write_text(version)
        (self.stage/'release.json').write_text(json.dumps({'source_commit':'test-fixture'}))
        self.manifest()
        (self.base/'active').touch()
        self.db = self.base/'relay.db'
        with sqlite3.connect(self.db) as db:
            db.execute('create table markers(value integer)'); db.execute('insert into markers values (1)')
        (self.base/'nginx.conf').write_text('untouched nginx')
        (self.base/'push.env').write_text('fixture-only credentials')
        fake = self.base/'fake'; fake.mkdir()
        command = fake/'command'; command.write_text(FAKE); command.chmod(0o755)
        for name in ('systemctl','curl','cp','mv','flock','chown','sleep'):(fake/name).symlink_to(command)
        self.env = dict(os.environ, CODEBRIDGE_FIXTURE=str(self.base), PATH=str(fake)+os.pathsep+os.environ['PATH'])

    def manifest(self):
        (self.stage/'dist.sha256').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+str(p.relative_to(self.stage))+'\n'
            for p in sorted(self.stage.rglob('*')) if p.is_file() and p.name!='dist.sha256'))

    def apply(self, failure=''):
        result = subprocess.run(['bash',str(SCRIPT),str(self.stage),str(self.root),'fixture-only',
            'http://127.0.0.1:1/healthz',str(self.db)], env=dict(self.env,CODEBRIDGE_FAILURE=failure),
            capture_output=True,text=True,timeout=30)
        self.assertEqual((self.base/'nginx.conf').read_text(),'untouched nginx')
        self.assertEqual((self.base/'push.env').read_text(),'fixture-only credentials')
        commands=(self.base/'commands').read_text()
        self.assertNotIn('nginx',commands); self.assertNotIn('caddy',commands); self.assertNotIn('docker',commands)
        return result

    def state(self):return (self.stage/'result').read_text().strip()
    def version(self):return (self.root/'lib/version').read_text()

    def test_success_keeps_program_and_consistent_database_backup(self):
        result=self.apply(); self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(self.state(),'ok'); self.assertEqual(self.version(),'new')
        backup=pathlib.Path((self.stage/'backup-path').read_text().strip())
        self.assertEqual((backup/'lib/version').read_text(),'old')
        with sqlite3.connect(backup/'relay.db') as db:self.assertEqual(db.execute('select value from markers').fetchall(),[(1,)])
        self.assertEqual((backup/'relay.db').stat().st_mode & 0o777,0o600)

    def test_completed_staging_cannot_restart_service_or_replace_its_result(self):
        self.assertEqual(self.apply().returncode,0)
        previous = (self.base/'commands').read_text()
        self.assertEqual(self.apply().returncode,65)
        self.assertEqual(self.state(),'ok')
        self.assertEqual((self.base/'commands').read_text(),previous)

    def test_corrupt_upload_does_not_stop_service(self):
        (self.stage/'lib/version').write_text('corrupted')
        self.assertNotEqual(self.apply().returncode,0)
        self.assertEqual(self.state(),'failed'); self.assertEqual(self.version(),'old')
        self.assertNotIn('systemctl stop',(self.base/'commands').read_text())

    def test_missing_launcher_does_not_stop_service(self):
        (self.stage/'bin/cc-pocket-relay').unlink()
        self.assertNotEqual(self.apply().returncode,0)
        self.assertNotIn('systemctl stop',(self.base/'commands').read_text())

    def test_preparation_copy_failure_does_not_stop_service(self):
        self.assertNotEqual(self.apply('prepare_copy').returncode,0)
        self.assertNotIn('systemctl stop',(self.base/'commands').read_text()); self.assertEqual(self.version(),'old')

    def test_failed_start_restores_program_without_rolling_back_database(self):
        self.assertNotEqual(self.apply('new_start').returncode,0)
        self.assertEqual(self.state(),'rolled_back'); self.assertEqual(self.version(),'old')
        with sqlite3.connect(self.db) as db:self.assertEqual(db.execute('select value from markers').fetchall(),[(1,),(2,)])
        self.assertTrue((self.base/'active').exists())

    def test_failed_health_restores_program(self):
        self.assertNotEqual(self.apply('new_health').returncode,0)
        self.assertEqual(self.state(),'rolled_back'); self.assertEqual(self.version(),'old')

    def test_signal_during_swap_restores_program(self):
        self.assertEqual(self.apply('swap_hup').returncode,129)
        self.assertEqual(self.state(),'rolled_back'); self.assertEqual(self.version(),'old')

    def test_rollback_failure_is_reported_and_backup_is_preserved(self):
        self.assertNotEqual(self.apply('rollback_start').returncode,0)
        self.assertEqual(self.state(),'rollback_failed')
        backup=pathlib.Path((self.stage/'backup-path').read_text().strip())
        self.assertEqual((backup/'lib/version').read_text(),'old')

    def test_symlink_payload_is_rejected_before_stopping_service(self):
        (self.stage/'lib/symlink').symlink_to(self.stage/'lib/version')
        self.assertNotEqual(self.apply().returncode,0)
        self.assertNotIn('systemctl stop',(self.base/'commands').read_text())

    def test_prepare_refuses_existing_payload_instead_of_mixing_old_jars(self):
        output = self.base/'release'; (output/'payload/lib').mkdir(parents=True)
        old = output/'payload/lib/stale.jar'; old.write_text('old jar')
        result = subprocess.run(['bash',str(PREPARE),'--prepare-only','--dist',str(self.stage),
            '--output',str(output)],capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,65,result.stdout+result.stderr)
        self.assertEqual(old.read_text(),'old jar')
        self.assertFalse((output/'dist.tgz').exists())

    def test_prepare_fresh_payload_covers_every_program_file(self):
        output = self.base/'release'
        result = subprocess.run(['bash',str(PREPARE),'--prepare-only','--dist',str(self.stage),
            '--output',str(output)],capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        manifest = json.loads((output/'payload/release.json').read_text())
        self.assertEqual(manifest['files']['lib/version'],hashlib.sha256(b'new').hexdigest())
        self.assertTrue((output/'dist.tgz').is_file())


if __name__=='__main__':unittest.main()
