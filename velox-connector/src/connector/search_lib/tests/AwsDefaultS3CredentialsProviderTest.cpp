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

#include <gtest/gtest.h>

#include <memory>
#include <optional>
#include <string>
#include <tuple>

#include "clp_s/InputConfig.hpp"
#include "connector/search_lib/S3NetworkAuth.h"
#include "connector/search_lib/tests/ScopedEnvironment.h"

namespace facebook::velox::connector::clp::search_lib {
namespace {

/// Isolates the default credential provider chain from the host's AWS
/// configuration, so that only the environment variables that a test sets can
/// supply credentials.
class AwsDefaultS3CredentialsProviderTest : public ::testing::Test {
 protected:
  void SetUp() override {
    for (const auto* name :
         {"AWS_ACCESS_KEY_ID",
          "AWS_CONTAINER_CREDENTIALS_FULL_URI",
          "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI",
          "AWS_PROFILE",
          "AWS_ROLE_ARN",
          "AWS_SECRET_ACCESS_KEY",
          "AWS_SESSION_TOKEN",
          "AWS_WEB_IDENTITY_TOKEN_FILE"}) {
      environment_.set(name, std::nullopt);
    }
    environment_.set("AWS_CONFIG_FILE", "/nonexistent/aws/config");
    environment_.set("AWS_EC2_METADATA_DISABLED", "true");
    environment_.set(
        "AWS_SHARED_CREDENTIALS_FILE", "/nonexistent/aws/credentials");
  }

  test::ScopedEnvironment environment_;
};

TEST_F(AwsDefaultS3CredentialsProviderTest, readsTheEnvironment) {
  environment_.set("AWS_ACCESS_KEY_ID", "AKIDFROMENVIRONMENT");
  environment_.set("AWS_SECRET_ACCESS_KEY", "secret-from-environment");
  environment_.set("AWS_SESSION_TOKEN", "token-from-environment");
  auto provider = std::make_shared<AwsDefaultS3CredentialsProvider>();

  const auto credentials = provider->getCredentials();
  ASSERT_TRUE(credentials.has_value());
  EXPECT_EQ("AKIDFROMENVIRONMENT", credentials->accessKeyId);
  EXPECT_EQ("secret-from-environment", credentials->secretAccessKey);
  EXPECT_EQ("token-from-environment", credentials->sessionToken);
  EXPECT_FALSE(credentials->expiration.has_value());

  const auto url = clp_s::try_authenticate_url(
      "https://test-bucket.s3.us-east-2.amazonaws.com/archives/a",
      createS3NetworkAuthOption(provider));
  ASSERT_TRUE(url.has_value());
  EXPECT_NE(
      std::string::npos, url->find("X-Amz-Credential=AKIDFROMENVIRONMENT"));
}

TEST_F(AwsDefaultS3CredentialsProviderTest, failsWithoutCredentials) {
  auto provider = std::make_shared<AwsDefaultS3CredentialsProvider>();
  EXPECT_FALSE(provider->getCredentials().has_value());
  EXPECT_THROW(
      std::ignore = clp_s::try_authenticate_url(
          "https://test-bucket.s3.us-east-2.amazonaws.com/archives/a",
          createS3NetworkAuthOption(provider)),
      S3AuthenticationError);
}

TEST_F(AwsDefaultS3CredentialsProviderTest, providersShareTheSdk) {
  environment_.set("AWS_ACCESS_KEY_ID", "AKIDFROMENVIRONMENT");
  environment_.set("AWS_SECRET_ACCESS_KEY", "secret-from-environment");

  // Destroying one provider must leave the SDK usable by another.
  auto first = std::make_unique<AwsDefaultS3CredentialsProvider>();
  auto second = std::make_unique<AwsDefaultS3CredentialsProvider>();
  first.reset();
  const auto credentials = second->getCredentials();
  ASSERT_TRUE(credentials.has_value());
  EXPECT_EQ("AKIDFROMENVIRONMENT", credentials->accessKeyId);
}

} // namespace
} // namespace facebook::velox::connector::clp::search_lib
