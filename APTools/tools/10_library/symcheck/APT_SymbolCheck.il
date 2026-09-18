;;; ============================================================================
;;; APT_SymbolCheck.il  --  工具② 符号封装一致性检查
;;; 阶段: 10_library (封装)      子菜单: 符号封装一致性
;;; ----------------------------------------------------------------------------
;;; 要解决的问题(来源: 嘉立创/AD 转过来的库)
;;;   * 同名封装有多个几何不同的变体(c0402 与 c0402_1..c0402_4), 复用库时抓错就用错
;;;   * .dra 改了但没重编, 或者根本没有 .psm —— 而 Allegro 用的是 psmpath 上的 .psm
;;;   * 板上用到某封装, 但当前 psmpath 里找不到对应 .psm(换机器/换库就炸)
;;;   * 位号缺失或重复
;;;
;;; 本工具只做"检测 + 报告", 不做任何自动修改。
;;;
;;; 两个命令
;;;   apt_symchk  检查当前图   —— 逐封装汇总(用了几次/引脚数/位号), 并核对
;;;                              该封装名在 psmpath 上有没有 .psm
;;;   apt_symlib  检查封装库... —— 选一个 .dra 所在目录, 找同名多变体、
;;;                              哪些 .dra 没有 .psm、哪些 .psm 不在 psmpath 上
;;;
;;; 为什么用 axlDMLibraryFileNames 而不是直接列目录
;;;   Allegro 放置封装时是按 psmpath 找 .psm 的。只看目录会漏掉"文件在、
;;;   但路径没配"这种情况 —— 那才是换电脑后打不开封装的真正原因。
;;;
;;; 关于"符号"这一侧
;;;   真正的原理图符号在 OrCAD Capture 的 .OLB 里, Allegro SKILL 读不到。
;;;   板上能拿到的是器件实例: sym->name(封装名) / sym->refdes / sym->device。
;;;   所以这里核对的是"板 vs 库"这一层。若要把 Capture 符号也纳进来,
;;;   得走 device 文件(.txt, axlWriteDeviceFile 可导出)那条路, 见文件末尾的待办。
;;;
;;; 编码: 必须 GBK(cp936)。
;;; ============================================================================

(defvar apt_symcheck_submenu nil)
(setq apt_symcheck_submenu "符号封装一致性")

;;; ---------------------------------------------------------------------------
;;; 本地字符串小工具
;;;   SKILL 的 substring 是 1 起算的, 且索引 0 会直接报错, 所以包一层。
;;; ---------------------------------------------------------------------------
(procedure (apt_syCh t_s t_i)
    (let (n)
        (setq n (strlen t_s))
        (if (or (t_i < 0) (t_i >= n)) "" (substring t_s (t_i + 1) 1))))

;;; 取路径最后一段(去掉目录)
(procedure (apt_syBare t_s)
    (let (n i ch last out)
        (setq n (strlen t_s))
        (setq last -1)
        (setq i 0)
        (while (i < n)
            (setq ch (apt_syCh t_s i))
            (when (or (equal ch "/") (equal ch "\\"))
                (setq last i))
            (setq i (i + 1)))
        (substring t_s (last + 2) (n - last - 1))))

;;; 去掉扩展名(.xxx)
(procedure (apt_syNoExt t_s)
    (let (n i ch dot)
        (setq n (strlen t_s))
        (setq dot -1)
        (setq i 0)
        (while (i < n)
            (setq ch (apt_syCh t_s i))
            (when (equal ch ".") (setq dot i))
            (setq i (i + 1)))
        (if (dot < 0) t_s (substring t_s 1 dot))))

