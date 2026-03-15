module Hypell.Api.Rest
  ( RestClient(..)
  , newRestClient
  , postInfo
  , postExchange
  ) where

import Data.Aeson (Value, encode, eitherDecode, object, (.=))
import Data.ByteString (ByteString)
import Data.Text (Text)
import qualified Data.Text as T
import Network.HTTP.Client
  ( Manager, newManager, parseRequest, httpLbs
  , method, requestBody, requestHeaders, responseBody
  , RequestBody(RequestBodyLBS)
  )
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Hypell.Api.Signing (SignedRequest(..), signRequest, makeNonce)

data RestClient = RestClient
  { rcManager :: Manager
  , rcBaseUrl :: String
  , rcPrivKey :: ByteString  -- strict ByteString
  }

newRestClient :: Text -> ByteString -> IO RestClient
newRestClient baseUrl privKey = do
  mgr <- newManager tlsManagerSettings
  pure RestClient
    { rcManager = mgr
    , rcBaseUrl = T.unpack baseUrl
    , rcPrivKey = privKey
    }

-- POST /info: unsigned query
postInfo :: RestClient -> Value -> IO (Either String Value)
postInfo rc payload = do
  req <- parseRequest (rcBaseUrl rc <> "/info")
  let req' = req
        { method = "POST"
        , requestBody = RequestBodyLBS (encode payload)
        , requestHeaders = [("Content-Type", "application/json")]
        }
  resp <- httpLbs req' (rcManager rc)
  pure $ eitherDecode (responseBody resp)

-- POST /exchange: signed action
postExchange :: RestClient -> Value -> IO (Either String Value)
postExchange rc action = do
  nonce <- makeNonce
  signed <- signRequest (rcPrivKey rc) action nonce
  let payload = object
        [ "action"    .= srAction signed
        , "nonce"     .= srNonce signed
        , "signature" .= srSignature signed
        ]
  req <- parseRequest (rcBaseUrl rc <> "/exchange")
  let req' = req
        { method = "POST"
        , requestBody = RequestBodyLBS (encode payload)
        , requestHeaders = [("Content-Type", "application/json")]
        }
  resp <- httpLbs req' (rcManager rc)
  pure $ eitherDecode (responseBody resp)
