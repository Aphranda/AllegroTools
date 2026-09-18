# Altium→Allegro 转换工具包（自动探测环境 + 自动修复测试点 + 自动校验）

本目录是把本次排查成果固化的可复用工具：一次运行即可完成
「体检 → 自动修复 → 自动导入 → 自动抓错/校验 → 产出 .brd」，
并**自动检索本机可用的 Allegro 环境**（无需写死安装路径）。

## 0) 背景结论（实测验证，供理解）

- Allegro 24.1 S008 的 `altium2pcb` 转换器会在 **“text blocks”阶段对 nil 调
  `upperCase` 而崩溃**。
- 触发条件：ASCII 中存在 **PATTERN（封装名）为空** 的 Component 记录
  （本工程为测试点 **T1/T2/T3/T4**）。
- 只要去掉/修正这些元件，整板（元件/网络/走线/铺铜/丝印）即可完整导入。
- 丝印里的非 ASCII 字符（Ω 等）**不是**崩溃原因（也已验证）。

## 1) 文件清单

| 文件 | 作用 |
|---|---|
| `find_allegro.ps1` | 自动探测 Allegro：CDSROOT/环境变量 → PATH → 注册表 SPB_* → 盘符扫描；校验 `allegro.exe` + `translators.cxt` + `altium2pcb.ini`；可输出 JSON |
| `altium_ascii_tool.py` | ASCII 体检/修复/变体工具（check / fix / variant） |
| `run_import.scr.template` | Allegro 导入脚本模板（`__PCB__` 占位） |
| `allegro_watchdog.ps1` | 启动 Allegro `-s` 跑脚本、自动收尾、抓 journal 错误与产物 |
| `run_conversion.ps1` | 流程管理：一键 发现→体检→修复→导入→校验→拷贝 .brd |
| `altium2allegro_qa.il` | SKILL：导入后在 Allegro 内核对 元件/网络/符号/DRC 数 |

## 2) 快速上手

### 只体检（不需要 Allegro）
```bat
python altium_ascii_tool.py check CTL-SYNCTRIG4F4-HASL-ASCII.pcbdoc
```

### 一键转换（推荐；会自动开 Allegro GUI 执行，需保持登录/授权）
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File run_conversion.ps1 `
    -Input CTL-SYNCTRIG4F4-HASL-ASCII.pcbdoc `
    -OutBrd out\CTL-SYNCTRIG4F4-HASL.brd `
    -FixMode remove -TpPadDia 40mil -AutoFallback
```
流程内部自动：探测 Allegro → check → fix（给空封装测试点分配 `TP1PAD` +
40mil 圆焊盘）→ 生成 .scr → 看门狗导入 → 若 pad 方案失败自动降级 remove 重试
→ 成功后拷贝 .brd 到 `-OutBrd`。

### 手动分步（便于排错）
```powershell
# 1) 修复
python altium_ascii_tool.py fix CTL-...-HASL-ASCII.pcbdoc -o fixed.pcbdoc `
      --empty-pattern-action pad --tp-pattern TP1PAD --tp-pad-dia 40mil