;;; 去掉变体后缀 _<数字>: c0402_1 -> c0402
(procedure (apt_syBase t_s)
    (let (n i ch us allDig cut)
        (setq n (strlen t_s))
        (setq us -1)
        (setq i 0)
        (while (i < n)
            (setq ch (apt_syCh t_s i))
            (when (equal ch "_") (setq us i))
            (setq i (i + 1)))
        (if (us < 0)
            t_s
            (progn
                ;; 下划线后面必须全是数字, 才算变体后缀
                (setq allDig t)
                (setq cut (us + 1))
                (while (cut < n)
                    (unless (rexMatchp "[0-9]" (apt_syCh t_s cut))
                        (setq allDig nil))
                    (setq cut (cut + 1)))
                (if (and allDig ((us + 1) < n))
                    (substring t_s 1 us)
                    t_s)))))

;;; 判断字符串是否在列表里(不用 member, 各版本行为一致些)
(procedure (apt_syHas t_lst t_x)
    (let (hit)
        (setq hit nil)
        (foreach x t_lst (when (equal x t_x) (setq hit t)))
        hit))

;;; 用 key 替换一条记录
(procedure (apt_syRepl t_rows t_key t_new)
    (let (out)
        (setq out nil)
        (foreach r t_rows
            (if (equal (car r) t_key)
                (setq out (append out (list t_new)))
                (setq out (append out (list r)))))
        out))

