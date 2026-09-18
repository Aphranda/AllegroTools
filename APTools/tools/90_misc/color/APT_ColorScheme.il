;;; ============================================================================
;;; APT_ColorScheme.il  --  颜色方案 (从 FanySkill V1.8 FYCOL 移植 + 表驱动重构)
;;; 阶段: 90_misc (辅助功能)      子菜单: 颜色方案
;;; ----------------------------------------------------------------------------
;;; 来源: FanySkill V1.8-CESC-KEY\SkillCode\FanySkill_Color_Setting.il
;;;       原命令 FYCOL / FYCOL1 / FYCOL2, 作者 王凯, 2020-01-01
;;;       配色数值与原版一致; 结构做了重构
;;;
;;; 相比原版的改动(纯结构优化, 配色结果不变)
;;;   1. 三套方案合并成 apt_colorSchemes 表 —— 加新方案只加一行, 不再复制函数
;;;   2. 固定配色抽成 apt_colorFixedGroups / apt_colorFixedLayers 两张表
;;;   3. 原版每设一层就调一次 axlVisibleUpdate(t)(几十次重绘), 这里只在最后调一次
;;;   4. 原来的全局变量(etchcolorslist 等)全部收进 let, 不与别的工具打架
;;;
;;; 编码: 必须 GBK(cp936)。SKILL 方言: 函数名不能含 '-'。
;;; ============================================================================

(defvar apt_color_submenu "颜色方案")

;;; 调色板覆写用的 RGB (与原版一致)
(defvar apt_color_white   (list 255 255 255))
(defvar apt_color_darkred (list 169 5 18))
(defvar apt_color_green   (list 0 221 0))
(defvar apt_color_lblue   (list 100 100 255))
(defvar apt_color_magenta (list 255 0 255))

;;; ---------------------------------------------------------------------------
;;; 方案表: (显示名  16 个信号层配色  第 63 号调色板槽的值)
;;;   信号层顺序 = BOTTOM 在最前, 其后是 TOP、内层... (与原版一致)
;;;   三套方案数值直接照搬 FYCOL / FYCOL1 / FYCOL2
;;; ---------------------------------------------------------------------------
(defvar apt_colorSchemes nil)
(setq apt_colorSchemes (list
    (list "配色方案 1"
          (list 12 5 40 43 36 53 41 65 73 80 111 119 6 10 18 24)
          apt_color_magenta)
    (list "配色方案 2"
          (list 64 5 43 36 53 45 65 73 80 111 119 6 10 18 24 40)
          apt_color_white)
    (list "配色方案 3"
          (list 5 41 43 36 53 45 65 73 80 111 119 6 10 18 24 40)
          apt_color_white)))

;;; 三套方案共用的调色板覆写 (与原版一致)
(defvar apt_colorPalette nil)
(setq apt_colorPalette (list
    (list 5  apt_color_darkred)
    (list 41 apt_color_green)
    (list 45 apt_color_lblue)))

;;; 固定配色: 整个"类"下的所有子类同色
(defvar apt_colorFixedGroups nil)
(setq apt_colorFixedGroups (list
    (list "Drc Error Class"   150)
    (list "Via Class"          28)
    (list "Boundary"            9)
    (list "Anti Etch"          22)
    (list "Constraint Region"  24)
    (list "Via Keepout"        40)
    (list "Route Keepout"     200)))

;;; 固定配色: 单个 类/子类
(defvar apt_colorFixedLayers nil)
(setq apt_colorFixedLayers (list
    (list "PACKAGE GEOMETRY/SILKSCREEN_TOP"    34)
    (list "PACKAGE GEOMETRY/SILKSCREEN_BOTTOM" 28)
    (list "BOARD GEOMETRY/SILKSCREEN_TOP"      24)
    (list "BOARD GEOMETRY/SILKSCREEN_BOTTOM"   28)
    (list "BOARD GEOMETRY/OUTLINE"            120)
    (list "REF DES/SILKSCREEN_TOP"             24)
    (list "REF DES/SILKSCREEN_BOTTOM"          28)
    (list "ROUTE KEEPIN/ALL"                  200)))

;;; ---------------------------------------------------------------------------
;;; 给单个 layer 设颜色。axlVisibleUpdate 不在这里调 —— 统一放到最后调一次
;;; ---------------------------------------------------------------------------
(procedure (apt_colorSetLayer t_layer t_colorIndex)
    (let (obj)
        (setq obj (axlLayerGet t_layer))
        (when obj
            obj->color = t_colorIndex
            (axlLayerSet obj))
        obj))

