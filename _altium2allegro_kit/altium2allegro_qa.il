; =========================================================================
; altium2allegro_qa.il - SKILL 质检/核对脚本 (Allegro PCB Editor 内使用)
; -------------------------------------------------------------------------
; 用途: Altium->Allegro 导入后, 在 Allegro 中快速核对设计完整性:
;   * 元件数 / 网络数 / 符号数 / DRC 数
;   * 把报告写到一个文本文件供流程回读
; -------------------------------------------------------------------------
; 用法(在 Allegro PCB Editor 命令行输入):
;   skill (load "F:/1.Hardware/GTS_PPA1/06.SYNC_TRIG/_altium2allegro_kit/altium2allegro_qa.il")
;   skill (alt2a-qa "F:/.../board_qa.txt")     ; 打印并写出报告
;   skill (alt2a-qa nil)                        ; 只打印不写文件
;   skill (alt2a-compare 265)                   ; 核对元件数是否为 265
; =========================================================================

(defun alt2a-qa (outFile)
  "Write an import QA summary to outFile (nil = console only)."
  (let (d ncomp nnet nsym ndrc msg p)
    (setq d (axlDBGetDesign))
    (cond
      ((null d)
       (printf "alt2a-qa: no design open (run inside Allegro with board loaded)\n")
       nil)
      (t
       (setq ncomp (length (d->components)))
       (setq nnet  (length (d->nets)))
       (setq nsym  (length (d->symdefs)))
       (setq ndrc  (length (d->drcs)))
       (setq msg (sprintf nil
                  "design      : %s\ncomponents  : %d\nnets        : %d\nsymbols     : %d\ndrcs        : %d\n"
                  (axlCurrentDesign) ncomp nnet nsym ndrc))
       (printf "%s" msg)
       (when outFile
         (setq p (outfile outFile "w"))
         (fprintf p "%s" msg)
         (close p)
         (printf "alt2a-qa: report written to %s\n" outFile))
       t))))

(defun alt2a-compare (refCount)
  "Report whether component count equals refCount."
  (let (d n ok)
    (setq d (axlDBGetDesign))
    (when d
      (setq n (length (d->components)))
      (setq ok (equal n refCount))
      (printf "components = %d (expect ~%d) -> %s\n"
              n refCount (if ok "OK" "MISMATCH"))
      ok)))

(printf "altium2allegro_qa.il loaded.\n")
(printf "  skill (alt2a-qa \"<path>/board_qa.txt\")  |  skill (alt2a-compare <N>)\n")
