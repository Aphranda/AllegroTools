#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
il_lint2.py -- 针对 Cadence SKILL 的常见"方言"陷阱做静态扫描:
  1. (setq a 1 b 2 ...)   -- SKILL 的 setq 只接受 一个变量, 多余实参会报
                             "setq: too many arguments"
  2. 符号名里的 '-'        -- SKILL reader 会把 a-b 当成减法, 必须用 '_'
  3. 前缀比较/算术 (> a b) -- SKILL 用中缀 (a > b)
用法: python il_lint2.py <file.il>
"""
import re
import sys


def strip_comments_and_strings(text):
    out = []
    i, n = 0, len(text)
    line = 1
    in_str = False
    while i < n:
        ch = text[i]
        if ch == '\n':
            line += 1
            out.append(('\n', line))
            i += 1
            continue
        if in_str:
            if ch == '\\':
                i += 2
                continue
            if ch == '"':
                in_str = False
            i += 1
            continue
        if ch == ';':
            while i < n and text[i] != '\n':
                i += 1
            continue
        if ch == '"':
            in_str = True
            i += 1
            continue
        out.append((ch, line))
        i += 1
    return out


def top_args(chars, start):
    """chars 是 (char,line) 列表; 从 start(指向 '(' 之后) 开始取顶层实参个数"""
    depth = 0
    args = 0
    seen = False
    i = start
    while i < len(chars):
        ch = chars[i][0]
        if ch in '([':
            depth += 1
            seen = True
        elif ch in ')]':
            if depth == 0:
                break
            depth -= 1
        elif depth == 0 and ch in ' \t\n':
            if seen:
                args += 1
                seen = False
        else:
            seen = True
        i += 1
    if seen:
        args += 1
    return args


def main(path):
    text = open(path, encoding='utf-8', errors='replace').read()
    chars = strip_comments_and_strings(text)
    flat = ''.join(c for c, _ in chars)
    problems = 0

    # 1) setq 实参个数
    for m in re.finditer(r'\(setq\s', flat):
        n = top_args(chars, m.end())
        if n > 2:
            line = chars[m.start()][1]
            print('  [ERR] L%-4d setq 有 %d 个实参 (SKILL 只允许 1 个变量): %s'
                  % (line, n, text.splitlines()[line - 1].strip()[:90]))
            problems += 1

    # 2) 符号名中的连字符(排除注释后仍有 a-b 形式的标识符)
    for m in re.finditer(r'\b[A-Za-z][A-Za-z0-9_]*\-[A-Za-z0-9_\-]+', flat):
        tok = m.group(0)
        if tok.startswith('alt2a') or tok.startswith('axl'):
            line = chars[m.start()][1]
            print('  [ERR] L%-4d 标识符含 "-": %s' % (line, tok))
            problems += 1

    # 3) 前缀比较/算术
    for m in re.finditer(r'\((>=|<=|!=|>|<|\+|\*|/)\s', flat):
        line = chars[m.start()][1]
        print('  [ERR] L%-4d 前缀运算符: %s' % (line, text.splitlines()[line - 1].strip()[:90]))
        problems += 1

    return problems


if __name__ == '__main__':
    total = 0
    for p in sys.argv[1:]:
        print('=== %s ===' % p)
        total += main(p)
    print('\n共发现 %d 处问题' % total)
    sys.exit(1 if total else 0)
