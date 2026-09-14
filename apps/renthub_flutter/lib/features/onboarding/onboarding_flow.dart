import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/renthub_components.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer(const Duration(milliseconds: 900), widget.onFinished);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Semantics(
              label: 'RentHub loading',
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 42,
                    backgroundColor: AppColors.primaryLight,
                    child: Icon(
                      Icons.handshake_outlined,
                      size: 42,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  SizedBox(height: 20),
                  RentHubLogo(),
                  SizedBox(height: 10),
                  Text(
                    'Rent with confidence across Malaysia',
                    style: TextStyle(color: AppColors.secondaryText),
                  ),
                  SizedBox(height: 24),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final controller = PageController();
  int index = 0;

  static const pages = [
    _OnboardingContent(
      icon: Icons.search_outlined,
      title: 'Find what you need nearby',
      message:
          'Explore verified items and trusted local services with clear prices and availability.',
    ),
    _OnboardingContent(
      icon: Icons.verified_user_outlined,
      title: 'Rent with greater confidence',
      message:
          'Verification badges, trust scores, reviews and structured booking details help you decide.',
    ),
    _OnboardingContent(
      icon: Icons.sync_alt_outlined,
      title: 'Manage the complete journey',
      message:
          'Track requests, handover, returns and service completion from one approachable experience.',
    ),
  ];

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _next() {
    if (index == pages.length - 1) {
      widget.onFinished();
      return;
    }
    controller.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const RentHubLogo(compact: true),
          actions: [
            TextButton(
              key: const Key('skip-onboarding'),
              onPressed: widget.onFinished,
              child: const Text('Skip'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: controller,
                    itemCount: pages.length,
                    onPageChanged: (value) => setState(() => index = value),
                    itemBuilder: (_, pageIndex) => pages[pageIndex],
                  ),
                ),
                Semantics(
                  label: 'Onboarding page ${index + 1} of ${pages.length}',
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var pageIndex = 0;
                          pageIndex < pages.length;
                          pageIndex++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: pageIndex == index ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: pageIndex == index
                                ? AppColors.primary
                                : AppColors.border,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('onboarding-next'),
                    onPressed: _next,
                    child: Text(
                      index == pages.length - 1 ? 'Get Started' : 'Continue',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _OnboardingContent extends StatelessWidget {
  const _OnboardingContent({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: AppColors.blueSurface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.primaryLight),
                ),
                child: Icon(icon, size: 88, color: AppColors.primaryDark),
              ),
              const SizedBox(height: 32),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.secondaryText,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
}
