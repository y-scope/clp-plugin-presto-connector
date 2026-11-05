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

#include "connector/search_lib/S3NetworkAuth.h"

#include <gtest/gtest.h>

#include <atomic>
#include <chrono>
#include <ctime>
#include <functional>
#include <iomanip>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <tuple>
#include <vector>

#include "clp_s/InputConfig.hpp"
#include "connector/search_lib/S3Credentials.h"
#include "connector/search_lib/tests/ScopedEnvironment.h"

namespace facebook::velox::connector::clp::search_lib {
namespace {

using std::chrono::system_clock;

constexpr std::string_view kUrl{
    "https://test-bucket.s3.us-east-2.amazonaws.com/archives/default/abc123"};

// Distinctive values that must never appear in an error message.
constexpr std::string_view kAccessKeyId{"AKIDSECRETMARKER"};
constexpr std::string_view kSecretAccessKey{"secret-access-key-marker"};
constexpr std::string_view kSessionToken{"session-token-marker"};

/// Supplies credentials from a callback, counting the calls.
class CallbackCredentialsProvider : public S3CredentialsProvider {
 public:
  explicit CallbackCredentialsProvider(
      std::function<std::optional<S3Credentials>()> callback)
      : callback_(std::move(callback)) {}

  std::optional<S3Credentials> getCredentials() override {
    ++numCalls_;
    return callback_();
  }

  size_t numCalls() const {
    return numCalls_;
  }

