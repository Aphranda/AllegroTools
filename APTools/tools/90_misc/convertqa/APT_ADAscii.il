;;; ============================================================================
;;; APT_ADAscii.il  --  转换核对: AD ASCII(.pcbdoc) 前置检查 / 删除空封装元件
;;; 阶段: 90_misc (辅助功能)      子菜单: 转换核对
;;; ----------------------------------------------------------------------------
;;; 为什么要在 ASCII 上查, 而不是转换后在 Allegro 里补救
;;;   Allegro 的 altium2pcb 转换器在 text blocks 阶段会对 nil 调 upperCase 崩掉,
;;;   触发条件是 ASCII 里存在 PATTERN(封装名)为空的 Component(本工程是测试点
;;;   T1~T4)。所以这一关必须在**转换之前**、在 AD 导出的 ASCII 源文件上过。
;;;
;;; 两个功能(检查与删除分开)
;;;   apt_adchk   检查: 记录类型统计 / PATTERN 为空的元件 / 没有任何焊盘的元件 /
;;;               非 ASCII 字符所在行 / 结论(能否直接导入)
;;;   apt_adfix   删除: 把 PATTERN 为空的 Component 记录去掉, **写出一个新文件**
;;;               (原名-fixed.pcbdoc), 原件一个字节都不动; 先列清单并确认
;;;
;;; 删的到底是什么(与 kit 里 altium_ascii_tool.py fix 一致)
;;;   只丢掉 |RECORD=Component|... 那一条记录本身, 焊盘/走线等其它记录一律保留。
;;;   也就是说这是纯文本层面的块过滤, 不做级联删除。
;;;
;;; 实现要点(11.6 MB / 14200 行 / 最长单行 849 KB 的实测文件)
;;;   * 记录以 |RECORD= 开头, 但**一条记录可以跨多行**(实测 1974 行是续行),
;;;     所以按"行以 |RECORD= 开头 = 新记录开始"来组装。
;;;   * 只有 Component / Pad 这类短记录才逐字符解析; 长记录(多边形等)只取类别名,
;;;     扫 40 个字符就够 —— 否则 849 KB 的行做逐字符扫描会慢到不可用。
;;;
;;; 编码: 必须 GBK(cp936)。
;;; ============================================================================

(defvar apt_ad_submenu nil)
(setq apt_ad_submenu "转换核对")

(defvar apt_adLastFile nil)      ; 上次选的文件, 下次做默认值

;;; ---------------------------------------------------------------------------
;;; 字符串工具
;;;   SKILL 的 substring 是 1 起算的, 索引 0 会报错, 所以统一包一层。
;;; ---------------------------------------------------------------------------
(procedure (apt_adCh t_s t_i)
    (let (n)
        (setq n (strlen t_s))
        (if (or (t_i < 0) (t_i >= n)) "" (substring t_s (t_i + 1) 1))))

(procedure (apt_adSub t_s t_i t_len)
    (let (n)
        (setq n (strlen t_s))
        (if (or (t_i < 0) (t_len < 1) (t_i >= n))
            ""
            (substring t_s (t_i + 1) (apt_min2 t_len (n - t_i))))))

(procedure (apt_adStarts t_s t_pre)
    (let (n m)
        (setq n (strlen t_s))
        (setq m (strlen t_pre))
        (if (n < m) nil (equal (apt_adSub t_s 0 m) t_pre))))

;;; 从 t_from 起找 "|", 返回位置(0 起算); 超过 t_max 还没找到就返回 -1
;;;   t_max 用来限制扫描长度 —— 长记录只关心开头那几十个字符
(procedure (apt_adBar t_s t_from t_max)
    (let (i hit ch n)
        (setq n (strlen t_s))
        (setq i t_from)
        (setq hit -1)
        (while (and (equal hit -1) (i < n) (i < (t_from + t_max)))
            (setq ch (apt_adCh t_s i))
            (when (equal ch "|") (setq hit i))
            (setq i (i + 1)))
        hit))

;;; 记录类别: 形如 |RECORD=Component|... 取 "Component"
(procedure (apt_adKind t_line)
    (let (pre b)
        (setq pre "|RECORD=")
        (if (apt_adStarts t_line pre)
            (progn
                (setq b (apt_adBar t_line (strlen pre) 60))
                (if (equal b -1) nil (apt_adSub t_line (strlen pre) (b - (strlen pre)))))
            nil)))

