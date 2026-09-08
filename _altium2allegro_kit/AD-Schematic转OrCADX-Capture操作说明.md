# AD 原理图 → OrCAD X Capture 逐张转换操作说明（含监控助手用法）

## 1) 前提（已满足）
- 8 张原理图已是 **ASCII .SchDoc**（Altium 保存为 ASCII），无需再做 AD 预处理：
  `BISSC_CON / INPUT_CON / IO_CON / ISO_PWR / LOCAL_COM / OUTPUT_CON / RJ45_CON / RP2350_CORE`
- 目录：
  `...\CTL-SYNCTRIG4F4-HASL\CTL-SYNCTRIG4F4-HASL\`（源 .SchDoc）
  输出建议统一到同目录下 `out\`

## 2) 每张图的导入操作（OrCAD X Capture 手动，GUI 无命令行）
1. OrCAD X Professional → **File → Import Design → Altium Schematic Translator**
2. 选择 单个 `.SchDoc`（Single Page 模式）
3. 输出目录选 `out\`
4. **Translate**
5. 结果：`out\<页名>.DSN`（每张独立），符号库写公共 `ORCAD_LIBRARY.OLB`
   （注意：每次导入会更新同一个 .OLB；若需保留各自库，导入时改库名）

已知已转：`BISSC_CON.DSN` ✅

## 3) 监控/校验助手（我提供的脚本）
`watch_capture_imports.ps1`：检测 `out\` 是否出现每张页的 `.DSN`，自动记录进度。

```powershell
# 单次扫描看当前进度
powershell -NoProfile -File watch_capture_imports.ps1 -OneShot
# 挂机监控 2 小时（每 15 秒扫一次，转完一张自动打印）
powershell -NoProfile -File watch_capture_imports.ps1 -Interval 15 -Minutes 120
```
状态写到源目录 `capture_import_state.json`；进度输出：
```
[STATUS] done=1/8   [DONE] BISSC_CON   [TODO] INPUT_CON, IO_CON, ...
```

## 4) 全部转完后“合成一个多页工程”的建议
逐张导入得到的是 N 个独立 `.DSN`。OrCAD 里把多张独立原理图合并成**一个多页 Design**不是“直接合并文件”操作，
推荐二选一：

- **方案 A（推荐，一次到位）**：在 Altium 里新建 **PCB Project(.PrjPcb)**，把这 8 张 `.SchDoc` 加入并
  **Compile**（生成 `.PrjPcbStructure`），然后用同一翻译器的 **Multipage Flat** 模式选 `.PrjPcb`，
  一次生成一个**多页 DSN**，免手工合成。
- **方案 B（仅在已逐张转出后）**：在 OrCAD X 中新建一个空 Project/Design，然后把各页导入的
  内容通过页面复制合入同一 Design（跨 Design 复制页面需人工核对网络/层次，耗时且易错）。

> 结论建议：如果最终目标是“一个多页 .DSN 工程”，优先走 **方案 A**（一次多页导入）；
> 逐张导入适合先快速验证各页内容。

## 5) 转完后检查项（Capture 内）
- 打开每个/合成 .DSN，检查：器件位号与值、网络、跨页连接符/端口（每张页的 IO 关系）、
  电源符号、层次/根页设置。
- 若最终要出网表给 Allegro PCB，在 Capture 里 Tools → Create Netlist 生成即可
  （与 PCB 侧 FIX 文件的元件位号需对应，如有差异以 Capture 侧为准再同步）。
