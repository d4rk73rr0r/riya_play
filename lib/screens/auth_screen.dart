import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:riya_play/blocs/auth/auth_bloc.dart';
import 'package:riya_play/main.dart';
import 'package:sms_autofill/sms_autofill.dart';

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
  int? _selectedGender;

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_formatPhoneNumber);
  }

  void _formatPhoneNumber() {
    String text = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.length > 9) text = text.substring(0, 9);
    String formatted = '';
    if (text.isNotEmpty) {
      if (text.length >= 2) {
        formatted += '(${text.substring(0, 2)})';
        if (text.length > 2) {
          formatted += text.substring(2, text.length > 5 ? 5 : text.length);
          if (text.length > 5)
            formatted +=
                '-${text.substring(5, text.length > 7 ? 7 : text.length)}';
          if (text.length > 7) formatted += '-${text.substring(7)}';
        }
      } else {
        formatted += '(${text}';
      }
    }
    if (formatted != _phoneController.text) {
      _phoneController.value = _phoneController.value.copyWith(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthSuccess) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MainScreen()),
          );
        }
        if (state is AuthDeviceSelection) {
          _showDeviceSelectionDialog(state.devices);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            context.watch<AuthBloc>().state is AuthRegister
                ? "Ro'yxatdan o'tish"
                : "Kirish",
            style: const TextStyle(color: Colors.white),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.blue.shade400, Colors.blue.shade900],
              ),
            ),
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.blue.shade300, Colors.blue.shade800],
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Card(
                  elevation: 12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        final isLoginMode = state is! AuthRegister;
                        final isCodeSent =
                            state is AuthCodeSent ||
                            state is AuthDeviceSelection;

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isLoginMode
                                  ? "Telefon orqali kirish"
                                  : "Ro'yxatdan o'tish",
                              style: Theme.of(
                                context,
                              ).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (isCodeSent) _buildCodeInputFields(context),
                            if (!isCodeSent) ...[
                              _buildPhoneField(context),
                              if (!isLoginMode) ...[
                                const SizedBox(height: 20),
                                _buildTextField(
                                  controller: _fullNameController,
                                  label: "To'liq ism",
                                ),
                                const SizedBox(height: 20),
                                _buildTextField(
                                  controller: _usernameController,
                                  label: "Foydalanuvchi nomi",
                                ),
                                const SizedBox(height: 20),
                                _buildDatePicker(context),
                                const SizedBox(height: 20),
                                _buildGenderDropdown(context),
                              ],
                            ],
                            if (state is AuthError) ...[
                              const SizedBox(height: 12),
                              Text(
                                state.message,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed:
                                  state is AuthLoading
                                      ? null
                                      : () => _handleAction(
                                        context,
                                        isCodeSent,
                                        isLoginMode,
                                      ),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 48,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                backgroundColor: Colors.blue.shade700,
                                elevation: 6,
                              ),
                              child:
                                  state is AuthLoading
                                      ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                      : Text(
                                        isCodeSent
                                            ? "Tasdiqlash"
                                            : "Kodni yuborish",
                                        style: const TextStyle(
                                          fontSize: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                            ),
                            const SizedBox(height: 20),
                            if (!isCodeSent)
                              TextButton(
                                onPressed:
                                    state is AuthLoading
                                        ? null
                                        : () => context.read<AuthBloc>().add(
                                          ToggleAuthModeEvent(),
                                        ),
                                child: Text(
                                  isLoginMode
                                      ? "Ro'yxatdan o'tmoqchimisiz?"
                                      : "Kirishni xohlaysizmi?",
                                  style: TextStyle(
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneField(BuildContext context) {
    return TextField(
      controller: _phoneController,
      decoration: InputDecoration(
        labelText: "Telefon",
        prefixText: "+998 ",
        prefixStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blue.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blue.shade700, width: 2),
        ),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(9),
      ],
      enabled: context.watch<AuthBloc>().state is! AuthLoading,
    );
  }

  Widget _buildCodeInputFields(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(4, (index) {
        return SizedBox(
          width: 60,
          child: TextField(
            controller: _codeControllers[index],
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
              counterText: "",
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.blue.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.blue.shade700, width: 2),
              ),
            ),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 1,
            onChanged: (value) {
              if (value.isNotEmpty && index < 3) {
                FocusScope.of(context).nextFocus();
              }
              if (index == 3 && value.isNotEmpty) {
                _confirmCode(context);
              }
            },
          ),
        );
      }),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blue.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blue.shade700, width: 2),
        ),
      ),
      enabled: context.watch<AuthBloc>().state is! AuthLoading,
    );
  }

  Widget _buildDatePicker(BuildContext context) {
    return TextField(
      readOnly: true,
      decoration: InputDecoration(
        labelText: "Tug'ilgan sana",
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
        hintText:
            _selectedBirthDate == null
                ? "Sanani tanlang"
                : DateFormat('dd.MM.yyyy').format(_selectedBirthDate!),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blue.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blue.shade700, width: 2),
        ),
      ),
      onTap: () async {
        final pickedDate = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime.now(),
        );
        if (pickedDate != null) setState(() => _selectedBirthDate = pickedDate);
      },
    );
  }

  Widget _buildGenderDropdown(BuildContext context) {
    return DropdownButtonFormField<int>(
      value: _selectedGender,
      decoration: InputDecoration(
        labelText: "Jins",
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blue.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blue.shade700, width: 2),
        ),
      ),
      items: [
        DropdownMenuItem(value: 1, child: Text("Erkak")),
        DropdownMenuItem(value: 0, child: Text("Ayol")),
      ],
      onChanged:
          context.watch<AuthBloc>().state is AuthLoading
              ? null
              : (value) => setState(() => _selectedGender = value),
    );
  }

  void _handleAction(BuildContext context, bool isCodeSent, bool isLoginMode) {
    if (isCodeSent) {
      _confirmCode(context);
    } else {
      final rawPhone = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
      final phone = "998$rawPhone";
      if (rawPhone.length != 9) {
        context.read<AuthBloc>().add(AuthErrorEvent("To‘liq raqam kiriting"));
        return;
      }
      context.read<AuthBloc>().add(SendPhoneEvent(phone));
      _listenForSms();
    }
  }

  void _confirmCode(BuildContext context) {
    final code = _codeControllers.map((c) => c.text).join();
    if (code.length != 4) {
      context.read<AuthBloc>().add(AuthErrorEvent("To‘liq kod kiriting"));
      return;
    }
    context.read<AuthBloc>().add(ConfirmCodeEvent(code));
  }

  void _listenForSms() {
    SmsAutoFill().unregisterListener();
    SmsAutoFill()
        .listenForCode()
        .then((_) {
          debugPrint("SMS tinglash boshlandi");
        })
        .catchError((error) {
          debugPrint("SMS tinglashda xato: $error");
        });
    SmsAutoFill().code.listen((code) {
      if (code.length == 4) {
        setState(() {
          for (int i = 0; i < 4; i++) _codeControllers[i].text = code[i];
        });
        _confirmCode(context);
      }
    });
  }

  Future<void> _showDeviceSelectionDialog(List<dynamic> devices) async {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text("Bir nechta qurilma topildi"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Bitta qurilmani tanlang"),
                const SizedBox(height: 10),
                ...devices.map(
                  (device) => ListTile(
                    title: Text(device['device_name']),
                    subtitle: Text("ID: ${device['id']}"),
                    onTap: () {
                      Navigator.pop(context);
                      final code = _codeControllers.map((c) => c.text).join();
                      context.read<AuthBloc>().add(
                        SelectDeviceEvent(code, device['id'].toString()),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
    );
  }

  void _registerUser(BuildContext context) {
    final fullName = _fullNameController.text;
    final username = _usernameController.text;
    if (fullName.isEmpty ||
        username.isEmpty ||
        _selectedBirthDate == null ||
        _selectedGender == null) {
      context.read<AuthBloc>().add(
        AuthErrorEvent("Barcha maydonlarni to‘ldiring"),
      );
      return;
    }
    final birthDateUnix = _selectedBirthDate!.millisecondsSinceEpoch ~/ 1000;
    context.read<AuthBloc>().add(
      RegisterUserEvent(fullName, username, birthDateUnix, _selectedGender!),
    );
  }

  @override
  void dispose() {
    _phoneController.removeListener(_formatPhoneNumber);
    _phoneController.dispose();
    for (var controller in _codeControllers) controller.dispose();
    _fullNameController.dispose();
    _usernameController.dispose();
    SmsAutoFill().unregisterListener();
    super.dispose();
  }
}
