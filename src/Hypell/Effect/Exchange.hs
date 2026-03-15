module Hypell.Effect.Exchange
  ( Exchange(..)
  , placeOrder
  , cancelOrder
  , cancelAll
  , getOpenOrders
  ) where

import Effectful
import Effectful.TH (makeEffect)
import Hypell.Types

data Exchange :: Effect where
  PlaceOrder    :: OrderRequest -> Exchange m OrderResponse
  CancelOrder   :: CancelRequest -> Exchange m CancelResponse
  CancelAll     :: Exchange m ()
  GetOpenOrders :: Exchange m [Order]

makeEffect ''Exchange
