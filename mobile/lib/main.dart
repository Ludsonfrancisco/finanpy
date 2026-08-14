import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'app/app_config.dart';
import 'app/router.dart';
import 'design_system/lar_theme.dart';
void main() => runApp(MyApp(appConfig: AppConfig.fromEnvironment()));
class MyApp extends StatelessWidget { MyApp({super.key, AppConfig? appConfig}) : appConfig = appConfig ?? AppConfig.fromEnvironment(), router = createAppRouter(appConfig ?? AppConfig.fromEnvironment()); final AppConfig appConfig; final GoRouter router; @override Widget build(BuildContext context) => MaterialApp.router(title: 'Lar Finance', theme: LarTheme.light, darkTheme: LarTheme.dark, themeMode: ThemeMode.dark, debugShowCheckedModeBanner: false, routerConfig: router); }
