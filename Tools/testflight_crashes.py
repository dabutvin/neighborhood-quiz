#!/usr/bin/env python3
"""Fetch the crash reports testers sent from TestFlight, and say what killed the app.

A crash report answers in its first ten lines the question that is otherwise a
guess: whether the app was shot by the watchdog for hanging the main thread,
killed for taking too much memory, or brought down by its own code touching
something it should not have. Those look identical from the outside — the app
vanishes — and they have nothing in common as bugs. Reading the code and
reasoning about which one it probably is has a poor record next to reading the
first ten lines.

Needs the same App Store Connect API key the release workflows use:

    export APP_STORE_CONNECT_API_KEY_ID=...
    export APP_STORE_CONNECT_ISSUER_ID=...
    export APP_STORE_CONNECT_API_KEY_CONTENT="$(cat AuthKey_XXX.p8)"

    Tools/testflight_crashes.py --out-dir crashes

One thing it cannot do anything about: a TestFlight crash only reaches App Store
Connect if the tester sends it. iOS offers after a crash, and the offer is easy to
dismiss. If this comes back empty, that is the likeliest reason, and the fix is on
the phone rather than here — TestFlight app, the build, and turn on sharing.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from bootstrap_signing import AppStoreConnect, Failure  # noqa: E402

BUNDLE_ID = "com.nycneighborhoodsquiz.app"

# Where the feedback lives. Apple has moved this once already, and a wrong guess
# here is a 404 rather than anything dangerous, so ask in order and use whichever
# answers. Reporting which one worked saves the next person the same archaeology.
CRASH_PATHS = (
    "/v1/apps/{app}/betaFeedbackCrashSubmissions",
    "/v1/betaFeedbackCrashSubmissions",
)

# What the tester typed, which is a different endpoint from what the phone
# recorded. Worth having: "it died while I was panning" is a fact about the crash
# that no stack frame carries.
SCREENSHOT_PATHS = (
    "/v1/apps/{app}/betaFeedbackScreenshotSubmissions",
    "/v1/betaFeedbackScreenshotSubmissions",
)

EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")


def redact(text: str) -> str:
    """Testers are people. The report goes in the build log, which is not the place
    for somebody's email address; the artifact keeps the unredacted copy."""
    return EMAIL.sub("<email>", text)


@dataclass
class Report:
    """The few lines of a crash report that decide what kind of bug it is."""

    exception_type: str = ""
    signal: str = ""
    subtype: str = ""
    codes: str = ""
    termination: str = ""
    thread_name: str = ""
    frames: list[str] = field(default_factory=list)
    os_version: str = ""
    app_version: str = ""


def parse(raw: bytes) -> Report:
    text = raw.decode("utf-8", errors="replace").lstrip()
    if text.startswith("{"):
        try:
            return parse_ips(text)
        except (ValueError, KeyError, IndexError, TypeError):
            pass  # fall through and read it as text, which is better than nothing
    return parse_text(text)


def parse_ips(text: str) -> Report:
    """The .ips format: a one-line JSON header, then the report as JSON."""
    head, _, rest = text.partition("\n")
    header = json.loads(head)
    body = json.loads(rest) if rest.strip() else {}

    report = Report(
        os_version=str(header.get("os_version", "")),
        app_version=str(header.get("app_version", "")) or str(header.get("bundleID", "")),
    )

    exception = body.get("exception") or {}
    report.exception_type = str(exception.get("type", ""))
    report.signal = str(exception.get("signal", ""))
    report.subtype = str(exception.get("subtype", ""))
    report.codes = str(exception.get("codes", ""))

    termination = body.get("termination") or {}
    if termination:
        parts = [
            str(termination.get("namespace", "")),
            str(termination.get("indicator", "")),
            str(termination.get("code", "")),
        ]
        parts += [str(reason) for reason in termination.get("reasons", []) or []]
        report.termination = " ".join(part for part in parts if part)

    threads = body.get("threads") or []
    images = body.get("usedImages") or []
    faulting = body.get("faultingThread")
    if faulting is None:
        faulting = next(
            (i for i, thread in enumerate(threads) if thread.get("triggered")), None
        )
    if faulting is not None and 0 <= faulting < len(threads):
        thread = threads[faulting]
        report.thread_name = str(thread.get("name") or thread.get("queue") or f"thread {faulting}")
        for frame in (thread.get("frames") or [])[:30]:
            index = frame.get("imageIndex")
            image = ""
            if isinstance(index, int) and 0 <= index < len(images):
                image = str(images[index].get("name") or "")
            symbol = frame.get("symbol")
            if symbol:
                offset = frame.get("symbolLocation", 0)
                report.frames.append(f"{image:<28} {symbol} + {offset}".strip())
            else:
                report.frames.append(f"{image:<28} 0x{frame.get('imageOffset', 0):x}".strip())
    return report


