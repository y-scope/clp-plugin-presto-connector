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

#include <cstdlib>
#include <map>
#include <optional>
#include <string>

namespace facebook::velox::connector::clp::search_lib::test {

/// Sets or unsets environment variables, restoring their original values when
/// destroyed.
class ScopedEnvironment {
 public:
  ScopedEnvironment() = default;

  ~ScopedEnvironment() {
    for (const auto& [name, value] : originalValues_) {
      apply(name, value);
    }
  }

  ScopedEnvironment(const ScopedEnvironment&) = delete;
  ScopedEnvironment& operator=(const ScopedEnvironment&) = delete;

  /// @param name
  /// @param value The value to set, or `std::nullopt` to unset the variable.
  void set(const std::string& name, const std::optional<std::string>& value) {
    originalValues_.try_emplace(name, get(name));
    apply(name, value);
  }

  /// @return The variable's current value, or `std::nullopt` if it's unset.
  static std::optional<std::string> get(const std::string& name) {
    const auto* value = std::getenv(name.c_str());
    if (nullptr == value) {
      return std::nullopt;
    }
    return std::string{value};
  }

 private:
  static void apply(
      const std::string& name,
      const std::optional<std::string>& value) {
    if (value.has_value()) {
      ::setenv(name.c_str(), value->c_str(), 1);
    } else {
      ::unsetenv(name.c_str());
    }
  }

  std::map<std::string, std::optional<std::string>> originalValues_;
};

} // namespace facebook::velox::connector::clp::search_lib::test
