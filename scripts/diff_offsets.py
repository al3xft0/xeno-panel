#!/usr/bin/env python3
import json, re, sys, pathlib

report = json.loads(pathlib.Path(sys.argv[1]).read_text())
hdr = pathlib.Path("src/Offsets.h").read_text()

declared = {m[0]: int(m[1], 16) for m in re.findall(r"constexpr uintptr_t (\w+)\s*=\s*(0x[0-9A-Fa-f]+);", hdr)}

bad = 0
for v in report.get("verdicts", []):
    label = v["label"]
    verdict = v["verdict"]
    want = declared.get(label)
    got = int(v["expected_offset"], 16)
    if want is not None and want != got:
        print(f"  {label}: report says {v['expected_offset']}, header says 0x{want:X}")
    if verdict == "OK":
        continue
    bad += 1
    extra = ""
    if verdict == "TYPE_MISMATCH":
        extra = f" -> at that offset: {v['found_name']} : {v['found_type']}"
    elif verdict == "PAST_END":
        extra = f" -> class ends at {v['max_instance_offset']}"
    print(f"FAIL {label} ({verdict}){extra}")

if report.get("fails", 0) == 0 and bad == 0:
    print(f"all {len(report['verdicts'])} offsets confirmed against {report['dump_date']}")
    sys.exit(0)
print(f"\n{bad} offset(s) need attention")
sys.exit(1)
