import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:riya_play/services/api_service.dart';

class TVBloc extends Bloc<TVEvent, TVState> {
  final ApiService apiService;
  final ScrollController scrollController = ScrollController();

  TVBloc(this.apiService) : super(TVState.initial()) {
    scrollController.addListener(_onScroll);

    on<FetchTVDataEvent>((event, emit) async {
      emit(state.copyWith(isLoading: true));
      try {
        final categoryData = await apiService.getTVCategories();
        final channelData = await apiService.getTVChannels(page: state.page);
        emit(
          state.copyWith(
            categories: categoryData,
            channels: channelData['tv_channels'] ?? [],
            totalChannels: channelData['count'] ?? 0,
            isLoading: false,
            hasMoreChannels: channelData['tv_channels'].length == 24,
          ),
        );
      } catch (e) {
        emit(state.copyWith(isLoading: false));
      }
    });

    on<SelectCategoryEvent>((event, emit) async {
      emit(
        state.copyWith(
          selectedCategoryId: event.categoryId,
          isLoading: true,
          channels: [],
          page: 1,
        ),
      );
      try {
        final channelData = await apiService.getTVChannels(
          page: 1,
          categoryId: event.categoryId,
        );
        emit(
          state.copyWith(
            channels: channelData['tv_channels'] ?? [],
            totalChannels: channelData['count'] ?? 0,
            isLoading: false,
            hasMoreChannels: channelData['tv_channels'].length == 24,
          ),
        );
      } catch (e) {
        emit(state.copyWith(isLoading: false));
      }
    });

    on<FetchMoreChannelsEvent>((event, emit) async {
      if (state.isLoadingMore || !state.hasMoreChannels) return;
      emit(state.copyWith(isLoadingMore: true));
      try {
        final channelData = await apiService.getTVChannels(
          page: state.page + 1,
          categoryId: state.selectedCategoryId,
        );
        emit(
          state.copyWith(
            channels: [...state.channels, ...channelData['tv_channels'] ?? []],
            page: state.page + 1,
            isLoadingMore: false,
            hasMoreChannels: channelData['tv_channels'].length == 24,
          ),
        );
      } catch (e) {
        emit(state.copyWith(isLoadingMore: false));
      }
    });

    on<PlayChannelEvent>((event, emit) {
      Navigator.push(
        event.context,
        MaterialPageRoute(
          builder:
              (_) => ChannelPlayerScreen(url: event.url, title: event.title),
        ),
      );
    });
  }

  void _onScroll() {
    if (scrollController.position.pixels >=
            scrollController.position.maxScrollExtent - 100 &&
        !state.isLoadingMore &&
        state.hasMoreChannels) {
      add(FetchMoreChannelsEvent());
    }
  }

  @override
  Future<void> close() {
    scrollController.dispose();
    return super.close();
  }
}

sealed class TVEvent {
  BuildContext get context => BuildContext();
}

class FetchTVDataEvent extends TVEvent {}

class SelectCategoryEvent extends TVEvent {
  final String? categoryId;
  SelectCategoryEvent(this.categoryId);
}

class FetchMoreChannelsEvent extends TVEvent {}

class PlayChannelEvent extends TVEvent {
  final String url;
  final String title;
  @override
  final BuildContext context;

  PlayChannelEvent(this.url, this.title, {this.context = const BuildContext()});
}

class TVState {
  final List<dynamic> categories;
  final List<dynamic> channels;
  final String? selectedCategoryId;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMoreChannels;
  final int totalChannels;
  final int page;

  TVState({
    required this.categories,
    required this.channels,
    this.selectedCategoryId,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMoreChannels,
    required this.totalChannels,
    required this.page,
  });

  factory TVState.initial() => TVState(
    categories: [],
    channels: [],
    isLoading: true,
    isLoadingMore: false,
    hasMoreChannels: true,
    totalChannels: 0,
    page: 1,
  );

  TVState copyWith({
    List<dynamic>? categories,
    List<dynamic>? channels,
    String? selectedCategoryId,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMoreChannels,
    int? totalChannels,
    int? page,
  }) => TVState(
    categories: categories ?? this.categories,
    channels: channels ?? this.channels,
    selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasMoreChannels: hasMoreChannels ?? this.hasMoreChannels,
    totalChannels: totalChannels ?? this.totalChannels,
    page: page ?? this.page,
  );
}
