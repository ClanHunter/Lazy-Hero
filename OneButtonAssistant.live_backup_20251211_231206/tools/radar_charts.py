#!/usr/bin/env python3
"""
radar_charts.py

Generate radar charts (PNG) per spec from `WAR_WITHIN_class_matrix.csv`.

Usage (PowerShell):
  python tools\radar_charts.py --csv "OneButtonAssistant\WAR_WITHIN_class_matrix.csv" --outdir charts

Produces one PNG per spec (filename: <SpecKey>.png) in the output directory.
"""
import os
import argparse
import math
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

AXES = ['Mobility','Control','BurstVsSustain','Complexity']

# normalization helpers: convert qualitative values to numeric scales
BURST_MAP = {
    'Burst': 8,
    'Sustain': 2,
    'Mixed': 5,
    'Sustain/Control': 3,
    'Burst/Sustain': 6,
    'Burst via damage':6,
}
MOBILITY_MAP = {
    'Very High': 10, 'High': 8, 'Medium-High':7, 'Medium':5, 'Low-Med':4, 'Low':2
}
CONTROL_MAP = {
    'High': 8, 'Medium':5, 'Low':2
}
COMPLEXITY_MAP = {
    'High':8, 'Medium-High':7, 'Medium':5, 'Low-Med':4, 'Low':2, 'Low':1
}

def map_value(val, mapping, default=5):
    if val is None: return default
    v = str(val).strip()
    return mapping.get(v, default)


def make_radar(values, labels, title, outpath):
    N = len(values)
    angles = np.linspace(0, 2 * np.pi, N, endpoint=False).tolist()
    values = list(values)
    values += values[:1]
    angles += angles[:1]

    fig, ax = plt.subplots(figsize=(4,4), subplot_kw=dict(polar=True))
    ax.plot(angles, values, linewidth=2)
    ax.fill(angles, values, alpha=0.25)
    ax.set_thetagrids(np.degrees(angles[:-1]), labels)
    ax.set_ylim(0, 10)
    ax.set_title(title, y=1.08)
    plt.tight_layout()
    fig.savefig(outpath)
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--csv', required=True)
    parser.add_argument('--outdir', default='charts')
    args = parser.parse_args()

    if not os.path.exists(args.csv):
        print('CSV not found:', args.csv)
        return
    if not os.path.exists(args.outdir):
        os.makedirs(args.outdir)

    df = pd.read_csv(args.csv, dtype=str)
    for _, row in df.iterrows():
        spec_key = row.get('SpecKey') or row.get('Spec') or 'spec'
        mobility = map_value(row.get('Mobility'), MOBILITY_MAP)
        control = map_value(row.get('Control'), CONTROL_MAP)
        burst = BURST_MAP.get(str(row.get('BurstVsSustain')).strip(), None)
        if burst is None:
            # try to derive: treat 'Sustain' -> low, 'Burst' -> high, 'Mixed' mid
            bv = str(row.get('BurstVsSustain') or '').lower()
            if 'burst' in bv and 'sustain' in bv:
                burst = 5
            elif 'burst' in bv:
                burst = 8
            elif 'sustain' in bv:
                burst = 2
            else:
                burst = 5
        complexity = map_value(row.get('Complexity'), COMPLEXITY_MAP)

        values = [mobility, control, burst, complexity]
        labels = ['Mobility','Control','Burst','Complexity']
        title = f"{row.get('Class','')}: {row.get('Spec','')}"
        outpath = os.path.join(args.outdir, f"{spec_key}.png")
        make_radar(values, labels, title, outpath)
        print('Wrote', outpath)

if __name__ == '__main__':
    main()
