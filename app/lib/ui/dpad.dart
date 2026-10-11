import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Text field that works with a TV remote: Up/Down move focus out of the field,
/// and the center (select) button re-opens the on-screen keyboard.
class DpadTextField extends StatefulWidget {
  final TextEditingController controller;
  final InputDecoration decoration;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  const DpadTextField({
    super.key,
    required this.controller,
    required this.decoration,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  @override
  State<DpadTextField> createState() => _DpadTextFieldState();
}

class _DpadTextFieldState extends State<DpadTextField> {
  late final FocusNode _node;

  @override
  void initState() {
    super.initState();
    _node = FocusNode(onKeyEvent: _onKey);
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      node.focusInDirection(TraversalDirection.down);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      node.focusInDirection(TraversalDirection.up);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.select && defaultTargetPlatform == TargetPlatform.android) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      focusNode: _node,
      controller: widget.controller,
      decoration: widget.decoration,
      obscureText: widget.obscureText,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autofocus: widget.autofocus,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: widget.onChanged,
      onSubmitted: (v) {
        widget.onSubmitted?.call(v);
        if (widget.textInputAction == TextInputAction.next) {
          _node.nextFocus();
        }
      },
    );
  }
}
