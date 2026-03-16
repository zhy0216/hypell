module Main where

import Data.Map.Strict qualified as Map
import Data.Scientific (Scientific, scientific, fromFloatDigits)
import Data.Text qualified as T
import Data.Time.Clock (addUTCTime, UTCTime(..))
import Data.Time.Calendar (fromGregorian)
import Prelude hiding (log)
import Hypell hiding (PlaceOrder)
import Hypell.Types (TradeAction(..))

-- ---------------------------------------------------------------------------
-- Grid strategy (same as SimpleGrid, works for both live and backtest)
-- ---------------------------------------------------------------------------

data GridStrategy = GridStrategy
  { gsGridLevels   :: [(Scientific, Scientific)]
  , gsActiveOrders :: Map.Map Scientific OrderId
  } deriving stock (Show)

instance Strategy GridStrategy where
  strategyName _ = "backtest-grid"

  initStrategy s = do
    log "Grid strategy initialised for backtest"
    pure s

  onEvent s (FillEvent ut) = do
    log $ "Fill: " <> T.pack (show (utSide ut))
           <> " " <> T.pack (show (utSize ut))
           <> " @ " <> T.pack (show (utPrice ut))
    pure (s, [])

  onEvent s (TradeUpdate (t:_)) = do
    let px = trdPrice t
        orders = concatMap (levelOrders (trdCoin t) px) (gsGridLevels s)
    pure (s, orders)

  onEvent s _ = pure (s, [])

  onShutdown _ = pure ()

levelOrders :: Coin -> Scientific -> (Scientific, Scientific) -> [TradeAction]
levelOrders coin currentPx (gridPx, size)
  | gridPx < currentPx =
      [ PlaceOrder OrderRequest
          { orCoin      = coin
          , orSide      = Buy
          , orSize      = size
          , orOrderType = Limit gridPx GTC
          , orClientId  = Nothing
          }
      ]
  | otherwise = []

-- ---------------------------------------------------------------------------
-- Synthetic OHLCV data (sine-wave price around 100)
-- ---------------------------------------------------------------------------

syntheticBars :: [OHLCVBar]
syntheticBars =
  [ let s = fromFloatDigits (sin (fromIntegral i * (0.3 :: Double)))
    in OHLCVBar
      { ohlcvCoin   = Coin "ETH"
      , ohlcvTime   = addUTCTime (fromIntegral (i * 3600 :: Int)) epoch
      , ohlcvOpen   = 100 + 5 * s
      , ohlcvHigh   = 100 + 5 * s + 1
      , ohlcvLow    = 100 + 5 * s - 1
      , ohlcvClose  = 100 + 5 * fromFloatDigits (sin (fromIntegral (i+1) * (0.3 :: Double)))
      , ohlcvVolume = 100
      }
  | i <- [0..167 :: Int]
  ]
  where
    epoch = UTCTime (fromGregorian 2025 1 1) 0

-- ---------------------------------------------------------------------------
-- Backtest configuration
-- ---------------------------------------------------------------------------

backtestCfg :: BacktestConfig
backtestCfg = BacktestConfig
  { bcInitialBalances = Map.fromList
      [ (Coin "USDC", 10000)
      , (Coin "ETH",  0)
      ]
  , bcFeeRate  = 0.001
  , bcSlippage = NoSlippage
  , bcRiskLimits = RiskLimits
      { rlMaxOrderSize    = 1000
      , rlMaxDailyVolume  = 100000
      , rlCooldownMs      = 0
      , rlMaxPositionSize = Map.empty
      }
  }

strategy :: GridStrategy
strategy = GridStrategy
  { gsGridLevels   = [ (scientific 95 0, scientific 10 0)
                     , (scientific 97 0, scientific 10 0)
                     , (scientific 99 0, scientific 10 0)
                     ]
  , gsActiveOrders = Map.empty
  }

-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------

main :: IO ()
main = do
  let events = ohlcvToEvents syntheticBars
  putStrLn $ "Running backtest on " <> show (length events) <> " events..."

  result <- runBacktest backtestCfg strategy events

  let m = brMetrics result
  putStrLn ""
  putStrLn "=== Backtest Results ==="
  putStrLn $ "Total fills:    " <> show (length (brFills result))
  putStrLn $ "Total PnL:      " <> show (bmTotalPnl m)
  putStrLn $ "Total fees:     " <> show (bmTotalFees m)
  putStrLn $ "Trade count:    " <> show (bmTradeCount m)
  putStrLn $ "Win rate:       " <> show (bmWinRate m)
  putStrLn $ "Max drawdown:   " <> show (bmMaxDrawdown m)
  putStrLn $ "Sharpe ratio:   " <> show (bmSharpeRatio m)
