import ballerina/io;
import ballerina/http;
import ballerina/config;
import ballerina/log;
import ballerina/sql;
import ballerina/mime;
import raj/orders.signal.model as model;

type orderSignalBatchType string|int|float;

endpoint mysql:Client orderSignalDB {
    host: config:getAsString("order_signal.db.host"),
    port: config:getAsInt("order_signal.db.port"),
    name: config:getAsString("order_signal.db.name"),
    username: config:getAsString("order_signal.db.username"),
    password: config:getAsString("order_signal.db.password"),
    poolOptions: { maximumPoolSize: 5 },
    dbOptions: { useSSL: false, serverTimezone:"UTC" }
};

public function addOrderSignal (http:Request req, model:OrderSignalDAO orderSignal) returns http:Response {

    string sqlString = "INSERT INTO order_signal(CTX,STATUS,ORDER_NO,PARTNER_ID,
        REQUEST,PROCESS_FLAG,RETRY_COUNT,ERROR_MESSAGE) 
        VALUES (?,?,?,?,?,?,?,?)";

    log:printInfo("Calling orderSignalDB->insert for order : " + orderSignal.orderNo);

    boolean isSuccessful;
    transaction with retries = 5, oncommit = onCommitFunction, onabort = onAbortFunction {                              

        string base64Request = check mime:base64EncodeString(orderSignal.request);

        var ret = orderSignalDB->update(sqlString, orderSignal.context, orderSignal.signal, 
                    orderSignal.orderNo, orderSignal.partnerId, base64Request, orderSignal.processFlag, 
                    orderSignal.retryCount, orderSignal.errorMessage);

        match ret {
            int insertedRows => {
                if (insertedRows < 1) {
                    log:printError("Calling orderSignalDB->insert for order : " + orderSignal.orderNo 
                        + " failed", err = ());
                    isSuccessful = false;
                    abort;
                } else {
                    log:printInfo("Calling orderSignalDB->insert order : " + orderSignal.orderNo + " succeeded");
                    isSuccessful = true;
                }
            }
            error err => {
                log:printError("Calling orderSignalDB->insert for order : " + orderSignal.orderNo 
                    + " failed", err = err);
                isSuccessful = false;    
                retry;
            }
        }        
    }  

    json resJson;
    int statusCode;
    if (isSuccessful) {
        statusCode = http:OK_200;
        resJson = { "Status": "Order-signal is inserted to the staging database for order : " 
                    + orderSignal.orderNo };
    } else {
        statusCode = http:INTERNAL_SERVER_ERROR_500;
        resJson = { "Status": "Failed to insert order-signal to the staging database for order : " 
                    + orderSignal.orderNo };
    }
    
    http:Response res = new;
    res.setJsonPayload(resJson);
    res.statusCode = statusCode;
    return res;
}

public function updateProcessFlag (http:Request req, model:OrderSignalDAO orderSignal)
                    returns http:Response {

    log:printInfo("Calling orderSignalDB->updateProcessFlag for tid : " + orderSignal.transactionId + 
                    ", order : " + orderSignal.orderNo);
    string sqlString = "UPDATE order_signal SET PROCESS_FLAG = ?, RETRY_COUNT = ?, ERROR_MESSAGE = ?, 
                            LAST_UPDATED_TIME = CURRENT_TIMESTAMP where TRANSACTION_ID = ?";

    json resJson;
    boolean isSuccessful;
    transaction with retries = 5, oncommit = onCommitFunction, onabort = onAbortFunction {                              

        var ret = orderSignalDB->update(sqlString, orderSignal.processFlag, orderSignal.retryCount, 
                                    orderSignal.errorMessage, orderSignal.transactionId);

        match ret {
            int updatedRows => {
                if (updatedRows < 1) {
                    log:printError("Calling orderSignalDB->updateProcessFlag for tid : " + orderSignal.transactionId + 
                                ", order : " + orderSignal.orderNo + " failed", err = ());
                    isSuccessful = false;
                    abort;
                } else {
                    log:printInfo("Calling orderSignalDB->updateProcessFlag for tid : " + orderSignal.transactionId + 
                                ", order : " + orderSignal.orderNo + " succeeded");
                    isSuccessful = true;
                }
            }
            error err => {
                log:printError("Calling orderSignalDB->updateProcessFlag for tid : " + orderSignal.transactionId +
                    ", order : " + orderSignal.orderNo + " failed", err = err);
                isSuccessful = false;
                retry;
            }
        } 

    }     

    int statusCode;
    if (isSuccessful) {
        resJson = { "Status": "ProcessFlag is updated for order : " + orderSignal.transactionId };
        statusCode = http:ACCEPTED_202;
    } else {
        resJson = { "Status": "Failed to update ProcessFlag for order : " + orderSignal.transactionId };
        statusCode = http:INTERNAL_SERVER_ERROR_500;
    }

    http:Response res = new;
    res.setJsonPayload(resJson);
    res.statusCode = statusCode;
    return res;
}

