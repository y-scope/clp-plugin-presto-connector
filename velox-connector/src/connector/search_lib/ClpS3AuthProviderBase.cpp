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

#include "connector/search_lib/ClpS3AuthProviderBase.h"
#include "connector/search_lib/S3Credentials.h"
#include "connector/search_lib/S3NetworkAuth.h"
#include "velox/common/base/Exceptions.h"
#include "velox/common/config/Config.h"

namespace facebook::velox::connector::clp {

ClpS3AuthProviderBase::ClpS3AuthProviderBase(
    const config::ConfigBase& config,
    std::shared_ptr<search_lib::S3CredentialsProvider> credentialsProvider) {
  endPoint_ = config.get<std::string>(kEndPoint, "");
  VELOX_CHECK(!endPoint_.empty(), fmt::format("{} cannot be empty", kEndPoint));
  if ('/' == endPoint_.back()) {
    endPoint_.pop_back();
  }

  bucket_ = config.get<std::string>(kBucket, "");

  networkAuthOption_ =
      search_lib::createS3NetworkAuthOption(std::move(credentialsProvider));
}

std::string ClpS3AuthProviderBase::constructS3Url(
    std::string_view splitPath) const {
  VELOX_CHECK(!splitPath.empty(), "splitPath cannot be empty");
  // For URLs where the bucket is already encoded in the endpoint (e.g., AWS S3
  // virtual-hosted style: https://bucket.s3.region.amazonaws.com).
  if (bucket_.empty()) {
    return fmt::format("{}/{}", endPoint_, splitPath);
  }
  return fmt::format("{}/{}/{}", endPoint_, bucket_, splitPath);
}

} // namespace facebook::velox::connector::clp