# 2) 导入（内部调用 Allegro 并自动抓错）
powershell -File allegro_watchdog.ps1 -WorkDir _auto_run\conv -ScrName run_import.scr
```

## 3) 自动探测 Allegro 的规则

优先级：显式 `-AllegroRoot` > `CDSROOT/CDS_INST_DIR/SPB_ROOT/ALLEGRO_ROOT` 环境变量
> `PATH` 中的 `allegro.exe`（回溯安装根）> 注册表 `HKLM\...\Cadence Design Systems\SPB_*`
> 各盘 `SPB_*` / `Cadence\SPB_*` 目录扫描。
每个候选都必须同时满足：`tools\bin\allegro.exe`、`share\pcb\etc\context\64bit\translators.cxt`、
`share\pcb\translators\config\altium2pcb.ini` 存在，才算“可用”。

```powershell
powershell -File find_allegro.ps1 -ListAll          # 列出全部候选
powershell -File find_allegro.ps1 -OutJson env.json # 写结果给流程脚本用
```

## 4) fix 策略（对空封装元件 / 测试点）

- `remove`（**默认**）：直接删除空封装元件，控制台与 `--report` 列出删除清单（位号/位置/原因）
  - `pad`（可选）：分配 `PATTERN=TP1PAD` + 按 Component ID 补一条 40mil ROUND 焊盘（模板取自文件内现成 SMD 圆焊盘），元件完整保留、可正常导入；

- `fill`：只填封装名、不加焊盘；
- `none`：不改（对照复现崩溃用）。

## 5) SKILL 质检用法

Allegro 中打开导入后的 .brd，命令行执行（**注意函数名已改为下划线形式**，见第 8 节）：
```skill
skill (load "F:/1.Hardware/GTS_PPA1/08.CTL-SYNCTRIG4F4-HASL/AllegroTools/_altium2allegro_kit/altium2allegro_qa.il")
skill (alt2a_qa "F:/.../board_qa.txt")
skill (alt2a_compare 265)
```

## 6) 还原封装里的"定位孔"（DOCUMENT 闭合线 -> BOARD GEOMETRY/CUTOUT）

### 6.1 问题

嘉立创(EasyEDA) 封装里, 连接器的机械定位孔(定位柱孔)**不是焊盘**, 而是画在
`DOCUMENT_LAYER` 上的一圈闭合线。经 AD -> Allegro 之后, 这些闭合线被原样搬成了

```
PACKAGE GEOMETRY/DOCUMENT_LAYER     上的 path 图形      (78 个 path / 例如 RJ45)
```

于是钻孔/铣槽文件里根本没有这些孔 —— 表现为"封装没有定位孔"。

实测(RJ45 `R-RJ45R08P-C000`): 该封装有 2 个定位孔, 闭合线外轮廓 Ø = 118.05 设计单位
= **2.998 mm**, 圆心分别为 (-249.95, -229.80) 与 (250.05, -229.80);
每一处都同时存在一个 `ROUTE KEEPOUT/ALL` 的 keepout 方块(129.9 x 129.9)。

### 6.2 识别规则（两根信号同时满足, 误判率极低）

| 信号 | 判据 |
|---|---|
| A | `PACKAGE GEOMETRY` 下 **DOCUMENT 类**图层上有一圈"闭合且近似圆"的线 |
| B | **同一圆心**位置存在 `ROUTE KEEPOUT/ALL` 的 keepout |

### 6.3 处理动作

闭合线是有宽度的, 所以取它们的**外轮廓**（中心线外扩半个线宽, 即 Z-Copy 的
enlarge 语义）作为 `BOARD GEOMETRY/CUTOUT` 上的一个**圆形 shape**。

实现方式: 把目标层上所有 path 的 `axlPolyFromDB` 方框做**聚类**, 每一块的
外接方框就是该处闭合线的外轮廓; 方框长宽差 ≤ 5% 判为圆。

### 6.4 用法

**推荐：单会话模式（整个库只启动一次 Allegro）**

```powershell
# 只读体检 + 不显示窗口（最不打扰办公）
powershell -NoProfile -ExecutionPolicy Bypass -File run_locator_holes.ps1 -InSession -NoGraph

# 只验证几个样本（用 ; 分隔多个通配符）
powershell ... -File run_locator_holes.ps1 -InSession -NoGraph `
    -Only "tf-smd_tf-01a.dra;usb-c-smd_type-c-6pin-2md-073.dra;c0402.dra"

# 有界面但只开一次、跑完才退
powershell ... -File run_locator_holes.ps1 -InSession

# 应用修改（会先整库备份到 Allegro\_lib_backup_<时间戳>）
powershell ... -File run_locator_holes.ps1 -InSession -Action fix
```

单会话模式为什么快且稳：
* `allegro.exe -nograph` —— 实测**不出现窗口**（进程 HasWindow=False），不抢焦点；
* scan 时自动加 `-readonly`，物理上无法写库；
* 会话内用 `axlKillDesign` + `axlOpenDesign ?mode "wl" ?ignoreLock t`：
  **不生成 `.dra.lck`**，也**不会因为残留 `.lck` 弹模态框卡死**（这正是早期"卡住不报错"的根因）。

**备选：逐文件模式（每个 `.dra` 起一次 Allegro）**

```powershell
powershell ... -File run_locator_holes.ps1 -Action scan -Only "rj45*"
```
不传 `-InSession` 即为逐文件模式；用"完成标记文件"判断结束，比 PID 可靠
（`allegro.exe` 会重新拉起子进程）。

常用参数: `-Targets DOCUMENT`、`-KeepoutPat KEEPOUT`、`-OutLayer "BOARD GEOMETRY/CUTOUT"`、
`-MinDiaMM/-MaxDiaMM`（默认 0.3~8.0 mm）、`-Only <通配符;分隔>`、
`-NoKeepoutRequired`（放宽成"只要闭合圆就认定"）、`-DeleteOriginal`、
`-NoBackup`、`-NoCreateSym`。

也可在 Allegro 里对当前打开的图手动跑:
```skill
skill (load ".../alt2a_locator_hole.il")
skill (alt2a_run "scan")                       ; 当前这张图
skill (alt2a_librun "<lib目录>" "scan")        ; 整个库(单会话)
```

### 6.4.1 回归基线（2026-09-17 实测，5 样本）