;;; 取 |KEY=VALUE| 里的值。要求 KEY 前一个字符是 "|" 或就在开头, 避免误匹配
;;; 别的以 KEY 结尾的属性名。找不到返回 nil。
(procedure (apt_adProp t_rec t_key)
    (let (n m i hit ch prev eq v b res)
        (setq n (strlen t_rec))
        (setq m (strlen t_key))
        (setq i 0)
        (setq hit -1)
        (while (and (equal hit -1) ((i + m) < n))
            (when (equal (apt_adSub t_rec i m) t_key)
                (setq prev (if (equal i 0) "|" (apt_adCh t_rec (i - 1))))
                (setq eq (apt_adCh t_rec (i + m)))
                (when (and (equal prev "|") (equal eq "="))
                    (setq hit i)))
            (setq i (i + 1)))
        (when (not (equal hit -1))
            (setq v (hit + m + 1))
            (setq b (apt_adBar t_rec v 200000))
            (setq res (if (equal b -1) (apt_adSub t_rec v (n - v)) (apt_adSub t_rec v (b - v)))))
        res))

;;; 空值判定: nil 或 全是空白
;;;   控制字符也算空白 —— 关键就是这一条: gets 会把行尾的 \r 带进值里,
;;;   于是 "PATTERN=" 正好在记录末尾时取到的是 "\r", 不这样判就会误判成
;;;   "非空", 漏掉本该删掉的空封装元件。
;;;   (判控制字符用正则 [^ -~], 不写 "\r" 字面量 —— SKILL 的 \r 转义不生效)
(procedure (apt_adBlank t_s)
    (let (n i ch blank)
        (if (null t_s)
            t
            (progn
                (setq n (strlen t_s))
                (setq i 0)
                (setq blank t)
                (while (i < n)
                    (setq ch (apt_adCh t_s i))
                    (unless (or (equal ch " ") (equal ch "\t")
                                (rexMatchp "[^ -~]" ch))
                        (setq blank nil))
                    (setq i (i + 1)))
                blank))))

