# SKILL 方言坑（写 APTools 工具前必看）

Cadence SKILL 和常见 Lisp 差别很大。以下是本项目**实际踩到并修好**的，每一条都曾让脚本直接加载失败或静默失效。

## 1. 函数名 / 变量名不能含 `-`

SKILL 的 reader 会把 `apt-qa` 解析成 `(apt - qa)`（减法表达式），于是：

```
*Error* defun: argument #1 should be a symbol (type template = "sgg") - (apt - qa)
```

- ❌ `alt2a-qa`、`apt-menu-add`
- ✅ `alt2a_qa`、`apt_menuAdd`

> 项目里 `altium2allegro_qa.il` 就是栽在这里 —— 它写成 `alt2a-qa`，`load` 从来没成功过，
> 一直"存在但不可用"。

## 2. `setq` 一次只能赋一个变量

```skill
(setq a 1 b 2)        ; ✗ setq: too many arguments (2 expected, 4 given)
(setq a 1) (setq b 2) ; ✓
```

## 3. 比较 / 算术是"中缀"

```skill
(a > b)      ; ✓
(w - h)      ; ✓
(x + 1)      ; ✓
(> a b)      ; ✗ SYNTAX ERROR found at line N column M
```

`abs` / `min` / `max` 也**不保险**，本项目自写了 `apt_abs` / `apt_min2` / `apt_max2` / `apt_ge` / `apt_le` 封装。

## 4. 零参过程

```skill
(procedure (name) body)         ; ✓
(procedure (name () body))      ; ✗ too few arguments (at least 2 expected, 1 given)
```

## 5. `cons` 第二参必须是 list

不能用来拼"点"。点用 `(list x y)` 构造：

```skill
(cons x y)        ; ✗ cons: argument #2 should be a list - y
(list x y)        ; ✓
```

## 6. `outfile` 的模式参是字符串

```skill
(outfile path "a")   ; ✓ 追加
(outfile path 'a)    ; ✗ outfile: argument #2 should be a string - a
(outfile path)       ; ✓ 覆盖写
```

## 7. `loadi` 静默失败

`loadi` 出错**不报错**，只是什么都不做。所以路径拼错、变量为空时，表现是"菜单里什么都没有"，
而不是报错。排查时优先用 `load`（会报错）。

## 8. 其它

- `isDir` / `isFile` 之类判断可用 `getDirFiles` 代替。注意两点：
  目录不存在时它**会报错**（`getDirFiles: nonexistent or permission denied`），要用
  `errset` 包住；返回的列表里**含 `.` 和 `..`**，递归时务必跳过（见第 15 条前的加载器注记）。
- **`defvar` 会覆盖已绑定的值**（这里原先写反了，2026-09-18 实测纠正，见第 19 条）。
  想让上层（ilinit）预置的全局不被覆盖，**不要用 `defvar`**，改成"安全读 + 校验"：
  ```skill
  ;; 未绑定就直接读会报错, 所以走 errset
  (setq cur (car (errset apt_home nil)))
  ```
- 菜单文字必须 GBK 编码，见 `编码要求.md`。

## 9. `substring` 是 **1 起算**的，索引 0 直接报错

写 `APT_NetColor.il` 时全线按 0 起算写，结果：

```
*Error* substring: second argument (i.e., index) must not be 0
```

实测确认：

```skill
(substring "ABCDEF" 2 3)   ; => "BCD"   （第 2 个字符起 3 个，不是 0 起算的 "CDE"）
(substring "ABC" 0 1)      ; ✗ 索引不能是 0
```

统一包一层再写，本项目在 `APT_NetColor.il` 里的做法：

```skill
;;; 第 t_i 个字符(0 起算), 越界返回 ""
(procedure (apt_ch t_s t_i)
    (let (n) (setq n (strlen t_s))
        (if (or (t_i < 0) (t_i >= n)) "" (substring t_s (t_i + 1) 1))))
```

## 10. 没有 bignum，整数是 32 位且会回绕

- 字面量超过 `INT_MAX` 会在**解析期**被截断成 `INT_MAX`（只是 warning，不报错）：
  `1000000000000000` → `2147483647`。
- 运行时相乘也会回绕成负数：`2147483647 + 2147483647` = `-2`，
  `1000003 * 1000000` = `-724379968`。

所以别想着拿大数做取模/哈希。要随机就用原生的（见第 12 条）。

## 11. `mod` 是**函数**不是中缀；`/` 对整数是整除

