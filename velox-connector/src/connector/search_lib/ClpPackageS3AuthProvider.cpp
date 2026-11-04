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

#include "connector/search_lib/ClpPackageS3AuthProvider.h"

#include <memory>
#include <string>

#include "connector/search_lib/S3Credentials.h"
#include "velox/common/base/Exceptions.h"
#include "velox/common/config/Config.h"

namespace facebook::velox::connector::clp {

namespace {

std::shared_ptr<search_lib::S3CredentialsProvider> createCredentialsProvider(
    const config::ConfigBase& config) {
  search_lib::S3Credentials credentials{
      .accessKeyId =
          config.get<std::string>(ClpPackageS3AuthProvider::kAccessKeyId, ""),
      .secretAccessKey = config.get<std::string>(
          ClpPackageS3AuthProvider::kSecretAccessKey, ""),
      .sessionToken =
          config.get<std::string>(ClpPackageS3AuthProvider::kSessionToken, ""),
      .expiration = std::nullopt};
  VELOX_CHECK(
      !credentials.accessKeyId.empty(),
      fmt::format(
          "{} cannot be empty", ClpPackageS3AuthProvider::kAccessKeyId));
  VELOX_CHECK(
      !credentials.secretAccessKey.empty(),
      fmt::format(
          "{} cannot be empty", ClpPackageS3AuthProvider::kSecretAccessKey));
  return std::make_shared<search_lib::StaticS3CredentialsProvider>(
      std::move(credentials));
}

} // namespace

ClpPackageS3AuthProvider::ClpPackageS3AuthProvider(
    const config::ConfigBase& config)
    : ClpS3AuthProviderBase(config, createCredentialsProvider(config)) {}

} // namespace facebook::velox::connector::clp
