import 'package:campusbite/navigation/bottom_navigation.dart';
import 'package:campusbite/screens/login_screen.dart';
import 'package:campusbite/services/auth_service.dart';
import 'package:campusbite/widgets/auth_fields.dart';
import 'package:flutter/material.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool agreeTerms = false;
  bool isLoading = false;

  @override
  void dispose() {
    fullNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (!agreeTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please read and accept the Terms of Service to continue.',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => isLoading = true);

    final error = await _authService.register(
      fullName: fullNameController.text,
      email: emailController.text,
      password: passwordController.text,
    );

    if (!mounted) return;
    setState(() => isLoading = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      // Clear the entire navigation stack and go to MainScreen —
      // the user must not be able to press back to the welcome/register flow.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xfff5f5f5),

      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              //----------------------------------------------------------
              // GREEN HEADER
              //----------------------------------------------------------
              Container(
                width: double.infinity,
                height: size.height * .28,
                decoration: const BoxDecoration(color: Colors.orange),

                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Campus Bite",
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    SizedBox(height: 8),

                    Text(
                      "Elevate Your Campus Dining",
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              //----------------------------------------------------------
              // WHITE CARD
              //----------------------------------------------------------
              Transform.translate(
                offset: const Offset(0, -20),

                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 16),

                  decoration: BoxDecoration(
                    color: Colors.white,

                    borderRadius: BorderRadius.circular(18),

                    border: Border.all(color: Colors.green.shade100),

                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .08),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),

                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 28,
                    ),

                    child: Form(
                      key: _formKey,

                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          //------------------------------------------------
                          // TITLE
                          //------------------------------------------------
                          const Align(
                            alignment: Alignment.center,
                            child: Text(
                              "Create Account",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Color(0xff156D27),
                              ),
                            ),
                          ),

                          const SizedBox(height: 6),

                          const Text(
                            "Join the campus food community",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 16,
                            ),
                          ),

                          const SizedBox(height: 28),

                          //------------------------------------------------
                          // FULL NAME
                          //------------------------------------------------
                          const Text(
                            "Full Name",
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                            ),
                          ),

                          const SizedBox(height: 8),

                          FullName(controller: fullNameController),
                          const SizedBox(height: 18),

                          //------------------------------------------------
                          // EMAIL
                          //------------------------------------------------
                          const Text(
                            "University Email",
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                            ),
                          ),

                          const SizedBox(height: 8),

                          EmailField(controller: emailController),

                          const SizedBox(height: 18),

                          //------------------------------------------------
                          // PASSWORD
                          //------------------------------------------------
                          const Text(
                            "Password",
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                            ),
                          ),

                          const SizedBox(height: 8),

                          PasswordField(controller: passwordController),
                          const Text(
                            '* save and remember your password somewhere safe',
                          ),
                          const SizedBox(height: 18),

                          //------------------------------------------------
                          // CONFIRM PASSWORD
                          //------------------------------------------------
                          const Text(
                            "Confirm Password",
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                            ),
                          ),

                          const SizedBox(height: 8),

                          PasswordField(
                            controller: confirmPasswordController,
                            matchController: passwordController,
                            isConfirmField: true,
                          ),
                          const SizedBox(height: 20),

                          //------------------------------------------------
                          // CHECKBOX
                          //------------------------------------------------
                          Row(
                            children: [
                              Checkbox(
                                value: agreeTerms,
                                activeColor: Colors.green,

                                onChanged: (value) {
                                  setState(() {
                                    agreeTerms = value!;
                                  });
                                },
                              ),

                              Expanded(
                                child: RichText(
                                  text: const TextSpan(
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontSize: 15,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: "Please read & agree to the ",
                                      ),
                                      TextSpan(
                                        text: "Terms of Service",
                                        style: TextStyle(
                                          color: Color(0xff156D27),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      TextSpan(
                                        text:
                                            " to prevent bans or account suspension.",
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          //------------------------------------------------
                          // REGISTER BUTTON
                          //------------------------------------------------
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: isLoading ? null : _handleRegister,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF116522),
                                disabledBackgroundColor: const Color(
                                  0xFF116522,
                                ).withValues(alpha: 0.6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: isLoading
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Register',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Icon(
                                          Icons.arrow_forward,
                                          size: 20,
                                          color: Colors.white,
                                        ),
                                      ],
                                    ),
                            ),
                          ),

                          const SizedBox(height: 26),

                          const Divider(),

                          const SizedBox(height: 20),

                          //------------------------------------------------
                          // LOGIN
                          //------------------------------------------------
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                "Already have an account?",
                                style: TextStyle(fontSize: 15),
                              ),
                              const SizedBox(width: 6),

                              GestureDetector(
                                onTap: () {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const LoginScreen(),
                                    ),
                                  );
                                },
                                child: const Text(
                                  'Login',
                                  style: TextStyle(
                                    color: Color(0xFF116522),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              //----------------------------------------------------------
              // BOTTOM SECTION
              //----------------------------------------------------------
              const Text(
                "Join thousands of students saving time on every meal.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
