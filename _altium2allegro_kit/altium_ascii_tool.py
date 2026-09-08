#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
altium_ascii_tool.py - Altium ASCII(.pcbdoc) 检查/修复/变体生成 一体化工具
============================================================================
背景(实测根因):
  Allegro 24.1 S008 的 altium2pcb 转换器在 "text blocks" 阶段会对 nil 调用
  upperCase 崩溃, 触发条件是 ASCII 中存在 PATTERN(封装名)为空的 Component
  (本工程为测试点 T1/T2/T3/T4)。默认策略: 自动识别这些元件, 分配 PATTERN 并
  按元件 ID 补一条 ROUND 单焊盘(测试点), 使其作为正常元件导入; 也可改删/填名。

子命令:
  check   <输入.pcbdoc>
      报告记录统计 + 非 ASCII + 空封装元件清单(核心体检)
  fix     <输入.pcbdoc> -o 输出.pcbdoc [选项]
      生成可直接导入 Allegro 的文件:
        --empty-pattern-action pad|remove|fill|none   (默认 pad)
             pad    : 填 PATTERN + 补圆形焊盘(测试点, 推荐, 保留元件)
             remove : 删除空封装元件
             fill   : 只填 PATTERN 名(无焊盘)
             none   : 不动(仅用于对照复现)
        --tp-pattern NAME   测试点封装名(默认 TP1PAD)
        --tp-pad-dia MIL    圆形焊盘直径 mil(默认 40, 约1.0mm)
        --remove-designators T1,T2  额外按位号删除元件
        --omega-replace CH  顺带把非 ASCII 文本字符替换为该字符(如 R)
  variant <输入.pcbdoc> -o 输出.pcbdoc --kinds Board,Component[,Net,...]
      保留指定类别记录(用于二分定位/最小复现)
