module Hypell.Interpreter.Exchange.Pure
  ( MockExchangeState(..)
  , emptyMockExchange
  , runExchangePure
  ) where

import Data.Map.Strict qualified as Map
import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local
import Hypell.Types hiding (PlaceOrder, CancelOrder, CancelAll)
import Hypell.Effect.Exchange

data MockExchangeState = MockExchangeState
  { mesOrders    :: Map.Map OrderId OrderRequest
  , mesNextId    :: OrderId
  , mesFillQueue :: [OrderResponse]
  } deriving stock (Eq, Show)

emptyMockExchange :: MockExchangeState
emptyMockExchange = MockExchangeState Map.empty 1 []

runExchangePure
  :: State MockExchangeState :> es
  => Eff (Exchange : es) a -> Eff es a
runExchangePure = interpret_ $ \case
  PlaceOrder req -> do
    st <- get
    let oid = mesNextId st
    put st { mesOrders = Map.insert oid req (mesOrders st)
           , mesNextId = oid + 1 }
    case mesFillQueue st of
      (r:rs) -> do
        modify $ \s -> s { mesFillQueue = rs }
        pure r
      [] -> pure $ OrderResponse "resting" (Just oid)
  CancelOrder _cr -> do
    modify $ \s -> s { mesOrders = Map.delete (crOrderId _cr) (mesOrders s) }
    pure $ CancelResponse "success"
  CancelAll -> modify $ \s -> s { mesOrders = Map.empty }
  GetOpenOrders -> pure []  -- simplified
