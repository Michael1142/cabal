{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Distribution.Package
-- Copyright   :  Isaac Jones 2003-2004
-- License     :  BSD3
--
-- Maintainer  :  cabal-devel@haskell.org
-- Portability :  portable
--
-- Defines a package identifier along with a parser and pretty printer for it.
-- 'PackageIdentifier's consist of a name and an exact version. It also defines
-- a 'Dependency' data type. A dependency is a package name and a version
-- range, like @\"foo >= 1.2 && < 2\"@.

module Distribution.Package (
        -- * Package ids
        PackageName, unPackageName, mkPackageName,
        PackageIdentifier(..),
        PackageId,
        PkgconfigName, unPkgconfigName, mkPkgconfigName,

        -- * Package keys/installed package IDs (used for linker symbols)
        ComponentId, unComponentId, mkComponentId,
        UnitId, unUnitId, mkUnitId,
        DefUnitId,
        unsafeMkDefUnitId,
        unDefUnitId,
        newSimpleUnitId,
        mkLegacyUnitId,
        getHSLibraryName,
        InstalledPackageId, -- backwards compat

        -- * Modules
        Module(..),

        -- * ABI hash
        AbiHash, unAbiHash, mkAbiHash,

        -- * Package classes
        Package(..), packageName, packageVersion,
        HasUnitId(..),
        installedPackageId,
        PackageInstalled(..),
  ) where

import Prelude ()
import Distribution.Compat.Prelude
import Distribution.Utils.ShortText

import Distribution.Version
         ( Version, nullVersion )

import qualified Distribution.Compat.ReadP as Parse
import qualified Text.PrettyPrint as Disp
import Distribution.Compat.ReadP
import Distribution.ParseUtils
import Distribution.Text
import Distribution.ModuleName

import Text.PrettyPrint (text)

-- | A package name.
--
-- Use 'mkPackageName' and 'unPackageName' to convert from/to a
-- 'String'.
--
-- This type is opaque since @Cabal-2.0@
--
-- @since 2.0
newtype PackageName = PackageName ShortText
    deriving (Generic, Read, Show, Eq, Ord, Typeable, Data)

-- | Convert 'PackageName' to 'String'
unPackageName :: PackageName -> String
unPackageName (PackageName s) = fromShortText s

-- | Construct a 'PackageName' from a 'String'
--
-- 'mkPackageName' is the inverse to 'unPackageName'
--
-- Note: No validations are performed to ensure that the resulting
-- 'PackageName' is valid
--
-- @since 2.0
mkPackageName :: String -> PackageName
mkPackageName = PackageName . toShortText

-- | 'mkPackageName'
--
-- @since 2.0
instance IsString PackageName where
  fromString = mkPackageName

instance Binary PackageName

instance Text PackageName where
  disp = Disp.text . unPackageName
  parse = mkPackageName <$> parsePackageName

instance NFData PackageName where
    rnf (PackageName pkg) = rnf pkg

-- | A pkg-config library name
--
-- This is parsed as any valid argument to the pkg-config utility.
--
-- @since 2.0
newtype PkgconfigName = PkgconfigName ShortText
    deriving (Generic, Read, Show, Eq, Ord, Typeable, Data)

-- | Convert 'PkgconfigName' to 'String'
--
-- @since 2.0
unPkgconfigName :: PkgconfigName -> String
unPkgconfigName (PkgconfigName s) = fromShortText s

-- | Construct a 'PkgconfigName' from a 'String'
--
-- 'mkPkgconfigName' is the inverse to 'unPkgconfigName'
--
-- Note: No validations are performed to ensure that the resulting
-- 'PkgconfigName' is valid
--
-- @since 2.0
mkPkgconfigName :: String -> PkgconfigName
mkPkgconfigName = PkgconfigName . toShortText

-- | 'mkPkgconfigName'
--
-- @since 2.0
instance IsString PkgconfigName where
    fromString = mkPkgconfigName

instance Binary PkgconfigName

-- pkg-config allows versions and other letters in package names, eg
-- "gtk+-2.0" is a valid pkg-config package _name_.  It then has a package
-- version number like 2.10.13
instance Text PkgconfigName where
  disp = Disp.text . unPkgconfigName
  parse = mkPkgconfigName
          <$> munch1 (\c -> isAlphaNum c || c `elem` "+-._")

instance NFData PkgconfigName where
    rnf (PkgconfigName pkg) = rnf pkg

-- | Type alias so we can use the shorter name PackageId.
type PackageId = PackageIdentifier

-- | The name and version of a package.
data PackageIdentifier
    = PackageIdentifier {
        pkgName    :: PackageName, -- ^The name of this package, eg. foo
        pkgVersion :: Version -- ^the version of this package, eg 1.2
     }
     deriving (Generic, Read, Show, Eq, Ord, Typeable, Data)

instance Binary PackageIdentifier

instance Text PackageIdentifier where
  disp (PackageIdentifier n v)
    | v == nullVersion = disp n -- if no version, don't show version.
    | otherwise        = disp n <<>> Disp.char '-' <<>> disp v

  parse = do
    n <- parse
    v <- (Parse.char '-' >> parse) <++ return nullVersion
    return (PackageIdentifier n v)

instance NFData PackageIdentifier where
    rnf (PackageIdentifier name version) = rnf name `seq` rnf version

-- | A module identity uniquely identifies a Haskell module by
-- qualifying a 'ModuleName' with the 'UnitId' which defined
-- it.  This type distinguishes between two packages
-- which provide a module with the same name, or a module
-- from the same package compiled with different dependencies.
-- There are a few cases where Cabal needs to know about
-- module identities, e.g., when writing out reexported modules in
-- the 'InstalledPackageInfo'.
data Module =
      Module DefUnitId ModuleName
    deriving (Generic, Read, Show, Eq, Ord, Typeable, Data)

instance Binary Module

instance Text Module where
    disp (Module uid mod_name) =
        disp uid <<>> Disp.text ":" <<>> disp mod_name
    parse = do
        uid <- parse
        _ <- Parse.char ':'
        mod_name <- parse
        return (Module uid mod_name)

instance NFData Module where
    rnf (Module uid mod_name) = rnf uid `seq` rnf mod_name

-- | A 'ComponentId' uniquely identifies the transitive source
-- code closure of a component (i.e. libraries, executables).
--
-- For non-Backpack components, this corresponds one to one with
-- the 'UnitId', which serves as the basis for install paths,
-- linker symbols, etc.
--
-- Use 'mkComponentId' and 'unComponentId' to convert from/to a
-- 'String'.
--
-- This type is opaque since @Cabal-2.0@
--
-- @since 2.0
newtype ComponentId = ComponentId ShortText
    deriving (Generic, Read, Show, Eq, Ord, Typeable, Data)

-- | Construct a 'ComponentId' from a 'String'
--
-- 'mkComponentId' is the inverse to 'unComponentId'
--
-- Note: No validations are performed to ensure that the resulting
-- 'ComponentId' is valid
--
-- @since 2.0
mkComponentId :: String -> ComponentId
mkComponentId = ComponentId . toShortText

-- | 'mkComponentId'
--
-- @since 2.0
instance IsString ComponentId where
    fromString = mkComponentId

-- | Convert 'ComponentId' to 'String'
--
-- @since 2.0
unComponentId :: ComponentId -> String
unComponentId (ComponentId s) = fromShortText s

{-# DEPRECATED InstalledPackageId "Use UnitId instead" #-}
type InstalledPackageId = UnitId

instance Binary ComponentId

instance Text ComponentId where
  disp = text . unComponentId

  parse = mkComponentId `fmap` Parse.munch1 abi_char
   where abi_char c = isAlphaNum c || c `elem` "-_."

instance NFData ComponentId where
    rnf = rnf . unComponentId

-- | Returns library name prefixed with HS, suitable for filenames
getHSLibraryName :: UnitId -> String
getHSLibraryName uid = "HS" ++ display uid

-- | A unit identifier identifies a (possibly instantiated)
-- package/component that can be installed the installed package
-- database.  There are several types of components that can be
-- installed:
--
--  * A traditional library with no holes, so that 'unitIdHash'
--    is @Nothing@.  In the absence of Backpack, 'UnitId'
--    is the same as a 'ComponentId'.
--
--  * An indefinite, Backpack library with holes.  In this case,
--    'unitIdHash' is still @Nothing@, but in the install,
--    there are only interfaces, no compiled objects.
--
--  * An instantiated Backpack library with all the holes
--    filled in.  'unitIdHash' is a @Just@ a hash of the
--    instantiating mapping.
--
-- A unit is a component plus the additional information on how the
-- holes are filled in. Thus there is a one to many relationship: for a
-- particular component there are many different ways of filling in the
-- holes, and each different combination is a unit (and has a separate
-- 'UnitId').
--
-- 'UnitId' is distinct from 'OpenUnitId', in that it is always
-- installed, whereas 'OpenUnitId' are intermediate unit identities
-- that arise during mixin linking, and don't necessarily correspond
-- to any actually installed unit.  Since the mapping is not actually
-- recorded in a 'UnitId', you can't actually substitute over them
-- (but you can substitute over 'OpenUnitId').  See also
-- "Distribution.Backpack.FullUnitId" for a mechanism for expanding an
-- instantiated 'UnitId' to retrieve its mapping.
--
-- Backwards compatibility note: if you need to get the string
-- representation of a UnitId to pass, e.g., as a @-package-id@
-- flag, use the 'display' function, which will work on all
-- versions of Cabal.
--
newtype UnitId = UnitId ShortText
  deriving (Generic, Read, Show, Eq, Ord, Typeable, Data, NFData)

instance Binary UnitId

-- | The textual format for 'UnitId' coincides with the format
-- GHC accepts for @-package-id@.
--
instance Text UnitId where
    disp = text . unUnitId
    parse = mkUnitId <$> Parse.munch1 (\c -> isAlphaNum c || c `elem` "-_.+")

-- | If you need backwards compatibility, consider using 'display'
-- instead, which is supported by all versions of Cabal.
--
unUnitId :: UnitId -> String
unUnitId (UnitId s) = fromShortText s

mkUnitId :: String -> UnitId
mkUnitId = UnitId . toShortText

-- | 'mkUnitId'
--
-- @since 2.0
instance IsString UnitId where
    fromString = mkUnitId

-- | A 'UnitId' for a definite package.  The 'DefUnitId' invariant says
-- that a 'UnitId' identified this way is definite; i.e., it has no
-- unfilled holes.
newtype DefUnitId = DefUnitId { unDefUnitId :: UnitId }
  deriving (Generic, Read, Show, Eq, Ord, Typeable, Data, Binary, NFData, Text)

-- | Unsafely create a 'DefUnitId' from a 'UnitId'.  Your responsibility
-- is to ensure that the 'DefUnitId' invariant holds.
unsafeMkDefUnitId :: UnitId -> DefUnitId
unsafeMkDefUnitId = DefUnitId

-- | Create a unit identity with no associated hash directly
-- from a 'ComponentId'.
newSimpleUnitId :: ComponentId -> UnitId
newSimpleUnitId (ComponentId s) = UnitId s

-- | Make an old-style UnitId from a package identifier
mkLegacyUnitId :: PackageId -> UnitId
mkLegacyUnitId = newSimpleUnitId . mkComponentId . display

-- | Class of things that have a 'PackageIdentifier'
--
-- Types in this class are all notions of a package. This allows us to have
-- different types for the different phases that packages go though, from
-- simple name\/id, package description, configured or installed packages.
--
-- Not all kinds of packages can be uniquely identified by a
-- 'PackageIdentifier'. In particular, installed packages cannot, there may be
-- many installed instances of the same source package.
--
class Package pkg where
  packageId :: pkg -> PackageIdentifier

packageName    :: Package pkg => pkg -> PackageName
packageName     = pkgName    . packageId

packageVersion :: Package pkg => pkg -> Version
packageVersion  = pkgVersion . packageId

instance Package PackageIdentifier where
  packageId = id

-- | Packages that have an installed unit ID
class Package pkg => HasUnitId pkg where
  installedUnitId :: pkg -> UnitId

{-# DEPRECATED installedPackageId "Use installedUnitId instead" #-}
-- | Compatibility wrapper for Cabal pre-1.24.
installedPackageId :: HasUnitId pkg => pkg -> UnitId
installedPackageId = installedUnitId

-- | Class of installed packages.
--
-- The primary data type which is an instance of this package is
-- 'InstalledPackageInfo', but when we are doing install plans in Cabal install
-- we may have other, installed package-like things which contain more metadata.
-- Installed packages have exact dependencies 'installedDepends'.
class (HasUnitId pkg) => PackageInstalled pkg where
  installedDepends :: pkg -> [UnitId]

-- -----------------------------------------------------------------------------
-- ABI hash

-- | ABI Hashes
--
-- Use 'mkAbiHash' and 'unAbiHash' to convert from/to a
-- 'String'.
--
-- This type is opaque since @Cabal-2.0@
--
-- @since 2.0
newtype AbiHash = AbiHash ShortText
    deriving (Eq, Show, Read, Generic)

-- | Construct a 'AbiHash' from a 'String'
--
-- 'mkAbiHash' is the inverse to 'unAbiHash'
--
-- Note: No validations are performed to ensure that the resulting
-- 'AbiHash' is valid
--
-- @since 2.0
unAbiHash :: AbiHash -> String
unAbiHash (AbiHash h) = fromShortText h

-- | Convert 'AbiHash' to 'String'
--
-- @since 2.0
mkAbiHash :: String -> AbiHash
mkAbiHash = AbiHash . toShortText

-- | 'mkAbiHash'
--
-- @since 2.0
instance IsString AbiHash where
    fromString = mkAbiHash

instance Binary AbiHash

instance Text AbiHash where
    disp = Disp.text . unAbiHash
    parse = fmap mkAbiHash (Parse.munch isAlphaNum)
