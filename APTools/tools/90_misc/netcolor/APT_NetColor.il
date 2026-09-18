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

;;; 排除(一): 后缀命中即"不是电源"(控制/反馈/状态类)
;;;   每条都必须带 $ 走后缀匹配。若写成包含匹配, "PG" 会误伤 PGND,
;;;   "EN" 会误伤 VCC_CURRENT(里面含 EN), 所以一律带 $。
;;;   控制信号常带电平尾缀或序号(ULPI0_VBUS_SEL_L), 光靠后缀撞不到 ——
;;;   apt_netPowClass 会把末尾那个单电平字母去掉再查一次这张表。
(defvar apt_netPowSkipSuf nil)
(setq apt_netPowSkipSuf (list
    "EN$" "ENB$" "ENABLE$" "PG$" "PGOOD$" "GOOD$" "PWRGD$" "PWROK$" "OK$"
    "FLT$" "FAULT$" "ALERT$" "RST$" "RESET$" "RESETN$" "NRST$" "TRIP$"
    "OC$" "OV$" "UV$" "DRV$" "GATE$" "COMP$" "CLK$" "SYNC$" "DET$" "FB$"
    "SENSE$" "SNS$" "NMI$" "IRQ$" "CS$" "SCL$" "SDA$" "STAT$" "STATUS$"
    "MON$" "ADC$" "TEMP$" "WDI$" "WDO$" "PWM$" "CTRL$" "CTL$" "SEL$" "MODE$"
    "TEST$" "TCK$" "TMS$" "TDI$" "TDO$" "TRST$"
    "NC$"))

;;; 排除(二): "包含"即排除(不分位置)
;;;   2026-09-18 真板实测(1211 网络)发现 51 个采样对漏进了电源组, 例如:
;;;     VCC1V2_ISEN_P/N       电流检测
;;;     VCCINT_AMS_VIN_R_P/N  开尔文采样
;;;     MGT1V8_SNS_P          远端采样
;;;     VCCINT_SEN_CORE_N     sense
;;;   它们的尾巴是 _P/_N 或 _SNS_P, **后缀表永远撞不到**, 所以改成按"含关键词"排除。
;;;   还有 MIO_1V8_RESERVED_GPIO0 这种"信号名里恰好含 1V8"的, 也在这张表里挡掉。
;;;   副作用: 名字里恰好含这些词的电源轨也会被排除, 核对时看报告"被排除"那一档即可。
(defvar apt_netPowSkipAny nil)
(setq apt_netPowSkipAny (list
    ;; 采样/检测类 —— VCC/VDD 名字里带这些的都不是电源轨本身
    "ISEN" "SNS" "SENSE" "VSNS" "CSEN" "VSEN" "IOUT" "VINR" "SEN"
    ;; 控制类
    "PWM"
    ;; 信号名里恰好含电压记号或电源关键词的
    ;;   MIO_1V8_RESERVED_GPIO0  (GPIO 信号名字里带 1V8)
    ;;   FAN_TACH_12V            (风扇测速信号名字里带 12V)
    "GPIO" "RESERVED" "SPARE" "TEST" "TACH"))

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
;;;   的名字才去看排除规则。否则 SPI_CS、SDA、TEMP、SEL0 这类普通信号全都会
;;;   被当成"排除", 把报告淹掉。
;;;
;;;   排除走两张表:
;;;     apt_netPowSkipAny  含关键词(采样对这类尾巴认不出来的, 见那张表的说明)
;;;     apt_netPowSkipSuf  后缀(控制/状态类), 会先把末尾电平字母去掉再查一次
;;; ---------------------------------------------------------------------------
(procedure (apt_netPowClass t_nm)
    (let (up cp cpTrim skAny skSuf lastc n g r mv grp why)
        (setq up (upperCase t_nm))
        (setq cp (apt_nosep up))
        ;; 去掉末尾单个电平字母: ULPI0_VBUS_SEL_L -> ULPI0_VBUSSEL
        (setq cpTrim cp)
        (setq n (strlen cp))
        (when (n > 1)
            (setq lastc (apt_ch cp (n - 1)))
            (when (or (equal lastc "L") (equal lastc "H")
                      (equal lastc "N") (equal lastc "P"))
                (setq cpTrim (apt_sub cp 0 (n - 1)))))
        ;; 排除(二) 含关键词 -> 排除(一) 后缀
        (setq skAny (apt_patAny cp apt_netPowSkipAny))
        (setq skSuf nil)
        (unless skAny
            (setq skSuf (apt_patAny cp apt_netPowSkipSuf))
            (unless skSuf
                (setq skSuf (apt_patAny cpTrim apt_netPowSkipSuf))))
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
            (if (or skAny skSuf)
                (list 'skip
                      (if skAny
                          (strcat "含 " skAny " (本可算电源)")
                          (strcat "后缀 " skSuf " (本可算电源)"))
                      mv)
                (list grp why mv)))))

