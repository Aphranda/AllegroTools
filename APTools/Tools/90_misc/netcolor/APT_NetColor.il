;;; ============================================================================
;;; APT_NetColor.il  --  电源网络刷色 (先识别, 再随机配色)
;;; 阶段: 90_misc (辅助功能)      子菜单: 电源网络刷色
;;; ----------------------------------------------------------------------------
;;; 三步走
;;;   ① 识别: 哪些网络是电源网络(只列出来, 不刷色)   -> 菜单"识别电源网络"
;;;   ② 随机: 每个电源网络一个不同的随机颜色        -> 菜单"随机刷色"
;;;   ③ GND 系单独处理: 只在灰色系里随机            (GND/AGND/DGND/PGND/VSS...)
;;;
;;; 怎么识别(两路信号, 都只看网络名)
;;;   信号一 关键词:  VCC VDD VEE VBUS VBAT VREF ...  见 apt_netPowRailKw
;;;           GND 系: GND VSS EARTH CHASSIS ...      见 apt_netPowGndKw
;;;   信号二 电压记号: 名字里带 3V3 / 3.3V / 12V / +5V / 5V0 / 0V9 / 1V25 / 1P8V
;;;           这类可读的电压写法, 且数值在 0.4V~60V 之间 -> 算电源网络。
;;;           这样 3V3_A、P12V、+1V8、VCC5V0 这类不用逐个加关键词也能认出来。
;;;
;;; 排除(不算电源网络): 名字以 _EN/_PG/_FLT/_FB/_SENSE/_CS 等结尾的是控制或
;;;   反馈信号, 不是电源。见 apt_netPowSkipSuf。被排除的会单独列出来, 方便核对。
;;;
;;; 颜色怎么落到网上
;;;   axlCustomColorObject 收的是"调色板索引", 不是 RGB, 所以:
;;;     ① 调色板里本来就有这个色        -> 直接用那个索引
;;;     ② 之前已经为这个 RGB 占过保留槽 -> 复用
;;;     ③ 都没有                        -> 写到调色板末尾的保留槽
;;;   保留槽会盖掉调色板原来那几格, 原 RGB 已记录, 菜单"释放保留调色板槽"可还原。
;;;
;;; 可调参数
;;;   (apt_cfgset 'netColorReserveN 32)   保留槽个数(默认 32)
;;;   (apt_cfgset 'netColorGreyMin 90)    GND 灰色下限(默认 90,  太暗看不见)
;;;   (apt_cfgset 'netColorGreyMax 210)   GND 灰色上限(默认 210, 太亮看不见)
;;;
;;; 编码: 必须 GBK(cp936)。UTF-8 存盘 Allegro 里会乱码并吃字。
;;; ============================================================================

(defvar apt_netcolor_submenu nil)
(setq apt_netcolor_submenu "电源网络刷色")

;;; ---------------------------------------------------------------------------
;;; 随机数
;;;   实测(devkit/tests/api_probe.il): SKILL 自带 (random n) -> 0..n-1, (srandom n)
;;;   设种子, 都可用, 所以不用自己造 LCG。自造那版还踩了两个坑:
;;;     - SKILL 没有 bignum: 字面量超过 INT_MAX 会被"解析期截断成 INT_MAX",
;;;       运行时相乘也会回绕成负数(2147483647 + 2147483647 = -2)。
;;;     - getCurrentTime 返回的是字符串 "Sep 17 21:54:02 2026", 不是数字列表。
;;;   这里从时间串里抽数字当种子, 保证每次刷出来的颜色都不一样。
;;; ---------------------------------------------------------------------------
(defvar apt_rndSeeded nil)
(setq apt_rndSeeded nil)

(procedure (apt_netSeed)
    (let (ts s i d n)
        (setq ts (car (errset (getCurrentTime) nil)))
        (setq s 0)
        (setq n (car (errset (strlen ts) nil)))      ; 不是字符串时 n = nil
        (when n
            (setq i 0)
            (while (i < n)
                (setq d (apt_digAt ts i))
                (when (d >= 0)
                    (setq s (mod ((s * 10) + d) 1000000)))
                (setq i (i + 1))))
        (when (s <= 0) (setq s (mod (random) 1000000)))
        (srandom s)
        ;; 先走几步, 让序列离开种子点
        (random 1000)
        (random 1000)
        (random 1000)
        (setq apt_rndSeeded t)
        s))

;;; 0 .. t_n-1
(procedure (apt_rnd t_n)
    (unless apt_rndSeeded (apt_netSeed))
    (when (t_n < 1) (setq t_n 1))
    (mod (random t_n) t_n))

;;; ---------------------------------------------------------------------------
;;; 识别规则表
;;;   写法: "^XXX" 前缀匹配 / "XXX$" 后缀匹配 / "^XXX$" 全等 / "XXX" 包含
;;;   都按"分隔符已去掉"的紧凑名匹配, 所以 GND_A、GND-A、GNDA 一律等价。
;;; ---------------------------------------------------------------------------

;;; GND 系 -> 灰色系随机
;;;   地就用 "GND" 做匹配: 一条就涵盖 AGND / DGND / PGND / FGND / SGND /
;;;   CGND / MGND / GNDA / GND0 / GND_xxx / GND12 等所有含 GND 的写法。
;;;   VSS 家族(VSS / VSSA / VSSD / VSSIO / AVSS ...)另算一条。
;;;   EARTH / CHASSIS / GROUND / 0V 是别的画法习惯, 一起当地处理。
(defvar apt_netPowGndKw nil)
(setq apt_netPowGndKw (list
    "GND" "VSS" "EARTH" "CHASSIS" "GROUND" "RTN" "^0V$"))

;;; 电源(非地) -> 随机彩
;;;   这里是"包含"匹配, 所以 VCC 已涵盖 VCCIO/VCCINT/AVCC/DVCC,
;;;   VDD 已涵盖 VDDIO/VDDA/AVDD/PVDD/VDDQ, 不用重复列。
(defvar apt_netPowRailKw nil)
(setq apt_netPowRailKw (list
    ;; 经典电源前缀
    "VCC" "VDD" "VEE" "VBB" "VPP" "VTT" "VREF" "VCORE" "VAUX" "VANA" "VDIG"
    ;; 总线/电池/系统
    "VBUS" "VUSB" "VBAT" "VSYS" "VMAIN" "VSUP" "VRAIL" "VDC" "VAC"
    "VMID" "VBIAS" "VFUSE" "VPHY" "VPLL" "VTERM" "VREG" "VLOAD"
    ;; 开关电源节点
    "VBUCK" "VBOOST" "VPHASE" "VPWR" "VSW" "VLX"
    ;; 负载类
    "VMOTOR" "VLED"
    ;; 电压数字简写(名字里没有 3V3 这类记号时靠它认)
    "V33" "V25" "V18" "V15" "V12" "V50" "V09" "V05" "V35" "V20"
    ;; 前缀式
    "^VIN" "^VOUT" "^VIO" "^VPH" "^PWR" "^POWER"))

;;; 排除: 后缀命中即"不是电源"(控制/反馈/状态类)
;;;   每条都必须带 $ 走后缀匹配。若写成包含匹配, "PG" 会误伤 PGND,
;;;   "EN" 会误伤 VCC_CURRENT(里面含 EN), 所以一律带 $。
(defvar apt_netPowSkipSuf nil)
(setq apt_netPowSkipSuf (list
    "EN$" "ENB$" "ENABLE$" "PG$" "PGOOD$" "GOOD$" "PWRGD$" "PWROK$" "OK$"
    "FLT$" "FAULT$" "ALERT$" "RST$" "RESET$" "RESETN$" "NRST$" "TRIP$"
    "OC$" "OV$" "UV$" "DRV$" "GATE$" "COMP$" "CLK$" "SYNC$" "DET$" "FB$"
    "SENSE$" "SNS$" "NMI$" "IRQ$" "CS$" "SCL$" "SDA$" "STAT$" "STATUS$"
    "MON$" "ADC$" "TEMP$" "WDI$" "WDO$" "PWM$" "CTRL$" "CTL$" "SEL$" "MODE$"
    "TEST$" "TCK$" "TMS$" "TDI$" "TDO$" "TRST$"))

;;; ---------------------------------------------------------------------------
;;; 字符串小工具
;;;   ！！大坑: SKILL 的 substring 是 1 起算的, 而且索引 0 会直接报错
;;;   "substring: second argument (i.e., index) must not be 0"。
;;;   (实测: (substring "ABCDEF" 2 3) => "BCD")
;;;   本文件一律按 0 起算写, 统一走下面两个包装, 不要直接调 substring。
;;; ---------------------------------------------------------------------------

;;; 第 t_i 个字符(0 起算), 越界返回 ""
(procedure (apt_ch t_s t_i)
    (let (n)
        (setq n (strlen t_s))
        (if (or (t_i < 0) (t_i >= n))
            ""
            (substring t_s (t_i + 1) 1))))

;;; 从第 t_i 个字符(0 起算)取 t_len 个
(procedure (apt_sub t_s t_i t_len)
    (let (n)
        (setq n (strlen t_s))
        (if (or (t_i < 0) (t_len < 1) (t_i >= n))
            ""
            (substring t_s (t_i + 1) (apt_min2 t_len (n - t_i))))))

(procedure (apt_isSep t_ch)
    (or (equal t_ch "_") (equal t_ch "-") (equal t_ch ",") (equal t_ch "+")
        (equal t_ch "/") (equal t_ch "\\") (equal t_ch ":") (equal t_ch " ")
        (equal t_ch "(") (equal t_ch ")") (equal t_ch "[") (equal t_ch "]")
        (equal t_ch "<") (equal t_ch ">") (equal t_ch "|") (equal t_ch ".")
        (equal t_ch "=") (equal t_ch "#") (equal t_ch "&") (equal t_ch "*")))

;;; 去掉分隔符: "GND_A" -> "GNDA"
(procedure (apt_nosep t_s)
    (let (n i out ch)
        (setq n (strlen t_s))
        (setq i 0)
        (setq out "")
        (while (i < n)
            (setq ch (apt_ch t_s i))
            (unless (apt_isSep ch)
                (setq out (strcat out ch)))
            (setq i (i + 1)))
        out))

;;; 单字符转数字, 不是数字返回 -1
(procedure (apt_digAt t_s t_i)
    (let (ch n)
        (setq n (strlen t_s))
        (if (or (t_i < 0) (t_i >= n))
            -1
            (progn
                (setq ch (apt_ch t_s t_i))
                (if (rexMatchp "[0-9]" ch) (atoi ch) -1)))))

;;; 模式匹配: ^前缀 / 后缀$ / ^全等$ / 包含
(procedure (apt_patHit t_s t_p)
    (let (n m pre suf st en core cl hit i)
        (setq n (strlen t_s))
        (setq m (strlen t_p))
        (setq pre (equal (apt_ch t_p 0) "^"))
        (setq suf (equal (apt_ch t_p (m - 1)) "$"))
        (setq st (if pre 1 0))
        (setq en (if suf (m - 1) m))
        (setq cl (en - st))
        (when (cl > 0)
            (setq core (apt_sub t_p st cl)))
        (if (null core)
            nil
            (if (and pre suf)
                (equal t_s core)
                (if pre
                    (and (n >= cl) (equal (apt_sub t_s 0 cl) core))
                    (if suf
                        (and (n >= cl) (equal (apt_sub t_s (n - cl) cl) core))
                        (progn
                            (setq hit nil)
                            (setq i 0)
                            (while (and (null hit) ((i + cl) <= n))
                                (when (equal (apt_sub t_s i cl) core)
                                    (setq hit t))
                                (setq i (i + 1)))
                            hit)))))))

;;; 在模式表里找到第一个命中的模式, 返回该模式串; 都不中返回 nil
(procedure (apt_patAny t_s t_pats)
    (let (hit)
        (foreach p t_pats
            (when (and (null hit) (apt_patHit t_s p))
                (setq hit p)))
        hit))

;;; ---------------------------------------------------------------------------
;;; 电压记号识别
;;;   3V3 -> 3300   3.3V -> 3300   12V -> 12000   5V0 -> 5000
;;;   0V9 -> 900    1V25 -> 1250   1P8V -> 1800  (P 在小数点位置)
;;;   返回"毫伏"整数, 认不出返回 nil。只用于分类, 不追求数值精确。
;;; ---------------------------------------------------------------------------
(procedure (apt_voltAt t_s t_i)
    (let (n j k ch d1 flen frac mult pre ok mv)
        (setq n (strlen t_s))
        (setq j t_i)
        ;; 允许 +/-
        (setq ch (apt_ch t_s j))
        (when (or (equal ch "+") (equal ch "-"))
            (setq j (j + 1)))
        (setq d1 0)
        (setq flen 0)
        (setq frac 0)
        (setq ok nil)
        ;; 整数位
        (if ((apt_digAt t_s j) < 0)
            nil
            (progn
                (while ((apt_digAt t_s j) >= 0)
                    (setq d1 ((d1 * 10) + (apt_digAt t_s j)))
                    (setq j (j + 1)))
                ;; 小数点: . 或 P(Altium 写法 1P8V), 或 V(3V3 写法)
                (setq ch (apt_ch t_s j))
                (if (or (equal ch ".") (equal ch "P"))
                    (progn
                        (setq k (j + 1))
                        (while (and ((apt_digAt t_s k) >= 0) (flen < 3))
                            (setq frac ((frac * 10) + (apt_digAt t_s k)))
                            (setq flen (flen + 1))
                            (setq k (k + 1)))
                        (while ((apt_digAt t_s k) >= 0)
                            (setq k (k + 1)))
                        (when (flen > 0)
                            (setq j k)
                            (setq ok t)
                            (when (equal (apt_ch t_s j) "V")
                                (setq j (j + 1)))))
                    (if (equal ch "V")
                        (progn
                            (setq j (j + 1))
                            (setq ok t)
                            ;; V 后面跟数字就是小数: 3V3 / 1V25
                            (setq k j)
                            (while (and ((apt_digAt t_s k) >= 0) (flen < 3))
                                (setq frac ((frac * 10) + (apt_digAt t_s k)))
                                (setq flen (flen + 1))
                                (setq k (k + 1)))
                            (while ((apt_digAt t_s k) >= 0)
                                (setq k (k + 1)))
                            (setq j k))
                        nil))))
        (when ok
            ;; 记号前一个字符不能是数字(别从 13V3 里截出 3V3)
            (setq pre t)
            (when (t_i > 0)
                (when ((apt_digAt t_s (t_i - 1)) >= 0)
                    (setq pre nil)))
            ;; 记号后一个字符也不能是数字
            (when ((apt_digAt t_s j) >= 0)
                (setq pre nil))
            (when pre
                (setq mult (nth (3 - flen) (list 1 10 100 1000)))
                (setq mv ((d1 * 1000) + (frac * mult)))
                (if (and (mv >= 400) (mv <= 60000)) mv nil)))))

;;; 在整个名字里找一个电压记号, 返回毫伏或 nil
(procedure (apt_voltFind t_s)
    (let (n i hit v)
        (setq n (strlen t_s))
        (setq i 0)
        (while (and (null hit) (i < n))
            (setq v (apt_voltAt t_s i))
            (if v
                (setq hit v)
                (setq i (i + 1))))
        hit))

;;; ---------------------------------------------------------------------------
;;; 分类: 返回 (组 原因 毫伏)  组 = gnd / pwr / skip; 不是电源网络返回 nil
;;;
;;;   先判"是不是电源"(GND 关键词 / 电源关键词 / 电压记号), 只有本来就是电源
;;;   的名字才去看排除后缀。否则 SPI_CS、SDA、TEMP、SEL0 这类普通信号全都会
;;;   被当成"排除", 把报告淹掉。
;;; ---------------------------------------------------------------------------
(procedure (apt_netPowClass t_nm)
    (let (up cp sk g r mv grp why)
        (setq up (upperCase t_nm))
        (setq cp (apt_nosep up))
        (setq sk (apt_patAny cp apt_netPowSkipSuf))
        ;; ① GND 系(用 GND/VSS 关键词匹配)
        (setq g (apt_patAny cp apt_netPowGndKw))
        ;; ② 电源关键词
        (setq r (apt_patAny cp apt_netPowRailKw))
        ;; ③ 电压记号 3V3 / 3.3V / 12V / +5V / 5V0 / 0V9 / 1V25 / 1P8V
        (setq mv (apt_voltFind up))
        (if g
            (progn
                (setq grp 'gnd)
                (setq why (strcat "关键词 " g)))
            (if (or r mv)
                (progn
                    (setq grp 'pwr)
                    (if r
                        (setq why (strcat "关键词 " r))
                        (setq why (strcat "电压 " (sprintf nil "%d" mv) "mV"))))))
        (when grp
            (if sk
                (list 'skip (strcat "后缀 " sk " (本可算电源)") mv)
                (list grp why mv)))))

;;; ---------------------------------------------------------------------------
;;; 调色板(带缓存)
;;; ---------------------------------------------------------------------------
(defvar apt_netColorPalette nil)
(defvar apt_netColorReserved nil)
(setq apt_netColorPalette nil)
(setq apt_netColorReserved nil)
;; 保留槽个数的单一来源是 apt_cfg(见文件末尾 apt_cfgdef), 本文件顶层不再读
;; 自己 setq 出来的全局变量 —— 原因见 docs/SKILL方言坑.md 第 9 条:
;; 同一文件里顶层 setq 的全局量在本文件末尾的顶层读不到, 会报 unbound variable
;; 把整个 load 打挂, 该文件里的过程定义会全部丢失。

(procedure (apt_netColorLoadPalette)
    (unless apt_netColorPalette
        (setq apt_netColorPalette (axlColorGet 'all)))
    apt_netColorPalette)

;;; 调色板里已有同色则返回索引, 否则 nil
(procedure (apt_netColorIndexOf t_rgb)
    (let (all i hit)
        (setq all (apt_netColorLoadPalette))
        (setq i 1)
        (foreach rgb all
            (when (and (null hit) (equal rgb t_rgb))
                (setq hit i))
            (setq i (i + 1)))
        hit))

;;; 把缓存里第 idx 格换成新色(写完调色板后必须调, 否则缓存是旧的)
(procedure (apt_netPalSet t_idx t_rgb)
    (let (all i out)
        (setq all (apt_netColorLoadPalette))
        (setq i 1)
        (setq out nil)
        (foreach rgb all
            (if (equal i t_idx)
                (setq out (append out (list t_rgb)))
                (setq out (append out (list rgb))))
            (setq i (i + 1)))
        (setq apt_netColorPalette out)
        out))

;;; 取一个还没被占用的保留槽(调色板末尾)
(procedure (apt_netColorFreeSlot)
    (let (n k used hit reserveN)
        (setq n (axlColorGet 'count))
        (setq reserveN (apt_cfg 'netColorReserveN))
        (unless reserveN (setq reserveN 32))
        (setq k (n - reserveN))
        (when (k < 1) (setq k 1))
        (while (and (null hit) (k <= n))
            (setq used nil)
            (foreach kv apt_netColorReserved
                (when (equal (nth 1 kv) k) (setq used t)))
            (unless used (setq hit k))
            (setq k (k + 1)))
        hit))

;;; RGB -> 调色板索引(已有同色 / 已占槽 / 新占保留槽)
(procedure (apt_netColorAlloc t_rgb)
    (let (idx slot orig)
        (setq idx (apt_netColorIndexOf t_rgb))
        (unless idx
            (foreach kv apt_netColorReserved
                (when (and (null idx) (equal (car kv) t_rgb))
                    (setq idx (nth 1 kv)))))
        (unless idx
            (setq slot (apt_netColorFreeSlot))
            (when slot
                (setq orig (nth (slot - 1) (apt_netColorLoadPalette)))
                (axlColorSet slot t_rgb)
                (apt_netPalSet slot t_rgb)
                (setq apt_netColorReserved
                      (append apt_netColorReserved (list (list t_rgb slot orig))))
                (setq idx slot)
                (printf "[APTools]   调色板槽 %d 写入 RGB %L (原值 %L)\n" slot t_rgb orig)))
        idx))

;;; 还原保留槽
(procedure (apt_netColorFreePal)
    (let (n)
        (setq n 0)
        (foreach kv apt_netColorReserved
            (when (nth 2 kv)
                (axlColorSet (nth 1 kv) (nth 2 kv))
                (apt_netPalSet (nth 1 kv) (nth 2 kv))
                (setq n (n + 1))))
        (setq apt_netColorReserved nil)
        (printf "[APTools] 已还原 %d 个保留调色板槽\n" n)
        n))

;;; ---------------------------------------------------------------------------
;;; 随机取色
;;; ---------------------------------------------------------------------------
(defvar apt_netPowUsed nil)
(defvar apt_netPowGreyIdx nil)
(setq apt_netPowUsed nil)
(setq apt_netPowGreyIdx 0)

;;; 与已用颜色的区分度够不够(t_min 为各通道差之和的下限)
(procedure (apt_netPowDistinct t_rgb t_min)
    (let (ok d)
        (setq ok t)
        (foreach u apt_netPowUsed
            (when ok
                (setq d ((apt_abs ((car u) - (car t_rgb))) +
                         (apt_abs ((cadr u) - (cadr t_rgb))) +
                         (apt_abs ((caddr u) - (caddr t_rgb)))))
                (when (d < t_min) (setq ok nil))))
        ok))

;;; GND 系: 灰色系里随机(R=G=B)
;;; 电源:   六个色相区里随机, 保证是鲜艳可分辨的颜色
(procedure (apt_netPowPick t_grp)
    (let (try rgb a k ok lo hi)
        (setq lo (apt_cfg 'netColorGreyMin))
        (unless lo (setq lo 90))
        (setq hi (apt_cfg 'netColorGreyMax))
        (unless hi (setq hi 210))
        (setq try 0)
        (setq ok nil)
        (while (and (null ok) (try < 60))
            (if (equal t_grp 'gnd)
                (progn
                    (setq a (lo + (apt_rnd ((hi - lo) + 1))))
                    (setq rgb (list a a a)))
                (progn
                    (setq k (apt_rnd 6))
                    (setq a (apt_rnd 160))
                    (setq rgb (if (equal k 0) (list 255 a 0)
                               (if (equal k 1) (list (255 - a) 255 0)
                               (if (equal k 2) (list 0 255 a)
                               (if (equal k 3) (list 0 (255 - a) 255)
                               (if (equal k 4) (list a 0 255)
                                               (list 255 0 a)))))))))
            (when (apt_netPowDistinct rgb (if (equal t_grp 'gnd) 60 130))
                (setq ok t))
            (setq try (try + 1)))
        ;; 随机死活撞不出来时兜底, 按固定间距铺开
        (unless ok
            (if (equal t_grp 'gnd)
                (progn
                    (setq a (lo + (mod ((apt_netPowGreyIdx * 17) + 3)
                                       ((hi - lo) + 1))))
                    (setq rgb (list a a a)))
                (progn
                    (setq k (mod ((apt_netPowGreyIdx * 3) + 1) 6))
                    (setq a (apt_rnd 160))
                    (setq rgb (if (equal k 0) (list 255 a 0)
                               (if (equal k 1) (list (255 - a) 255 0)
                               (if (equal k 2) (list 0 255 a)
                               (if (equal k 3) (list 0 (255 - a) 255)
                               (if (equal k 4) (list a 0 255)
                                               (list 255 0 a))))))))))
        (setq apt_netPowUsed (append apt_netPowUsed (list rgb)))
        (setq apt_netPowGreyIdx (apt_netPowGreyIdx + 1))
        rgb))

;;; ---------------------------------------------------------------------------
;;; 报告: 控制台 + CSV
;;; ---------------------------------------------------------------------------
(procedure (apt_netPowCsv t_rows t_path)
    (let (p)
        (setq p (car (errset (outfile t_path "w") nil)))
        (if p
            (progn
                (fprintf p "group,net,reason,rgb,paletteSlot\n")
                (foreach r t_rows
                    (fprintf p "%s,%s,%s,%s,%s\n"
                             (nth 0 r) (nth 1 r) (nth 2 r) (nth 3 r) (nth 4 r)))
                (close p)
                (printf "[APTools] 识别报告已写出: %s\n" t_path)
                t_path)
            (progn
                (printf "[APTools] 识别报告写入失败: %s\n" t_path)
                nil))))

;;; ---------------------------------------------------------------------------
;;; 主流程: 识别 + (可选)随机刷色
;;;   返回 (GND数 电源数 排除数 其它数 上色数)
;;; ---------------------------------------------------------------------------
(procedure (apt_netPowRun t_doColor)
    (let (nets nm cls grp why nGnd nPwr nSkip nOther nSet rgb idx rows rep cnt tag)
        (setq nets (axlDBGetDesign)->nets)
        (setq nGnd 0)
        (setq nPwr 0)
        (setq nSkip 0)
        (setq nOther 0)
        (setq nSet 0)
        (setq rows nil)
        (setq apt_netPowUsed nil)
        (setq apt_netPowGreyIdx 0)
        (apt_netSeed)

        (when t_doColor
            (axlDBDisplayControl 'customColorEnabled t))

        (foreach nm nets
            (when (and nm nm->name)
                (setq cls (apt_netPowClass nm->name))
                (if (null cls)
                    (setq nOther (nOther + 1))
                    (progn
                        (setq grp (car cls))
                        (setq why (nth 1 cls))
                        (if (equal grp 'skip)
                            (progn
                                (setq nSkip (nSkip + 1))
                                (setq rows (append rows (list (list "排除" nm->name why "" "")))))
                            (progn
                                (if (equal grp 'gnd)
                                    (setq nGnd (nGnd + 1))
                                    (setq nPwr (nPwr + 1)))
                                (setq rgb (apt_netPowPick grp))
                                (setq idx nil)
                                (when t_doColor
                                    (setq idx (apt_netColorAlloc rgb))
                                    (if idx
                                        (progn
                                            (axlCustomColorObject nm idx)
                                            (setq nSet (nSet + 1)))
                                        (printf "[APTools]   %s 没有可用调色板槽, 未上色\n" nm->name)))
                                (setq rows (append rows (list
                                    (list (if (equal grp 'gnd) "GND系" "电源")
                                          nm->name why
                                          (sprintf nil "%L" rgb)
                                          (if idx (sprintf nil "%d" idx) "")))))))))))

        (printf "\n[APTools] ===== 电源网络识别 =====\n")
        (printf "[APTools] 合计: GND 系 %d 个 / 电源 %d 个 / 排除 %d 个 / 其它 %d 个%s\n"
                nGnd nPwr nSkip nOther
                (if t_doColor (sprintf nil " ; 已上色 %d 个" nSet) " ; 未刷色(仅识别)"))
        (foreach tag (list "GND系" "电源" "排除")
            (setq cnt 0)
            (foreach r rows (when (equal (nth 0 r) tag) (setq cnt (cnt + 1))))
            (when (cnt > 0)
                (if (equal tag "GND系")
                    (printf "[APTools]   -- GND 系 (灰色系随机) %d 个 --\n" cnt)
                    (if (equal tag "电源")
                        (printf "[APTools]   -- 电源 (随机彩) %d 个 --\n" cnt)
                        (printf "[APTools]   -- 被排除 (控制/反馈信号) %d 个 --\n" cnt)))
                (foreach r rows
                    (when (equal (nth 0 r) tag)
                        (if (equal tag "排除")
                            (printf "[APTools]     %s   (%s)\n" (nth 1 r) (nth 2 r))
                            (printf "[APTools]     %s   -> RGB %s  槽 %s   (%s)\n"
                                    (nth 1 r) (nth 3 r) (nth 4 r) (nth 2 r)))))))

        (when t_doColor
            (axlVisibleUpdate t))

        ;; 报告落盘(写不出也不影响刷色)
        (setq rep (car (errset (strcat apt_home "/Temp/netcolor_report.csv") nil)))
        (when rep
            (errset (apt_netPowCsv rows rep) nil))

        (list nGnd nPwr nSkip nOther nSet)))

;;; ---------------------------------------------------------------------------
;;; 辅助打印
;;; ---------------------------------------------------------------------------
(procedure (apt_netColorShowPalette)
    (let (all i)
        (setq all (apt_netColorLoadPalette))
        (setq i 1)
        (foreach rgb all
            (printf "  %3d : %L\n" i rgb)
            (setq i (i + 1)))
        (printf "[APTools] 调色板共 %d 色\n" (length all))))

(procedure (apt_netColorShowRules)
    (let (i)
        (printf "\n[APTools] ===== 电源网络识别规则 =====\n")
        (printf "[APTools] GND 系(灰色系随机) %d 条:\n" (length apt_netPowGndKw))
        (setq i 0)
        (foreach p apt_netPowGndKw
            (setq i (i + 1))
            (printf "  %2d. %s\n" i p))
        (printf "[APTools] 电源(随机彩) %d 条:\n" (length apt_netPowRailKw))
        (setq i 0)
        (foreach p apt_netPowRailKw
            (setq i (i + 1))
            (printf "  %2d. %s\n" i p))
        (printf "[APTools] 排除后缀 %d 条:\n" (length apt_netPowSkipSuf))
        (setq i 0)
        (foreach p apt_netPowSkipSuf
            (setq i (i + 1))
            (printf "  %2d. %s\n" i p))
        (printf "[APTools] 电压记号: 3V3 / 3.3V / 12V / +5V / 5V0 / 0V9 / 1V25 / 1P8V ... 取值 0.4V~60V\n")
        (when apt_netColorReserved
            (printf "[APTools] 已占用的保留槽:\n")
            (foreach kv apt_netColorReserved
                (printf "     槽 %s = RGB %L (原 %L)\n"
                        (nth 1 kv) (car kv) (nth 2 kv))))
        (length apt_netPowRailKw)))

;;; ---------------------------------------------------------------------------
;;; 清除 / 命令 / 菜单
;;; ---------------------------------------------------------------------------
(procedure (apt_netColorClear)
    (let (nets dbids n)
        (setq nets (axlDBGetDesign)->nets)
        (setq dbids nil)
        (foreach nm nets
            (when (axlIsCustomColored nm)
                (setq dbids (cons nm dbids))))
        (setq n (length dbids))
        (when dbids
            (axlClearObjectCustomColor dbids))
        (axlVisibleUpdate t)
        (printf "[APTools] 已清除 %d 个网络的自定义配色\n" n)
        n))

(procedure (apt_cmd_netPowScan)
    (let (r)
        (setq r (apt_netPowRun nil))
        (axlUIConfirm (sprintf nil
            "电源网络识别完成(未刷色)\n\nGND 系 : %d 个\n电源   : %d 个\n排除   : %d 个\n其它   : %d 个\n\n详细清单见命令窗口, 报告在 APTools/Temp/netcolor_report.csv"
            (nth 0 r) (nth 1 r) (nth 2 r) (nth 3 r)))))

(procedure (apt_cmd_netcolor)
    (let (r)
        (setq r (apt_netPowRun t))
        (axlUIConfirm (sprintf nil
            "电源网络随机刷色完成\n\nGND 系 : %d 个 (灰色系随机)\n电源   : %d 个 (随机彩)\n已上色 : %d 个\n排除   : %d 个\n\n想先看清单不刷色, 用菜单\"识别电源网络\"。"
            (nth 0 r) (nth 1 r) (nth 4 r) (nth 2 r)))))

(procedure (apt_cmd_netcolorClear)
    (axlUIConfirm (sprintf nil "已清除 %d 个网络的自定义配色。"
                           (apt_netColorClear))))

(procedure (apt_cmd_netcolorFree)
    (axlUIConfirm (sprintf nil "已还原 %d 个保留调色板槽。"
                           (apt_netColorFreePal))))

(procedure (apt_cmd_netcolorPal)
    (apt_netColorShowPalette)
    (axlUIConfirm "调色板已打印到命令窗口。"))

(procedure (apt_cmd_netcolorRule)
    (apt_netColorShowRules)
    (axlUIConfirm "识别规则已打印到命令窗口。"))

(axlCmdRegister "apt_netcolorscan"  'apt_cmd_netPowScan      ?cmdType "general")
(axlCmdRegister "apt_netcolor"      'apt_cmd_netcolor        ?cmdType "general")
(axlCmdRegister "apt_netcolorclear" 'apt_cmd_netcolorClear   ?cmdType "general")
(axlCmdRegister "apt_netcolorfree"  'apt_cmd_netcolorFree    ?cmdType "general")
(axlCmdRegister "apt_netcolorpal"   'apt_cmd_netcolorPal     ?cmdType "general")
(axlCmdRegister "apt_netcolorrule"  'apt_cmd_netcolorRule    ?cmdType "general")

(apt_cfgdef 'netColorReserveN 32)
(apt_cfgdef 'netColorGreyMin 90)
(apt_cfgdef 'netColorGreyMax 210)

(apt_menuSub "90_misc" apt_netcolor_submenu "识别电源网络"        "apt_netcolorscan")
(apt_menuSub "90_misc" apt_netcolor_submenu "随机刷色"            "apt_netcolor")
(apt_menuSub "90_misc" apt_netcolor_submenu "清除刷色"            "apt_netcolorclear")
(apt_menuSubSep "90_misc" apt_netcolor_submenu)
(apt_menuSub "90_misc" apt_netcolor_submenu "查看识别规则"        "apt_netcolorrule")
(apt_menuSub "90_misc" apt_netcolor_submenu "查看调色板"          "apt_netcolorpal")
(apt_menuSub "90_misc" apt_netcolor_submenu "释放保留调色板槽"    "apt_netcolorfree")

(printf "[APTools] APT_NetColor 已加载 (GND规则 %d / 电源规则 %d / 排除 %d; 保留槽 %d)\n"
        (length apt_netPowGndKw) (length apt_netPowRailKw)
        (length apt_netPowSkipSuf) (apt_cfg 'netColorReserveN))
