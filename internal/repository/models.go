package repository

// Type aliases re-exported from the sqlite driver package.
// All storage drivers must use these canonical types in their Store implementations.
// When a non-sqlite driver becomes the reference implementation, update these aliases.

import "github.com/tinyauthapp/tinyauth/internal/repository/sqlite"

type Session = sqlite.Session
type OidcCode = sqlite.OidcCode
type OidcToken = sqlite.OidcToken
type OidcUserinfo = sqlite.OidcUserinfo

type CreateSessionParams = sqlite.CreateSessionParams
type UpdateSessionParams = sqlite.UpdateSessionParams
type CreateOidcCodeParams = sqlite.CreateOidcCodeParams
type CreateOidcTokenParams = sqlite.CreateOidcTokenParams
type UpdateOidcTokenByRefreshTokenParams = sqlite.UpdateOidcTokenByRefreshTokenParams
type DeleteExpiredOidcTokensParams = sqlite.DeleteExpiredOidcTokensParams
type CreateOidcUserInfoParams = sqlite.CreateOidcUserInfoParams
