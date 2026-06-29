#!/usr/bin/env python3

# PPA overview report generator for AES PNR results.
# Scans post-layout report directories, extracts setup/hold timing, power, area, and kGE metrics, then writes a consolidated PPA summary report.

import os
import re
import sys
from pathlib import Path

NUM_RE = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"

POWER_REPORTS = [
    "power_tvla_dynamic.rpt",
    "power_tvla_static.rpt",
    "power_psim.rpt",
]

DEFAULT_NAND2_AREA = 2.54144

def read_text(path):
    try:
        return Path(path).read_text(errors="ignore")
    except FileNotFoundError:
        return None

def to_float(x):
    try:
        return float(x)
    except Exception:
        return None

def fmt4(x):
    return "NA" if x is None else f"{x:.4f}"

def fmt2(x):
    return "NA" if x is None else f"{x:.2f}"

def fmt_pct(x):
    return "NA" if x is None else f"{x:.1f}"

def percent(part, total):
    if part is None or total is None or total == 0:
        return None
    return part / total * 100.0

def select_power_unit(total_power_w):

    if total_power_w is None:
        return "uW", 1e6

    value = abs(total_power_w)

    if value >= 1:
        return "W", 1.0
    elif value >= 1e-3:
        return "mW", 1e3
    elif value >= 1e-6:
        return "uW", 1e6
    elif value >= 1e-9:
        return "nW", 1e9
    else:
        return "pW", 1e12

def fmt_power(value_w, scale):
    if value_w is None:
        return "NA"
    return f"{value_w * scale:.4f}"

def parse_period_from_design_name(design_name):

    m = re.search(r"_([0-9]+)p([0-9]+)ns$", design_name)
    if m:
        return float(f"{m.group(1)}.{m.group(2)}")

    m = re.search(r"_([0-9]+(?:\.[0-9]+)?)ns$", design_name)
    if m:
        return float(m.group(1))

    return None

def parse_qor_timing(text, timing_type, preferred_group="clk"):
    if text is None:
        return None

    pattern = re.compile(
        r"Timing Path Group\s+'([^']+)'\s+\(([^)]+)\)\s*"
        r"\n\s*-+\s*\n(.*?)\n\s*-+",
        re.S,
    )

    groups = []

    for group, typ, block in pattern.findall(text):
        if typ.strip() != timing_type:
            continue

        data = {
            "group": group.strip(),
            "levels": None,
            "critical_path_length": None,
            "slack": None,
            "tns": None,
            "violating_paths": None,
        }

        fields = {
            "Levels of Logic": "levels",
            "Critical Path Length": "critical_path_length",
            "Critical Path Slack": "slack",
            "Total Negative Slack": "tns",
            "No. of Violating Paths": "violating_paths",
        }

        for label, key in fields.items():
            m = re.search(rf"{re.escape(label)}:\s*({NUM_RE})", block)
            if m:
                data[key] = to_float(m.group(1))

        groups.append(data)

    for item in groups:
        if item["group"] == preferred_group:
            return item

    valid = [x for x in groups if x["slack"] is not None]
    if valid:
        return sorted(valid, key=lambda x: x["slack"])[0]

    return None

def parse_qor_area(text):
    area = {
        "net_interconnect_area": None,
        "total_cell_area": None,
        "design_area": None,
    }

    if text is None:
        return area

    fields = {
        "Net Interconnect area": "net_interconnect_area",
        "Total cell area": "total_cell_area",
        "Design Area": "design_area",
    }

    for label, key in fields.items():
        m = re.search(rf"{re.escape(label)}:\s*({NUM_RE})", text)
        if m:
            area[key] = to_float(m.group(1))

    return area

