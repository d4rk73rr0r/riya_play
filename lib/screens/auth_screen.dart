import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'phone_number_formatter.dart';
import 'package:riya_play/utils/navigation.dart';
import 'package:riya_play/utils/app_logger.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phoneController = TextEditingController();
  final List<TextEditingController> _codeControllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  DateTime? _selectedBirthDate;
  bool _isLoginMode = true;
  bool _isCodeSent = false;
  bool _isLoading = false;
  String? _error;
  int? _selectedGender;
  int _remainingSeconds = 60;
  Timer? _timer;
  bool _canResend = false;

  void _startTimer() {
    _remainingSeconds = 60;
    _canResend = false;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        setState(() {
          _canResend = true;
          timer.cancel();
        });
      }
    });
  }

  String _formatDateTime(int? timestamp) {
    if (timestamp == null) return "Noma'lum";
    try {
      final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
      return DateFormat('dd.MM.yyyy HH:mm').format(dateTime);
    } catch (e) {
      return "Noma'lum";
    }
  }

  @override
  Widget build(BuildContext context) {
    // Oldingi build metodi o'zgarishsiz qoladi
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/background.png'),
                fit: BoxFit.cover,
                opacity: 0.3,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.black.withValues(alpha: 0.3),
                  Colors.black.withValues(alpha: 1.0),
                ],
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 50, bottom: 30),
                    child: Image.asset('assets/images/logo.png', height: 80),
                  ),
                  Text(
                    _isCodeSent ? "Kodni kiriting" : "Raqamingizni kiriting",
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 30),
                  if (_isCodeSent) ...[
                    _buildCodeInputFields(),
                  ] else if (_isLoginMode) ...[
                    _buildPhoneField(),
                  ] else ...[
                    _buildPhoneField(),
                    const SizedBox(height: 20),
                    _buildTextField(
                      controller: _fullNameController,
                      label: "To‘liq ism",
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      controller: _usernameController,
                      label: "Foydalanuvchi nomi",
                    ),
                    const SizedBox(height: 20),
                    _buildDatePicker(),
                    const SizedBox(height: 20),
                    _buildGenderDropdown(),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 14,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed:
                        _isLoading ||
                                (_isCodeSent &&
                                    !_canResend &&
                                    _remainingSeconds > 0)
                            ? null
                            : _handleAction,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: const Color(0xFFE91E63),
                      elevation: 6,
                    ),
                    child:
                        _isLoading
                            ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : Text(
                              _isCodeSent
                                  ? "Tasdiqlash ($_remainingSeconds)"
                                  : _canResend
                                  ? "Qayta yuborish"
                                  : "Yuborish",
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                  ),
                  const SizedBox(height: 20),
                  if (!_isCodeSent)
                    TextButton(
                      onPressed:
                          _isLoading
                              ? null
                              : () => setState(() {
                                _isLoginMode = !_isLoginMode;
                                _resetFields();
                              }),
                      child: Text(
                        _isLoginMode
                            ? "Ro‘yxatdan o‘tishni xohlaysizmi?"
                            : "Kirishni xohlaysizmi?",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: TextField(
        controller: _phoneController,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.phone, color: Colors.white),
          prefixText: "+998 ",
          prefixStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.5),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 16,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white, width: 2),
          ),
        ),
        style: const TextStyle(color: Colors.white),
        keyboardType: TextInputType.number,
        inputFormatters: [PhoneNumberFormatter()],
        enabled: !_isLoading,
      ),
    );
  }

  Widget _buildCodeInputFields() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SizedBox(
            width: 50,
            child: TextField(
              controller: _codeControllers[index],
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.5),
                counterText: "",
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white, width: 2),
                ),
              ),
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 1,
              obscureText: true,
              obscuringCharacter: '*',
              onChanged: (value) {
                if (value.isNotEmpty && index < 3) {
                  FocusScope.of(context).nextFocus();
                }
                if (index == 3 && value.isNotEmpty) _confirmCode();
              },
            ),
          ),
        );
      }),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.5),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 16,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white, width: 2),
          ),
        ),
        style: const TextStyle(color: Colors.white),
        enabled: !_isLoading,
      ),
    );
  }

  Widget _buildDatePicker() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: InkWell(
        onTap: () async {
          final pickedDate = await showDatePicker(
            context: context,
            initialDate: _selectedBirthDate ?? DateTime.now(),
            firstDate: DateTime(1900),
            lastDate: DateTime.now(),
            builder: (context, child) {
              return Theme(
                data: ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: Color(0xFFE91E63),
                    onPrimary: Colors.white,
                    surface: Colors.black,
                    onSurface: Colors.white,
                  ),
                  dialogTheme: const DialogThemeData(backgroundColor: Colors.black),
                ),
                child: child!,
              );
            },
          );
          if (pickedDate != null) {
            setState(() => _selectedBirthDate = pickedDate);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(12),
            color: Colors.black.withValues(alpha: 0.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _selectedBirthDate == null
                    ? "Tug‘ilgan sanani tanlang"
                    : DateFormat('dd MMMM yyyy').format(_selectedBirthDate!),
                style: TextStyle(
                  color:
                      _selectedBirthDate == null
                          ? Colors.white70
                          : Colors.white,
                  fontSize: 16,
                ),
              ),
              const Icon(Icons.calendar_today, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenderDropdown() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: DropdownButtonFormField<int>(
        value: _selectedGender,
        decoration: InputDecoration(
          labelText: "Jins",
          labelStyle: const TextStyle(color: Colors.white70),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.5),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 16,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white, width: 2),
          ),
        ),
        style: const TextStyle(color: Colors.white),
        dropdownColor: Colors.black,
        items: const [
          DropdownMenuItem(value: 1, child: Text("Erkak")),
          DropdownMenuItem(value: 0, child: Text("Ayol")),
        ],
        onChanged:
            _isLoading
                ? null
                : (value) => setState(() => _selectedGender = value),
      ),
    );
  }

  Future<void> _handleAction() async {
    if (_isCodeSent) {
      await _confirmCode();
    } else {
      await _sendPhone();
    }
  }

  Future<void> _sendPhone() async {
    final rawPhone = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final phone = "998$rawPhone";
    if (rawPhone.length != 9) {
      setState(() => _error = "To‘liq raqam kiriting");
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await ApiService.sendPhone(phone);

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (result) {
      setState(() => _isCodeSent = true);
      _startTimer();
      _listenForSms();
    } else {
      setState(() => _error = "SMS yuborishda xatolik yuz berdi");
    }
  }

  void _listenForSms() {
    SmsAutoFill().unregisterListener();
    SmsAutoFill()
        .listenForCode()
        .then((_) {
          appLogger.d("SMS tinglash boshlandi");
        })
        .catchError((error) {
          appLogger.d("SMS tinglashda xato: $error");
        });

    SmsAutoFill().code.listen((code) {
      appLogger.d("SMSdan olingan kod: $code");
      if (code.length == 4) {
        setState(() {
          for (int i = 0; i < 4; i++) {
            _codeControllers[i].text = code[i];
          }
        });
        appLogger.d("Kod joylashtirildi: $code");
        _confirmCode();
      } else {
        appLogger.d("Kod noto‘g‘ri uzunlikda yoki null: $code");
      }
    });
  }

  Future<void> _confirmCode() async {
    final code = _codeControllers.map((c) => c.text).join();
    if (code.length != 4) {
      setState(() => _error = "To‘liq kod kiriting");
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await ApiService.confirmSms(code);

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (result['success']) {
      if (_isLoginMode) {
        _navigateToMainScreen();
      } else {
        await _registerUser();
      }
    } else if (result.containsKey('devices')) {
      _showDeviceSelectionDialog(result['devices']);
    } else {
      setState(() => _error = result['message'] ?? "Kod tasdiqlashda xatolik");
    }
  }

  Future<void> _showDeviceSelectionDialog(List<dynamic> devices) async {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: Colors.black,
            title: const Text(
              "Bir nechta qurilma topildi",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Bitta qurilmani o‘chirib, davom eting:",
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 10),
                ...devices.map((device) {
                  final deviceId = device['id']?.toString() ?? "ID yo‘q";
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    title: Text(
                      device['device_name'] ?? "Noma'lum qurilma",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Qurilma ID: $deviceId",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          "Kirish vaqti: ${_formatDateTime(device['created_at'])}",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          "IP: ${device['user_ip'] ?? 'Noma\'lum'}",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    trailing: GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        setState(() => _isLoading = true);

                        appLogger.d("O‘chirilayotgan qurilma ID: $deviceId");
                        // kickDevice() o‘rniga confirmSms() ga token_id bilan so‘rov
                        final confirmResult = await ApiService.confirmSms(
                          _codeControllers.map((c) => c.text).join(),
                          tokenId: deviceId,
                        );
                        appLogger.d("confirmSms result: $confirmResult");

                        setState(() => _isLoading = false);
                        if (confirmResult['success']) {
                          if (_isLoginMode) {
                            _navigateToMainScreen();
                          } else {
                            await _registerUser();
                          }
                        } else {
                          setState(() {
                            _error =
                                confirmResult['message'] ??
                                "Qurilma o‘chirishda xatolik";
                          });
                        }
                      },
                      child: const Icon(
                        Icons.delete,
                        color: Colors.red,
                        size: 24,
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "Bekor qilish",
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
    );
  }

  Future<void> _registerUser() async {
    final fullName = _fullNameController.text;
    final username = _usernameController.text;
    if (fullName.isEmpty ||
        username.isEmpty ||
        _selectedBirthDate == null ||
        _selectedGender == null) {
      setState(() => _error = "Barcha maydonlarni to‘ldiring");
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';
    final birthDateUnix = (_selectedBirthDate!.millisecondsSinceEpoch ~/ 1000);

    final result = await ApiService.updateUser(
      fullName: fullName,
      username: username,
      birthDate: birthDateUnix,
      sex: _selectedGender!,
      token: token,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (result) {
      _navigateToMainScreen();
    } else {
      setState(() => _error = "Ro‘yxatdan o‘tishda xatolik yuz berdi");
    }
  }

  void _navigateToMainScreen() {
    Navigator.pushReplacement(context, createSlideRoute(const MainScreen()));
  }

  void _resetFields() {
    _error = null;
    _phoneController.clear();
    for (var controller in _codeControllers) controller.clear();
    _fullNameController.clear();
    _usernameController.clear();
    _selectedBirthDate = null;
    _selectedGender = null;
    _isCodeSent = false;
    _remainingSeconds = 60;
    _canResend = false;
    _timer?.cancel();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    for (var controller in _codeControllers) controller.dispose();
    _fullNameController.dispose();
    _usernameController.dispose();
    _timer?.cancel();
    SmsAutoFill().unregisterListener();
    super.dispose();
  }
}
