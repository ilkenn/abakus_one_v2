import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../shared/widgets/hero/hero_abacus.dart';
import '../shared/widgets/hero/hero_abacus_controller.dart';

/// Isolated development/validation screen for the Hero Abacus signature
/// object. Exists ONLY to iterate on and review its rendering/physics on a
/// real device — entirely decoupled from the real app (see
/// `hero_abacus_lab_main.dart`, its own separate entrypoint: no bootstrap,
/// no auth, no router). Never linked from `LoginScreen` or any production
/// navigation.
class HeroAbacusLabScreen extends StatefulWidget {
  const HeroAbacusLabScreen({super.key});

  @override
  State<HeroAbacusLabScreen> createState() => _HeroAbacusLabScreenState();
}

class _HeroAbacusLabScreenState extends State<HeroAbacusLabScreen> {
  // Owned here (not by HeroAbacus) specifically so this screen's debug
  // readout can observe the exact same physics state HeroAbacus is
  // rendering — see HeroAbacus.controller's doc comment.
  final HeroAbacusController _controller = HeroAbacusController();

  double _fps = 0;
  final List<Duration> _recentFrameSpans = [];

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _controller.dispose();
    super.dispose();
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _recentFrameSpans.add(timing.totalSpan);
      if (_recentFrameSpans.length > 30) _recentFrameSpans.removeAt(0);
    }
    if (_recentFrameSpans.isEmpty || !mounted) return;
    final avgMicros = _recentFrameSpans.fold<int>(
          0,
          (sum, d) => sum + d.inMicroseconds,
        ) /
        _recentFrameSpans.length;
    if (avgMicros <= 0) return;
    setState(() => _fps = 1e6 / avgMicros);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width * 0.86;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F6F2),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: HeroAbacus(width: width, controller: _controller),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  final row = _controller.draggingRow;
                  final col = _controller.draggingCol;
                  final active =
                      row == null || col == null ? 'none' : '($row, $col)';
                  final release = _controller.lastReleaseSpeed;
                  final impact = _controller.lastImpactSpeed;
                  return Text(
                    'FPS: ${_fps.toStringAsFixed(0)}   '
                    'active: $active   '
                    'release: ${release == null ? '—' : release.toStringAsFixed(2)}   '
                    'impact: ${impact.toStringAsFixed(2)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF667085),
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
