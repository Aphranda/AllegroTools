# Run this file from the Tcl command window in the open Capture design.
# First use report mode. Change mode to "apply" only after reviewing the log.

namespace eval ::normalizeSourcePart {
    variable mode "report"
    variable changed 0
    variable conflicts 0
}

proc ::normalizeSourcePart::getProp {partInst propertyName} {
    set property [DboTclHelper_sMakeCString $propertyName]
    set value [DboTclHelper_sMakeCString]
    $partInst GetEffectivePropStringValue $property $value
    return [DboTclHelper_sGetConstCharPtr $value]
}

proc ::normalizeSourcePart::getReference {partInst} {
    set reference [DboTclHelper_sMakeCString]
    $partInst GetReferenceDesignator $reference
    return [DboTclHelper_sGetConstCharPtr $reference]
}

proc ::normalizeSourcePart::setProp {partInst propertyName value} {
    set property [DboTclHelper_sMakeCString $propertyName]
    set newValue [DboTclHelper_sMakeCString $value]
    $partInst SetEffectivePropStringValue $property $newValue
}

proc ::normalizeSourcePart::visitPart {partInst} {
    variable firstPackage
    variable firstPart
    variable conflict

    set device [getProp $partInst "Device"]
    set sourceLibrary [getProp $partInst "Source Library"]
    set sourcePackage [getProp $partInst "Source Package"]
    set sourcePart [getProp $partInst "Source Part"]

    # Empty and inherited properties are not eligible for this normalization.
    if {$device == "" || $device == "<null>" || $sourceLibrary == "" || $sourceLibrary == "<null>" || $sourcePart == "" || $sourcePart == "<null>"} {
        return
    }

    set key "$device\x1f$sourceLibrary"
    if {![info exists firstPart($key)]} {
        set firstPackage($key) $sourcePackage
        set firstPart($key) $sourcePart
        return
    }

    if {$sourcePackage != $firstPackage($key) || $sourcePart != $firstPart($key)} {
        set conflict($key) 1
    }
}

proc ::normalizeSourcePart::applyPart {partInst} {
    variable mode
    variable firstPackage
    variable firstPart
    variable conflict
    variable changed

    set device [getProp $partInst "Device"]
    set sourceLibrary [getProp $partInst "Source Library"]
    set sourcePackage [getProp $partInst "Source Package"]
    set sourcePart [getProp $partInst "Source Part"]

    if {$device == "" || $device == "<null>" || $sourceLibrary == "" || $sourceLibrary == "<null>" || $sourcePart == "" || $sourcePart == "<null>"} {
        return
    }

    set key "$device\x1f$sourceLibrary"
    if {![info exists conflict($key)]} {
        return
    }

    set targetPackage $firstPackage($key)
    set targetPart $firstPart($key)
    if {$sourcePackage == $targetPackage && $sourcePart == $targetPart} {
        return
    }

    set reference [getReference $partInst]
    puts "$reference : Source Package '$sourcePackage' -> '$targetPackage'; Source Part '$sourcePart' -> '$targetPart'"

    if {$mode == "apply"} {
        setProp $partInst "Source Package" $targetPackage
        setProp $partInst "Source Part" $targetPart
        $partInst MarkModified
    }
    incr changed
}

proc ::normalizeSourcePart::forEachPart {callback} {
    set status [DboState]
    set session $::DboSession_s_pDboSession
    DboSession -this $session
    set design [$session GetActiveDesign]

    if {$design == "NULL"} {
        error "No active Capture design. Open the target .DSN first."
    }

    set schematicIter [$design NewViewsIter $status $::IterDefs_SCHEMATICS]
    set schematic [$schematicIter NextView $status]
    while {$schematic != "NULL"} {
        set pageIter [$schematic NewPagesIter $status]
        set page [$pageIter NextPage $status]
        while {$page != "NULL"} {
            set partIter [$page NewPartInstsIter $status]
            set part [$partIter NextPartInst $status]
            while {$part != "NULL"} {
                $callback $part
                set part [$partIter NextPartInst $status]
            }
            delete_DboPagePartInstsIter $partIter
            set page [$pageIter NextPage $status]
        }
        delete_DboSchematicPagesIter $pageIter
        set schematic [$schematicIter NextView $status]
    }
    delete_DboLibViewsIter $schematicIter
    $status -delete
}

proc ::normalizeSourcePart::run {} {
    variable mode
    variable firstPackage
    variable firstPart
    variable conflict
    variable changed
    variable conflicts

    array unset firstPackage
    array unset firstPart
    array unset conflict
    set changed 0
    set conflicts 0

    forEachPart ::normalizeSourcePart::visitPart
    foreach key [array names conflict] {
        incr conflicts
    }
    puts "Source Part conflict groups: $conflicts"

    forEachPart ::normalizeSourcePart::applyPart
    puts "Mode: $mode; affected instances: $changed"
    if {$mode == "report"} {
        puts "No properties were changed. Set ::normalizeSourcePart::mode to apply and run ::normalizeSourcePart::run again."
    } else {
        puts "Properties changed in memory. Use File > Save to write the .DSN."
    }
    DboTclHelper_sReleaseAllCreatedPtrs
}

::normalizeSourcePart::run
