package com.facebook.presto.plugin.clp;

import static com.facebook.presto.common.ErrorType.EXTERNAL;
import static com.facebook.presto.common.ErrorType.USER_ERROR;

import com.facebook.presto.common.ErrorCode;
import com.facebook.presto.common.ErrorType;
import com.facebook.presto.spi.ErrorCodeSupplier;

public enum ClpErrorCode implements ErrorCodeSupplier {
    CLP_PUSHDOWN_UNSUPPORTED_EXPRESSION(0, EXTERNAL),
    CLP_UNSUPPORTED_METADATA_SOURCE(1, EXTERNAL),
    CLP_UNSUPPORTED_SPLIT_SOURCE(2, EXTERNAL),
    CLP_UNSUPPORTED_TYPE(3, EXTERNAL),
    CLP_UNSUPPORTED_CONFIG_OPTION(4, EXTERNAL),

    CLP_SPLIT_FILTER_CONFIG_NOT_FOUND(10, USER_ERROR),
    CLP_MANDATORY_SPLIT_FILTER_NOT_VALID(11, USER_ERROR),
    CLP_UNSUPPORTED_SPLIT_FILTER_SOURCE(12, EXTERNAL);

    private final ErrorCode errorCode;

    ClpErrorCode(int code, ErrorType type) {
        errorCode = new ErrorCode(code + 0x0400_0000, name(), type);
    }

    @Override
    public ErrorCode toErrorCode() {
        return errorCode;
    }
}