public function batchUpdateProcessFlag (http:Request req, model:OrderSignalsDAO orderSignals)
                    returns http:Response {
    io:println(orderSignals);
    orderSignalBatchType[][] orderSignalBatches;
    foreach i, orderSignal in orderSignals.orderSignals {
        orderSignalBatchType[] sig = [orderSignal.processFlag, orderSignal.retryCount, 
                                    orderSignal.errorMessage, orderSignal.transactionId];
        orderSignalBatches[i] = sig;
    }

    string sqlString = "UPDATE order_signal SET PROCESS_FLAG = ?, RETRY_COUNT = ?, ERROR_MESSAGE = ?, 
                            LAST_UPDATED_TIME = CURRENT_TIMESTAMP where TRANSACTION_ID = ?";    

    log:printInfo("Calling orderSignalDB->batchUpdateProcessFlag");
    
    json resJson;
    boolean isSuccessful;
    transaction with retries = 5, oncommit = onCommitFunction, onabort = onAbortFunction {                              

        var retBatch = orderSignalDB->batchUpdate(sqlString, ... orderSignalBatches);
        match retBatch {
            int[] counts => {
                foreach count in counts {
                    if (count < 1) {
                        log:printError("Calling orderSignalDB->batchUpdateProcessFlag failed", err = ());
                        isSuccessful = false;
                        abort;
                    } else {
                        log:printInfo("Calling orderSignalDB->batchUpdateProcessFlag succeeded");
                        isSuccessful = true;
                    }
                }
            }
            error err => {
                log:printError("Calling orderSignalDB->batchUpdateProcessFlag failed", err = err);
                retry;
            }
        }      
    }     

    int statusCode;
    if (isSuccessful) {
        resJson = { "Status": "ProcessFlags updated"};
        statusCode = http:ACCEPTED_202;
    } else {
        resJson = { "Status": "ProcessFlags not updated" };
        statusCode = http:INTERNAL_SERVER_ERROR_500;
    }

    http:Response res = new;
    res.setJsonPayload(resJson);
    res.statusCode = statusCode;
    return res;
}

public function getOrderSignals (http:Request req)
                    returns http:Response {

    int retryCount = config:getAsInt("order_signal.data.service.default.retryCount");
    int resultsLimit = config:getAsInt("order_signal.data.service.default.resultsLimit");
    string processFlag = config:getAsString("order_signal.data.service.default.processFlag");

    map<string> params = req.getQueryParams();

    if (params.hasKey("processFlag")) {
        processFlag = params.processFlag;
    }

    if (params.hasKey("maxRetryCount")) {
        match <int> params.maxRetryCount {
            int n => {
                retryCount = n;
            }
            error err => {
                throw err;
            }
        }
    }

    if (params.hasKey("maxRecords")) {
        match <int> params.maxRecords {
            int n => {
                resultsLimit = n;
            }
            error err => {
                throw err;
            }
        }
    }

    string sqlString = "select * from order_signal where PROCESS_FLAG in ( ? ) 
        and RETRY_COUNT <= ? order by TRANSACTION_ID asc limit ?";

    string[] processFlagArray = processFlag.split(",");
    sql:Parameter processFlagPara = { sqlType: sql:TYPE_VARCHAR, value: processFlagArray };

    var ret = orderSignalDB->select(sqlString, model:OrderSignalDAO, loadToMemory = true, processFlagPara, retryCount, resultsLimit);

    http:Response resp = new;
    json[] jsonReturnValue;
    match ret {
        table<model:OrderSignalDAO> tableOrderSignaDAO => {
            foreach orderSignalRec in tableOrderSignaDAO {
                orderSignalRec.request = check mime:base64DecodeString(orderSignalRec.request);
                jsonReturnValue[lengthof jsonReturnValue] = check <json> orderSignalRec;
            }
            resp.setJsonPayload(untaint jsonReturnValue);
            resp.statusCode = http:OK_200;
        }
        error err => {
            json respPayload = { "Status": "Internal Server Error", "Error": err.message };
            resp.setJsonPayload(untaint respPayload);
            resp.statusCode = http:INTERNAL_SERVER_ERROR_500;
        }
    }

    return resp;
}

function onCommitFunction(string transactionId) {
    log:printInfo("Transaction: " + transactionId + " committed");
}

function onAbortFunction(string transactionId) {
    log:printInfo("Transaction: " + transactionId + " aborted");
}