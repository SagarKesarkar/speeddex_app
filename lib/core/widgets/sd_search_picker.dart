import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/sd_colors.dart';
import '../theme/sd_tokens.dart';
import '../theme/sd_typography.dart';

/// Type-to-search dropdown. The user types, matching options load from
/// [search], and a value only counts once it is picked from the list, so free
/// text can never be saved. Typing over a picked value clears the selection.
class SdSearchPicker<T extends Object> extends StatefulWidget {
  const SdSearchPicker({
    super.key,
    required this.label,
    required this.search,
    required this.displayOf,
    required this.onChanged,
    this.selected,
    this.subtitleOf,
    this.hint,
    this.enabled = true,
    this.requiredMessage,
  });

  final String label;
  final String? hint;
  final T? selected;
  final Future<List<T>> Function(String query) search;
  final String Function(T) displayOf;
  final String? Function(T)? subtitleOf;
  final ValueChanged<T?> onChanged;
  final bool enabled;

  /// When set, an empty selection fails validation with this message.
  final String? requiredMessage;

  @override
  State<SdSearchPicker<T>> createState() => _SdSearchPickerState<T>();
}

class _SdSearchPickerState<T extends Object> extends State<SdSearchPicker<T>> {
  late final _controller = TextEditingController(
    text: widget.selected == null ? '' : widget.displayOf(widget.selected as T),
  );
  final _focus = FocusNode();
  bool _loading = false;
  String? _error;
  int _request = 0;

  @override
  void didUpdateWidget(covariant SdSearchPicker<T> old) {
    super.didUpdateWidget(old);
    // Parent reset the value (e.g. city cleared after the country changed).
    if (widget.selected == null && old.selected != null && !_focus.hasFocus) {
      _controller.clear();
    } else if (widget.selected != null && widget.selected != old.selected) {
      _controller.text = widget.displayOf(widget.selected as T);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<Iterable<T>> _options(TextEditingValue value) async {
    final query = value.text.trim();
    // A picked value's own label isn't a new search.
    if (widget.selected != null && query == widget.displayOf(widget.selected as T)) return const [];
    final id = ++_request;
    await Future<void>.delayed(const Duration(milliseconds: 250)); // debounce typing
    if (id != _request || !mounted) return const [];
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.search(query);
      return id == _request ? r : const [];
    } catch (_) {
      if (mounted && id == _request) {
        setState(() => _error = 'Couldn’t load options. Check your connection.');
      }
      return const [];
    } finally {
      if (mounted && id == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<T>(
      textEditingController: _controller,
      focusNode: _focus,
      displayStringForOption: widget.displayOf,
      optionsBuilder: _options,
      onSelected: (v) {
        widget.onChanged(v);
        _focus.unfocus();
      },
      fieldViewBuilder: (context, controller, focus, onSubmitted) => TextFormField(
        controller: controller,
        focusNode: focus,
        enabled: widget.enabled,
        textInputAction: TextInputAction.search,
        textCapitalization: TextCapitalization.words,
        autocorrect: false,
        onChanged: (text) {
          if (widget.selected != null && text != widget.displayOf(widget.selected as T)) {
            widget.onChanged(null);
          }
        },
        validator: (_) {
          final text = controller.text.trim();
          if (widget.selected == null && text.isNotEmpty) {
            return 'Choose a ${widget.label.toLowerCase()} from the list.';
          }
          if (widget.selected == null && widget.requiredMessage != null) {
            return widget.requiredMessage;
          }
          return null;
        },
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          errorText: _error,
          suffixIcon: _loading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : controller.text.isEmpty || !widget.enabled
              ? const Icon(Icons.search_rounded, color: SdColors.textFaint)
              : IconButton(
                  tooltip: 'Clear ${widget.label.toLowerCase()}',
                  icon: const Icon(Icons.close_rounded, color: SdColors.textMuted),
                  onPressed: () {
                    controller.clear();
                    widget.onChanged(null);
                    focus.requestFocus();
                  },
                ),
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: SdColors.surfaceHigh,
          elevation: 8,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(SdRadius.sm),
            side: BorderSide(color: SdColors.lineStrong),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: 240,
              maxWidth: MediaQuery.sizeOf(context).width - SdSpace.gutter * 2,
            ),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, i) {
                final o = options.elementAt(i);
                final sub = widget.subtitleOf?.call(o);
                return InkWell(
                  onTap: () => onSelected(o),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SdSpace.lg,
                      vertical: SdSpace.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.displayOf(o), style: SdType.body),
                        if (sub != null) Text(sub, style: SdType.caption.copyWith(fontSize: 11)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
