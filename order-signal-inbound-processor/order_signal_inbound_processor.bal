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
                
                boolean success = handleOrderSignal(path);

                if (success) {
                    archiveCompletedRefund(path);
                } else {
                    archiveErroredRefund(path);
                }
            }
            error e => {
                log:printError("Error occurred while reading message from " 
                                + config:getAsString("order_signal.mb.queueName") + " queue.", err = e);
            }
        }
    }
}

function handleOrderSignal(string path) returns boolean {

    boolean success = false;
    var ret = orderSignalSFTPClient -> get(path);

    match ret {
        io:ByteChannel channel => {
            io:CharacterChannel characters = new(channel, "utf-8");
            xml orderSignalXml = check characters.readXml();
            _ = channel.close();

            json orderSignals = generateOrderSignalJson(orderSignalXml);

            io:println(orderSignals);

            http:Request req = new;
            req.setJsonPayload(untaint orderSignals);
            var response = orderSignalDataEndpoint->post("/", req);

            match response {
                http:Response resp => {
                    match resp.getJsonPayload() {
                        json j => {
                            log:printInfo("Response from orderSignalDataEndpoint : " + j.toString());
                            success = true;
                        }
                        error err => {
                            log:printError("Response from orderSignalDataEndpoint is not a json : " + err.message, err = err);
                        }
                    }
                }
                error err => {
                    log:printError("Error while calling orderSignalDataEndpoint : " + err.message, err = err);
                }
            }
        }

        error err => {
            log:printError("Error while reading files from orderSignalSFTPClient : " + err.message, err = err);
        }
    }

    return success;
}

function generateOrderSignalJson(xml orderSignalXml) returns json {

    json orderSignalPayload = {
        "context" : orderSignalXml.IDOC.ZECOMMEDK01.ZCONID.getTextValue(),
        "signal" : orderSignalXml.IDOC.ZECOMMEDK01.ZSHIPST.getTextValue(),
        "orderNo" : orderSignalXml.IDOC.ZECOMMEDK01.BELNR.getTextValue(),
        "partnerId" : orderSignalXml.IDOC.EDI_DC40.DOCNUM.getTextValue(),
        "request" : <string> orderSignalXml,
        "processFlag" : "N",
        "retryCount" : 0,
        "errorMessage" : "None"
    };

    return orderSignalPayload;
}

function archiveCompletedRefund(string  path) {
    string archivePath = config:getAsString("ecomm_backend.order_signal.sftp.path") + "/archive/" + getFileName(path);
    _ = orderSignalSFTPClient -> rename(path, archivePath);
    io:println("Archived order-signal path : ", archivePath);
}

function archiveErroredRefund(string path) {
    string erroredPath = config:getAsString("ecomm_backend.order_signal.sftp.path") + "/error/" + getFileName(path);
    _ = orderSignalSFTPClient -> rename(path, erroredPath);
    io:println("Errored order-signal path : ", erroredPath);
}

function getFileName(string path) returns string {
    string[] tmp = path.split("/");
    int size = lengthof tmp;
    return tmp[size-1];
}