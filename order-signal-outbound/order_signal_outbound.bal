import ballerina/log;
import ballerina/http;
import ballerina/config;
import ballerina/task;
import ballerina/runtime;
import ballerina/io;
import raj/orders.signal.model as model;

endpoint http:Client orderSignalDataServiceEndpoint {
    url: config:getAsString("order_signal.data.service.url")
};

endpoint http:Client ecommFrontendRefundAPIEndpoint {
    url: config:getAsString("ecomm_frontend.order_signal.api.url")
};

int count;
task:Timer? timer;
int interval = config:getAsInt("order_signal.outbound.task.interval");
int delay = config:getAsInt("order_signal.outbound.task.delay");
int maxRetryCount = config:getAsInt("order_signal.outbound.task.maxRetryCount");
int maxRecords = config:getAsInt("order_signal.outbound.task.maxRecords");
string apiKey = config:getAsString("ecomm_frontend.order_signal.api.key");


function main(string... args) {

    (function() returns error?) onTriggerFunction = doRefundETL;

    function(error) onErrorFunction = handleError;

    log:printInfo("Starting order-signal ETL");

    timer = new task:Timer(onTriggerFunction, onErrorFunction,
        interval, delay = delay);

    timer.start();
    runtime:sleep(20000000);
}

function doRefundETL() returns  error? {

    log:printInfo("Calling orderSignalDataServiceEndpoint to fetch order-signals");

    var response = orderSignalDataServiceEndpoint->get("?maxRecords=" + maxRecords
            + "&maxRetryCount=" + maxRetryCount + "&processFlag=N,E");

    match response {
        http:Response resp => {
            match resp.getJsonPayload() {
                json jsonOrderSignalArray => {  

                    model:OrderSignalDAO[] orderSignals = check <model:OrderSignalDAO[]> jsonOrderSignalArray;
                    // terminate the flow if no orderSignals found
                    if (lengthof orderSignals == 0) {
                        return;
                    }

                    log:printInfo("Fetched order-signals. Payload: \n" + jsonOrderSignalArray.toString());

                    // update process flag to P in DB so that next ETL won't fetch these again
                    boolean success = batchUpdateProcessFlagsToP(orderSignals);
                    // send refunds to Ecomm Frontend
                    if (success) {
                        // processRefundsToEcommFrontend(orderSignals);
                    }
                }
                error err => {
                    log:printError("Response from orderSignalDataServiceEndpoint is not a json : " + 
                                    err.message, err = err);
                    throw err;
                }
            }
        }
        error err => {
            log:printError("Error while calling orderSignalDataServiceEndpoint : " + 
                            err.message, err = err);
            throw err;
        }
    }

    return ();
}

// function processRefundsToEcommFrontend (model:OrderSignalDAO[] orderSignals) {

//     http:Request req = new;
//     foreach orderSignal in orderSignals {

//         int tid = orderSignal.transactionId;
//         string orderNo = orderSignal.orderNo;
//         int retryCount = orderSignal.retryCount;
       
//         json jsonPayload = untaint getRefundPayload(refund);
//         req.setJsonPayload(jsonPayload);
//         req.setHeader("api-key", apiKey);
//         string contextId = "ECOMM_" + refund.countryCode;
//         req.setHeader("Context-Id", "ECOMM_US");

//         log:printInfo("Calling ecomm-frontend to process refund for : " + orderNo + 
//                         ". Payload : " + jsonPayload.toString());

//         var response = ecommFrontendRefundAPIEndpoint->post("/" + untaint orderNo + "/cancel/async", req);

//         match response {
//             http:Response resp => {

