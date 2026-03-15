module Test.Hypell.AlgoTest (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Data.Scientific (scientific)
import Hypell.Types
import Hypell.Algo.TWAP (computeSlices)
import Hypell.Algo.Iceberg (computeIcebergOrder)

tests :: TestTree
tests = testGroup "Algo"
  [ testGroup "TWAP"
    [ testCase "splits evenly" $ do
        let params = TWAPParams
              { twapCoin = Coin "HYPE/USDC", twapSide = Buy
              , twapTotalSize = scientific 100 0, twapNumSlices = 4
              , twapDurationSecs = 60, twapLimitPrice = Nothing
              }
        let slices = computeSlices params
        length slices @?= 4
        all (== scientific 25 0) slices @?= True

    , testCase "handles remainder" $ do
        let params = TWAPParams
              { twapCoin = Coin "HYPE/USDC", twapSide = Buy
              , twapTotalSize = scientific 100 0, twapNumSlices = 3
              , twapDurationSecs = 60, twapLimitPrice = Nothing
              }
        let slices = computeSlices params
        length slices @?= 3
        sum slices @?= scientific 100 0
    ]

  , testGroup "Iceberg"
    [ testCase "visible size capped at total remaining" $ do
        let params = IcebergParams
              { iceCoin = Coin "HYPE/USDC", iceSide = Buy
              , iceTotalSize = scientific 30 0
              , iceShowSize = scientific 100 0
              , iceLimitPrice = scientific 25 0
              }
        let order = computeIcebergOrder params 0
        orSize order @?= scientific 30 0  -- capped at remaining

    , testCase "normal visible slice" $ do
        let params = IcebergParams
              { iceCoin = Coin "HYPE/USDC", iceSide = Buy
              , iceTotalSize = scientific 1000 0
              , iceShowSize = scientific 100 0
              , iceLimitPrice = scientific 25 0
              }
        let order = computeIcebergOrder params 0
        orSize order @?= scientific 100 0
    ]
  ]
