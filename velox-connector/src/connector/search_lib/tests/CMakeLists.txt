# These tests link CLP and the AWS SDK, but not Velox, which only the Presto worker provides at
# runtime.
add_executable(clp-connector-s3-auth-tests
        AwsDefaultS3CredentialsProviderTest.cpp
        S3NetworkAuthTest.cpp
)

target_link_libraries(clp-connector-s3-auth-tests
        PRIVATE
        clp_connector_s3_auth
        clp_s::io
        GTest::gtest_main
)

gtest_discover_tests(clp-connector-s3-auth-tests)
