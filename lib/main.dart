import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:sms_manager/src/core/di/injection_container.dart';
import 'package:sms_manager/src/core/routing/app_router.dart';
import 'package:sms_manager/src/features/home/presentation/bloc/home_bloc.dart';
import 'package:sms_manager/src/features/search/presentation/bloc/search_bloc.dart';
import 'package:sms_manager/src/services/intent_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setupDependencyInjection();
  IntentService.initialize();
  runApp(const SmsManagerApp());
}

class SmsManagerApp extends StatelessWidget {
  const SmsManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<HomeBloc>(create: (context) => sl<HomeBloc>()),
        BlocProvider<SearchBloc>(create: (context) => sl<SearchBloc>()),
      ],
      child: DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
          ColorScheme lightColorScheme;
          ColorScheme darkColorScheme;

          if (lightDynamic != null && darkDynamic != null) {
            lightColorScheme = lightDynamic.harmonized();
            darkColorScheme = darkDynamic.harmonized();
          } else {
            lightColorScheme = ColorScheme.fromSeed(seedColor: Colors.blue);
            darkColorScheme = ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            );
          }

          return MaterialApp.router(
            title: 'SMS Manager',
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('en', 'US'), // English
            ],
            theme: ThemeData(
              colorScheme: lightColorScheme,
              useMaterial3: true,
              brightness: Brightness.light,
            ),
            darkTheme: ThemeData(
              colorScheme: darkColorScheme,
              useMaterial3: true,
              brightness: Brightness.dark,
            ),
            themeMode: ThemeMode.system,
            routerConfig: appRouter,
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
