import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/theme/glass.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileDetailsScreen extends StatefulWidget {
  const ProfileDetailsScreen({super.key});

  @override
  _ProfileDetailsScreenState createState() => _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends State<ProfileDetailsScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? userProfile;
  bool isLoadingProfile = true;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserProfile() async {
    try {
      final profile = await ApiService.getUserProfile();
      if (mounted) {
        setState(() {
          userProfile = profile;
          isLoadingProfile = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoadingProfile = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profil maʼlumotlarini yuklashda xato: $e')),
        );
      }
    }
  }

  void _showEditProfileDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (dialogContext) => EditProfileDialog(
            userProfile: userProfile!,
            onSave: () async {
              Navigator.pop(dialogContext);
              await _fetchUserProfile(); // Profilni yangilash
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: themeProvider.backgroundColor,
      appBar: AppBar(
        backgroundColor: themeProvider.appBarColor,
        elevation: 2,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: themeProvider.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Profil maʼlumotlari',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: themeProvider.textColor,
          ),
        ),
      ),
      body: SafeArea(
        top: true,
        child:
            isLoadingProfile
                ? Center(
                  child: CircularProgressIndicator(
                    color: themeProvider.accentColor,
                  ),
                )
                : userProfile == null
                ? Center(
                  child: Text(
                    "Profil ma'lumotlari topilmadi",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: themeProvider.subTextColor,
                    ),
                  ),
                )
                : RefreshIndicator(
                  onRefresh: _fetchUserProfile,
                  color: themeProvider.accentColor,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: themeProvider.currentDeviceColor,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: themeProvider.accentColor,
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: themeProvider.shadowColor,
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: themeProvider.accentColor,
                                  ),
                                  child: CircleAvatar(
                                    radius: 50,
                                    backgroundColor: Colors.transparent,
                                    child: Text(
                                      userProfile!['full_name']?.substring(
                                            0,
                                            1,
                                          ) ??
                                          "A",
                                      style: const TextStyle(
                                        fontSize: 40,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  userProfile!['full_name'] ?? "Noma'lum",
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: themeProvider.textColor,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                GestureDetector(
                                  onTapDown:
                                      (_) => _animationController.forward(),
                                  onTapUp: (_) {
                                    _animationController.reverse();
                                    _showEditProfileDialog();
                                  },
                                  onTapCancel:
                                      () => _animationController.reverse(),
                                  child: AnimatedBuilder(
                                    animation: _animationController,
                                    builder: (context, child) {
                                      return Transform.scale(
                                        scale: _scaleAnimation.value,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                            horizontal: 20,
                                          ),
                                          decoration: BoxDecoration(
                                            color: themeProvider.accentColor,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                IconlyLight.edit,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                "Tahrirlash",
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildProfileInfoCard(
                            "Username",
                            userProfile!['username'] ?? "Noma'lum",
                            IconlyLight.profile,
                          ),
                          _buildProfileInfoCard(
                            "Telefon",
                            userProfile!['phone'] ?? "Noma'lum",
                            IconlyLight.call,
                          ),
                          _buildProfileInfoCard(
                            "Jins",
                            userProfile!['sex'] == 1 ? "Erkak" : "Ayol",
                            IconlyLight.user2,
                          ),
                          _buildProfileInfoCard(
                            "Tug'ilgan sana",
                            DateTime.fromMillisecondsSinceEpoch(
                              userProfile!['birth_date'] * 1000,
                            ).toString().split(" ")[0],
                            IconlyLight.calendar,
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
      ),
    );
  }

  Widget _buildProfileInfoCard(String label, String value, IconData icon) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTapDown: (_) => _animationController.forward(),
        onTapUp: (_) => _animationController.reverse(),
        onTapCancel: () => _animationController.reverse(),
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 15,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: themeProvider.cardColor,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: themeProvider.borderColor,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: themeProvider.shadowColor,
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: themeProvider.iconCircleColor,
                      ),
                      child: Icon(
                        icon,
                        color: themeProvider.iconColor,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 16,
                              color: themeProvider.textColor,
                            ),
                          ),
                          Text(
                            value,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: themeProvider.textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class EditProfileDialog extends StatefulWidget {
  final Map<String, dynamic> userProfile;
  final Future<void> Function() onSave;

  const EditProfileDialog({
    super.key,
    required this.userProfile,
    required this.onSave,
  });

  @override
  _EditProfileDialogState createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<EditProfileDialog> {
  late TextEditingController fullNameController;
  late TextEditingController usernameController;
  late DateTime selectedBirthDate;
  late int selectedSex;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    fullNameController = TextEditingController(
      text: widget.userProfile['full_name'] ?? '',
    );
    usernameController = TextEditingController(
      text: widget.userProfile['username'] ?? '',
    );
    selectedBirthDate = DateTime.fromMillisecondsSinceEpoch(
      widget.userProfile['birth_date'] * 1000,
    );
    selectedSex = widget.userProfile['sex'] ?? 1;
  }

  @override
  void dispose() {
    fullNameController.dispose();
    usernameController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (fullNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("To'liq ism bo'sh bo'lmasligi kerak")),
      );
      return;
    }
    if (usernameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Username bo'sh bo'lmasligi kerak")),
      );
      return;
    }
    setState(() => isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    if (authToken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Xatolik: Auth token topilmadi')),
      );
      setState(() => isLoading = false);
      return;
    }

    final success = await ApiService.updateUser(
      fullName: fullNameController.text,
      username: usernameController.text,
      birthDate: (selectedBirthDate.millisecondsSinceEpoch ~/ 1000),
      sex: selectedSex,
      token: authToken,
    );

    setState(() => isLoading = false);

    if (success) {
      widget.onSave();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil ma\'lumotlari yangilandi')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profil ma\'lumotlarini yangilashda xato'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewPadding.bottom,
        ),
        decoration: BoxDecoration(
          gradient: GlassSurface.gradient,
          borderRadius: GlassSurface.sheetBorderRadius,
          border: GlassSurface.sheetBorder,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    IconlyLight.edit,
                    color: themeProvider.accentColor,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Profilni tahrirlash",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: themeProvider.textColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: fullNameController,
                decoration: InputDecoration(
                  labelText: "To'liq ism",
                  labelStyle: TextStyle(color: themeProvider.subTextColor),
                  filled: true,
                  fillColor: themeProvider.backgroundColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: themeProvider.borderColor),
                  ),
                ),
                style: TextStyle(color: themeProvider.textColor),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: usernameController,
                decoration: InputDecoration(
                  labelText: "Username",
                  labelStyle: TextStyle(color: themeProvider.subTextColor),
                  filled: true,
                  fillColor: themeProvider.backgroundColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: themeProvider.borderColor),
                  ),
                ),
                style: TextStyle(color: themeProvider.textColor),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: selectedBirthDate,
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now().subtract(
                      const Duration(days: 365 * 13),
                    ), // 13 yoshdan kichik bo‘lmasligi uchun
                    builder: (context, child) {
                      return Theme(
                        data: ThemeData.light().copyWith(
                          colorScheme: ColorScheme.light(
                            primary: themeProvider.accentColor,
                            onPrimary: Colors.white,
                            surface: themeProvider.cardColor,
                            onSurface: themeProvider.textColor,
                          ),
                          dialogBackgroundColor: themeProvider.cardColor,
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null && picked != selectedBirthDate) {
                    setState(() {
                      selectedBirthDate = picked;
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 15,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: themeProvider.backgroundColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: themeProvider.borderColor),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        IconlyLight.calendar,
                        color: themeProvider.iconColor,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        "Tug'ilgan sana: ${selectedBirthDate.toString().split(" ")[0]}",
                        style: TextStyle(
                          fontSize: 16,
                          color: themeProvider.textColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: selectedSex,
                decoration: InputDecoration(
                  labelText: "Jins",
                  labelStyle: TextStyle(color: themeProvider.subTextColor),
                  filled: true,
                  fillColor: themeProvider.backgroundColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: themeProvider.borderColor),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text("Erkak")),
                  DropdownMenuItem(value: 2, child: Text("Ayol")),
                ],
                onChanged: (value) {
                  setState(() {
                    selectedSex = value!;
                  });
                },
                style: TextStyle(color: themeProvider.textColor),
                dropdownColor: themeProvider.cardColor,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: isLoading ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeProvider.accentColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 5,
                    ),
                    child:
                        isLoading
                            ? const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            )
                            : const Text("Saqlash"),
                  ),
                  ElevatedButton(
                    onPressed: isLoading ? null : () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeProvider.cancelButtonColor,
                      foregroundColor: themeProvider.textColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 5,
                    ),
                    child: const Text("Bekor qilish"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
