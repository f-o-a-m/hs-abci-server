module Nameservice.Modules.Nameservice

  (
    -- * Module
    NameserviceM
  , nameserviceModule
  , module           Nameservice.Modules.Nameservice.Keeper
  , module           Nameservice.Modules.Nameservice.Messages
  , module           Nameservice.Modules.Nameservice.Query
  , module           Nameservice.Modules.Nameservice.Router
  , module           Nameservice.Modules.Nameservice.Types


  ) where

import           Data.Proxy
import           Nameservice.Modules.Nameservice.Keeper   hiding (storeKey)
import           Nameservice.Modules.Nameservice.Messages
import           Nameservice.Modules.Nameservice.Query
import           Nameservice.Modules.Nameservice.Router
import           Nameservice.Modules.Nameservice.Types
import           Polysemy                                 (Members)
import           Tendermint.SDK.Application               (Module (..))
import           Tendermint.SDK.BaseApp                   (BaseEffs,
                                                           DefaultCheckTx (..),
                                                           TxEffs)
import           Tendermint.SDK.Modules.Auth              (AuthEffs)
import           Tendermint.SDK.Modules.Bank              (BankEffs)

type NameserviceM r =
  Module "nameservice" MessageApi MessageApi QueryApi NameserviceEffs r

nameserviceModule
  :: Members BaseEffs r
  => Members AuthEffs r
  => Members TxEffs r
  => Members BankEffs r
  => Members NameserviceEffs r
  => NameserviceM r
nameserviceModule = Module
  { moduleTxDeliverer = messageHandlers
  , moduleTxChecker = defaultCheckTx (Proxy :: Proxy MessageApi) (Proxy :: Proxy r)
  , moduleQuerier = querier
  , moduleEval = eval
  }
