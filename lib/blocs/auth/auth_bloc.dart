import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/services/storage_service.dart';

sealed class AuthEvent {}

class SendPhoneEvent extends AuthEvent {
  final String phone;
  SendPhoneEvent(this.phone);
}

class ConfirmCodeEvent extends AuthEvent {
  final String code;
  ConfirmCodeEvent(this.code);
}

class SelectDeviceEvent extends AuthEvent {
  final String code;
  final String tokenId;
  SelectDeviceEvent(this.code, this.tokenId);
}

class RegisterUserEvent extends AuthEvent {
  final String fullName;
  final String username;
  final int birthDate;
  final int sex;
  RegisterUserEvent(this.fullName, this.username, this.birthDate, this.sex);
}

class ToggleAuthModeEvent extends AuthEvent {}

class AuthErrorEvent extends AuthEvent {
  final String message;
  AuthErrorEvent(this.message);
}

sealed class AuthState {}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthCodeSent extends AuthState {}

class AuthSuccess extends AuthState {}

class AuthError extends AuthState {
  final String message;
  AuthError(this.message);
}

class AuthDeviceSelection extends AuthState {
  final List<dynamic> devices;
  AuthDeviceSelection(this.devices);
}

class AuthRegister extends AuthState {}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final ApiService apiService;
  final StorageService storageService;

  AuthBloc(this.apiService, this.storageService) : super(AuthInitial()) {
    on<SendPhoneEvent>((event, emit) async {
      emit(AuthLoading());
      final result = await apiService.sendPhone(event.phone);
      if (result) {
        emit(AuthCodeSent());
      } else {
        emit(AuthError("SMS yuborishda xatolik yuz berdi"));
      }
    });

    on<ConfirmCodeEvent>((event, emit) async {
      emit(AuthLoading());
      final result = await apiService.confirmSms(event.code);
      if (result['success']) {
        if (state is AuthRegister) {
          emit(AuthSuccess()); // Keyinroq ro‘yxatdan o‘tish logikasi qo‘shiladi
        } else {
          emit(AuthSuccess());
        }
      } else if (result.containsKey('devices')) {
        emit(AuthDeviceSelection(result['devices']));
      } else {
        emit(AuthError(result['message'] ?? "Kod tasdiqlashda xatolik"));
      }
    });

    on<SelectDeviceEvent>((event, emit) async {
      emit(AuthLoading());
      final result = await apiService.confirmSms(
        event.code,
        tokenId: event.tokenId,
      );
      if (result['success']) {
        emit(AuthSuccess());
      } else {
        emit(AuthError("Qurilma tanlashda xatolik"));
      }
    });

    on<RegisterUserEvent>((event, emit) async {
      emit(AuthLoading());
      final token = await storageService.getToken() ?? '';
      final result = await apiService.updateUser(
        fullName: event.fullName,
        username: event.username,
        birthDate: event.birthDate,
        sex: event.sex,
      );
      if (result) {
        emit(AuthSuccess());
      } else {
        emit(AuthError("Ro‘yxatdan o‘tishda xatolik yuz berdi"));
      }
    });

    on<ToggleAuthModeEvent>((event, emit) {
      emit(state is AuthRegister ? AuthInitial() : AuthRegister());
    });

    on<AuthErrorEvent>((event, emit) {
      emit(AuthError(event.message));
    });
  }
}
