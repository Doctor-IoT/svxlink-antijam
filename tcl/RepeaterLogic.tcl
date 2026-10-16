# RepeaterLogic.tcl - Squelch hook for the anti-jam system
# Version: 2026-10
# Repo   : https://github.com/Doctor-IoT/svxlink-antijam
#
# Installs antijam.tcl into SvxLink's event loop by wrapping
# the squelch_open proc (handles both open and close in SvxLink 26.05.1;
# there is no separate squelch_close proc in this version).
#
# Install to: /usr/share/svxlink/events.d/local/RepeaterLogic.tcl

source [file join [file dirname [info script]] antijam.tcl]

namespace eval ${::logic_name} {

  # 30-minute beacon (at :00 and :30)
  if {[info commands every_minute_orig] eq ""} {
    rename every_minute every_minute_orig
  }
  proc every_minute {} {
    set minute [scan [clock format [clock seconds] -format "%M"] %d]
    if {$minute == 0 || $minute == 30} { playMsg "beacon_30min" }
    every_minute_orig
  }

  # Hook into squelch_open (handles both open and close states).
  # NOTE: SvxLink 26.05.1 has no separate squelch_close proc.
  if {[info commands squelch_open_orig] eq ""} {
    if {[info commands squelch_open] ne ""} {
      rename squelch_open squelch_open_orig
    } else {
      proc squelch_open_orig {rx_id is_open} {}
    }
  }

  proc squelch_open {rx_id is_open} {
    if {$is_open} {
      if {[::antijam::on_squelch_open]} return
    } else {
      if {[::antijam::on_squelch_close]} return
    }
    squelch_open_orig $rx_id $is_open
  }

}
