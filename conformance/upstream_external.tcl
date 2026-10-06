# Refuse unreconstructable external state changes; reset_db clears ordinary exclusions.
proc capture_external {command operation} {
  if {[lindex $command 0] eq "sqlite3_db_config"} {
    capture_event config {*}[lrange $command 1 end]
  } elseif {[string match sqlite3_blob_* [lindex $command 0]]} {
    capture_event exclude "incremental BLOB operation: [lindex $command 0]"
  } elseif {[lindex $command 0] eq "sqlite3_limit"} {
    capture_event exclude "external/configuration operation: sqlite3_limit"
  } elseif {[lindex $command 0] eq "sqlite3_test_control"} {
    set scope exclude
    if {[lindex $command 1] ni {SQLITE_TESTCTRL_INTERNAL_FUNCTIONS SQLITE_TESTCTRL_FK_NO_ACTION
        SQLITE_TESTCTRL_SORTER_MMAP SQLITE_TESTCTRL_IMPOSTER}} { set scope persistent-exclude }
    capture_event $scope "external/configuration operation: sqlite3_test_control [lindex $command 1]"
  } elseif {[info exists ::capture_active] && $::capture_active} {
    capture_event exclude "external/configuration operation: [lindex $command 0]"
  }
}
# Main DB state includes sidecars and directory-level removal. Unrelated files are harmless.
proc capture_database_path {path {ancestors 0}} {
  if {![info exists ::capture_file(db)] || $::capture_file(db) eq ":memory:"} { return 0 }
  if {[catch {file normalize $path} normalized]} { return 0 }
  set database $::capture_file(db)
  if {$normalized in [list $database $database-journal $database-wal $database-shm]} { return 1 }
  return [expr {$ancestors && [string first "$normalized/" "$database/"] == 0}]
}
proc capture_file_operation {method command operation} {
  # Native ensemble implementations cover aliases and unique file-subcommand prefixes.
  set paths [lrange $command 1 end]
  if {$method in {delete copy rename}} {
    while {[llength $paths] && [lindex $paths 0] in {-force --}} {
      set option [lindex $paths 0]
      set paths [lrange $paths 1 end]
      if {$option eq "--"} { break }
    }
    if {$method in {copy rename}} {
      set target [lindex $paths end]
      set sources [lrange $paths 0 end-1]
      set paths {}
      foreach source $sources {
        if {$method eq "rename"} { lappend paths $source }
        if {[file isdirectory $target]} {
          lappend paths [file join $target [file tail $source]]
        } else { lappend paths $target }
      }
    }
  } elseif {$method in {atime mtime}} {
    if {[llength $paths] != 2} { return }
    set paths [lrange $paths 0 0]
  } elseif {$method eq "attributes"} {
    if {[llength $paths] < 3} { return }
    set paths [lrange $paths 0 0]
  } elseif {$method eq "link"} {
    if {[llength $paths] && [string match -* [lindex $paths 0]]} { set paths [lrange $paths 1 end] }
    if {[llength $paths] != 2} { return }
    # Linking from the primary creates a writable alias to its same stored state.
  }
  foreach path $paths {
    if {[capture_database_path $path [expr {$method in {delete rename}}]]} {
      # Enter covers partial multi-file failures; do not claim the operation succeeded.
      capture_event exclude "database file operation: file $method"
      return
    }
  }
}
proc capture_write_open {command operation} {
  # Writable channels can mutate the database outside its recorded SQL prefix.
  set mode [expr {[llength $command] > 2 ? [lindex $command 2] : "r"}]
  if {$mode in {r rb} || $mode eq "RDONLY"} { return }
  if {[capture_database_path [lindex $command 1]]} {
    capture_event exclude "database file operation: open for writing"
  }
}
proc capture_install_filesystem_traces {} {
  # Trace implementation commands so aliases and abbreviated ensemble names retain identity.
  set mapping [namespace ensemble configure ::file -map]
  foreach method {delete copy rename atime mtime attributes link} {
    trace add execution [dict get $mapping $method] enter [list capture_file_operation $method]
  }
  trace add execution ::open enter capture_write_open
}
