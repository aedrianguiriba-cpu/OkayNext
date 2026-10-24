import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ableton_state.dart';
import '../providers/ableton_provider.dart';
import '../theme/app_theme.dart';

class ConnectionIndicator extends StatelessWidget {
  const ConnectionIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final ableton = context.watch<AbletonProvider>();
    final status = ableton.state.connectionStatus;
    final col = context.col;

    final (color, label) = switch (status) {
      ConnectionStatus.connected => (AppTheme.success, 'Connected'),
      ConnectionStatus.connecting => (AppTheme.warning, 'Connecting…'),
      ConnectionStatus.disconnected => (col.textMuted, 'Offline'),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: status == ConnectionStatus.connected
                ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)]
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
