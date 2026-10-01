# Trace the real upstream harness; Tcl itself expands loops, ifcapable and substitutions.
set capture [open $env(CONFORMANCE_EVENTS) w]
set capture_metadata 0
proc capture_event {args} {
  set fields {}
  foreach item $args { lappend fields [binary encode hex [encoding convertto utf-8 $item]] }
  puts $::capture [join $fields \t]
  flush $::capture
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
  set operation [lindex $command 1]
  if {$operation in {eval onecolumn exists}} {
    if {[lindex $args end] eq "enter"} {
      set callback [expr {[llength $command] > 3}]
      set helper $operation
      if {$operation eq "eval" && $callback && [capture_pure_row_body $command]} {
        set helper eval-script
        set callback 0
      }
      capture_event sql $name [lindex $command 2] $callback $helper
    } else {
      if {[lindex $args 0] == 0 && $operation eq "eval"} {
        capture_event result $name 0 {*}[lindex $args 1]
      } else { capture_event result $name [lindex $args 0] [lindex $args 1] }
      set ::capture_metadata 1
      try {
        capture_event databases $name {*}[$name eval {PRAGMA database_list}]
      } on error {message options} {
        capture_event exclude "attachment context unobservable"
      } finally { set ::capture_metadata 0 }
    }
  } elseif {$operation eq "close"} {
    if {[lindex $args end] eq "leave" && [lindex $args 0] == 0} { capture_event close $name }
  } elseif {$operation in {function collation authorizer progress trace update_hook rollback_hook commit_hook}} {
    capture_event exclude "application callback: $operation"
  }
}
proc capture_factory {command code result operation} {
  set name [lindex $command 1]
  if {$code == 0 && ![string match -* $name] && [llength [info commands ::$name]]} {
    set filename [lindex $command 2]
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
  if {[info exists ::capture_file(db)]} { capture_event reset $::capture_file(db) } else { capture_event reset }
}
proc capture_failure {command operation} { capture_event failed [lindex $command 1] }
proc capture_external {command operation} {
  if {[lindex $command 0] eq "sqlite3_db_config"} {
    capture_event config {*}[lrange $command 1 end]
  } elseif {[info exists ::capture_active] && $::capture_active} {
    capture_event exclude "external/configuration operation: [lindex $command 0]"
  }
}
proc capture_source {command code result operation} {
  if {[file tail [lindex $command end]] eq "tester.tcl" && ![info exists ::capture_installed]} {
    set ::capture_installed 1
    trace add execution do_test {enter leave} capture_test
    trace add execution reset_db leave capture_reset
    trace add execution fail_test enter capture_failure
    foreach command {open sqlite3_db_config sqlite3_limit sqlite3_test_control} {
      if {[llength [info commands $command]]} { trace add execution $command enter capture_external }
    }
    capture_reset {}
  }
}
trace add execution sqlite3 leave capture_factory
trace add execution source leave capture_source
set argv0 $env(CONFORMANCE_TEST)
set argv {}
source $argv0
