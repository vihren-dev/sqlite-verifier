# Trace the real upstream harness; Tcl itself expands loops, ifcapable and substitutions.
set capture [open $env(CONFORMANCE_EVENTS) w]
proc capture_event {args} {
  set fields {}
  foreach item $args { lappend fields [binary encode hex [encoding convertto utf-8 $item]] }
  puts $::capture [join $fields \t]
  flush $::capture
}
proc capture_connection {name command args} {
  set operation [lindex $command 1]
  if {$operation in {eval onecolumn exists}} {
    if {[lindex $args end] eq "enter"} {
      capture_event sql $name [lindex $command 2] [expr {[llength $command] > 3}] $operation
    } else {
      if {[lindex $args 0] == 0 && $operation eq "eval"} {
        capture_event result $name 0 {*}[lindex $args 1]
      } else { capture_event result $name [lindex $args 0] [lindex $args 1] }
    }
  } elseif {$operation in {close function collation authorizer progress trace update_hook rollback_hook commit_hook}} {
    capture_event exclude "application callback: $operation"
  }
}
proc capture_factory {command code result operation} {
  set name [lindex $command 1]
  if {$code == 0 && ![string match -* $name] && [llength [info commands ::$name]]} {
    capture_event open $name [lindex $command 2]
    trace add execution ::$name {enter leave} [list capture_connection $name]
  }
}
proc capture_test {command args} {
  if {[lindex $args end] eq "enter"} {
    set ::capture_active 1
    capture_event begin [lindex $command 1] [lindex $command 3]
  } else { capture_event end [lindex $command 1]; set ::capture_active 0 }
}
proc capture_reset {command args} { capture_event reset }
proc capture_failure {command operation} { capture_event failed [lindex $command 1] }
proc capture_external {command operation} {
  if {[info exists ::capture_active] && $::capture_active} {
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
    capture_event reset
  }
}
trace add execution sqlite3 leave capture_factory
trace add execution source leave capture_source
set argv0 $env(CONFORMANCE_TEST)
set argv {}
source $argv0
