;;; dbg.il -- 诊断: 打开一张 .dra, 列出它里面所有线/弧/圆/shape 所在的 subclass
;;; 目的: 搞清楚"定位孔"到底落在哪个 subclass、用什么对象类型表示。
;;; 注意: 本文件必须用 SKILL 方言写 --
;;;   * 函数名不能含 '-'            (用 '_')
;;;   * setq 一次只能赋一个变量
;;;   * 比较/算术是中缀: (a > b), 不是 (> a b)
;;;   * 零参过程写成 (procedure (name) body)

(defvar dbgOut "F:/1.Hardware/GTS_PPA1/08.CTL-SYNCTRIG4F4-HASL/AllegroTools/Temp/smoke/dbg_out.txt")

(procedure (dbg_pr msg)
    (let (p)
        (setq p (outfile dbgOut "a"))
        (when p
            (fprintf p "%s\n" msg)
            (close p))))

(procedure (dbg_sel kind)
    (let (res)
        (axlClearSelSet)
        (axlSetFindFilter ?enabled (list "noall" kind) ?onButtons (list "noall" kind))
        (axlAddSelectAll)
        (setq res (axlGetSelSet))
        (axlClearSelSet)
        res))

(procedure (dbg_uniq objs)
    (let (seen o)
        (foreach o objs
            (unless (member o->layer seen)
                (setq seen (cons o->layer seen))))
        seen))

(procedure (dbg_layers objs tag)
    (let (lays lay n o)
        (setq lays (dbg_uniq objs))
        (dbg_pr (sprintf nil "  [%s] %d 个对象, %d 个 subclass" tag (length objs) (length lays)))
        (foreach lay lays
            (setq n 0)
            (foreach o objs
                (when (equal o->layer lay)
                    (setq n (n + 1))))
            (dbg_pr (sprintf nil "      %-46s x%d" lay n)))))

(procedure (dbg_dump objs tag limit)
    (let (n o)
        (dbg_layers objs tag)
        (dbg_pr (sprintf nil "  --- %s 明细(最多 %d 条) ---" tag limit))
        (setq n 0)
        (foreach o objs
            (when (n < limit)
                (setq n (n + 1))
                (dbg_pr (sprintf nil "    #%d type=%L layer=%L circle=%L bb=%L"
                                 n o->objType o->layer
                                 (if (eq o->objType 'arc) o->isCircle nil)
                                 o->bBox))))))

(procedure (dbg_one dra)
    (let (d lines shapes)
        (dbg_pr (sprintf nil "======== %s" dra))
        (if (axlOpenDesignForBatch dra "wf")
            (progn
                (dbg_pr "  open: ok")
                (setq d (axlDBGetDesign))
                (dbg_pr (sprintf nil "  userUnits: %L" d->userUnits))
                (dbg_pr (sprintf nil "  pins: %L" (length d->pins)))
                (dbg_pr (sprintf nil "  components: %L" (length d->components)))
                (setq lines (dbg_sel "lines"))
                (dbg_pr (sprintf nil "  find 'lines' -> %L" (length lines)))
                (when lines
                    (dbg_dump lines "lines" 150))
                (setq shapes (dbg_sel "shapes"))
                (dbg_pr (sprintf nil "  find 'shapes' -> %L" (length shapes)))
                (when shapes
                    (dbg_dump shapes "shapes" 60)))
            (dbg_pr "  open: FAILED"))))

(procedure (dbg_cur)
    (let (d lines shapes)
        (dbg_pr "######## current drawing ########")
        (dbg_pr (sprintf nil "design: %L" (axlCurrentDesign)))
        (setq d (axlDBGetDesign))
        (dbg_pr (sprintf nil "userUnits: %L" d->userUnits))
        (dbg_pr (sprintf nil "pins: %L" (length d->pins)))
        (dbg_pr (sprintf nil "components: %L" (length d->components)))
        (setq lines (dbg_sel "lines"))
        (dbg_pr (sprintf nil "find 'lines' -> %L" (length lines)))
        (when lines
            (dbg_dump lines "lines" 400))
        (setq shapes (dbg_sel "shapes"))
        (dbg_pr (sprintf nil "find 'shapes' -> %L" (length shapes)))
        (when shapes
            (dbg_dump shapes "shapes" 200))))

(procedure (dbg_all libDir)
    (let (files f full)
        (dbg_pr "############ dbg start ############")
        (setq files (getDirFiles libDir))
        (foreach f files
            (when (rexMatchp "\\.dra$" (lowerCase f))
                (setq full (strcat libDir "/" f))
                (dbg_one full)))
        (dbg_pr "############ dbg end ############")))