 private:
  std::function<std::optional<S3Credentials>()> callback_;
  std::atomic<size_t> numCalls_{0};
};

S3Credentials makeCredentials(
    std::optional<system_clock::time_point> expiration = std::nullopt) {
  return S3Credentials{
      .accessKeyId = std::string{kAccessKeyId},
      .secretAccessKey = std::string{kSecretAccessKey},
      .sessionToken = std::string{kSessionToken},
      .expiration = expiration};
}

/// @return The value of the query parameter `name` in `url`, if any.
std::optional<std::string> getQueryParameter(
    std::string_view url,
    std::string_view name) {
  const auto queryBegin = url.find('?');
  if (std::string_view::npos == queryBegin) {
    return std::nullopt;
  }
  std::stringstream query{std::string{url.substr(queryBegin + 1)}};
  std::string parameter;
  while (std::getline(query, parameter, '&')) {
    if (parameter.size() > name.size() && parameter.starts_with(name) &&
        '=' == parameter[name.size()]) {
      return parameter.substr(name.size() + 1);
    }
  }
  return std::nullopt;
}

/// @return The access key ID in the `X-Amz-Credential` parameter of `url`.
std::string getAccessKeyId(std::string_view url) {
  const auto credential = getQueryParameter(url, "X-Amz-Credential");
  EXPECT_TRUE(credential.has_value());
  // The parameter is `<access-key-id>/<scope>`, with '/' percent-encoded.
  return credential.value_or("").substr(0, credential.value_or("").find("%2F"));
}

/// @return When the presigned `url` expires.
system_clock::time_point getUrlExpiration(std::string_view url) {
  const auto date = getQueryParameter(url, "X-Amz-Date");
  const auto expires = getQueryParameter(url, "X-Amz-Expires");
  EXPECT_TRUE(date.has_value());
  EXPECT_TRUE(expires.has_value());
  std::tm signingTime{};
  std::istringstream{date.value_or("")} >>
      std::get_time(&signingTime, "%Y%m%dT%H%M%SZ");
  return system_clock::from_time_t(::timegm(&signingTime)) +
      std::chrono::seconds{std::stoll(expires.value_or("0"))};
}

/// @return The presigned `kUrl`.
/// @throw S3AuthenticationError if the URL can't be presigned.
std::string presign(const clp_s::NetworkAuthOption& networkAuthOption) {
  auto url = clp_s::try_authenticate_url(kUrl, networkAuthOption);
  if (false == url.has_value()) {
    throw std::runtime_error("CLP failed to presign the URL.");
  }
  return std::move(url.value());
}

/// Expects authenticating a request with `networkAuthOption` to fail with an
/// `S3AuthenticationError` that doesn't reveal any of the test's credentials.
void expectAuthenticationError(
    const clp_s::NetworkAuthOption& networkAuthOption) {
  try {
    presign(networkAuthOption);
    ADD_FAILURE() << "Expected an S3AuthenticationError.";
  } catch (const S3AuthenticationError& e) {
    const std::string_view message{e.what()};
    EXPECT_FALSE(message.empty());
    for (const auto secret : {kAccessKeyId, kSecretAccessKey, kSessionToken}) {
      EXPECT_EQ(std::string_view::npos, message.find(secret)) << message;
    }
    EXPECT_EQ(std::string_view::npos, message.find("test-bucket")) << message;
  }
}

TEST(S3NetworkAuthTest, presignsWithTheProvidersCredentials) {
  auto provider = std::make_shared<CallbackCredentialsProvider>(
      [] { return makeCredentials(); });
  const auto networkAuthOption = createS3NetworkAuthOption(provider);

  EXPECT_EQ(clp_s::AuthMethod::S3PresignedUrlV4, networkAuthOption.method);
  for (size_t i = 0; i < 3; ++i) {
    const auto url = presign(networkAuthOption);
    EXPECT_EQ(kAccessKeyId, getAccessKeyId(url));
    EXPECT_EQ(kSessionToken, getQueryParameter(url, "X-Amz-Security-Token"));
    EXPECT_EQ(
        std::to_string(kPresignedUrlLifetime.count()),
        getQueryParameter(url, "X-Amz-Expires"));
  }
  // Each request gets a fresh snapshot.
  EXPECT_EQ(size_t{3}, provider->numCalls());
}

TEST(S3NetworkAuthTest, omitsTheSessionTokenOfLongTermCredentials) {
  auto credentials = makeCredentials();
  credentials.sessionToken.clear();
  const auto networkAuthOption = createS3NetworkAuthOption(
      std::make_shared<StaticS3CredentialsProvider>(credentials));

  const auto url = presign(networkAuthOption);
  EXPECT_EQ(kAccessKeyId, getAccessKeyId(url));
  EXPECT_FALSE(getQueryParameter(url, "X-Amz-Security-Token").has_value());
}

TEST(S3NetworkAuthTest, urlsExpireBeforeTheirCredentials) {
  const auto minimumLifetime =
      kPresignedUrlLifetime + kCredentialExpirationMargin;
  for (const auto remainingLifetime :
       {std::chrono::seconds{std::chrono::hours{1}},
        minimumLifetime + std::chrono::seconds{3}}) {
    const auto expiration = system_clock::now() + remainingLifetime;
    const auto networkAuthOption = createS3NetworkAuthOption(
        std::make_shared<StaticS3CredentialsProvider>(
            makeCredentials(expiration)));

    const auto url = presign(networkAuthOption);
    EXPECT_LE(getUrlExpiration(url), expiration);
  }

  for (const auto remainingLifetime :
       {minimumLifetime - std::chrono::seconds{1},
        kPresignedUrlLifetime,
        std::chrono::seconds{0},
        std::chrono::seconds{-1}}) {
    SCOPED_TRACE(remainingLifetime.count());
    expectAuthenticationError(createS3NetworkAuthOption(
        std::make_shared<StaticS3CredentialsProvider>(
            makeCredentials(system_clock::now() + remainingLifetime))));
  }
}

TEST(S3NetworkAuthTest, rejectsMissingOrIncompleteCredentials) {
  // Valid credentials in the environment make any fallback to them observable.
  test::ScopedEnvironment environment;
  environment.set("AWS_ACCESS_KEY_ID", "AKIDENVIRONMENT");
  environment.set("AWS_SECRET_ACCESS_KEY", "environment-secret");
  environment.set("AWS_SESSION_TOKEN", std::nullopt);

  std::vector<std::function<std::optional<S3Credentials>()>> callbacks{
      []() -> std::optional<S3Credentials> { return std::nullopt; },
      [] {
        auto credentials = makeCredentials();
        credentials.accessKeyId.clear();
        return credentials;
      },
      [] {
        auto credentials = makeCredentials();
        credentials.secretAccessKey.clear();
        return credentials;
      },
  };
  for (auto& callback : callbacks) {
    expectAuthenticationError(createS3NetworkAuthOption(
        std::make_shared<CallbackCredentialsProvider>(std::move(callback))));
  }
}

TEST(S3NetworkAuthTest, recoversWhenTheProviderRecovers) {
  size_t numCalls = 0;
  auto provider = std::make_shared<CallbackCredentialsProvider>(
      [&numCalls]() -> std::optional<S3Credentials> {
        switch (numCalls++) {
          case 0:
            throw std::runtime_error(
                "Refresh failed for " + std::string{kSecretAccessKey});
          case 1:
            return std::nullopt;
          case 2:
            // A stale cached snapshot after the failed refreshes.
            return makeCredentials(
                system_clock::now() - std::chrono::seconds{1});
          default:
            return makeCredentials(system_clock::now() + std::chrono::hours{1});
        }
      });
  const auto networkAuthOption = createS3NetworkAuthOption(provider);

  for (size_t i = 0; i < 3; ++i) {
    expectAuthenticationError(networkAuthOption);
  }
  for (size_t i = 0; i < 2; ++i) {
    EXPECT_EQ(kAccessKeyId, getAccessKeyId(presign(networkAuthOption)));
  }
}

TEST(S3NetworkAuthTest, presignsConsistentSnapshotsWhileRefreshing) {
  // Rotates to new credentials every `kCallsPerGeneration` calls, as a refresh
  // would, while other threads presign requests.
  constexpr size_t kCallsPerGeneration = 50;
  std::mutex mutex;
  size_t numCalls = 0;
  auto provider = std::make_shared<CallbackCredentialsProvider>([&] {
    std::lock_guard lock{mutex};
    const auto generation = std::to_string(numCalls++ / kCallsPerGeneration);
    return S3Credentials{
        .accessKeyId = "AKIDGENERATION" + generation,
        .secretAccessKey = "secret-" + generation,
        .sessionToken = "token-" + generation,
        .expiration = system_clock::now() + std::chrono::hours{1}};
  });
  const auto networkAuthOption = createS3NetworkAuthOption(provider);

  constexpr size_t kNumThreads = 8;
  constexpr size_t kNumRequestsPerThread = 100;
  std::vector<std::vector<std::string>> urls(kNumThreads);
  std::vector<std::thread> threads;
  for (size_t i = 0; i < kNumThreads; ++i) {
    // Each thread uses its own copy of the option, as each reader does.
    threads.emplace_back([&urls, i, networkAuthOption] {
      for (size_t j = 0; j < kNumRequestsPerThread; ++j) {
        urls[i].push_back(presign(networkAuthOption));
      }
    });
  }
  for (auto& thread : threads) {
    thread.join();
  }

  std::set<std::string> generations;
  for (const auto& threadUrls : urls) {
    ASSERT_EQ(kNumRequestsPerThread, threadUrls.size());
    for (const auto& url : threadUrls) {
      const auto accessKeyId = getAccessKeyId(url);
      ASSERT_TRUE(accessKeyId.starts_with("AKIDGENERATION")) << accessKeyId;
      const auto generation = accessKeyId.substr(sizeof("AKIDGENERATION") - 1);
      // Each URL is signed with a single snapshot.
      EXPECT_EQ(
          "token-" + generation,
          getQueryParameter(url, "X-Amz-Security-Token"));
      generations.insert(generation);
    }
  }
  EXPECT_EQ(kNumThreads * kNumRequestsPerThread, provider->numCalls());
  EXPECT_EQ(
      kNumThreads * kNumRequestsPerThread / kCallsPerGeneration,
      generations.size());
}

TEST(S3NetworkAuthTest, keepsCatalogsIsolated) {
  const std::vector<std::string> environmentVariables{
      "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"};
  test::ScopedEnvironment environment;
  environment.set("AWS_ACCESS_KEY_ID", "AKIDENVIRONMENT");
  environment.set("AWS_SECRET_ACCESS_KEY", "environment-secret");
  environment.set("AWS_SESSION_TOKEN", std::nullopt);
  std::vector<std::optional<std::string>> originalValues;
  for (const auto& name : environmentVariables) {
    originalValues.push_back(test::ScopedEnvironment::get(name));
  }

  const auto makeCatalog = [](const std::string& name) {
    return createS3NetworkAuthOption(
        std::make_shared<StaticS3CredentialsProvider>(S3Credentials{
            .accessKeyId = "AKID" + name,
            .secretAccessKey = "secret-" + name,
            .sessionToken = "token-" + name,
            .expiration = std::nullopt}));
  };
  const auto catalogA = makeCatalog("CATALOGA");
  const auto catalogB = makeCatalog("CATALOGB");

  std::thread threadA{[&catalogA] {
    for (size_t i = 0; i < 100; ++i) {
      EXPECT_EQ("AKIDCATALOGA", getAccessKeyId(presign(catalogA)));
    }
  }};
  std::thread threadB{[&catalogB] {
    for (size_t i = 0; i < 100; ++i) {
      const auto url = presign(catalogB);
      EXPECT_EQ("AKIDCATALOGB", getAccessKeyId(url));
      EXPECT_EQ(
          "token-CATALOGB", getQueryParameter(url, "X-Amz-Security-Token"));
    }
  }};
  threadA.join();
  threadB.join();

  for (size_t i = 0; i < environmentVariables.size(); ++i) {
    EXPECT_EQ(
        originalValues[i],
        test::ScopedEnvironment::get(environmentVariables[i]))
        << environmentVariables[i];
  }
}

TEST(S3NetworkAuthTest, authenticationErrorsEscapeReaderCreation) {
  const auto networkAuthOption = createS3NetworkAuthOption(
      std::make_shared<CallbackCredentialsProvider>(
          []() -> std::optional<S3Credentials> {
            throw std::runtime_error(std::string{kSecretAccessKey});
          }));
  const clp_s::Path path{
      .source = clp_s::InputSource::Network, .path = std::string{kUrl}};

  // CLP must not turn the failure into a missing reader, which the connector
  // can't distinguish from other read failures.
  try {
    std::ignore = clp_s::try_create_reader(path, networkAuthOption);
    ADD_FAILURE() << "Expected an S3AuthenticationError.";
  } catch (const S3AuthenticationError& e) {
    EXPECT_EQ(
        std::string_view::npos,
        std::string_view{e.what()}.find(kSecretAccessKey));
  }
}

TEST(S3NetworkAuthTest, rejectsANullProvider) {
  EXPECT_THROW(
      std::ignore = createS3NetworkAuthOption(nullptr), std::invalid_argument);
}

} // namespace
} // namespace facebook::velox::connector::clp::search_lib
