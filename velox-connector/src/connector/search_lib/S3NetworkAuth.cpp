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

#include "connector/search_lib/S3NetworkAuth.h"

#include <chrono>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>

#include "clp_s/InputConfig.hpp"
#include "connector/search_lib/S3Credentials.h"

namespace facebook::velox::connector::clp::search_lib {

namespace {

/// Gets credentials from `provider` and checks that they can sign a presigned
/// URL that remains valid for `kPresignedUrlLifetime`.
///
/// @param provider
/// @return The credentials.
/// @throw S3AuthenticationError if the credentials can't sign the URL.
S3Credentials getSigningCredentials(S3CredentialsProvider& provider) {
  std::optional<S3Credentials> credentials;
  try {
    credentials = provider.getCredentials();
  } catch (...) {
    // The provider's message may contain credentials or other sensitive
    // details, so it's deliberately dropped.
    throw S3AuthenticationError(
        "Failed to get the AWS credentials for S3 requests.");
  }

  if (false == credentials.has_value()) {
    throw S3AuthenticationError(
        "No AWS credentials are available for S3 requests.");
  }
  if (credentials->accessKeyId.empty() ||
      credentials->secretAccessKey.empty()) {
    throw S3AuthenticationError(
        "The AWS credentials for S3 requests are incomplete.");
  }
  if (credentials->expiration.has_value() &&
      credentials->expiration.value() - std::chrono::system_clock::now() <
          kPresignedUrlLifetime + kCredentialExpirationMargin) {
    throw S3AuthenticationError(
        "The AWS credentials for S3 requests have expired or are about to "
        "expire.");
  }
  return std::move(credentials.value());
}

} // namespace

S3AuthenticationError::~S3AuthenticationError() = default;

clp_s::NetworkAuthOption createS3NetworkAuthOption(
    std::shared_ptr<S3CredentialsProvider> provider) {
  if (nullptr == provider) {
    throw std::invalid_argument("The S3 credentials provider can't be null.");
  }

  return clp_s::NetworkAuthOption{
      .method = clp_s::AuthMethod::S3PresignedUrlV4,
      .aws_credentials_provider = [provider = std::move(provider)]()
          -> std::optional<clp_s::AwsCredentials> {
        auto credentials = getSigningCredentials(*provider);
        std::optional<std::string> sessionToken;
        if (false == credentials.sessionToken.empty()) {
          sessionToken = std::move(credentials.sessionToken);
        }
        return clp_s::AwsCredentials{
            .access_key_id = std::move(credentials.accessKeyId),
            .secret_access_key = std::move(credentials.secretAccessKey),
            .session_token = std::move(sessionToken)};
      },
      .presigned_url_expire_time = kPresignedUrlLifetime};
}

} // namespace facebook::velox::connector::clp::search_lib
