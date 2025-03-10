import 'dart:async';

import 'package:market_stream/data/data_providers.dart';
import 'package:market_stream/data/events/candlestick_event.dart';
import 'package:market_stream/data/models/candle.dart';
import 'package:market_stream/data/models/symbol.dart';
import 'package:market_stream/data/models/time_interval.dart';
import 'package:market_stream/data/repositories/candlestick_repository.dart';
import 'package:riverpod/riverpod.dart';

final symbolDetailVMProvider = StateNotifierProvider.autoDispose<SymbolDetailViewModel, SymbolDetailState>((ref) {
  return SymbolDetailViewModel(
    ref.read(candlestickRepositoryProvider),
  );
});

class SymbolDetailViewModel extends StateNotifier<SymbolDetailState> {
  SymbolDetailViewModel(this._candlestickRepository) : super(SymbolDetailState());

  final CandlestickRepository _candlestickRepository;

  StreamSubscription? _candlestickStreamSubscription;

  void init(MarketSymbol symbol) async {
    state = state.copyWith(
      currentSymbol: symbol,
      intervals: TimeInterval.values,
      currentInterval: TimeInterval.values.where((interval) => interval.isPinned).first,
    );
    _fetchNewCandles();

    /// Websocket streams handling
    _candlestickStreamSubscription = _candlestickRepository.candlestickStream.listen(_onCandlestickEvent);
  }

  Future<void> _fetchNewCandles() async {
    final symbol = state.currentSymbol;
    final interval = state.currentInterval;
    if (symbol == null || interval == null) return;

    _candlestickRepository.unsubscribeCandlestickStream(symbol: symbol.id, interval: interval);
    final candles = await _candlestickRepository.fetchCandles(symbol: symbol.id, interval: interval);
    if (candles.isNotEmpty) {
      state = state.copyWith(candles: candles);
      _candlestickRepository.subscribeCandlestickStream(symbol: symbol.id, interval: interval);
    }
  }

  void _onCandlestickEvent(CandlestickEvent event) {
    final candles = List.of(state.candles ?? <Candle>[]);
    if (candles.isEmpty) return;

    final incommingCandle = event.candle;
    final latestCandle = candles.first;
    // Check if incoming candle is an update on current latest candle, or a new one
    if (latestCandle.date == incommingCandle.date && latestCandle.open == incommingCandle.open) {
      candles[0] = incommingCandle;
      state = state.copyWith(candles: candles);
    }
    // check if incoming new candle is next candle so the difrence
    // between times must be the same as last existing 2 candles
    else if (incommingCandle.date.difference(latestCandle.date) == latestCandle.date.difference(candles[1].date)) {
      candles.insert(0, incommingCandle);
      state = state.copyWith(candles: candles);
    }
  }

  void onSymbolChanged(MarketSymbol symbol) {
    state = state.copyWith(currentSymbol: symbol);
    _fetchNewCandles();
  }

  void onIntervalChanged(TimeInterval interval) {
    state = state.copyWith(currentInterval: interval);
    _fetchNewCandles();
  }

  Future<void> fetchMoreCandles() async {
    final candles = state.candles;
    final symbol = state.currentSymbol;
    final interval = state.currentInterval;
    if (candles == null || candles.isEmpty || symbol == null || interval == null) return;

    final newCandles = await _candlestickRepository.fetchCandles(
      symbol: symbol.id,
      interval: interval,
      endTime: candles.last.date.millisecondsSinceEpoch + 1,
    );

    if (newCandles.length > 1) {
      state = state.copyWith(candles: [...candles, ...newCandles]);
    }
  }

  @override
  void dispose() {
    _candlestickStreamSubscription?.cancel();
    super.dispose();
  }
}

class SymbolDetailState {
  SymbolDetailState({
    this.intervals,
    this.candles,
    this.currentInterval,
    this.currentSymbol,
  });

  final List<TimeInterval>? intervals;
  final List<Candle>? candles;
  final TimeInterval? currentInterval;
  final MarketSymbol? currentSymbol;

  SymbolDetailState copyWith({
    List<TimeInterval>? intervals,
    List<Candle>? candles,
    TimeInterval? currentInterval,
    MarketSymbol? currentSymbol,
  }) {
    return SymbolDetailState(
      intervals: intervals ?? this.intervals,
      candles: candles ?? this.candles,
      currentInterval: currentInterval ?? this.currentInterval,
      currentSymbol: currentSymbol ?? this.currentSymbol,
    );
  }
}
