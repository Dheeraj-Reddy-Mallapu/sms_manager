import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:sms_manager/src/services/native_sms_service.dart';
import 'package:sms_manager/src/core/widgets/smart_avatar.dart';

class ComposePage extends StatefulWidget {
  const ComposePage({super.key});

  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  bool _isLoading = false;
  List<Map<String, String>> _searchResults = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Request focus on start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await NativeSmsService.searchContacts(query.trim());
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isLoading = false;
        });
      }
    });
  }

  Future<void> _selectContact(
    String name,
    String number,
    String photoUri,
  ) async {
    // If they typed a raw number and tapped "Send to", name might be empty
    final address = number;
    final threadId = await NativeSmsService.getOrCreateThreadId(address);
    if (threadId != null && mounted) {
      context.pushReplacement('/home/conversation/$threadId', extra: null);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to create conversation.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final query = _searchController.text.trim();

    // Check if query looks like a phone number
    final isPhoneNumber = RegExp(r'^\+?[0-9\-\s\(\)]+$').hasMatch(query);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New message'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // "To" Field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'To',
                  style: TextStyle(
                    fontSize: 16,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _focusNode,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Type a name, phone number, or email',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                // (Optional) Dialer / Contact picker icon
                IconButton(
                  icon: const Icon(Icons.dialpad),
                  onPressed: () {
                    // Could open native contact picker, but not strictly needed
                    // since we search contacts natively.
                  },
                ),
              ],
            ),
          ),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),

          Expanded(
            child: ListView(
              children: [
                // 1. Suggest sending to the typed raw number if it looks like one
                if (query.isNotEmpty && isPhoneNumber)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colorScheme.primaryContainer,
                      child: Icon(
                        Icons.send,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: const Text('Send to'),
                    subtitle: Text(query),
                    onTap: () => _selectContact(query, query, ''),
                  ),

                // 2. Search Results
                ..._searchResults.map((c) {
                  final name = c['name'] ?? '';
                  final number = c['number'] ?? '';
                  final photoUri = c['photoUri'] ?? '';
                  return ListTile(
                    leading: SmartAvatar(
                      overrideContactName: name,
                      overrideContactPhotoUri: photoUri,
                      overrideAddress: number,
                      radius: 20,
                    ),
                    title: Text(name),
                    subtitle: Text(number),
                    onTap: () => _selectContact(name, number, photoUri),
                  );
                }),

                if (!_isLoading &&
                    query.isNotEmpty &&
                    !isPhoneNumber &&
                    _searchResults.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(child: Text('No contacts found.')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
