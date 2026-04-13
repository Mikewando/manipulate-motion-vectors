import os
import sys
import shutil
import subprocess
from typing import Any
from pathlib import Path
from packaging import tags
from hatchling.builders.hooks.plugin.interface import BuildHookInterface

class ZigBuildHook(BuildHookInterface):
    PLUGIN_NAME = "custom"

    def initialize(self, version: str, build_data: dict[str, Any]) -> None:
        build_data["pure_python"] = False

        root = Path(self.root)
        out = root / "vapoursynth" / "plugins" / "manipmv"
        out.mkdir(parents=True, exist_ok=True)

        shutil.copy2(root / "manifest.vs", out / "manifest.vs")

        target = os.environ.get("MANIPMV_TARGET")
        cpus = os.environ.get("MANIPMV_CPUS")
        tag = os.environ.get("MANIPMV_TAG") or next(tags.platform_tags())

        build_data["tag"] = f"py3-none-{tag}"

        if cpus:
            for entry in cpus.split(";"):
                cpu, _, opt = entry.partition(":")
                self._zig_build(root, target=target, cpu=cpu)
                self._collect_artifacts(root, out, opt_level=opt)
                shutil.rmtree(root / "zig-out", ignore_errors=True)
        else:
            self._zig_build(root, target=target)
            self._collect_artifacts(root, out)


    def _zig_build(self, root: Path, target: str | None = None, cpu: str | None = None) -> None:
        cmd = [sys.executable, "-m", "ziglang", "build", "-Doptimize=ReleaseFast"]
        if target:
            cmd.append(f"-Dtarget={target}")
        if cpu:
            cmd.append(f"-Dcpu={cpu}")
        subprocess.run(cmd, cwd=root, check=True)


    def _collect_artifacts(self, root: Path, out: Path, opt_level: str | None = None) -> None:
        extensions = {".so", ".dll", ".dylib"}
        for dirpath, _, filenames in os.walk(root / "zig-out"):
            for filename in filenames:
                src = Path(dirpath) / filename
                if src.suffix in extensions:
                    if opt_level:
                        dest = out / f"{src.stem}.{opt_level}{src.suffix}"
                    else:
                        dest = out / filename
                    shutil.copy2(src, dest)
