import 'package:campusbite/screens/register_screen.dart';
<<<<<<< HEAD
import 'package:campusbite/widgets/auth_fields.dart';
=======
>>>>>>> b6e1b79b61bdd3cd1aa77758b5fd238ceaecd727
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
<<<<<<< HEAD
=======
  bool _obscurePassword = true;

>>>>>>> b6e1b79b61bdd3cd1aa77758b5fd238ceaecd727
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 60),

              // App Logo Placeholder (Mimicking the Orange Burger/Cap Logo)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'designs/assets/screen.png',
                  height: 80,
                  width: 80,
                ),
              ),
              const SizedBox(height: 15),

              // Welcome Text
              const Text(
                'Welcome Back!',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),

              // Subtitle Text
              const Text(
                'Fuel your study sessions with campus-best bites.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.black54),
              ),
              const SizedBox(height: 24),

              // University Email Input Field
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'University Email',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black.withValues(alpha: 0.8),
                  ),
                ),
              ),
              const SizedBox(height: 8),
<<<<<<< HEAD
              EmailField(),
=======
              TextFormField(
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'donny.wilson@student.udsm.ac.tz',
                  hintStyle: const TextStyle(color: Colors.black38),
                  prefixIcon: const Icon(
                    Icons.alternate_email,
                    size: 20,
                    color: Colors.black,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black26),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
>>>>>>> b6e1b79b61bdd3cd1aa77758b5fd238ceaecd727
              const SizedBox(height: 20),

              // Password Input Header (Label + Forgot Link)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Password',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black.withValues(alpha: 0.8),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      // Handle Forgot Password tap
                    },
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF116522),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Password Input Field
<<<<<<< HEAD
              PasswordField(),
=======
              TextFormField(
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: '••••••••',
                  hintStyle: const TextStyle(color: Colors.black38),
                  prefixIcon: const Icon(
                    Icons.lock_outline,
                    size: 20,
                    color: Colors.black,
                  ),
                  suffixIcon: GestureDetector(
                    onTap: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                    child: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: Colors.black,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black26),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
>>>>>>> b6e1b79b61bdd3cd1aa77758b5fd238ceaecd727
              const SizedBox(height: 24),

              // Login Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    // Handle Login action
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
                        'Login',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 20, color: Colors.white),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 36),

              // Footer Navigation Text
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(color: Colors.black54, fontSize: 15),
                  ),
                  GestureDetector(
                    onTap: () {
                      // Handle Sign Up navigation
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RegisterScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      'Sign Up',
                      style: TextStyle(
                        color: Color(0xFF116522),
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
