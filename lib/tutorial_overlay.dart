import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TutorialStep {
  final GlobalKey targetKey;
  final List<GlobalKey> extraKeys;
  final String title;
  final String description;
  final double padding;
  final VoidCallback? onStepEnter;
  final double borderRadius;
  final int locateDelayMs;
  final bool noSpotlight;

  TutorialStep({
    required this.targetKey,
    this.extraKeys = const [],
    required this.title,
    required this.description,
    this.padding = 12,
    this.onStepEnter,
    this.borderRadius = 12,
    this.locateDelayMs = 0,
    this.noSpotlight = false,
  });

  List<GlobalKey> get allKeys => [targetKey, ...extraKeys];
}

class TutorialOverlay extends StatefulWidget {
  final List<TutorialStep> steps;
  final VoidCallback onFinished;
  final VoidCallback onSkipped;

  const TutorialOverlay({
    super.key,
    required this.steps,
    required this.onFinished,
    required this.onSkipped,
  });

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  int _currentStep = 0;
  Rect? _targetRect;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateTarget());
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _locateTarget() {
    final step = widget.steps[_currentStep];
    final keys = step.allKeys;
    Rect? union;
    for (final key in keys) {
      if (key.currentContext == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _locateTarget());
        return;
      }
      final box = key.currentContext!.findRenderObject() as RenderBox;
      if (!box.hasSize) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _locateTarget());
        return;
      }
      final pos = box.localToGlobal(Offset.zero);
      final size = box.size;
      final rect = Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
      union = union == null ? rect : union.expandToInclude(rect);
    }
    if (union == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _locateTarget());
      return;
    }
    final r = union;
    setState(() {
      _targetRect = Rect.fromLTWH(
        r.left - step.padding,
        r.top - step.padding,
        r.width + step.padding * 2,
        r.height + step.padding * 2,
      );
    });
    _animController.forward();
  }

  void _goToStep(int step) {
    if (step < 0 || step >= widget.steps.length) return;

    final onEnter = widget.steps[step].onStepEnter;
    if (onEnter != null) onEnter();

    setState(() {
      _currentStep = step;
      _targetRect = null;
    });
    _animController.reset();
    final delay = widget.steps[step].locateDelayMs;
    if (delay > 0) {
      Future.delayed(Duration(milliseconds: delay), () {
        if (mounted) _locateTarget();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _locateTarget());
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    if (_targetRect == null) return const SizedBox.shrink();

    final step = widget.steps[_currentStep];
    final center = _targetRect!.center;
    final isTopHalf = center.dy < screen.height * 0.55;
    final borderRadius = widget.steps[_currentStep].borderRadius;

    return Stack(
      children: [
        if (step.noSpotlight)
          Container(
            color: Colors.black.withValues(alpha: 0.55),
            width: screen.width,
            height: screen.height,
          )
        else
          GestureDetector(
            onTap: () {},
            child: AnimatedBuilder(
              animation: _scaleAnim,
              builder: (context, _) {
                final scaleVal = _scaleAnim.value;
                final animatedRect = Rect.fromCenter(
                  center: _targetRect!.center,
                  width: _targetRect!.width * scaleVal,
                  height: _targetRect!.height * scaleVal,
                );
                return ClipPath(
                  clipper: _SpotlightClipper(
                    targetRect: animatedRect,
                    borderRadius: borderRadius,
                  ),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.55),
                    width: screen.width,
                    height: screen.height,
                  ),
                );
              },
            ),
          ),
        if (step.noSpotlight)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: _TooltipCard(
                  step: step,
                  currentStep: _currentStep,
                  totalSteps: widget.steps.length,
                  onNext: () => _goToStep(_currentStep + 1),
                  onSkip: widget.onSkipped,
                  onFinish: widget.onFinished,
                  centered: true,
                ),
              ),
            ),
          )
        else if (isTopHalf)
          Positioned(
            left: 16,
            right: 16,
            bottom: 40,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: _TooltipCard(
                step: step,
                currentStep: _currentStep,
                totalSteps: widget.steps.length,
                onNext: () => _goToStep(_currentStep + 1),
                onSkip: widget.onSkipped,
                onFinish: widget.onFinished,
              ),
            ),
          )
        else
          Positioned(
            left: 16,
            right: 16,
            top: 40,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: _TooltipCard(
                step: step,
                currentStep: _currentStep,
                totalSteps: widget.steps.length,
                onNext: () => _goToStep(_currentStep + 1),
                onSkip: widget.onSkipped,
                onFinish: widget.onFinished,
              ),
            ),
          ),
      ],
    );
  }
}

class _SpotlightClipper extends CustomClipper<Path> {
  final Rect targetRect;
  final double borderRadius;

  _SpotlightClipper({required this.targetRect, required this.borderRadius});

  @override
  Path getClip(Size size) {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(
        RRect.fromRectAndRadius(
          targetRect,
          Radius.circular(borderRadius),
        ),
      );
  }

  @override
  bool shouldReclip(_SpotlightClipper oldClipper) {
    return oldClipper.targetRect != targetRect ||
        oldClipper.borderRadius != borderRadius;
  }
}

class _TooltipCard extends StatelessWidget {
  final TutorialStep step;
  final int currentStep;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback onFinish;
  final bool centered;

  const _TooltipCard({
    required this.step,
    required this.currentStep,
    required this.totalSteps,
    required this.onNext,
    required this.onSkip,
    required this.onFinish,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = currentStep == totalSteps - 1;

    return Material(
      elevation: 16,
      borderRadius: BorderRadius.circular(20),
      shadowColor: Colors.black26,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            if (centered) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  "${currentStep + 1}",
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                step.title,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0D7377),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${currentStep + 1}",
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      step.title,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0D7377),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Text(
              step.description,
              textAlign: centered ? TextAlign.center : null,
              style: GoogleFonts.poppins(
                fontSize: centered ? 14 : 13,
                color: Colors.grey.shade700,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                ...List.generate(totalSteps, (i) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.only(right: 6),
                    width: currentStep == i ? 28 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: currentStep == i
                          ? const LinearGradient(
                              colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                            )
                          : null,
                      color: currentStep == i ? null : Colors.grey.shade300,
                    ),
                  );
                }),
                const Spacer(),
                TextButton(
                  onPressed: onSkip,
                  child: Text(
                    "Skip",
                    style: GoogleFonts.poppins(
                      color: Colors.grey.shade500,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: isLast ? onFinish : onNext,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        child: Text(
                          isLast ? "Mula" : "Seterusnya",
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
