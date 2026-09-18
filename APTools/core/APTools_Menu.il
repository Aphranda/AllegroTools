;;; ============================================================================
;;; APTools_Menu.il  --  APTools 的 ilinit 唯一入口
;;; ----------------------------------------------------------------------------
;;; Allegro 的加载点是  %HOME%\pcbenv\allegro.ilinit  (本机 HOME=D:\Cadence\SPB_Data)
;;; 里面写:
;;;     ; ---- APTools 自建 SKILL 工具集 ----
;;;     apt_home = "D:/Aphranda/APTools"
;;;     errset(loadi(strcat(apt_home "/core/APTools_Menu.il")) t)
;;;
;;; 2026-09-18 修的坑(当天菜单整个消失过一次, 而且不报错)
;;;   坑1  apt_home 被解析错。原来第一句是 (defvar apt_home nil), 它会把 ilinit
;;;        刚设好的值覆盖掉, 于是去读环境变量 APTools。那个变量当时指着已经废弃的
;;;        D:\Aphranda\APTools_prod(旧目录结构, 没有 core/), loadi 静默失败,
;;;        下一句 (apt_loadAll) 就成了未定义函数 -> 菜单消失。
;;;        为什么昨天没事: 用户级环境变量对"环境块已过期"的进程不可见, 昨天读不到
;;;        就退回内置路径了; 机器重启后环境块刷新, 变量第一次真正可见, 于是踩中。
;;;        现在: 不再 defvar 覆盖, 而且**每个候选目录都必须校验
;;;        core/APTools_Load.il 真的存在**, 校验不过就换下一个候选。
;;;   坑2  loadi 静默失败 + 裸调 apt_loadAll 会抛异常。现在改用 load + errset,
;;;        成功与否都会打印出来。
;;;
;;; 本文件本身也能独立工作(没在 ilinit 里设 apt_home 时按候选顺序自己找)。
;;;
;;; 编码: 必须 GBK(cp936)。
;;; ============================================================================

;;; 内置默认运行位置(最后兜底)
(defvar apt_homeBuiltin nil)
(setq apt_homeBuiltin "D:/Aphranda/APTools")

;;; 安全读 apt_home: 直接读未绑定符号会报错, 所以走 errset
(defvar apt_homeHint nil)
(setq apt_homeHint (car (errset apt_home nil)))

;;; ---------------------------------------------------------------------------
;;; 某个目录是不是一个"能用的运行位置": core/APTools_Load.il 必须真的在
;;;   不直接判文件是否存在(那要靠 isFile, 实测不保险), 而是列目录再看文件名,
;;;   这样对"目录不存在"也能安全返回 nil。
;;; ---------------------------------------------------------------------------
(procedure (apt_homeOk t_dir)
    (let (fs hit)
        (when t_dir
            (setq fs (car (errset (getDirFiles (strcat t_dir "/core")) nil)))
            (when fs
                (foreach f fs
                    (when (and (null hit) (rexMatchp "APTools_Load.il$" f))
                        (setq hit t)))))
        hit))

;;; ---------------------------------------------------------------------------
;;; 依次尝试: ilinit 预置值 -> 环境变量 APTools -> 内置默认
;;;   取第一个"校验通过"的, 而不是第一个非空的 —— 这是这次坏掉的根本教训。
;;; ---------------------------------------------------------------------------
(defvar apt_homePick nil)
(defvar apt_homeEnv nil)
(setq apt_homePick nil)
(setq apt_homeEnv (getShellEnvVar "APTools"))

(foreach cand (list apt_homeHint apt_homeEnv apt_homeBuiltin)
    (when (and (null apt_homePick) (apt_homeOk cand))
        (setq apt_homePick cand)))

(if apt_homePick
    (setq apt_home (axlOSSlash apt_homePick))
    (progn
        (setq apt_home (axlOSSlash apt_homeBuiltin))
        (printf "[APTools] !! 找不到可用的运行位置(core/APTools_Load.il 不存在)\n")
        (printf "[APTools] !! 候选: ilinit=%L  环境变量 APTools=%L  内置=%L\n"
                apt_homeHint apt_homeEnv apt_homeBuiltin)))

;;; 1) 加载核心框架(用 load 不用 loadi, 出错才看得见)
(if (car (errset (load (strcat apt_home "/core/APTools_Load.il")) t))
    (progn
        ;; Load.il 内部原本也有一段 apt_home 兜底, 而且会用 (defvar apt_home nil)
        ;; 把这里刚选好的值覆盖成 nil, 再去读那个可能指向废弃目录的环境变量 ——
        ;; 这就是 2026-09-18 菜单消失的直接原因。它现在已改成"校验式、不覆盖",
        ;; 但这里**再断言一次**: 将来万一又被改坏, 也不至于让 apt_loadAll 扫错目录。
        (setq apt_home (axlOSSlash apt_homePick))

        ;; 2) 加载 tools/ 下所有工具(各工具自己调用 apt_menuAdd 声明菜单项)
        ;; 3) 汇总菜单并挂到 menubar 右端
        (if (car (errset (apt_loadAll) t))
            (errset (apt_menuRegister) t)
            (printf "[APTools] !! apt_loadAll 失败, 菜单未注册\n")))
    (printf "[APTools] !! 加载 %s/core/APTools_Load.il 失败, 菜单未注册\n" apt_home))

(printf "[APTools] 工具集就绪 (root=%s)\n" apt_home)
