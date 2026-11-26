/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
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

/// Authenticates S3 requests with the access key configured in the catalog
/// (`clp.s3-auth-provider=clp_package`).
class ClpPackageS3AuthProvider : public ClpS3AuthProviderBase {
 public:
  static constexpr const char* kAccessKeyId = "clp.s3-access-key-id";
  static constexpr const char* kSecretAccessKey = "clp.s3-secret-access-key";
  static constexpr const char* kSessionToken = "clp.s3-session-token";

  explicit ClpPackageS3AuthProvider(const config::ConfigBase& config);
};

} // namespace facebook::velox::connector::clp
