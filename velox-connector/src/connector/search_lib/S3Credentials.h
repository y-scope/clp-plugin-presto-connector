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
#include <optional>
#include <string>
#include <utility>

namespace facebook::velox::connector::clp::search_lib {

/// A complete set of AWS credentials, as obtained at one point in time.
struct S3Credentials {
  std::string accessKeyId;
  std::string secretAccessKey;
  /// Empty unless the credentials are temporary.
  std::string sessionToken;
  /// When the credentials stop working, or `std::nullopt` if they don't expire.
  std::optional<std::chrono::system_clock::time_point> expiration;
};

/// Supplies the credentials that sign a catalog's S3 requests.
///
/// Implementations must be safe to call from multiple threads at once.
class S3CredentialsProvider {
 public:
  virtual ~S3CredentialsProvider() = default;

  /// Gets the current credentials, refreshing them first if necessary.
  ///
  /// @return The credentials, or `std::nullopt` if none are available.
  virtual std::optional<S3Credentials> getCredentials() = 0;
};

/// Supplies the same long-term credentials for every request.
class StaticS3CredentialsProvider : public S3CredentialsProvider {
 public:
  explicit StaticS3CredentialsProvider(S3Credentials credentials)
      : credentials_(std::move(credentials)) {}

  std::optional<S3Credentials> getCredentials() override {
    return credentials_;
  }

 private:
  const S3Credentials credentials_;
};

} // namespace facebook::velox::connector::clp::search_lib
