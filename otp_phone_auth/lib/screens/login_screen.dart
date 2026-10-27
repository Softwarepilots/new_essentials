import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../utils/app_colors.dart';
import '../models/user_model.dart';
import 'registration_screen.dart';
import 'pending_approval_screen.dart';
import 'supervisor_dashboard_feed.dart';
import 'site_engineer_dashboard.dart';
import 'accountant_dashboard.dart';
import 'architect_dashboard.dart';
import 'owner_dashboard.dart';
import 'admin_dashboard.dart';
import 'client_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );
    if (!mounted) return;
    if (success) {
      final user = authProvider.currentUser!;
      final role = user['role'];

      // Debug logs removed for performance

      Widget dashboard;

      // Normalize role for comparison (case-insensitive)
      final roleNormalized = role?.toString().toLowerCase() ?? '';

      switch (roleNormalized) {
        case 'admin':
          dashboard = const AdminDashboard();
          break;
        case 'supervisor':
          dashboard = const SupervisorDashboardFeed();
          break;
        case 'site engineer':
          final u = UserModel(
            uid: user['id'],
            phoneNumber: user['phone'] ?? '',
            name: user['full_name'],
            email: user['email'],
            role: UserRole.siteEngineer,
            createdAt: DateTime.now(),
          );
          dashboard = SiteEngineerDashboard(user: u);
          break;
        case 'accountant':
          final u = UserModel(
            uid: user['id'],
            phoneNumber: user['phone'] ?? '',
            name: user['full_name'],
            email: user['email'],
            role: UserRole.accountant,
            createdAt: DateTime.now(),
          );
          dashboard = AccountantDashboard(user: u);
          break;
        case 'architect':
          final u = UserModel(
            uid: user['id'],
            phoneNumber: user['phone'] ?? '',
            name: user['full_name'],
            email: user['email'],
            role: UserRole.architect,
            createdAt: DateTime.now(),
          );
          dashboard = ArchitectDashboard(user: u);
          break;
        case 'owner':
          final u = UserModel(
            uid: user['id'],
            phoneNumber: user['phone'] ?? '',
            name: user['full_name'],
            email: user['email'],
            role: UserRole.owner,
            createdAt: DateTime.now(),
          );
          dashboard = OwnerDashboard(user: u);
          break;
        case 'client':
          dashboard = const ClientDashboard();
          break;
        default:
          dashboard = const SupervisorDashboardFeed();
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => dashboard),
      );
    } else {
      if (authProvider.error?.contains('pending') == true ||
          authProvider.error?.contains('PENDING') == true) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PendingApprovalScreen(
              username: _usernameController.text.trim(),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.error ?? 'Login failed'),
            backgroundColor: AppColors.statusOverdue,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        return Scaffold(
          body: Stack(
            children: [
              // ── Gradient background ──────────────────────────
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D1B2A), Color(0xFF1B3A5C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),

              // ── Decorative circles ───────────────────────────
              Positioned(
                top: -60,
                right: -60,
                child: _circle(200, Colors.white.withValues(alpha: 0.04)),
              ),
              Positioned(
                top: 80,
                left: -40,
                child: _circle(140, Colors.white.withValues(alpha: 0.04)),
              ),

              // ── Main content ─────────────────────────────────
              SafeArea(
                child: Column(
                  children: [
                    // Logo area
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Logo container with frosted look
                            Container(
                              padding: EdgeInsets.all(16.r),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24.r),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 24.r,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/images/essential_homes_logo.png',
                                height: 150.h,
                                fit: BoxFit.contain,
                              ),
                            ),
                            SizedBox(height: 20.h),
                            Text(
                              'Welcome',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28.sp,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            SizedBox(height: 6.h),
                            Text(
                              'Sign in to continue',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 15.sp,
                              ),
                            ),
                            
                          ],
                        ),
                      ),
                    ),

                    // ── White card ───────────────────────────────
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(36.r),
                              topRight: Radius.circular(36.r),
                            ),
                          ),
                          padding: EdgeInsets.fromLTRB(28.w, 32.h, 28.w, 24.h),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Username
                                _buildInputField(
                                  controller: _usernameController,
                                  label: 'Username',
                                  icon: Icons.person_outline_rounded,
                                  textInputAction: TextInputAction.next,
                                  validator: (v) => (v == null || v.isEmpty)
                                      ? 'Enter your username'
                                      : null,
                                ),
                                SizedBox(height: 16.h),

                                // Password
                                _buildInputField(
                                  controller: _passwordController,
                                  label: 'Password',
                                  icon: Icons.lock_outline_rounded,
                                  obscure: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) {
                                    FocusScope.of(context).unfocus();
                                    _login();
                                  },
                                  suffix: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: Colors.grey,
                                      size: 20.sp,
                                    ),
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
                                  validator: (v) => (v == null || v.isEmpty)
                                      ? 'Enter your password'
                                      : null,
                                ),
                                SizedBox(height: 28.h),

                                // Login button
                                _buildLoginButton(authProvider),

                                SizedBox(height: 20.h),

                                // Register link
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      "Don't have an account? ",
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13.sp,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const RegistrationScreen(),
                                        ),
                                      ),
                                      child: Text(
                                        'Register',
                                        style: TextStyle(
                                          color: AppColors.deepNavy,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.sp,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8.h),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    String? Function(String?)? validator,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      style: TextStyle(
        fontSize: 15.sp,
        color: AppColors.deepNavy,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 14.sp),
        prefixIcon: Icon(
          icon,
          color: AppColors.deepNavy.withValues(alpha: 0.6),
          size: 20.sp,
        ),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF4F6FA),
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: const BorderSide(color: Color(0xFFE8ECF4), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: const BorderSide(color: AppColors.deepNavy, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: const BorderSide(
            color: AppColors.statusOverdue,
            width: 1.5,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: const BorderSide(
            color: AppColors.statusOverdue,
            width: 2,
          ),
        ),
        errorStyle: TextStyle(color: Colors.red, fontSize: 12.sp),
      ),
      validator: validator,
    );
  }

  Widget _buildLoginButton(AuthProvider authProvider) {
    return Container(
      height: 56.h,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16.r,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: authProvider.isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
          ),
        ),
        child: authProvider.isLoading
            ? SizedBox(
                width: 22.w,
                height: 22.h,
                child: const CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Sign In',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 20.sp,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _circle(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}
