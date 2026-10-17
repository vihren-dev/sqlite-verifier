import Belay.Sqlite.Date.Strftime

set_option doc.verso true

/-! The {lit}`localtime` and {lit}`utc` modifiers of the pinned SQLite 3.51.0
{lit}`date.c` (ADR 0012, amendment 5, slice 6g, owner decision 6): {lit}`toLocaltime`
and the inverse loop of {lit}`utc`. SQLite calls the C library's {lit}`localtime_r`.
The model implements the time zone UTC, in which the recorder runs SQLite
({lit}`TZ=UTC0`); the execution profile refuses other zones. In UTC,
{lit}`localtime_r` has no offset and no daylight saving time, and it cannot fail for the
times that {lit}`toLocaltime` gives it, so the error {lit}`local time unavailable` cannot
occur. -/

namespace Belay.Sqlite

/-- The broken-down time ({lit}`struct tm`) that {lit}`localtime_r` gives: the
calendar fields of a Unix time. -/
structure BrokenDownTime where
  /-- The year ({lit}`tm_year + 1900`). -/
  year : Int
  /-- The month 1 to 12 ({lit}`tm_mon + 1`). -/
  month : Int
  /-- The day of the month ({lit}`tm_mday`). -/
  day : Int
  /-- The hour ({lit}`tm_hour`). -/
  hour : Int
  /-- The minute ({lit}`tm_min`). -/
  minute : Int
  /-- The whole seconds ({lit}`tm_sec`). -/
  second : Int

/-- {lit}`localtime_r` in the time zone UTC, for a Unix time from 0 to below
{lit}`2^31` seconds, the range that {lit}`toLocaltime` gives it: the
Gregorian calendar date by {name}`civilDateOfValidClock` and the time of day, with no
offset and no leap seconds. Only the time zone UTC is modeled; another zone needs its
own offsets here. -/
def utcLocaltime (unixSeconds : Int) : BrokenDownTime :=
  let date := civilDateOfValidClock (unixSeconds * 1000 + unixEpochJulianMilliseconds)
  let secondOfDay := unixSeconds.emod 86400
  { year := date.year, month := date.month, day := date.day, hour := secondOfDay / 3600,
    minute := secondOfDay % 3600 / 60, second := secondOfDay % 60 }

/-- The Julian day milliseconds of 1970-01-01 00:00:00: below it, {lit}`toLocaltime` maps
the year into the range that {lit}`localtime_r` handles. -/
def localtimeRangeStart : Int := 2108667600 * 100000

/-- The Julian day milliseconds of 2038-01-18 12:00:00: above it, {lit}`toLocaltime`
maps the year into the range that {lit}`localtime_r` handles. -/
def localtimeRangeEnd : Int := 2130141456 * 100000

/-- The base year of the mapping in {lit}`toLocaltime`. A year outside 1970 to 2037 moves
to {lit}`2000 + Y%4`, which has the same leap-year rule for every year divisible by 4. -/
def localtimeBaseYear : Int := 2000

/-- {lit}`toLocaltime` in the time zone UTC: move the time to local time and set the
date and the time from {name}`utcLocaltime`. A Julian day outside
{name}`localtimeRangeStart` to {name}`localtimeRangeEnd` is first moved by whole years to
a year near {name}`localtimeBaseYear`, and the year difference is subtracted again after
the call. The seconds keep the milliseconds of the Julian day. The result has a valid
date and time, no valid Julian day and no error. The time zone is always UTC in the
model, because the execution profile accepts only UTC. -/
def DateTime.toLocaltime (p : DateTime) : DateTime :=
  let p := p.computeJulianDay
  let (unixSeconds, yearShift) :=
    if p.julianMilliseconds < localtimeRangeStart || p.julianMilliseconds > localtimeRangeEnd then
      let x := p.computeCivilDate.computeTimeOfDay
      let yearShift := localtimeBaseYear + x.year.tmod 4 - x.year
      let x := { x with year := x.year + yearShift, validJulianMilliseconds := false }.computeJulianDay
      (x.julianMilliseconds.tdiv 1000 - unixEpochJulianMilliseconds / 1000, yearShift)
    else (p.julianMilliseconds.tdiv 1000 - unixEpochJulianMilliseconds / 1000, 0)
  let localTime := utcLocaltime unixSeconds
  { p with year := localTime.year - yearShift, month := localTime.month, day := localTime.day,
           hour := localTime.hour, minute := localTime.minute,
           seconds := Float.ofInt localTime.second + Float.ofInt (p.julianMilliseconds.tmod 1000) * 0.001,
           validDate := true, validTime := true, validJulianMilliseconds := false,
           rawSeconds := false, timezoneMinutes := 0, isError := false }

/-- The {lit}`localtime` modifier: {name}`DateTime.toLocaltime` unless the time is
already local, then the time is marked as local and not UTC. -/
def DateTime.applyLocaltime (p : DateTime) : DateTime :=
  { (if p.isLocal then p else p.toLocaltime) with isUtc := false, isLocal := true }

/-- The number of extra guesses of the {lit}`utc` loop after the first one: SQLite stops
after four guesses at most. -/
def utcGuessRetries : Nat := 3

/-- The guess loop of the {lit}`utc` modifier: convert the guess to local time and back
to a Julian day; when it differs from the original local time, correct the guess by the
error and try again, at most {lit}`retries` more times. The result is the last guess. -/
def utcGuess (original : Int) : Nat → Int → Int
  | retries, guess =>
    let localTime := ({ julianMilliseconds := guess, validJulianMilliseconds := true } : DateTime).toLocaltime
    let error := localTime.computeJulianDay.julianMilliseconds - original
    match retries with
    | 0 => guess
    | retries + 1 => if error == 0 then guess else utcGuess original retries (wrapInt64 (guess - error))

/-- The {lit}`utc` modifier: when the time is not known to be UTC, find the UTC time
whose local time is the current value by {name}`utcGuess`. The result is a cleared
structure with only that Julian day, marked as UTC; this also clears {lit}`subsec`. -/
def DateTime.applyUtc (p : DateTime) : DateTime :=
  if p.isUtc then p else
  let original := p.computeJulianDay.julianMilliseconds
  { julianMilliseconds := utcGuess original utcGuessRetries original, validJulianMilliseconds := true,
    isUtc := true }

end Belay.Sqlite
