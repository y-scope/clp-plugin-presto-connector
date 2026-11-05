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

#include <memory>
#include <optional>

#include "connector/search_lib/S3Credentials.h"

namespace Aws::Auth {
class AWSCredentialsProvider;
} // namespace Aws::Auth

namespace facebook::velox::connector::clp::search_lib {

/// Supplies credentials from the AWS SDK for C++'s default credential provider
/// chain: environment variables, shared config and credentials files, STS web
/// identity (e.g., EKS IAM roles for service accounts), SSO, container
/// credentials, and EC2 instance profiles, in that order.
///
/// The chain caches temporary credentials and refreshes them before they
/// expire; for web identity, it reads the (rotated) token file again on each
/// refresh. Each instance has its own chain and cache, and it never modifies
/// the process's environment.
class AwsDefaultS3CredentialsProvider : public S3CredentialsProvider {
 public:
  AwsDefaultS3CredentialsProvider();

  ~AwsDefaultS3CredentialsProvider() override;

  AwsDefaultS3CredentialsProvider(const AwsDefaultS3CredentialsProvider&) =
      delete;
  AwsDefaultS3CredentialsProvider& operator=(
      const AwsDefaultS3CredentialsProvider&) = delete;

  std::optional<S3Credentials> getCredentials() override;

 private:
  // Keeps the SDK initialized while `chain_` exists, so it's declared first.
  std::shared_ptr<const void> sdk_;
  std::shared_ptr<Aws::Auth::AWSCredentialsProvider> chain_;
};

} // namespace facebook::velox::connector::clp::search_lib
