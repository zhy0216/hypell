# Backtesting with Hypell

## Overview

Any strategy that implements the `Strategy` typeclass runs unchanged in both live trading (`runEngine`) and backtesting (`runBacktest`). The backtest engine replays historical `MarketEvent`s, matches limit orders against trade ticks or order book snapshots, updates simulated balances, and computes performance metrics.

---

## Quick start

```haskell
import Hypell
import Hypell.Backtest

main :: IO ()
main = do
  -- 1. Load historical data
  Right events <- loadCsvTrades "data/eth_trades.csv"

  -- 2. Configure the simulation
  let cfg = BacktestConfig
        { bcInitialBalances = Map.fromList
            [ (Coin "USDC", 10000)
            , (Coin "ETH",  0)
            ]
        , bcFeeRate  = 0.001   -- 0.1 % taker fee
        , bcSlippage = FixedBps 5
        , bcRiskLimits = defaultRiskLimits
        }

  -- 3. Run
  result <- runBacktest cfg MyStrategy events

  -- 4. Inspect results
  let m = brMetrics result
  putStrLn $ "PnL:       " <> show (bmTotalPnl m)
  putStrLn $ "Sharpe:    " <> show (bmSharpeRatio m)
  putStrLn $ "Win rate:  " <> show (bmWinRate m)
  putStrLn $ "Max DD:    " <> show (bmMaxDrawdown m)
```

---

## Writing a strategy

Implement `Strategy` exactly as you would for live trading. The backtest engine calls `initStrategy` once, then calls `onEvent` for every replayed event.

```haskell
data MyStrategy = MyStrategy { msThreshold :: Scientific }

instance Strategy MyStrategy where
  strategyName _ = "my-strategy"

  initStrategy s = do
    log "Starting backtest"
    pure s

  onEvent s (TradeUpdate (t:_)) =
    if trdPrice t < msThreshold s
      then pure (s, [PlaceOrder OrderRequest
            { orCoin      = trdCoin t
            , orSide      = Buy
            , orSize      = 1
            , orOrderType = Limit (trdPrice t * 0.99) GTC
            , orClientId  = Nothing
            }])
      else pure (s, [])

  onEvent s _ = pure (s, [])

  onShutdown _ = pure ()
```

Effects available inside `onEvent`:

| Effect | What you can call |
|---|---|
| `MarketData` | `getOrderBook`, `getSpotMeta`, `getSpotAssetCtxs` |
| `Account` | `getBalances`, `getUserTrades` |
| `Log` | `log`, `logError` |

---

## Loading historical data

### CSV trade ticks

File format — one row per trade, header required:

```
time,coin,side,price,size
2025-01-01T00:00:00UTC,ETH,buy,3200.5,0.5
2025-01-01T00:00:01UTC,ETH,sell,3201.0,1.2
```

```haskell
Right events <- loadCsvTrades "data/trades.csv"
```

Supported `time` formats: `2025-01-01T00:00:00UTC` or `2025-01-01 00:00:00`.  
Supported `side` values: `buy`/`sell` or `B`/`A`.

### JSON trade array

File must be a JSON array matching the `Trade` type (`FromJSON` instance):

```json
[
  { "coin": "ETH", "side": "buy", "px": "3200.5", "sz": "0.5", "time": 1735689600000 },
  ...
]
```

```haskell
Right events <- loadJsonTrades "data/trades.json"
```

### OHLCV bars

Each bar is expanded into four synthetic trade ticks in the order:
`open → low → high → close`. This ensures both buy and sell limit orders
can be triggered within a single bar.

```haskell
let bars =
      [ OHLCVBar
          { ohlcvCoin   = Coin "ETH"
          , ohlcvTime   = read "2025-01-01 00:00:00 UTC"
          , ohlcvOpen   = 3200
          , ohlcvHigh   = 3250
          , ohlcvLow    = 3180
          , ohlcvClose  = 3230
          , ohlcvVolume = 500
          }
      ]

let events = ohlcvToEvents bars
result <- runBacktest cfg MyStrategy events
```

---

## Configuration reference

```haskell
data BacktestConfig = BacktestConfig
  { bcInitialBalances :: Map Coin Scientific
    -- ^ Starting wallet balances per token

  , bcFeeRate         :: Scientific
    -- ^ Fee charged on each fill (e.g. 0.001 = 0.1%)

  , bcSlippage        :: SlippageModel
    -- ^ NoSlippage | FixedBps n  (applied to market orders only)

  , bcRiskLimits      :: RiskLimits
    -- ^ Same risk guard as live engine (max order size, daily volume, etc.)
  }
```

---

## Order matching rules

| Order type | Filled when |
|---|---|
| **Market** | Immediately at the best available trade price, plus slippage |
| **Limit Buy** | A trade tick or order book best-ask ≤ limit price |
| **Limit Sell** | A trade tick or order book best-bid ≥ limit price |

Fill price is always the **limit price** (not the market price), matching
exchange behaviour for resting orders.

---

## Reading results

```haskell
data BacktestResult = BacktestResult
  { brFills      :: [SimFill]       -- every simulated fill in order
  , brFinalState :: SimState        -- final balances and open orders
  , brMetrics    :: BacktestMetrics
  }

data BacktestMetrics = BacktestMetrics
  { bmTotalPnl    :: Scientific               -- cumulative realised PnL
  , bmTotalFees   :: Scientific               -- total fees paid
  , bmTradeCount  :: Int                      -- number of fills
  , bmWinRate     :: Scientific               -- fraction of profitable sells
  , bmMaxDrawdown :: Scientific               -- peak-to-trough PnL drawdown
  , bmSharpeRatio :: Scientific               -- annualised Sharpe (252-day basis)
  , bmPnlCurve    :: [(UTCTime, Scientific)]  -- PnL over time
  , bmPerTradePnl :: [(Text, Scientific)]     -- per-sell-fill PnL
  }
```

PnL is calculated on **realised** trades only (FIFO cost basis on sells).
Unrealised inventory is not included.

---

## Running the example

```bash
cabal run backtest-grid
```

This runs the `GridStrategy` from `examples/BacktestGrid.hs` against 168 hours of synthetic sine-wave OHLCV data and prints a results summary.
