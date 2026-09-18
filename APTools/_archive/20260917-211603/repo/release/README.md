# APTools release —— 已验证可用的成品

这个目录是**自包含的装载单元**：内部布局和工具集开发根一样（`skill/` + `SkillCode/`），
`install.ps1` 会把环境变量 `APTools` 指向它自己，因此可以整目录拷给别人直接用。

## 版本

| 项 | 值 |
|---|---|
| 版本 | v0.1 |
| 日期 | 2026-09-17 |
| 内容 | 工具① 定位孔还原（APT_LocatorHole） |

## 包含什么

```
release/
├─ install.ps1                 安装: 设 APTools 环境变量 + 备份并追加 pcbenv\allegro.ilinit
├─ skill/
│   ├─ APTools_Menu.il         ilinit 唯一入口: 加载工具 + 注册 menubar 菜单
│   └─ APTools_Load.il         加载器: 自动 load SkillCode/ 下所有 .il
└─ SkillCode/
    └─ APT_LocatorHole.il      工具① 定位孔还原(DOCUMENT 闭合线 -> BOARD GEOMETRY/CUTOUT)
```

## 安装

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <本目录>\install.ps1
```

然后**重启 Allegro**。启动后命令行应出现：

```
[APTools]   ok   APT_LocatorHole.il
[APTools] 工具加载完成: 成功 1, 失败 0
[APTools] 菜单已注册 (menubar 右端 "APTools")
[APTools] 工具集就绪 (root=D:/Aphranda/APTools/release)
```

menubar 右端会出现 **APTools** 菜单。

> 注意：环境变量 `APTools` 只能指向一个根。装 release 版就会指向 release/；
> 想回到开发根，用开发根的 `install.ps1` 再装一次即可（幂等，会覆盖环境变量、
> 不重复追加 ilinit）。

## 已验证内容（装载 + 功能）

装载链路：Allegro 启动 → `pcbenv\allegro.ilinit` → `APTools_Menu.il` → `APTools_Load.il`
→ `APT_LocatorHole.il`，`apt_loadAll` 返回 `(1 0)`（1 成功 / 0 失败），journal 零错误。

功能回归基线（2026-09-17 实测）：

| 器件 | DOCUMENT 圆 | keepout | 认定孔 | |
|---|---|---|---|---|
| `c0402`（正常） | 无 | – | 0 | ✓ |
| `soic-8_l5_3-w5_3-p1_27-ls8_0-bl`（正常） | 1 × Ø0.598mm | no | 0 | ✓ |
| `tqfn-16_l3_0-w3_0-p0_50-bl-ep1_7`（正常） | 1 × Ø0.498mm | no | 0 | ✓ |
| `tf-smd_tf-01a`（TF 卡座） | 2 × Ø0.799mm | **YES** | **2** | ✓ 已开图确认 |
| `usb-c-smd_type-c-6pin-2md-073`（Type-C） | 2 × Ø0.498mm | **YES** | **2** | ✓ |
| `rj45-th_r-rj45r08p-c000`（RJ45） | 2 × Ø2.998mm | **YES** | **2** | ✓ fix 已落盘验证 |

## 常用命令

| 菜单 | 命令 |
|---|---|
| 定位孔: 扫描当前图 | `apt_scan` |
| 定位孔: 修复当前图 | `apt_fix` |
| 定位孔: 扫描整个库… | `apt_scanlib` |
| 定位孔: 修复整个库… | `apt_fixlib` |
| 设置库目录… | `apt_setlib` |

修完记得重编译 `.psm`（`File > Create Symbol`），板上已放置元件需
`Place > Update Symbols`。

## 卸载

```powershell
# 开发根里带了卸载脚本
powershell -NoProfile -ExecutionPolicy Bypass -File ..\uninstall.ps1
```
