;;; ============================================================================
;;; selftest_netcolor.il  --  APT_NetColor 识别逻辑自检 (ASCII only)
;;; ----------------------------------------------------------------------------
;;; 只调用 apt_netPowClass / apt_voltFind / apt_rnd / apt_netPowPick,
;;; 不访问数据库, 不需要打开 brd, 可以在 -nograph 下跑。
;;; 每个用例独立 errset, 单条出错不会中断整轮。
;;; ============================================================================

;;; --- 附带的方言探测: (defvar X <值>) 在同一次 load 的顶层能不能立刻读到? ---
(defvar aptTestPlainVar 32)
(defvar aptTestSameFileRead nil)
(setq aptTestSameFileRead (errset (if aptTestPlainVar t nil) nil))

;;; errset 语义: 表达式出错 -> 返回 nil (并打印错误); 表达式返回 nil -> 返回 (nil)
;;; 所以 (null e) 一定是"出错了", 不是"结果是 nil"。print 参数给 t 才打印错误文本。
(procedure (aptTestOne t_nm)
    (let (c e)
        (setq e (errset (apt_netPowClass t_nm) t))
        (if (null e)
            (printf "CLS  %-18s <ERROR: 见上面的 *Error* 行>\n" t_nm)
            (progn
                (setq c (car e))
                (if c
                    (printf "CLS  %-18s %-5s %s\n" t_nm (car c) (nth 1 c))
                    (printf "CLS  %-18s -\n" t_nm))))))

(procedure (aptTestList t_title t_names)
    (printf "\n=== %s ===\n" t_title)
    (foreach nm t_names (aptTestOne nm)))

(procedure (aptTestAll)
    (let (i)
        (aptTestList "A. GND family (expect gnd)"
            (list "GND" "AGND" "DGND" "PGND" "FGND" "SGND" "CGND" "MGND"
                  "GNDA" "GND0" "GND_1" "GND12" "VSS" "VSSA" "VSSD" "VSSIO"
                  "AVSS" "EARTH" "CHASSIS" "GROUND" "0V"))

        (aptTestList "B. Power rails (expect pwr)"
            (list "VCC" "VDD" "VEE" "VPP" "VTT" "VREF" "VBUS" "VUSB" "VBAT"
                  "VSYS" "VMAIN" "VIN" "VOUT" "VIO" "AVDD" "DVDD" "PVDD"
                  "AVCC" "DVCC" "VCCIO" "VCCINT" "VCCAUX" "VDDCORE" "VDDA"
                  "VDDO" "V33" "V18" "PWR" "POWER" "VBUCK" "VPHASE" "VPWR"
                  "3V3" "3.3V" "1V8" "1.2V" "5V" "12V" "+5V" "-12V" "N12V"
                  "24V" "48V" "0V9" "1V25" "2V5" "5V0" "12V0" "VCC3V3"
                  "VDD_1V8" "VCC5V0" "P12V" "1P8V" "3P3V" "3V3_A" "5V_STBY"))

        (aptTestList "C. Excluded control/feedback (expect skip)"
            (list "PWR_EN" "VCC_EN" "3V3_EN" "VBUS_PG" "PWRGD" "PWROK"
                  "VCC_FB" "VCC_SENSE" "3V3_OV" "VDD_DET" "GND_PG" "VCC_CLK"
                  "VCC_MON" "VDDO_TEMP" "5V_SEL"))

        (aptTestList "D. Ordinary signals (expect -, must NOT be listed as excluded)"
            (list "TX_P" "RX_N" "SPI_CLK" "SPI_CS" "SDA" "SCL" "GPIO5"
                  "ADC_IN0" "N00001" "RESET_N" "LED1" "USB_DM" "D0" "DATA3"
                  "TEMP" "SEL0" "MODE1" "NMI" "TDO" "CTRL1" "STAT" "MON1"
                  "VCC_CURRENT"))

        (aptTestList "E. Voltage token edge cases"
            (list "3V3" "3.3V" "12V" "+5V" "5V0" "0V9" "1V25" "1P8V" "3P3V"
                  "13V3" "DDR13V3" "100V" "0V" "DATA0V" "TXD3" "VCC" "5"))

        (printf "\n=== F. RNG / random color picks ===\n")
        (printf "seed(timestamp string) : %L\n" (errset (apt_netSeed) nil))
        (printf "RND  (rnd 100) x16 : ")
        (setq i 0)
        (while (i < 16)
            (printf "%L " (errset (apt_rnd 100) nil))
            (setq i (i + 1)))
        (printf "\n")

        (setq apt_netPowUsed nil)
        (setq apt_netPowGreyIdx 0)
        (printf "GREY (6 nets)      : ")
        (setq i 0)
        (while (i < 6)
            (printf "%L " (errset (apt_netPowPick 'gnd) nil))
            (setq i (i + 1)))
        (printf "\n")

        (setq apt_netPowUsed nil)
        (setq apt_netPowGreyIdx 0)
        (printf "PWR  (8 nets)      : ")
        (setq i 0)
        (while (i < 8)
            (printf "%L " (errset (apt_netPowPick 'pwr) nil))
            (setq i (i + 1)))
        (printf "\n")

        (printf "GREY cfg range     : min=%L max=%L\n"
                (errset (apt_cfg 'netColorGreyMin) nil)
                (errset (apt_cfg 'netColorGreyMax) nil))

        (printf "\n=== G. dialect diagnostics ===\n")
        (printf "(defvar X 32) readable at own load's top level : %L\n" aptTestSameFileRead)
        (printf "rule tables bound (GndKw/RailKw/SkipSuf)       : %L %L %L\n"
                (errset (if apt_netPowGndKw t nil) nil)
                (errset (if apt_netPowRailKw t nil) nil)
                (errset (if apt_netPowSkipSuf t nil) nil))
        (printf "ReserveN / GreyIdx                             : %L %L\n"
                (errset apt_netColorReserveN nil)
                (errset apt_netPowGreyIdx nil))
        (printf "palette count                                  : %L\n"
                (errset (axlColorGet 'count) nil))
        (printf "\nSELFTEST DONE\n")
        t))
