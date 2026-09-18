;;; ============================================================================
;;; APT_ConvertQA.il  --  转换核对(AD/OrCAD -> Allegro 的前置/后置检查)
;;; 阶段: 90_misc (辅助功能)      子菜单: 转换核对
;;; ----------------------------------------------------------------------------
;;; 为什么需要
;;;   从 AD/OrCAD 转过来的板子, 有几类问题每次都要人工核一遍。原来这些散在
;;;   _altium2allegro_kit 的 Python/SKILL 脚本里, 现在收进 APTools 随手可查。
;;;
;;; 五个命令
;;;   apt_qa        整体核对: 元件(含未放置)/网络/符号定义/DRC/未布线连接,
;;;                 并可与你给的期望值对比, 报告写到 APTools/Temp/
;;;   apt_qaset     设期望值(期望元件数/期望网络数), 供 apt_qa 对比
;;;   apt_layers    层映射核对: 本图各类对象(线/弧/shape/引脚/过孔/文字)
;;;                 分别落在哪些 subclass, 导出 CSV
;;;   apt_empty     空封装检查: 引脚数为 0 的器件(转换过来的"空封装元件"),
;;;                 列出+高亮, 不删任何东西
;;;   apt_emptyfix  空封装删除: 确认后真正删除(对应 kit 里 fix 模式的"删空封装")
;;;
;;; 删除的安全设计(重要)
;;;   1. 先跑一遍检查并列清单, 弹 axlUIYesNo 让你确认, 你点"否"就什么都不做
;;;   2. LOGO/HOLE/FIDUCIAL/MOUNT/TP/TEST 这类**机械与图形件**默认受保护,
;;;      它们引脚本来就是 0, 不该删(见 apt_qaKeep)
;;;   3. 删掉哪些会单独写一份清单到 APTools/Temp/, 便于事后核对
;;;   4. 想只看不删: (apt_cfgset 'qaDryRun t)
;;;
;;; 编码: 必须 GBK(cp936)。
;;; ============================================================================

(defvar apt_convertqa_submenu nil)
(setq apt_convertqa_submenu "转换核对")

;;; ---------------------------------------------------------------------------
;;; 可调参数
;;;   qaWantComps / qaWantNets  期望值(0 表示不核对)
;;;   qaKeep                    空封装保护名单(名字里含这些词就不算空封装)
;;;   qaDryRun                  只报告不删除
;;; ---------------------------------------------------------------------------
(defvar apt_qaKeep nil)
(setq apt_qaKeep (list "LOGO" "HOLE" "FIDUCIAL" "FID" "MOUNT" "TP" "TEST"
                       "MECH" "SILK" "BARCODE" "DATUM" "FRAME" "TITLE"))

;;; ---------------------------------------------------------------------------
;;; 小工具
;;; ---------------------------------------------------------------------------
(procedure (apt_qaHas t_lst t_x)
    (let (hit)
        (setq hit nil)
        (foreach x t_lst (when (equal x t_x) (setq hit t)))
        hit))

;;; 想拿字符串就原样返回, 否则用 %L 兜底
;;;   不用 stringp(不保险), 改用 strlen 能不能算出来判断是不是字符串
(procedure (apt_qaStr t_x)
    (if (car (errset (strlen t_x) nil))
        t_x
        (sprintf nil "%L" t_x)))

;;; 安全取符号名(可能为 nil)
(procedure (apt_qaSymName t_s)
    (let (nm)
        (setq nm (car (errset t_s->name nil)))
        (if (car (errset (strlen nm) nil)) nm "(无名)")))

;;; ---------------------------------------------------------------------------
;;; 空封装检查: 引脚数为 0 的器件
;;;   返回 ((dbid 封装名 位号 是否受保护) ...)
;;; ---------------------------------------------------------------------------
(procedure (apt_qaEmptyList)
    (let (syms out pins nm keep kw)
        (setq syms (axlDBGetDesign)->symbols)
        (setq out nil)
        (foreach s syms
            (setq pins (car (errset (length s->pins) nil)))
            (when (equal pins 0)
                (setq nm (apt_qaSymName s))
                (setq keep nil)
                (foreach kw apt_qaKeep
                    (when (rexMatchp kw (upperCase nm)) (setq keep t)))
                (setq out (append out (list (list s nm (car (errset s->refdes nil)) keep))))))
        out))

;;; 打印清单, 返回 (总数 受保护数 可删数)
(procedure (apt_qaEmptyShow t_rows)
    (let (n keepN delN)
        (setq n (length t_rows))
        (setq keepN 0)
        (setq delN 0)
        (printf "\n[APTools] ===== 空封装检查(引脚数为 0 的器件) =====\n")
        (when (equal n 0)
            (printf "[APTools] 没有空封装元件\n"))
        (foreach r t_rows
            (if (nth 3 r)
                (progn
                    (setq keepN (keepN + 1))
                    (printf "[APTools]   [保护] %-34s 位号 %s\n" (nth 1 r) (apt_qaStr (nth 2 r))))
                (progn
                    (setq delN (delN + 1))
                    (printf "[APTools]   [可删] %-34s 位号 %s\n" (nth 1 r) (apt_qaStr (nth 2 r))))))
        (printf "[APTools] 合计 %d 个: 可删 %d, 受保护(机械/图形件) %d\n" n delN keepN)
        (list n keepN delN)))

;;; ---------------------------------------------------------------------------
;;; 整体核对
;;; ---------------------------------------------------------------------------
(procedure (apt_qaRun t_report)
    (let (d st ncomp nnet nsym ndrc placed unplaced totConn doneConn openConn
          wantC wantN msg p ok)
        (setq d (axlDBGetDesign))
        ;; 注意: return 只能在 prog 里用, 这里用 if/progn 包住, 不用 return
        (if (null d)
            (printf "[APTools] apt_qa: 没有打开的图(请先在 Allegro 里打开图)\n")
            (progn
        (setq ncomp (length d->components))
        (setq nnet (length d->nets))
        (setq nsym (length d->symdefs))
        (setq ndrc (length d->drcs))
        ;; 设计统计(状态表单里那份), 取不到就留 nil
        (setq st (car (errset (axlDBGetDesignStats) nil)))
        (when st
            (setq placed (car (errset st->placedComponents nil)))
            (setq unplaced (car (errset st->unplacedComponents nil)))
            (setq totConn (car (errset st->totalConnections nil)))
            (setq doneConn (car (errset st->completeConnections nil)))
            (setq openConn (car (errset st->incompleteConnections nil))))

        (setq wantC (apt_cfg 'qaWantComps))
        (setq wantN (apt_cfg 'qaWantNets))
        (unless wantC (setq wantC 0))
        (unless wantN (setq wantN 0))

        (setq ok t)
        (setq msg (sprintf nil
            "设计        : %s\n元件        : %d   (已放置 %L / 未放置 %L)\n网络        : %d\n符号定义    : %d\nDRC         : %d\n连接        : 共 %L, 已完成 %L, 未完成 %L\n"
            (axlCurrentDesign) ncomp placed unplaced nnet nsym ndrc
            totConn doneConn openConn))
        (printf "\n[APTools] ===== 转换核对 =====\n")
        (printf "[APTools] %s" msg)

        (when (wantC > 0)
            (printf "[APTools] 期望元件数 %d -> %s\n" wantC
                    (if (equal ncomp wantC) "一致" "不一致!"))
            (unless (equal ncomp wantC) (setq ok nil)))
        (when (wantN > 0)
            (printf "[APTools] 期望网络数 %d -> %s\n" wantN
                    (if (equal nnet wantN) "一致" "不一致!"))
            (unless (equal nnet wantN) (setq ok nil)))
        (when (and openConn (openConn > 0))
            (printf "[APTools] !! 还有 %d 条连接未完成\n" openConn)
            (setq ok nil))
        (when (and unplaced (unplaced > 0))
            (printf "[APTools] !! 还有 %d 个器件未放置\n" unplaced))
        (printf "[APTools] 结论: %s\n" (if ok "无异常" "有需要确认的项"))

        (when t_report
            (setq p (car (errset (outfile t_report "w") nil)))
            (when p
                (fprintf p "%s" msg)
                (fprintf p "期望元件 %d / 期望网络 %d -> %s\n" wantC wantN
                         (if ok "无异常" "有需确认项"))
                (close p)
                (printf "[APTools] 报告已写出: %s\n" t_report)))
        (list ncomp nnet nsym ndrc (if ok 1 0))))))

;;; ---------------------------------------------------------------------------
;;; 层映射核对: 各类对象分别落在哪些 subclass
;;; ---------------------------------------------------------------------------
(procedure (apt_qaSel t_kind)
    (let (res)
        (axlClearSelSet)
        (setq res (car (errset (progn
            (axlSetFindFilter ?enabled (list "noall" t_kind) ?onButtons (list "noall" t_kind))
            (axlAddSelectAll)
            (axlGetSelSet)) nil)))
        (errset (axlClearSelSet) nil)
        res))

(procedure (apt_qaLayers t_csv)
    (let (kinds objs rows lay layName hit cnt lays o n layerRows csvRows tag)
        (setq kinds (list "lines" "arcs" "shapes" "pins" "vias" "text"))
        (setq rows nil)
        (printf "\n[APTools] ===== 层映射核对(本图用到的 subclass) =====\n")
        (foreach tag kinds
            (setq objs (apt_qaSel tag))
            ;; 一个对象都没有也报一声, 免得让人以为这一类没检查
            (unless objs (printf "[APTools]   [%s] 0 个对象\n" tag))
            (when objs
                (setq lays nil)
                (foreach o objs
                    (setq lay (car (errset o->layer nil)))
                    (unless (apt_qaHas lays lay)
                        (setq lays (append lays (list lay)))))
                (printf "[APTools]   [%s] %d 个对象, %d 个 subclass\n" tag (length objs) (length lays))
                (foreach lay lays
                    (setq cnt 0)
                    (foreach o objs
                        (when (equal (car (errset o->layer nil)) lay)
                            (setq cnt (cnt + 1))))
                    ;; pin/via 这类没有单一的 ->layer, 取到 nil 就明说, 别打成 nil 误导人
                    (setq layName (if lay (apt_qaStr lay) "(该类型无单一 subclass 属性)"))
                    (printf "[APTools]       %-42s x%d\n" layName cnt)
                    (setq rows (append rows (list (list tag layName cnt)))))))
        (when t_csv
            (setq csvRows nil)
            (foreach r rows
                (setq csvRows (append csvRows (list
                    (list (nth 0 r) (nth 1 r) (sprintf nil "%d" (nth 2 r)))))))
            (setq p (car (errset (outfile t_csv "w") nil)))
            (when p
                (fprintf p "对象类型,subclass,数量\n")
                (foreach r csvRows
                    (fprintf p "%s,%s,%s\n" (nth 0 r) (nth 1 r) (nth 2 r)))
                (close p)
                (printf "[APTools] 报告已写出: %s\n" t_csv)))
        rows))

;;; ---------------------------------------------------------------------------
;;; 命令
;;; ---------------------------------------------------------------------------
(procedure (apt_cmd_qa)
    (let (r)
        (setq r (apt_qaRun (strcat apt_home "/Temp/apt_qa_report.txt")))
        (when r
            (axlUIConfirm (sprintf nil
                "转换核对完成\n\n元件 %d\n网络 %d\n符号定义 %d\nDRC %d\n\n结论: %s\n\n报告: APTools/Temp/apt_qa_report.txt"
                (nth 0 r) (nth 1 r) (nth 2 r) (nth 3 r)
                (if (equal (nth 4 r) 1) "无异常" "有需要确认的项"))))))

(procedure (apt_cmd_qaset)
    (let (a b na nb)
        (setq a (axlUIPrompt "期望元件数(留空或 0 表示不核对):"
                             (sprintf nil "%d" (if (apt_cfg 'qaWantComps) (apt_cfg 'qaWantComps) 0))))
        (when a
            (setq na (atoi a))
            (unless na (setq na 0))
            (apt_cfgset 'qaWantComps na))
        (setq b (axlUIPrompt "期望网络数(留空或 0 表示不核对):"
                             (sprintf nil "%d" (if (apt_cfg 'qaWantNets) (apt_cfg 'qaWantNets) 0))))
        (when b
            (setq nb (atoi b))
            (unless nb (setq nb 0))
            (apt_cfgset 'qaWantNets nb))
        (printf "[APTools] 期望值已设为 元件 %L / 网络 %L\n"
                (apt_cfg 'qaWantComps) (apt_cfg 'qaWantNets))))

(procedure (apt_cmd_layers)
    (let (r)
        (setq r (apt_qaLayers (strcat apt_home "/Temp/apt_qa_layers.csv")))
        (axlUIConfirm (sprintf nil
            "层映射核对完成\n\n共列出 %d 条 (对象类型 x subclass)\n\n清单见命令窗口; 报告: APTools/Temp/apt_qa_layers.csv"
            (length r)))))

(procedure (apt_cmd_empty)
    (let (rows rc)
        (setq rows (apt_qaEmptyList))
        (setq rc (apt_qaEmptyShow rows))
        (foreach r rows
            (errset (axlHighlightObject (car r)) nil))
        (axlUIConfirm (sprintf nil
            "空封装检查(未删除任何东西)\n\n引脚数为 0 的器件 %d 个\n  可删 %d\n  受保护(机械/图形件) %d\n\n已高亮; 清单见命令窗口。\n要删除请用菜单的「删除空封装」。"
            (nth 0 rc) (nth 2 rc) (nth 1 rc)))))

(procedure (apt_cmd_emptyfix)
    (let (rows rc ndel nskip p r ok d)
        (setq rows (apt_qaEmptyList))
        (setq rc (apt_qaEmptyShow rows))
        (setq ndel 0)
        (setq nskip (nth 1 rc))
        (cond
            ((equal (nth 2 rc) 0)
                (axlUIConfirm "没有可删的空封装元件(受保护的机械/图形件不算)。"))
            ((apt_cfg 'qaDryRun)
                (axlUIConfirm (sprintf nil
                    "qaDryRun = t, 只报告不删除。\n\n可删的空封装元件 %d 个(清单见命令窗口)。\n要真删: (apt_cfgset 'qaDryRun nil)"
                    (nth 2 rc))))
            (t
                (setq ok (axlUIYesNo
                    (sprintf nil
                        "确认删除 %d 个空封装元件(引脚数为 0)?\n\n受保护的机械/图形件 %d 个不会被删。\n此操作会修改当前设计, 建议先存盘。"
                        (nth 2 rc) nskip)
                    "APTools 删除确认"))
                ;; 第三参不传(各版本对默认值的符号写法不一定一致), 用户点否 -> nil
                (if ok
                    (progn
                        (setq p (car (errset (outfile (strcat apt_home "/Temp/apt_qa_deleted.txt") "w") nil)))
                        (when p
                            (fprintf p "空封装元件删除清单 (refdes, footprint)\n"))
                        (foreach r rows
                            (unless (nth 3 r)
                                (when (car (errset (axlDeleteObject (car r)) t))
                                    (setq ndel (ndel + 1))
                                    (when p
                                        (fprintf p "%s,%s\n"
                                                 (apt_qaStr (nth 2 r)) (nth 1 r))))))
                        (when p (close p))
                        (errset (axlDBRefreshId t) nil)
                        (printf "[APTools] 已删除 %d 个空封装元件; 清单: %s\n"
                                ndel (strcat apt_home "/Temp/apt_qa_deleted.txt"))
                        (axlUIConfirm (sprintf nil
                            "已删除 %d 个空封装元件。\n\n清单: APTools/Temp/apt_qa_deleted.txt\n\n注意: 这是对设计的修改, 需要你自行存盘。"
                            ndel))))))))

(procedure (apt_cmd_qarule)
    (printf "\n[APTools] ===== 转换核对 说明 =====\n")
    (printf "[APTools] 检查项:\n")
    (printf "    1. 元件数(含未放置)/ 网络数 / 符号定义数 / DRC / 未完成连接\n")
    (printf "    2. 与期望值对比(菜单「设期望值」, 或 (apt_cfgset 'qaWantComps 265))\n")
    (printf "    3. 层映射: 每类对象落在哪些 subclass(转过来的层错位一眼能看出)\n")
    (printf "    4. 空封装元件: 引脚数为 0 的器件, 可检查也可删除\n")
    (printf "[APTools] 删除的安全性:\n")
    (printf "    - 先列清单 + axlUIYesNo 确认, 点否就什么都不做\n")
    (printf "    - 机械/图形件受保护, 名单: %L\n" apt_qaKeep)
    (printf "    - (apt_cfgset 'qaDryRun t) 可强制只报告不删\n")
    (printf "    - 删除清单写到 APTools/Temp/apt_qa_deleted.txt\n")
    (printf "[APTools] 删空封装的来历: kit 里 altium_ascii_tool.py fix 模式的\"删空封装\"\n")
    (printf "         那步在 AD ASCII 源码侧做; 这里是转换后在 Allegro 里补救。\n"))

(axlCmdRegister "apt_qa"        'apt_cmd_qa       ?cmdType "general")
(axlCmdRegister "apt_qaset"     'apt_cmd_qaset    ?cmdType "general")
(axlCmdRegister "apt_layers"    'apt_cmd_layers   ?cmdType "general")
(axlCmdRegister "apt_empty"     'apt_cmd_empty    ?cmdType "general")
(axlCmdRegister "apt_emptyfix"  'apt_cmd_emptyfix ?cmdType "general")
(axlCmdRegister "apt_qarule"    'apt_cmd_qarule   ?cmdType "general")

(apt_menuSub    "90_misc" apt_convertqa_submenu "整体核对"        "apt_qa")
(apt_menuSub    "90_misc" apt_convertqa_submenu "设期望值..."     "apt_qaset")
(apt_menuSubSep "90_misc" apt_convertqa_submenu)
(apt_menuSub    "90_misc" apt_convertqa_submenu "层映射核对"      "apt_layers")
(apt_menuSubSep "90_misc" apt_convertqa_submenu)
(apt_menuSub    "90_misc" apt_convertqa_submenu "检查空封装"      "apt_empty")
(apt_menuSub    "90_misc" apt_convertqa_submenu "删除空封装"      "apt_emptyfix")
(apt_menuSubSep "90_misc" apt_convertqa_submenu)
(apt_menuSub    "90_misc" apt_convertqa_submenu "查看说明"        "apt_qarule")

(apt_cfgdef 'qaWantComps 0)
(apt_cfgdef 'qaWantNets  0)
(apt_cfgdef 'qaDryRun    nil)

(printf "[APTools] APT_ConvertQA 已加载 (apt_qa / apt_layers / apt_empty / apt_emptyfix)\n")
