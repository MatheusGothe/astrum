#!/usr/bin/env python3
"""Non-interactive feasibility probe for Astrum as an Apple Silicon Mac app."""

from __future__ import annotations

import json
import os
import pathlib
import platform
import re
import shutil
import subprocess
import sys
import time

APP_STORE_ID = "6758635201"
APP_STORE_URL = f"https://apps.apple.com/br/app/astrum/id{APP_STORE_ID}"
OUTPUT = pathlib.Path(os.environ.get("GITHUB_OUTPUT", "/dev/null"))
SUMMARY = pathlib.Path(os.environ.get("GITHUB_STEP_SUMMARY", "/dev/null"))
ARTIFACT = pathlib.Path("artifacts/macos-poc.json")
try:
    STATE: dict[str, object] = json.loads(ARTIFACT.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    STATE = {}


def emit_output(**values: object) -> None:
    with OUTPUT.open("a", encoding="utf-8") as handle:
        for key, value in values.items():
            handle.write(f"{key}={value}\n")


def run(command: list[str], timeout: int = 30) -> dict[str, object]:
    started = time.monotonic()
    try:
        result = subprocess.run(
            command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=timeout, check=False,
        )
        output = re.sub(r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}", "[redacted-email]", result.stdout.strip())
        return {
            "command": " ".join(command),
            "returncode": result.returncode,
            "output": output[-5000:],
            "seconds": round(time.monotonic() - started, 2),
        }
    except subprocess.TimeoutExpired as exc:
        captured = exc.stdout or ""
        if isinstance(captured, bytes):
            captured = captured.decode("utf-8", errors="replace")
        return {
            "command": " ".join(command), "returncode": 124,
            "output": f"Timed out after {timeout}s. {captured}"[-5000:],
            "seconds": round(time.monotonic() - started, 2),
        }
    except OSError as exc:
        return {
            "command": " ".join(command), "returncode": 127,
            "output": f"Command unavailable: {exc}",
            "seconds": round(time.monotonic() - started, 2),
        }


def log_result(label: str, result: dict[str, object]) -> None:
    print(f"## {label} ({result['seconds']}s): exit {result['returncode']}")
    if result["output"]:
        print(re.sub(r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}", "[redacted-email]", str(result["output"])))


def persist() -> None:
    ARTIFACT.parent.mkdir(parents=True, exist_ok=True)
    ARTIFACT.write_text(json.dumps(STATE, indent=2), encoding="utf-8")


def find_astrum_app() -> str | None:
    spotlight = run(["mdfind", f"kMDItemAppStoreAdamID == '{APP_STORE_ID}'"], timeout=20)
    candidates = [line for line in str(spotlight["output"]).splitlines() if line.endswith(".app")]
    candidates += ["/Applications/Astrum.app", str(pathlib.Path.home() / "Applications/Astrum.app")]
    return next((candidate for candidate in candidates if pathlib.Path(candidate).exists()), None)


def capture_app_store_ui(stage: str) -> dict[str, object]:
    artifact_dir = pathlib.Path("artifacts")
    artifact_dir.mkdir(parents=True, exist_ok=True)
    screenshot = artifact_dir / f"app-store-screen-{stage}.png"
    accessibility_dump = artifact_dir / f"app-store-accessibility-{stage}.txt"

    screenshot_result = run(["screencapture", "-x", str(screenshot)], timeout=15)
    tree_result = run(["swift", "scripts/dump-app-store-accessibility.swift"], timeout=25)
    tree_text = re.sub(
        r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}", "[redacted-email]", str(tree_result["output"])
    )
    accessibility_dump.write_text(tree_text + "\n", encoding="utf-8")
    log_result("App Store visible accessibility text", tree_result)
    print(f"App Store screenshot: {screenshot} (exit {screenshot_result['returncode']})")
    return {
        "screenshot": str(screenshot), "screenshot_result": screenshot_result,
        "accessibility_dump": str(accessibility_dump), "accessibility_result": tree_result,
    }


def inspect() -> None:
    started = time.monotonic()
    os_version = run(["sw_vers", "-productVersion"])
    build = run(["sw_vers", "-buildVersion"])
    xcode = run(["xcode-select", "-p"])
    gui = run(["launchctl", "print", f"gui/{os.getuid()}"], timeout=10)
    store_path = pathlib.Path("/System/Applications/App Store.app")
    accessibility = run([
        "osascript", "-e",
        'tell application "System Events" to get name of first process',
    ], timeout=15)
    accessibility_trust = run([
        "swift", "-e",
        'import ApplicationServices; print(AXIsProcessTrusted() ? "trusted" : "not_trusted")',
    ], timeout=30)
    STATE["environment"] = {
        "macos_version": os_version["output"], "build": build["output"],
        "architecture": platform.machine(), "user": os.environ.get("USER", "unknown"),
        "uid": os.getuid(), "xcode_select": xcode["output"],
        "gui_session": gui["returncode"] == 0,
        "window_server_running": run(["pgrep", "-x", "WindowServer"])["returncode"] == 0,
        "app_store_present": store_path.exists(),
        "accessibility_probe": accessibility,
        "accessibility_trusted": accessibility_trust["output"],
        "osascript_available": shutil.which("osascript") is not None,
        "mas_preinstalled": shutil.which("mas") is not None,
    }
    print("## Runner environment")
    print(json.dumps(STATE["environment"], indent=2))
    elapsed = round(time.monotonic() - started, 2)
    STATE["timings"] = {"environment_inspection_seconds": elapsed}
    emit_output(seconds=elapsed)
    persist()


def install_launch() -> None:
    started = time.monotonic()
    store_path = pathlib.Path("/System/Applications/App Store.app")
    store_start = time.monotonic()
    store_open = run(["open", "-a", str(store_path), APP_STORE_URL], timeout=20)
    store_open["seconds"] = round(time.monotonic() - store_start, 2)
    log_result("Open App Store listing", store_open)

    lookup = run(["mas", "lookup", APP_STORE_ID], timeout=45)
    log_result("mas public lookup", lookup)

    install_start = time.monotonic()
    install = run(["mas", "install", APP_STORE_ID], timeout=150)
    install_seconds = round(time.monotonic() - install_start, 2)
    log_result("mas install attempt (no Apple ID credentials supplied)", install)

    gui_install_start = time.monotonic()
    gui_install = run(["osascript", "scripts/probe-mac-app-store.applescript"], timeout=35)
    log_result("App Store GUI download-button probe", gui_install)
    before_retry = capture_app_store_ui("before-retry")
    retry_result: dict[str, object] | None = None
    after_retry: dict[str, object] | None = None
    continue_result: dict[str, object] | None = None
    after_continue: dict[str, object] | None = None
    not_now_result: dict[str, object] | None = None
    after_not_now: dict[str, object] | None = None
    listing_open_result: dict[str, object] | None = None
    astrum_listing: dict[str, object] | None = None
    install_button_result: dict[str, object] | None = None
    after_install_attempt: dict[str, object] | None = None
    visible_text = str(before_retry["accessibility_result"].get("output", ""))
    if "Cannot Connect" in visible_text and "Retry" in visible_text:
        retry_result = run(["swift", "scripts/dump-app-store-accessibility.swift", "--click-retry"], timeout=25)
        log_result("Retry App Store page load", retry_result)
        if "UI_ACTION_RETRY=clicked" in str(retry_result["output"]):
            time.sleep(15)
            after_retry = capture_app_store_ui("after-retry")
            retry_text = str(after_retry["accessibility_result"].get("output", ""))
            if "AXButton: Continue" in retry_text:
                continue_result = run(
                    ["swift", "scripts/dump-app-store-accessibility.swift", "--click-continue"],
                    timeout=25,
                )
                log_result("Continue past App Store welcome screen", continue_result)
                if "UI_ACTION_CONTINUE=clicked" in str(continue_result["output"]):
                    time.sleep(10)
                    after_continue = capture_app_store_ui("after-continue")
                    continue_text = str(after_continue["accessibility_result"].get("output", ""))
                    if "AXStaticText: Not Now" in continue_text:
                        not_now_result = run(
                            ["swift", "scripts/dump-app-store-accessibility.swift", "--click-not-now"],
                            timeout=25,
                        )
                        log_result("Dismiss App Store notifications prompt", not_now_result)
                        if "UI_ACTION_NOT NOW=clicked" in str(not_now_result["output"]):
                            time.sleep(5)
                            after_not_now = capture_app_store_ui("after-not-now")
                            listing_open_result = run(["open", "-a", str(store_path), APP_STORE_URL], timeout=20)
                            log_result("Open Astrum listing after first-run prompts", listing_open_result)
                            time.sleep(15)
                            astrum_listing = capture_app_store_ui("astrum-listing")
                            listing_text = str(astrum_listing["accessibility_result"].get("output", ""))
                            install_clicked = False
                            if re.search(r"^\s*AXButton: (Get|Download|Install|Obter|Baixar|Instalar)$", listing_text, re.MULTILINE):
                                install_button_result = run(
                                    ["swift", "scripts/dump-app-store-accessibility.swift", "--click-install"],
                                    timeout=25,
                                )
                                log_result("Click App Store install button", install_button_result)
                                install_clicked = "UI_ACTION_INSTALL=clicked" in str(install_button_result["output"])
                            else:
                                install_button_result = run(
                                    [
                                        "swift", "scripts/dump-app-store-accessibility.swift",
                                        "--click-visible-get", "artifacts/app-store-screen-astrum-listing.png",
                                    ],
                                    timeout=30,
                                )
                                log_result("Click visible Get button using screenshot text", install_button_result)
                                install_clicked = "UI_ACTION_GET=clicked_by_ocr" in str(install_button_result["output"])
                            if install_clicked:
                                deadline = time.monotonic() + 60
                                while time.monotonic() < deadline and not find_astrum_app():
                                    time.sleep(3)
                                after_install_attempt = capture_app_store_ui("after-install-attempt")
    ui_diagnostics = {
        "before_retry": before_retry, "retry": retry_result, "after_retry": after_retry,
        "continue": continue_result, "after_continue": after_continue,
        "not_now": not_now_result, "after_not_now": after_not_now,
        "listing_open": listing_open_result, "astrum_listing": astrum_listing,
        "install_button": install_button_result, "after_install_attempt": after_install_attempt,
    }

    app_path = find_astrum_app()
    if not app_path and "download_button_clicked" in str(gui_install["output"]):
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline and not app_path:
            time.sleep(3)
            app_path = find_astrum_app()
    gui_install_seconds = round(time.monotonic() - gui_install_start, 2)

    app_info: dict[str, object] = {}
    launched = False
    launch_seconds = 0.0
    if app_path:
        app = pathlib.Path(app_path)
        bundle_id = run(["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleIdentifier", str(app / "Contents/Info.plist")])
        executable = run(["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleExecutable", str(app / "Contents/Info.plist")])
        executable_path = app / "Contents/MacOS" / str(executable["output"])
        arch = run(["file", str(executable_path)]) if executable_path.exists() else {"output": "No Contents/MacOS executable", "returncode": 1}
        launch_start = time.monotonic()
        launch = run(["open", app_path], timeout=20)
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            proc = run(["pgrep", "-fl", "Astrum"], timeout=5)
            if proc["returncode"] == 0:
                launched = True
                break
            time.sleep(1)
        launch_seconds = round(time.monotonic() - launch_start, 2)
        app_info = {
            "path": app_path, "bundle_id": bundle_id["output"],
            "executable": executable_path.name, "binary": arch["output"],
            "open_result": launch, "process_detected": launched,
        }
    else:
        print("Astrum.app was not found in /Applications, ~/Applications, or Spotlight results.")

    STATE["installation"] = {
        "app_store_id": APP_STORE_ID, "app_store_open": store_open,
        "app_store_gui_probe": gui_install, "app_store_gui_install_seconds": gui_install_seconds,
        "app_store_ui_diagnostics": ui_diagnostics,
        "mas_lookup": lookup, "mas_install": install,
        "app_found": bool(app_path), "app": app_info,
    }
    timings = STATE.setdefault("timings", {})
    assert isinstance(timings, dict)
    timings["app_store_open_seconds"] = round(store_open["seconds"], 2)
    timings["mas_lookup_seconds"] = round(install_start - store_start - float(store_open["seconds"]), 2)
    timings["mas_install_seconds"] = install_seconds
    timings["app_store_gui_install_seconds"] = gui_install_seconds
    timings["launch_seconds"] = launch_seconds
    total = round(time.monotonic() - started, 2)
    emit_output(
        install_seconds=install_seconds, gui_install_seconds=gui_install_seconds,
        launch_seconds=launch_seconds,
        app_found=str(bool(app_path)).lower(), app_launched=str(launched).lower(),
    )
    print(json.dumps(STATE["installation"], indent=2))
    persist()


def ui_probe() -> None:
    started = time.monotonic()
    script = pathlib.Path("scripts/probe-astrum-ui.applescript")
    result = run(["osascript", str(script)], timeout=30)
    log_result("AppleScript/System Events UI probe", result)
    ok = result["returncode"] == 0 and "PROBE_RESULT=interaction_verified" in str(result["output"])
    STATE["ui_automation"] = {**result, "interaction_verified": ok}
    timings = STATE.setdefault("timings", {})
    assert isinstance(timings, dict)
    timings["ui_probe_seconds"] = round(time.monotonic() - started, 2)
    emit_output(seconds=timings["ui_probe_seconds"], result="verified" if ok else "not_verified")
    persist()


def summary() -> None:
    # Summary runs in a fresh step; preserve values exported by prior steps.
    env = STATE.get("environment", {})
    install = STATE.get("installation", {})
    app_found = os.environ.get("APP_FOUND", "false") == "true"
    app_launched = os.environ.get("APP_LAUNCHED", "false") == "true"
    ui_result = os.environ.get("UI_RESULT", "not_run")
    architecture = str(env.get("architecture", "unknown"))
    if architecture != "arm64":
        verdict = f"Runner mismatch: expected Apple Silicon arm64 but detected {architecture}."
    elif app_found and app_launched and ui_result == "verified":
        verdict = "Complete success: Astrum installed, launched, and UI interaction verified."
    elif app_found and app_launched:
        verdict = "Partial success: Astrum installed and launched; UI automation was not verified."
    elif app_found:
        verdict = "Execution failure: Astrum was installed but did not remain open."
    else:
        verdict = "Installation failure: Astrum was not installed by the non-interactive App Store path."

    rows = [
        ("macOS / architecture / GUI / App Store", f"{env.get('macos_version', 'N/A')} / {architecture} / GUI={env.get('gui_session', 'N/A')} / App Store={env.get('app_store_present', 'N/A')}"),
        ("Accessibility API permission", str(env.get("accessibility_trusted", "N/A"))),
        ("Environment inspection", f"{os.environ.get('INSPECT_SECONDS', 'N/A')}s"),
        ("mas preparation", f"{os.environ.get('MAS_SECONDS', 'N/A')}s"),
        ("App Store download + install attempt", f"{os.environ.get('INSTALL_SECONDS', 'N/A')}s"),
        ("App Store GUI download/install", f"{os.environ.get('GUI_INSTALL_SECONDS', 'N/A')}s"),
        ("Native launch", f"{os.environ.get('LAUNCH_SECONDS', 'N/A')}s"),
        ("Accessibility interaction", f"{os.environ.get('UI_SECONDS', 'N/A')}s ({ui_result})"),
        ("Total workflow", f"{round(time.time() - int(os.environ.get('POC_START', str(int(time.time())))))}s"),
    ]
    with SUMMARY.open("a", encoding="utf-8") as handle:
        handle.write("## Astrum native macOS feasibility\n\n")
        handle.write(f"**Result:** {verdict}\n\n")
        handle.write("| Stage | Result |\n|---|---|\n")
        for label, value in rows:
            handle.write(f"| {label} | {value} |\n")
        app_result = install if isinstance(install, dict) else {}
        mas_result = app_result.get("mas_install", {}) if isinstance(app_result, dict) else {}
        store_result = app_result.get("app_store_gui_probe", {}) if isinstance(app_result, dict) else {}
        if isinstance(mas_result, dict):
            handle.write(f"\n**`mas install` exit:** {mas_result.get('returncode', 'not run')}  \n")
            if mas_result.get("output"):
                handle.write(f"**`mas install` output:** `{mas_result.get('output')}`  \n")
        if isinstance(store_result, dict):
            handle.write(f"**Mac App Store UI probe:** `{store_result.get('output', 'not run')}`\n")
        handle.write("\nNo Apple ID credentials, simulators, emulators, or app builds were used. Full command evidence is in the job log.\n")
    print(verdict)


if __name__ == "__main__":
    commands = {"inspect": inspect, "install-launch": install_launch, "ui-probe": ui_probe, "summary": summary}
    if len(sys.argv) != 2 or sys.argv[1] not in commands:
        raise SystemExit("Usage: test-astrum-macos.py {inspect|install-launch|ui-probe|summary}")
    commands[sys.argv[1]]()
