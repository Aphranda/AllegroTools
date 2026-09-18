# APTools —— 自建 Allegro SKILL 工具集

按 **板卡开发流程** 分层的纯 SKILL 工具集（不需要编译 `.cxt`）。
框架参考 FanySkill：`allegro.ilinit` 一行入口 + `tools/` 丢文件即装。

## 目录层级

```
APTools/                          ← 本仓库 = 只负责开发(唯一真源)
├─ core/                          ★ 框架层, 不含业务工具
│   ├─ APTools_Menu.il            ilinit 唯一入口: 加载框架 → 加载工具 → 注册菜单
│   └─ APTools_Load.il            配置/日志/输出 + 通用助手 + 菜单机制 + 加载器
│
├─ tools/                         ★ 按板卡开发流程分层
│   ├─ 10_library/                ① 封装
│   │   └─ locatorhole/           子类: 定位孔修复
│   │       └─ APT_LocatorHole.il
│   ├─ 20_placement/              ② 布局: 摆放/对齐/镜像/聚拢/格点
│   ├─ 30_routing/                ③ 布线: 线宽/过孔/差分/铺铜/截铜
│   ├─ 40_marking/                ④ 字符: 丝印/位号/文字
│   ├─ 50_process/                ⑤ 工艺: DRC/DFM/工艺边/拼板/测试点
│   └─ 90_misc/                   ⑥ 辅助功能: 图层/诊断/设置
│
├─ docs/
│   ├─ SKILL方言坑.md             ★ 写工具前必看(函数名/ setq / 中缀 / cons / outfile)
│   ├─ 编码要求.md                ★ .il 必须 GBK; .ps1 必须 UTF-8 BOM
│   └─ 新工具模板.il.txt
│
├─ devkit/                        ★ 只在开发时用, 不部署
│   ├─ il_check.py                静态检查: 括号配平 / 未定义调用 / sprintf 实参
│   ├─ il_lint.py                 方言检查: 函数名含 '-' / setq 多变量 / 前缀运算符
│   ├─ deploy.ps1                 同步 core/ + tools/ 到运行位置(含 GBK 体检)
│   └─ probe.ps1                  启一次无窗口 Allegro, 自检加载与菜单
│
├─ install/
│   ├─ install.ps1                写/更新 allegro.ilinit 里的 APTools 挂载块
│   └─ uninstall.ps1              移除挂载块
│
└─ release/                       (历史快照, 勿手改; 新部署走 devkit\deploy.ps1)
```

**运行位置**（Allegro 实际加载的地方，与 FanySkill 并排）：

```
D:\Aphranda\APTools\
├─ core/     ← 由 devkit\deploy.ps1 同步
├─ tools/    ← 由 devkit\deploy.ps1 同步
└─ Temp/     ← 运行期输出(报告/日志/probe), 不部署、不入库
```

## 安装 / 部署

```powershell
# 1) 部署到运行位置(会先做 GBK 编码体检)
powershell -NoProfile -ExecutionPolicy Bypass -File devkit\deploy.ps1

# 2) 挂到 Allegro(写 pcbenv\allegro.ilinit, 先备份)
powershell -NoProfile -ExecutionPolicy Bypass -File install\install.ps1

# 3) 自检(无窗口启动一次, dump 菜单)
powershell -NoProfile -ExecutionPolicy Bypass -File devkit\probe.ps1
```

装完**重启 Allegro**，menubar 右端出现 `APTools` 菜单。

`allegro.ilinit` 里写入的块（唯一入口）：

```skill
; ---- APTools 自建 SKILL 工具集 ----
apt_home = "D:/Aphranda/APTools"
loadi(strcat(apt_home "/core/APTools_Menu.il"))
```

> **为什么不用环境变量**：本机 `FyEnhanceTool` 是**机器级**变量所以 FanySkill 正常；
> 而 `APTools` 设成用户级时 **Allegro 进程读不到**（注册表有值，但已运行的父进程不会更新
> 自己的环境块，新进程继承的是旧环境块）。`getShellEnvVar` 返回空 → `loadi` **静默失败**
> → 菜单完全不出现。改用绝对路径后一次通过。

## 加一个工具（3 步）

1. 在对应阶段/子类目录建文件，例如 `tools/10_library/<子类>/APT_你的工具.il`
   （照抄 `docs/新工具模板.il.txt`）。加载器**递归**扫描，几层都能找到。
2. 里面 `axlCmdRegister` 注册命令 + 声明菜单：
   ```skill
   (axlCmdRegister "apt_xxx" 'apt_cmd_xxx ?cmdType "general")
   ```
3. `deploy.ps1` → 重启 Allegro（或命令行 `skill (apt_loadAll)` 只热加载工具）

### 菜单声明 API

菜单是三级结构：**APTools → 阶段 → 子类 → 菜单项**。

| 调用 | 挂在哪 |
|---|---|
| `(apt_menuAdd "10_library" "标签" "命令")` | 直接挂在 阶段 下（不再分子类） |
| `(apt_menuSep "10_library")` | 阶段 下的分隔线 |
| `(apt_menuSub "10_library" "定位孔修复" "标签" "命令")` | 挂在 阶段 的子类 **定位孔修复** 下 |
| `(apt_menuSubSep "10_library" "定位孔修复")` | 子类 下的分隔线 |

子类的**显示名就是中文**（写在工具文件里，GBK），与目录名无关 ——
所以目录可以用 ASCII（`locatorhole`）避开中文路径的编码问题。

阶段（`10_library` 等）是固定枚举，在 `core/APTools_Load.il` 的
`apt_stageOrder` / `apt_stageNames` 里登记；子类是各工具自由声明的。

