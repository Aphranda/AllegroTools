# MOVE_LOG - 归档 D:\Aphranda\APTools_prod

- 时间: 2026-09-18 12:57:46
- 来源: D:\Aphranda\APTools_prod
- 去向: AllegroTools\_archive\20260918-125746\runtime\APTools_prod
- 方式: **移动, 未删除** (15 个文件, 1.05 MB)

## 为什么归档

它是 APTools 最早那次"生产位置"尝试留下的目录, 旧布局:

    skill\APTools_Load.il        <- 旧布局, 不是 core\
    SkillCode\APT_LocatorHole.il
    install.ps1 / uninstall.ps1  <- 会把 ilinit 指回 APTools_prod 的旧版
    ✗ 没有 core\   ✗ 没有 tools\

2026-09-18 APTools 菜单整个消失的事故, 就是它引起的:

  1. 用户级环境变量 APTools 指向了这个目录
  2. APTools_Menu.il 开头 (defvar apt_home nil) 覆盖掉 ilinit 设好的正确路径
  3. 于是去读环境变量 -> 得到这个没有 core/ 的旧目录
  4. loadi 静默失败 -> (apt_loadAll) 未定义 -> 菜单消失, 且全程无报错
  5. APTools_Load.il 里还有一份同样的 defvar + 读环境变量, 把选对的路径又覆盖了一次

详细链路见 APTools\docs\SKILL方言坑.md 第 19 条。

## 归档前的安全确认

- 用户级环境变量 APTools 已改指 D:\Aphranda\APTools (Machine 级为空)
- PATH 里没有 APTools_prod
- 无任何进程占用 (归档时没有 allegro 在运行)
- 活代码里没有引用: 仅存的提及都是注释/文档里的历史说明
- 运行位置 D:\Aphranda\APTools 与之无依赖关系

## 需要时如何恢复

把 APTools_prod 移回 D:\Aphranda\ 即可。**不建议**, 除非要做历史对照。
若真要再用, 注意它的 install.ps1 会把 ilinit 指回旧布局。