//                 int httpCode = resp.statusCode;
//                 if (httpCode == 201) {
//                     log:printInfo("Successfully processed refund for : " + orderNo + " to ecomm-frontend");
//                     updateProcessFlag(tid, retryCount, "C", "sent to ecomm-frontend");
//                 } else {
//                     match resp.getTextPayload() {
//                         string payload => {
//                             log:printInfo("Failed to process refund for : " + orderNo +
//                                     " to ecomm-frontend. Error code : " + httpCode + ". Error message : " + payload);
//                             updateProcessFlag(tid, retryCount + 1, "E", payload);
//                         }
//                         error err => {
//                             log:printInfo("Failed to process refund for : " + orderNo +
//                                     " to ecomm-frontend. Error code : " + httpCode);
//                             updateProcessFlag(tid, retryCount + 1, "E", "unknown error");
//                         }
//                     }
//                 }
//             }
//             error err => {
//                 log:printError("Error while calling ecomm-frontend for refund for : " + orderNo, err = err);
//                 updateProcessFlag(tid, retryCount + 1, "E", "unknown error");
//             }
//         }
//     }
// }

// function getRefundPayload(model:OrderSignalDAO refund) returns (json) {

//     json refundPayload ;

//     // convert string 7,8,9 to json ["7","8","9"]
//     string itemIds = refund.itemIds;
//     string[] itemIdsArray = itemIds.split(",");
//     json itemIdsJsonArray = check <json> itemIdsArray;

//     // default is cancel payload
//     refundPayload = {
//         "type": "AUTH_CANCEL",
//         "invoiceId": refund.invoiceId,
//         "currency": refund.countryCode,
//         "countryCode": refund.countryCode,
//         "comments": refund.countryCode,
//         "amount": refund.countryCode,
//         "itemIds": itemIdsJsonArray
//     };

//     string kind = <string> refund.kind;
//     if (kind == "REFUND" || kind == "CREDITMEMO") {        
//         refundPayload["creditMemoId"] = refund.creditMemoId;
//         refundPayload["settlementId"] = refund.settlementId;
//         refundPayload["type"] = "REFUND";
//         refundPayload["totalAmount"] = refund.countryCode;

//         if (kind == "REFUND") {
//             refundPayload["requestId"] = refund.countryCode; // should be timestamp
//         } else {
//             refundPayload["requestId"] = refund.creditMemoId;
//         }
//     } 

//     return refundPayload;
// }

function batchUpdateProcessFlagsToP (model:OrderSignalDAO[] orderSignals) returns boolean {

    json batchUpdateProcessFlagsPayload;
    foreach i, orderSignal in orderSignals {
        json updateProcessFlagPayload = {
            "transactionId": orderSignal.transactionId,
            "retryCount": orderSignal.retryCount,
            "processFlag": "P"           
        };
        batchUpdateProcessFlagsPayload.orderSignals[i] = updateProcessFlagPayload;
    }

    http:Request req = new;
    req.setJsonPayload(untaint batchUpdateProcessFlagsPayload);

    var response = orderSignalDataServiceEndpoint->put("/process-flag/batch/", req);

    boolean success;
    match response {
        http:Response resp => {
            if (resp.statusCode == 202) {
                success = true;
            }
        }
        error err => {
            log:printError("Error while calling orderSignalDataServiceEndpoint.batchUpdateProcessFlags", err = err);
        }
    }

    return success;
}

function updateProcessFlag(int tid, int retryCount, string processFlag, string errorMessage) {

    json updateOrderSignal = {
        "transactionId": tid,
        "processFlag": processFlag,
        "retryCount": retryCount,
        "errorMessage": errorMessage
    };

    http:Request req = new;
    req.setJsonPayload(untaint updateOrderSignal);

    var response = orderSignalDataServiceEndpoint->put("/process-flag/", req);

    match response {
        http:Response resp => {
            int httpCode = resp.statusCode;
            if (httpCode == 202) {
                if (processFlag == "E" && retryCount > maxRetryCount) {
                    notifyOperation();
                }
            }
        }
        error err => {
            log:printError("Error while calling orderSignalDataServiceEndpoint", err = err);
        }
    }
}

function notifyOperation()  {
    // sending email alerts
    log:printInfo("Notifying operations");
}

function handleError(error e) {
    log:printError("Error in processing order-signals to ecomm-frontend", err = e);
    // I don't want to stop the ETL if backend is down
    // timer.stop();
}