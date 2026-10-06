# Trace the real upstream harness; Tcl itself expands loops, ifcapable and substitutions.
set capture [open $env(CONFORMANCE_EVENTS) w]
set capture_metadata 0
set capture_sql_depth 0
if {[info exists env(CONFORMANCE_CLOCK_SECONDS)]} {
  if {![info exists sqlite_current_time]} { error "Testfixture has no native clock control" }
  set sqlite_current_time $env(CONFORMANCE_CLOCK_SECONDS)
}
proc capture_event {args} {
  set fields {}
  foreach item $args { lappend fields [binary encode hex [encoding convertto utf-8 $item]] }
  puts $::capture [join $fields \t]
  flush $::capture
}
proc capture_method {operation} {
  # Match the pinned tclsqlite.c DB_strs: exact names win over unique prefixes.
  set methods {authorizer backup bind_fallback busy cache changes close collate
    collation_needed commit_hook complete config copy deserialize enable_load_extension
    errorcode erroroffset eval exists function incrblob interrupt last_insert_rowid
    nullvalue onecolumn preupdate profile progress rekey restore rollback_hook serialize
    status timeout total_changes trace trace_v2 transaction unlock_notify update_hook version wal_hook}
  if {$operation in $methods} { return $operation }
  set matches {}
  foreach method $methods {
    if {[string first $operation $method] == 0} { lappend matches $method }
  }
  if {[llength $matches] == 1} { return [lindex $matches 0] }
  return ""
}
# Read display conditions without invoking Tcl variable callbacks.
proc capture_precision {} {
  if {![llength [trace info variable ::tcl_precision]] && [info exists ::tcl_precision]} { return $::tcl_precision }
  return ""
}
proc capture_pure_row_body {command} {
  # ponytail: only empty/basic braced expr bodies; widen verified forms when yield warrants it.
  if {[llength $command] ni {4 5}} { return 0 }
  set body [string trim [lindex $command end]]
  if {$body ne ""} {
    if {![regexp {^expr\s+\{([^{}\\\[\]]*)\}\s*;?\s*$} $body -> expression]} { return 0 }
    if {[regexp {[[:alpha:]_][[:alnum:]_:]*\s*\(} $expression]} { return 0 }
    if {[string first :: $expression] >= 0} { return 0 }
    if {[llength [info procs ::expr]] || [interp alias {} expr] ne ""} { return 0 }
  }
  # Variable read traces can turn an otherwise pure expression into a state change.
  foreach variable [uplevel 2 {info vars}] {
    if {[llength [uplevel 2 [list trace info variable $variable]]]} { return 0 }
  }
  foreach variable [info globals] {
    if {[llength [uplevel #0 [list trace info variable ::$variable]]]} { return 0 }
  }
  return 1
}
proc capture_connection {name command args} {
  if {$::capture_metadata} { return }
  set operation [capture_method [lindex $command 1]]
  if {$operation in {eval onecolumn exists}} {
    if {[lindex $args end] eq "enter"} {
      if {[incr ::capture_sql_depth] > 1} {
        capture_event exclude "nested SQL execution"
        return
      }
      if {[info exists ::env(CONFORMANCE_CLOCK_SECONDS)] &&
          $::sqlite_current_time != $::env(CONFORMANCE_CLOCK_SECONDS)} {
        capture_event exclude "test changed the controlled clock"
      }
      if {[info exists ::env(CONFORMANCE_TCL_PRECISION)]} {
        set precision [capture_precision]
        if {$precision eq ""} { capture_event exclude "Tcl display precision unobservable"
        }
      }
      set callback [expr {[llength $command] > 3}]
      set helper $operation
      if {$operation eq "eval" && $callback && [capture_pure_row_body $command]} {
        set helper eval-script
        set callback 0
      }
      capture_event sql $name [lindex $command 2] $callback $helper
    } else {
      # Inner SQL/results must not be paired with the enclosing call's result.
      if {[incr ::capture_sql_depth -1] > 0} { return }
      if {[lindex $args 0] == 0 && $operation eq "eval"} {
        capture_event result $name 0 {*}[lindex $args 1]
      } else { capture_event result $name [lindex $args 0] [lindex $args 1] }
      if {[lindex $args 0] != 0} { return } ;# Metadata SQL would clear the failed call's errorcode.
      capture_event result-precision $name [capture_precision]
      set ::capture_metadata 1
      try {
        if {[catch {$name nullvalue} marker]} {
          capture_event exclude "Tcl NULL display marker unobservable"
        } else { capture_event result-nullvalue $name $marker }
        capture_event databases $name {*}[$name eval {PRAGMA database_list}]
      } on error {message options} {
        capture_event exclude "attachment context unobservable"
      } finally { set ::capture_metadata 0 }
    }
  } elseif {$operation eq "close"} {
    if {[lindex $args end] eq "leave" && [lindex $args 0] == 0} { capture_event close $name }
  } elseif {$operation eq "function"} {
    if {[lindex $args end] eq "leave" && [lindex $args 0] == 0} { capture_event function $name [lindex $command 2] }
  } elseif {$operation in {collate collation_needed authorizer bind_fallback busy
      preupdate profile progress trace trace_v2 unlock_notify update_hook rollback_hook commit_hook wal_hook}} {
    capture_event exclude "application callback: $operation"
  } elseif {$operation eq "incrblob"} {
    capture_event exclude "incremental BLOB operation: incrblob"
  }
}
proc capture_factory {command code result operation} {
  set name [lindex $command 1]
  if {$code == 0 && ![string match -* $name] && [llength [info commands ::$name]]} {
    set filename [lindex $command 2]
    if {[info exists ::env(CONFORMANCE_FOREIGN_KEYS)]} {
      foreach {setting variable} {foreign_keys CONFORMANCE_FOREIGN_KEYS recursive_triggers CONFORMANCE_RECURSIVE_TRIGGERS} {
        $name eval "PRAGMA $setting=$::env($variable)"
        if {[$name onecolumn "PRAGMA $setting"] != $::env($variable)} {
          error "Testfixture profile setting readback differs: $setting"
        }
      }
      if {[info exists ::env(CONFORMANCE_CLOCK_SECONDS)]} {
        if {$::sqlite_current_time != $::env(CONFORMANCE_CLOCK_SECONDS)} {
          capture_event exclude "test changed the controlled clock"
        } elseif {[$name onecolumn {SELECT unixepoch()}] != $::env(CONFORMANCE_CLOCK_SECONDS)} {
          error "Testfixture controlled clock readback differs"
        }
      }
    }
    set ::capture_file($name) [expr {$filename in {"" ":memory:"} ? ":memory:" : [file normalize $filename]}]
    if {[llength $command] > 3} { capture_event exclude "connection open options" }
    capture_event open $name $::capture_file($name)
    trace add execution ::$name {enter leave} [list capture_connection $name]
    trace add command ::$name {rename delete} [list capture_deleted $name]
  }
}
proc capture_deleted {name old new operation} {
  # close deletes the Tcl command, so its execution-leave trace may never run.
  if {$operation eq "rename"} {
    capture_event exclude "connection command renamed"
  } else { capture_event close $name }
}
proc capture_test {command args} {
  if {[lindex $args end] eq "enter"} {
    set ::capture_active 1
    set line 0
    for {set i 1} {$i < [info frame]} {incr i} {
      set frame [info frame $i]
      if {[dict exists $frame file] && [dict get $frame file] eq $::env(CONFORMANCE_TEST)} {
        set line [dict get $frame line]
        break
      }
    }
    capture_event begin [lindex $command 1] [lindex $command 3] $line
  } else { capture_event end [lindex $command 1]; set ::capture_active 0 }
}
proc capture_reset {command args} {
  # Failed resets can have partial effects; setup SQL also leaves state to retain.
  if {[llength $args] && [lindex $args 0] != 0} {
    capture_event exclude "reset_db failed"
    return
  }
  if {[info exists ::capture_file(db)]} { capture_event reset $::capture_file(db) } else { capture_event reset }
  if {[info exists ::SETUP_SQL] && [string trim $::SETUP_SQL] ne ""} {
    capture_event exclude "reset_db initialization SQL is not retained"
  }
}
proc capture_failure {command operation} { capture_event failed [lindex $command 1] }
# Flush source completion before finish_test exits, including assertion failures.
proc capture_complete {command operation} { capture_event complete }
source [file join [file dirname [info script]] upstream_external.tcl]
proc capture_source {command code result operation} {
  if {[file tail [lindex $command end]] eq "tester.tcl" && ![info exists ::capture_installed]} {
    set ::capture_installed 1
    if {[info exists ::env(CONFORMANCE_TCL_PRECISION)]} {
      set original [capture_precision]
      if {$original ne ""} { set ::tcl_precision $::env(CONFORMANCE_TCL_PRECISION) }
      capture_event precision-policy $original [capture_precision] $::env(CONFORMANCE_TCL_PRECISION)
    }
    trace add execution do_test {enter leave} capture_test
    trace add execution reset_db leave capture_reset
    trace add execution fail_test enter capture_failure
    trace add execution finish_test enter capture_complete
    foreach command [concat {open sqlite3_db_config sqlite3_limit sqlite3_test_control} \
                            [info commands sqlite3_blob_*]] {
      if {[llength [info commands $command]]} { trace add execution $command enter capture_external }
    }
    capture_install_filesystem_traces
    capture_reset {}
  }
}
trace add execution sqlite3 leave capture_factory
trace add execution source leave capture_source
set argv0 $env(CONFORMANCE_TEST)
set argv {}
source $argv0
