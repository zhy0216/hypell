# Backtest System Plan

## Goal

Enable strategy backtesting using the existing pure interpreter infrastructure.
A strategy written against the `Strategy` typeclass should run identically in
both live trading (`runEngine`) and historical simulation (`runBacktest`).

## Architecture Overview

```
Historical Data             Backtest Harness            Strategy
(CSV / JSON)                                            (Strategy typeclass)
     │                           │                            │
     ▼                           ▼                            ▼
loadEvents :: [MarketEvent] → eventLoop (pure) → onEvent → [TradeAction]
                                     │
                              executeAction
                                     │
                         ┌──────────────────────┐
                         │  Backtest Interpreter │
                         │  ─ MatchingEngine     │  ← fills orders against
                         │  ─ AccountSimulator   │    incoming trade/book events
                         │  ─ RiskControlPure    │
                         └──────────────────────┘
                                     │
                              BacktestResult
                         (PnL, trades, drawdown, …)
```

## Components

### 1. `Hypell.Backtest.Types` — new types
- `BacktestConfig` — initial balances, fee rate, slippage model
- `BacktestResult` — executed trades, final balances, PnL curve, metrics
- `BacktestMetrics` — total PnL, win rate, max drawdown, Sharpe ratio
- `SimFill` — record of a simulated fill (price, size, side, time)

### 2. `Hypell.Backtest.MatchingEngine` — fill simulation
Replaces the pre-populated `mesFillQueue` in `Exchange.Pure` with a
price-aware matching engine:
- Maintains a `Map OrderId PendingOrder` of resting limit orders
- On each `TradeUpdate [Trade]`: if a trade's price crosses a resting order's
  limit, generate a `FillEvent` for that order
- On `OrderBookUpdate`: optionally fill against the current best bid/ask
- Market orders fill immediately at the current best price
- Applies a configurable `feeRate` to each fill

### 3. `Hypell.Backtest.AccountSim` — account state simulator
Wraps `runAccountPure` with fill-driven balance updates:
- Tracks `Map Coin SimBalance` (total, hold, available)
- On buy fill: deduct quote, add base
- On sell fill: deduct base, add quote (after fee deduction)
- Exposes `applyFill :: SimFill -> SimState -> SimState`

### 4. `Hypell.Backtest.Runner` — `runBacktest`
```haskell
runBacktest
  :: Strategy s
  => BacktestConfig
  -> s
  -> [MarketEvent]
  -> BacktestResult
```
- Pure, no IO
- Threads `SimState` through the event sequence
- After each `TradeAction`, calls the matching engine
- The matching engine may produce new `FillEvent`s that are injected back
  into the event queue (so the strategy sees its own fills)
- Collects all `SimFill`s into `BacktestResult`

### 5. `Hypell.Backtest.DataLoader` — historical data ingestion
```haskell
loadCsvTrades  :: FilePath -> IO [MarketEvent]
loadJsonEvents :: FilePath -> IO [MarketEvent]
ohlcvToEvents  :: [OHLCVBar] -> [MarketEvent]
```
- CSV format: `time,coin,side,price,size`
- JSON format: array of serialised `Trade` objects
- `ohlcvToEvents` expands each bar into synthetic `TradeUpdate` events
  (open, high, low, close ticks) sufficient to trigger limit fills

### 6. `Hypell.Backtest.Metrics` — performance calculation
```haskell
computeMetrics :: [SimFill] -> PnLCurve -> BacktestMetrics
```
- Total PnL (realised + unrealised)
- Per-trade PnL (FIFO matching of buy/sell fills)
- Win rate (% profitable trades)
- Max drawdown
- Sharpe ratio (annualised, assumes daily grouping)

### 7. Module wiring
- `Hypell.Backtest` re-exports the public API
- `Hypell.hs` exports `Hypell.Backtest`
- `hypell.cabal` adds new modules and `cassava` (CSV) dependency

## File Layout

```
src/Hypell/Backtest/
  Types.hs           ← BacktestConfig, BacktestResult, BacktestMetrics, SimFill
  MatchingEngine.hs  ← price-aware fill simulation + Exchange interpreter
  AccountSim.hs      ← balance/position update on fills + Account interpreter
  Runner.hs          ← runBacktest harness
  DataLoader.hs      ← CSV / JSON / OHLCV loaders
  Metrics.hs         ← PnL, drawdown, Sharpe
src/Hypell/Backtest.hs  ← re-export facade
examples/
  BacktestGrid.hs    ← run SimpleGrid against synthetic OHLCV data
```

## Implementation Order

1. `Backtest/Types.hs`
2. `Backtest/MatchingEngine.hs`
3. `Backtest/AccountSim.hs`
4. `Backtest/Metrics.hs`
5. `Backtest/Runner.hs`
6. `Backtest/DataLoader.hs`
7. `Backtest.hs` facade + `Hypell.hs` re-export
8. `hypell.cabal` updates
9. `examples/BacktestGrid.hs`
