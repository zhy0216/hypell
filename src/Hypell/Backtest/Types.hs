module Hypell.Backtest.Types
  ( -- * Configuration
    BacktestConfig(..)
  , SlippageModel(..)
    -- * Simulation state
  , SimBalance(..)
  , SimState(..)
  , initialSimState
    -- * Fill record
  , SimFill(..)
    -- * Results
  , BacktestResult(..)
  , BacktestMetrics(..)
  ) where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Scientific (Scientific)
import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)
import Hypell.Types

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

data SlippageModel
  = NoSlippage
  | FixedBps Scientific
  deriving stock (Eq, Show, Generic)

data BacktestConfig = BacktestConfig
  { bcInitialBalances :: Map Coin Scientific
  , bcFeeRate         :: Scientific
  , bcSlippage        :: SlippageModel
  , bcRiskLimits      :: RiskLimits
  } deriving stock (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Simulation state
-- ---------------------------------------------------------------------------

data SimBalance = SimBalance
  { sbTotal     :: Scientific
  , sbAvailable :: Scientific
  } deriving stock (Eq, Show, Generic)

data SimState = SimState
  { ssBalances    :: Map Coin SimBalance
  , ssOpenOrders  :: Map OrderId (OrderRequest, Scientific)
  , ssNextOrderId :: OrderId
  , ssDailyStats  :: DailyStats
  , ssFills       :: [SimFill]
  } deriving stock (Eq, Show, Generic)

initialSimState :: BacktestConfig -> SimState
initialSimState cfg = SimState
  { ssBalances    = Map.map (\a -> SimBalance a a) (bcInitialBalances cfg)
  , ssOpenOrders  = Map.empty
  , ssNextOrderId = 1
  , ssDailyStats  = DailyStats 0 0 0
  , ssFills       = []
  }

-- ---------------------------------------------------------------------------
-- Fill record
-- ---------------------------------------------------------------------------

data SimFill = SimFill
  { sfOrderId :: OrderId
  , sfCoin    :: Coin
  , sfSide    :: Side
  , sfPrice   :: Scientific
  , sfSize    :: Scientific
  , sfFee     :: Scientific
  , sfTime    :: UTCTime
  } deriving stock (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Result types
-- ---------------------------------------------------------------------------

data BacktestResult = BacktestResult
  { brFills       :: [SimFill]
  , brFinalState  :: SimState
  , brMetrics     :: BacktestMetrics
  } deriving stock (Eq, Show, Generic)

data BacktestMetrics = BacktestMetrics
  { bmTotalPnl      :: Scientific
  , bmTotalFees     :: Scientific
  , bmTradeCount    :: Int
  , bmWinRate       :: Scientific
  , bmMaxDrawdown   :: Scientific
  , bmSharpeRatio   :: Scientific
  , bmPnlCurve      :: [(UTCTime, Scientific)]
  , bmPerTradePnl   :: [(Text, Scientific)]
  } deriving stock (Eq, Show, Generic)
