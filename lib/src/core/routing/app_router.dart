import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:sms_manager/src/core/di/injection_container.dart';
import 'package:sms_manager/src/data/models/sms_thread.dart';
import 'package:sms_manager/src/features/conversation/presentation/bloc/conversation_bloc.dart';
import 'package:sms_manager/src/features/conversation/presentation/pages/conversation_page.dart';
import 'package:sms_manager/src/features/compose/presentation/pages/compose_page.dart';
import 'package:sms_manager/src/features/home/presentation/pages/home_page.dart';
import 'package:sms_manager/src/features/home/presentation/pages/splash_page.dart';

/// Helper: wraps ConversationPage in its own BlocProvider so each
/// conversation gets an independent ConversationBloc instance.
Widget _conversationRoute(int threadId, SmsThread? thread) {
  return BlocProvider<ConversationBloc>(
    create: (_) => sl<ConversationBloc>(),
    child: ConversationPage(
      threadId: threadId,
      address: thread?.address,
      contactName: thread?.contactName,
      contactPhotoUri: thread?.contactPhotoUri,
    ),
  );
}

final appRouter = GoRouter(
  initialLocation: '/',
  debugLogDiagnostics: false,
  routes: [
    GoRoute(path: '/', builder: (context, state) => const SplashPage()),

    GoRoute(
      path: '/home',
      builder: (context, state) => const HomePage(),
      routes: [
        GoRoute(
          path: 'conversation/:threadId',
          builder: (context, state) {
            final threadId = int.parse(state.pathParameters['threadId']!);
            SmsThread? thread;
            String? initialBody;

            if (state.extra is SmsThread) {
              thread = state.extra as SmsThread;
            } else if (state.extra is Map<String, dynamic>) {
              final map = state.extra as Map<String, dynamic>;
              thread = map['thread'] as SmsThread?;
              initialBody = map['initialBody'] as String?;
            }

            return BlocProvider<ConversationBloc>(
              create: (_) => sl<ConversationBloc>(),
              child: ConversationPage(
                threadId: threadId,
                address: thread?.address,
                contactName: thread?.contactName,
                contactPhotoUri: thread?.contactPhotoUri,
                initialBody: initialBody,
              ),
            );
          },
        ),
        GoRoute(
          path: 'compose',
          builder: (context, state) {
            final initialBody = state.extra as String?;
            return ComposePage(initialBody: initialBody);
          },
        ),
      ],
    ),

    // ── Top-level deep link for notification taps ──────────────────────────
    // e.g. notification opens /conversation/42 without going through /home
    GoRoute(
      path: '/conversation/:threadId',
      builder: (context, state) {
        final threadId = int.parse(state.pathParameters['threadId']!);
        return _conversationRoute(threadId, null);
      },
    ),
  ],
);
