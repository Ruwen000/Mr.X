// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passController = TextEditingController();
  bool isLogin = true;
  String error = '';
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);

    // Kontrastreiche Button-Farben auf dunklem Hintergrund
    final buttonColor =
        isLogin ? Colors.deepPurpleAccent : Colors.greenAccent.shade400;
    final buttonText = isLogin ? 'Einloggen' : 'Registrieren';
    final titleText = isLogin ? 'Login' : 'Registrierung';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                titleText,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: buttonColor,
                ),
              ),
              const SizedBox(height: 32),
              // E-Mail
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'E-Mail',
                  labelStyle: TextStyle(color: Colors.white70),
                  prefixIcon: Icon(Icons.email, color: buttonColor),
                  filled: true,
                  fillColor: Colors.grey[900],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Passwort
              TextField(
                controller: passController,
                obscureText: true,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Passwort',
                  labelStyle: TextStyle(color: Colors.white70),
                  prefixIcon: Icon(Icons.lock, color: buttonColor),
                  filled: true,
                  fillColor: Colors.grey[900],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Action-Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: buttonColor,
                    foregroundColor: Colors.black,
                    textStyle:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: loading
                      ? null
                      : () async {
                          setState(() {
                            loading = true;
                            error = '';
                          });
                          try {
                            if (isLogin) {
                              await auth.login(
                                emailController.text.trim(),
                                passController.text.trim(),
                              );
                            } else {
                              await auth.register(
                                emailController.text.trim(),
                                passController.text.trim(),
                              );
                              await auth.login(
                                emailController.text.trim(),
                                passController.text.trim(),
                              );
                            }
                          } catch (e) {
                            setState(() => error =
                                e.toString().replaceAll('firebase_auth/', ''));
                          } finally {
                            setState(() => loading = false);
                          }
                        },
                  child: loading
                      ? SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.black),
                            strokeWidth: 2,
                          ),
                        )
                      : Text(buttonText),
                ),
              ),
              const SizedBox(height: 12),
              // Umschalter Login/Registrieren
              TextButton(
                onPressed: () {
                  setState(() {
                    isLogin = !isLogin;
                    error = '';
                  });
                },
                child: Text(
                  isLogin
                      ? 'Noch kein Konto? Jetzt registrieren'
                      : 'Schon registriert? Zum Login',
                  style: TextStyle(color: buttonColor),
                ),
              ),
              const SizedBox(height: 16),
              // Google Sign-In
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey[700])),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child:
                        Text('ODER', style: TextStyle(color: Colors.grey[500])),
                  ),
                  Expanded(child: Divider(color: Colors.grey[700])),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: Image.asset('lib/assets/GoogleLogo.png', height: 24),
                  label: Text('Mit Google anmelden'),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    side: BorderSide(color: Colors.grey[700]!),
                    foregroundColor: Colors.white,
                    textStyle: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onPressed: () async {
                    setState(() {
                      loading = true;
                      error = '';
                    });
                    try {
                      await auth.signInWithGoogle();
                    } catch (e) {
                      setState(() => error = e.toString());
                    } finally {
                      setState(() => loading = false);
                    }
                  },
                ),
              ),
              // Fehleranzeige
              if (error.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  error,
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
