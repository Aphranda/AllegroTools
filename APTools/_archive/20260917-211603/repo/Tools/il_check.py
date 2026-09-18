#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
il_check.py -- 轻量 SKILL 静态检查(不依赖 Allegro)
  * 括号/引号配平 (忽略 ; 注释与 "字符串" 里的内容)
  * 报告每层未闭合的位置
  * 检查常见笔误: 未定义的 alt2a-* 调用, sprintf 格式符与参数个数不匹配

用法: python il_check.py <file.il> [...]
"""
import re
import sys

FMT = re.compile(r'%[-+ #0]*[0-9]*(?:\.[0-9]+)?[a-zA-Z%]')


def strip_code(text):
    """返回 (清理后的字符流, 每字符对应原行号)。去注释与字符串字面量。"""
    out = []
    lines = []
    i, n = 0, len(text)
    line = 1
    in_str = False
    in_comment = False
    while i < n:
        ch = text[i]
        if ch == '\n':
            line += 1
            in_comment = False
            i += 1
            continue
        if in_comment:
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
            in_comment = True
            i += 1
            continue
        if ch == '"':
            in_str = True
            i += 1
            continue
        if ch == '\\' and i + 1 < n and text[i + 1] == '\n':
            line += 1
            i += 2
            continue
        out.append(ch)
        lines.append(line)
        i += 1
    return ''.join(out), lines, in_str


def check_balance(path):
    text = open(path, encoding='utf-8', errors='replace').read()
    code, lines, in_str = strip_code(text)
    stack = []
    bad = False
    for k, ch in enumerate(code):
        if ch in '([':
            stack.append((ch, lines[k]))
        elif ch in ')]':
            if not stack:
                print('  [ERR] 多余的 %s 于第 %d 行' % (ch, lines[k]))
                bad = True
            else:
                op, ln = stack.pop()
                if (op, ch) not in (('(', ')'), ('[', ']')):
                    print('  [ERR] 第 %d 行 %s 与第 %d 行 %s 不匹配' % (ln, op, lines[k], ch))
                    bad = True
    for op, ln in stack:
        print('  [ERR] 第 %d 行 %s 未闭合' % (ln, op))
        bad = True
    if in_str:
        print('  [ERR] 字符串未闭合')
        bad = True
    return bad


def check_calls(path):
    text = open(path, encoding='utf-8', errors='replace').read()
    # 只看去掉注释/字符串之后的代码, 否则注释里的示例会被误判成真实调用
    code, _, _ = strip_code(text)
    defined = set(re.findall(r'\(\s*(?:procedure|defun)\s*\(?\s*([A-Za-z_][\w\-]*)', code))
    defined |= set(re.findall(r'\(\s*procedure\s*\(\s*([A-Za-z_][\w\-]*)', code))
    called = set(re.findall(r'\(\s*([A-Za-z_][\w\-]*)', code))
    builtin_prefix = ('axl', 'sprintf', 'printf', 'fprintf', 'strcat', 'substring', 'rex',
                      'setq', 'let', 'when', 'unless', 'if', 'cond', 'foreach', 'while',
                      'list', 'cons', 'car', 'cdr', 'cadr', 'caddr', 'nth', 'member',
                      'remove', 'append', 'reverse', 'length', 'mapcar', 'lambda',
                      'sqrt', 'expt', 'abs', 'min', 'max', 'round', 'fix', 'float',
                      'outfile', 'close', 'errset', 'isFile', 'isDir', 'isFileName',
                      'getDirFiles', 'upperCase', 'lowerCase', 'equal', 'neq', 'atof',
                      'atoi', 'numberp', 'stringp', 'listp', 'null', 'and', 'or', 'not',
                      'progn', 'prog', 'set', 'defvar', 'defun', 'procedure', 'return',
                      'last', 'xcons', 'nconc', 'assoc', 'get', 'putprop', 'zerop',
                      'println', 'print', 'lineread', 'unwindProtect')
    unknown = sorted(c for c in called
                     if c.startswith('alt2a') and not c.startswith(builtin_prefix)
                     and c not in defined)
    for c in unknown:
        print('  [WARN] 调用了未在本文件定义的: %s' % c)
    return len(unknown) > 0


def split_args(text, i):
    """从 text[i:] 开始, 按 SKILL 语法切分顶层空白分隔的实参。
    返回 (参数个数, 结束位置)。括号组算一个参数。"""
    n = len(text)
    args = 0
    seen = False          # 当前是否正在积累一个参数
    depth = 0
    while i < n:
        ch = text[i]
        if ch == '"':
            seen = True
            i += 1
            while i < n and text[i] != '"':
                i += 2 if text[i] == '\\' else 1
            i += 1
            continue
        if ch in '([':
            depth += 1
            seen = True
            i += 1
            continue
        if ch in ')]':
            if depth == 0:
                break
            depth -= 1
            i += 1
            continue
        if depth == 0 and (ch in ' \t\r\n,'):
            if seen:
                args += 1
                seen = False
            i += 1
            continue
        seen = True
        i += 1
    if seen:
        args += 1
    return args, i


def check_sprintf(path):
    text = open(path, encoding='utf-8', errors='replace').read()
    warn = False
    for m in re.finditer(r'\(sprintf\s+nil\s+"((?:[^"\\]|\\.)*)"', text):
        fmt = m.group(1)
        specs = [s for s in FMT.findall(fmt) if s != '%%']
        nargs, _ = split_args(text, m.end())
        if nargs != len(specs):
            ln = text[:m.start()].count('\n') + 1
            print('  [WARN] 第 %d 行 sprintf 格式符 %d 个, 实参 %d 个: %s'
                  % (ln, len(specs), nargs, fmt[:60]))
            warn = True
    return warn


def main(argv):
    rc = 0
    for p in argv:
        print('=== %s ===' % p)
        b1 = check_balance(p)
        b2 = check_calls(p)
        b3 = check_sprintf(p)
        if not (b1 or b2 or b3):
            print('  OK')
        else:
            rc = 1
        print()
    return rc


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
