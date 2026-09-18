;;; ============================================================================
;;; APTools_Load.il  --  APTools 工具集加载器
;;; ----------------------------------------------------------------------------
;;; 作用: 把 SkillCode/ 目录下所有 .il 依次 load 进来。
;;;       单个工具报错不会影响其它工具(用 errset 兜住), 并在控制台明确报出来。
;;;       新增工具 = 往 SkillCode/ 丢一个 .il 文件, 不用改任何代码。
;;;
;;; 工具集根目录来自环境变量 APTools; 没有就退回到默认路径。
;;;
;;; SKILL 方言注意(本项目踩过的坑, 改这个文件前必看):
;;;   * 函数名不能含 '-'   (reader 会当成减法)
;;;   * setq 一次只能赋一个变量
;;;   * 比较/算术是中缀: (a > b) / (w - h), 不能写 (> a b)
;;;   * 零参过程写 (procedure (name) body)
;;; ============================================================================

(defvar apt_home nil)

(unless apt_home
    (setq apt_home (getShellEnvVar "APTools")))
(unless apt_home
    (setq apt_home "D:/Aphranda/APTools_prod"))
(setq apt_home (axlOSSlash apt_home))

;;; 加载 SkillCode/ 下所有 .il
;;; 返回 (总数 失败数)
(procedure (apt_loadAll)
    (let (dir files f full n bad ok)
        (setq dir (strcat apt_home "/SkillCode"))
        (setq files (getDirFiles dir))
        (setq n 0)
        (setq bad 0)
        (when (null files)
            (printf "[APTools] !! SkillCode 目录读不到: %s\n" dir))
        (foreach f files
            (when (rexMatchp "\\.il$" (lowerCase f))
                (setq full (strcat dir "/" f))
                (setq n (n + 1))
                (setq ok (errset (load full) t))
                (if ok
                    (printf "[APTools]   ok   %s\n" f)
                    (progn
                        (setq bad (bad + 1))
                        (printf "[APTools]   FAIL %s\n" f)))))
        (printf "[APTools] 工具加载完成: 成功 %d, 失败 %d\n" (n - bad) bad)
        (list n bad)))