def parse_text(text: str) -> Report:
    """The older plain-text .crash layout, kept because a report that will not parse
    is still worth showing rather than swallowing."""

    def field_value(name: str) -> str:
        match = re.search(rf"^{name}:\s*(.+)$", text, re.M)
        return match.group(1).strip() if match else ""

    report = Report(
        exception_type=field_value("Exception Type"),
        subtype=field_value("Exception Subtype"),
        codes=field_value("Exception Codes"),
        termination=field_value("Termination Reason"),
        os_version=field_value("OS Version"),
        app_version=field_value("Version"),
    )
    crashed = re.search(r"^(Thread \d+ Crashed.*?):?\n(.*?)(?:\n\s*\n|\Z)", text, re.M | re.S)
    if crashed:
        report.thread_name = crashed.group(1)
        report.frames = [
            line.strip() for line in crashed.group(2).splitlines()[:30] if line.strip()
        ]
    return report


def verdict(report: Report) -> tuple[str, str]:
    """What kind of death this was, and what it means for the map.

    The three that matter here look the same to anybody holding the phone and are
    completely different bugs, which is the whole reason for fetching these.
    """
    blob = " ".join(
        [report.exception_type, report.subtype, report.codes, report.termination, report.signal]
    ).upper()

    if "EXC_RESOURCE" in blob and "MEMORY" in blob:
        return (
            "MEMORY LIMIT",
            "The app was killed for holding too much memory, not for a mistake in "
            "a particular line. On a drawing this is nearly always a per-frame "
            "allocation that the frame loop cannot free as fast as it makes it.",
        )
    if "JETSAM" in blob or "PER-PROCESS-LIMIT" in blob or "VM-PAGESHORTAGE" in blob:
        return (
            "OUT OF MEMORY",
            "The system reclaimed the app under memory pressure. Same shape of bug "
            "as the memory limit: something is being made faster than it is dropped.",
        )
    if "0X8BADF00D" in blob or "WATCHDOG" in blob or "SCENE-UPDATE" in blob or "FRONTBOARD" in blob:
        return (
            "WATCHDOG — MAIN THREAD HUNG",
            "The app was shot for failing to answer in time, which means a frame "
            "took far too long rather than anything being wrong with the code's "
            "logic. This is the one that points at drawing cost, and the one the "
            "halo and per-rank changes were aimed at.",
        )
    if "EXC_BAD_ACCESS" in blob or "SIGSEGV" in blob or "SIGBUS" in blob:
        return (
            "BAD ACCESS — MEMORY TOUCHED WRONGLY",
            "The app reached for memory it did not own. In this map the standing "
            "suspect is the shared label-measurement cache being read while "
            "another thread grows it; the backtrace below says whether it is.",
        )
    if "EXC_BREAKPOINT" in blob or "SIGTRAP" in blob:
        return (
            "SWIFT RUNTIME TRAP",
            "Swift stopped the app on purpose: a force-unwrapped nil, an index off "
            "the end of an array, arithmetic that overflowed, or a precondition. "
            "The top frame below names the line.",
        )
    if "SIGABRT" in blob:
        return (
            "ABORT",
            "An uncaught exception or an explicit abort. The top frames name it.",
        )
    return (
        "UNCLASSIFIED",
        "None of the usual signatures matched. The full report is in the artifact.",
    )


def find_log_url(attributes: dict) -> str:
    """Apple has renamed this field before. Anything that is a URL and is called
    something to do with a log will do."""
    for key, value in attributes.items():
        if isinstance(value, str) and value.startswith("http") and "log" in key.lower():
            return value
        if isinstance(value, dict):
            nested = value.get("url")
            if isinstance(nested, str) and nested.startswith("http"):
                return nested
    for value in attributes.values():
        if isinstance(value, str) and value.startswith("https://"):
            return value
    return ""


def fetch_first(api: AppStoreConnect, paths, app_id: str, params: dict) -> tuple[list, str]:
    problems = []
    for template in paths:
        path = template.format(app=app_id)
        query = dict(params)
        if "{app}" not in template:
            query["filter[app]"] = app_id
        try:
            response = api.request("GET", path, params=query)
        except Failure as failure:
            problems.append(f"  {path}: {failure}")
            continue
        return response.get("data", []), path
    raise Failure("no feedback endpoint answered:\n" + "\n".join(problems))


def download(url: str) -> bytes:
    try:
        with urllib.request.urlopen(url, timeout=120) as response:
            return response.read()
    except (urllib.error.URLError, urllib.error.HTTPError) as error:
        raise Failure(f"could not download the crash log: {error}") from None


