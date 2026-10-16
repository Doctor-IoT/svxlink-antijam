# antijam.tcl - Anti-jamming protection for SvxLink repeater
# Version 1.5 - timestamp-based timing (no 'after' callbacks)
#
# Author  : IZ0ABD Francesco - https://iz0abd.wordpress.com
# Hardware: UDOO NEO (Ubuntu 18.04, ARM) - SvxLink 26.05.1
# Repo    : https://github.com/Doctor-IoT/svxlink-antijam
#
# Detects >= JAM_COUNT squelch opens within JAM_WINDOW_MS milliseconds
# and locks out the repeater TX for LOCKOUT_MS milliseconds.
#
# IMPORTANT: Do NOT use 'after' for timing in SvxLink scripts.
# SvxLink's Asynclib event loop does not call Tcl_DoOneEvent() between
# hardware squelch events, so 'after' callbacks are silently queued but
# never executed during radio-quiet periods. v1.5 uses clock milliseconds
# checked inline on every squelch event instead.

namespace eval ::antijam {
    variable JAM_COUNT       3        ;# squelch opens that trigger lockout
    variable JAM_WINDOW_MS   15000    ;# detection sliding window (ms)
    variable LOCKOUT_MS      30000    ;# lockout duration (ms)
    variable WARN_ON_LOCKOUT 1        ;# 1 = play warning tone during lockout
    variable WARN_REPEAT_MS  5000     ;# interval between warning tones (ms)

    variable open_times     {}
    variable locked         0
    variable lockout_end_ms 0
    variable last_warn_ms   0
}

proc ::antijam::on_squelch_open {} {
    set now [clock milliseconds]

    # If locked, check whether the lockout has expired
    if {$::antijam::locked} {
        if {$now >= $::antijam::lockout_end_ms} {
            ::antijam::deactivate_lockout
        } else {
            # Still locked: optionally play a warning tone
            if {$::antijam::WARN_ON_LOCKOUT} {
                if {($now - $::antijam::last_warn_ms) >= $::antijam::WARN_REPEAT_MS} {
                    catch { playTone 440 300 150 }
                    set ::antijam::last_warn_ms $now
                }
            }
            return 1  ;# block TX
        }
    }

    # Record this squelch open and purge events outside the window
    lappend ::antijam::open_times $now
    set cutoff [expr {$now - $::antijam::JAM_WINDOW_MS}]
    set filtered {}
    foreach t $::antijam::open_times {
        if {$t >= $cutoff} { lappend filtered $t }
    }
    set ::antijam::open_times $filtered
    set cnt [llength $::antijam::open_times]
    printInfo "ANTIJAM: squelch open #${cnt} in window"

    if {$cnt >= $::antijam::JAM_COUNT} {
        ::antijam::activate_lockout
        return 1  ;# block TX
    }
    return 0  ;# allow TX
}

proc ::antijam::on_squelch_close {} {
    set now [clock milliseconds]
    if {$::antijam::locked} {
        if {$now >= $::antijam::lockout_end_ms} {
            ::antijam::deactivate_lockout
            return 0
        }
        return 1  ;# block TX
    }
    return 0  ;# allow TX
}

proc ::antijam::activate_lockout {} {
    set now [clock milliseconds]
    set ::antijam::locked         1
    set ::antijam::open_times     {}
    set ::antijam::lockout_end_ms [expr {$now + $::antijam::LOCKOUT_MS}]
    set ::antijam::last_warn_ms   $now
    catch {
        playTone 880 500 250
        playSilence 100
        playTone 440 400 200
    }
    set secs [expr {$::antijam::LOCKOUT_MS / 1000}]
    printInfo "ANTIJAM: lockout attivato per ${secs}s"
}

proc ::antijam::deactivate_lockout {} {
    set ::antijam::locked         0
    set ::antijam::lockout_end_ms 0
    set ::antijam::open_times     {}
    printInfo "ANTIJAM: lockout terminato, ripetitore operativo"
}
