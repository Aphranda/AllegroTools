#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
migrate_split.py -- 把单文件版 APT_LocatorHole.il 拆成
    core/APTools_Load.il          (框架: 配置/日志/输出/通用几何助手/菜单/加载器)
    tools/10_library/APT_LocatorHole.il (工具: 只留自己的算法与命令 + 菜单自声明)
读取 GBK, 输出 UTF-8 (之后统一转回 GBK)。
"""
import io
import os
import re
import sys

SRC = r"D:\Aphranda\APTools\SkillCode\APT_LocatorHole.il"
OUT_CORE = r"D:\Aphranda\APTools\Temp\_core_part.txt"
OUT_TOOL = r"D:\Aphranda\APTools\Temp\_tool_part.txt"

# ---- 要搬进 core 的顶层定义 ----
MOVE_PROCS = {
    'apt_cfg', 'apt_cfgset', 'apt_log', 'apt_csvline',
    'apt_abs', 'apt_min2', 'apt_max2', 'apt_ge', 'apt_le',
    'apt_bb', 'apt_ptEq', 'apt_dist', 'apt_mm2uu', 'apt_uu2mm',
    'apt_selAll', 'apt_layerHas',
    'apt_begin', 'apt_end', 'apt_uiDefaults',
}
MOVE_DEFVARS = {'aptCfg', 'aptReport', 'aptCSV', 'aptChanged', 'aptModList', 'apt_home'}


def split_top_forms(text):
    """返回 [(preamble, form_text, kind, name)]，kind in {proc,defvar,other}"""
    forms = []
    i, n = 0, len(text)
    buf_start = 0
    while i < n:
        ch = text[i]
        if ch == ';':
            while i < n and text[i] != '\n':
                i += 1
            continue
        if ch == '"':
            i += 1
            while i < n and text[i] != '"':
                i += 2 if text[i] == '\\' else 1
            i += 1
            continue
        if ch == '(':
            start = i
            depth = 0
            while i < n:
                c = text[i]
                if c == ';':
                    while i < n and text[i] != '\n':
                        i += 1
                    continue
                if c == '"':
                    i += 1
                    while i < n and text[i] != '"':
                        i += 2 if text[i] == '\\' else 1
                    i += 1
                    continue
                if c == '(':
                    depth += 1
                elif c == ')':
                    depth -= 1
                    if depth == 0:
                        i += 1
                        break
                i += 1
            form = text[start:i]
            pre = text[buf_start:start]
            kind, name = classify(form)
            forms.append((pre, form, kind, name))
            buf_start = i
            continue
        i += 1
    forms.append((text[buf_start:], '', 'tail', ''))
    return forms


def classify(form):
    m = re.match(r'\(procedure\s+\(\s*([A-Za-z0-9_]+)', form)
    if m:
        return 'proc', m.group(1)
    m = re.match(r'\(defvar\s+([A-Za-z0-9_]+)', form)
    if m:
        return 'defvar', m.group(1)
    return 'other', ''


def main():
    text = io.open(SRC, encoding='gbk').read()
    forms = split_top_forms(text)

    core_parts, tool_parts = [], []
    cfg_block_pre = None
    first = True
    for pre, form, kind, name in forms:
        if first and pre.strip().startswith(';;;'):
            pre = ''      # 原文件头注释 -> 丢弃, 稍后写新头
        first = False
        if kind == 'proc' and name in MOVE_PROCS:
            core_parts.append(pre + form)
        elif kind == 'defvar' and name in MOVE_DEFVARS:
            core_parts.append(pre + form)
        elif kind == 'other' and 'apt_home' in form:
            pass                            # 归 core, 丢弃
        elif kind == 'other' and form.strip().startswith('(unless aptCfg'):
            cfg_block_pre = form            # 配置默认块 -> 转成 apt_cfgset
            tool_parts.append(pre)          # 注释保留
        else:
            tool_parts.append(pre + form)

    # ---- 解析配置默认块 -> apt_cfgset 调用 ----
    cfg_calls = []
    if cfg_block_pre:
        for m in re.finditer(r"\(list\s+'([A-Za-z0-9_]+)\s+([^()]*(?:\([^()]*\)[^()]*)*)\)", cfg_block_pre):
            key, val = m.group(1), m.group(2).strip()
            cfg_calls.append("(apt_cfgset '%s %s)" % (key, val))

    io.open(OUT_CORE, 'w', encoding='utf-8').write('\n'.join(core_parts))
    io.open(OUT_TOOL, 'w', encoding='utf-8').write('\n'.join(tool_parts))
    io.open(OUT_CORE + '.cfg', 'w', encoding='utf-8').write('\n'.join(cfg_calls))

    print('core 顶层定义: %d 个' % len(core_parts))
    print('tool 顶层定义: %d 个' % len([p for p in tool_parts if p.strip()]))
    print('配置项转 apt_cfgset: %d 条' % len(cfg_calls))
    for c in cfg_calls:
        print('   ', c)


if __name__ == '__main__':
    main()