> ⚠️ 同名 `.il` 只会被加载一次（加载器按文件名去重），避免同一工具被多次注册。
>
> `.il` 必须存成 **GBK**，否则菜单中文乱码 —— 见 `docs/编码要求.md`。

## 工具① 定位孔还原（APT_LocatorHole）

### 解决什么问题

嘉立创(EasyEDA) 封装里连接器的机械定位孔**不是焊盘**，而是画在 `DOCUMENT_LAYER` 上的一圈
闭合线。经 AD → Allegro 之后被原样搬成 `PACKAGE GEOMETRY/DOCUMENT_LAYER` 上的 path 图形，
于是钻孔/铣槽文件里没有这些孔 —— 表现为"封装没有定位孔"。

### 识别规则（两根信号同时满足，误判率极低）

| 信号 | 判据 |
|---|---|
| A | `PACKAGE GEOMETRY` 下 **DOCUMENT 类**图层上有一圈"闭合且近似圆"的线 |
| B | **同一圆心**位置存在 `ROUTE KEEPOUT/ALL` 的 keepout |

### 处理动作

闭合线是有宽度的，取它们的**外轮廓**（中心线外扩半个线宽，即 Z-Copy 的 enlarge 语义）
作为 `BOARD GEOMETRY/CUTOUT` 上的圆形 shape。

### 命令

| 菜单 | 命令 | 作用 |
|---|---|---|
| 定位孔: 扫描当前图 | `apt_scan` | 只报告当前打开的图 |
| 定位孔: 修复当前图 | `apt_fix` | 生成 CUTOUT 并存盘 |
| 定位孔: 扫描整个库… | `apt_scanlib` | 单会话连跑整个库，只读 |
| 定位孔: 修复整个库… | `apt_fixlib` | 单会话连跑整个库并生成 |
| 设置库目录… | `apt_setlib` | 记住库目录 |

也可在命令行：
```skill
skill (apt_librun "F:/1.Hardware/.../Allegro/lib" "scan")
```

### 可调参数

```skill
(apt_cfgset 'targets        (list "DOCUMENT"))          ; 闭合线所在图层关键字
(apt_cfgset 'keepoutPat     "KEEPOUT")                  ; keepout 图层关键字
(apt_cfgset 'outLayer       "BOARD GEOMETRY/CUTOUT")    ; 生成 CUTOUT 的图层
(apt_cfgset 'requireKeepout t)                          ; 是否必须同时有 keepout
(apt_cfgset 'minDiaMM       0.3)                        ; 孔径下限(mm)
(apt_cfgset 'maxDiaMM       8.0)                        ; 孔径上限(mm)
(apt_cfgset 'circleTol      0.05)                       ; 圆度容差(长宽差比例)
(apt_cfgset 'padTol         0.10)                       ; keepout 覆盖判定容差
(apt_cfgset 'deleteOriginal nil)                        ; t=顺带删掉源闭合线
(apt_cfgset 'only           nil)                        ; 正则列表, 只处理匹配的 .dra
```

### 修完还要做

1. **重编译 `.psm`**：`File > Create Symbol`，或 `create_sym -p <name>.dra`
2. 板上**已放置**的元件需 `Place > Update Symbols` 才会带上新 CUTOUT

### 实测回归基线（2026-09-17）

| 器件 | DOCUMENT 圆 | keepout | 认定孔 | |
|---|---|---|---|---|
| `c0402`（正常） | 无 | – | 0 | ✓ |
| `soic-8_l5_3-w5_3-p1_27-ls8_0-bl`（正常） | 1 × Ø0.598mm | no | 0 | ✓ |
| `tqfn-16_l3_0-w3_0-p0_50-bl-ep1_7`（正常） | 1 × Ø0.498mm | no | 0 | ✓ |
| `tf-smd_tf-01a`（TF 卡座） | 2 × Ø0.799mm | **YES** | **2** | ✓ 已开图确认 |
| `usb-c-smd_type-c-6pin-2md-073`（Type-C） | 2 × Ø0.498mm | **YES** | **2** | ✓ |
| `rj45-th_r-rj45r08p-c000`（RJ45） | 2 × Ø2.998mm | **YES** | **2** | ✓ fix 已落盘验证 |

要点：两个"正常"器件在 DOCUMENT 层**也有圆**（Ø0.5~0.6mm），但都没有 keepout，
被双信号规则挡掉 —— **keepout 才是真正起作用的判据**，孔径范围只是辅助过滤。

## 排错

| 现象 | 原因 | 处理 |
|---|---|---|
| 菜单栏没有 APTools，控制台也没有 `[APTools]` | 加载链没跑（路径拿不到，`loadi` 静默失败） | `devkit\probe.ps1` 定位；确认 ilinit 里是绝对路径 |
| `[APTools]` 行都有但菜单不显示 | 菜单注册时机 | 改 `axlTriggerSet('menu …)` + `axlUIMenuInsert`（文档明确：trigger 回调里不能用 `axlUIMenuRegister`） |
| 菜单有 APTools 但文字乱码 | `.il` 被存成 UTF-8 | 转回 GBK，见 `docs/编码要求.md` |
| 菜单在、工具没加载 | 某个 `.il` 报错 | 看 `[APTools]   FAIL <阶段>/<文件>`；加载器用 `errset` 兜住，单个失败不影响其他 |

诊断利器：`skill (axlUIMenuDump "D:/tmp/menu.txt")` 把当前菜单**完整导出**，
比肉眼看菜单栏可靠得多。
