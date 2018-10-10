import ballerina/log;
import ballerina/http;
import ballerina/config;
import ballerina/task;
import ballerina/runtime;
import ballerina/io;
import ballerina/math;
import raj/orders.signal.model as model;

endpoint http:Client orderSignalDataServiceEndpoint {
    url: config:getAsString("order_signal.data.service.url")
};

endpoint http:Client ecommFrontendOrderSignalAPIEndpoint {
    url: config:getAsString("ecomm_frontend.order_signal.api.url")
};

endpoint http:Client notificationServiceEndpoint {
    url: config:getAsString("notification.service.url")
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
                    // update process flag to P in DB so that next ETL won't fetch these again
                    boolean success = batchUpdateProcessFlagsToP(orderSignals);
                    // send order-signals to Ecomm Frontend
                    if (success) {
                        processRefundsToEcommFrontend(orderSignals);
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

function processRefundsToEcommFrontend (model:OrderSignalDAO[] orderSignals) {

    http:Request req = new;
    foreach orderSignal in orderSignals {

        int tid = orderSignal.transactionId;
        string orderNo = orderSignal.orderNo;
        int retryCount = orderSignal.retryCount;
        string contextId = orderSignal.context;

        try {

            json jsonPayload = untaint getOrderSignalPayload(orderSignal);
            io:println(jsonPayload);
            req.setJsonPayload(jsonPayload);
            req.setHeader("Api-Key", apiKey);
            req.setHeader("Context-Id", contextId);

            log:printInfo("Calling ecomm-frontend to process order-signal for : " + orderNo + 
                            ". Payload : " + jsonPayload.toString());

            var response = ecommFrontendOrderSignalAPIEndpoint->post("/", req);

            match response {
                http:Response resp => {

                    int httpCode = resp.statusCode;
                    if (httpCode == 201) {
                        log:printInfo("Successfully processed order-signal for : " + orderNo + " to ecomm-frontend");
                        updateProcessFlag(tid, retryCount, "C", "sent to ecomm-frontend", httpCode, jsonPayload.toString());
                    } else {
                        match resp.getTextPayload() {
                            string payload => {
                                log:printInfo("Failed to process order-signal for : " + orderNo +
                                        " to ecomm-frontend. Error code : " + httpCode + ". Error message : " + payload);
                                updateProcessFlag(tid, retryCount + 1, "E", payload, httpCode, jsonPayload.toString());
                            }
                            error err => {
                                log:printInfo("Failed to process order-signal for : " + orderNo +
                                        " to ecomm-frontend. Error code : " + httpCode);
                                updateProcessFlag(tid, retryCount + 1, "E", err.message, httpCode, jsonPayload.toString());
                            }
                        }
                    }
                }
                error err => {
                    log:printError("Error while calling ecomm-frontend for order-signal for : " + orderNo, err = err);
                    updateProcessFlag(tid, retryCount + 1, "E", err.message, -1, jsonPayload.toString());
                }
            }
        } catch (error err) {
            log:printError("Error while calling ecomm-frontend for order-signal for : " + orderNo, err = err);
            updateProcessFlag(tid, retryCount + 1, "E", err.message, -2, "");
        }
    }
}

function getOrderSignalPayload(model:OrderSignalDAO orderSignal) returns (json) {

    io:StringReader sr = new(orderSignal.request);
    xml? requestOptional = check sr.readXml();
    
    json orderSignalPayload;
    match requestOptional {
        xml request => {

            json[] productLines;
            foreach i, x in request.IDOC.ZECOMMEDK01.selectDescendants("ZECOMMEDP01") {
                json productLineItem = {
                    "lineItemText": x.ZTEXT.getTextValue(),
                    "taxRate": x.ZTAXR.getTextValue(),
                    "productName": x.ZPNAME.getTextValue(),
                    "quantity": math:floor(check <int> x.ZQTY.getTextValue()),
                    "shipmentId": x.ZSHIPID.getTextValue(),
                    "shipmentQuantity": x.ZSHIPQTY.getTextValue(),
                    "promiseDate": x.ZSSD.getTextValue(),
                    "lineItemPosition": x.ZLINENO.getTextValue(),
                    "shippingStatus": x.ZSHIPST.getTextValue(),
                    "shipmentDelayReason": x.ZSPDELAY.getTextValue()
                };
                productLines[i] = productLineItem;
            }

            json[] shipments;
            foreach i, x in request.IDOC.ZECOMMEDK01.selectDescendants("ZECOMMEDK02") {
                json shipment = {
                    "shipmentId": x.ZSHIPID.getTextValue(),
                    "status": {
                        "shippingStatus": x.ZSHIPST.getTextValue()
                    },
                    "shipmentDelayReason": x.ZSPDELAY.getTextValue(),
                    "shippingMethod": x.ZSMETHOD.getTextValue(),
                    "trackingNumber": x.ZTRACKNO.getTextValue(),
                    "carrier": x.ZCARRIER.getTextValue(),
                    "shipmentDate": x.ZSHIPDATE.getTextValue()
                };
                shipments[i] = shipment;
            }

            orderSignalPayload = {
                    "orders":{
                        "order":[
                            {
                                "orderNo": request.IDOC.ZECOMMEDK01.BELNR.getTextValue(),
                                "orderDate": request.IDOC.ZECOMMEDK01.ZDATE.getTextValue(),
                                "originalOrderNo": request.IDOC.ZECOMMEDK01.OBELNR.getTextValue(),
                                "currency": request.IDOC.ZECOMMEDK01.CURCY.getTextValue(),
                                "status":{
                                    "orderStatus": request.IDOC.ZECOMMEDK01.ZORDST.getTextValue(),
                                    "shippingStatus": request.IDOC.ZECOMMEDK01.ZSHIPST.getTextValue()
                                },
                                "MFGOrderNumber": request.IDOC.ZECOMMEDK01.ZMFGSO.getTextValue(),
                                "MFGCustomerNumber": request.IDOC.ZECOMMEDK01.ZMFGCU.getTextValue(),
                                "productLineItems":{
                                    "productLineItem": productLines
                                },                    
                                "shipments":{
                                    "shipment": shipments
                                }
                            }
                        ]
                    }
                };

        }

        () => {}
    }

    return orderSignalPayload;
}

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

function updateProcessFlag(int tid, int retryCount, string processFlag, string errorMessage, int resCode, string reqPayload) {

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
                    // sending email alerts
                    log:printError("Max retry count exeeced. Notifying operations. Tid " + tid);
                    notifyOperation(errorMessage, resCode, reqPayload);
                }
            }
        }
        error err => {
            log:printError("Error while calling orderSignalDataServiceEndpoint", err = err);
        }
    }
}

