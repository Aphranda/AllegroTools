;;; ============================================================================
;;; APTools_Menu.il  --  APTools 菜单注册 + 工具加载入口
;;; ----------------------------------------------------------------------------
;;; 这个文件是 allegro.ilinit 唯一的入口。加载顺序:
;;;     1. APTools_Load.il  -> 把 SkillCode/ 下所有工具 load 进来(含 axlCmdRegister)
;;;     2. 注册 menubar 上的 "APTools" 菜单
;;;
;;; Allegro 的加载点:  %HOME%\pcbenv\allegro.ilinit   (本机 HOME=D:\Cadence\SPB_Data)
;;; 里面只需要一行:
;;;     loadi(strcat(getShellEnvVar("APTools") "\\skill\\APTools_Menu.il"))
;;;
;;; 菜单是纯 SKILL 定义的(axlUIMenuRegister)。FanySkill 用 .ini 是因为它带编译好的
;;; cxt; 纯 SKILL 工具集不需要那层, 直接改下面的列表即可。
;;;
;;; SKILL 方言注意: 函数名不能含 '-'; setq 一次一个变量; 比较/算术用中缀 (a > b)。
;;; ============================================================================

(defvar apt_home nil)
(unless apt_home
    (setq apt_home (getShellEnvVar "APTools")))
(unless apt_home
    (setq apt_home "D:/Aphranda/APTools_prod"))
(setq apt_home (axlOSSlash apt_home))

;; 先加载工具(会 axlCmdRegister 出 apt_scan / apt_fix / apt_scanlib / apt_fixlib 等)
(loadi (strcat apt_home "/skill/APTools_Load.il"))

;;; ---------------------------------------------------------------------------
;;; 菜单定义
;;;   (popup "显示名") 开一个子菜单 / (separator) 分隔线 / ("显示名" "命令")
;;; 命令列可以是 Allegro 命令, 也可以是 "skill 表达式"。
;;; ---------------------------------------------------------------------------
apt_menuList = '(
    (popup "APTools")
        ("定位孔: 扫描当前图"      "apt_scan")
        ("定位孔: 修复当前图"      "apt_fix")
        (separator)
        ("定位孔: 扫描整个库..."   "apt_scanlib")
        ("定位孔: 修复整个库..."   "apt_fixlib")
        (separator)
        ("设置库目录..."           "apt_setlib")
        ("重新加载工具集"          "skill (apt_loadAll)")
)

(procedure (apt_menuRegister)
    (let (res)
        (setq res (errset (axlUIMenuRegister -1 apt_menuList) t))
        (if res
            (printf "[APTools] 菜单已注册 (menubar 右端 \"APTools\")\n")
            (printf "[APTools] !! 菜单注册失败, 可在命令行直接用 apt_scan 等命令\n"))))

(apt_menuRegister)

(printf "[APTools] 工具集就绪 (root=%s)\n" apt_home)
