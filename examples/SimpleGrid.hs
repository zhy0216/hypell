module Main where

import Data.Map.Strict qualified as Map
import Data.Scientific (Scientific, scientific)
import qualified Data.Text as T
import Hypell.Types
import Hypell.Strategy
import Hypell.Effect.Log (log)
import Hypell.Effect.Account (getBalances)
import Prelude hiding (log)

data GridStrategy = GridStrategy
  { gsGridLevels  :: [(Scientific, Scientific)]  -- (price, size)
  , gsActiveOrders :: Map.Map Scientific OrderId
  } deriving stock (Show)

instance Strategy GridStrategy where
  strategyName _ = "simple-grid"

  initStrategy s = do
    log "Grid strategy initialized"
    pure s

  onEvent s (FillEvent _ut) = do
    log "Fill event received"
    pure (s, [])

  onEvent s TimerTick = do
    bals <- getBalances
    log $ "Heartbeat, balances: " <> T.pack (show (length bals))
    pure (s, [])

  onEvent s _ = pure (s, [])

  onShutdown _ = do
    log "Grid strategy shutting down"
    pure ()

main :: IO ()
main = do
  let strategy = GridStrategy
        { gsGridLevels   = [(scientific 24 0, scientific 10 0), (scientific 26 0, scientific 10 0)]
        , gsActiveOrders = Map.empty
        }
  putStrLn $ "Strategy: " <> show (strategyName strategy)
  putStrLn "TODO: integrate with runEngine"
