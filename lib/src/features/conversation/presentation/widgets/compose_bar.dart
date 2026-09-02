import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

class ComposeBar extends StatefulWidget {
  final String address;
  final bool isSending;
  final void Function(String body) onSend;

  final List<Map<String, dynamic>> simInfoList;
  final int? selectedSimId;
  final void Function(int id)? onSimSelected;
  final String? initialBody;

  const ComposeBar({
    super.key,
    required this.address,
    required this.onSend,
    this.isSending = false,
    this.initialBody,
    this.simInfoList = const [],
    this.selectedSimId,
    this.onSimSelected,
  });

  @override
  State<ComposeBar> createState() => _ComposeBarState();
}

class _ComposeBarState extends State<ComposeBar> {
  static final Map<String, String> _drafts = {};

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  int _charCount = 0;

  static const _smsLimit = 160;
  static const _multipartLimit = 153; // GSM-7 chars per part when multipart

  @override
  void initState() {
    super.initState();
    // Restore draft if exists, or use initialBody
    final savedDraft = _drafts[widget.address] ?? '';
    if (savedDraft.isNotEmpty) {
      _controller.text = savedDraft;
      _charCount = savedDraft.length;
    } else if (widget.initialBody != null && widget.initialBody!.isNotEmpty) {
      _controller.text = widget.initialBody!;
      _charCount = widget.initialBody!.length;
    }

    _controller.addListener(() {
      final text = _controller.text;
      _drafts[widget.address] = text;
      setState(() => _charCount = text.length);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isSending) return;
    HapticFeedback.lightImpact();
    widget.onSend(text);
    _drafts.remove(widget.address);
    _controller.clear();
    setState(() => _charCount = 0);
  }

  /// Returns (remaining chars in current part, total parts)
  (int, int) get _smsInfo {
    if (_charCount == 0) return (_smsLimit, 1);
    if (_charCount <= _smsLimit) {
      return (_smsLimit - _charCount, 1);
    }
    final parts = ((_charCount - 1) ~/ _multipartLimit) + 1;
    final usedInCurrentPart = _charCount - (_multipartLimit * (parts - 1));
    final remaining = _multipartLimit - usedInCurrentPart;
    return (remaining, parts);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEmpty = _charCount == 0;
    final (remaining, parts) = _smsInfo;
    final isNearLimit = remaining <= 20;
    final isMultipart = parts > 1;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Text field + char counter
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      maxLines: 5,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Message',
                        hintStyle: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                    // SMS character counter — always shown when typing
                    if (!isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 14, bottom: 6),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            isMultipart
                                ? '$remaining / $parts SMS'
                                : '$remaining',
                            style: TextStyle(
                              fontSize: 10,
                              color: isNearLimit
                                  ? colorScheme.error
                                  : colorScheme.onSurfaceVariant,
                              fontWeight: isNearLimit
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Send button
            GestureDetector(
              onTap: (isEmpty || widget.isSending) ? null : _send,
              onLongPress:
                  (widget.simInfoList.length > 1 &&
                      !isEmpty &&
                      !widget.isSending)
                  ? () => _showSimSwitcher(context)
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: isEmpty
                      ? colorScheme.surfaceContainerHighest
                      : colorScheme.primary,
                  borderRadius: BorderRadius.circular(
                    24,
                  ), // Pill shape to fit text if needed
                ),
                padding: const EdgeInsets.all(12),
                child: widget.isSending
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.simInfoList.length > 1 && !isEmpty) ...[
                            Text(
                              _getSimLabel(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimary,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Icon(
                            Icons.send_rounded,
                            size: 20,
                            color: isEmpty
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.onPrimary,
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getSimLabel() {
    if (widget.selectedSimId == null) return 'SIM 1'; // fallback
    final sim = widget.simInfoList.firstWhere(
      (s) => s['subscriptionId'] == widget.selectedSimId,
      orElse: () => widget.simInfoList.first,
    );
    return 'SIM ${(sim['simSlotIndex'] as int) + 1}';
  }

  void _showSimSwitcher(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: widget.simInfoList.map((sim) {
              final isSelected = sim['subscriptionId'] == widget.selectedSimId;
              final name = sim['displayName'] as String;
              final number = sim['number'] as String;
              return ListTile(
                leading: Icon(
                  Icons.sim_card,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(name),
                subtitle: number.isNotEmpty ? Text(number) : null,
                trailing: isSelected ? const Icon(Icons.check) : null,
                onTap: () {
                  widget.onSimSelected?.call(sim['subscriptionId'] as int);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
