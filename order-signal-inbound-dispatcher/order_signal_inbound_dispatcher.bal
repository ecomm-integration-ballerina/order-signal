import wso2/ftp;
import ballerina/io;
import ballerina/config;
import ballerina/mb;
import ballerina/log;

endpoint ftp:Listener orderSignalSFTPListener {
    protocol: ftp:SFTP,
    host: config:getAsString("ecomm_backend.order_signal.sftp.host"),
    port: config:getAsInt("ecomm_backend.order_signal.sftp.port"),
    secureSocket: {
        basicAuth: {
            username: config:getAsString("ecomm_backend.order_signal.sftp.username"),
            password: config:getAsString("ecomm_backend.order_signal.sftp.password")
        }
    },
    path:config:getAsString("ecomm_backend.order_signal.sftp.path") + "/original"
};

endpoint mb:SimpleQueueSender orderSignalInboundQueue {
    host: config:getAsString("order_signal.mb.host"),
    port: config:getAsInt("order_signal.mb.port"),
    queueName: config:getAsString("order_signal.mb.queueName")
};

service orderSignalMonitor bind orderSignalSFTPListener {

    fileResource (ftp:WatchEvent m) {

        foreach v in m.addedFiles {
            log:printInfo("New order-signal received, inserting into " 
                            + config:getAsString("order_signal.mb.queueName") + " queue : " + v.path);
            handleorderSignal(v.path);
        }

        foreach v in m.deletedFiles {
            // ignore
        }
    }
}

function handleorderSignal(string path) {
    match (orderSignalInboundQueue.createTextMessage(path)) {
        error e => {
            log:printError("Error occurred while creating order-signal message for : " + path, err = e);
        }
        mb:Message msg => {
            orderSignalInboundQueue->send(msg) but {
                error e => log:printError("Error occurred while sending message to "
                    + config:getAsString("order_signal.mb.queueName") + " queue : " + path, err = e)
            };
        }
    }
}