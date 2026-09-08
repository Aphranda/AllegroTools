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
    -FixMode pad -TpPadDia 40mil -AutoFallback
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

- `pad`（默认）：分配 `PATTERN=TP1PAD` + 按 Component ID 补一条 **40mil ROUND**
  焊盘（模板取自文件内现成 SMD 圆焊盘），元件完整保留、可正常导入；
- `remove`：删除这些元件（简单稳妥，适合不需要测试点对象的情况）；
- `fill`：只填封装名、不加焊盘；
- `none`：不改（对照复现崩溃用）。

## 5) SKILL 质检用法

Allegro 中打开导入后的 .brd，命令行执行：
```skill
skill (load "F:/1.Hardware/GTS_PPA1/06.SYNC_TRIG/_altium2allegro_kit/altium2allegro_qa.il")
skill (alt2a-qa "F:/1.Hardware/GTS_PPA1/06.SYNC_TRIG/_auto_run/board_qa.txt")
skill (alt2a-compare 265)
```

## 6) 注意事项

- 转换需要合法 Allegro 许可；脚本会打开一个 Allegro GUI 窗口并自动操作、
  结束后自行退出（若被“是否保存”弹窗卡住，看门狗会自动按键放行）。
- 本机若在受管/沙箱环境运行，启动 GUI 需放行完整权限。
- 导入后记得核对：差分对类别（缺 `DifferentialPair_Classes.txt` 的旧告警）、
  Dielectric 0 厚度告警、以及测试点补的 40mil 圆焊盘是否符合生产要求。
- 建议把“空封装元件导致崩溃”的最小复现反馈 Cadence（附一个空封装元件即可复现）。
