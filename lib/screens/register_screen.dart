import 'package:campusbite/screens/login_screen.dart';
import 'package:campusbite/widgets/auth_fields.dart';
import 'package:flutter/material.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool obscureConfirmPassword = true;
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

                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
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
                          Align(
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

                          Text(
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

                          // Added in Part 2
                          FullName(),
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

                          EmailField(),

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

                          PasswordField(),

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

                          PasswordField(),
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
                              onPressed: () {
                                // Handle register action
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF116522),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
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
                              Text(
                                "Already have an account?",
                                style: TextStyle(fontSize: 15),
                              ),
                              SizedBox(width: 6),

                              GestureDetector(
                                onTap: () {
                                  // Handle Sign Up navigation
                                  Navigator.push(
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

  //==============================================================
  // These methods will be implemented in Part 2
  //==============================================================

  Widget buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return const SizedBox();
  }

  Widget buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onTap,
  }) {
    return const SizedBox();
  }

  Widget buildAvatarSection() {
    return const SizedBox();
  }
}