;;; ---------------------------------------------------------------------------
;;; 扫描整个 ASCII 文件
;;;   返回 (记录总数 assoc类别表 元件表 焊盘计数表 含非ASCII的行数)
;;;     类别表   (("Component" . 263) ...)
;;;     元件表   ((designator id pattern x y) ...)
;;;     焊盘表   (("id" . 焊盘数) ...)
;;; ---------------------------------------------------------------------------
(procedure (apt_adScan t_file)
    (let (p ln rec kind kinds comps pads hic nRec id ds pat x y hit cnt cur newList chk nchk)
        (setq p (car (errset (infile t_file) nil)))
        (if (null p)
            (progn
                (printf "[APTools] 打不开文件: %s\n" t_file)
                nil)
            (progn
                (setq kinds nil)
                (setq comps nil)
                (setq pads nil)
                (setq hic 0)
                (setq nRec 0)
                (setq rec nil)
                (setq ln "")
                (setq ln (gets ln p))
                (while ln
                    ;; 含非 ASCII 字符的行(GBK 中文等)计数
                    ;;   三个坑:
                    ;;   1) 别写 [\200-\377] —— SKILL 的 ed 风格正则里 \2 是反向引用,
                    ;;      这种八进制范围不生效, 会几乎匹配所有行。
                    ;;   2) gets 会**保留行尾的 \r**(写出时靠它保住 CRLF), 而 \r 是
                    ;;      控制字符, 直接用 [^ -~] 判会每行都中。
                    ;;   3) "\r" 字面量在 SKILL 里不生效, 所以用"行尾是非打印字符"
                    ;;      来判断并去掉它。
                    (setq chk ln)
                    (setq nchk (strlen chk))
                    (when (and (nchk > 0) (rexMatchp "[^ -~]$" chk))
                        (setq chk (apt_adSub chk 0 (nchk - 1))))
                    (when (rexMatchp "[^ -~]" chk) (setq hic (hic + 1)))
                    (setq kind (apt_adKind ln))
                    (if kind
                        (progn
                            ;; 新记录开始: 先把上一条收尾
                            (when rec
                                (setq nRec (nRec + 1))
                                (setq kind (apt_adKind rec))
                                (when kind
                                    (setq hit nil)
                                    (foreach kv kinds (when (equal (car kv) kind) (setq hit kv)))
                                    (if hit
                                        (setq kinds (apt_adReplace kinds kind (list kind ((nth 1 hit) + 1))))
                                        (setq kinds (append kinds (list (list kind 1)))))
                                    ;; Component: 记 designator/id/pattern/坐标
                                    (when (equal kind "Component")
                                        (setq id (apt_adProp rec "ID"))
                                        (setq ds (apt_adProp rec "SOURCEDESIGNATOR"))
                                        (setq pat (apt_adProp rec "PATTERN"))
                                        (setq x (apt_adProp rec "X"))
                                        (setq y (apt_adProp rec "Y"))
                                        (setq comps (append comps (list (list ds id pat x y)))))
                                    ;; Pad: 统计它属于哪个元件(COMPONENT=<id>)
                                    (when (equal kind "Pad")
                                        (setq id (apt_adProp rec "COMPONENT"))
                                        (setq hit nil)
                                        (foreach kv pads (when (equal (car kv) id) (setq hit kv)))
                                        (if hit
                                            (setq pads (apt_adReplaceK pads id ((nth 1 hit) + 1)))
                                            (setq pads (append pads (list (list id 1))))))))
                            (setq rec ln))
                        ;; 续行: 并进当前记录
                        (when rec (setq rec (strcat rec "\n" ln))))
                    (setq ln (gets ln p)))
                ;; 收尾最后一条
                (when rec
                    (setq nRec (nRec + 1))
                    (setq kind (apt_adKind rec))
                    (when kind
                        (setq hit nil)
                        (foreach kv kinds (when (equal (car kv) kind) (setq hit kv)))
                        (if hit
                            (setq kinds (apt_adReplace kinds kind (list kind ((nth 1 hit) + 1))))
                            (setq kinds (append kinds (list (list kind 1)))))
                        (when (equal kind "Component")
                            (setq comps (append comps (list (list (apt_adProp rec "SOURCEDESIGNATOR")
                                                                  (apt_adProp rec "ID")
                                                                  (apt_adProp rec "PATTERN")
                                                                  (apt_adProp rec "X")
                                                                  (apt_adProp rec "Y"))))))))
                (close p)
                (list nRec kinds comps pads hic)))))

;;; assoc 表里换一条(键相同)
(procedure (apt_adReplace t_lst t_key t_new)
    (let (out)
        (setq out nil)
        (foreach kv t_lst
            (if (equal (car kv) t_key)
                (setq out (append out (list t_new)))
                (setq out (append out (list kv)))))
        out))

;;; 焊盘计数表换一条
(procedure (apt_adReplaceK t_lst t_key t_cnt)
    (apt_adReplace t_lst t_key (list t_key t_cnt)))

;;; 取 assoc 表里的值
(procedure (apt_adGet t_lst t_key)
    (let (hit)
        (setq hit nil)
        (foreach kv t_lst (when (equal (car kv) t_key) (setq hit kv)))
        (if hit (nth 1 hit) nil)))

