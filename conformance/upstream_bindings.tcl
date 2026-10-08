# Skip metadata commands when a source callback could run or the original handle was renamed.
proc capture_callback_context {database} {
  return [expr {![llength [info commands ::$database]] || [llength [trace info execution ::$database]] != 1}]
}
# Observe scalar objects before the pinned binder converts them. SQL slots are verified natively.
proc capture_bindings {database sql} {
  # The event transport must preserve the bytes that Tcl passes as SQL.
  if {[encoding convertto identity $sql] ne [encoding convertto utf-8 $sql]} {
    capture_event exclude "Tcl SQL encoding is not reproduced"
  }
  set callbacks [capture_callback_context $database]
  foreach slot [lsort -unique [regexp -all -inline {[$:@][[:alnum:]_:]+} $sql]] {
    set variable [string range $slot 1 end]
    set reason ""
    set kind ""
    set data ""
    set type ""
    set has_string ""
    if {![regexp {^(::)?[[:alnum:]_]+$} $variable]} {
      set reason "unsupported Tcl parameter variable form"
    } elseif {$callbacks} {
      set reason "Tcl parameter execution callback context"
    } elseif {[llength [uplevel 2 [list trace info variable $variable]]]} {
      set reason "traced Tcl parameter variable"
    } elseif {[uplevel 2 [list array exists $variable]]} {
      set reason "unsupported Tcl parameter variable form"
    } elseif {![uplevel 2 [list info exists $variable]]} {
      set reason "missing Tcl parameter variable"
    } elseif {[llength [info procs ::tcl::unsupported::representation]] ||
              [interp alias {} ::tcl::unsupported::representation] ne ""} {
      set reason "Tcl parameter object type unobservable"
    } else {
      set value [uplevel 2 [list set $variable]]
      if {[catch {tcl::unsupported::representation $value} representation] ||
          ![regexp {^value is a (?:pure )?([^ ]+) } $representation -> type]} {
        set reason "Tcl parameter object type unobservable"
      } else {
        set has_string [expr {![string match {*no string representation} $representation]}]
        if {[catch {
        if {$type in {boolean booleanString}} {
          set reason "unsupported Tcl parameter boolean object"
        } elseif {!$has_string && $type ni {int wideInt double bytearray}} {
          set reason "unsupported Tcl parameter object conversion"
        } elseif {[string index $slot 0] eq "@" || ($type eq "bytearray" && !$has_string)} {
          set kind blob
          if {$type eq "bytearray"} {
            set data [binary encode hex $value]
          } else {
            if {!$has_string && $type eq "double"} { binary scan [binary format Q $value] Q copy
            } elseif {!$has_string} { binary scan [binary format W $value] W copy
            } else { set copy $value }
            # Convert a new string object; converting the shared value would change later bindings.
            set copy [string range "x$copy" 1 end]
            set data [binary encode hex $copy]
          }
        } elseif {$type eq "double"} {
          set kind real
          set data [binary encode hex [binary format Q $value]]
        } elseif {$type in {int wideInt}} {
          set kind integer
          set data [binary encode hex [binary format W $value]]
        } else {
          set kind text
          # identity exposes Tcl's original UTF-8 bytes, including its encoded NUL.
          set data [binary encode hex [encoding convertto identity $value]]
        }
        }]} { set reason "Tcl parameter value encoding unobservable" }
      }
    }
    capture_event binding $database $slot $type $has_string $kind $data $reason
  }
  capture_event bindings-complete $database
}
