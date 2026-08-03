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

namespace facebook::velox::config {
class ConfigBase;
} // namespace facebook::velox::config

namespace facebook::velox::connector::clp {

class ClpS3AuthProviderBase;

class ClpConfig {
 public:
  enum class S3AuthProvider {
    kClpPackage,
  };

  enum class StorageType {
    kFs,
    kS3,
  };

  static constexpr const char* kAuthProvider = "clp.s3-auth-provider";
  static constexpr const char* kStorageType = "clp.storage-type";
  static constexpr const char* kCaseInsensitive = "clp.case-insensitive";

  /// Name of the per-catalog session property that overrides
  /// `clp.case-insensitive`. Set on the coordinator via
  /// `SET SESSION <catalog>.case_insensitive = true` and forwarded to workers
  /// in the session's catalog properties.
  ///
  /// NOTE: presto_cpp also merges X-Presto-Extra-Credential pairs into the
  /// same per-catalog session config map, so an extra credential with this
  /// key incidentally acts as a session-level override too. This is upstream
  /// behavior, not a supported configuration route.
  static constexpr const char* kCaseInsensitiveSession = "case_insensitive";

  explicit ClpConfig(std::shared_ptr<const config::ConfigBase> config);

  [[nodiscard]] const std::shared_ptr<const config::ConfigBase>& config()
      const {
    return config_;
  }

  StorageType storageType() const;
  std::shared_ptr<ClpS3AuthProviderBase> s3AuthProvider() const;
  bool caseInsensitive() const;

 private:
  std::shared_ptr<const config::ConfigBase> config_;
  std::shared_ptr<ClpS3AuthProviderBase> s3AuthProvider_;
  StorageType storageType_;
  bool caseInsensitive_;
};

} // namespace facebook::velox::connector::clp