;;; ---------------------------------------------------------------------------
;;; 电源"族"归并 —— 给"按电源族刷色"用
;;;
;;;   为什么需要: 大板上电源网络常有 100+ 个(实测一块 1715 网络的板上有 187 个),
;;;   一网一色既人眼分不出来, 调色板也不够(总共 192 色)。按族归并后只剩二三十族。
;;;
;;;   取自真板数据的例子:
;;;     VCC5V_LMK_BUF1/2/3, VCC5V_TCXO, VCC5V_VCXO   -> 族 VCC5V
;;;     VCC1V8, VCC1V8_BUS, VCC1V8_SWITCH            -> 族 VCC1V8
;;;     UTIL_5V0, UTIL_5V0_A                         -> 族 UTIL_5V0
;;;     UTIL_3V3, UTIL_3V3_SW                        -> 族 UTIL_3V3   (与 5V0 分开)
;;;     ADC_AVCC, ADC_AVCC_BUS                       -> 族 ADC_AVCC
;;;     DAC_AVTT, DAC_AVTT_BUS                       -> 族 DAC_AVTT
;;;     8A34001_VDDO_Q0..Q11                         -> 族 8A34001_VDDO
;;;     MGTAVCC, MGTAVCC_BUS                         -> 族 MGTAVCC
;;;
;;;   规则(两步, 刻意做得简单可预期):
;;;     1) 取第一段。若第一段里已经有电压记号(如 VCC5V / VCC1V8 / VCC12),
;;;        就到此为止 —— 这样 VCC5V_LMK_* 全部归成 VCC5V。
;;;     2) 否则往后找第一个"既不是修饰词、也不是序号"的段并进来。
;;;        所以 UTIL_5V0 会并上 5V0(与 UTIL_3V3 分开),
;;;        而 MGTAVCC_BUS 只会停在 MGTAVCC(BUS 是修饰词)。
;;;
;;;   觉得归并得不合适就改 apt_netPowFamilyMod, 或直接用一网一色那个菜单项。
;;; ---------------------------------------------------------------------------
(defvar apt_netPowFamilyMod nil)
(setq apt_netPowFamilyMod (list
    "BUS" "SW" "SWITCH" "BUF" "VCO" "VCXO" "TCXO" "OSC" "PLL" "CP" "CLK"
    "FOD" "Q" "IN" "OUT" "HS" "WAKE" "SNS" "SEN" "ISEN" "TACH"
    "A" "B" "C" "D" "E" "F" "L" "H" "N" "P" "R"))

;;; 这一段是不是"修饰词/序号"(是的话不参与族名)
(procedure (apt_netFamSkip t_tok)
    (let (hit)
        (setq hit nil)
        (foreach m apt_netPowFamilyMod
            (when (equal t_tok m) (setq hit t)))
        (when (null hit)
            (when (or (rexMatchp "^[0-9]+$" t_tok)
                      (rexMatchp "^[A-Z]+[0-9]+$" t_tok))
                (setq hit t)))
        hit))

;;; 按 '_' 切成段(不用 split, 各版本 SKILL 的写法不一定一致)
(procedure (apt_netSplit t_s)
    (let (n i out cur ch)
        (setq n (strlen t_s))
        (setq i 0)
        (setq cur "")
        (setq out nil)
        (while (i < n)
            (setq ch (apt_ch t_s i))
            (if (equal ch "_")
                (progn
                    (setq out (append out (list cur)))
                    (setq cur ""))
                (setq cur (strcat cur ch)))
            (setq i (i + 1)))
        (append out (list cur))))

