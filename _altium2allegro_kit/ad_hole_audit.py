#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ad_hole_audit.py -- 审计 Altium ASCII(.pcbdoc) 里"每个封装的钻孔/定位孔"是否真的存在。

背景:
  嘉立创(EasyEDA) -> AD -> Allegro 这条链路里, 连接器的机械定位孔
  (RJ45 塑料定位柱 / DC 座 / 端子) 经常在转换中丢失或退化成 0 孔径焊盘,
  导致转换后的 Allegro 封装"没有定位孔"。

本脚本直接读 AD 的 ASCII 源文件(权威源), 按封装聚合焊盘, 输出:
  - 每个封装的焊盘数 / 通孔焊盘数 / 孔径列表 / 焊盘外径
  - 不属于任何元件的"自由焊盘"(常被当作板级定位孔/安装孔使用)
  - 可疑封装: 名称/器件目录显示应为通孔, 却没有任何通孔焊盘

用法:
  python ad_hole_audit.py <xxx-ASCII.pcbdoc> [--csv out.csv] [--focus RJ45]
"""
import argparse
import csv
import os
import re
import sys
from collections import defaultdict

DEFAULT_ENC = 'gb18030'


def read_records(path, enc=DEFAULT_ENC):
    with open(path, 'rb') as fh:
        raw = fh.read()
    return raw.decode(enc, errors='replace').split('|RECORD=')


def kind_of(chunk):
    return chunk.split('|', 1)[0]


def prop(chunk, name):
    m = re.search(r'(?<![A-Za-z0-9])' + re.escape(name) + r'=([^|]*)', chunk)
    return m.group(1) if m else None


def to_mil(v):
    """Altium 坐标单位是 1/10000 mil。"""
    if v is None:
        return None
    try:
        t = v.strip().lower()
        for suf, mul in (('mil', 1.0), ('mm', 39.3701), ('in', 1000.0)):
            if t.endswith(suf):
                return float(t[:-len(suf)]) * mul
        return float(t) / 10000.0
    except ValueError:
        return None


def main(argv=None):
    ap = argparse.ArgumentParser(description='审计 AD ASCII 封装的定位孔/通孔')
    ap.add_argument('input')
    ap.add_argument('--csv', default='')
    ap.add_argument('--focus', default='', help='只详细打印名称含该串的封装')
    args = ap.parse_args(argv)

    chunks = read_records(args.input)
    print('文件: %s  (%.1f MB)' % (args.input, os.path.getsize(args.input) / 1e6))

    comps = {}          # ID -> dict
    for c in chunks[1:]:
        if kind_of(c) == 'Component':
            cid = prop(c, 'ID')
            comps[cid] = {
                'des': prop(c, 'SOURCEDESIGNATOR') or prop(c, 'DESIGNATOR') or '?',
                'pattern': (prop(c, 'PATTERN') or '').strip(),
                'layer': prop(c, 'LAYER') or '',
                'x': to_mil(prop(c, 'X')),
                'y': to_mil(prop(c, 'Y')),
                'pads': [],
            }

    free_pads = []
    for c in chunks[1:]:
        if kind_of(c) != 'Pad':
            continue
        hs = prop(c, 'HOLESIZE')
        hole = to_mil(hs) if hs else 0.0
        hole = hole or 0.0
        rec = {
            'name': prop(c, 'NAME') or '',
            'shape': prop(c, 'SHAPE') or '',
            'xs': to_mil(prop(c, 'XSIZE')),
            'ys': to_mil(prop(c, 'YSIZE')),
            'hole': hole,
            'layer': prop(c, 'LAYER') or '',
            'x': to_mil(prop(c, 'X')),
            'y': to_mil(prop(c, 'Y')),
            'plated': (prop(c, 'PLATED') or ''),
        }
        cid = prop(c, 'COMPONENT')
        if cid in comps:
            comps[cid]['pads'].append(rec)
        else:
            free_pads.append(rec)

    print('元件数: %d   自由焊盘(不属于任何元件)数: %d' % (len(comps), len(free_pads)))
    print()

    # ---- 自由焊盘 = 潜在板级定位孔/安装孔 ----
    print('== 不属于任何元件的自由焊盘 (板级定位孔/安装孔候选) ==')
    if not free_pads:
        print('  (无)  <-- 如果 AD 源里安装孔是"元件"或"过孔", 请看下面的封装表')
    else:
        by = defaultdict(int)
        for p in free_pads:
            by[(p['layer'], round(p['hole'], 1), round(p['xs'] or 0, 1), p['shape'])] += 1
        for (lay, h, xs, sh), n in sorted(by.items(), key=lambda kv: -kv[1]):
            print('  x%-3d  孔径=%-8s 外径=%-8s 形状=%-8s 层=%s' % (n, h, xs, sh, lay))
    print()

    # ---- 按封装聚合 ----
    agg = defaultdict(lambda: {'comps': [], 'pads': []})
    for cid, c in comps.items():
        agg[c['pattern']]['comps'].append(c)
        agg[c['pattern']]['pads'].extend(c['pads'])

    rows = []
    for pat, a in sorted(agg.items()):
        pads = a['pads']
        th = [p for p in pads if p['hole'] > 0.01]
        holes = sorted({round(p['hole'], 1) for p in th})
        sizes = sorted({(round(p['xs'] or 0, 1), round(p['ys'] or 0, 1)) for p in pads})
        des = ','.join(sorted(c['des'] for c in a['comps'])[:8])
        rows.append({
            'pattern': pat,
            'instances': len(a['comps']),
            'designators': des,
            'pads_total': len(pads),
            'pads_thru': len(th),
            'hole_sizes_mil': ' '.join('%g' % h for h in holes),
            'pad_sizes_mil': ' '.join('%gx%g' % s for s in sizes[:8]),
            'layers': ','.join(sorted({p['layer'] for p in pads if p['layer']})),
        })

    rows.sort(key=lambda r: (-r['pads_thru'], r['pattern']))
    hdr = ('pattern', 'instances', 'designators', 'pads_total', 'pads_thru',
           'hole_sizes_mil', 'pad_sizes_mil', 'layers')
    w = [max(len(hdr[i]), max((len(str(r[hdr[i]])) for r in rows), default=0)) for i in range(len(hdr))]
    w[0] = min(w[0], 52)
    print('== 按封装聚合 (按通孔焊盘数降序) ==')
    print('  '.join(hdr[i].ljust(w[i]) for i in range(len(hdr))))
    print('  '.join('-' * w[i] for i in range(len(hdr))))
    for r in rows:
        print('  '.join(str(r[hdr[i]])[:w[i]].ljust(w[i]) for i in range(len(hdr))))
    print()

    # ---- 可疑: 名字像连接器/座子却没有通孔 ----
    print('== 可疑: 名称暗示是插件(THT)却没有任何通孔焊盘 ==')
    key = re.compile(r'(conn|hdr|hx-pz|rj45|dc-in|dc-|sma|tf-|usb|terminal|pin|socket|key|sw-|led-th|th_)', re.I)
    suspect = [r for r in rows if r['pads_thru'] == 0 and key.search(r['pattern'] or '')]
    if not suspect:
        print('  (无)')
    for r in suspect:
        print('  %-52s 位号=%-18s 焊盘=%d  全部无孔' % (r['pattern'], r['designators'], r['pads_total']))
    print()

    # ---- 焦点封装明细 ----
    if args.focus:
        f = args.focus.lower()
        print('== 焦点封装明细 (PATTERN 含 "%s") ==' % args.focus)
        for pat, a in sorted(agg.items()):
            if f not in pat.lower():
                continue
            print('-- %s  实例: %s' % (pat, ','.join(c['des'] for c in a['comps'])))
            print('   焊盘角度=未解析; 焊盘列表(NAME/层/形状/外径/孔径/坐标):')
            for p in sorted(a['pads'], key=lambda q: (q['layer'], q['name'])):
                print('     %-6s %-10s %-8s %8s x %-8s  hole=%-7s  @(%s,%s)' % (
                    p['name'], p['layer'], p['shape'],
                    round(p['xs'] or 0, 1), round(p['ys'] or 0, 1),
                    round(p['hole'], 1), p['x'], p['y']))
            print()

    if args.csv:
        with open(args.csv, 'w', newline='', encoding='utf-8-sig') as fh:
            wr = csv.DictWriter(fh, fieldnames=list(hdr))
            wr.writeheader()
            wr.writerows(rows)
        print('CSV 已写出:', args.csv)


if __name__ == '__main__':
    main()
