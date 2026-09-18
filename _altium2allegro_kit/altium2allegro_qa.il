;;; =========================================================================
;;; altium2allegro_qa.il - SKILL 质检/核对脚本 (Allegro PCB Editor 内使用)
;;; -------------------------------------------------------------------------
;;; 用途: Altium->Allegro 导入后, 在 Allegro 中快速核对设计完整性:
;;;   * 元件数 / 网络数 / 符号数 / DRC 数
;;;   * 把报告写到一个文本文件供流程回读
;;; -------------------------------------------------------------------------
;;; 用法(在 Allegro PCB Editor 命令行输入):
;;;   skill (load "F:/1.Hardware/GTS_PPA1/08.CTL-SYNCTRIG4F4-HASL/AllegroTools/_altium2allegro_kit/altium2allegro_qa.il")
;;;   skill (alt2a_qa "F:/.../board_qa.txt")     ; 打印并写出报告
;;;   skill (alt2a_qa nil)                        ; 只打印不写文件
;;;   skill (alt2a_compare 265)                   ; 核对元件数是否为 265
;;; -------------------------------------------------------------------------
;;; 2026-09 修订: 原来函数名写成 alt2a-qa / alt2a-compare, 而 SKILL 的 reader
;;;   会把 "alt2a-qa" 解析成 (alt2a - qa) (减号!), 于是 load 直接报
;;;   "defun: argument #1 should be a symbol ... - (alt2a - qa)"。
;;;   已全部改成下划线形式 alt2a_qa / alt2a_compare。
;;;   同理: SKILL 里函数名不要用 '-'；setq 一次只能赋一个变量；
;;;   比较/算术是中缀 (a > b) 而不是前缀 (> a b)。
;;; =========================================================================

(procedure (alt2a_qa outFile)
    (let (d ncomp nnet nsym ndrc msg p)
        (setq d (axlDBGetDesign))
        (cond
            ((null d)
                (printf "alt2a_qa: 没有打开的图 (请在 Allegro 里打开后再跑)\n")
                nil)
            (t
                (setq ncomp (length d->components))
                (setq nnet  (length d->nets))
                (setq nsym  (length d->symdefs))
                (setq ndrc  (length d->drcs))
                (setq msg (sprintf nil
                            "design      : %s\ncomponents  : %d\nnets        : %d\nsymbols     : %d\ndrcs        : %d\n"
                            (axlCurrentDesign) ncomp nnet nsym ndrc))
                (printf "%s" msg)
                (when outFile
                    (setq p (outfile outFile "w"))
                    (when p
                        (fprintf p "%s" msg)
                        (close p)
                        (printf "alt2a_qa: 报告已写出 %s\n" outFile)))
                t))))

(procedure (alt2a_compare refCount)
    (let (d n ok)
        (setq d (axlDBGetDesign))
        (when d
            (setq n (length d->components))
            (setq ok (equal n refCount))
            (printf "components = %d (期望 %d) -> %s\n"
                    n refCount (if ok "OK" "MISMATCH"))
            ok)))

(printf "altium2allegro_qa.il loaded.\n")
(printf "  skill (alt2a_qa \"<path>/board_qa.txt\")  |  skill (alt2a_compare <N>)\n")