;;; 取族名(入参用原名即可, 内部转大写)
;;;   注意: 变量名不能用 t —— t 是 SKILL 的保留字(let 会报 illegal variable name)
(procedure (apt_netPowFamily t_nm)
    (let (toks n i key done tok)
        (setq toks (apt_netSplit (upperCase t_nm)))
        (setq n (length toks))
        (setq key (car toks))
        ;; 第一段里已有电压记号 -> 到此为止
        (unless (apt_voltFind (car toks))
            (setq i 1)
            (setq done nil)
            (while (and (null done) (i < n))
                (setq tok (nth i toks))
                (unless (apt_netFamSkip tok)
                    (setq key (strcat key "_" tok))
                    (setq done t))
                (setq i (i + 1))))
        key))

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
;;;   返回 (GND数 电源数 排除数 其它数 上色数 无槽未上色数)
;;; ---------------------------------------------------------------------------
(procedure (apt_netPowRun t_doColor t_byFamily)
    (let (nets nm cls grp why fam byFam famMap nGnd nPwr nSkip nOther nSet nNoSlot rgb idx rows rep cnt tag nWant nSlot)
        (setq nets (axlDBGetDesign)->nets)
        (setq nGnd 0)
        (setq nPwr 0)
        (setq nSkip 0)
        (setq nOther 0)
        (setq nSet 0)
        (setq nNoSlot 0)
        (setq rows nil)
        (setq famMap nil)
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
                                ;; 族名: 只对电源算(GND 系仍按网络各自随机灰阶)
                                (setq fam nil)
                                (when (equal grp 'pwr)
                                    (setq fam (apt_netPowFamily nm->name))
                                    (when fam
                                        (setq why (strcat why " ; 族 " fam))))
                                (setq byFam (and t_doColor t_byFamily fam))
                                (setq rgb nil)
                                (setq idx nil)
                                ;; ---- 按族: 先找这一族已经分配过的颜色 ----
                                (when byFam
                                    (foreach fe famMap
                                        (when (and (null idx) (equal (car fe) fam))
                                            (setq rgb (nth 1 fe))
                                            (setq idx (nth 2 fe)))))
                                ;; ---- 需要新颜色就随机一个 ----
                                (when (null idx)
                                    (setq rgb (apt_netPowPick grp))
                                    (when t_doColor
                                        (setq idx (apt_netColorAlloc rgb))
                                        (when (and idx byFam)
                                            (setq famMap (append famMap
                                                                 (list (list fam rgb idx)))))))
                                (when (and t_doColor idx)
                                    (axlCustomColorObject nm idx)
                                    (setq nSet (nSet + 1)))
                                (when (and t_doColor (null idx))
                                    (setq nNoSlot (nNoSlot + 1))
                                    (when (equal nNoSlot 1)
                                        (printf "[APTools]   ... 调色板保留槽已用尽, 之后的网络不再上色\n")))
                                (setq rows (append rows (list
                                    (list (if (equal grp 'gnd) "GND系" "电源")
                                          nm->name why
                                          (sprintf nil "%L" rgb)
                                          (if idx (sprintf nil "%d" idx) "")))))))))))

        (printf "\n[APTools] ===== 电源网络识别%s =====\n"
                (if t_doColor
                    (if t_byFamily " (按电源族刷色)" " (一网一色)")
                    " (只识别)"))
        (printf "[APTools] 合计: GND 系 %d 个 / 电源 %d 个 / 排除 %d 个 / 其它 %d 个%s\n"
                nGnd nPwr nSkip nOther
                (if t_doColor (sprintf nil " ; 已上色 %d 个" nSet) " ; 未刷色(仅识别)"))
        ;; 调色板容量提示 —— 网络数超过保留槽时会有一部分上不了色, 别让它静默发生
        (when t_doColor
            (setq nWant (nGnd + nPwr))
            (setq nSlot (apt_cfg 'netColorReserveN))
            (unless nSlot (setq nSlot 32))
            (when (nNoSlot > 0)
                (printf "[APTools] !! 有 %d 个网络没有可用调色板槽, 未上色\n" nNoSlot)
                (printf "[APTools] !! 需要 %d 个颜色, 保留槽只有 %d 个(调色板共 %d 色)\n"
                        nWant nSlot (axlColorGet 'count))
                (printf "[APTools] !! 可加大保留槽: (apt_cfgset 'netColorReserveN 96), 代价是覆盖更多调色板原有颜色\n")))
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

        (list nGnd nPwr nSkip nOther nSet nNoSlot)))

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
        (printf "[APTools] 排除后缀 %d 条(会先去末尾电平字母再查):\n" (length apt_netPowSkipSuf))
        (setq i 0)
        (foreach p apt_netPowSkipSuf
            (setq i (i + 1))
            (printf "  %2d. %s\n" i p))
        (printf "[APTools] 排除关键词 %d 条(名字里含即排除):\n" (length apt_netPowSkipAny))
        (setq i 0)
        (foreach p apt_netPowSkipAny
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
        (setq r (apt_netPowRun nil nil))
        (axlUIConfirm (sprintf nil
            "电源网络识别完成(未刷色)\n\nGND 系 : %d 个\n电源   : %d 个\n排除   : %d 个\n其它   : %d 个\n\n详细清单见命令窗口, 报告在 APTools/Temp/netcolor_report.csv"
            (nth 0 r) (nth 1 r) (nth 2 r) (nth 3 r)))))

(procedure (apt_cmd_netcolor)
    (let (r ns)
        (setq r (apt_netPowRun t nil))
        (setq ns (nth 5 r))
        (axlUIConfirm (sprintf nil
            "电源网络随机刷色(一网一色)完成\n\nGND 系 : %d 个 (灰色系随机)\n电源   : %d 个 (每网一个随机色)\n已上色 : %d 个\n排除   : %d 个%s"
            (nth 0 r) (nth 1 r) (nth 4 r) (nth 2 r)
            (if (ns > 0)
                (sprintf nil "\n\n注意: 还有 %d 个网络没有可用调色板槽, 未能上色。\n网络多时建议改用菜单的「按电源族刷色」。" ns)
                "")))))

;;; 按电源族刷色: 同一族共用一色, 网络多的大板用这个
(procedure (apt_cmd_netcolorFam)
    (let (r ns)
        (setq r (apt_netPowRun t t))
        (setq ns (nth 5 r))
        (axlUIConfirm (sprintf nil
            "电源网络按族刷色完成\n\n同一族的网络共用一色(如 VCC5V_LMK_BUF1/2/3 同色)\nGND 系 : %d 个 (各自随机灰阶)\n电源   : %d 个 (按族共用随机彩)\n已上色 : %d 个\n排除   : %d 个%s"
            (nth 0 r) (nth 1 r) (nth 4 r) (nth 2 r)
            (if (ns > 0)
                (sprintf nil "\n\n注意: 还有 %d 个网络没有可用调色板槽。" ns)
                "")))))

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
(axlCmdRegister "apt_netcolorfam"   'apt_cmd_netcolorFam     ?cmdType "general")
(axlCmdRegister "apt_netcolorclear" 'apt_cmd_netcolorClear   ?cmdType "general")
(axlCmdRegister "apt_netcolorfree"  'apt_cmd_netcolorFree    ?cmdType "general")
(axlCmdRegister "apt_netcolorpal"   'apt_cmd_netcolorPal     ?cmdType "general")
(axlCmdRegister "apt_netcolorrule"  'apt_cmd_netcolorRule    ?cmdType "general")

(apt_cfgdef 'netColorReserveN 32)
(apt_cfgdef 'netColorGreyMin 90)
(apt_cfgdef 'netColorGreyMax 210)

(apt_menuSub "90_misc" apt_netcolor_submenu "识别电源网络"        "apt_netcolorscan")
(apt_menuSub "90_misc" apt_netcolor_submenu "按电源族刷色"        "apt_netcolorfam")
(apt_menuSub "90_misc" apt_netcolor_submenu "随机刷色(每网一色)"  "apt_netcolor")
(apt_menuSub "90_misc" apt_netcolor_submenu "清除刷色"            "apt_netcolorclear")
(apt_menuSubSep "90_misc" apt_netcolor_submenu)
(apt_menuSub "90_misc" apt_netcolor_submenu "查看识别规则"        "apt_netcolorrule")
(apt_menuSub "90_misc" apt_netcolor_submenu "查看调色板"          "apt_netcolorpal")
(apt_menuSub "90_misc" apt_netcolor_submenu "释放保留调色板槽"    "apt_netcolorfree")

(printf "[APTools] APT_NetColor 已加载 (GND规则 %d / 电源规则 %d / 排除后缀 %d / 排除关键词 %d; 保留槽 %d)\n"
        (length apt_netPowGndKw) (length apt_netPowRailKw)
        (length apt_netPowSkipSuf) (length apt_netPowSkipAny)
        (apt_cfg 'netColorReserveN))
