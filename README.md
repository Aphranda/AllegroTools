# AllegroTools — Altium ↔ Cadence(Allegro / OrCAD X) 转换工具集

本次项目沉淀的可复用脚本与结论。核心解决两类实测问题：

1. **Altium PCB(ASCII .pcbdoc) → Allegro PCB**：
   - 根因：Allegro 24.1 S008 `altium2pcb` 遇到 **PATTERN(封装名)为空**的元件（本板为测试点 T1–T4）
     会在文字块阶段 `*Error* upperCase: … nil` 崩溃（与 Ω/丝印/文字数量无关，已实测排除）。
   - 对策：自动识别空封装元件 → **删除**并**报告**（位号/坐标/原因）；或给它们分配 40mil 圆焊盘封装保留。
   - 结果：`FIX1/NOTP`（删除版）与 `FIX2-40`（补焊盘版）均完整导入成功（7.0MB .brd，261 元件全保留）。

2. **Altium 原理图(ASCII .SchDoc) → OrCAD X Capture**：
   - Capture 的 Altium 翻译器为 GUI(无命令行)，每张 ASCII SchDoc 可独立导入出一个 .DSN；
   - 实测出现**整体 +5mil 偏移**（引脚/元件符号/封装一致平移）→ 源侧修正：脚本把坐标整体左移 5mil 后重导解决；
   - 多页合成建议：在 Altium 建 `.PrjPcb` 并 Compile，用 Flat Multipage 一次生成多页 DSN。

## 目录

```
AllegroTools
├─ README.md                      ← 本文件（总览）
└─ _altium2allegro_kit/
   ├─ find_allegro.ps1            自动探测本机 Allegro 安装(环境变量/PATH/注册表/盘符, 校验 exe+cxt+ini, 多版本取新)
   ├─ altium_ascii_tool.py        PCB ASCII 体检/修复/二分变体: check / fix(默认删空封装+报告) / variant
   ├─ run_import.scr.template     Allegro 导入脚本模板(占位 __PCB__)
   ├─ allegro_watchdog.ps1        启动 Allegro -s 导入, 自动收尾、弹窗放行、抓 journal 错误与产物
   ├─ run_conversion.ps1          流程管理一键: 发现→check→fix(报告)→导入→校验→拷贝 .brd(失败可自动换策略重试)
   ├─ altium2allegro_qa.il        SKILL 质检: 导入后核对 元件/网络/符号/DRC 并写报告
   ├─ sch_xshift.py               SchDoc 坐标整体平移(修正 Capture 转换的整体偏移; 单位×10=mil, 自动 .bak)
   ├─ watch_capture_imports.ps1   监控手动逐张 Capture 导入进度/校验 .DSN
   ├─ AD-Schematic转OrCADX-Capture操作说明.md
   ├─ alt2a_locator_hole.il       ★ SKILL: 还原封装"定位孔"(DOCUMENT 闭合线 -> BOARD GEOMETRY/CUTOUT)
   ├─ run_locator_holes.ps1       ★ 驱动: 逐 .dra 跑上面这个 SKILL, 备份 + 汇总 + create_sym 重编译
   ├─ alt2a_dump_layers.il          诊断: 列出某张 .dra 里所有线/弧/shape 所在的 subclass
   ├─ il_check.py                   SKILL 静态检查(括号配平 / 未定义调用 / sprintf 实参个数)
   ├─ il_lint2.py                   SKILL 方言检查(函数名含 '-' / setq 多变量 / 前缀比较运算符)
   └─ README.md                   工具包内详细说明
```

## 常用命令

```powershell
# —— PCB 方向 ——
python _altium2allegro_kit\altium_ascii_tool.py check CTL-...-HASL-ASCII.pcbdoc     # 体检
python _altium2allegro_kit\altium_ascii_tool.py fix <输入>.pcbdoc -o <输出>.pcbdoc --report r.txt  # 删空封装+报告
powershell -File _altium2allegro_kit\run_conversion.ps1 -Input <输入>.pcbdoc -OutBrd out.brd -FixMode remove

# —— 封装"定位孔"还原 ——
powershell -File _altium2allegro_kit\run_locator_holes.ps1                     # 体检, 不改文件
powershell -File _altium2allegro_kit\run_locator_holes.ps1 -Only "rj45*"       # 只看 RJ45
powershell -File _altium2allegro_kit\run_locator_holes.ps1 -Action fix         # 生成 CUTOUT + 重编译 .psm

# —— 原理图方向(手动导入) ——
python _altium2allegro_kit\sch_xshift.py <原理图目录> --dx 5 --dry-run              # 预览整体左移5mil
python _altium2allegro_kit\sch_xshift.py <原理图目录> --dx 5                        # 应用(自动 .bak)
powershell -File _altium2allegro_kit\watch_capture_imports.ps1 -OneShot            # 查看导入进度
```

## 已知问题 / 待办 (TODO)
- [x] **封装缺"定位孔"**（嘉立创→AD→Allegro 链路）：定位孔不是焊盘, 而是 `PACKAGE GEOMETRY/DOCUMENT_LAYER`
      上的闭合线。已做出 `alt2a_locator_hole.il` + `run_locator_holes.ps1`：
      以「DOCUMENT 闭合圆 + 同位置 ROUTE KEEPOUT/ALL」双信号识别, 取闭合线外轮廓生成
      `BOARD GEOMETRY/CUTOUT` 的圆形 shape。RJ45 实测 2 个孔 / Ø2.998mm, 已验证落盘。
- [ ] **部分焊盘位置不对**：同一条转换链路还会让同名封装产生多个几何不同的变体
      （如 `c0402` 与 `c0402_1..c0402_4`，`c0603_1/_2`，`ssop-16..._1`，`usb-c..._1`）。
      复用库时若抓错变体就会"焊盘位置/尺寸不对"。建议按 IPC-7351 重建这批通用封装，
      或逐封装与数据手册核对后收敛同名变体。
- [ ] **元件本体方框未随 X 偏移**：`sch_xshift.py --dx 5` 平移后引脚/连线已对齐，但部分元件符号外框(方框)未跟着动 → 需定位方框在 SchDoc 中使用的坐标字段（可能非 `LOCATION.X/X1/X2/CORNER.X`），扩展脚本键集后重导验证。
- [ ] **跨页连接符(Off-page/Port/Sheet Symbol)仍偏移**：同类原因，坐标字段或记录类型未被覆盖；并入上一条一起修。
- [ ] 修完用 `--dry-run` 对比 + OrCAD X 重导抽查，确认全部对象(引脚/外框/文字/跨页符)一致。
- [ ] 若外框来自转换生成的 `ORCAD_LIBRARY.OLB` 符号库(而非页面坐标)，需改为修符号库或确认重导会重建 OLB。

## 环境与注意事项
- 需要合法 Cadence 许可；转换会打开 Allegro/Capture GUI 自动操作，脚本带看门狗自动收尾。
- 受管/沙箱环境运行 GUI 需放行完整权限。
- 本机曾探测到 `SPB_24.1` 与 `SPB_25.1` 双版本，默认取新版，可用 `-AllegroRoot` 指定。
- 所有工具均为“源侧修复+自动验证”，对原始文件只做备份后修改（`.bak`）。
- **写 SKILL 前先看 `_altium2allegro_kit/README.md` 第 8 节**（SKILL 方言坑：函数名不能含 `-`、
  `setq` 一次一个变量、比较/算术是中缀、`cons` 不能拼点、`outfile` 模式参是字符串）。

