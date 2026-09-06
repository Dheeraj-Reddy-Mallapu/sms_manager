import 'package:get_it/get_it.dart';
import 'package:sms_manager/src/data/repositories/sms_repository.dart';
import 'package:sms_manager/src/features/home/presentation/bloc/home_bloc.dart';
import 'package:sms_manager/src/features/conversation/presentation/bloc/conversation_bloc.dart';
import 'package:sms_manager/src/features/search/presentation/bloc/search_bloc.dart';

final sl = GetIt.instance;

void setupDependencyInjection() {
  // Repositories
  sl.registerLazySingleton<SmsRepository>(() => SmsRepository());

  // BLoCs
  sl.registerFactory<HomeBloc>(() => HomeBloc(repository: sl()));
  sl.registerFactory<ConversationBloc>(
    () => ConversationBloc(repository: sl()),
  );
  sl.registerFactory<SearchBloc>(() => SearchBloc());
}
