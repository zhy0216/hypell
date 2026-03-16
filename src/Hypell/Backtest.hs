module Hypell.Backtest
  ( -- * Runner
    runBacktest
    -- * Configuration
  , BacktestConfig(..)
  , SlippageModel(..)
    -- * Results
  , BacktestResult(..)
  , BacktestMetrics(..)
  , SimFill(..)
    -- * Simulation state
  , SimState(..)
  , SimBalance(..)
    -- * Data loading
  , OHLCVBar(..)
  , loadCsvTrades
  , loadJsonTrades
  , ohlcvToEvents
  , tradesToEvents
  ) where

import Hypell.Backtest.Runner (runBacktest)
import Hypell.Backtest.Types
import Hypell.Backtest.DataLoader