;;; 某组类下的所有子类统一上色
(procedure (apt_colorSetGroup t_groupName t_colorIndex)
    (let (param members one)
        (setq param (errset (axlGetParam (strcat "paramLayerGroup:" t_groupName)) t))
        (when param
            (setq param (car param))
            (when param
                (setq members (param->groupMembers))
                (foreach one members
                    (apt_colorSetLayer (strcat t_groupName "/" one) t_colorIndex))))))

;;; ---------------------------------------------------------------------------
;;; 取信号层列表: BOTTOM 提前到首位
;;; (与原版 append(list("BOTTOM") reverse(cdr(reverse(etchl)))) 等价)
;;; ---------------------------------------------------------------------------
(procedure (apt_colorEtchLayers)
    (let (etchl)
        (setq etchl (axlGetParam "paramLayerGroup:ETCH")->groupMembers)
        (append (list "BOTTOM") (reverse (cdr (reverse etchl))))))

;;; ---------------------------------------------------------------------------
;;; 主配色逻辑 (原 Quick_ColorSetTr)
;;; ---------------------------------------------------------------------------
(procedure (apt_colorApply t_etchColors)
    (let (etchlayers etchlnum i lay idx kv)
        (setq etchlayers (apt_colorEtchLayers))
        (setq etchlnum (length etchlayers))

        ;; 信号层: PIN/<层> 与 ETCH/<层> 同色
        (setq i 0)
        (while (i < etchlnum)
            (setq lay (nth i etchlayers))
            (setq idx (nth i t_etchColors))
            (when idx
                (apt_colorSetLayer (strcat "PIN/"  lay) idx)
                (apt_colorSetLayer (strcat "ETCH/" lay) idx))
            (setq i (i + 1)))

        ;; 固定配色
        (foreach kv apt_colorFixedGroups
            (apt_colorSetGroup (car kv) (cadr kv)))
        (foreach kv apt_colorFixedLayers
            (apt_colorSetLayer (car kv) (cadr kv)))

        ;; 全部设完只重绘一次
        (axlVisibleUpdate t)
        etchlnum))

;;; ---------------------------------------------------------------------------
;;; 套用第 n 套方案
;;; ---------------------------------------------------------------------------
(procedure (apt_colorScheme t_n)
    (let (sc kv n)
        (setq sc (nth (t_n - 1) apt_colorSchemes))
        (if (null sc)
            (progn
                (printf "[APTools] 没有第 %L 套配色方案(共 %d 套)\n" t_n (length apt_colorSchemes))
                nil)
            (progn
                (foreach kv apt_colorPalette
                    (axlColorSet (car kv) (cadr kv)))
                (axlColorSet 63 (nth 2 sc))
                (setq n (apt_colorApply (nth 1 sc)))
                (printf "[APTools] %s 已套用 (%d 个信号层 + 固定类)\n" (car sc) n)
                t))))

;;; 列出所有方案(便于确认编号)
(procedure (apt_colorList)
    (let (i sc)
        (setq i 1)
        (foreach sc apt_colorSchemes
            (printf "  %d : %s\n" i (car sc))
            (setq i (i + 1)))
        (printf "[APTools] 共 %d 套方案; 数值在 apt_colorSchemes\n" (length apt_colorSchemes))
        (length apt_colorSchemes)))

;;; ---------------------------------------------------------------------------
;;; 命令 + 菜单
;;; ---------------------------------------------------------------------------
(procedure (apt_cmd_color1) (apt_colorScheme 1))
(procedure (apt_cmd_color2) (apt_colorScheme 2))
(procedure (apt_cmd_color3) (apt_colorScheme 3))

(axlCmdRegister "apt_color1"    'apt_cmd_color1  ?cmdType "general")
(axlCmdRegister "apt_color2"    'apt_cmd_color2  ?cmdType "general")
(axlCmdRegister "apt_color3"    'apt_cmd_color3  ?cmdType "general")
(axlCmdRegister "apt_colorlist" 'apt_colorList   ?cmdType "general")

(apt_menuSub "90_misc" apt_color_submenu "配色方案 1" "apt_color1")
(apt_menuSub "90_misc" apt_color_submenu "配色方案 2" "apt_color2")
(apt_menuSub "90_misc" apt_color_submenu "配色方案 3" "apt_color3")
(apt_menuSubSep "90_misc" apt_color_submenu)
(apt_menuSub "90_misc" apt_color_submenu "列出全部方案" "apt_colorlist")

(printf "[APTools] APT_ColorScheme 已加载 (%d 套方案; 改数值见 apt_colorSchemes)\n"
        (length apt_colorSchemes))