| 器件 | DOCUMENT 圆 | keepout | 认定孔 | 结论 |
|---|---|---|---|---|
| `c0402`（对照/正常） | 无 | – | 0 | ✓ 无误报 |
| `soic-8_l5_3-w5_3-p1_27-ls8_0-bl`（正常） | 1 × Ø0.598mm | no | 0 | ✓ 无误报 |
| `tqfn-16_l3_0-w3_0-p0_50-bl-ep1_7`（正常） | 1 × Ø0.498mm | no | 0 | ✓ 无误报 |
| `tf-smd_tf-01a`（有问题的 TF 卡座） | 2 × Ø0.799mm | **YES** | **2** | ✓ |
| `usb-c-smd_type-c-6pin-2md-073`（有问题的 Type-C） | 2 × Ø0.498mm | **YES** | **2** | ✓ |
| `rj45-th_r-rj45r08p-c000`（RJ45） | 2 × Ø2.998mm | **YES** | **2** | ✓ 已实测 fix 落盘 |

要点：**两个"正常"器件在 DOCUMENT 层也有圆（Ø0.5~0.6mm），但都没有 keepout**，
被双信号规则挡掉 —— keepout 才是真正起作用的判据，孔径范围只是辅助过滤。
`-MinDiaMM` 默认已从 0.5 调到 **0.3**，否则 Type-C 的 Ø0.498mm 会被静默丢掉
（现在即便被孔径范围拒掉也会显式打印原因，不再静默丢弃）。


### 6.5 重要限制 / 后续

- 脚本**只改 .dra**; 之后必须重编译 `.psm`: `create_sym -p <name>.dra`（驱动脚本会自动做）。
- 板子上**已放置**的元件需要 `Place > Update Symbols` 才会带上新 CUTOUT。
- 一个 `.dra` 起一次 Allegro（用命令行把图直接传进去）。**不要**在脚本里用
  `axlOpenDesignForBatch` 循环开图 —— 在本机实测会卡住（无报错、无对话框）。
- 驱动脚本只结束"本次自己启动"的 Allegro 进程, 不会误杀用户已打开的 Allegro。
- 仍需人工复核: 生成的 Ø 是"闭合线外轮廓"。RJ45 实测得到 2.998 mm, 若供应链要求
  名义 3.0 mm 可直接用; 若要求 3.2 mm 请配合 `-MinDiaMM/-MaxDiaMM` 与后处理调整。

### 6.6 配套工具

| 文件 | 作用 |
|---|---|
| `alt2a_locator_hole.il` | SKILL 主体: 识别 + 生成 CUTOUT（`(alt2a_run "scan"\|"fix")`） |
| `run_locator_holes.ps1` | 驱动: 逐 .dra 起 Allegro、汇总报告、备份、`create_sym` 重编译 |
| `alt2a_dump_layers.il` | 诊断: 打开一张 .dra, 列出它所有线/弧/shape 所在的 subclass（用来确认"孔到底在哪个层"） |
| `il_check.py` | SKILL 静态检查: 括号配平、未定义调用、`sprintf` 格式符与实参个数 |
| `il_lint2.py` | SKILL 方言检查: 函数名含 `-`、`setq` 多变量、前缀比较运算符 |

## 7) 注意事项

- 转换需要合法 Allegro 许可；脚本会打开一个 Allegro GUI 窗口并自动操作、
  结束后自行退出（若被"是否保存"弹窗卡住，看门狗会自动按键放行）。
- 本机若在受管/沙箱环境运行，启动 GUI 需放行完整权限。
- 导入后记得核对：差分对类别（缺 `DifferentialPair_Classes.txt` 的旧告警）、
  Dielectric 0 厚度告警、以及测试点补的 40mil 圆焊盘是否符合生产要求。
- 建议把"空封装元件导致崩溃"的最小复现反馈 Cadence（附一个空封装元件即可复现）。

## 8) SKILL 方言坑（本项目踩过的，写 .il 时必看）

Cadence SKILL 和常见 Lisp 差别很大，本项目实际踩到并修复的：

1. **函数名不能含 `-`**：reader 会把 `alt2a-qa` 解析成 `(alt2a - qa)`（减法！），
   于是 `defun`/`procedure` 直接报
   `argument #1 should be a symbol ... - (alt2a - qa)`。→ 一律用 `_`。
   *原来的 `altium2allegro_qa.il` 就是栽在这里，一直没能加载，本次已修好。*
2. **`setq` 一次只能赋一个变量**：`(setq a 1 b 2)` 报 `too many arguments`；必须拆开写。
3. **比较/算术是"中缀"**：写 `(a > b)`、`(w - h)`、`(x + 1)`；
   写成前缀 `(> a b)` 是**语法错误**（`SYNTAX ERROR ... column N`）。
   `abs`/`min`/`max` 同理不安全，本项目改成自写的 `alt2a_abs/alt2a_min2/alt2a_max2`。
4. **零参过程**写 `(procedure (name) body)`；写成 `(procedure (name () body))` 会报参数个数错。
5. **`cons` 第二参必须是 list**，不能用来拼点；点用 `(list x y)` 构造。
6. **`outfile` 的模式参是字符串**：`(outfile path "a")`，不是 `'a`。
7. 用 `il_check.py` / `il_lint2.py` 先静态扫一遍，再进 Allegro 试，能省大量往返。


