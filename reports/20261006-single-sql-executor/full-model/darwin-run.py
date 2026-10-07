from pathlib import Path
import datetime, json, subprocess, time
root=Path('/Users/tzankomatev/work/sqlite-verifier-executor')
command=['timeout','900','nix-build','/private/tmp/t05-model-600.nix','--out-link','build/t05-nix-model-600','--option','sandbox','true','--option','sandbox-fallback','false','--extra-experimental-features','nix-command flakes']
start=time.monotonic();wall=datetime.datetime.now(datetime.UTC).isoformat()
with (root/'build/t05-model-full-darwin-600.log').open('wb') as log:
    try:
        result=subprocess.run(command,cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=900)
        code=result.returncode
    except subprocess.TimeoutExpired:
        code=124
meta={'command':command,'outerLimitSeconds':900,'validationSuiteLimitSeconds':600,'startedUtc':wall,'finishedUtc':datetime.datetime.now(datetime.UTC).isoformat(),'elapsedMonotonicSeconds':time.monotonic()-start,'exitCode':code}
(root/'build/t05-model-full-darwin-600-process.json').write_text(json.dumps(meta,indent=2)+'\n')
print(json.dumps(meta));raise SystemExit(code)
