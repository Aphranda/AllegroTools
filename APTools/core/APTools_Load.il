;;; ============================================================================
;;; APTools_Load.il  --  APTools 框架层
;;; 配置存储 / 日志与输出 / SKILL 方言助手 / 通用 CAD 助手 / 菜单 / 加载器
;;; ----------------------------------------------------------------------------
;;; 本文件不含任何业务工具。业务工具放 ../tools/<阶段>/*.il
;;;
;;; 加载链路(由 core/APTools_Menu.il 触发):
;;;   1. 本文件被 loadi        -> 定义框架
;;;   2. (apt_loadAll)         -> 按 apt_stageOrder 顺序加载各阶段工具
;;;   3. 工具加载时用 (apt_menuAdd ...) 声明自己的菜单项
;;;   4. (apt_menuRegister)    -> 汇总菜单树并挂到 menubar
;;;
;;; 新增工具 = 往 tools/<阶段>/ 丢一个 .il, 里面 axlCmdRegister + apt_menuAdd。
;;; 新增阶段 = 建 tools/<两位数字_名字>/ 目录, 并在下面的 apt_stageOrder 里登记。
;;;
;;; 编码: 必须 GBK(cp936)。Allegro 在中文 Windows 上按本地代码页渲染
;;;       菜单/对话框/控制台文字, 存 UTF-8 会整片乱码。
;;;
;;; SKILL 方言坑: 函数名不能含 '-'; setq 一次只能赋一个变量;
;;;               比较/算术是中缀 (a > b); 零参过程写 (procedure (name) body)。
;;; ============================================================================
(defvar aptCfg      nil)

(defvar aptReport   nil)

(defvar aptCSV      nil)

(defvar aptChanged  nil)

(defvar aptModList  nil)


;;; ---------------------------------------------------------------------------
;;; 配置 / 输出
;;; ---------------------------------------------------------------------------

(procedure (apt_cfg key)
    (let (kv)
        (setq kv (assoc key aptCfg))
        (if kv (cadr kv) nil)))


(procedure (apt_cfgset key val)
    (let (kv)
        (setq kv (assoc key aptCfg))
        (if kv
            (progn (rplaca (cdr kv) val) val)
            (progn (setq aptCfg (cons (list key val) aptCfg)) val))))


(procedure (apt_log msg)
    (printf "%s\n" msg)
    (when aptReport (fprintf aptReport "%s\n" msg))
    t)


(procedure (apt_csvline msg)
    (when aptCSV (fprintf aptCSV "%s\n" msg))
    t)


;;; ---------------------------------------------------------------------------
;;; 基础工具 (SKILL 方言注意: 函数名不能含 '-'；setq 一次一个变量；
;;;             比较/算术是中缀 (a > b)；零参过程写 (procedure (name) ...))
;;; ---------------------------------------------------------------------------

(procedure (apt_abs x)
    (if (x < 0.0) (0.0 - x) x))


(procedure (apt_min2 a b)
    (if (a < b) a b))


(procedure (apt_max2 a b)
    (if (a > b) a b))


(procedure (apt_ge a b)
    (if (a >= b) t nil))


(procedure (apt_le a b)
    (if (a <= b) t nil))


;;; bBox -> (minX minY maxX maxY) 或 nil
(procedure (apt_bb bb)
    (let (a b)
        (cond
            ((null bb) nil)
            ((not (listp bb)) nil)
            ((and (apt_ge (length bb) 2)
                  (listp (car bb)) (listp (cadr bb))
                  (apt_ge (length (car bb)) 2) (apt_ge (length (cadr bb)) 2))
                (setq a (car bb))
                (setq b (cadr bb))
                (list (apt_min2 (car a) (car b)) (apt_min2 (cadr a) (cadr b))
                      (apt_max2 (car a) (car b)) (apt_max2 (cadr a) (cadr b))))
            ((and (apt_ge (length bb) 4) (numberp (nth 0 bb)))
                (list (apt_min2 (nth 0 bb) (nth 2 bb)) (apt_min2 (nth 1 bb) (nth 3 bb))
                      (apt_max2 (nth 0 bb) (nth 2 bb)) (apt_max2 (nth 1 bb) (nth 3 bb))))
            (t nil))))


(procedure (apt_mm2uu mm)
    (let (k) (setq k (axlMKS2UU "1mm")) (if k (mm * k) nil)))


(procedure (apt_uu2mm uu)
    (let (k) (setq k (axlMKS2UU "1mm")) (if (and k (k != 0.0)) (uu / k) nil)))


;;; 取某种图形: "lines" / "shapes"
(procedure (apt_selAll kind)
    (let (res)
        (axlClearSelSet)
        (axlSetFindFilter ?enabled (list "noall" kind) ?onButtons (list "noall" kind))
        (axlAddSelectAll)
        (setq res (axlGetSelSet))
        (axlClearSelSet)
        res))


(procedure (apt_layerHas lay pats)
    (let (up hit)
        (when lay
            (setq up (upperCase lay))
            (foreach p pats
                (when (rexMatchp (upperCase p) up) (setq hit t))))
        hit))


;;; ---------------------------------------------------------------------------
;;; 输出文件初始化/收尾 (由 .scr 先 cfgset 路径, 再由 PowerShell 收尾写 modified)
;;; ---------------------------------------------------------------------------

(procedure (apt_begin)
    (setq aptChanged nil)
    (setq aptModList nil)
    (when (and (apt_cfg 'report) (neq (apt_cfg 'report) ""))
        (setq aptReport (outfile (apt_cfg 'report) "a")))
    (when (and (apt_cfg 'csv) (neq (apt_cfg 'csv) ""))
        (setq aptCSV (outfile (apt_cfg 'csv) "a"))))


(procedure (apt_end)
    (when (and aptModList (apt_cfg 'modified) (neq (apt_cfg 'modified) ""))
        (let (mport nm)
            (setq mport (outfile (apt_cfg 'modified) "a"))
            (when mport
                (foreach nm (reverse aptModList)
                    (fprintf mport "%s\n" nm))
                (close mport))))
    (when aptReport (close aptReport) (setq aptReport nil))
    (when aptCSV (close aptCSV) (setq aptCSV nil)))
   ; 库目录, 第一次用会提示输入, 之后记住
;;; ---------------------------------------------------------------------------
;;; apt_home: 工具集根目录
;;;   ilinit 里已经设好了, core/APTools_Menu.il 还会校验一遍。
;;;
;;;   ！！这里绝对不能用 (defvar apt_home nil) —— **defvar 会覆盖已绑定的值**。
;;;   一旦被清成 nil, 下面就会去读环境变量 APTools, 而那个变量可能指着废弃的旧
;;;   目录(如 D:\Aphranda\APTools_prod)。2026-09-18 菜单整个消失就是这个原因:
;;;   Menu.il 明明已经选对了路径, 又被这里覆盖成旧路径, 全程静默, 最后
;;;   apt_loadAll 扫空目录 -> 0 个工具 -> 菜单不出现。
;;;
;;;   规则: 已绑定且目录校验通过 -> 原样保留; 否则按候选顺序找第一个"校验通过"的,
;;;        而不是第一个非空的。
;;; ---------------------------------------------------------------------------

;;; 目录里真的有 core/APTools_Load.il 才算可用
;;;   注意: Menu.il 里有个同义的 apt_homeOk, 这里刻意换个名字 apt_rootOk,
;;;   两边都定义是为了各自能被单独 load, 但同名会让 Allegro 打
;;;   "function X redefined" 警告, 所以错开命名。
(procedure (apt_rootOk t_dir)
    (let (fs hit)
        (when t_dir
            (setq fs (car (errset (getDirFiles (strcat t_dir "/core")) nil)))
            (when fs
                (foreach f fs
                    (when (and (null hit) (rexMatchp "APTools_Load.il$" f))
                        (setq hit t)))))
        hit))

(let (cur pick)
    (setq cur (car (errset apt_home nil)))          ; 未绑定时直接读会报错
    (setq pick nil)
    (when (apt_rootOk cur) (setq pick cur))
    (unless pick
        (foreach cand (list (getShellEnvVar "APTools") "D:/Aphranda/APTools")
            (when (and (null pick) (apt_rootOk cand))
                (setq pick cand))))
    (unless pick (setq pick "D:/Aphranda/APTools"))
    (setq apt_home (axlOSSlash pick)))


;;; UI 模式下给输出文件填默认值(写在 APTools/Temp 下)
(procedure (apt_uiDefaults)
    (unless apt_home (setq apt_home "D:/Aphranda/APTools"))
    (when (or (null (apt_cfg 'report)) (equal (apt_cfg 'report) ""))
        (apt_cfgset 'report (strcat (axlOSSlash apt_home) "/Temp/apt_locator_report.txt")))
    (when (or (null (apt_cfg 'csv)) (equal (apt_cfg 'csv) ""))
        (apt_cfgset 'csv (strcat (axlOSSlash apt_home) "/Temp/apt_locator_report.csv")))
    (when (or (null (apt_cfg 'modified)) (equal (apt_cfg 'modified) ""))
        (apt_cfgset 'modified (strcat (axlOSSlash apt_home) "/Temp/apt_locator_modified.txt"))))

;;; 当前工作目录(Allegro 打开图后一般会切到该图所在目录)
(procedure (apt_workDir)
    (let (d)
        (setq d (errset (getWorkingDir) t))
        (if (and d (car d)) (axlOSSlash (car d)) ".")))
;;; 只在未设置过时才写默认值(工具用自己的默认值调用它)
(procedure (apt_cfgdef key val)
    (unless (assoc key aptCfg)
        (apt_cfgset key val)))

;;; ---------------------------------------------------------------------------
;;; 菜单自声明
;;;   工具的 .il 里调用 (apt_menuAdd "10_library" "显示文字" "命令")
;;;   分隔线用 (apt_menuSep "10_library")
;;; ---------------------------------------------------------------------------

(defvar apt_menuTree nil)      ; ((阶段/子类 (项...) ...) ...) 保持插入顺序
(defvar apt_menuDone nil)      ; 菜单是否已注册过(热加载后需要重注册)

;; 阶段目录名 -> 中文菜单名; 列表顺序就是菜单顺序
(defvar apt_stageOrder nil)
(defvar apt_stageNames nil)

(setq apt_stageOrder (list "10_library" "20_placement" "30_routing"
                           "40_marking" "50_process" "90_misc"))

(setq apt_stageNames (list
    (list "10_library"   "封装")
    (list "20_placement" "布局")
    (list "30_routing"   "布线")
    (list "40_marking"   "字符")
    (list "50_process"   "工艺")
    (list "90_misc"      "辅助功能")))

(procedure (apt_stageLabel stg)
    (let (kv)
        (setq kv (assoc stg apt_stageNames))
        (if kv (cadr kv) stg)))

(procedure (apt_menuAddRaw stage item)
    (let (kv)
        (setq kv (assoc stage apt_menuTree))
        (unless kv
            (setq kv (cons stage nil))
            (setq apt_menuTree (append apt_menuTree (list kv))))
        (rplacd kv (append (cdr kv) (list item)))))

(procedure (apt_menuAdd stage label cmd)
    (apt_menuAddRaw stage (list label cmd)))

(procedure (apt_menuSep stage)
    (apt_menuAddRaw stage (list 'separator)))

;;; 挂在"阶段下的子菜单"里。sub = 子菜单显示名(中文), 例如 "定位孔还原"
(procedure (apt_menuSub stage sub label cmd)
    (apt_menuAddRaw (strcat stage "/" sub) (list label cmd)))

(procedure (apt_menuSubSep stage sub)
    (apt_menuAddRaw (strcat stage "/" sub) (list 'separator)))

;;; 某阶段下所有键(阶段本身 + 它的各子菜单), 按声明顺序
(procedure (apt_keysOf stage)
    (let (out kv)
        (foreach kv apt_menuTree
            (when (or (equal (car kv) stage)
                      (rexMatchp (strcat "^" stage "/") (car kv)))
                (setq out (append out (list (car kv))))))
        out))

;;; 把 apt_menuTree 汇总成 axlUIMenuRegister 需要的菜单列表
;;;   结构: APTools -> 阶段 -> [直接项] + [子菜单 -> 项] ...
(procedure (apt_buildMenu)
    (let (out keys k sub)
        (setq out (list (list 'popup "APTools")))
        (foreach stg apt_stageOrder
            (setq keys (apt_keysOf stg))
            (when keys
                (setq out (append out (list (list 'popup (apt_stageLabel stg)))))
                ;; 阶段下的直接项
                (when (assoc stg apt_menuTree)
                    (foreach it (cdr (assoc stg apt_menuTree))
                        (setq out (append out (list it)))))
                ;; 阶段下的子菜单
                (foreach k keys
                    (unless (equal k stg)
                        (setq sub (substring k ((strlen stg) + 2) (strlen k)))
                        (setq out (append out (list (list 'popup sub))))
                        (foreach it (cdr (assoc k apt_menuTree))
                            (setq out (append out (list it))))
                        (setq out (append out (list 'end)))))
                (setq out (append out (list 'end)))))
        out))

;;; 注册菜单。
;;;   注意 res 一定要取 (car res): errset 返回的是"包了一层的列表",
;;;   即使 axlUIMenuRegister 返回 nil, res 也是 (nil) —— 非空,
;;;   直接 (if res ...) 会把"返回 nil"误报成"注册成功"(2026-09-18 修)。
;;;   返回值一并打印出来, 方便判断到底成功了没有。
(procedure (apt_menuRegister)
    (let (lst res)
        (setq lst (apt_buildMenu))
        (setq res (errset (axlUIMenuRegister -1 lst) t))
        (if res
            (progn
                (setq apt_menuDone t)
                (printf "[APTools] 菜单已注册 (menubar 右端 \"APTools\", %d 个阶段; 返回值 %L)\n"
                        (length apt_stageOrder) (car res)))
            (printf "[APTools] !! 菜单注册抛异常; 命令仍可直接用 (apt_scan 等)\n"))))

;;; ---------------------------------------------------------------------------
;;; 加载器: 按 apt_stageOrder 顺序加载 tools/<阶段>/*.il
;;;   单个工具报错不影响其它工具(errset 兜住), 但会在控制台明确报出来
;;; ---------------------------------------------------------------------------

;;; 递归加载一个目录下所有 .il(支持 tools/<阶段>/<子类>/<工具>.il)
(defvar apt_loadN    0)
(defvar apt_loadBad  0)
(defvar apt_loadSeen nil)   ; 已加载的工具名, 防止同名文件被递归加载两次

;;; 注意: getDirFiles 会把 "." 和 ".." 也列出来, 不排除就会无限递归
;;;       (实测会拼出 .../././././... 超长路径然后把整个脚本搞崩)
(defvar apt_loadDepthMax 3)

(procedure (apt_loadTree dir depth)
    (let (files f full ok)
        (setq files (errset (getDirFiles dir) t))
        (when files
            (setq files (car files))
            (foreach f files
                (unless (member f (list "." ".."))
                    (setq full (strcat dir "/" f))
                    (if (rexMatchp "\\.il$" (lowerCase f))
                        (progn
                            (if (member f apt_loadSeen)
                                (printf "[APTools]   skip %s (同名已加载)\n" full)
                                (progn
                                    (setq apt_loadSeen (cons f apt_loadSeen))
                                    (setq apt_loadN (apt_loadN + 1))
                                    (setq ok (errset (load full) t))
                                    (if ok
                                        (printf "[APTools]   ok   %s\n" full)
                                        (progn
                                            (setq apt_loadBad (apt_loadBad + 1))
                                            (printf "[APTools]   FAIL %s\n" full))))))
                        (when (depth < apt_loadDepthMax)
                            (apt_loadTree full (depth + 1)))))))))

;;; 重新加载全部工具。
;;; 重点: 必须先把 apt_menuTree 清空, 否则会话内再调一次会把菜单项翻倍
;;;       (各工具会再次执行 apt_menuAdd, 往同一棵树里追加)。
;;; 如果菜单之前已经注册过, 加载完自动重注册一次, 让热加载即时生效。
(procedure (apt_loadAll)
    (let (root stg wasRegistered)
        (setq root (strcat apt_home "/tools"))
        (setq apt_loadN 0)
        (setq apt_loadBad 0)
        (setq apt_loadSeen nil)
        (setq wasRegistered apt_menuDone)
        (setq apt_menuTree nil)
        (setq apt_menuDone nil)
        (foreach stg apt_stageOrder
            (apt_loadTree (strcat root "/" stg) 0))
        (printf "[APTools] 工具加载完成: 成功 %d, 失败 %d\n" apt_loadN apt_loadBad)
        (when wasRegistered
            (apt_menuRegister))
        (list apt_loadN apt_loadBad)))