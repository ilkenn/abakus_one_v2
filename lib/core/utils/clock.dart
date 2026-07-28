/// The smallest replaceable seam for "what time is it" — domain and
/// application code must never call `DateTime.now()` directly (untestable,
/// and it hides a real dependency). Everything that needs the current time
/// takes a [Clock] instead.
abstract interface class Clock {
  DateTime now();
}

/// The real implementation — [DateTime.now()] behind the [Clock] seam.
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}
