module Test.Hypell.TypesTest (tests) where

import Data.Aeson (FromJSON, ToJSON, decode, encode)
import qualified Data.Map.Strict as Map
import Data.Time (UTCTime(..), fromGregorian, secondsToDiffTime)
import Test.Tasty
import Test.Tasty.HUnit

import Hypell.Types

-- A fixed time for deterministic tests
fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2025 1 15) (secondsToDiffTime 43200)

-- | Check JSON roundtrip: encode then decode should return the original value.
roundtrip :: (Eq a, Show a, ToJSON a, FromJSON a) => (a -> a -> Bool) -> a -> Bool
roundtrip eq' x = case decode (encode x) of
  Nothing -> False
  Just y  -> eq' x y

rt :: (Eq a, Show a, ToJSON a, FromJSON a) => a -> Bool
rt = roundtrip (==)

tests :: TestTree
tests = testGroup "Hypell.Types JSON"
  [ testGroup "Side"
      [ testCase "Buy encodes to B" $
          encode Buy @?= "\"B\""
      , testCase "Sell encodes to A" $
          encode Sell @?= "\"A\""
      , testCase "roundtrip Buy"  $ assertBool "" (rt Buy)
      , testCase "roundtrip Sell" $ assertBool "" (rt Sell)
      ]
  , testGroup "TimeInForce"
      [ testCase "roundtrip GTC" $ assertBool "" (rt GTC)
      , testCase "roundtrip IOC" $ assertBool "" (rt IOC)
      , testCase "roundtrip ALO" $ assertBool "" (rt ALO)
      ]
  , testGroup "OrderType"
      [ testCase "roundtrip Market" $ assertBool "" (rt Market)
      , testCase "roundtrip Limit" $ assertBool "" (rt (Limit 100.5 GTC))
      ]
  , testGroup "OrderStatus"
      [ testCase "roundtrip all statuses" $ do
          assertBool "Pending" (rt Pending)
          assertBool "Open" (rt Open)
          assertBool "PartiallyFilled" (rt PartiallyFilled)
          assertBool "Filled" (rt Filled)
          assertBool "Cancelled" (rt Cancelled)
          assertBool "Rejected" (rt Rejected)
      ]
  , testGroup "Coin"
      [ testCase "roundtrip" $ assertBool "" (rt (Coin "HYPE"))
      , testCase "as JSON key" $ do
          let m = Map.singleton (Coin "BTC") (42 :: Int)
          assertBool "" (decode (encode m) == Just m)
      ]
  , testGroup "OrderRequest"
      [ testCase "roundtrip" $ do
          let req = OrderRequest
                { orCoin = Coin "HYPE"
                , orSide = Buy
                , orSize = 10.5
                , orOrderType = Limit 25.0 GTC
                , orClientId = Just "my-order-1"
                }
          assertBool "" (rt req)
      , testCase "roundtrip without clientId" $ do
          let req = OrderRequest
                { orCoin = Coin "PURR"
                , orSide = Sell
                , orSize = 100
                , orOrderType = Market
                , orClientId = Nothing
                }
          assertBool "" (rt req)
      ]
  , testGroup "OrderResponse"
      [ testCase "roundtrip" $ assertBool "" (rt (OrderResponse "ok" (Just 12345)))
      , testCase "roundtrip no orderId" $ assertBool "" (rt (OrderResponse "error" Nothing))
      ]
  , testGroup "CancelRequest"
      [ testCase "roundtrip" $ assertBool "" (rt (CancelRequest (Coin "HYPE") 42))
      ]
  , testGroup "CancelResponse"
      [ testCase "roundtrip" $ assertBool "" (rt (CancelResponse "success"))
      ]
  , testGroup "Order"
      [ testCase "roundtrip" $ do
          let o = Order
                { orderId = 999
                , orderCoin = Coin "HYPE"
                , orderSide = Buy
                , orderSize = 50
                , orderFilled = 25
                , orderPrice = Just 30.0
                , orderStatus = PartiallyFilled
                , orderClientId = Just "c1"
                , orderTime = fixedTime
                }
          assertBool "" (rt o)
      ]
  , testGroup "OrderBook"
      [ testCase "roundtrip" $ do
          let ob = OrderBook
                { obBids = [(100.0, 10.0), (99.5, 20.0)]
                , obAsks = [(100.5, 5.0), (101.0, 15.0)]
                , obTime = fixedTime
                }
          assertBool "" (rt ob)
      ]
  , testGroup "Trade"
      [ testCase "roundtrip" $ do
          let t = Trade (Coin "HYPE") Buy 100.0 5.0 fixedTime
          assertBool "" (rt t)
      ]
  , testGroup "SpotAssetCtx"
      [ testCase "roundtrip" $ do
          let ctx = SpotAssetCtx 25.5 (Just 25.4) 24.0 1000000 500000
          assertBool "" (rt ctx)
      , testCase "roundtrip without midPrice" $ do
          let ctx = SpotAssetCtx 25.5 Nothing 24.0 1000000 500000
          assertBool "" (rt ctx)
      ]
  , testGroup "SpotMeta"
      [ testCase "roundtrip" $ do
          let meta = SpotMeta
                { smTokens = [TokenInfo "HYPE" 0 "0xhype", TokenInfo "USDC" 1 "0xusdc"]
                , smPairs  = [SpotPair "HYPE/USDC" (0, 1) 0 True]
                }
          assertBool "" (rt meta)
      ]
  , testGroup "TokenBalance"
      [ testCase "roundtrip" $ assertBool "" (rt (TokenBalance (Coin "USDC") 10000 500))
      ]
  , testGroup "UserTrade"
      [ testCase "roundtrip" $ do
          let ut = UserTrade (Coin "HYPE") Buy 25.0 10.0 0.025 fixedTime 42
          assertBool "" (rt ut)
      ]
  , testGroup "RiskLimits"
      [ testCase "roundtrip" $ do
          let rl = RiskLimits
                { rlMaxOrderSize = 1000
                , rlMaxDailyVolume = 50000
                , rlCooldownMs = 500
                , rlMaxPositionSize = Map.fromList [(Coin "HYPE/USDC", 5000)]
                }
          assertBool "" (rt rl)
      ]
  , testGroup "RiskResult"
      [ testCase "roundtrip Allow" $ assertBool "" (rt RiskAllow)
      , testCase "roundtrip Reject" $ assertBool "" (rt (RiskReject "too large"))
      ]
  , testGroup "TWAPParams"
      [ testCase "roundtrip" $ do
          let p = TWAPParams (Coin "HYPE") Buy 1000 300 10 (Just 25.0)
          assertBool "" (rt p)
      ]
  , testGroup "IcebergParams"
      [ testCase "roundtrip" $ do
          let p = IcebergParams (Coin "HYPE") Sell 5000 100 24.5
          assertBool "" (rt p)
      ]
  , testGroup "AlgoParams"
      [ testCase "roundtrip TWAP" $ do
          let p = AlgoTWAP (TWAPParams (Coin "HYPE") Buy 1000 300 10 Nothing)
          assertBool "" (rt p)
      , testCase "roundtrip Iceberg" $ do
          let p = AlgoIceberg (IcebergParams (Coin "PURR") Sell 5000 100 24.5)
          assertBool "" (rt p)
      ]
  , testGroup "AlgoStatus"
      [ testCase "roundtrip Running"  $ assertBool "" (rt (AlgoRunning 500))
      , testCase "roundtrip Complete" $ assertBool "" (rt (AlgoComplete 1000 25.3))
      , testCase "roundtrip Stopped"  $ assertBool "" (rt (AlgoStopped "user cancelled" 750))
      ]
  , testGroup "LogLevel"
      [ testCase "roundtrip all" $ do
          assertBool "Debug" (rt Debug)
          assertBool "Info"  (rt Info)
          assertBool "Warn"  (rt Warn)
          assertBool "Error" (rt Error)
      ]
  , testGroup "Network"
      [ testCase "roundtrip" $ do
          assertBool "Mainnet" (rt Mainnet)
          assertBool "Testnet" (rt Testnet)
      ]
  , testGroup "EngineConfig"
      [ testCase "roundtrip" $ assertBool "" (rt (EngineConfig 4096 2000 1000))
      ]
  , testGroup "DailyStats"
      [ testCase "roundtrip" $ assertBool "" (rt (DailyStats 100000 42 250.5))
      ]
  ]
