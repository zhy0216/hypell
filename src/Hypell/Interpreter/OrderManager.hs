module Hypell.Interpreter.OrderManager
  ( runOrderManagerPure
  , runOrderManagerIO
  , orderFromManaged
  ) where

import Control.Concurrent.STM
import Control.Monad (void)
import Data.Map.Strict qualified as Map
import Data.Time.Clock (getCurrentTime)
import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local
import Hypell.Types hiding (PlaceOrder, CancelOrder, CancelAll)
import Hypell.Effect.Exchange (Exchange, placeOrder, cancelOrder)
import Hypell.Effect.OrderManager

runOrderManagerPure
  :: (Exchange :> es, State (Map.Map OrderId ManagedOrder) :> es)
  => Eff (OrderManager : es) a -> Eff es a
runOrderManagerPure = interpret_ $ \case
  SubmitOrder req -> do
    resp <- placeOrder req
    let oid = maybe 0 id (orspOrderId resp)
        status = case orspStatus resp of
          "resting" -> Open
          "filled"  -> Filled
          _         -> Rejected
    let mo = ManagedOrder oid req status (read "2026-01-01 00:00:00 UTC")
    modify $ Map.insert oid mo
    pure mo
  TrackOrder oid -> do
    orders <- get @(Map.Map OrderId ManagedOrder)
    pure $ maybe Cancelled moStatus (Map.lookup oid orders)
  CancelManaged oid ->
    modify $ Map.delete @OrderId @ManagedOrder oid

-- | IO interpreter for OrderManager, backed by a TVar of orders
-- and delegating to the Exchange effect for actual order placement/cancellation.
runOrderManagerIO
  :: (Exchange :> es, IOE :> es)
  => TVar (Map.Map OrderId Order)
  -> Eff (OrderManager : es) a -> Eff es a
runOrderManagerIO ordersVar = interpret_ $ \case
  SubmitOrder req -> do
    resp <- placeOrder req
    now  <- liftIO getCurrentTime
    let oid = maybe 0 id (orspOrderId resp)
        status = case orspStatus resp of
          "resting" -> Open
          "filled"  -> Filled
          _         -> Rejected
    let mo = ManagedOrder oid req status now
    liftIO $ atomically $ modifyTVar' ordersVar (Map.insert oid (orderFromManaged mo))
    pure mo
  TrackOrder oid -> do
    orders <- liftIO $ atomically $ readTVar ordersVar
    pure $ maybe Cancelled orderStatus (Map.lookup oid orders)
  CancelManaged oid -> do
    void $ cancelOrder (CancelRequest (Coin "") oid)
    liftIO $ atomically $ modifyTVar' ordersVar (Map.delete oid)

-- | Convert a ManagedOrder to an Order for TVar storage.
orderFromManaged :: ManagedOrder -> Order
orderFromManaged mo = Order
  { orderId       = moId mo
  , orderCoin     = orCoin (moRequest mo)
  , orderSide     = orSide (moRequest mo)
  , orderSize     = orSize (moRequest mo)
  , orderFilled   = 0
  , orderPrice    = Nothing
  , orderStatus   = moStatus mo
  , orderClientId = orClientId (moRequest mo)
  , orderTime     = moCreatedAt mo
  }