;;; ---------------------------------------------------------------------------
;;; 检查报告。返回 (元件数 空封装数 无焊盘数 记录数)
;;; ---------------------------------------------------------------------------
(procedure (apt_adCheck t_file t_report)
    (let (r nRec kinds comps pads hic empty noPad e empties p msg)
        (printf "\n[APTools] ===== AD ASCII 前置检查 =====\n")
        (printf "[APTools] 文件: %s\n" t_file)
        (setq r (apt_adScan t_file))
        (if (null r)
            nil
            (progn
                (setq nRec (nth 0 r))
                (setq kinds (nth 1 r))
                (setq comps (nth 2 r))
                (setq pads (nth 3 r))
                (setq hic (nth 4 r))
                (printf "[APTools] 记录 %d 条; 含非 ASCII 字符的行 %d 行\n" nRec hic)
                (printf "[APTools]   -- 记录类型统计 --\n")
                (foreach kv (apt_adSortKinds kinds)
                    (printf "[APTools]     %-34s %d\n" (nth 0 kv) (nth 1 kv)))

                ;; PATTERN 为空的元件 -> Allegro 转换崩溃根因
                (setq empty nil)
                (foreach c comps
                    (when (apt_adBlank (nth 2 c))
                        (setq empty (append empty (list c)))))
                (printf "[APTools]   -- PATTERN 为空的元件(转换会在 text blocks 阶段崩) --\n")
                (if (null empty)
                    (printf "[APTools]     (无) 该文件应可直接导入\n")
                    (foreach c empty
                        (printf "[APTools]     designator=%-8s id=%-6s X=%s Y=%s\n"
                                (if (nth 0 c) (nth 0 c) "(空)")
                                (if (nth 1 c) (nth 1 c) "(空)")
                                (if (nth 3 c) (nth 3 c) "?")
                                (if (nth 4 c) (nth 4 c) "?"))))

                ;; 一个焊盘都没有的元件(空焊盘封装)
                (setq noPad nil)
                (foreach c comps
                    (setq e (if (nth 1 c) (apt_adGet pads (nth 1 c)) 0))
                    (unless e (setq e 0))
                    (when (e < 1)
                        (setq noPad (append noPad (list c)))))
                (printf "[APTools]   -- 没有任何焊盘的元件(空焊盘封装, 只报告不删) --\n")
                (if (null noPad)
                    (printf "[APTools]     (无)\n")
                    (foreach c noPad
                        (printf "[APTools]     designator=%-8s id=%-6s PATTERN=%s\n"
                                (if (nth 0 c) (nth 0 c) "(空)")
                                (if (nth 1 c) (nth 1 c) "(空)")
                                (if (nth 2 c) (nth 2 c) "(空)"))))
                (printf "[APTools] 结论(PATTERN 这一项): %s\n"
                        (if (null empty)
                            "PATTERN 无空缺 —— 这一项通过"
                            "先把 PATTERN 为空的元件清掉再导入(菜单: 删除空封装元件)"))
                (printf "[APTools] 注意: 本检查只覆盖 PATTERN 为空这一个根因。实测有一块板\n")
                (printf "        PATTERN 全部合格, 转换仍在 text blocks 之后对 nil 调 upperCase\n")
                (printf "        崩掉(PowerDetector 板)。那类问题看转换日志更直接, 典型两条:\n")
                (printf "          Unable to find device file for ...  -> 缺 device 文件\n")
                (printf "          axlDBCreateSymbol: Refdes not found -> 建符号时拿不到位号\n")

                (when t_report
                    (setq p (car (errset (outfile t_report "w") nil)))
                    (when p
                        (fprintf p "AD ASCII 前置检查报告\n文件: %s\n记录: %d\n非ASCII行: %d\n\n"
                                 t_file nRec hic)
                        (fprintf p "PATTERN 为空的元件: %d\n" (length empty))
                        (foreach c empty
                            (fprintf p "  DELETE designator=%s id=%s X=%s Y=%s\n"
                                     (if (nth 0 c) (nth 0 c) "")
                                     (if (nth 1 c) (nth 1 c) "")
                                     (if (nth 3 c) (nth 3 c) "")
                                     (if (nth 4 c) (nth 4 c) "")))
                        (fprintf p "\n没有焊盘的元件: %d\n" (length noPad))
                        (foreach c noPad
                            (fprintf p "  %s id=%s PATTERN=%s\n"
                                     (if (nth 0 c) (nth 0 c) "")
                                     (if (nth 1 c) (nth 1 c) "")
                                     (if (nth 2 c) (nth 2 c) "")))
                        (close p)
                        (printf "[APTools] 报告已写出: %s\n" t_report)))
                (list (length comps) (length empty) (length noPad) nRec)))))

;;; 类别表按次数排序(选择排序, 类别数不多)
(procedure (apt_adSortKinds t_lst)
    (let (rest out best bi i ca cb)
        (setq rest t_lst)
        (setq out nil)
        (while rest
            (setq best (car rest))
            (setq bi 0)
            (setq i 0)
            (foreach kv rest
                (setq ca (nth 1 kv))
                (setq cb (nth 1 best))
                (when (ca > cb) (setq best kv) (setq bi i))
                (setq i (i + 1)))
            (setq out (append out (list best)))
            (setq rest (apt_adDrop rest bi)))
        out))

