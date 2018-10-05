public type OrderSignalDAO record {
    int transactionId,
    string context,
    string signal,
    string orderNo,
    string partnerId,
    string request,
    string processFlag,
    int retryCount,
    string errorMessage,
    string createdTime,
    string lastUpdatedTime,
};

public type OrderSignalsDAO record {
    OrderSignalDAO[] orderSignals,
};