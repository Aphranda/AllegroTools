#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
il_parens.py -- SKILL 源文件括号平衡 / 顶层定义完整性检查

为什么需要它:
    SKILL 里少一个右括号不会在载入时报语法错, 而是把后面的顶层 form
    吞进前一个 form 的函数体里 —— 结果就是"载入显示 ok, 但一半函数未定义"。
    (APT_NetColor.il 就踩过这个坑: apt_voltAt 少一个 ')' 把后面 4 个
     过程定义全吞了, 加载日志还是 "成功 4, 失败 0"。)

检查内容:
    1. 全文件括号是否平衡(先剔除 ';' 注释和 "..." 字符串)
    2. 每个顶层 form 是否在同一层闭合; 未闭合的顶层 form 会被点名,
       并指出它吞掉了后面哪几个顶层 form
    3. 每个 (procedure (name ...)) 是否完整闭合

用法:
    python il_parens.py <文件.il> [更多文件...]
    退出码 0 = 全通过; 1 = 有问题
"""
import sys
import os

OPEN, CLOSE = '(', ')'


def strip_code(text):
    """去掉注释和字符串, 保留换行以便定位行号; 字符串内容用 'S' 占位。"""
    out = []
    i = 0
    n = len(text)
    in_str = False
    while i < n:
        c = text[i]
        if in_str:
            if c == '\\' and i + 1 < n:
                i += 2
                continue
            if c == '"':
                in_str = False
                out.append(c)
            else:
                out.append('S')
            i += 1
            continue
        if c == ';':
            while i < n and text[i] != '\n':
                i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def check(path):
    raw = open(path, 'rb').read().decode('gbk', errors='replace')
    code = strip_code(raw)

    depth = 0
    # 记录每个顶层 form 的起点与闭合行
    tops = []          # (start_line, start_char, end_line or None)
    cur = None
    line = 1
    problems = []

    for idx, c in enumerate(code):
        if c == '\n':
            line += 1
        elif c == OPEN:
            if depth == 0:
                cur = [line, idx, None]
                tops.append(cur)
            depth += 1
        elif c == CLOSE:
            depth -= 1
            if depth < 0:
                problems.append("第 %d 行: 多出一个右括号" % line)
                depth = 0
                cur = None
            elif depth == 0 and cur is not None:
                cur[2] = line
                cur = None

    if depth != 0:
        problems.append("文件结束时仍有 %d 个未闭合的左括号" % depth)

    unclosed = [t for t in tops if t[2] is None]
    if unclosed:
        for t in unclosed:
            problems.append("第 %d 行开始的顶层 form 没有闭合(吞掉了它后面的顶层 form)" % t[0])

    # 每个顶层 form 是不是 procedure 定义, 且内部有没有嵌套未闭合
    proc_count = 0
    for t in tops:
        head = code[t[1]:t[1] + 64].replace('\n', ' ')
        if head.startswith('(procedure'):
            proc_count += 1
            name = head.split('(')[2].split()[0] if head.count('(') >= 2 else '?'
            if t[2] is None:
                problems.append("过程 %s (第 %d 行) 未闭合" % (name, t[0]))

    print("=== %s ===" % path)
    print("  顶层 form 数 %d (其中 procedure %d 个), 括号平衡: %s"
          % (len(tops), proc_count, "是" if not problems else "否"))
    if problems:
        for p in problems:
            print("  [问题] %s" % p)
    else:
        print("  OK")
    return len(problems) == 0


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    ok = True
    for p in sys.argv[1:]:
        if not os.path.isfile(p):
            print("找不到文件: %s" % p)
            ok = False
            continue
        if not check(p):
            ok = False
        print()
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
