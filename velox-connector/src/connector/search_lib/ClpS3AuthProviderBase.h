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

#include <memory>
#include <string>
#include <string_view>

#include "clp_s/InputConfig.hpp"

namespace facebook::velox::config {
class ConfigBase;
} // namespace facebook::velox::config

namespace facebook::velox::connector::clp {

namespace search_lib {
class S3CredentialsProvider;
} // namespace search_lib

/// Locates a catalog's splits in S3 and authenticates the catalog's requests
/// for them. Each catalog has its own instance, so its credentials never affect
/// another catalog's requests or the process's environment.
class ClpS3AuthProviderBase {
 public:
  static constexpr const char* kBucket = "clp.s3-bucket";
  static constexpr const char* kEndPoint = "clp.s3-end-point";

  virtual ~ClpS3AuthProviderBase() = default;

  /// Constructs the actual S3 URL so that CLP-s can access the split.
  ///
  /// @param splitPath The current path stored in the split to add.
  /// @return The constructed S3 URL.
  std::string constructS3Url(std::string_view splitPath) const;

  /// @return The option with which CLP-s authenticates this catalog's S3
  /// requests. Copies of it keep the catalog's credentials provider alive.
  const clp_s::NetworkAuthOption& networkAuthOption() const {
    return networkAuthOption_;
  }

 protected:
  /// @param config The catalog's configuration.
  /// @param credentialsProvider Supplies the credentials that sign the
  /// catalog's S3 requests.
  ClpS3AuthProviderBase(
      const config::ConfigBase& config,
      std::shared_ptr<search_lib::S3CredentialsProvider> credentialsProvider);

 private:
  std::string bucket_;
  std::string endPoint_;
  clp_s::NetworkAuthOption networkAuthOption_;
};

} // namespace facebook::velox::connector::clp