;;; ---------------------------------------------------------------------------
;;; psmpath 上能看到的 .psm 名字集合(只留文件名, 便于比对)
;;;   axlDMLibraryFileNames 的参数在文档里写作 ALLEGRO_PACKAGE_DB,
;;;   字符串/符号两种写法都试一次, 拿不到就返回 nil(后续检查自动跳过)。
;;; ---------------------------------------------------------------------------
(procedure (apt_symPsmNames)
    (let (raw names)
        (setq raw (car (errset (axlDMLibraryFileNames "ALLEGRO_PACKAGE_DB") nil)))
        (unless raw
            (setq raw (car (errset (axlDMLibraryFileNames 'ALLEGRO_PACKAGE_DB) nil))))
        (setq names nil)
        (foreach f raw
            (when (stringp f)
                (setq names (append names (list (upperCase (apt_syNoExt (apt_syBare f))))))))
        names))

;;; ---------------------------------------------------------------------------
;;; 板级检查
;;;   返回 (符号数 封装种类数 引脚不一致数 缺位号数 重复位号数 库里找不到数)
;;; ---------------------------------------------------------------------------
(procedure (apt_symBoard t_csv)
    (let (syms rows nm pins hit cnt pdiff samp rd seen miss dup psm bad nPin nMiss nDup nBad nSym rec csvRows nMech)
        (setq syms (axlDBGetDesign)->symbols)
        (setq nSym (length syms))
        (setq rows nil)
        (setq seen nil)
        (setq miss nil)
        (setq dup nil)
        (setq nMech 0)

        (foreach s syms
            (setq nm (s->name))
            (setq pins (length (s->pins)))
            (if (null nm) (setq nm "(无名)"))
            (setq hit nil)
            (foreach rec rows (when (equal (car rec) nm) (setq hit rec)))
            (if hit
                (progn
                    (setq cnt ((nth 1 hit) + 1))
                    (setq pdiff (nth 3 hit))
                    (unless (equal (nth 2 hit) pins) (setq pdiff t))
                    (setq rows (apt_syRepl rows nm
                                (list nm cnt (nth 2 hit) pdiff (nth 4 hit)))))
                (setq rows (append rows (list (list nm 1 pins nil (s->refdes))))))
            ;; 位号: 0 引脚的符号(logo/机械件)本来就不需要位号, 单独计, 不算缺
            (setq rd (s->refdes))
            (if (or (null rd) (equal rd ""))
                (if (pins > 0)
                    (setq miss (append miss (list nm)))
                    (setq nMech (nMech + 1)))
                (if (apt_syHas seen rd)
                    (setq dup (append dup (list rd)))
                    (setq seen (append seen (list rd))))))

        (setq nPin 0)
        (foreach rec rows (when (nth 3 rec) (setq nPin (nPin + 1))))
        (setq nMiss (length miss))
        (setq nDup (length dup))

        ;; 板上用到的封装名, 在 psmpath 上找不找得到
        (setq psm (apt_symPsmNames))
        (setq bad nil)
        (foreach rec rows
            (when (and psm (null (apt_syHas psm (upperCase (car rec)))))
                (setq bad (append bad (list (car rec))))))
        (setq nBad (length bad))

        ;; ---- 控制台报告 ----
        (printf "\n[APTools] ===== 符号封装一致性(当前图) =====\n")
        (printf "[APTools] 器件 %d 个, 封装 %d 种\n" nSym (length rows))
        (printf "[APTools]   -- 逐封装汇总(按使用次数排序) --\n")
        (foreach rec (apt_symSortByCnt rows)
            (printf "[APTools]     %-34s x%-3d 引脚 %-3d %s\n"
                    (car rec) (nth 1 rec) (nth 2 rec)
                    (if (nth 3 rec) "<不一致!>" "")))
        (when (nPin > 0)
            (printf "[APTools] !! 有 %d 种封装出现引脚数不一致(同名变体抓错或被改过)\n" nPin))
        (when (nMiss > 0)
            (printf "[APTools] !! 有 %d 个器件缺位号\n" nMiss)
            (foreach m miss (printf "[APTools]      %s\n" m)))
        (when (nMech > 0)
            (printf "[APTools] (另有 %d 个 0 引脚符号(logo/机械件), 不计入缺位号)\n" nMech))
        (when (nDup > 0)
            (printf "[APTools] !! 有 %d 个重复位号: %L\n" nDup dup))
        (if (null psm)
            (printf "[APTools] (取不到 psmpath 上的 .psm 列表, 跳过封装存在性核对)\n")
            (progn
                (printf "[APTools] psmpath 上共有 %d 个 .psm\n" (length psm))
                (when (nBad > 0)
                    (printf "[APTools] !! 板上 %d 种封装不在 psmpath 上(重新放置/刷新封装、或换台机器打开时会找不到):\n" nBad)
                    (foreach b bad (printf "[APTools]      %s\n" b)))))

        ;; ---- CSV ----
        ;; 注意: foreach 不返回列表, 必须自己 append 收集
        (when t_csv
            (setq csvRows nil)
            (foreach rec rows
                (setq csvRows (append csvRows (list
                    (list (car rec) (sprintf nil "%d" (nth 1 rec)) (sprintf nil "%d" (nth 2 rec))
                          (if (nth 3 rec) "不一致" "")
                          (if (nth 4 rec) (nth 4 rec) "")
                          (if (null psm) "?"
                              (if (apt_syHas psm (upperCase (car rec))) "是" "否")))))))
            (apt_symCsv t_csv "封装,使用次数,引脚数,引脚不一致,位号样例,在psmpath上" csvRows))

        (list nSym (length rows) nPin nMiss nDup nBad)))

;;; 按使用次数排序(简单选择排序, 列表不长)
;;;   比较先取到局部变量里再做中缀, 不把函数调用直接放中缀左边
(procedure (apt_symSortByCnt t_rows)
    (let (rest out best bi i ca cb)
        (setq rest t_rows)
        (setq out nil)
        (while rest
            (setq best (car rest))
            (setq bi 0)
            (setq i 0)
            (foreach r rest
                (setq ca (nth 1 r))
                (setq cb (nth 1 best))
                (when (ca > cb)
                    (setq best r)
                    (setq bi i))
                (setq i (i + 1)))
            (setq out (append out (list best)))
            (setq rest (apt_symDrop rest bi)))
        out))

(procedure (apt_symDrop t_lst t_i)
    (let (out i)
        (setq out nil)
        (setq i 0)
        (foreach x t_lst
            (unless (equal i t_i) (setq out (append out (list x))))
            (setq i (i + 1)))
        out))

;;; 简单 CSV 写盘(不依赖框架的 apt_csvline, 免得耦合)
(procedure (apt_symCsv t_path t_head t_rows)
    (let (p)
        (setq p (car (errset (outfile t_path "w") nil)))
        (if p
            (progn
                (fprintf p "%s\n" t_head)
                (foreach r t_rows
                    (fprintf p "%s,%s,%s,%s,%s,%s\n"
                             (nth 0 r) (nth 1 r) (nth 2 r) (nth 3 r) (nth 4 r) (nth 5 r)))
                (close p)
                (printf "[APTools] 报告已写出: %s\n" t_path))
            (printf "[APTools] 报告写入失败: %s\n" t_path))))

;;; ---------------------------------------------------------------------------
;;; 库级检查: 同名多变体 / .dra 没有 .psm / .psm 不在 psmpath 上
;;; ---------------------------------------------------------------------------
(procedure (apt_symLib t_dir t_csv)
    (let (files dra variants nm base hit cnt psm badNoPsm badPath names csvRows)
        (setq files (car (errset (getDirFiles t_dir) nil)))
        (setq dra nil)
        (foreach f files
            (when (and (stringp f) (rexMatchp ".dra$" (lowerCase f)))
                (setq dra (append dra (list f)))))
        (setq psm (apt_symPsmNames))

        ;; ---- 同名多变体 ----
        (setq variants nil)
        (foreach f dra
            (setq nm (apt_syNoExt f))
            (setq base (apt_syBase nm))
            (setq hit nil)
            (foreach rec variants (when (equal (car rec) base) (setq hit rec)))
            (if hit
                (progn
                    (setq cnt ((nth 1 hit) + 1))
                    (setq variants (apt_syRepl variants base
                                     (list base cnt (append (nth 2 hit) (list nm))))))
                (setq variants (append variants (list (list base 1 (list nm)))))))

        ;; ---- .dra 没有 .psm / .psm 不在 psmpath ----
        (setq badNoPsm nil)
        (setq badPath nil)
        (setq names nil)
        (foreach f dra
            (setq nm (upperCase (apt_syNoExt f)))
            (setq names (append names (list nm)))
            (if (null psm)
                nil
                (if (apt_syHas psm nm)
                    nil
                    (progn
                        (setq badNoPsm (append badNoPsm (list nm)))))))

        ;; ---- 报告 ----
        (printf "\n[APTools] ===== 符号封装一致性(封装库) =====\n")
        (printf "[APTools] 目录: %s\n" t_dir)
        (printf "[APTools] 目录下 .dra %d 个\n" (length dra))
        (when psm (printf "[APTools] psmpath 上 .psm %d 个\n" (length psm)))

        (printf "[APTools]   -- 同名多变体(库里同名不同几何, 容易抓错) --\n")
        (setq cnt 0)
        (foreach rec variants
            (when ((nth 1 rec) > 1)
                (setq cnt (cnt + 1))
                (printf "[APTools]     %s  x%d: %L\n" (car rec) (nth 1 rec) (nth 2 rec))))
        (when (equal cnt 0) (printf "[APTools]     (没有)\n"))

        (printf "[APTools]   -- .dra 在 psmpath 上找不到同名 .psm (共 %d 个) --\n" (length badNoPsm))
        (if (null psm)
            (printf "[APTools]     (取不到 .psm 列表, 跳过)\n")
            (progn
                (foreach nm badNoPsm (printf "[APTools]     %s\n" nm))
                (when (equal (length badNoPsm) 0) (printf "[APTools]     (没有)\n"))))

        (when t_csv
            (setq csvRows nil)
            (foreach rec variants
                (setq csvRows (append csvRows (list
                    (list (car rec) (sprintf nil "%d" (nth 1 rec))
                          (apt_syJoin (nth 2 rec) " ")
                          (if (null psm) "?"
                              (if (apt_syHas psm (upperCase (car rec))) "是" "否")))))))
            (apt_symCsv t_csv "封装,变体数,变体列表,psmpath上有psm" csvRows))

        (list (length dra) cnt (length badNoPsm) (length names))))

;;; 列表拼成字符串
(procedure (apt_syJoin t_lst t_sep)
    (let (out first)
        (setq out "")
        (setq first t)
        (foreach x t_lst
            (if first
                (progn (setq out (strcat out x)) (setq first nil))
                (setq out (strcat out t_sep x))))
        out))

;;; ---------------------------------------------------------------------------
;;; 命令
;;; ---------------------------------------------------------------------------
(procedure (apt_cmd_symchk)
    (let (r csv)
        (setq csv (strcat apt_home "/Temp/apt_symcheck_board.csv"))
        (setq r (apt_symBoard csv))
        (axlUIConfirm (sprintf nil
            "符号封装一致性(当前图)\n\n器件 %d 个, 封装 %d 种\n\n引脚数不一致 : %d 种\n缺位号       : %d 个\n重复位号     : %d 个\npsmpath 上找不到封装 : %d 种\n\n详细清单见命令窗口; 报告: APTools/Temp/apt_symcheck_board.csv"
            (nth 0 r) (nth 1 r) (nth 2 r) (nth 3 r) (nth 4 r) (nth 5 r)))))

(procedure (apt_cmd_symlib)
    (let (d r csv start ld)
        ;; apt_libDir 是定位孔工具用的会话级全局; 未绑定时直接读会报错, 所以走 errset
        (setq ld (car (errset apt_libDir nil)))
        (setq start (if ld ld (apt_workDir)))
        (setq d (axlDMDirectoryBrowse start t
                                      ?title "选择封装库目录(.dra 所在目录)"))
        (when d
            (setq apt_libDir d)
            (setq csv (strcat apt_home "/Temp/apt_symcheck_lib.csv"))
            (setq r (apt_symLib d csv))
            (axlUIConfirm (sprintf nil
                "符号封装一致性(封装库)\n\n目录: %s\n\n.dra 共 %d 个\n同名多变体 %d 组\npsmpath 上找不到 .psm 的 %d 个\n\n详细清单见命令窗口; 报告: APTools/Temp/apt_symcheck_lib.csv"
                d (nth 0 r) (nth 1 r) (nth 2 r))))))

(procedure (apt_cmd_symrule)
    (printf "\n[APTools] ===== 符号封装一致性 检查说明 =====\n")
    (printf "[APTools] 板级(apt_symchk):\n")
    (printf "    1. 同一封装名出现不同引脚数 -> 同名变体抓错或封装被改过\n")
    (printf "    2. 器件缺位号 / 位号重复\n")
    (printf "    3. 板上用到的封装名在 psmpath 上有没有 .psm(换机器/换库会炸)\n")
    (printf "[APTools] 库级(apt_symlib):\n")
    (printf "    1. 同名多变体: c0402 与 c0402_1/_2... 并存\n")
    (printf "    2. .dra 在 psmpath 上找不到同名 .psm(没重编, 或库路径没配)\n")
    (printf "[APTools] 本工具只检测+报告, 不修改任何东西。\n")
    (printf "[APTools] 待办: 把原理图符号(Capture .OLB)纳进来需要走 device 文件那条路\n")
    (printf "         (axlWriteDeviceFile 可导出 compdef 的 device 文件再比对引脚), Allegro\n")
    (printf "         SKILL 读不到 .OLB。\n"))

(axlCmdRegister "apt_symchk"  'apt_cmd_symchk  ?cmdType "general")
(axlCmdRegister "apt_symlib"  'apt_cmd_symlib  ?cmdType "general")
(axlCmdRegister "apt_symrule" 'apt_cmd_symrule ?cmdType "general")

(apt_menuSub    "10_library" apt_symcheck_submenu "检查当前图"      "apt_symchk")
(apt_menuSub    "10_library" apt_symcheck_submenu "检查封装库..."   "apt_symlib")
(apt_menuSubSep "10_library" apt_symcheck_submenu)
(apt_menuSub    "10_library" apt_symcheck_submenu "查看检查说明"    "apt_symrule")

(printf "[APTools] APT_SymbolCheck 已加载 (apt_symchk / apt_symlib / apt_symrule)\n")
