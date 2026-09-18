;;; ============================================================================
;;; api_probe.il  --  探明 SKILL 方言/API 事实 (ASCII only)
;;;   1) defvar / 算术 / mod / random / 32 位溢出 / 字符串 / 调色板
;;;   2) 顶层全局变量在本文件末尾的顶层能不能读到 (repro, 见文件最末)
;;;   有风险的中缀写法一律走 evalstring, 避免 reader 在载入期就报语法错。
;;; ============================================================================

;;; --- 第1节用的变量 ---------------------------------------------------------
(defvar probeA nil)
(defvar probeB 32)
(defvar probeC nil)
(setq probeC 7)

;;; --- repro 用变量: 四种写法并排放, 在文件最末的顶层统一读一次 --------------
(defvar rpA nil)                        ; 1: defvar nil + setq 数字
(setq rpA 32)
(defvar rpB nil)                        ; 2: defvar nil + setq 列表
(setq rpB (list "x" "y"))
(defvar rpC 32)                         ; 3: defvar 直接带值
(defvar rpD nil)                        ; 4: defvar nil + 紧跟 setq
(setq rpD 7)
(defvar rpE nil)                        ; 5: defvar nil + setq 99
(setq rpE 99)

;;; --- padding: 拉开距离, 模拟真实工具文件的长度 ------------------------------
(procedure (rpPad1) rpA)
(procedure (rpPad2) rpB)
(procedure (rpPad3) rpC)
(procedure (rpPad4) rpD)
(procedure (rpPad5) rpE)
(procedure (rpPad6) (list rpA rpB rpC rpD rpE))
(procedure (rpPad7) (list 'a 'b 'c 'd 'e 'f 'g 'h))
(procedure (rpPad8) (list 'a 'b 'c 'd 'e 'f 'g 'h))
(procedure (rpPad9) (list 'a 'b 'c 'd 'e 'f 'g 'h))
(procedure (rpPad10) (list 'a 'b 'c 'd 'e 'f 'g 'h))

(procedure (aptProbe)
    (printf "=== 1. defvar semantics ===\n")
    (printf "defvar X nil  then read : %L\n" (errset (list 'A probeA) nil))
    (printf "defvar X 32   then read : %L\n" (errset (list 'B probeB) nil))
    (printf "defvar X nil + setq 7   : %L\n" (errset (list 'C probeC) nil))

    (printf "\n=== 2. integer division / modulo ===\n")
    (printf "(7 / 2)                 : %L\n" (errset (7 / 2) nil))
    (printf "(1 / 3)                 : %L\n" (errset (1 / 3) nil))
    (printf "((0 - 7) / 2)           : %L\n" (errset ((0 - 7) / 2) nil))
    (printf "evalstring (7 mod 2)    : %L\n" (errset (evalstring "(7 mod 2)") nil))
    (printf "(mod 7 2) prefix        : %L\n" (errset (eval (list 'mod 7 2)) nil))
    (printf "(remainder 7 2)         : %L\n" (errset (remainder 7 2) nil))
    (printf "(atoi \"42\")              : %L\n" (errset (atoi "42") nil))

    (printf "\n=== 3. random ===\n")
    (printf "(random 10)             : %L\n" (errset (random 10) nil))
    (printf "(random)                : %L\n" (errset (random) nil))
    (printf "(getCurrentTime)        : %L\n" (errset (getCurrentTime) nil))

    (printf "\n=== 4. 32-bit overflow (no bignum) ===\n")
    (printf "1000000000000000 literal: %L\n" (errset 1000000000000000 nil))
    (printf "2147483647 + 2147483647 : %L\n" (errset (2147483647 + 2147483647) nil))
    (printf "1000003 * 1000000       : %L\n" (errset (1000003 * 1000000) nil))

    (printf "\n=== 5. string / palette ===\n")
    (printf "(substring \"ABCDEF\" 2 3) : %L\n" (errset (substring "ABCDEF" 2 3) nil))
    (printf "sprintf %%-18s padding   : [%L]\n" (errset (sprintf nil "%-18s|" "GND") nil))
    (printf "(axlColorGet 'count)    : %L\n" (errset (axlColorGet 'count) nil))

    (printf "\n=== 6. repro: 过程内读顶层全局 ===\n")
    (printf "in-proc rpA(1) : %L\n" (errset (list rpA) nil))
    (printf "in-proc rpB(2) : %L\n" (errset (list rpB) nil))
    (printf "in-proc rpC(3) : %L\n" (errset (list rpC) nil))
    (printf "in-proc rpD(4) : %L\n" (errset (list rpD) nil))
    (printf "in-proc rpE(5) : %L\n" (errset (list rpE) nil))
    (printf "\nPROBE DONE\n")
    t)

;;; --- 关键复现: 本文件末尾的顶层读(即出问题的那种读法) ----------------------
(printf "\n### REPRO 顶层读(本文件末尾) ###\n")
(printf "TOP rpA defvar nil + setq 32   : %L\n" (errset (list rpA) nil))
(printf "TOP rpB defvar nil + setq list : %L\n" (errset (list rpB) nil))
(printf "TOP rpC defvar 32              : %L\n" (errset (list rpC) nil))
(printf "TOP rpD defvar nil + setq 7    : %L\n" (errset (list rpD) nil))
(printf "TOP rpE defvar 32   + setq 99  : %L\n" (errset (list rpE) nil))
(printf "### REPRO END ###\n")
