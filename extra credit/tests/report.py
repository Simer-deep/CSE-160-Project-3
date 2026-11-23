from __future__ import print_function

import csv
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(ROOT, "results")


def read_json(name):
    with open(os.path.join(RESULTS, name + ".json"), "r") as source:
        return json.load(source)


def fairness(rates):
    sum_rates = sum(rates)
    squared = sum(rate * rate for rate in rates)
    if not squared:
        return 0
    return (sum_rates * sum_rates) / (len(rates) * squared)


def windows(log):
    events = {3: [], 4: []}
    with open(os.path.join(RESULTS, log), "r") as source:
        for line in source:
            match = re.search(
                r"CC node=(3|4) port=\d+ cwnd=(\d+) "
                r"ssthresh=(\d+) reason=(\w+)", line)
            if match:
                events[int(match.group(1))].append(
                    (int(match.group(2)), match.group(4)))
    return events


def make_svg(events):
    width, height = 830, 360
    left, top = 70, 30
    plot_width, plot_height = 710, 255
    count = max(len(value) for value in events.values())
    count = max(count - 1, 1)

    colors = {3: "#1464b4", 4: "#d35a24"}
    parts = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
        'viewBox="0 0 %d %d">' % (width, height, width, height),
        '<rect width="%d" height="%d" fill="white"/>' % (width, height),
        '<text x="70" y="20" font-family="sans-serif" font-size="16">'
        'Congestion window (bytes) by control event</text>'
    ]
    for value in (0, 12, 24, 36, 48):
        y = top + plot_height - value * plot_height / 48.0
        parts.append(
            '<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" '
            'stroke="#e0e0e0"/>' % (left, y, left + plot_width, y))
        parts.append(
            '<text x="32" y="%.1f" font-family="sans-serif" '
            'font-size="12">%d</text>' % (y + 4, value))

    for node in (3, 4):
        values = events[node]
        if not values:
            continue
        points = []
        for idx, (cwnd, reason) in enumerate(values):
            x = left + idx * plot_width / float(count)
            y = top + plot_height - cwnd * plot_height / 48.0
            points.append("%.1f,%.1f" % (x, y))
        if len(points) == 1:
            points.append(points[0])
        parts.append('<polyline fill="none" stroke="%s" stroke-width="2" '
                     'points="%s"/>' % (colors[node], " ".join(points)))
        for idx, (cwnd, reason) in enumerate(values):
            if reason == "timeout":
                x = left + idx * plot_width / float(count)
                y = top + plot_height - cwnd * plot_height / 48.0
                parts.append('<circle cx="%.1f" cy="%.1f" r="5" '
                             'fill="%s"/>' % (x, y, colors[node]))

    parts += [
        '<text x="330" y="320" font-family="sans-serif" font-size="13">'
        'ACK / timeout event index</text>',
        '<text x="70" y="343" font-family="sans-serif" font-size="12" '
        'fill="#1464b4">Node 3</text>',
        '<text x="150" y="343" font-family="sans-serif" font-size="12" '
        'fill="#d35a24">Node 4</text>',
        '<text x="238" y="343" font-family="sans-serif" font-size="12">'
        'Circles mark timeout reductions; baseline window = 48 bytes</text>',
        '</svg>'
    ]
    with open(os.path.join(RESULTS, "cwnd.svg"), "w") as output:
        output.write("\n".join(parts))


def main():
    fixed = read_json("fixed")
    congestion = read_json("congestion")
    rows = []
    for report in (fixed, congestion):
        flows = report["flows"]
        rates = [f["throughput_bytes_per_second"] for f in flows]
        for flow in flows:
            rows.append([
                report["mode"], flow["node"], flow["bytes"],
                flow["completion_seconds"],
                flow["throughput_bytes_per_second"],
                flow["data_retransmissions"], report["dropped_packets"],
                round(fairness(rates), 4), flow["passed"]
            ])

    csv_file = os.path.join(RESULTS, "comparison.csv")
    with open(csv_file, "wb") as output:
        writer = csv.writer(output)
        writer.writerow([
            "mode", "client_node", "bytes", "completion_s",
            "throughput_Bps", "data_retransmissions", "dropped_packets",
            "jain_fairness", "passed"
        ])
        writer.writerows(rows)

    samples = windows("congestion.log")
    make_svg(samples)

    summary = [
        "# Congestion-control comparison",
        "",
        "Identical seed, 4-node line, two concurrent 1025-byte flows,",
        "shared relay/bottleneck 2->1, and one deliberate DATA loss.",
        "Completion time is measured in 5-second simulation steps.",
        "Jain fairness uses per-flow completed-byte throughput.",
        "",
        "| Mode | Mean throughput (B/s) | Retransmissions | Fairness |",
        "| --- | ---: | ---: | ---: |"
    ]
    for report in (fixed, congestion):
        rates = [f["throughput_bytes_per_second"] for f in report["flows"]]
        retries = sum(f["data_retransmissions"] for f in report["flows"])
        summary.append("| %s | %.2f | %d | %.4f |" % (
            report["mode"], sum(rates) / len(rates),
            retries, fairness(rates)))
    summary += [
        "",
        "Congestion signal: retransmission timeout. Slow start begins at",
        "one 12-byte segment, then AIMD increases the window on new ACKs",
        "and halves the threshold on timeout. The active window remains",
        "bounded by the original 48-byte send cap and peer window.",
        "",
        "Window graph: cwnd.svg. Event index is not simulated time.",
        "Wireless loss can trigger unnecessary window reduction, so",
        "greater throughput is not guaranteed in congestion mode."
    ]
    with open(os.path.join(RESULTS, "comparison.md"), "w") as output:
        output.write("\n".join(summary) + "\n")

    print("Summary: extra credit/results/comparison.md")
    print("Data: extra credit/results/comparison.csv")
    print("Window graph: extra credit/results/cwnd.svg")


if __name__ == "__main__":
    main()
