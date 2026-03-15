module Hypell.Api.Signing
  ( SignedRequest(..)
  , signRequest
  , makeNonce
  ) where

import Crypto.Hash (hashWith, Keccak_256(..))
import Data.Aeson (Value, object, (.=), encode)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Word (Word64)

data SignedRequest = SignedRequest
  { srAction    :: Value
  , srNonce     :: Word64
  , srSignature :: Value
  } deriving stock (Show)

makeNonce :: IO Word64
makeNonce = do
  t <- getPOSIXTime
  pure $ round (t * 1000)

-- Placeholder: actual EIP-712 signing requires structured type hashing.
-- This will be refined when testing against Hyperliquid testnet.
signRequest :: ByteString -> Value -> Word64 -> IO SignedRequest
signRequest _privateKey action nonce = do
  -- TODO: Implement EIP-712 typed data hashing and secp256k1 signing
  -- For now, use Keccak-256 of the action payload as a compilation smoke test.
  -- show produces a String representation of the Digest; the real implementation
  -- will use proper binary operations via secp256k1.
  let _actionHash = show (hashWith Keccak_256 (BL.toStrict (encode action)))
      _payload    = BS.empty  -- placeholder for typed-data hash
  let sig = object ["r" .= ("" :: Text), "s" .= ("" :: Text), "v" .= (27 :: Int)]
  pure SignedRequest
    { srAction    = action
    , srNonce     = nonce
    , srSignature = sig
    }
