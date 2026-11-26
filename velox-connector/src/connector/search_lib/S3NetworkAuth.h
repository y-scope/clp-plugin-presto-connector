/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Free of Velox, so that the S3 authentication tests can link it without the
// Presto worker.

#pragma once

#include <chrono>
#include <memory>
#include <stdexcept>

#include "clp_s/InputConfig.hpp"
#include "connector/search_lib/S3Credentials.h"

namespace facebook::velox::connector::clp::search_lib {

/// How long each presigned S3 URL remains valid. Every reader requests its
/// object as soon as its URL is signed, so a short lifetime suffices, and it
/// limits how long a leaked URL stays usable.
inline constexpr std::chrono::seconds kPresignedUrlLifetime{60};

/// How much longer than `kPresignedUrlLifetime` credentials must remain valid
/// to sign a request. It covers the time between checking the credentials and
/// signing with them, and clock skew between this host and their issuer.
inline constexpr std::chrono::seconds kCredentialExpirationMargin{5};

/// Thrown when an S3 request can't be authenticated. Its message never contains
/// credentials, URLs, or messages from the credentials provider.
class S3AuthenticationError : public std::runtime_error {
 public:
  using std::runtime_error::runtime_error;

  ~S3AuthenticationError() override;
};

/// Creates the option that authenticates a catalog's S3 requests.
///
/// CLP presigns each request (every reader it creates) with a credential
/// snapshot that it gets from `provider` just before the request, so refreshed
/// credentials take effect on the next request. Each presigned URL remains
/// valid for `kPresignedUrlLifetime`, which never exceeds the remaining
/// lifetime of the credentials that signed it: a request fails if its
/// credentials are unavailable, incomplete, or expire within
/// `kPresignedUrlLifetime` plus `kCredentialExpirationMargin`. CLP never falls
/// back to the credentials in the environment.
///
/// A failed request throws `S3AuthenticationError` out of the CLP call that
/// creates the reader (e.g., `clp_s::ArchiveReader::open` or
/// `clp_s::try_create_reader`), so that the failure reaches the query instead
/// of being treated as an unreadable split.
///
/// The returned option shares ownership of `provider`, and copies of it may be
/// used from multiple threads at once.
///
/// @param provider
/// @return The network authentication option.
/// @throw std::invalid_argument if `provider` is null.
[[nodiscard]] clp_s::NetworkAuthOption createS3NetworkAuthOption(
    std::shared_ptr<S3CredentialsProvider> provider);

} // namespace facebook::velox::connector::clp::search_lib