"""
import argparse
import os
import random
import re
import sys

DEFAULT_ENC = 'gb18030'  # GBK 超集, 兼容中文 Windows 导出的 Altium ASCII, 无损往返

# ---------- 基础工具 ----------

def read_records(path, enc=DEFAULT_ENC):
    with open(path, 'rb') as fh:
        raw = fh.read()
    text = raw.decode(enc)
    chunks = text.split('|RECORD=')
    return chunks  # [0]=文件头, 其余 'Kind|...'

def kind_of(chunk):
    return chunk.split('|', 1)[0]

def prop(chunk, name):
    m = re.search(r'(?<![A-Za-z0-9])' + re.escape(name) + r'=([^|]*)', chunk)
    return m.group(1) if m else None

def set_prop(chunk, name, value):
    """把记录里第一个 NAME= 的值整体替换为新值, 返回新记录。"""
    pat = re.compile(r'(?<![A-Za-z0-9])' + re.escape(name) + r'=[^|]*')
    return pat.sub(name + '=' + str(value), chunk, count=1)

def write_records(chunks, out, enc=DEFAULT_ENC):
    with open(out, 'wb') as fh:
        fh.write('|RECORD='.join(chunks).encode(enc))

def kind_counts(chunks):
    c = {}
    for x in chunks[1:]:
        k = kind_of(x)
        c[k] = c.get(k, 0) + 1
    return c

def non_ascii_bytes(path):
    with open(path, 'rb') as fh:
        b = fh.read()
    return sum(1 for x in b if x >= 0x80)

def rand_id(n=8):
    return ''.join(random.choice('ABCDEFGHIJKLMNOPQRSTUVWXYZ') for _ in range(n))

# ---------- check ----------

def cmd_check(args):
    chunks = read_records(args.input)
    print('== 记录统计 ==')
    for k, n in sorted(kind_counts(chunks).items(), key=lambda kv: -kv[1]):
        print('%6d  %s' % (n, k))
    print('文件大小: %d bytes, 非 ASCII 字节: %d' % (os.path.getsize(args.input),
                                                non_ascii_bytes(args.input)))
    print()
    print('== 空封装(PATTERN=为空)元件体检 (Allegro 转换崩溃根因) ==')
    hits = empty_components(chunks)
    if not hits:
        print('  (无) - 该文件应可直接导入')
    else:
        for (d, cid, x, y, layer, nameon) in hits:
            print('  designator=%-6s id=%-5s X=%s Y=%s LAYER=%s NAMEON=%s' % (d, cid, x, y, layer, nameon))
    print()

def empty_components(chunks):
    hits = []
    for c in chunks[1:]:
        if kind_of(c) == 'Component':
            pat = prop(c, 'PATTERN')
            if pat is None or pat.strip() == '':
                hits.append((prop(c, 'SOURCEDESIGNATOR'), prop(c, 'ID'),
                             prop(c, 'X'), prop(c, 'Y'), prop(c, 'LAYER'), prop(c, 'NAMEON')))
    return hits

# ---------- fix ----------

def _build_pad(template, comp_id, x, y, dia_mil, net):
    """克隆一个现成 ROUND SMD 焊盘, 替换成单焊盘测试点参数。"""
    p = template
    p = set_prop(p, 'COMPONENT', comp_id)
    p = set_prop(p, 'NAME', '1')
    p = set_prop(p, 'NET', net)
    p = set_prop(p, 'X', x)
    p = set_prop(p, 'Y', y)
    p = set_prop(p, 'XSIZE', dia_mil)
    p = set_prop(p, 'YSIZE', dia_mil)
    p = set_prop(p, 'SHAPE', 'ROUND')
    p = set_prop(p, 'HOLESIZE', '0mil')
    p = set_prop(p, 'UNIQUEID', rand_id())
    return p

def cmd_fix(args):
    chunks = read_records(args.input)
    kept = [chunks[0]]
    removed = []
    filled = []
    extra_pads = []
    # 找一个 ROUND + 0mil 孔 + TOP 的现成焊盘作模板
    template = None
    for c in chunks[1:]:
        if kind_of(c) == 'Pad':
            if (prop(c, 'SHAPE') == 'ROUND' and prop(c, 'HOLESIZE') == '0mil'
                    and prop(c, 'LAYER') in ('TOP', 'BOTTOM', 'MULTILAYER')):
                template = c
                break
    for c in chunks[1:]:
        if kind_of(c) != 'Component':
            kept.append(c)
            continue
        d = prop(c, 'SOURCEDESIGNATOR') or ''
        pat = prop(c, 'PATTERN')
        empty = (pat is None or pat.strip() == '')
        if d in args.remove_designators:
            removed.append(d)
            continue
        if empty and args.action == 'remove':
            removed.append(d)
            continue
        if empty:
            if args.action == 'fill':
                c = set_prop(c, 'PATTERN', args.tp_pattern)
                filled.append(d)
            elif args.action == 'pad':
                c = set_prop(c, 'PATTERN', args.tp_pattern)
                filled.append(d + '@' + (prop(c, 'X') or '') + ',' + (prop(c, 'Y') or ''))
                if template:
                    extra_pads.append(_build_pad(template, prop(c, 'ID'),
                                                 prop(c, 'X'), prop(c, 'Y'),
                                                 args.tp_pad_dia, 0))
        kept.append(c)
    # 追加测试点焊盘(放在全部记录之后亦可, 转换器按 COMPONENT=ID 关联)
    kept.extend(extra_pads)
    write_records(kept, args.output)
    print('写出:', args.output, os.path.getsize(args.output), 'bytes')
    if removed:
        print('已删除元件:', ', '.join(removed))
    if filled:
        print('已分配封装 %s 的元件: %s' % (args.tp_pattern, ', '.join(filled)))
    if extra_pads:
        print('已补圆形焊盘(直径 %s) %d 个' % (args.tp_pad_dia, len(extra_pads)))
    if not removed and not filled and not extra_pads:
        print('未做任何修改(文件本身没有空封装元件)')

# ---------- variant ----------

def cmd_variant(args):
    chunks = read_records(args.input)
    kinds = set(k.strip() for k in args.kinds.split(',') if k.strip())
    kept = [chunks[0]]
    for c in chunks[1:]:
        if kind_of(c) in kinds:
            kept.append(c)
    write_records(kept, args.output)
    print('变体写出:', args.output, os.path.getsize(args.output), 'bytes')
    print('包含:', {k: n for k, n in kind_counts(kept).items()})

# ---------- main ----------

def main(argv=None):
    ap = argparse.ArgumentParser(description='Altium ASCII pcbdoc 检查/修复工具')
    sub = ap.add_subparsers(dest='cmd', required=True)

    p = sub.add_parser('check', help='体检: 记录统计 + 空封装元件')
    p.add_argument('input')
    p.set_defaults(fn=cmd_check)

    p = sub.add_parser('fix', help='生成可导入文件(默认给测试点补焊盘)')
    p.add_argument('input')
    p.add_argument('-o', '--output', required=True)
    p.add_argument('--empty-pattern-action', dest='action',
                   choices=['pad', 'remove', 'fill', 'none'], default='pad',
                   help='pad=补封装+圆焊盘(默认) remove=删除 fill=只填名 none=不动')
    p.add_argument('--tp-pattern', default='TP1PAD', help='测试点封装名')
    p.add_argument('--tp-pad-dia', default='40mil', help='测试点圆焊盘直径, 如 40mil/1.0mm')
    p.add_argument('--remove-designators', default='', metavar='T1,T2')
    p.add_argument('--omega-replace', metavar='CH', default='',
                   help='顺带把非 ASCII 文本字符替换为该字符(如 R)')
    p.set_defaults(fn=cmd_fix)

    p = sub.add_parser('variant', help='按记录类别生成二分变体')
    p.add_argument('input')
    p.add_argument('-o', '--output', required=True)
    p.add_argument('--kinds', required=True, help='保留的类别, 如 Board,Component')
    p.set_defaults(fn=cmd_variant)

    args = ap.parse_args(argv)
    if args.cmd == 'fix':
        args.remove_designators = {x.strip() for x in args.remove_designators.split(',') if x.strip()}
        if args.action == 'none':
            # 便于对照: none 时若还给了 omega 仍可执行; 其它空封装处理全跳过
            pass
    args.fn(args)

if __name__ == '__main__':
    main()
