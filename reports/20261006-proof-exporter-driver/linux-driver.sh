#!/usr/bin/env bash
# Run bounded native acceptance in this fresh public-source directory.
set -euo pipefail
cd /var/tmp/sqlite-verifier-exporter.4yS0uj/source
mkdir -p ../validation build/test-results
python3 tools/check_resources.py > ../validation/resources.log 2>&1
just test > ../validation/development.log 2>&1
readlink -f build/runtime > ../validation/runtime-path
just test-nix > ../validation/nix-inputs.log 2>&1
just runtime-package > ../validation/package.log 2>&1
# Run exporter-specific cases through the actual offline-installed archive too.
timeout 900 python3 -m pytest -q tests/proof_exporter_test.py \
  --runtime-archive dist/sqlite-verifier-x86_64-linux.tar.gz --runtime-variant installed \
  --junitxml ../validation/exporter-installed.xml > ../validation/exporter-installed.log 2>&1
python3 - <<'PY'
from pathlib import Path
import hashlib,json,platform,subprocess,sys,xml.etree.ElementTree as ET
root=Path.cwd()
out=root.parent/'validation'
runtime=(root/'build/runtime').resolve()
receipts={}
for path in [root/'build/test-results/source.xml',root/'build/test-results/nix.xml',root/'build/test-results/installed.xml',out/'exporter-installed.xml']:
 suites=list(ET.parse(path).getroot().iter('testsuite'))
 receipts[str(path.relative_to(root.parent))]={'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
    'suites':[{key:s.attrib[key] for key in ('tests','failures','errors','skipped','time')} for s in suites]}
expected={'atuin','bundle','cli','kernel','sample','upstream'}
found=set()
for test in sorted((root/'build').glob('nix-tests*')):
 target=test.resolve()
 path=target/'junit.xml'
 if path.is_file():
  name=next((name for name in expected if '-test-'+name+'-' in target.name),None)
  if name is not None:
   found.add(name)
   receipts[name]={'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
    'suites':[{key:s.attrib[key] for key in ('tests','failures','errors','skipped','time')}
      for s in ET.parse(path).getroot().iter('testsuite')]}
if found != expected:
 raise RuntimeError('Development JUnit targets differ; inspect build/nix-tests* links: '+str(sorted(found)))
archive=root/'dist/sqlite-verifier-x86_64-linux.tar.gz'
with archive.open('rb') as stream:
 archive_sha=hashlib.file_digest(stream,'sha256').hexdigest()
executables={}
for name in ('migration-proof-exporter','migration-bundle-checker','migration-proof-checker'):
 with (runtime/'.lake/build/bin'/name).open('rb') as stream:
  executables[name]=hashlib.file_digest(stream,'sha256').hexdigest()
receipt={'platform':platform.platform(),'machine':platform.machine(),'python':sys.executable,
 'runtime':str(runtime),'lean':subprocess.run([str(runtime/'lean/bin/lean'),'--version'],
   check=True,capture_output=True,text=True,timeout=5).stdout.strip(),
 'junit':receipts,'executablesSha256':executables,
 'archive':{'bytes':archive.stat().st_size,'sha256':archive_sha},'status':'passed'}
(out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'status':receipt['status'],'runtime':receipt['runtime'],'checks':list(receipts)}))
PY