```skill
(mod 7 2)     ; ✓ => 1
(7 mod 2)     ; ✗ reader 报语法错, 整个文件载入失败
(7 / 2)       ; => 3     （整除）
(1 / 3)       ; => 0
((0 - 7) / 2) ; => -3    （向零截断）
```

第 3 条说的"中缀"只适用于 `+ - * / < > <= >= ==`，`mod` 不在其中。

## 12. `random` / `srandom` 有，`getCurrentTime` 返回**字符串**

```skill
(random 10)        ; => 0..9     （可用! 不用自己造 LCG）
(random)           ; => 大随机整数
(srandom 12345)    ; 设种子
(getCurrentTime)   ; => "Sep 17 21:54:02 2026"   ← 是字符串, 不是数字列表!
```

所以想用时间播种，得从这串里抽数字（`APT_NetColor.il` 的 `apt_netSeed` 就是这么做的）。

## 13. `itoa` **不存在**

```skill
(itoa 3300)                 ; ✗ *Error* eval: undefined function - itoa
(sprintf nil "%d" 3300)     ; ✓ => "3300"
```

## 14. 多套一层括号 = "调用这个值"

```skill
(255 - a)     ; ✓  字面量可以当中缀左操作数
((255 - a))   ; ✗ *Error* eval: not a function - (255 - a)
```

`((x))` 在 SKILL 里是"把 `x` 求值结果当函数调用"，所以多出来的那层括号必炸。
（对比 `((hi - lo) + 1)` 是合法的 —— 外层的括号里是完整的中缀表达式，不是单个 form。）

## 15. 括号错位的**连锁反应**（最坑的一条）

SKILL 没有编译器帮你挡这一关，代价是错误现场和原因离得很远：

- **少一个右括号**：不会报语法错，而是把后面的顶层 form **吞进前一个函数体**。
  现象是加载日志显示"成功 4 失败 0"，但一半函数 `undefined function`。
  （`APT_NetColor.il` 的 `apt_voltAt` 少一个 `)`，把后面 4 个过程定义全吞了。）
- **多一个右括号**：会让 `let` 提前闭合，后面的语句变成**载入期顶层语句**立刻执行，
  于是报 `unbound variable`（因为 `let` 里的局部量还不存在）。
  排查时会误以为是变量声明的问题。

所以：**改完先看括号平衡**，`devkit/il_parens.py` 就是干这个的。

## 16. `errset` 的返回值要看清楚

```skill
(errset expr nil)    ; 表达式**出错** -> nil（且第二参为 nil 时不打印错误!）
                     ; 表达式**返回 nil** -> (nil)
```

所以 `(null e)` 只说明"出错了"，不说明"结果是 nil"。调试时把第二参给 `t`，
错误文本才会打出来，否则只能看到一片 `nil`。

## 17. 看菜单不一定要开窗口

`axlUIMenuDump` / `axlUIMenuFind` 在 `-nograph` 下都返回 nil。但要确认菜单项注册没注册，
直接读变量 `apt_menuTree` 即可（纯数据，无窗口也行）：

```skill
skill (printf "MENUTREE=%L\n" (errset apt_menuTree nil))
```

## 18. 打开图做只读验证

```powershell
allegro.exe -nograph -readonly -s check.scr
```

```skill
(axlOpenDesign ?design "F:/.../xxx.brd" ?noMru t)   ; ?mode "r" 是非法值, 会 warning
```

- 只读靠命令行的 `-readonly`（`?mode "r"` 不被接受）。
- `?noMru t` 避免污染用户的"最近打开"列表。
- 只读打开下跑工具不会落盘，板文件时间戳/校验和不变。

## 19. 运行位置解析：校验目录，别信环境变量，别用 defvar 覆盖

**2026-09-18 的事故**：APTools 菜单整个消失，FanySkill 菜单却正常，而且**全程没有任何报错**。

三个坑叠在一起：

1. `APTools_Menu.il` 开头是 `(defvar apt_home nil)` —— **`defvar` 把 ilinit 刚设好的值
   覆盖成了 nil**（我原先以为它只在未绑定时赋值，是错的）。
2. 于是去读环境变量 `APTools`。那个变量（用户级）指着**已废弃的旧目录**
   `D:\Aphranda\APTools_prod`（旧布局 `skill/` + `SkillCode/`，**没有 `core/`**）。
