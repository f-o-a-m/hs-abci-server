{-# LANGUAGE UndecidableInstances #-}

module Tendermint.SDK.Query.StoreClient
  ( RunClient(..)
  , HasClient(..)
  , ClientResponse(..)
  ) where

import           Control.Lens                         (to, (^.))
import qualified Data.ByteArray.Base64String          as Base64
import           Data.Proxy
import           Data.String.Conversions              (cs)
import           GHC.TypeLits                         (KnownSymbol, symbolVal)
import qualified Network.ABCI.Types.Messages.Request  as Req
import qualified Network.ABCI.Types.Messages.Response as Resp
import           Servant.API                          ((:<|>) (..), (:>))
import           Tendermint.SDK.Query.Types           (Leaf, QA, QueryArgs (..),
                                                       Queryable (..))
import           Tendermint.SDK.Store                 (RawKey (..))

class Monad m => RunClient m where
    -- | How to make a request.
    runQuery :: Req.Query -> m Resp.Query

class HasClient m layout where

    type ClientT (m :: * -> *) layout :: *
    genClient :: Proxy m -> Proxy layout -> Req.Query -> ClientT m layout

instance (HasClient m a, HasClient m b) => HasClient m (a :<|> b) where
    type ClientT m (a :<|> b) = ClientT m a :<|> ClientT m b
    genClient pm _ q = genClient pm (Proxy @a) q :<|> genClient pm (Proxy @b) q

instance (KnownSymbol path, HasClient m a) => HasClient m (path :> a) where
    type ClientT m (path :> a) = ClientT m a
    genClient pm _ q = genClient pm (Proxy @a)
      q {Req.queryPath = Req.queryPath q <> "/" <> cs (symbolVal (Proxy @path))}

instance (RawKey k, HasClient m a) => HasClient m (QA k :> a) where
    type ClientT m (QA k :> a) = QueryArgs k -> ClientT m a
    genClient pm _ q QueryArgs{..} = genClient pm (Proxy @a)
      q { Req.queryData = queryArgsData ^. rawKey . to Base64.fromBytes
        , Req.queryHeight = queryArgsHeight
        , Req.queryProve = queryArgsProve
        }

data ClientResponse a = ClientResponse
  { clientResponseData :: a
  , clientResponseRaw  :: Resp.Query
  }

instance (RunClient m, Queryable a, name ~  Name a, KnownSymbol name ) => HasClient m (Leaf a) where
    type ClientT m (Leaf a) = m (ClientResponse a)
    genClient _ _ q =
        let leaf = symbolVal (Proxy @(Name a))
        in do
            r@Resp.Query{..} <- runQuery q { Req.queryPath = Req.queryPath q <> "/" <> cs leaf }
            return $ case decodeQueryResult queryValue of
                Left err -> error $ "Impossible parse error: " <> cs err
                Right a  -> ClientResponse a r
