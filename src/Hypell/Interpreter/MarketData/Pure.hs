module Hypell.Interpreter.MarketData.Pure
  ( MockMarketDataState(..)
  , emptyMockMarketData
  , runMarketDataPure
  ) where

import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local
import Hypell.Types
import Hypell.Effect.MarketData

data MockMarketDataState = MockMarketDataState
  { mmdSpotMeta      :: SpotMeta
  , mmdAssetCtxs     :: [SpotAssetCtx]
  , mmdOrderBooks    :: [(Coin, OrderBook)]
  } deriving stock (Eq, Show)

emptyMockMarketData :: MockMarketDataState
emptyMockMarketData = MockMarketDataState
  (SpotMeta [] []) [] []

runMarketDataPure
  :: State MockMarketDataState :> es
  => Eff (MarketData : es) a -> Eff es a
runMarketDataPure = interpret_ $ \case
  GetSpotMeta      -> gets mmdSpotMeta
  GetSpotAssetCtxs -> gets mmdAssetCtxs
  GetOrderBook c   -> do
    obs <- gets mmdOrderBooks
    case lookup c obs of
      Just ob -> pure ob
      Nothing -> pure $ OrderBook [] [] (read "2026-01-01 00:00:00 UTC")
  SubscribeTrades _ -> pure ()