3. `loadi` 找不到文件**静默返回** → 下一句裸调 `(apt_loadAll)` 成了未定义函数 → 菜单消失。
   而 `APTools_Load.il` 里**还有一份同样的 `defvar apt_home nil` + 读环境变量**，
   把 `Menu.il` 好不容易选对的路径**又覆盖了一次** → `apt_loadAll` 去扫旧目录 → 0 个工具。

**为什么"昨天还好好的"**：用户级环境变量对"环境块已过期"的进程不可见。重启前 Allegro 读不到
那个变量，兜底路径生效；**机器重启后环境块刷新，变量第一次真正可见**，于是踩中。
（所以"实测不可见"这种结论必须带上"在什么前提下"。）

**正确写法**：候选路径逐个**校验目录**，取第一个通过校验的，而不是第一个非空的：

```skill
;;; 目录里真有 core/APTools_Load.il 才算可用
;;; (目录不存在时 getDirFiles 会直接报错, 所以要用 errset 包住)
(procedure (apt_homeOk t_dir)
    (let (fs hit)
        (when t_dir
            (setq fs (car (errset (getDirFiles (strcat t_dir "/core")) nil)))
            (when fs
                (foreach f fs
                    (when (and (null hit) (rexMatchp "APTools_Load.il$" f))
                        (setq hit t)))))
        hit))

(let (cur pick)
    (setq cur (car (errset apt_home nil)))          ; 已绑定就不动它, 绝不用 defvar
    (when (apt_homeOk cur) (setq pick cur))
    (unless pick
        (foreach cand (list (getShellEnvVar "APTools") "D:/Aphranda/APTools")
            (when (and (null pick) (apt_homeOk cand)) (setq pick cand))))
    (unless pick (setq pick "D:/Aphranda/APTools"))
    (setq apt_home (axlOSSlash pick)))
```

配套三条纪律：

- **`loadi` 只用在"文件一定在"的地方**；关键入口用 `load` + `errset`，失败必须打印出来
- 报"成功"的地方，`errset` 返回值要取 `(car res)` —— `errset` 包了一层，
  即使里面返回 nil，`res` 也是 `(nil)`（非空）；直接 `(if res ...)` 会把
  "返回 nil"误报成"注册成功"
- **只做开发的那块盘（F:）绝不能出现在运行时链路里**：运行位置固定在 D:，
  环境变量、缓存、路径一个都不留

**可复现的验证方式**：故意把错的值塞进子进程环境，再起 Allegro，看它能不能自救：

```powershell
$env:APTools = 'D:\Aphranda\APTools_prod'      # 故意给错的
allegro -nograph -readonly -s verify.scr
# 期望: apt_home = D:/Aphranda/APTools / 成功 4 失败 0 / 菜单已注册
```

顺带一条排查经验：**先怀疑"值被谁覆盖了"**。用一个最小探针把中间变量全打出来
（`apt_homeHint` / `apt_homeEnv` / `apt_homeBuiltin` / `apt_homePick` / 最终 `apt_home`），
一眼就能看出是"选错了"还是"选对了又被改掉了" —— 本次就是靠这个在一步内定位到第二个
`defvar` 的。

## 写之前先跑静态检查

`devkit/` 下有免费的自检，能省掉大量"进 Allegro 试一次 20 秒"的往返：

```powershell
python devkit\il_check.py  core\APTools_Load.il tools\10_library\APT_LocatorHole.il
python devkit\il_parens.py core\APTools_Load.il tools\10_library\APT_LocatorHole.il
python devkit\il_lint.py   core\APTools_Load.il tools\10_library\APT_LocatorHole.il
```

| 脚本 | 查什么 |
|---|---|
| `il_check.py` | GBK 编码体检、调用了未定义的 `apt_*`、`sprintf` 格式符与实参个数不匹配 |
| `il_parens.py` | **括号平衡 / 顶层 form 完整性**（第 15 条那类坑，加载日志看不出来） |
| `il_lint.py` | 函数名含 `-`、`setq` 多变量、前缀比较/算术运算符 |

> **待办**：现有三个脚本还是"单个文件 + 关键词扫描"，挡不住本轮踩的
> `itoa` 不存在、`((x))` 多括号、`if` 实参过多、`substring` 索引 0 这几类。
> 计划把它们合并成一个**真正的静态检查器**：先做词法/语法解析成 AST，再基于 AST 查
> 未定义函数、实参个数、多余括号、`if`/`setq` 实参个数、中缀/前缀误用、
> 变量是否赋值过。等价于给 SKILL 补一个"编译器"。见 `docs/待办-静态检查器.md`。
