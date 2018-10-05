import wso2/ftp;
import ballerina/io;
import ballerina/config;
import ballerina/log;
import ballerina/mb;
import ballerina/http;

endpoint ftp:Client orderSignalSFTPClient {
    protocol: ftp:SFTP,
    host: config:getAsString("ecomm_backend.order_signal.sftp.host"),
    port: config:getAsInt("ecomm_backend.order_signal.sftp.port"),
    secureSocket: {
        basicAuth: {
            username: config:getAsString("ecomm_backend.order_signal.sftp.username"),
            password: config:getAsString("ecomm_backend.order_signal.sftp.password")
        }
    }
};

endpoint http:Client orderSignalDataEndpoint {
    url: config:getAsString("order_signal.data.service.url")
};

endpoint mb:SimpleQueueReceiver orderSignalInboundQueue {
    host: config:getAsString("order_signal.mb.host"),
    port: config:getAsInt("order_signal.mb.port"),
    queueName: config:getAsString("order_signal.mb.queueName")
};

service<mb:Consumer> orderSignalInboundQueueReceiver bind orderSignalInboundQueue {

    onMessage(endpoint consumer, mb:Message message) {
        match (message.getTextMessageContent()) {           
            string path => {
                log:printInfo("New order-signal received from " + 
                                config:getAsString("order_signal.mb.queueName") + " queue." + path);
                // boolean success = handleRefund(path);

                // if (success) {
                //     archiveCompletedRefund(path);
                // } else {
                //     archiveErroredRefund(path);
                // }
            }
            error e => {
                log:printError("Error occurred while reading message from " 
                                + config:getAsString("order_signal.mb.queueName") + " queue.", err = e);
            }
        }
    }
}

// function handleRefund(string path) returns boolean {

//     boolean success = false;
//     var refundOrError = refundSFTPClient -> get(path);
//     match refundOrError {

//         io:ByteChannel channel => {
//             io:CharacterChannel characters = new(channel, "utf-8");
//             xml refundXml = check characters.readXml();
//             _ = channel.close();

//             json refunds = generateRefundsJson(refundXml);

//             http:Request req = new;
//             req.setJsonPayload(untaint refunds);
//             var response = refundDataEndpoint->post("/batch/", req);

//             match response {
//                 http:Response resp => {
//                     match resp.getJsonPayload() {
//                         json j => {
//                             log:printInfo("Response from refundDataEndpoint : " + j.toString());
//                             success = true;
//                         }
//                         error err => {
//                             log:printError("Response from refundDataEndpoint is not a json : " + err.message, err = err);
//                         }
//                     }
//                 }
//                 error err => {
//                     log:printError("Error while calling refundDataEndpoint : " + err.message, err = err);
//                 }
//             }
//         }

//         error err => {
//             log:printError("Error while reading files from refundSFTPClient : " + err.message, err = err);
//         }
//     }

//     return success;
// }

// function generateRefundsJson(xml refundXml) returns json {

//     json refunds;
//     foreach i, x in refundXml.selectDescendants("ZECOMMCREDITMEMO") { 
//         json refundJson = {
//             "orderNo" : x.selectDescendants("ZBLCORD").getTextValue(),
//             "kind" : x.selectDescendants("ZCMTYPE").getTextValue(),
//             "invoiceId" : x.selectDescendants("AUBEL").getTextValue(),
//             "settlementId" : x.selectDescendants("ZOSETTID").getTextValue(),
//             "creditMemoId" : x.selectDescendants("ZCMNO").getTextValue(),
//             "itemIds" : x.selectDescendants("ZBLCITEM").getTextValue(),
//             "countryCode" : x.selectDescendants("LAND1").getTextValue(),
//             "request" : <string> x,
//             "processFlag" : "N",
//             "retryCount" : 0,
//             "errorMessage":"None"
//         };
//         refunds.refunds[i] = refundJson;
//     }
    
//     return refunds;
// }

// function archiveCompletedRefund(string  path) {
//     string archivePath = config:getAsString("ecomm_backend.refund.sftp.path") + "/archive/" + getFileName(path);
//     _ = refundSFTPClient -> rename(path, archivePath);
//     io:println("Archived refund path : ", archivePath);
// }

// function archiveErroredRefund(string path) {
//     string erroredPath = config:getAsString("ecomm_backend.refund.sftp.path") + "/error/" + getFileName(path);
//     _ = refundSFTPClient -> rename(path, erroredPath);
//     io:println("Errored refund path : ", erroredPath);
// }

// function getFileName(string path) returns string {
//     string[] tmp = path.split("/");
//     int size = lengthof tmp;
//     return tmp[size-1];
// }