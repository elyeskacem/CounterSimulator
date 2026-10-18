import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine_scope.dart';
import 'theme.dart';

/// Rounded dark panel used by Trip, Fuel and Oil.
class DashCard extends StatelessWidget {
  const DashCard({super.key, required this.child, this.border = Palette.line});

  final Widget child;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: child,
    );
  }
}

/// Horizontal progress bar.
class Meter extends StatelessWidget {
  const Meter({super.key, required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 10,
        color: Palette.track,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction.clamp(0.0, 1.0),
          child: Container(color: color),
        ),
      ),
    );
  }
}

/// A button that needs two taps (it asks "sure?" for 3 seconds), so a bump or a
/// glove can't trigger a refuel, an oil change or a reset by accident.
class ConfirmButton extends StatefulWidget {
  const ConfirmButton({
    super.key,
    required this.label,
    required this.armedLabel,
    required this.onConfirmed,
    this.compact = false,
    this.danger = false,
  });

  final String label;
  final String armedLabel;
  final VoidCallback onConfirmed;
  final bool compact;
  final bool danger;

  @override
  State<ConfirmButton> createState() => _ConfirmButtonState();
}

class _ConfirmButtonState extends State<ConfirmButton> {
  bool _armed = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tap() {
    if (_armed) {
      _timer?.cancel();
      setState(() => _armed = false);
      HapticFeedback.mediumImpact();
      widget.onConfirmed();
    } else {
      HapticFeedback.selectionClick();
      setState(() => _armed = true);
      _timer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _armed = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _armed ? Palette.danger : (widget.danger ? Palette.danger : Colors.white);
    return SizedBox(
      width: widget.compact ? null : double.infinity,
      height: widget.compact ? 36 : 44,
      child: TextButton(
        onPressed: _tap,
        style: TextButton.styleFrom(
          backgroundColor: _armed ? Palette.danger.withValues(alpha: 0.18) : Palette.panel2,
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: _armed ? Palette.danger : Palette.line),
          ),
        ),
        child: Text(
          _armed ? widget.armedLabel : widget.label,
          style: TextStyle(fontSize: widget.compact ? 13 : 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Numeric text field that commits when you leave it (or press Done).
class NumberRow extends StatefulWidget {
  const NumberRow({super.key, required this.title, required this.value, required this.onCommit});

  final String title;
  final double value;
  final void Function(double) onCommit;

  @override
  State<NumberRow> createState() => _NumberRowState();
}

class _NumberRowState extends State<NumberRow> {
  late final TextEditingController _controller = TextEditingController(text: _format(widget.value));
  final FocusNode _focus = FocusNode();

  static String _format(double v) => v.roundToDouble() == v ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(NumberRow old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.value != widget.value) _controller.text = _format(widget.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final v = double.tryParse(_controller.text.replaceAll(',', '.').trim());
    if (v != null && v.isFinite && v >= 0) {
      if (v != widget.value) widget.onCommit(v);
      _controller.text = _format(v);
    } else {
      _controller.text = _format(widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(widget.title),
      trailing: SizedBox(
        width: 120,
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          textAlign: TextAlign.end,
          style: mono(size: 17),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _focus.unfocus(),
          decoration: const InputDecoration(isDense: true, border: InputBorder.none),
        ),
      ),
    );
  }
}

/// Banners that slide in from the top for reminders and confirmations.
class ToastOverlay extends StatelessWidget {
  const ToastOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = EngineScope.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final t in engine.toasts)
                  GestureDetector(
                    key: ValueKey(t.id),
                    onTap: () => engine.dismissToast(t.id),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xF2161B23),
                        borderRadius: BorderRadius.circular(14),
                        border: Border(
                          left: BorderSide(color: Palette.forLevel(t.level), width: 4),
                          top: const BorderSide(color: Palette.line),
                          right: const BorderSide(color: Palette.line),
                          bottom: const BorderSide(color: Palette.line),
                        ),
                        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4))],
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          if (t.body.isNotEmpty)
                            Text(t.body, style: const TextStyle(fontSize: 13, color: Palette.muted)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
