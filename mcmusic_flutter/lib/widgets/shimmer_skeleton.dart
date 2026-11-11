import 'package:flutter/material.dart';

class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final v = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(-1.5 + (v * 3.0), 0),
              end: Alignment(-0.5 + (v * 3.0), 0),
              colors: const [
                Color(0xFF1A1A1E),
                Color(0xFF282830),
                Color(0xFF1A1A1E),
              ],
            ),
          ),
        );
      },
    );
  }
}

class HomeSkeletonLoader extends StatelessWidget {
  const HomeSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              ShimmerBox(width: 34, height: 34, borderRadius: BorderRadius.all(Radius.circular(17))),
              SizedBox(width: 10),
              ShimmerBox(width: 68, height: 32, borderRadius: BorderRadius.all(Radius.circular(16))),
              SizedBox(width: 8),
              ShimmerBox(width: 68, height: 32, borderRadius: BorderRadius.all(Radius.circular(16))),
              SizedBox(width: 8),
              ShimmerBox(width: 78, height: 32, borderRadius: BorderRadius.all(Radius.circular(16))),
            ],
          ),
          const SizedBox(height: 20),
          const ShimmerBox(width: 160, height: 26),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 3.1,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: 8,
            itemBuilder: (_, _) => const ShimmerBox(
              width: double.infinity,
              height: 56,
              borderRadius: BorderRadius.all(Radius.circular(6)),
            ),
          ),
          const SizedBox(height: 28),
          const ShimmerBox(width: 190, height: 22),
          const SizedBox(height: 12),
          SizedBox(
            height: 185,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  ShimmerBox(width: 140, height: 140, borderRadius: BorderRadius.all(Radius.circular(8))),
                  SizedBox(height: 8),
                  ShimmerBox(width: 110, height: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