(procedure (apt_adDrop t_lst t_i)
    (let (out i)
        (setq out nil)
        (setq i 0)
        (foreach x t_lst
            (unless (equal i t_i) (setq out (append out (list x))))
            (setq i (i + 1)))
        out))

;;; ---------------------------------------------------------------------------
;;; 删除: 把 PATTERN 为空的 Component 记录整条丢掉, 写一个新文件
;;;   只丢 Component 记录本身, 其它记录原样复制; 原件不动。
;;;   返回 (写入记录数 删除数 输出路径)
;;; ---------------------------------------------------------------------------
;;; 这条记录该丢掉吗? —— PATTERN 为空的 Component
(procedure (apt_adDropRec t_rec)
    (and (equal (apt_adKind t_rec) "Component")
         (apt_adBlank (apt_adProp t_rec "PATTERN"))))

(procedure (apt_adFixWrite t_file t_out)
    (let (pin pout ln rec wRec nDel)
        (setq pin (car (errset (infile t_file) nil)))
        (setq pout (car (errset (outfile t_out "w") nil)))
        (if (or (null pin) (null pout))
            (progn
                (printf "[APTools] 打开文件失败: in=%L out=%L\n" pin pout)
                nil)
            (progn
                (setq wRec 0)
                (setq nDel 0)
                (setq rec nil)
                (setq ln "")
                (setq ln (gets ln pin))
                (while ln
                    (if (apt_adKind ln)
                        ;; 新的一条记录开始: 先把上一条处理掉, 再开新的一条
                        (progn
                            (when rec
                                (if (apt_adDropRec rec)
                                    (progn
                                        (setq nDel (nDel + 1))
                                        (printf "[APTools]   删除元件 designator=%s id=%s\n"
                                                (let (d) (setq d (apt_adProp rec "SOURCEDESIGNATOR"))
                                                     (if d d "(空)"))
                                                (let (d) (setq d (apt_adProp rec "ID"))
                                                     (if d d "(空)"))))
                                    (progn
                                        (fprintf pout "%s" rec)
                                        (setq wRec (wRec + 1)))))
                            (setq rec ln))
                        ;; 续行: 并进当前记录(一条记录可以跨多行)
                        (when rec (setq rec (strcat rec "\n" ln))))
                    (setq ln (gets ln pin)))
                ;; 收尾最后一条
                (when rec
                    (if (apt_adDropRec rec)
                        (setq nDel (nDel + 1))
                        (progn
                            (fprintf pout "%s" rec)
                            (setq wRec (wRec + 1)))))
                (close pin)
                (close pout)
                (printf "[APTools] 已写出: %s (记录 %d 条, 删除 %d 条)\n" t_out wRec nDel)
                (list wRec nDel t_out)))))

;;; ---------------------------------------------------------------------------
;;; 选文件
;;; ---------------------------------------------------------------------------
(procedure (apt_adPickFile)
    (let (f d)
        (setq d (if apt_adLastFile apt_adLastFile (apt_workDir)))
        (setq f (car (errset (axlDMFileBrowse "TEMP" nil
                                              ?title "选择 AD 导出的 ASCII (.pcbdoc)"
                                              ?defaultName d) nil)))
        (unless (car (errset (strlen f) nil))
            ;; 文件浏览器不可用时退回手输路径
            (setq f (axlUIPrompt "AD ASCII 文件全路径(.pcbdoc):" d)))
        (when (car (errset (strlen f) nil))
            (setq apt_adLastFile f))
        f))

;;; 输出文件名: 原名 + -fixed.pcbdoc
(procedure (apt_adOutName t_file)
    (let (n i ch dot)
        (setq n (strlen t_file))
        (setq dot -1)
        (setq i 0)
        (while (i < n)
            (setq ch (apt_adCh t_file i))
            (when (and (equal ch ".") (i > (n - 8))) (setq dot i))
            (setq i (i + 1)))
        (if (dot >= 0)
            (strcat (apt_adSub t_file 0 dot) "-fixed.pcbdoc")
            (strcat t_file "-fixed.pcbdoc"))))

