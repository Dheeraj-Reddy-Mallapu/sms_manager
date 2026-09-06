import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sms_manager/src/core/utils/smart_text_parser.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sms_manager/src/services/native_sms_service.dart';

void showEntityBottomSheet(BuildContext context, MessageToken token) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _EntityBottomSheet(token: token),
  );
}

class _EntityBottomSheet extends StatelessWidget {
  final MessageToken token;

  const _EntityBottomSheet({required this.token});

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.pop(context);
  }

  void _launchUrl(BuildContext context, String urlString) async {
    final uri = Uri.tryParse(urlString);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    IconData icon;
    String title;
    List<Widget> actions = [];

    switch (token.type) {
      case TokenType.url:
        icon = Icons.language;
        title = 'Web Link';
        actions = [
          ListTile(
            leading: const Icon(Icons.open_in_browser),
            title: const Text('Open in Browser'),
            onTap: () {
              var url = token.text;
              if (!url.startsWith('http://') && !url.startsWith('https://')) {
                url = 'https://$url';
              }
              _launchUrl(context, url);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy Link'),
            onTap: () => _copy(context, token.text),
          ),
        ];
        break;

      case TokenType.phone:
        icon = Icons.phone;
        title = 'Phone Number';
        actions = [
          ListTile(
            leading: const Icon(Icons.call),
            title: const Text('Call'),
            onTap: () {
              NativeSmsService.dialNumber(token.text);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.message),
            title: const Text('Send Message'),
            onTap: () {
              _launchUrl(context, 'sms:${token.text}');
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_add),
            title: const Text('Add to Contacts'),
            onTap: () {
              // Can't directly open insert intent without specific code, so we dial to open dialer, which has add contact
              NativeSmsService.dialNumber(token.text);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy Number'),
            onTap: () => _copy(context, token.text),
          ),
        ];
        break;

      case TokenType.email:
        icon = Icons.email;
        title = 'Email Address';
        actions = [
          ListTile(
            leading: const Icon(Icons.mail),
            title: const Text('Send Email'),
            onTap: () => _launchUrl(context, 'mailto:${token.text}'),
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy Email'),
            onTap: () => _copy(context, token.text),
          ),
        ];
        break;

      case TokenType.date:
        icon = Icons.calendar_today;
        title = 'Date';
        actions = [
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy Date'),
            onTap: () => _copy(context, token.text),
          ),
        ];
        break;

      case TokenType.otp:
        icon = Icons.password;
        title = 'Verification Code';
        actions = [
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy Code'),
            onTap: () => _copy(context, token.text),
          ),
        ];
        break;

      default:
        icon = Icons.text_snippet;
        title = 'Text';
        actions = [
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy Text'),
            onTap: () => _copy(context, token.text),
          ),
        ];
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  foregroundColor: theme.colorScheme.onSecondaryContainer,
                  child: Icon(icon),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        token.text,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          ...actions,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
