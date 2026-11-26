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

#pragma once

#include "connector/search_lib/ClpS3AuthProviderBase.h"

namespace facebook::velox::config {
class ConfigBase;
} // namespace facebook::velox::config

namespace facebook::velox::connector::clp {

/// Authenticates S3 requests with credentials from the AWS SDK for C++'s
/// default credential provider chain (`clp.s3-auth-provider=default`), such as
/// an EKS IAM role for the worker's service account. Temporary credentials are
/// refreshed before they expire.
class ClpDefaultS3AuthProvider : public ClpS3AuthProviderBase {
 public:
  /// @param config The catalog's configuration, which must not contain any
  /// `clp_package` credential properties.
  explicit ClpDefaultS3AuthProvider(const config::ConfigBase& config);
};

} // namespace facebook::velox::connector::clp