function notifyOperation(string errorMessage, int httpCode, string reqPayload)  {

    string failedParty;
    string message;
    float intervalSec = interval/1000;
    if (httpCode == -1) {
        failedParty = "Network";
        message = "Ballerina has retried " + maxRetryCount + " times with " + intervalSec + " sec interval, but experiencing a network failure";
    } else if (httpCode == -2) {
        failedParty = "Ballerina";
        message = "Ballerina has retried " + maxRetryCount + " times with " + intervalSec + " sec interval, but experiencing a mediation failure";
    } else {
        failedParty = "EF";
        message = "Ballerina has retried " + maxRetryCount + " times with " + intervalSec + " sec interval, but EF is responding with an error";
    }

    json notificationPayload = {
        "parties": ["BQ","EF","Ballerina","Network"],
        "recipient": config:getAsString("order_signal.outbound.notification.recipient"),
        "cc": config:getAsString("order_signal.outbound.notification.cc"),
        "failedParty" : failedParty,
        "subject": "Failed to submit order to EF",
        "message": message,
        "targetResponse": {
                "party": "EF",
                "sc": httpCode,
                "payload": errorMessage
            },
            "sourceRequest": {
                "party": "Ballerina",
                "payload": reqPayload
            }
    };
    http:Request req = new;

    req.setJsonPayload(untaint notificationPayload);

    var response = notificationServiceEndpoint->post("/email", req);
    io:println(response);
}

function handleError(error e) {
    log:printError("Error in processing order-signals to ecomm-frontend", err = e);
    // I don't want to stop the ETL if backend is down
    // timer.stop();
}