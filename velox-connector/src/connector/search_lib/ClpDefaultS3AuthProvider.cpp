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

#include "connector/search_lib/ClpDefaultS3AuthProvider.h"

#include <memory>
#include <string>

#include "connector/search_lib/AwsDefaultS3CredentialsProvider.h"
#include "connector/search_lib/ClpPackageS3AuthProvider.h"
#include "velox/common/base/Exceptions.h"
#include "velox/common/config/Config.h"

namespace facebook::velox::connector::clp {

namespace {

std::shared_ptr<search_lib::S3CredentialsProvider> createCredentialsProvider(
    const config::ConfigBase& config) {
  // Reject the properties rather than ignore them, since a catalog that sets
  // them presumably expects its requests to use them.
  for (const auto* property :
       {ClpPackageS3AuthProvider::kAccessKeyId,
        ClpPackageS3AuthProvider::kSecretAccessKey,
        ClpPackageS3AuthProvider::kSessionToken}) {
    VELOX_CHECK(
        false == config.valueExists(property),
        fmt::format(
            "{} can't be set when clp.s3-auth-provider is default", property));
  }
  return std::make_shared<search_lib::AwsDefaultS3CredentialsProvider>();
}

} // namespace

ClpDefaultS3AuthProvider::ClpDefaultS3AuthProvider(
    const config::ConfigBase& config)
    : ClpS3AuthProviderBase(config, createCredentialsProvider(config)) {}

} // namespace facebook::velox::connector::clp