def parse_power_report(path):
    text = read_text(path)
    if text is None:
        return None

    data = {
        "path": str(path),
        "total_power": None,
        "internal_power": None,
        "switching_power": None,
        "leakage_power": None,
        "peak_power": None,
        "x_transition_power": None,
        "glitching_power": None,
    }

    patterns = {
        "total_power": r"Total Power\s*=\s*(" + NUM_RE + ")",
        "internal_power": r"Cell Internal Power\s*=\s*(" + NUM_RE + ")",
        "switching_power": r"Net Switching Power\s*=\s*(" + NUM_RE + ")",
        "leakage_power": r"Cell Leakage Power\s*=\s*(" + NUM_RE + ")",
        "peak_power": r"Peak Power\s*=\s*(" + NUM_RE + ")",
        "x_transition_power": r"X Transition Power\s*=\s*(" + NUM_RE + ")",
        "glitching_power": r"Glitching Power\s*=\s*(" + NUM_RE + ")",
    }

    for key, pat in patterns.items():
        m = re.search(pat, text)
        if m:
            data[key] = to_float(m.group(1))

    return data

def select_max_power_report(reports_sta_dir):
    candidates = []

    for rpt in POWER_REPORTS:
        path = reports_sta_dir / rpt
        data = parse_power_report(path)
        if data is not None and data["total_power"] is not None:
            candidates.append(data)

    if not candidates:
        return None

    return max(candidates, key=lambda x: x["total_power"])

def area_mismatch_warning(setup_area, hold_area, tol=1e-3):
    keys = [
        "design_area",
        "total_cell_area",
        "net_interconnect_area",
    ]

    warnings = []

    for key in keys:
        setup_val = setup_area.get(key)
        hold_val = hold_area.get(key)

        if setup_val is None or hold_val is None:
            continue

        if abs(setup_val - hold_val) > tol:
            warnings.append(
                f"{key}: func_slow_max={setup_val}, func_fast_min={hold_val}"
            )

    return warnings

def write_design_report(lines, design_dir, nand2_area):
    design_name = design_dir.name
    reports_sta = design_dir / "reports_sta"

    setup_qor_path = reports_sta / "func_slow_max" / "report_qor.rpt"
    hold_qor_path = reports_sta / "func_fast_min" / "report_qor.rpt"

    setup_text = read_text(setup_qor_path)
    hold_text = read_text(hold_qor_path)

    setup = parse_qor_timing(setup_text, "max_delay/setup", "clk")
    hold = parse_qor_timing(hold_text, "min_delay/hold", "clk")

    setup_area = parse_qor_area(setup_text)
    hold_area = parse_qor_area(hold_text)

    area = setup_area
    if area["design_area"] is None:
        area = hold_area

    period_ns = parse_period_from_design_name(design_name)

    if period_ns is None:
        period_ns = to_float(os.environ.get("CLK_PERIOD"))

    setup_slack = setup["slack"] if setup else None

    max_freq_mhz = None
    if period_ns is not None and setup_slack is not None:
        critical_delay_ns = period_ns - setup_slack
        if critical_delay_ns > 0:
            max_freq_mhz = 1000.0 / critical_delay_ns

    power = select_max_power_report(reports_sta)

    design_area = area["design_area"]
    total_cell_area = area["total_cell_area"]
    net_interconnect_area = area["net_interconnect_area"]

    kge = None
    if design_area is not None and nand2_area > 0:
        kge = design_area / nand2_area / 1000.0

    cell_pct = percent(total_cell_area, design_area)
    net_pct = percent(net_interconnect_area, design_area)

    lines.append(f"Design: {design_name}")
    lines.append("")

    lines.append(f"Performance Setup: {setup_qor_path}")
    lines.append(f"  Timing Path Group        : {setup['group'] if setup else 'NA'}")
    lines.append(f"  Critical Path Clk Period : {fmt4(period_ns)} ns")
    lines.append(f"  Critical Path Slack      : {fmt4(setup_slack)} ns")
    lines.append(f"  Maximum Frequency        : {fmt2(max_freq_mhz)} MHz")
    lines.append("")

    hold_slack = hold["slack"] if hold else None

    lines.append(f"Performance Hold: {hold_qor_path}")
    lines.append(f"  Timing Path Group        : {hold['group'] if hold else 'NA'}")
    lines.append(f"  Critical Path Slack      : {fmt4(hold_slack)} ns")
    lines.append("")

    if power:
        total_w = power["total_power"]
        internal_w = power["internal_power"]
        switching_w = power["switching_power"]
        leakage_w = power["leakage_power"]

        dynamic_w = None
        if internal_w is not None and switching_w is not None:
            dynamic_w = internal_w + switching_w

        dyn_pct = percent(dynamic_w, total_w)
        leak_pct = percent(leakage_w, total_w)

        power_unit, power_scale = select_power_unit(total_w)

        lines.append(f"Power: {power['path']}")
        lines.append(
            f"  Total power              : {fmt_power(total_w, power_scale)} {power_unit}"
        )
        lines.append(
            f"  Dynamic power            : {fmt_power(dynamic_w, power_scale)} {power_unit} "
            f"({fmt_pct(dyn_pct)}%)"
        )
        lines.append(
            f"    Internal power         : {fmt_power(internal_w, power_scale)} {power_unit}"
        )
        lines.append(
            f"    Switching power        : {fmt_power(switching_w, power_scale)} {power_unit}"
        )
        lines.append(
            f"  Static power             : {fmt_power(leakage_w, power_scale)} {power_unit} "
            f"({fmt_pct(leak_pct)}%)"
        )
        lines.append(
            f"  Peak Power               : {fmt_power(power['peak_power'], power_scale)} {power_unit}"
        )
        lines.append(
            f"  X Transition Power       : {fmt_power(power['x_transition_power'], power_scale)} {power_unit}"
        )
        lines.append(
            f"  Glitching Power          : {fmt_power(power['glitching_power'], power_scale)} {power_unit}"
        )
    else:
        lines.append("Power: NA")
        lines.append("  Total power              : NA")
        lines.append("  Dynamic power            : NA")
        lines.append("    Internal power         : NA")
        lines.append("    Switching power        : NA")
        lines.append("  Static power             : NA")
        lines.append("  Peak Power               : NA")
        lines.append("  X Transition Power       : NA")
        lines.append("  Glitching Power          : NA")

    lines.append("")

    area_path = setup_qor_path if setup_text is not None else hold_qor_path

    lines.append(f"Area: {area_path}")
    lines.append(f"  Design Area              : {fmt4(design_area)} ({fmt4(kge)} kGE)")
    lines.append(
        f"    Total Cell Area        : {fmt4(total_cell_area)} "
        f"({fmt_pct(cell_pct)}%)"
    )
    lines.append(
        f"    Net Interconnect Area  : {fmt4(net_interconnect_area)} "
        f"({fmt_pct(net_pct)}%)"
    )

    return area_mismatch_warning(setup_area, hold_area)

