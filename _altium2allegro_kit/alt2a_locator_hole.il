;;; ============================================================================
;;; alt2a_locator_hole.il   --  Allegro SKILL: 还原连接器"定位孔"为 CUTOUT
;;; ----------------------------------------------------------------------------
;;; 问题
;;;   本工程封装走 "嘉立创(EasyEDA) -> AD -> Allegro" 链路。EasyEDA 封装里
;;;   连接器的机械定位孔(定位柱孔)不是焊盘, 而是画在 DOCUMENT_LAYER 上的
;;;   "闭合线"。AD->Allegro 之后这些闭合线原样搬成了
;;;       PACKAGE GEOMETRY/DOCUMENT_LAYER  上的 path 图形
;;;   于是钻孔/铣槽文件里没有这些孔 —— 表现为"封装没有定位孔"。
;;;
;;; 识别规则(两根信号同时满足才认定, 误判率极低)
;;;   A. PACKAGE GEOMETRY 的 DOCUMENT 类图层上, 有一圈"闭合且近似圆"的线;
;;;   B. 同一圆心位置存在 ROUTE KEEPOUT/ALL 的 keepout。
;;;
;;; 处理动作
;;;   闭合线是有宽度的, 所以取它们的"外轮廓"(= 中心线外扩半个线宽, 即
;;;   Z-Copy 的 enlarge 语义)作为 BOARD GEOMETRY/CUTOUT 上的一个圆形 shape。
;;;
;;; 用法(由 run_locator_holes.ps1 驱动, 一个 .dra 起一次 Allegro)
;;;   allegro -s fix_one.scr  <xxx.dra>
;;;   其中 fix_one.scr:
;;;       skill load(".../alt2a_locator_hole.il")
;;;       skill alt2a_cfgset('report "...")
;;;       skill (alt2a_current "scan")     ; 或 "fix"
;;;       exit
;;;
;;; 也可在 Allegro 里手动用:
;;;   skill (alt2a_current "scan")
;;;   skill (alt2a_current "fix")
;;;
;;; 可调参数 (调用前 alt2a_cfgset)
;;;   'targets        ("DOCUMENT")                       ; 闭合线所在图层关键字
;;;   'keepoutPat     "KEEPOUT"                          ; keepout 图层关键字
;;;   'outLayer       "BOARD GEOMETRY/CUTOUT"            ; 生成 CUTOUT 的图层
;;;   'requireKeepout t                                  ; 是否必须同时有 keepout
;;;   'circleTol      0.05                               ; 圆度容差(长宽差比例)
;;;   'minDiaMM       0.5 / 'maxDiaMM 8.0                ; 孔径范围
;;;   'padTol         0.10                               ; keepout 覆盖判定容差
;;;   'deleteOriginal nil                                ; t=顺带删掉源闭合线
;;;   'dryRun         nil                                ; t=只报告不生成
;;;   'report / 'csv / 'modified                         ; 输出文件
;;;
;;; 注意
;;;   * 只改当前打开的那张 .dra; 之后必须重编译 .psm: create_sym -p <name>.dra
;;;   * 已放置元件需 Place > Update Symbols 才会带上 CUTOUT。
;;; ============================================================================

(defvar alt2aCfg      nil)
(defvar alt2aReport   nil)
(defvar alt2aCSV      nil)
(defvar alt2aChanged  nil)
(defvar alt2aModList  nil)   ; 本次批处理里改过的符号名

(unless alt2aCfg
    (setq alt2aCfg (list
        (list 'targets        (list "DOCUMENT"))
        (list 'keepoutPat     "KEEPOUT")
        (list 'outLayer       "BOARD GEOMETRY/CUTOUT")
        (list 'requireKeepout t)
        (list 'circleTol      0.05)
        (list 'minDiaMM       0.3)
        (list 'maxDiaMM       8.0)
        (list 'padTol         0.10)
        (list 'deleteOriginal nil)
        (list 'dryRun         nil)
        (list 'segments       72)
        (list 'only          nil)   ; 只处理匹配这些正则的 .dra (nil=全部)
        (list 'report         "")
        (list 'csv            "")
        (list 'modified       "")
    )))

;;; ---------------------------------------------------------------------------
;;; 配置 / 输出
;;; ---------------------------------------------------------------------------

(procedure (alt2a_cfg key)
    (let (kv)
        (setq kv (assoc key alt2aCfg))
        (if kv (cadr kv) nil)))

(procedure (alt2a_cfgset key val)
    (let (kv)
        (setq kv (assoc key alt2aCfg))
        (if kv
            (progn (rplaca (cdr kv) val) val)
            (progn (setq alt2aCfg (cons (list key val) alt2aCfg)) val))))

(procedure (alt2a_log msg)
    (printf "%s\n" msg)
    (when alt2aReport (fprintf alt2aReport "%s\n" msg))
    t)

(procedure (alt2a_csvline msg)
    (when alt2aCSV (fprintf alt2aCSV "%s\n" msg))
    t)

;;; ---------------------------------------------------------------------------
;;; 基础工具 (SKILL 方言注意: 函数名不能含 '-'；setq 一次一个变量；
;;;             比较/算术是中缀 (a > b)；零参过程写 (procedure (name) ...))
;;; ---------------------------------------------------------------------------

(procedure (alt2a_abs x)
    (if (x < 0.0) (0.0 - x) x))

(procedure (alt2a_min2 a b)
    (if (a < b) a b))

(procedure (alt2a_max2 a b)
    (if (a > b) a b))

(procedure (alt2a_ge a b)
    (if (a >= b) t nil))

(procedure (alt2a_le a b)
    (if (a <= b) t nil))

;;; bBox -> (minX minY maxX maxY) 或 nil
(procedure (alt2a_bb bb)
    (let (a b)
        (cond
            ((null bb) nil)
            ((not (listp bb)) nil)
            ((and (alt2a_ge (length bb) 2)
                  (listp (car bb)) (listp (cadr bb))
                  (alt2a_ge (length (car bb)) 2) (alt2a_ge (length (cadr bb)) 2))
                (setq a (car bb))
                (setq b (cadr bb))
                (list (alt2a_min2 (car a) (car b)) (alt2a_min2 (cadr a) (cadr b))
                      (alt2a_max2 (car a) (car b)) (alt2a_max2 (cadr a) (cadr b))))
            ((and (alt2a_ge (length bb) 4) (numberp (nth 0 bb)))
                (list (alt2a_min2 (nth 0 bb) (nth 2 bb)) (alt2a_min2 (nth 1 bb) (nth 3 bb))
                      (alt2a_max2 (nth 0 bb) (nth 2 bb)) (alt2a_max2 (nth 1 bb) (nth 3 bb))))
            (t nil))))

(procedure (alt2a_mm2uu mm)
    (let (k) (setq k (axlMKS2UU "1mm")) (if k (mm * k) nil)))

(procedure (alt2a_uu2mm uu)
    (let (k) (setq k (axlMKS2UU "1mm")) (if (and k (k != 0.0)) (uu / k) nil)))

;;; 取某种图形: "lines" / "shapes"
(procedure (alt2a_selAll kind)
    (let (res)
        (axlClearSelSet)
        (axlSetFindFilter ?enabled (list "noall" kind) ?onButtons (list "noall" kind))
        (axlAddSelectAll)
        (setq res (axlGetSelSet))
        (axlClearSelSet)
        res))

(procedure (alt2a_layerHas lay pats)
    (let (up hit)
        (when lay
            (setq up (upperCase lay))
            (foreach p pats
                (when (rexMatchp (upperCase p) up) (setq hit t))))
        hit))

(procedure (alt2a_diaOK dia)
    (let (mm)
        (setq mm (alt2a_uu2mm dia))
        (and mm (mm >= (alt2a_cfg 'minDiaMM)) (mm <= (alt2a_cfg 'maxDiaMM)))))

;;; ---------------------------------------------------------------------------
;;; 收集: 目标层的 path, 以及 keepout 的方框
;;; ---------------------------------------------------------------------------

;;; 返回 list of (dbid bBox) ; bBox = (minX minY maxX maxY)
(procedure (alt2a_targetPaths)
    (let (objs res bb)
        (setq objs (alt2a_selAll "lines"))
        (foreach o objs
            (when (alt2a_layerHas o->layer (alt2a_cfg 'targets))
                (setq bb (alt2a_bb o->bBox))
                (when bb
                    (setq res (cons (list o bb) res)))))
        (reverse res)))

;;; 返回 list of (dbid (minX minY maxX maxY))
(procedure (alt2a_keepouts)
    (let (objs res bb)
        (setq objs (alt2a_selAll "shapes"))
        (foreach o objs
            (when (alt2a_layerHas o->layer (list (alt2a_cfg 'keepoutPat)))
                (setq bb (alt2a_bb o->bBox))
                (when bb
                    (setq res (cons (list o bb) res)))))
        (reverse res)))

;;; ---------------------------------------------------------------------------
;;; 方框聚类: 把互相重叠(或很近)的方框并成一块 -> 每块就是一个候选定位孔
;;; ---------------------------------------------------------------------------

(procedure (alt2a_bbMerge a b)
    (list (alt2a_min2 (nth 0 a) (nth 0 b)) (alt2a_min2 (nth 1 a) (nth 1 b))
          (alt2a_max2 (nth 2 a) (nth 2 b)) (alt2a_max2 (nth 3 a) (nth 3 b))))

(procedure (alt2a_bbTouch a b tol)
    (and (alt2a_le (nth 0 a) ((nth 2 b) + tol))
         (alt2a_ge (nth 2 a) ((nth 0 b) - tol))
         (alt2a_le (nth 1 a) ((nth 3 b) + tol))
         (alt2a_ge (nth 3 a) ((nth 1 b) - tol))))

(procedure (alt2a_cluster bbs tol)
    (let (pool merged changed cur rest hit out)
        (setq pool bbs)
        (setq out nil)
        (while pool
            (setq cur (car pool))
            (setq pool (cdr pool))
            (setq changed t)
            (while changed
                (setq changed nil)
                (setq rest nil)
                (foreach b pool
                    (if (alt2a_bbTouch cur b tol)
                        (progn
                            (setq cur (alt2a_bbMerge cur b))
                            (setq changed t))
                        (setq rest (cons b rest))))
                (setq pool (reverse rest)))
            (setq out (cons cur out)))
        (reverse out)))

;;; ---------------------------------------------------------------------------
;;; 判定: 每个聚类块是不是"圆"
;;; 返回 list of (cx cy outerDia bb)
;;; ---------------------------------------------------------------------------

(procedure (alt2a_clusterCircles clusters)
    (let (res w h tol)
        (setq tol (alt2a_cfg 'circleTol))
        (foreach c clusters
            (setq w ((nth 2 c) - (nth 0 c)))
            (setq h ((nth 3 c) - (nth 1 c)))
            (when (and (w > 0.0) (h > 0.0)
                       (alt2a_le (alt2a_abs (w - h)) (tol * (alt2a_max2 w h))))
                (setq res (cons (list (((nth 0 c) + (nth 2 c)) / 2.0)
                                       (((nth 1 c) + (nth 3 c)) / 2.0)
                                       ((w + h) / 2.0) c)
                                res))))
        (reverse res)))

;;; keepout 是否盖住 (cx cy)
(procedure (alt2a_keepoutAt kps cx cy tol)
    (let (hit b pad)
        (setq pad (tol * 1.0))
        (foreach k kps
            (setq b (cadr k))
            (when (and (alt2a_ge cx ((nth 0 b) - pad)) (alt2a_le cx ((nth 2 b) + pad))
                       (alt2a_ge cy ((nth 1 b) - pad)) (alt2a_le cy ((nth 3 b) + pad)))
                (setq hit t)))
        hit))

;;; ---------------------------------------------------------------------------
;;; 生成 CUTOUT 圆形 shape
;;; ---------------------------------------------------------------------------

(procedure (alt2a_makeCirclePoly cx cy rad)
    (let (n i a pts p poly)
        (setq n (alt2a_cfg 'segments))
        (setq pts nil)
        (for i 0 (n - 1)
            (setq a ((2.0 * 3.14159265358979 * i) / n))
            (setq pts (cons (list (cx + (rad * (cos a))) (cy + (rad * (sin a)))) pts)))
        (setq pts (reverse pts))
        (setq pts (append pts (list (car pts))))
        (setq p (axlPathStart pts 0.0))
        (setq poly (axlPolyFromDB p))
        (if poly (car poly) nil)))

(procedure (alt2a_makeCutout cx cy dia)
    (let (poly res)
        (setq poly (alt2a_makeCirclePoly cx cy (dia / 2.0)))
        (if (null poly)
            nil
            (progn
                (setq res (axlDBCreateShape poly nil (alt2a_cfg 'outLayer)))
                (if res (car res) nil)))))

;;; ---------------------------------------------------------------------------
;;; 主流程: 处理当前打开的那张图
;;; 返回 (nCircle nKeepout nHole nMade nErr)
;;; ---------------------------------------------------------------------------

(procedure (alt2a_current t_action)
    (let (paths kps clusters circles c cx cy dia diaMM hit nCircle nKp nHole nMade nErr
          tol doFix polyRes confirmed)
        (setq nCircle 0)
        (setq nKp 0)
        (setq nHole 0)
        (setq nMade 0)
        (setq nErr 0)
        (setq alt2aChanged nil)   ; 每张图单独判定, 批处理时不能沿用上一张的
        (setq doFix (equal (lowerCase t_action) "fix"))
        (when (alt2a_cfg 'dryRun) (setq doFix nil))

        (setq paths (alt2a_targetPaths))
        (setq kps (alt2a_keepouts))
        (setq tol (alt2a_cfg 'padTol))

        (alt2a_log "")
        (alt2a_log (sprintf nil "=== %s ===  [%s]"
                            (axlCurrentDesign) (if doFix "FIX" "SCAN")))
        (alt2a_log (sprintf nil "  目标层 path: %d 个 (图层关键字 %L)"
                            (length paths) (alt2a_cfg 'targets)))
        (alt2a_log (sprintf nil "  keepout    : %d 个 (图层关键字 %L)"
                            (length kps) (alt2a_cfg 'keepoutPat)))

        (if (null paths)
            (alt2a_log "  -> 目标层没有闭合线, 跳过")
            (progn
                ;; 聚类容差按实际单位换算(0.01mm), 免得库是 mm 单位时 0.5 个单位太粗
                (setq clusters (alt2a_cluster (mapcar (lambda (x) (cadr x)) paths)
                                              (alt2a_max2 0.01 (or (axlMKS2UU "0.01mm") 0.5))))
                (setq circles (alt2a_clusterCircles clusters))
                (setq nCircle (length circles))
                (alt2a_log (sprintf nil "  聚类出 %d 块, 其中近似圆 %d 个:"
                                    (length clusters) nCircle))

                (foreach c circles
                    (setq cx (nth 0 c))
                    (setq cy (nth 1 c))
                    (setq dia (nth 2 c))
                    (setq diaMM (alt2a_uu2mm dia))
                    (setq hit (alt2a_keepoutAt kps cx cy tol))
                    (when hit (setq nKp (nKp + 1)))
                    (setq c (append c (list hit)))
                    (alt2a_log (sprintf nil "    @ (%9.3f, %9.3f)  外轮廓 D=%8.3f (=%.3f mm)  keepout=%s"
                                        cx cy dia (if diaMM diaMM 0.0)
                                        (if hit "YES" "no")))
                    (alt2a_csvline (sprintf nil "%s,%s,%.4f,%.4f,%.4f,%s,%s"
                                            (axlCurrentDesign) "candidate" cx cy
                                            (if diaMM diaMM 0.0)
                                            (if hit "KEEPOUT" "-") ""))

                    ;; 判定为"缺定位孔"
                    (if (and (not (alt2a_diaOK dia)) hit)
                        (alt2a_log (sprintf nil "      -- keepout 命中但孔径 %.3fmm 超出 %.2f~%.2fmm 范围, 已跳过"
                                            (if diaMM diaMM 0.0) (alt2a_cfg 'minDiaMM) (alt2a_cfg 'maxDiaMM)))
                        nil)
                    (when (and (or hit (not (alt2a_cfg 'requireKeepout)))
                               (alt2a_diaOK dia))
                        (setq nHole (nHole + 1))
                        (setq confirmed (cons (list cx cy dia (nth 3 c)) confirmed))
                        (alt2a_log (sprintf nil "      => 认定为缺失定位孔, 生成 %s 上 D=%.3fmm 的 shape"
                                            (alt2a_cfg 'outLayer) (if diaMM diaMM 0.0)))
                        (if doFix
                            (progn
                                (setq polyRes (errset (alt2a_makeCutout cx cy dia) t))
                                (if (and polyRes (car polyRes))
                                    (progn
                                        (setq nMade (nMade + 1))
                                        (setq alt2aChanged t)
                                        (setq alt2aModList (cons (axlCurrentDesign) alt2aModList))
                                        (alt2a_log "      ++ 已生成 CUTOUT shape")
                                        (alt2a_csvline (sprintf nil "%s,%s,%.4f,%.4f,%.4f,%s,%s"
                                                                (axlCurrentDesign) "cutout" cx cy
                                                                (if diaMM diaMM 0.0)
                                                                (alt2a_cfg 'outLayer) "")))
                                    (progn
                                        (setq nErr (nErr + 1))
                                        (alt2a_log "      !! 生成 CUTOUT 失败"))))
                            (alt2a_log "      (scan 模式, 未生成)"))))

                ;; 按需删掉源闭合线(只删落在已确认孔范围内的)
                (when (and doFix (alt2a_cfg 'deleteOriginal) confirmed)
                    (foreach c confirmed
                        (foreach tk paths
                            (when (alt2a_bbTouch (cadr tk) (nth 3 c) 0.5)
                                (errset (axlDeleteObject (car tk)) t)))))))

        ;; 保存
        (when (and doFix alt2aChanged)
            (if (axlSaveDesign ?noConfirm t)
                (alt2a_log "  .. 已保存 drawing")
                (progn
                    (setq nErr (nErr + 1))
                    (alt2a_log "  !! 保存失败"))))

        (alt2a_log (sprintf nil "  小结: 圆 %d, 有 keepout %d, 认定缺失定位孔 %d, 已生成 %d, 错误 %d"
                            nCircle nKp nHole nMade nErr))
        (list nCircle nKp nHole nMade nErr)))

;;; ---------------------------------------------------------------------------
;;; 输出文件初始化/收尾 (由 .scr 先 cfgset 路径, 再由 PowerShell 收尾写 modified)
;;; ---------------------------------------------------------------------------

(procedure (alt2a_begin)
    (setq alt2aChanged nil)
    (setq alt2aModList nil)
    (when (and (alt2a_cfg 'report) (neq (alt2a_cfg 'report) ""))
        (setq alt2aReport (outfile (alt2a_cfg 'report) "a")))
    (when (and (alt2a_cfg 'csv) (neq (alt2a_cfg 'csv) ""))
        (setq alt2aCSV (outfile (alt2a_cfg 'csv) "a"))))

(procedure (alt2a_end)
    (when (and alt2aModList (alt2a_cfg 'modified) (neq (alt2a_cfg 'modified) ""))
        (let (mport nm)
            (setq mport (outfile (alt2a_cfg 'modified) "a"))
            (when mport
                (foreach nm (reverse alt2aModList)
                    (fprintf mport "%s\n" nm))
                (close mport))))
    (when alt2aReport (close alt2aReport) (setq alt2aReport nil))
    (when alt2aCSV (close alt2aCSV) (setq alt2aCSV nil)))

;;; 一条龙: (alt2a_run "scan"|"fix")  -- 自动 begin/end
(procedure (alt2a_run t_action)
    (let (r)
        (alt2a_begin)
        (setq r (alt2a_current t_action))
        (alt2a_end)
        r))

;;; ---------------------------------------------------------------------------
;;; 单会话批处理: 在"同一个" Allegro 里连跑整个库, 不反复开关窗口
;;; ---------------------------------------------------------------------------

;;; 打开一张图。要点:
;;;   * 先用 axlKillDesign 无确认地丢掉当前图, 避免"是否保存"模态框
;;;   * 用 ?mode "wl" (写 + 不加锁) + ?ignoreLock t
;;;     既不会生成 .dra.lck, 也能忽略别人/上次残留的 .lck ——
;;;     实测残留 .lck 会让打开动作弹模态框从而"卡住不报错"
(procedure (alt2a_openDra dra)
    (let (r)
        (errset (axlKillDesign) t)
        (setq r (errset (axlOpenDesign ?design dra ?mode "wl" ?ignoreLock t ?noMru t) t))
        (if r (car r) nil)))

;;; 'only 命中判断(nil 或空表 = 全部通过)
(procedure (alt2a_onlyOK f)
    (let (pats hit nm)
        (setq pats (alt2a_cfg 'only))
        (if (null pats)
            t
            (progn
                (setq nm (lowerCase f))
                (foreach p pats
                    (when (rexMatchp p nm) (setq hit t)))
                hit))))

;;; (alt2a_librun "<lib目录>" "scan"|"fix") -- 单会话处理整个库
;;; 返回 (文件数 命中孔数 已生成数 失败数)
(procedure (alt2a_librun t_libDir t_action)
    (let (doFix dir files f full n nOpen ok nCircle nKp nHole nMade nErr r)
        (setq dir (axlOSSlash t_libDir))
        (setq doFix (equal (lowerCase t_action) "fix"))
        (setq n 0)
        (setq nOpen 0)
        (setq nCircle 0)
        (setq nKp 0)
        (setq nHole 0)
        (setq nMade 0)
        (setq nErr 0)

        (alt2a_begin)
        (alt2a_log "================================================================")
        (alt2a_log (sprintf nil "单会话批处理  action=%s" (if doFix "FIX" "SCAN")))
        (alt2a_log (sprintf nil "lib = %s" dir))
        (alt2a_log "================================================================")

        (setq files (getDirFiles dir))
        (foreach f files
            (when (and (rexMatchp "\\.dra$" (lowerCase f))
                       (alt2a_onlyOK f))
                (setq full (if (rexMatchp "/" f) f (strcat dir "/" f)))
                (setq n (n + 1))
                (setq ok (alt2a_openDra full))
                (if ok
                    (progn
                        (setq nOpen (nOpen + 1))
                        (setq r (errset (alt2a_current (if doFix "fix" "scan")) t))
                        (if r
                            (progn
                                (setq nCircle (nCircle + (nth 0 (car r))))
                                (setq nKp     (nKp     + (nth 1 (car r))))
                                (setq nHole   (nHole   + (nth 2 (car r))))
                                (setq nMade   (nMade   + (nth 3 (car r))))
                                (setq nErr    (nErr    + (nth 4 (car r)))))
                            (progn
                                (setq nErr (nErr + 1))
                                (alt2a_log (sprintf nil "[FAIL] 处理异常: %s" f)))))
                    (progn
                        (setq nErr (nErr + 1))
                        (alt2a_log (sprintf nil "[FAIL] 打不开: %s" full))))))

        (alt2a_log "================================================================")
        (alt2a_log (sprintf nil ".dra 总数 %d, 打开成功 %d" n nOpen))
        (alt2a_log (sprintf nil "圆 %d, 有 keepout %d, 认定缺失定位孔 %d, 已生成 %d, 错误 %d"
                            nCircle nKp nHole nMade nErr))
        (alt2a_log "================================================================")
        (alt2a_end)
        (list n nOpen nHole nMade nErr)))

(printf "\n[alt2a_locator_hole] loaded.\n")
(printf "  单会话(推荐, 只开一次 Allegro):\n")
(printf "    (alt2a_librun \"<lib目录>\" \"scan\")   /  \"fix\"\n")
(printf "  当前打开的那张图:\n")
(printf "    (alt2a_run \"scan\")  /  (alt2a_run \"fix\")\n")
