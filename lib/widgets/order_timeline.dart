import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OrderTimeline extends StatelessWidget {
  final String currentStatus;
  final int? activeIndex;

  const OrderTimeline({
    super.key,
    required this.currentStatus,
    this.activeIndex,
  });

  int get _activeIndex {
    if (activeIndex != null) return activeIndex!;
    switch (currentStatus) {
      case 'pending':
      case 'menunggu':
        return 0;
      case 'accepted':
      case 'dijemput':
        return 1;
      case 'on the way':
      case 'dalam perjalanan':
        return 2;
      case 'delivered':
      case 'selesai':
        return 3;
      default:
        return 0;
    }
  }

  static const Color _completedColor = Color(0xFFFCD34D);
  static const Color _activeColor = Color(0xFF0D7377);
  static const Color _futureColor = Color(0xFFBDBDBD);

  static const List<String> _labels = [
    'Menunggu',
    'Dijemput',
    'Dalam\nPerjalanan',
    'Selesai',
  ];

  @override
  Widget build(BuildContext context) {
    final active = _activeIndex.clamp(0, 4);

    return SizedBox(
      height: 80,
      child: Row(
        children: List.generate(_labels.length * 2 - 1, (index) {
          if (index.isOdd) {
            final stepIndex = index ~/ 2;
            final isCompleted = stepIndex < active;
            return Expanded(
              child: Container(
                height: 3,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: isCompleted ? _completedColor : _futureColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }
          final stepIndex = index ~/ 2;
          final isCompleted = stepIndex < active;
          final isActive = stepIndex == active;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: isActive ? 28 : 20,
                height: isActive ? 28 : 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted
                      ? _completedColor
                      : isActive
                          ? _activeColor
                          : _futureColor,
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: _activeColor.withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: isCompleted
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : isActive
                        ? Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          )
                        : null,
              ),
              const SizedBox(height: 6),
              Text(
                _labels[stepIndex],
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive
                      ? _activeColor
                      : isCompleted
                          ? _completedColor
                          : _futureColor,
                  height: 1.3,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
