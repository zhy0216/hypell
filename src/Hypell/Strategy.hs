module Hypell.Strategy
  ( Strategy(..)
  ) where

import Data.Text (Text)
import Effectful
import Hypell.Types
import Hypell.Effect.Log (Log)
import Hypell.Effect.MarketData (MarketData)
import Hypell.Effect.Account (Account)
import Hypell.Effect.OrderManager (OrderManager)

class Strategy s where
  strategyName :: s -> Text

  initStrategy
    :: (MarketData :> es, Account :> es, Log :> es)
    => s -> Eff es s

  onEvent
    :: (MarketData :> es, Account :> es, Log :> es)
    => s -> MarketEvent -> Eff es (s, [TradeAction])

  onShutdown
    :: (OrderManager :> es, Log :> es)
    => s -> Eff es ()