def main():
    workarea = os.environ.get("WORKAREA")
    if not workarea:
        print("ERROR: WORKAREA is not set.", file=sys.stderr)
        sys.exit(1)

    nand2_area = to_float(os.environ.get("NAND2_AREA", str(DEFAULT_NAND2_AREA)))
    if nand2_area is None or nand2_area <= 0:
        print("ERROR: NAND2_AREA must be a positive number.", file=sys.stderr)
        sys.exit(1)

    pnr_dir = Path(workarea).resolve() / "pnr"
    results_dir = pnr_dir / "results"
    output_path = pnr_dir / "ppa_overview.rpt"

    if not results_dir.is_dir():
        print(f"ERROR: Cannot find results directory: {results_dir}", file=sys.stderr)
        sys.exit(1)

    design_dirs = sorted(
        d for d in results_dir.iterdir()
        if d.is_dir() and (d / "reports_sta").is_dir()
    )

    if not design_dirs:
        print(f"ERROR: No design reports found under {results_dir}", file=sys.stderr)
        sys.exit(1)

    lines = []
    all_warnings = []

    for i, design_dir in enumerate(design_dirs):
        if i > 0:
            lines.append("")
            lines.append("*****************************************************************")
            lines.append("")

        warnings = write_design_report(lines, design_dir, nand2_area)

        for warning in warnings:
            all_warnings.append(f"{design_dir.name}: {warning}")

    output_path.write_text("\n".join(lines) + "\n")

    print(f"Wrote {output_path}")

    if all_warnings:
        print("", file=sys.stderr)
        print("Area mismatch warnings:", file=sys.stderr)
        for warning in all_warnings:
            print(f"  WARNING: {warning}", file=sys.stderr)

if __name__ == "__main__":
    main()

