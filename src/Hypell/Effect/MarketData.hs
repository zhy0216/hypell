module Hypell.Effect.MarketData
  ( MarketData(..)
  , getSpotMeta
  , getSpotAssetCtxs
  , getOrderBook
  , subscribeTrades
  ) where

import Effectful
import Effectful.TH (makeEffect)
import Hypell.Types

data MarketData :: Effect where
  GetSpotMeta      :: MarketData m SpotMeta
  GetSpotAssetCtxs :: MarketData m [SpotAssetCtx]
  GetOrderBook     :: Coin -> MarketData m OrderBook
  SubscribeTrades  :: Coin -> MarketData m ()

makeEffect ''MarketData