def render(index: int, submission: dict, report: Report | None, note: str) -> str:
    attributes = submission.get("attributes", {})
    lines = [f"### Crash {index}", ""]
    uptime = attributes.get("appUptimeInMilliseconds")
    facts = [
        ("When", attributes.get("createdDate", "")),
        ("Device", attributes.get("deviceModel", "")),
        ("iOS", attributes.get("osVersion", "") or (report.os_version if report else "")),
        ("Build", attributes.get("buildBundleId", "") or (report.app_version if report else "")),
        ("Up for", f"{uptime} ms" if uptime is not None else ""),
    ]
    lines += [f"- **{name}:** {value}" for name, value in facts if value not in ("", None)]

    comment = (attributes.get("comment") or "").strip()
    if comment:
        lines += ["", f"> {comment}"]

    if report is None:
        lines += ["", f"_{note}_"]
        return "\n".join(lines)

    label, meaning = verdict(report)
    lines += ["", f"**{label}**", "", meaning, ""]
    if report.exception_type:
        detail = " ".join(
            part for part in (report.exception_type, report.signal, report.subtype) if part
        )
        lines.append(f"- Exception: `{detail}`")
    if report.termination:
        lines.append(f"- Termination: `{report.termination}`")
    if report.frames:
        lines += ["", f"<details><summary>{report.thread_name or 'Crashed thread'}</summary>", "", "```"]
        lines += report.frames
        lines += ["```", "", "</details>"]
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--bundle-id", default=BUNDLE_ID)
    parser.add_argument("--limit", type=int, default=10, help="how many of the most recent to fetch")
    parser.add_argument("--out-dir", default="crashes", help="where to write the raw reports")
    parser.add_argument("--summary", help="write the readable report here as well as to stdout")
    parser.add_argument(
        "--report-file", help="read a saved .ips instead of calling the API; for testing the parser"
    )
    args = parser.parse_args(argv)

    if args.report_file:
        raw = Path(args.report_file).read_bytes()
        print(render(1, {}, parse(raw), ""))
        return 0

    import os

    key_id = os.environ.get("APP_STORE_CONNECT_API_KEY_ID", "")
    issuer_id = os.environ.get("APP_STORE_CONNECT_ISSUER_ID", "")
    key_pem = os.environ.get("APP_STORE_CONNECT_API_KEY_CONTENT", "")
    missing = [
        name
        for name, value in (
            ("APP_STORE_CONNECT_API_KEY_ID", key_id),
            ("APP_STORE_CONNECT_ISSUER_ID", issuer_id),
            ("APP_STORE_CONNECT_API_KEY_CONTENT", key_pem),
        )
        if not value
    ]
    if missing:
        raise Failure("missing credentials: " + ", ".join(missing))

    api = AppStoreConnect(key_id, issuer_id, key_pem)
    try:
        apps = api.request(
            "GET", "/v1/apps", params={"filter[bundleId]": args.bundle_id, "limit": "10"}
        ).get("data", [])
        if not apps:
            raise Failure(f"App Store Connect has no app with bundle id {args.bundle_id}")
        app_id = apps[0]["id"]

        params = {"limit": str(max(1, min(args.limit, 200))), "sort": "-createdDate"}
        submissions, endpoint = fetch_first(api, CRASH_PATHS, app_id, params)

        out_dir = Path(args.out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)

        pieces = [f"## TestFlight crashes\n\nFrom `{endpoint}` — {len(submissions)} report(s).\n"]
        if not submissions:
            pieces.append(
                "Nothing here. A TestFlight crash only arrives if the tester sends it, "
                "and the prompt is easy to dismiss — so an empty list means *not shared*, "
                "not *did not crash*. On the phone: TestFlight, this app, turn on sharing, "
                "then reproduce it and tap Share when iOS offers."
            )
        for index, submission in enumerate(submissions, start=1):
            attributes = submission.get("attributes", {})
            url = find_log_url(attributes)
            report, note = None, "No crash log attached to this submission."
            if url:
                try:
                    raw = download(url)
                    (out_dir / f"crash-{index:02d}.ips").write_bytes(raw)
                    report = parse(raw)
                except Failure as failure:
                    note = str(failure)
            (out_dir / f"crash-{index:02d}.json").write_text(json.dumps(submission, indent=2))
            pieces.append(render(index, submission, report, note))

        # The tester's own words, which the crash log does not carry.
        try:
            notes, _ = fetch_first(api, SCREENSHOT_PATHS, app_id, params)
        except Failure:
            notes = []
        written = [n for n in notes if (n.get("attributes", {}).get("comment") or "").strip()]
        if written:
            pieces.append("\n## What testers wrote\n")
            for note in written:
                attributes = note["attributes"]
                pieces.append(f"- _{attributes.get('createdDate', '?')}_ — {attributes['comment'].strip()}")

        summary = redact("\n\n".join(pieces))
        print(summary)
        if args.summary:
            Path(args.summary).write_text(summary)
    finally:
        api.close()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Failure as failure:
        print(f"error: {failure}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
