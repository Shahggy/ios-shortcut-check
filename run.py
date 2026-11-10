"""Apple platform probe. Run a fresh iPhone 16e only; never pair a physical device."""
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import urllib.request

HERE = Path(__file__).resolve().parent
MODEL = "com.apple.CoreSimulator.SimDeviceType.iPhone-16e"
TARGET = (27, 0, 1)
PUBLIC_FILE = "https://temporary-nimble-spruce-dz8vszj.vercel.app/shortcuts/ShagAttack.shortcut"
DIGEST = "2e12d8a24d8a9e425a4d789c2354ac53f258c37f2816f4977df92ae38491f219"

def choose(runtimes):
    candidates = []
    for r in runtimes:
        if not r.get("isAvailable") or ".SimRuntime.iOS-" not in r.get("identifier",""):
            continue
        version = tuple(map(int,r["version"].split("."))) + (0,0)
        version = version[:3]
        supported = r.get("supportedDeviceTypes")
        if version[0] != TARGET[0] or (supported and not any(t.get("identifier")==MODEL for t in supported)):
            continue
        candidates.append(((abs(version[1]-TARGET[1]),abs(version[2]-TARGET[2])),r))
    return min(candidates,key=lambda entry:entry[0])[1] if candidates else None

def call(*args, capture=False, timeout=240, check=True):
    return subprocess.run(args,check=check,text=True,capture_output=capture,timeout=timeout)

def run():
    if platform.system() != "Darwin":
        raise SystemExit("NOT RUN: Xcode/macOS required. No iPhone result.")
    if os.environ.get("GITHUB_ACTIONS") == "true":
        with open(os.environ["GITHUB_EVENT_PATH"]) as stream: event = json.load(stream)
        if event.get("repository",{}).get("visibility") != "public" or os.environ.get("GITHUB_EVENT_NAME") != "workflow_dispatch":
            raise SystemExit("Refusing private or automatic cloud run.")
    call("xcodebuild","-version")
    catalog=json.loads(call("xcrun","simctl","list","-j",capture=True).stdout)
    runtime=choose(catalog["runtimes"])
    if not runtime or MODEL not in {d["identifier"] for d in catalog["devicetypes"]}:
        raise SystemExit("BLOCKED: No compatible iPhone 16e / iOS 27 simulator. No substitute model used.")
    print("SIMULATOR_EVIDENCE",json.dumps({"model":"iPhone 16e","requested":"27.0.1","actual":runtime["version"],"physical":False}),flush=True)
    udid=call("xcrun","simctl","create","Isolated shortcut test",MODEL,runtime["identifier"],capture=True).stdout.strip()
    # Only the device created by the previous call may be cleaned up.
    import uuid
    uuid.UUID(udid)
    try:
        call("xcrun","simctl","bootstatus",udid,"-b",timeout=360)
        capabilities={b:call("xcrun","simctl","get_app_container",udid,b,"app",capture=True,check=False).returncode==0
                      for b in ("com.apple.shortcuts","com.apple.mobilesafari","com.apple.mobiletimer")}
        print("SIMULATOR_EVIDENCE",json.dumps(capabilities),flush=True)
        with tempfile.TemporaryDirectory(prefix="shortcut-lab-") as tmp:
            root=Path(tmp)
            for name in ("Probe","Checks"): shutil.copytree(HERE/name,root/name)
            shutil.copy(HERE/"project.yml",root)
            with urllib.request.urlopen(PUBLIC_FILE,timeout=30) as response:
                if response.geturl()!=PUBLIC_FILE: raise RuntimeError("Unexpected fixture redirect")
                fixture=response.read(100_001)
            if hashlib.sha256(fixture).hexdigest()!=DIGEST or not fixture.startswith(b"AEA1"):
                raise RuntimeError("The public signed shortcut has changed; review the new artifact first.")
            (root/"Probe"/"ShagAttack.shortcut").write_bytes(fixture)
            os.environ["HOMEBREW_NO_AUTO_UPDATE"]="1"
            if not shutil.which("xcodegen"): call("brew","install","xcodegen")
            call("xcodegen","generate","--spec",str(root/"project.yml"),"--project",str(root))
            args=["xcodebuild","-project",str(root/"ShortcutLab.xcodeproj"),"-scheme","ShortcutLab","-destination","platform=iOS Simulator,id="+udid,
                  "-parallel-testing-enabled","NO","-maximum-concurrent-test-simulator-destinations","1","-derivedDataPath",str(root/"Derived")]
            if not capabilities["com.apple.shortcuts"]:
                call(*args,"-only-testing:Checks/RoutingTests/testPublishedAppOpensInSafari","test",timeout=540)
                raise SystemExit("BLOCKED: Apple Shortcuts is absent from this runtime; no Siri/Clock shortcut test can pass.")
            call(*args,"test",timeout=650)
    finally:
        call("xcrun","simctl","delete",udid,check=False)

if __name__=="__main__": run()
