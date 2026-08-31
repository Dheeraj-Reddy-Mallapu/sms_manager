import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:sms_manager/src/services/native_sms_service.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Prompt for Default SMS Role (required for fetching/receiving smoothly)
    bool isDefault = await NativeSmsService.isDefaultSmsApp();
    if (!isDefault) {
      await NativeSmsService.requestDefaultSmsRole();
    }

    // Brief delay for visual effect
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
