# Import Capture .EXP property values by reference designator instead of EXP's
# internal object ID. This works around ORCAP-1705 on converted legacy designs.
#
# 1. Update expFile and fieldsToImport below.
# 2. Run once in report mode and review the Capture Tcl window.
# 3. Set mode to "apply", run again, then use File > Save in Capture.

namespace eval ::importPropertiesByReference {
    variable mode "report"
    variable expFile "F:/1.Hardware/GTS_PPA1/08.CTL-SYNCTRIG4F4-HASL/Allegro/CTL-SYNCTRIG4F4-HASL.EXP"

    # Add only the property columns that were intentionally edited in the EXP.
    # Examples: {"PCB Footprint" "Manufacturer Part" "Source Package" "Source Part"}
    variable fieldsToImport {"Source Package" "Source Part"}
    variable partsByReference
    variable rowsByReference
    variable changed 0
    variable skipped 0
}

proc ::importPropertiesByReference::unquoteField {field} {
    if {[string length $field] < 2 || [string index $field 0] ne "\"" || [string index $field end] ne "\""} {
        error "EXP field is not quoted: $field"
    }
    return [string map {\"\" \"} [string range $field 1 end-1]]
}

proc ::importPropertiesByReference::readExp {} {
    variable expFile
    variable fieldsToImport
    variable rowsByReference

    if {![file exists $expFile]} {
        error "EXP file not found: $expFile"
    }

    # Capture generated this file in the local Windows code page. Do not convert
    # it to UTF-8 before using either Capture's importer or this workaround.
    set channel [open $expFile r]
    fconfigure $channel -encoding [encoding system] -translation auto
    set designLine [gets $channel]
    set headerLine [gets $channel]
    if {$designLine eq "" || $headerLine eq ""} {
        close $channel
        error "EXP file must contain DESIGN and HEADER lines"
    }

    set rawHeaders [split $headerLine "\t"]
    set headerLineFields {}
    foreach field $rawHeaders {
        lappend headerLineFields [unquoteField $field]
    }
    if {[lindex $headerLineFields 0] ne "HEADER" || [lindex $headerLineFields 1] ne "ID" || [lindex $headerLineFields 2] ne "Part Reference"} {
        close $channel
        error "Unexpected EXP header; expected HEADER, ID, Part Reference"
    }
    # HEADER is a row marker only; the data records start directly at ID.
    set headerNames [lrange $headerLineFields 1 end]

    array unset rowsByReference
    set lineNumber 2
    while {[gets $channel line] >= 0} {
        incr lineNumber
        if {$line eq ""} {
            continue
        }
        set rawValues [split $line "\t"]
        if {[llength $rawValues] != [llength $headerNames]} {
            close $channel
            error "EXP line $lineNumber has [llength $rawValues] columns; expected [llength $headerNames]"
        }
        set values {}
        foreach field $rawValues {
            lappend values [unquoteField $field]
        }
        set reference [lindex $values 1]
        if {$reference eq "" || $reference eq "<null>"} {
            close $channel
            error "EXP line $lineNumber has no Part Reference"
        }
        foreach property $fieldsToImport {
            set index [lsearch -exact $headerNames $property]
            if {$index < 0} {
                close $channel
                error "Property '$property' is not a column in the EXP file"
            }
            set rowsByReference($reference,$property) [lindex $values $index]
        }
    }
    close $channel
}

proc ::importPropertiesByReference::getReference {partInst} {
    set reference [DboTclHelper_sMakeCString]
    $partInst GetReferenceDesignator $reference
    return [DboTclHelper_sGetConstCharPtr $reference]
}

proc ::importPropertiesByReference::getProp {partInst propertyName} {
    set property [DboTclHelper_sMakeCString $propertyName]
    set value [DboTclHelper_sMakeCString]
    $partInst GetEffectivePropStringValue $property $value
    return [DboTclHelper_sGetConstCharPtr $value]
}

proc ::importPropertiesByReference::setProp {partInst propertyName value} {
    set property [DboTclHelper_sMakeCString $propertyName]
    set newValue [DboTclHelper_sMakeCString $value]
    $partInst SetEffectivePropStringValue $property $newValue
}

proc ::importPropertiesByReference::indexPart {partInst} {
    variable partsByReference
    set reference [getReference $partInst]
    if {$reference ne ""} {
        if {[info exists partsByReference($reference)]} {
            error "Duplicate reference '$reference' in the active design; cannot use reference matching"
        }
        set partsByReference($reference) $partInst
    }
}

proc ::importPropertiesByReference::forEachPart {callback} {
    set status [DboState]
    set session $::DboSession_s_pDboSession
    DboSession -this $session
    set design [$session GetActiveDesign]
    if {$design == "NULL"} {
        error "No active Capture design. Open the target DSN first."
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

proc ::importPropertiesByReference::run {} {
    variable mode
    variable fieldsToImport
    variable partsByReference
    variable rowsByReference
    variable changed
    variable skipped

    readExp
    array unset partsByReference
    set changed 0
    set skipped 0
    forEachPart ::importPropertiesByReference::indexPart

    foreach key [array names rowsByReference] {
        lassign [split $key ,] reference property
        if {![info exists partsByReference($reference)]} {
            puts "SKIP: $reference is in the EXP but not in the active design"
            incr skipped
            continue
        }
        set newValue $rowsByReference($key)
        if {$newValue eq "<null>"} {
            continue
        }
        set partInst $partsByReference($reference)
        set oldValue [getProp $partInst $property]
        if {$oldValue eq $newValue} {
            continue
        }
        puts "$reference : $property '$oldValue' -> '$newValue'"
        if {$mode eq "apply"} {
            setProp $partInst $property $newValue
            $partInst MarkModified
        }
        incr changed
    }

    puts "Mode: $mode; proposed changes: $changed; skipped EXP references: $skipped"
    if {$mode eq "report"} {
        puts "No properties changed. Set ::importPropertiesByReference::mode to apply and run ::importPropertiesByReference::run again."
    } else {
        puts "Properties changed in memory. Use File > Save to write the DSN."
    }
    DboTclHelper_sReleaseAllCreatedPtrs
}

::importPropertiesByReference::run
