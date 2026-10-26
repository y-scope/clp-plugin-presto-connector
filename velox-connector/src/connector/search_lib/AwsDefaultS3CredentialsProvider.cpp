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

#include "connector/search_lib/AwsDefaultS3CredentialsProvider.h"

#include <chrono>
#include <memory>
#include <optional>
#include <string>

#include <aws/core/Aws.h>
#include <aws/core/auth/AWSCredentials.h>
#include <aws/core/auth/AWSCredentialsProviderChain.h>

#include "clp/CurlGlobalInstance.hpp"
#include "connector/search_lib/S3Credentials.h"

namespace facebook::velox::connector::clp::search_lib {

namespace {

/// Initializes the plugin's (private) copy of the AWS SDK for its lifetime.
class AwsSdk {
 public:
  AwsSdk() {
    // CLP's readers share libcurl's global state through
    // `::clp::CurlGlobalInstance`, which serializes its initialization, so the
    // SDK holds an instance rather than initializing libcurl itself. Likewise,
    // OpenSSL >= 1.1 initializes itself, so the SDK shouldn't (de)initialize it
    // for the other libraries in the process.
    options_.httpOptions.initAndCleanupCurl = false;
    options_.cryptoOptions.initAndCleanupOpenSSL = false;
    Aws::InitAPI(options_);
  }

  ~AwsSdk() {
    Aws::ShutdownAPI(options_);
  }

  AwsSdk(const AwsSdk&) = delete;
  AwsSdk& operator=(const AwsSdk&) = delete;

 private:
  // Declared first so that libcurl stays initialized until the SDK shuts down.
  ::clp::CurlGlobalInstance curl_;
  Aws::SDKOptions options_;
};

/// @return The process-wide SDK instance. Credentials providers share it, so
/// the SDK shuts down only after the static reference and every provider are
/// destroyed.
std::shared_ptr<const AwsSdk> acquireAwsSdk() {
  static const auto sdk = std::make_shared<const AwsSdk>();
  return sdk;
}

} // namespace

AwsDefaultS3CredentialsProvider::AwsDefaultS3CredentialsProvider()
    : sdk_(acquireAwsSdk()),
      chain_(
          std::make_shared<Aws::Auth::DefaultAWSCredentialsProviderChain>()) {}

AwsDefaultS3CredentialsProvider::~AwsDefaultS3CredentialsProvider() = default;

std::optional<S3Credentials> AwsDefaultS3CredentialsProvider::getCredentials() {
  // Thread-safe; returns a copy of the chain's cached credentials, refreshing
  // them first if they're about to expire.
  const auto credentials = chain_->GetAWSCredentials();
  if (credentials.IsEmpty()) {
    return std::nullopt;
  }

  const auto& accessKeyId = credentials.GetAWSAccessKeyId();
  const auto& secretAccessKey = credentials.GetAWSSecretKey();
  const auto& sessionToken = credentials.GetSessionToken();
  S3Credentials result{
      .accessKeyId = std::string{accessKeyId.data(), accessKeyId.size()},
      .secretAccessKey =
          std::string{secretAccessKey.data(), secretAccessKey.size()},
      .sessionToken = std::string{sessionToken.data(), sessionToken.size()},
      .expiration = std::nullopt};
  // The SDK uses the latest representable time for credentials that don't
  // expire.
  if (const auto expiration = credentials.GetExpiration().UnderlyingTimestamp();
      std::chrono::system_clock::time_point::max() != expiration) {
    result.expiration = expiration;
  }
  return result;
}

} // namespace facebook::velox::connector::clp::search_lib