;;; ---------------------------------------------------------------------------
;;; 命令
;;; ---------------------------------------------------------------------------
(procedure (apt_cmd_adchk)
    (let (f r)
        (setq f (apt_adPickFile))
        (when f
            (setq r (apt_adCheck f (strcat apt_home "/Temp/apt_ad_check.txt")))
            (when r
                (axlUIConfirm (sprintf nil
                    "AD ASCII 前置检查完成\n\n文件: %s\n\n元件 %d 个\nPATTERN 为空的元件 %d 个\n没有任何焊盘的元件 %d 个\n记录 %d 条\n\n报告: APTools/Temp/apt_ad_check.txt"
                    f (nth 0 r) (nth 1 r) (nth 2 r) (nth 3 r)))))))

(procedure (apt_cmd_adfix)
    (let (f r out nDel ok res)
        (setq f (apt_adPickFile))
        (when f
            ;; 先查一遍, 有东西可删才问
            (setq r (apt_adCheck f (strcat apt_home "/Temp/apt_ad_check.txt")))
            (when r
                (setq nDel (nth 1 r))
                (cond
                    ((equal nDel 0)
                        (axlUIConfirm (sprintf nil
                            "AD ASCII 前置检查: 没有 PATTERN 为空的元件, 不需要删除。\n\n文件: %s\n下次从 AD 重新导出后可以再查一遍。"
                            f)))
                    (t
                        (setq ok (axlUIYesNo
                            (sprintf nil
                                "发现 %d 个 PATTERN 为空的元件(清单见命令窗口)。\n\n将写出一个新文件:\n%s\n\n原文件一个字节都不会动。确认继续?"
                                nDel (apt_adOutName f))
                            "APTools 删除确认"))
                        (if ok
                            (progn
                                (setq out (apt_adOutName f))
                                (setq res (apt_adFixWrite f out))
                                (when res
                                    (axlUIConfirm (sprintf nil
                                        "已写出: %s\n\n记录 %d 条(删掉 %d 条 Component)\n原文件未修改。\n\n下一步用这个新文件做 Allegro 转换。"
                                        (nth 2 res) (nth 0 res) (nth 1 res)))))
                            (printf "[APTools] 已取消, 没有写出任何文件\n"))))))))

(procedure (apt_cmd_adrule)
    (printf "\n[APTools] ===== AD ASCII 前置检查 说明 =====\n")
    (printf "[APTools] 为什么在 ASCII 上查:\n")
    (printf "    Allegro 的 altium2pcb 在 text blocks 阶段会对 nil 调 upperCase 崩掉,\n")
    (printf "    触发条件是 ASCII 里 PATTERN(封装名)为空的 Component。这一关必须在\n")
    (printf "    转换之前、在 AD 导出的 ASCII 源文件上过。\n")
    (printf "[APTools] 检查项:\n")
    (printf "    1. 记录类型统计(看这个文件到底导出了什么)\n")
    (printf "    2. PATTERN 为空的元件(要删的)\n")
    (printf "    3. 没有任何焊盘的元件(只报告)\n")
    (printf "    4. 含非 ASCII 字符的行数\n")
    (printf "[APTools] 删除方式:\n")
    (printf "    只丢掉 Component 那一条记录, 焊盘/走线等一律保留;\n")
    (printf "    写出 原名-fixed.pcbdoc, **原件不动**, 并用确认对话框把关。\n")
    (printf "[APTools] 与 kit 的关系: 等价于 altium_ascii_tool.py 的 check / fix,\n")
    (printf "         收进 APTools 是为了不用装 Python 也能随手复检。\n"))

(axlCmdRegister "apt_adchk"  'apt_cmd_adchk  ?cmdType "general")
(axlCmdRegister "apt_adfix"  'apt_cmd_adfix  ?cmdType "general")
(axlCmdRegister "apt_adrule" 'apt_cmd_adrule ?cmdType "general")

(apt_menuSub    "90_misc" apt_ad_submenu "检查 AD ASCII..."     "apt_adchk")
(apt_menuSub    "90_misc" apt_ad_submenu "删除空封装元件..."    "apt_adfix")
(apt_menuSubSep "90_misc" apt_ad_submenu)
(apt_menuSub    "90_misc" apt_ad_submenu "AD ASCII 检查说明"    "apt_adrule")

(printf "[APTools] APT_ADAscii 已加载 (apt_adchk / apt_adfix / apt_adrule)\n")
