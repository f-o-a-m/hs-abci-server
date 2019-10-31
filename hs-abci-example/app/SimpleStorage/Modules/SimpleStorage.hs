{-# LANGUAGE TemplateHaskell #-}

module SimpleStorage.Modules.SimpleStorage
  (
  -- * Component
    SimpleStorage
  , putCount
  , getCount

  , Api
  , server
  , eval
  , initialize

  -- * Store
  , CountStoreContents

  -- * Types
  , Count(..)
  , CountKey(..)

  -- * Events
  , CountSet

  ) where

import           Control.Lens                (from, iso, (^.))
import           Crypto.Hash                 (SHA256 (..), hashWith)
import qualified Data.Binary                 as Binary
import           Data.ByteArray              (convert)
import           Data.ByteArray.Base64String (fromBytes, toBytes)
import           Data.ByteString             (ByteString)
import           Data.Int                    (Int32)
import           Data.Maybe                  (fromJust)
import           Data.Proxy
import           Data.String.Conversions     (cs)
import           Polysemy
import           Polysemy.Output
import           Servant.API                 ((:>))
import           Tendermint.SDK.Codec
import qualified Tendermint.SDK.Events       as Events
import           Tendermint.SDK.Module
import           Tendermint.SDK.Router
import           Tendermint.SDK.Store
import           Tendermint.SDK.StoreQueries

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

newtype Count = Count Int32 deriving (Eq, Show)

data CountKey = CountKey

instance HasCodec Count where
    encode (Count c) = cs . Binary.encode $ c
    decode = Right . Count . Binary.decode . cs

instance HasKey Count where
    type Key Count = CountKey
    rawKey = iso (\_ -> cs countKey) (const CountKey)
      where
        countKey :: ByteString
        countKey = convert . hashWith SHA256 . cs @_ @ByteString $ ("count" :: String)

instance FromQueryData CountKey where
  fromQueryData bs = Right (toBytes bs ^. from rawKey)

instance EncodeQueryResult Count where
  encodeQueryResult = fromBytes . encode

instance Queryable Count where
  type Name Count = "count"

data SimpleStorage m a where
    PutCount :: Count -> SimpleStorage m ()
    GetCount :: SimpleStorage m Count

makeSem ''SimpleStorage

type CountStoreContents = '[Count]

data CountSet = CountSet Count deriving (Show)

instance HasCodec CountSet where
  encode (CountSet c) = encode $ c
  decode = fmap CountSet . decode

instance Events.IsEvent CountSet where
  type EventName CountSet = "count_set"


--------------------------------------------------------------------------------
-- SimpleStorage Module
--------------------------------------------------------------------------------

eval
  :: forall r.
     BaseApp r
  => forall a. (Sem (SimpleStorage ': r) a -> Sem r a)
eval = interpret (\case
  PutCount count -> do
    put CountKey count
    Events.emit $ CountSet count

  GetCount -> fromJust <$> get (undefined :: Root) CountKey
  )

initialize
  :: BaseApp r
  => Member (Output Events.Event) r
  => Sem r ()
initialize = eval $ do
  putCount (Count 0)

type Api = "count" :> QueryApi CountStoreContents

server :: Member RawStore r => RouteT Api (Sem r)
server = storeQueryHandlers (Proxy :: Proxy CountStoreContents) (Proxy :: Proxy (Sem r))
