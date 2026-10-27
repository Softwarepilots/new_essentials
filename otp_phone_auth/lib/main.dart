import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'services/push_notification_service.dart';
import 'services/location_tracking_service.dart';
import 'screens/login_screen.dart';
import 'screens/supervisor_dashboard_feed.dart';
import 'screens/admin_dashboard.dart';
import 'screens/site_engineer_dashboard.dart';
import 'screens/accountant_dashboard.dart';
import 'screens/architect_dashboard.dart';
import 'screens/owner_dashboard.dart';
import 'screens/client_dashboard.dart';
import 'utils/app_theme.dart';
import 'models/user_model.dart';
import 'providers/auth_provider.dart';
import 'providers/construction_provider.dart';
import 'providers/change_request_provider.dart';
import 'providers/site_engineer_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/material_provider.dart';
import 'providers/admin_provider.dart';
import 'providers/supervisor_provider.dart';
import 'providers/accountant_provider.dart';
import 'providers/accountant_dashboard_provider.dart';
import 'providers/accountant_entries_provider.dart';
import 'providers/architect_provider.dart';
import 'providers/client_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Firebase (mobile only — FCM not used on web)
  if (!kIsWeb) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  // Supervisor location sharing (mobile only; started from the supervisor dashboard)
  await LocationTrackingService.configure();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ConstructionProvider()),
        ChangeNotifierProvider(create: (_) => ChangeRequestProvider()),
        ChangeNotifierProvider(create: (_) => SiteEngineerProvider()),
        ChangeNotifierProvider(create: (_) => MaterialProvider()),
        ChangeNotifierProvider(create: (_) => AdminProvider()),
        ChangeNotifierProvider(create: (_) => SupervisorProvider()),
        ChangeNotifierProvider(create: (_) => AccountantProvider()),
        ChangeNotifierProvider(create: (_) => AccountantDashboardProvider()),
        ChangeNotifierProvider(create: (_) => AccountantEntriesProvider()),
        ChangeNotifierProvider(create: (_) => ArchitectProvider()),
        ChangeNotifierProvider(create: (_) => ClientProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return ScreenUtilInit(
            // Design base: standard Android phone (360×800 dp)
            designSize: const Size(360, 800),
            minTextAdapt: true,
            splitScreenMode: true,
            builder: (_, __) => MaterialApp(
              title: 'Essential Homes',
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeProvider.themeMode,
              home: const AuthChecker(),
              debugShowCheckedModeBanner: false,
            ),
          );
        },
      ),
    );
  }
}

class AuthChecker extends StatefulWidget {
  const AuthChecker({super.key});

  @override
  State<AuthChecker> createState() => _AuthCheckerState();
}

class _AuthCheckerState extends State<AuthChecker> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.initialize();
    
    if (!mounted) return;
    
    if (authProvider.isAuthenticated && authProvider.currentUser != null) {
      final user = authProvider.currentUser!;
      final role = user['role'];
      
      print('🔐 AUTH CHECK');
      print('🔐 User: ${user['username']}');
      print('🔐 Role: "$role"');
      
      // Normalize role for comparison (case-insensitive)
      final roleNormalized = role?.toString().toLowerCase() ?? '';
      print('🔐 Normalized role: "$roleNormalized"');
      
      // Navigate to appropriate dashboard
      Widget dashboard;
      switch (roleNormalized) {
        case 'admin':
          print('🔐 → AdminDashboard');
          dashboard = const AdminDashboard();
          break;
        case 'supervisor':
          print('🔐 → SupervisorDashboardFeed');
          dashboard = const SupervisorDashboardFeed();
          break;
        case 'site engineer':
          print('🔐 → SiteEngineerDashboard');
          final dummyUser = UserModel(
            uid: user['id'],
            phoneNumber: user['phone'] ?? '',
            name: user['full_name'],
            email: user['email'],
            role: UserRole.siteEngineer,
            createdAt: DateTime.now(),
          );
          dashboard = SiteEngineerDashboard(user: dummyUser);
          break;
        case 'accountant':
          print('🔐 → AccountantDashboard');
          final dummyUser = UserModel(
            uid: user['id'],
            phoneNumber: user['phone'] ?? '',
            name: user['full_name'],
            email: user['email'],
            role: UserRole.accountant,
            createdAt: DateTime.now(),
          );
          dashboard = AccountantDashboard(user: dummyUser);
          break;
        case 'architect':
          print('🔐 → ArchitectDashboard');
          final dummyUser = UserModel(
            uid: user['id'],
            phoneNumber: user['phone'] ?? '',
            name: user['full_name'],
            email: user['email'],
            role: UserRole.architect,
            createdAt: DateTime.now(),
          );
          dashboard = ArchitectDashboard(user: dummyUser);
          break;
        case 'owner':
          print('🔐 → OwnerDashboard');
          final dummyUser = UserModel(
            uid: user['id'],
            phoneNumber: user['phone'] ?? '',
            name: user['full_name'],
            email: user['email'],
            role: UserRole.owner,
            createdAt: DateTime.now(),
          );
          dashboard = OwnerDashboard(user: dummyUser);
          break;
        case 'client':
          print('🔐 ✅ → ClientDashboard');
          dashboard = const ClientDashboard();
          break;
        default:
          print('🔐 ⚠️ Unknown role "$role", showing login');
          dashboard = const LoginScreen();
      }
      
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => dashboard),
        );
      }
    } else {
      // Not logged in, show login screen
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logo.png',
              height: 100,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.construction,
                  size: 100,
                  color: Color(0xFFFF6B35),
                );
              },
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
