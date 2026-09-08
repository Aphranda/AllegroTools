#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
sch_xshift.py - shift Altium ASCII .SchDoc content by a small X offset (mils)
=============================================================================
Coordinate convention in Protel/SchDoc ASCII:
  LOCATION.X / X1 / X2 / CORNER.X ...  integer part, unit = 10 mil per integer
  <key>_FRAC                         ... fraction, 1e6 per integer (0.5 unit = 5mil)
  mil = X*10 + FRAC/100000
Purpose: compensate the uniform right-shift seen after Altium->OrCAD import
(e.g. all content needs to move left 5 mil => -dx 5).

Usage:
  python sch_xshift.py "dir_of_schdocs" --dx 5            # shift LEFT 5 mil, in place (+.bak)
  python sch_xshift.py "file.schdoc" --dx 5 --dry-run     # show what would change
  python sch_xshift.py "file.schdoc" --dx -5              # shift RIGHT 5 mil
  python sch_xshift.py "dir" --dx 5 --out out_dir         # write copies to out_dir (no in-place)
"""
import argparse
import glob
import os
import re
import sys
import shutil

X_KEYS = ('LOCATION.X', 'X1', 'X2', 'CORNER.X')
X_FRAC = ('LOCATION.X_FRAC', 'X1_FRAC', 'X2_FRAC', 'CORNER.X_FRAC')


def parse_token(tok):
    m = re.fullmatch(r'([A-Za-z0-9_.]+)=(-?[0-9]+)', tok)
    if not m:
        return None
    return m.group(1), int(m.group(2))


def coord_mil(xint, frac):
    # frac stored in 1e6 per unit; 1 unit = 10 mil -> frac/100000 mil
    return xint * 10.0 + frac / 100000.0


def encode_mil(mil):
    v = mil / 10.0  # value in integer units
    xi = int(v) if v >= 0 else -int(abs(v))
    frac = int(round((v - xi) * 1e6))
    if frac >= 1000000:
        xi += 1
        frac -= 1000000
    elif frac < 0:
        xi -= 1
        frac += 1000000
    return xi, frac


def shift_file(path, dx_mil, dy_mil, dry=False):
    with open(path, 'rb') as fh:
        raw = fh.read()
    text = raw.decode('gb18030', errors='replace')
    toks = text.split('|')
    changed = 0
    samples = []
    for i, tok in enumerate(toks):
        info = parse_token(tok)
        if not info:
            continue
        key, val = info
        if key in X_KEYS and dx_mil != 0:
            # find companion FRAC token (usually follows; search forward a few)
            frac = 0
            for j in range(i + 1, min(i + 6, len(toks))):
                fi = parse_token(toks[j])
                if fi and fi[0] == key + '_FRAC':
                    frac = fi[1]
                    break
            mil = coord_mil(val, frac)
            new_mil = mil - dx_mil  # subtract dx to move LEFT by dx
            ni, nf = encode_mil(new_mil)
            toks[i] = key + '=' + str(ni)
            # update companion frac token if present
            for j in range(i + 1, min(i + 6, len(toks))):
                fi = parse_token(toks[j])
                if fi and fi[0] == key + '_FRAC':
                    toks[j] = key + '_FRAC=' + str(nf)
                    break
            changed += 1
            if len(samples) < 3:
                samples.append('%s=%d(frac %d) -> %d(frac %d)  (%.2f -> %.2f mil)'
                               % (key, val, frac, ni, nf, mil, new_mil))
    if dry:
        return changed, samples
    out_text = '|'.join(toks)
    bak = path + '.bak'
    if not os.path.exists(bak):
        shutil.copy2(path, bak)
    with open(path, 'wb') as fh:
        fh.write(out_text.encode('gb18030'))
    return changed, samples


def main(argv=None):
    ap = argparse.ArgumentParser(description='shift SchDoc X coordinates by mils')
    ap.add_argument('target', help='a .schdoc file or a directory containing .schdoc')
    ap.add_argument('--dx', type=float, default=5.0,
                    help='shift amount in mils (positive = content moves LEFT)')
    ap.add_argument('--dy', type=float, default=0.0)
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--out', default='', help='write shifted copies here (no in-place)')
    a = ap.parse_args(argv)
    files = []
    if os.path.isdir(a.target):
        files = sorted(glob.glob(os.path.join(a.target, '*.schdoc')))
    elif os.path.isfile(a.target):
        files = [a.target]
    if not files:
        print('no .schdoc files found')
        return 1
    total = 0
    for f in files:
        changed, samples = shift_file(f, a.dx, a.dy, dry=a.dry_run or bool(a.out))
        total += changed
        print('%-60s changed-coords=%d' % (os.path.basename(f), changed))
        for s in samples:
            print('    e.g. ' + s)
        if a.out and os.path.isdir(a.out):
            shutil.copy2(f, os.path.join(a.out, os.path.basename(f)))
    print('TOTAL shifted X coordinates: %d (dx=%.2f mil left)' % (total, a.dx))
    if a.dry_run:
        print('DRY-RUN only - no files modified (in-place run does .bak backup)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
