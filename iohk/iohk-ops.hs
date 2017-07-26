#!/usr/bin/env runhaskell
{-# LANGUAGE DataKinds, DeriveGeneric, GADTs, GeneralizedNewtypeDeriving, OverloadedStrings, RankNTypes, RecordWildCards, ScopedTypeVariables, StandaloneDeriving, TupleSections, ViewPatterns #-}
{-# OPTIONS_GHC -Wall -Wno-name-shadowing -Wno-missing-signatures -Wno-type-defaults -Wno-unused-imports -Wno-unticked-promoted-constructors #-}

import           Control.Monad                    (forM, forM_)
import           Control.Monad.Trans.AWS   hiding (IAM, send)
import           Control.Lens              hiding ()
import           Data.Char                        (toLower)
import           Data.List
import           Data.Maybe
import           Data.Monoid                      ((<>))
import qualified Data.HashMap.Lazy             as Map
import           Data.Optional                    (Optional)
import qualified Data.Text                     as T
import qualified Filesystem.Path.CurrentOS     as Path
import           Network.AWS               hiding () -- send
import           Network.AWS.Auth
import           Network.AWS.EC2           hiding (DeleteTag, Snapshot, Stop)
import           Network.AWS.IAM           hiding (Any)
import           System.IO                     as Sys
import qualified Text.Printf                   as T
import           Text.Read                        (readMaybe)
import           Turtle                    hiding (find, procs, shells)


-- * Local imports
import           NixOps                           (Branch(..), Commit(..), Environment(..), Deployment(..), Target(..)
                                                  ,Options(..), NixopsCmd(..), Project(..), URL(..)
                                                  ,showT, lowerShowT, errorT, cmd, incmd, projectURL, every)
import qualified NixOps                        as Ops

import qualified CardanoCSL                    as Cardano
import qualified Snapshot                      as Snapshot
import qualified Timewarp                      as Timewarp


-- * Elementary parsers
--
-- | Given a string, either return a constructor that being 'show'n case-insensitively matches the string,
--   or raise an error, explaining what went wrong.
diagReadCaseInsensitive :: (Bounded a, Enum a, Read a, Show a) => String -> Maybe a
diagReadCaseInsensitive str = diagRead $ toLower <$> str
  where mapping    = Map.fromList [ (toLower <$> show x, x) | x <- every ]
        diagRead x = Just $ flip fromMaybe (Map.lookup x mapping)
                     (errorT $ format ("Couldn't parse '"%s%"' as one of: "%s%"\n")
                                        (T.pack str) (T.pack $ intercalate ", " $ Map.keys mapping))

optReadLower :: (Bounded a, Enum a, Read a, Show a) => ArgName -> ShortName -> Optional HelpMessage -> Parser a
optReadLower = opt (diagReadCaseInsensitive . T.unpack)
argReadLower :: (Bounded a, Enum a, Read a, Show a) => ArgName -> Optional HelpMessage -> Parser a
argReadLower = arg (diagReadCaseInsensitive . T.unpack)

parserBranch :: Optional HelpMessage -> Parser Branch
parserBranch desc = Branch <$> argText "branch" desc

parserCommit :: Optional HelpMessage -> Parser Commit
parserCommit desc = Commit <$> argText "commit" desc

parserEnvironment :: Parser Environment
parserEnvironment = fromMaybe Ops.defaultEnvironment <$> optional (optReadLower "environment" 'e' $ pure $
                                                                   Turtle.HelpMessage $ "Environment: "
                                                                   <> T.intercalate ", " (lowerShowT <$> (every :: [Environment])) <> ".  Default: development")

parserTarget      :: Parser Target
parserTarget      = fromMaybe Ops.defaultTarget      <$> optional (optReadLower "target"      't' "Target: aws, all;  defaults to AWS")

parserProject     :: Parser Project
parserProject     = argReadLower "project" $ pure $ Turtle.HelpMessage ("Project to set version of: " <> T.intercalate ", " (lowerShowT <$> (every :: [Project])))

parserDeployment  :: Parser Deployment
parserDeployment  = argReadLower "DEPL" (pure $
                                         Turtle.HelpMessage $ "Deployment, one of: "
                                         <> T.intercalate ", " (lowerShowT <$> (every :: [Deployment])))
parserDeployments :: Parser [Deployment]
parserDeployments = (\(a, b, c, d) -> concat $ maybeToList <$> [a, b, c, d])
                    <$> ((,,,)
                         <$> (optional parserDeployment) <*> (optional parserDeployment) <*> (optional parserDeployment) <*> (optional parserDeployment))

parserDo :: Parser [Command Top]
parserDo = (\(a, b, c, d) -> concat $ maybeToList <$> [a, b, c, d])
           <$> ((,,,)
                 <$> (optional centralCommandParser) <*> (optional centralCommandParser) <*> (optional centralCommandParser) <*> (optional centralCommandParser))

newtype InstId  = InstId              Text   deriving (Eq, IsString, Show)
newtype InstTag = InstTag             Text   deriving (Eq, IsString, Show)
newtype AZ      = AZ      { fromAZ :: Text } deriving (Eq, IsString, Show)

parserInstId :: Optional HelpMessage -> Parser InstId
parserInstId  desc =  InstId <$> argText "INSTANCE-ID"  desc

parserInstTag :: Optional HelpMessage -> Parser InstTag
parserInstTag desc = InstTag <$> argText "INSTANCE-TAG" desc

-- | Sum to track assurance
data Go = Go | Ask | Dry
  deriving (Eq, Read, Show)

parserGo  :: Parser Go
parserGo  = argRead "GO" "How to proceed before critical action: Go (fully automated), Ask (for confirmation) or Dry (no go)"


-- * Central command
--
data Kind = Top | EC2' | IAM'
data Command a where

  -- * setup
  Template              :: { tNodeLimit   :: Integer
                           , tHere        :: Bool
                           , tFile        :: Maybe Turtle.FilePath
                           , tEnvironment :: Environment
                           , tTarget      :: Target
                           , tBranch      :: Branch
                           , tDeployments :: [Deployment]
                           } -> Command Top
  SetRev                :: Project -> Commit -> Command Top
  FakeKeys              :: Command Top

  -- * building
  Genesis               :: Command Top
  GenerateIPDHTMappings :: Command Top
  Build                 :: Deployment -> Command Top
  AMI                   :: Command Top

  -- * cluster lifecycle
  Nixops                :: NixopsCmd -> [Text] -> Command Top
  Do                    :: [Command Top] -> Command Top
  Create                :: Command Top
  Modify                :: Command Top
  Deploy                :: Bool -> Bool -> Command Top
  Destroy               :: Command Top
  Delete                :: Command Top
  FromScratch           :: Command Top
  Status                :: Command Top

  -- * AWS
  EC2Sub                :: Command EC2' -> Command Top
  Instances             :: Command EC2'
  InstInfo              :: InstId -> Command EC2'
  SetTag                :: InstId -> InstTag -> Text -> Command EC2'
  DeleteTag             :: InstId -> InstTag -> Command EC2'
  ListSnapshottable     :: Command EC2'
  Snapshot              :: Go -> Command EC2'

  IAMSub                :: Command IAM' -> Command Top
  Whoami                :: Command IAM'

  -- * live cluster ops
  CheckStatus           :: Command Top
  Start                 :: Command Top
  Stop                  :: Command Top
  -- FirewallBlock         :: { from :: Region, to :: Region } -> Command Top
  FirewallClear         :: Command Top
  RunExperiment         :: Deployment -> Command Top
  PostExperiment        :: Command Top
  DumpLogs              :: { depl :: Deployment, withProf :: Bool } -> Command Top
  PrintDate             :: Command Top
deriving instance Show (Command a)

centralCommandParser :: Parser (Command Top)
centralCommandParser =
  (    subcommandGroup "General:"
    [ ("template",              "Produce (or update) a checkout of BRANCH with a configuration YAML file (whose default name depends on the ENVIRONMENT), primed for future operations.",
                                Template
                                <$> (fromMaybe Ops.defaultNodeLimit
                                      <$> optional (optInteger "node-limit" 'l' "Limit cardano-node count to N"))
                                <*> (fromMaybe False
                                      <$> optional (switch "here" 'h' "Instead of cloning a subdir, operate on a config in the current directory"))
                                <*> (optional (optPath "config" 'c' "Override the default, environment-dependent config filename"))
                                <*> parserEnvironment
                                <*> parserTarget
                                <*> parserBranch "iohk-nixops branch to check out"
                                <*> parserDeployments)
    , ("set-rev",               "Set commit of PROJECT dependency to COMMIT",
                                SetRev
                                <$> parserProject
                                <*> parserCommit "Commit to set PROJECT's version to")
    , ("fake-keys",             "Fake minimum set of keys necessary for a minimum complete deployment (explorer + report-server + nodes)",
                                                                                                    pure FakeKeys)
    , ("do",                    "Chain commands",                                                   Do <$> parserDo) ]

   <|> subcommandGroup "Build-related:"
    [ ("genesis",               "initiate production of Genesis in cardano-sl/genesis subdir",      pure Genesis)
    , ("generate-ipdht",        "Generate IP/DHT mappings for wallet use",                          pure GenerateIPDHTMappings)
    , ("build",                 "Build the application specified by DEPLOYMENT",                    Build <$> parserDeployment)
    , ("ami",                   "Build ami",                                                        pure AMI) ]

   <|> subcommandGroup "AWS:"
    [ ("ec2",                   "EC2 subcommand",                                                   EC2Sub <$> ec2CommandParser)
    , ("iam",                   "IAM subcommand",                                                   IAMSub <$> iamCommandParser) ]

   <|> subcommandGroup "Cluster lifecycle:"
   [
     -- ("nixops",                "Call 'nixops' with current configuration",
     --                           (Nixops
     --                            <$> (NixopsCmd <$> argText "CMD" "Nixops command to invoke")
     --                            <*> ???)) -- should we switch to optparse-applicative?
     ("create",                 "Create the whole cluster",                                         pure Create)
   , ("modify",                 "Update cluster state with the nix expression changes",             pure Modify)
   , ("deploy",                 "Deploy the whole cluster",
                                Deploy
                                <$> switch "evaluate-only" 'e' "Pass --evaluate-only to 'nixops'."
                                <*> switch "build-only"    'b' "Pass --build-only to 'nixops'.")
   , ("destroy",                "Destroy the whole cluster",                                        pure Destroy)
   , ("delete",                 "Unregistr the cluster from NixOps",                                pure Delete)
   , ("fromscratch",            "Destroy, Delete, Create, Deploy",                                  pure FromScratch)
   , ("info",                   "Invoke 'nixops info'",                                             pure Status)]

   <|> subcommandGroup "Live cluster ops:"
   [ ("checkstatus",            "Check if nodes are accessible via ssh and reboot if they timeout", pure CheckStatus)
   , ("start",                  "Start cardano-node service",                                       pure Start)
   , ("stop",                   "Stop cardano-node service",                                        pure Stop)
   -- , ("firewall-block-region",  "Block whole region in firewall",
   --                              FirewallBlock
   --                              <$> (Region <$> optReadLower "from-region" 'f' "AWS Region that won't reach --to")
   --                              <*> (Region <$> optReadLower "to-region"   't' "AWS Region that all nodes will be blocked"))
   , ("firewall-clear",         "Clear firewall",                                                   pure FirewallClear)
   , ("runexperiment",          "Deploy cluster and perform measurements",                          RunExperiment <$> parserDeployment)
   , ("postexperiment",         "Post-experiments logs dumping (if failed)",                        pure PostExperiment)
   , ("dumplogs",               "Dump logs",
                                DumpLogs
                                <$> parserDeployment
                                <*> switch "prof"         'p' "Dump profiling data as well (requires service stop)")
   , ("date",                   "Print date/time",                                                  pure PrintDate)]

   <|> subcommandGroup "Other:"
    [ ])

ec2CommandParser =
  subcommandGroup "General:"
    [ ("instances",             "Print instances on the chosen region",                             pure Instances)
    , ("info",                  "Print information about instance specified by INSTANCE-ID, in the chosen region",
                                InstInfo
                                <$> parserInstId "The ID of the instance to examine")
    , ("set-tag",               "Set INSTANCE-TAG of INSTANCE-ID, in the chosen region",
                                SetTag
                                <$> parserInstId  "The ID of the instance to examine"
                                <*> parserInstTag "The tag of the instance to set"
                                <*> argText "VALUE" "The new tag value")
    , ("unset-tag",             "Set INSTANCE-TAG of INSTANCE-ID, in the chosen region",
                                DeleteTag
                                <$> parserInstId  "The ID of the instance to examine"
                                <*> parserInstTag "The tag of the instance to set")
    , ("list-snapshottable",    "List instances that have the snapshot schedule set",               pure ListSnapshottable)
    , ("snapshot",              "WIP",
                                Snapshot
                                <$> (fromMaybe Ask
                                      <$> optional parserGo)) ]

iamCommandParser =
  subcommandGroup "General:"
    [ ("whoami",                "Print current access credentials",                                 pure Whoami) ]


main :: IO ()
main = do
  (o@Options{..}, topcmd) <- options "Helper CLI around IOHK NixOps. For example usage see:\n\n  https://github.com/input-output-hk/internal-documentation/wiki/iohk-ops-reference#example-deployment" $
                             (,) <$> Ops.parserOptions <*> centralCommandParser

  case topcmd of
    Template{..}                -> runTemplate        o topcmd
    SetRev       project commit -> runSetRev          o project commit

    _ -> do
      -- XXX: Config filename depends on environment, which defaults to 'Development'
      let cf = flip fromMaybe oConfigFile $
               Ops.envConfigFilename Any
      c <- Ops.readConfig cf

      when oVerbose $
        printf ("-- config '"%fp%"'\n"%w%"\n") cf c

      -- * CardanoCSL
      -- dat <- getSmartGenCmd c
      -- TIO.putStrLn $ T.pack $ show dat

      doCommand o c topcmd
    where
        doCommand :: Options -> Ops.NixopsConfig -> Command Top -> IO ()
        doCommand o c cmd = do
          let isNode (T.unpack . Ops.fromNodeName -> ('n':'o':'d':'e':_)) = True
              isNode _ = False
              getNodeNames' = filter isNode <$> Ops.getNodeNames o c
          case cmd of
            -- * setup
            FakeKeys                 -> runFakeKeys
            -- * building
            Genesis                  -> Ops.generateGenesis           o c
            GenerateIPDHTMappings    -> void $
                                        Cardano.generateIPDHTMappings o c
            Build depl               -> Ops.build                     o c depl
            AMI                      -> Cardano.buildAMI              o c
            -- * deployment lifecycle
            Nixops cmd args          -> Ops.nixops                    o c cmd args
            Do cmds                  -> sequence_ $ doCommand o c <$> cmds
            Create                   -> Ops.create                    o c
            Modify                   -> Ops.modify                    o c
            Deploy evonly buonly     -> Ops.deploy                    o c evonly buonly
            Destroy                  -> Ops.destroy                   o c
            Delete                   -> Ops.delete                    o c
            FromScratch              -> Ops.fromscratch               o c
            Status                   -> Ops.nixops                    o c "info" []
            -- * AWS
            EC2Sub cmd               -> runEC2                        o c cmd
            IAMSub cmd               -> runIAM                        o c cmd

            -- * live deployment ops
            CheckStatus              -> Ops.checkstatus               o c
            Start                    -> getNodeNames'
                                        >>= Cardano.startNodes        o c
            Stop                     -> getNodeNames'
                                        >>= Cardano.stopNodes         o c
            -- FirewallBlock{..}        -> Cardano.firewallBlock         o c from to
            FirewallClear            -> Cardano.firewallClear         o c
            RunExperiment Nodes      -> getNodeNames'
                                        >>= Cardano.runexperiment     o c
            RunExperiment Timewarp   -> Timewarp.runexperiment        o c
            RunExperiment x          -> die $ "RunExperiment undefined for deployment " <> showT x
            PostExperiment           -> Cardano.postexperiment        o c
            DumpLogs{..}
              | Nodes        <- depl -> getNodeNames'
                                        >>= void . Cardano.dumpLogs  o c withProf
              | Timewarp     <- depl -> getNodeNames'
                                        >>= void . Timewarp.dumpLogs o c withProf
              | x            <- depl -> die $ "DumpLogs undefined for deployment " <> showT x
            PrintDate                -> getNodeNames'
                                        >>= Cardano.printDate        o c
            Template{..}             -> error "impossible"
            SetRev   _ _             -> error "impossible"


runTemplate :: Options -> Command Top -> IO ()
runTemplate o@Options{..} Template{..} = do
  when (elem (fromBranch tBranch) $ showT <$> (every :: [Deployment])) $
    die $ format ("the branch name "%w%" ambiguously refers to a deployment.  Cannot have that!") (fromBranch tBranch)
  homeDir <- home
  let bname     = fromBranch tBranch
      branchDir = homeDir <> (fromText bname)
  exists <- testpath branchDir
  case (exists, tHere) of
    (_, True) -> pure ()
    (True, _) -> echo $ "Using existing git clone ..."
    _         -> cmd o "git" ["clone", fromURL $ projectURL IOHK, "-b", bname, bname]

  unless tHere $ do
    cd branchDir
    cmd o "git" (["config", "--replace-all", "receive.denyCurrentBranch", "updateInstead"])

  Ops.GithubSource{..} <- Ops.readSource Ops.githubSource Nixpkgs

  let config = Ops.mkConfig tBranch ghRev tEnvironment tTarget tDeployments tNodeLimit
  configFilename <- T.pack . Path.encodeString <$> Ops.writeConfig tFile config

  echo ""
  echo $ "-- " <> (unsafeTextToLine $ configFilename) <> " is:"
  cmd o "cat" [configFilename]
runTemplate Options{..} _ = error "impossible"

runSetRev :: Options -> Project -> Commit -> IO ()
runSetRev o proj rev = do
  printf ("Setting '"%s%"' commit to "%s%"\n") (lowerShowT proj) (fromCommit rev)
  spec <- incmd o "nix-prefetch-git" ["--no-deepClone", fromURL $ projectURL proj, fromCommit rev]
  writeFile (T.unpack $ format fp $ Ops.projectSrcFile proj) $ T.unpack spec

runFakeKeys :: IO ()
runFakeKeys = do
  echo "Faking keys/key*.sk"
  testdir "keys"
    >>= flip unless (mkdir "keys")
  forM_ (41:[1..14]) $
    (\x-> do touch $ Turtle.fromText $ format ("keys/key"%d%".sk") x)
  echo "Minimum viable keyset complete."


-- * AWS
--
-- type AWSConstraint r m = MonadBaseControl IO m

defaultRegion = Frankfurt

az'region'map :: AZ -> Region
az'region'map "ap-northeast-1a" = Tokyo
az'region'map "ap-northeast-2c" = Seoul
az'region'map "ap-southeast-1a" = Singapore
az'region'map "ap-southeast-2b" = Sydney
az'region'map "eu-central-1b"   = Frankfurt
az'region'map "eu-west-1a"      = Ireland
az'region'map "eu-west-1b"      = Ireland
az'region'map "eu-west-1c"      = Ireland
az'region'map "us-west-2b"      = Oregon
az'region'map (AZ x)            = errorT $ "Unknown AZ '" <> x <> "'"

withAWS :: Options -> (forall m . (MonadAWS m) => m a) -> IO a
withAWS Options{..} awsAction = do
  lgr <- newLogger (if oDebug then Debug else Info) Sys.stdout
  env <- newEnv Discover
        <&> set envLogger lgr
        <&> set envRegion defaultRegion
  (runResourceT . runAWST env) awsAction

allRegions :: [Region]
allRegions = [NorthVirginia, Ohio, NorthCalifornia, Oregon, Tokyo, Seoul, Mumbai, Singapore, Sydney, SaoPaulo, Ireland, Frankfurt]
forAWSRegions :: Options -> [Region] -> (forall m . MonadAWS m => Region -> m a) -> IO [a]
forAWSRegions Options{..} rs awsAction = do
  lgr <- newLogger (if oDebug then Debug else Info) Sys.stderr
  forM rs $
    \r-> do
      env <- newEnv Discover
        <&> set envLogger lgr
        <&> set envRegion r
      (runResourceT . runAWST env) (awsAction r)

forAWSRegions_ :: Options -> [Region] -> (forall m . MonadAWS m => Region -> m a) -> IO ()
forAWSRegions_ o rs a = forAWSRegions o rs a >> pure ()


-- * IAM
--
whoami :: (MonadAWS m) => m User
whoami = do
  gurs <- send $ getUser
  pure $ gurs^.gursUser

runIAM :: Options -> Ops.NixopsConfig -> Command IAM' -> IO ()
runIAM o _c Whoami = withAWS o $ do
  user <- whoami
  printf (w%"\n") user
  pure ()


-- * EC2
--
pp'tag :: Tag -> Text
pp'tag x = format (s%":"%s) (x^.tagKey) (x^.tagValue)

inst'tag :: Instance -> Text -> Maybe Tag
inst'tag ins tag'name =
  find ((== tag'name) . (^.tagKey)) $ ins^.insTags

inst'tag'val' :: Instance -> Text -> Text -> Text
inst'tag'val' ins tag'name def = inst'tag ins tag'name
                                <&> (^.tagValue)
                                & fromMaybe def

get'insts'current'region :: MonadAWS m => m [Instance]
get'insts'current'region = send describeInstances
                           <&> concat . ((^.rInstances) <$>) . (^.dirsReservations)

get'insts'global :: Options -> IO [Instance]
get'insts'global o = forAWSRegions o allRegions (\_ -> get'insts'current'region)
                     <&> concat

inst'tag'val :: Instance -> Text -> Text
inst'tag'val ins tag'name = inst'tag'val' ins tag'name (errorT $ "Instance has no tag '" <> tag'name <> "'")

inst'name :: Instance -> Text
inst'name ins = inst'tag'val' ins "Name" ""

inst'az :: Instance -> Maybe AZ
inst'az inst = AZ <$> inst^.insPlacement.pAvailabilityZone

inst'az'pretty :: Instance -> AZ
inst'az'pretty = fromMaybe (AZ "--unknown-AZ--") . inst'az

inst'info :: MonadAWS m => Options -> InstId -> m ()
inst'info _o (InstId inst'id) = do
  insts <- get'insts'current'region
  let inst = flip find insts (\i-> i^.insInstanceId == inst'id)
             & fromMaybe (error $ T.printf "No instance with id '%s' in current region." inst'id)
  liftIO $ T.printf ("%s %s \"%s\"  tags:  %s\n")
    (inst^.insInstanceId) (fromAZ $ inst'az'pretty inst) (inst'name inst) (T.intercalate " " $ pp'tag <$> inst^.insTags)

print'insts'tags :: MonadIO m => [(Int, Text)] -> [Instance] -> m ()
print'insts'tags tags ists = do
  forM_ ists $
    \ins -> do
      liftIO $ T.printf ("  %45s  %20s  %s") (inst'name ins) (ins^.insInstanceId) (fromAZ $ inst'az'pretty ins) -- (ins^.insImageId) (T.intercalate " " $ ppTag <$> ins^.insTags)
      forM_ tags $
        \(width, tag) -> liftIO $ T.printf (T.printf "  %%%ds" width) (inst'tag'val' ins tag "")
      liftIO $ putStrLn ""

runEC2 :: Options -> Ops.NixopsConfig -> Command EC2' -> IO ()
runEC2 o _c Instances = forAWSRegions_ o allRegions $
  \(region :: Region) -> do
    liftIO $ putStrLn $ "region " <> show region
    get'insts'current'region
      >>= print'insts'tags [(10, "Name")]

runEC2 o _c (InstInfo inst'id) = withAWS o $ do
  inst'info o inst'id

runEC2 o _c (SetTag (InstId inst'id) (InstTag tag'name) tag'value) = withAWS o $ do
  _ctrs <- send $
    (createTags
     & cResources .~ [inst'id]
     & cTags      .~ [tag tag'name tag'value])
  pure ()

-- | WARNING: this is inefficient (two reqs instead of one), because deleteTags is
--   slightly broken in amazonka-ec2 -- see semantics of
--   http://hackage.haskell.org/package/amazonka-ec2-1.4.5/docs/Network-AWS-EC2-DeleteTags.html#v:dtsTags
--   ..and observe how 'Tag' has no way to encode absence of value.
runEC2 o _c (DeleteTag (InstId inst'id) (InstTag tag'name)) = withAWS o $ do
  _ctrs <- send $
    (createTags
     & cResources .~ [inst'id]
     & cTags      .~ [tag tag'name ""])
  _dtrs <- send $
    (deleteTags
     & dtsResources .~ [inst'id]
     & dtsTags      .~ [tag tag'name ""])
  pure ()

runEC2 o _c ListSnapshottable = do
  all'insts <- get'insts'global o
  let snapshottable = flip filter all'insts $
                      isJust . flip inst'tag Snapshot.schedule'tag
  print'insts'tags [] snapshottable

runEC2 o _c (Snapshot go) = do
  echo "Querying global instance list."
  all'insts <- get'insts'global o

  let snapshottable = flip filter all'insts $
                      isJust . flip inst'tag Snapshot.schedule'tag
      region'insts  = Map.fromList [ (az'region'map $ inst'az'pretty inst, inst)
                                   | inst <- snapshottable ]
      regions       = Map.keys region'insts
  printf ("Snapshottable instances ("%d%" of total "%d%") in "%d%" regions:\n")
         (length snapshottable) (length all'insts) (Map.size region'insts)
  print'insts'tags [] snapshottable

  case go of
    Dry -> do
      echo "Dry run mode, exiting."
      exit $ ExitFailure 1
    Ask -> do
      echo "Confirmation mode, enter 'yes' to proceed:"
      x <- readline
      unless (x == Just "yes") $ do
        echo "User declined to proceed, exiting."
        exit $ ExitFailure 1
    Go  -> pure ()

  forAWSRegions_ o regions $
    \_region-> do
      liftIO $ echo "Initiating snapshotting"
    -- Snapshot.processAllInstances (length snapshottable) $ zip [1..] snapshottable
