import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:sms_manager/src/data/models/sms_thread.dart';

class SmartAvatar extends StatefulWidget {
  final SmsThread? thread;
  final String? overrideAddress;
  final String? overrideContactName;
  final String? overrideContactPhotoUri;
  final double radius;

  const SmartAvatar({
    super.key,
    this.thread,
    this.overrideAddress,
    this.overrideContactName,
    this.overrideContactPhotoUri,
    this.radius = 24.0,
  });

  @override
  State<SmartAvatar> createState() => _SmartAvatarState();
}

class _SmartAvatarState extends State<SmartAvatar> {
  static const _queryChannel = MethodChannel('sms_manager/query');
  static final Map<String, Uint8List?> _photoCache = {};

  Uint8List? _photoBytes;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  @override
  void didUpdateWidget(SmartAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.thread?.id != oldWidget.thread?.id ||
        widget.overrideAddress != oldWidget.overrideAddress) {
      _photoBytes = null;
      _loadPhoto();
    }
  }

  String? get _photoUri =>
      widget.overrideContactPhotoUri ?? widget.thread?.contactPhotoUri;
  String get _displayName {
    final name = widget.overrideContactName ?? widget.thread?.contactName;
    if (name != null && name.isNotEmpty) return name;
    final address =
        widget.overrideAddress ?? widget.thread?.address ?? 'Unknown';
    if (address.isNotEmpty) return address;
    return 'Unknown';
  }

  Future<void> _loadPhoto() async {
    final uri = _photoUri;
    if (uri == null || uri.isEmpty) {
      if (mounted && _photoBytes != null) {
        setState(() => _photoBytes = null);
      }
      return;
    }

    if (_photoCache.containsKey(uri)) {
      setState(() {
        _photoBytes = _photoCache[uri];
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _queryChannel.invokeMethod<Uint8List>(
        'getContactPhoto',
        {'uri': uri},
      );
      if (mounted) {
        setState(() {
          _photoBytes = result;
          _photoCache[uri] = result;
          _isLoading = false;
        });
      } else {
        _photoCache[uri] = result;
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String? _getBrandLogo(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('amazon')) return 'https://logo.clearbit.com/amazon.com';
    if (lower.contains('flipkart')) {
      return 'https://logo.clearbit.com/flipkart.com';
    }
    if (lower.contains('google')) return 'https://logo.clearbit.com/google.com';
    if (lower.contains('netflix')) {
      return 'https://logo.clearbit.com/netflix.com';
    }
    if (lower.contains('swiggy')) return 'https://logo.clearbit.com/swiggy.com';
    if (lower.contains('zomato')) return 'https://logo.clearbit.com/zomato.com';
    if (lower.contains('uber')) return 'https://logo.clearbit.com/uber.com';
    if (lower.contains('ola')) return 'https://logo.clearbit.com/olacabs.com';
    if (lower.contains('hdfc')) return 'https://logo.clearbit.com/hdfcbank.com';
    if (lower.contains('sbi')) return 'https://logo.clearbit.com/onlinesbi.sbi';
    if (lower.contains('icici')) {
      return 'https://logo.clearbit.com/icicibank.com';
    }
    if (lower.contains('apple')) return 'https://logo.clearbit.com/apple.com';
    if (lower.contains('facebook') || lower.contains('fb')) {
      return 'https://logo.clearbit.com/facebook.com';
    }
    if (lower.contains('instagram')) {
      return 'https://logo.clearbit.com/instagram.com';
    }
    if (lower.contains('whatsapp')) {
      return 'https://logo.clearbit.com/whatsapp.com';
    }
    if (lower.contains('twitter') || lower.contains(' x ')) {
      return 'https://logo.clearbit.com/x.com';
    }
    if (lower.contains('myntra')) return 'https://logo.clearbit.com/myntra.com';
    if (lower.contains('paytm')) return 'https://logo.clearbit.com/paytm.com';
    if (lower.contains('phonepe')) {
      return 'https://logo.clearbit.com/phonepe.com';
    }
    if (lower.contains('jio')) return 'https://logo.clearbit.com/jio.com';
    if (lower.contains('airtel')) return 'https://logo.clearbit.com/airtel.in';
    if (lower.contains('vi') || lower.contains('vodafone')) {
      return 'https://logo.clearbit.com/myvi.in';
    }
    return null;
  }

  Color _colorFromString(String text, ColorScheme colorScheme) {
    if (text.isEmpty) return colorScheme.primary;
    int hash = 0;
    for (int i = 0; i < text.length; i++) {
      hash = text.codeUnitAt(i) + ((hash << 5) - hash);
    }
    final hue = (hash.abs() % 360).toDouble();
    // Fixed lightness to 0.4 and saturation to 0.65 to avoid white/black extremes
    return HSLColor.fromAHSL(1.0, hue, 0.65, 0.4).toColor();
  }

  Color _onColor(Color background) {
    return background.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final initial = _displayName.isNotEmpty
        ? _displayName[0].toUpperCase()
        : '?';
    final avatarColor = _colorFromString(_displayName, colorScheme);
    final fallbackTextStyle = TextStyle(
      color: _onColor(avatarColor),
      fontWeight: FontWeight.bold,
      fontSize: widget.radius * 0.75,
    );

    // 1. Check if we have loaded Android contact photo bytes
    if (_photoBytes != null) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: avatarColor,
        backgroundImage: MemoryImage(_photoBytes!),
      );
    }

    // 2. If it's a known brand, use Clearbit logo API
    final brandLogo = _getBrandLogo(_displayName);
    if (brandLogo != null && _photoUri == null) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: Colors.transparent,
        child: ClipOval(
          child: Container(
            color: Colors.white,
            child: Image.network(
              brandLogo,
              width: widget.radius * 2,
              height: widget.radius * 2,
              fit: BoxFit.cover,
              errorBuilder: (context, error, _) => Container(
                width: widget.radius * 2,
                height: widget.radius * 2,
                color: avatarColor,
                alignment: Alignment.center,
                child: Text(initial, style: fallbackTextStyle),
              ),
            ),
          ),
        ),
      );
    }

    // 3. Fallback to colored initial
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: avatarColor,
      child: _isLoading
          ? CircularProgressIndicator(
              color: _onColor(avatarColor),
              strokeWidth: 2,
            )
          : Text(initial, style: fallbackTextStyle),
    );
  }
}
