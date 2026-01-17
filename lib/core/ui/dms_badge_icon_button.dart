import 'package:flutter/material.dart';

class DmsBadgeIconButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final String tooltip;
  final VoidCallback? onPressed;

  const DmsBadgeIconButton({
    super.key,
    required this.icon,
    required this.count,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: count > 0 ? '$tooltip ($count)' : tooltip,
      onPressed: onPressed,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon),
          if (count > 0)
            Positioned(
              right: -6,
              top: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
