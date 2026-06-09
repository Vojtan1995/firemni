import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Desktop (Windows/macOS/Linux) — ESC = zpět / zavřít dialog.
class DesktopEscScope extends StatelessWidget {
  const DesktopEscScope({super.key, required this.child});

  final Widget child;

  static bool get enabled {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): EscapeIntent(),
      },
      child: Actions(
        actions: {
          EscapeIntent: CallbackAction<EscapeIntent>(
            onInvoke: (_) {
              final navigator = Navigator.maybeOf(context);
              if (navigator != null && navigator.canPop()) {
                navigator.maybePop();
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: child,
        ),
      ),
    );
  }
}

class EscapeIntent extends Intent {
  const EscapeIntent();
}
