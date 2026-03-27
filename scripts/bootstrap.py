from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from skill_runtime import (
    DEFAULT_MODEL_DIR,
    SCRIPT_DIR,
    ensure_skill_requirements,
    runtime_summary,
)


def run_script_with_venv(
    venv_python: Path,
    script_name: str,
    script_args: list[str] | None = None,
    capture_output: bool = False,
) -> subprocess.CompletedProcess[str]:
    if script_args is None:
        script_args = []
    cmd = [str(venv_python), str(SCRIPT_DIR / script_name), *script_args]
    return subprocess.run(
        cmd,
        check=False,
        capture_output=capture_output,
        text=True,
    )


def ensure_ffmpeg(venv_python: Path, force: bool = False) -> None:
    args: list[str] = []
    if force:
        args.append("--force")
    result = run_script_with_venv(venv_python, "setup_resources.py", args)
    if result.returncode != 0:
        raise RuntimeError("ffmpeg / ffprobe 准备失败")


def ensure_model(venv_python: Path, force: bool = False) -> None:
    if not force:
        check = run_script_with_venv(
            venv_python,
            "setup_ov_model.py",
            ["--check-only"],
            capture_output=True,
        )
        if check.returncode == 0:
            if check.stdout:
                print(check.stdout.strip())
            return
        if check.stdout:
            print(check.stdout.strip())
        if check.stderr:
            print(check.stderr.strip(), file=sys.stderr)

    args: list[str] = []
    if force:
        args.append("--force")
    result = run_script_with_venv(venv_python, "setup_ov_model.py", args)
    if result.returncode != 0:
        raise RuntimeError(f"模型准备失败：{DEFAULT_MODEL_DIR}")


def bootstrap_environment(
    force_requirements: bool = False,
    force_ffmpeg: bool = False,
    force_model: bool = False,
    skip_ffmpeg: bool = False,
    skip_model: bool = False,
) -> dict[str, str]:
    venv_python = ensure_skill_requirements(force=force_requirements)
    if not skip_ffmpeg:
        ensure_ffmpeg(venv_python, force=force_ffmpeg)
    if not skip_model:
        ensure_model(venv_python, force=force_model)
    return runtime_summary()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="统一准备阶段 bootstrap：.venv、requirements、ffmpeg、模型"
    )
    parser.add_argument(
        "--force-requirements",
        action="store_true",
        help="强制重新安装 requirements.txt",
    )
    parser.add_argument(
        "--force-ffmpeg",
        action="store_true",
        help="强制重新下载 ffmpeg / ffprobe",
    )
    parser.add_argument(
        "--force-model",
        action="store_true",
        help="强制重新下载 OpenVINO 模型",
    )
    parser.add_argument(
        "--skip-ffmpeg",
        action="store_true",
        help="跳过 ffmpeg / ffprobe 准备",
    )
    parser.add_argument(
        "--skip-model",
        action="store_true",
        help="跳过模型准备",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="以 JSON 输出准备结果",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        summary = bootstrap_environment(
            force_requirements=args.force_requirements,
            force_ffmpeg=args.force_ffmpeg,
            force_model=args.force_model,
            skip_ffmpeg=args.skip_ffmpeg,
            skip_model=args.skip_model,
        )
    except Exception as exc:
        print(f"[bootstrap] ✗ 失败：{exc}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    else:
        print("[bootstrap] ✓ 准备完成")
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
